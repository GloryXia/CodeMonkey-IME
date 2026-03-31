-- ============================================================
-- model_bridge.lua — 本地模型桥接层
-- 当前阶段只做特征构造、日志埋点和安全回退
-- ============================================================

local feature_extractor = require("model_feature_extractor")
local cache = require("model_cache")
local logger = require("model_logger")
local sidecar_client = require("model_sidecar_client")

local M = {}

local DEFAULT_CONFIG = {
    mode = "log_only",
    endpoint = "http://127.0.0.1:39571/score_context",
    timeout_ms = 200,
    cache_ttl_ms = 800,
}

local function copy_table(input)
    local output = {}
    for key, value in pairs(input or {}) do
        output[key] = value
    end
    return output
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parse_bool(value)
    local normalized = trim(value):lower()
    return normalized == "1"
        or normalized == "true"
        or normalized == "yes"
        or normalized == "on"
end

local function read_local_config()
    local home = os.getenv("HOME")
    if not home or home == "" then
        return {}
    end

    local path = home .. "/Library/Rime/hybrid_ime_model.conf"
    local file = io.open(path, "r")
    if not file then
        return {}
    end

    local config = {}
    for line in file:lines() do
        local stripped = trim(line)
        if stripped ~= "" and stripped:sub(1, 1) ~= "#" then
            local key, value = stripped:match("^([%w_]+)%s*=%s*(.+)$")
            if key and value then
                config[key] = trim(value)
            end
        end
    end
    file:close()

    local merged = {}
    if config.enabled ~= nil then
        merged.mode = parse_bool(config.enabled) and "sidecar" or "log_only"
    end
    if config.endpoint and config.endpoint ~= "" then
        merged.endpoint = config.endpoint
    end
    if config.timeout_ms then
        merged.timeout_ms = tonumber(config.timeout_ms) or DEFAULT_CONFIG.timeout_ms
    end
    if config.cache_ttl_ms then
        merged.cache_ttl_ms = tonumber(config.cache_ttl_ms) or DEFAULT_CONFIG.cache_ttl_ms
    end
    return merged
end

local function resolve_config(env)
    local merged = copy_table(DEFAULT_CONFIG)
    local file_config = read_local_config()
    local runtime_config = env.model_bridge_config or {}

    for _, source in ipairs({ file_config, runtime_config }) do
        for key, value in pairs(source) do
            merged[key] = value
        end
    end

    if merged.enabled ~= nil then
        merged.mode = merged.enabled and "sidecar" or "log_only"
    end

    return merged
end

local function ensure_state(env)
    env.model_bridge_state = env.model_bridge_state or {
        sequence = 0,
        cache = cache.new(),
        config = resolve_config(env),
    }
    return env.model_bridge_state
end

local function get_context(env)
    return env.engine and env.engine.context or nil
end

local function get_option_snapshot(context)
    local options = {}
    if not context or not context.get_option then
        return options
    end

    for _, name in ipairs({ "hybrid_mode", "auto_punct", "auto_space", "ascii_mode" }) do
        local ok, value = pcall(function()
            return context:get_option(name)
        end)
        if ok then
            options[name] = value
        end
    end

    return options
end

local function next_request_id(env, prefix)
    local state = ensure_state(env)
    state.sequence = state.sequence + 1
    return string.format("%s-%d-%d", prefix or "req", os.time(), state.sequence)
end

local function snapshot_args(env, extra)
    extra = extra or {}
    local context = get_context(env)
    local hybrid_state = env.hybrid_state or {}

    return {
        app_id = extra.app_id or hybrid_state.current_app or "",
        recent_committed = extra.recent_committed or hybrid_state.recent_committed or env.recent_committed or "",
        last_commit_text = extra.last_commit_text or hybrid_state.last_committed_text or env.last_committed_text or "",
        current_input = extra.current_input or (context and context.input) or "",
        target_punct = extra.target_punct or "",
        options = extra.options or get_option_snapshot(context),
    }
