-- ============================================================
-- model_feature_extractor.lua — 本地模型特征提取
-- 为未来的 sidecar 推理和本地埋点生成稳定的上下文快照
-- ============================================================

local utils = require("utils")
local detector = require("context_detector")

local M = {}

local function trim_text(text, max_chars)
    local normalized = utils.trim(text or "")
    if normalized == "" then
        return ""
    end
    return utils.utf8_sub(normalized, max_chars or 80)
end

local function clone_options(options)
    local result = {}
    for key, value in pairs(options or {}) do
        result[key] = value
    end
    return result
end

local function last_visible_char(last_commit_text, recent_committed)
    local char = utils.utf8_last_char(last_commit_text or "")
    if char and char ~= "" then
        return char
    end
    return utils.utf8_last_char(recent_committed or "")
end

function M.build_context_snapshot(args)
    args = args or {}

    local recent_committed = trim_text(args.recent_committed, args.text_limit or 80)
    local last_commit_text = trim_text(args.last_commit_text, args.text_limit or 40)
    local current_input = trim_text(args.current_input, args.input_limit or 32)
    local snapshot_text = recent_committed ~= "" and recent_committed or last_commit_text
    local protected, reason = detector.is_protected(recent_committed, current_input)
    local last_char = last_visible_char(last_commit_text, recent_committed)

    return {
        app_id = args.app_id or "",
        recent_committed = recent_committed,
        last_commit_text = last_commit_text,
        current_input = current_input,
        target_punct = args.target_punct or "",
        protected = protected,
        protected_reason = reason,
        language_context = detector.detect_language_context(snapshot_text),
        last_token_type = detector.classify_token(last_commit_text),
        prev_char_type = detector.get_prev_char_type(last_char),
        options = clone_options(args.options),
    }
end

function M.build_context_request(args)
    args = args or {}
    local snapshot = M.build_context_snapshot(args)
    return {
        request_id = args.request_id or "",
        mode = args.mode or "context_score",
        app_id = snapshot.app_id,
        recent_committed = snapshot.recent_committed,
        last_commit_text = snapshot.last_commit_text,
        current_input = snapshot.current_input,
        target_punct = snapshot.target_punct,
        options = snapshot.options,
    }
end

function M.build_commit_observation(args)
    args = args or {}
    return {
        request_id = args.request_id or "",
        source = args.source or "normal",
        committed_text = trim_text(args.committed_text, args.text_limit or 40),
        snapshot = M.build_context_snapshot(args),
    }
end

function M.build_punctuation_observation(args)
    args = args or {}
    return {
        request_id = args.request_id or "",
        input_punct = args.input_punct or "",
        output_text = args.output_text or "",
        decision_source = args.decision_source or "rules",
        used_model = args.used_model == true,
        snapshot = M.build_context_snapshot(args),
    }
end

function M.build_candidate_rerank_request(args)
    args = args or {}
    return {
        request_id = args.request_id or "",
        mode = "candidate_rerank",
        app_id = args.app_id or "",
        recent_committed = trim_text(args.recent_committed, args.text_limit or 80),
        last_commit_text = trim_text(args.last_commit_text, args.text_limit or 40),
        current_input = trim_text(args.current_input, args.input_limit or 32),
        options = clone_options(args.options),
        candidates = args.candidates or {},
    }
end

function M.summarize_candidates(candidates, limit)
    local summarized = {}
    local max_items = limit or 5

    for index, candidate in ipairs(candidates or {}) do
        if index > max_items then
            break
        end
        summarized[#summarized + 1] = {
            text = trim_text(candidate.text, 32),
            comment = trim_text(candidate.comment, 16),
            quality = candidate.quality or 0,
            type = candidate.type or "",
        }
    end

    return summarized
end

return M