end

local function append_event(sink, event)
    local ok = pcall(function()
        sink.append_event(event)
    end)
    return ok
end

local function build_cache_key(request)
    return logger.encode_json({
        app_id = request.app_id,
        candidates = request.candidates,
        current_input = request.current_input,
        target_punct = request.target_punct,
        last_commit_text = request.last_commit_text,
        mode = request.mode,
        options = request.options,
        recent_committed = request.recent_committed,
    })
end

local function append_bridge_event(sink, event)
    append_event(sink, event)
end

local function fallback_result(source)
    return {
        available = false,
        source = source or "log_only",
        confidence = 0,
        context = "rules",
        scores = {},
    }
end

local function normalize_sidecar_result(response)
    if type(response) ~= "table" then
        return nil, "invalid_response"
    end

    return {
        available = true,
        source = response.source or "sidecar",
        confidence = tonumber(response.confidence) or 0,
        context = response.context or "unknown",
        scores = type(response.scores) == "table" and response.scores or {},
        ttl_ms = tonumber(response.ttl_ms) or DEFAULT_CONFIG.cache_ttl_ms,
    }
end

local function normalize_rerank_result(response)
    if type(response) ~= "table" then
        return nil, "invalid_response"
    end

    return {
        available = true,
        source = response.source or "sidecar",
        confidence = tonumber(response.confidence) or 0,
        ranked_scores = type(response.ranked_scores) == "table" and response.ranked_scores or {},
        ttl_ms = tonumber(response.ttl_ms) or DEFAULT_CONFIG.cache_ttl_ms,
    }
end

function M.init(env)
    local state = ensure_state(env)
    state.config = resolve_config(env)
end

function M.capture_snapshot(env, extra)
    return feature_extractor.build_context_snapshot(snapshot_args(env, extra))
end

function M.score_context(env, extra)
    M.init(env)

    extra = extra or {}
    local state = ensure_state(env)
    local sink = extra.logger or logger
    local args = snapshot_args(env, extra)
    local request = feature_extractor.build_context_request({
        request_id = extra.request_id or next_request_id(env, "ctx"),
        mode = extra.mode or "context_score",
        app_id = args.app_id,
        recent_committed = args.recent_committed,
        last_commit_text = args.last_commit_text,
        current_input = args.current_input,
        target_punct = args.target_punct,
        options = args.options,
    })

    append_event(sink, {
        event = "context_score_requested",
        request = request,
    })

    if state.config.mode ~= "sidecar" then
        return fallback_result("log_only")
    end

    local cache_key = build_cache_key(request)
    local cached = cache.get(state.cache, cache_key)
    if cached then
        append_bridge_event(sink, {
            event = "context_score_cache_hit",
            request_id = request.request_id,
            source = cached.source,
        })
        return cached
    end

    local response, err = sidecar_client.request(request, {
        endpoint = state.config.endpoint,
        timeout_ms = state.config.timeout_ms,
        transport = state.config.transport,
    })
    if not response then
        append_bridge_event(sink, {
            event = "context_score_failed",
            request_id = request.request_id,
            reason = err or "sidecar_failed",
        })
        return fallback_result("sidecar_fallback")
    end

    local normalized, normalize_err = normalize_sidecar_result(response)
    if not normalized then
        append_bridge_event(sink, {
            event = "context_score_failed",
            request_id = request.request_id,
            reason = normalize_err or "invalid_response",
        })
        return fallback_result("sidecar_fallback")
    end

    cache.put(state.cache, cache_key, normalized, normalized.ttl_ms or state.config.cache_ttl_ms)
    append_bridge_event(sink, {
        event = "context_score_resolved",
        request_id = request.request_id,
        response = {
            confidence = normalized.confidence,
            context = normalized.context,
            scores = normalized.scores,
            source = normalized.source,
            ttl_ms = normalized.ttl_ms,
        },
    })

    return normalized
end

function M.record_commit(env, extra)
    M.init(env)

    extra = extra or {}
    local sink = extra.logger or logger
    local args = snapshot_args(env, {
        app_id = extra.app_id,
        recent_committed = extra.recent_committed,
        last_commit_text = extra.text,
        current_input = extra.current_input,
        options = extra.options,
    })

    append_event(sink, {
        event = "commit_observed",
        payload = feature_extractor.build_commit_observation({
            request_id = extra.request_id or next_request_id(env, "commit"),
            app_id = args.app_id,
            recent_committed = args.recent_committed,
            last_commit_text = args.last_commit_text,
            current_input = args.current_input,
            options = args.options,
            committed_text = extra.text or "",
            source = extra.source or "normal",
        }),
    })
end

function M.rerank_candidates(env, extra)
    M.init(env)

    extra = extra or {}
    local state = ensure_state(env)
    local sink = extra.logger or logger
    local args = snapshot_args(env, extra)
    local request = feature_extractor.build_candidate_rerank_request({
        request_id = extra.request_id or next_request_id(env, "rerank"),
        app_id = args.app_id,
        recent_committed = args.recent_committed,
        last_commit_text = args.last_commit_text,
        current_input = args.current_input,
        options = args.options,
        candidates = extra.candidates or {},
    })

    append_event(sink, {
        event = "candidate_rerank_requested",
        request = request,
    })

    if state.config.mode ~= "sidecar" then
        return {
            available = false,
            source = "log_only",
            confidence = 0,
            ranked_scores = {},
        }
    end

    local cache_key = build_cache_key(request)
    local cached = cache.get(state.cache, cache_key)
    if cached then
        append_bridge_event(sink, {
            event = "candidate_rerank_cache_hit",
            request_id = request.request_id,
            source = cached.source,
        })
        return cached
    end

    local response, err = sidecar_client.request(request, {
        endpoint = state.config.endpoint,
        timeout_ms = state.config.timeout_ms,
        transport = state.config.transport,
    })
    if not response then
        append_bridge_event(sink, {
            event = "candidate_rerank_failed",
            request_id = request.request_id,
            reason = err or "sidecar_failed",
        })
        return {
            available = false,
            source = "sidecar_fallback",
            confidence = 0,
            ranked_scores = {},
        }
    end

    local normalized, normalize_err = normalize_rerank_result(response)
    if not normalized then
        append_bridge_event(sink, {
            event = "candidate_rerank_failed",
            request_id = request.request_id,
            reason = normalize_err or "invalid_response",
        })
        return {
            available = false,
            source = "sidecar_fallback",
            confidence = 0,
            ranked_scores = {},
        }
    end

    cache.put(state.cache, cache_key, normalized, normalized.ttl_ms or state.config.cache_ttl_ms)
    append_bridge_event(sink, {
        event = "candidate_rerank_resolved",
        request_id = request.request_id,
        response = {
            confidence = normalized.confidence,
            ranked_scores = normalized.ranked_scores,
            source = normalized.source,
            ttl_ms = normalized.ttl_ms,
        },
    })

    return normalized
end

function M.record_punctuation_decision(env, extra)
    M.init(env)

    extra = extra or {}
    local sink = extra.logger or logger
    local args = snapshot_args(env, {
        app_id = extra.app_id,
        recent_committed = extra.recent_committed,
        last_commit_text = extra.last_commit_text,
        current_input = extra.current_input,
        options = extra.options,
    })

    append_event(sink, {
        event = "punctuation_decided",
        payload = feature_extractor.build_punctuation_observation({
            request_id = extra.request_id or next_request_id(env, "punct"),
            app_id = args.app_id,
            recent_committed = args.recent_committed,
            last_commit_text = args.last_commit_text,
            current_input = args.current_input,
            options = args.options,
            input_punct = extra.input_punct,
            output_text = extra.output_text,
            decision_source = extra.decision_source or "rules",
            used_model = extra.used_model == true,
        }),
    })
end

return M
