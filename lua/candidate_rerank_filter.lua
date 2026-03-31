-- ============================================================
-- candidate_rerank_filter.lua — Phase 2 保守版候选重排
-- 只在高置信度场景下重排前几个候选，其余保持原顺序
-- ============================================================

local utils = require("utils")
local detector = require("context_detector")
local model_bridge = require("model_bridge")

local TOP_N = 6
local MIN_CONFIDENCE = 0.82
local MIN_SCORE_GAP = 0.08

local function wrap_candidate(cand)
    if ShadowCandidate then
        return ShadowCandidate(cand, cand.type, cand.text, cand.comment)
    end

    local wrapped = Candidate(
        cand.type,
        cand.start,
        cand._end,
        cand.text,
        cand.comment
    )
    if wrapped and cand.quality ~= nil then
        wrapped.quality = cand.quality
    end
    return wrapped or cand
end

local function latest_commit_text(context)
    if not context then
        return ""
    end

    local commit_text = context:get_commit_text() or ""
    if commit_text ~= "" then
        return commit_text
    end

    local history = context.commit_history
    if history and history.latest_text then
        local ok, text = pcall(function()
            return history:latest_text()
        end)
        if ok and text and text ~= "" then
            return text
        end
    end

    return ""
end

local function classify_candidate_type(text)
    local has_zh = false
    local has_en = false

    for char in utils.utf8_chars(text or "") do
        if utils.is_chinese_char(char) then
            has_zh = true
        elseif utils.is_ascii_letter(char) then
            has_en = true
        end
    end

    local token_type = detector.classify_token(text or "")
    if token_type == detector.TOKEN_TECH_TERM
        or token_type == detector.TOKEN_CODE
        or token_type == detector.TOKEN_COMMAND
        or token_type == detector.TOKEN_MIXED then
        return "tech"
    end

    if has_zh and has_en then
        return "mixed"
    end
    if has_en then
        return "en"
    end
    if has_zh then
        return "zh"
    end
    return "other"
end

local function should_attempt_rerank(env, candidates, current_input)
    if not current_input or current_input == "" then
        return false, false
    end

    local context = env.engine and env.engine.context
    if context and context:is_composing() ~= true then
        return false, false
    end

    local has_zh = false
    local has_en_or_tech = false
    for index = 1, math.min(#candidates, TOP_N) do
        local cand_type = classify_candidate_type(candidates[index].text)
        if cand_type == "zh" then
            has_zh = true
        elseif cand_type == "en" or cand_type == "tech" or cand_type == "mixed" then
            has_en_or_tech = true
        end
    end

    if has_zh and has_en_or_tech then
        return true, false
    end

    -- 保守召回：只在可见前缀全是中文时，允许从更深位置召回一个
    -- 与当前输入完全匹配的英文/技术候选。
    if not has_zh then
        return false, false
    end

    local lowered_input = string.lower(current_input)
    for index = TOP_N + 1, #candidates do
        local cand = candidates[index]
        local cand_type = classify_candidate_type(cand.text)
        if (cand_type == "en" or cand_type == "tech" or cand_type == "mixed")
            and string.lower(cand.text or "") == lowered_input then
            return true, true
        end
    end

    return false, false
end

local function summarize_candidates(candidates)
    local summarized = {}
    for _, item in ipairs(candidates or {}) do
        local cand = item.candidate or item
        summarized[#summarized + 1] = {
            id = tostring(item.id or summarized[#summarized + 1]),
            text = cand.text or "",
            comment = cand.comment or "",
            quality = cand.quality or 0,
            type = classify_candidate_type(cand.text or ""),
        }
    end
    return summarized
end

local function build_sorted_prefix(prefix, ranked_scores)
    local score_map = {}
    for _, item in ipairs(ranked_scores or {}) do
        score_map[tostring(item.id)] = tonumber(item.score) or 0
    end

    local decorated = {}
    for _, item in ipairs(prefix) do
        local cand = item.candidate or item
        local id = tostring(item.id or item.original_index or "")
        decorated[#decorated + 1] = {
            candidate = cand,
            id = id,
            score = score_map[id] or (cand.quality or 0),
            original_index = item.original_index or tonumber(id) or 0,
        }
    end

    table.sort(decorated, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.original_index < b.original_index
    end)

    return decorated, score_map
end

local function build_rerank_pool(candidates, current_input, allow_recall)
    local pool = {}
    local seen_indices = {}

    for index = 1, math.min(#candidates, TOP_N) do
        pool[#pool + 1] = {
            id = index,
            original_index = index,
            candidate = candidates[index],
        }
        seen_indices[index] = true
    end

    if not allow_recall then
        return pool
    end

    local lowered_input = string.lower(current_input or "")
    for index = TOP_N + 1, #candidates do
        local cand = candidates[index]
        local cand_type = classify_candidate_type(cand.text)
        if not seen_indices[index]
            and (cand_type == "en" or cand_type == "tech" or cand_type == "mixed")
            and string.lower(cand.text or "") == lowered_input then
            pool[#pool + 1] = {
                id = index,
                original_index = index,
                candidate = cand,
            }
            break
        end
    end

    return pool
end

local function should_apply_reorder(original_prefix, decorated, score_map, confidence)
    if not decorated or #decorated < 2 then
        return false
    end

    if (tonumber(confidence) or 0) < MIN_CONFIDENCE then
        return false
    end

    local top_id = decorated[1].id
    if top_id == "1" then
        return false
    end

    local top_score = decorated[1].score or 0
    local original_score = score_map["1"] or (original_prefix[1].quality or 0)
    return (top_score - original_score) >= MIN_SCORE_GAP
end

local function init(env)
    model_bridge.init(env)
end

local function filter(input, env)
    local context = env.engine and env.engine.context
    local hybrid_on = true
    if context then
        local opt = context:get_option("hybrid_mode")
        if opt == false then
            hybrid_on = false
        end
    end

    local candidates = {}
    for cand in input:iter() do
        candidates[#candidates + 1] = cand
    end

    if not hybrid_on or #candidates < 2 then
        for _, cand in ipairs(candidates) do
            yield(wrap_candidate(cand))
        end
        return
    end

    local current_input = context and context.input or ""
    local should_rerank, allow_recall = should_attempt_rerank(env, candidates, current_input)
    if not should_rerank then
        for _, cand in ipairs(candidates) do
            yield(wrap_candidate(cand))
        end
        return
    end

    local last_commit_text = latest_commit_text(context)
    local recent_committed = last_commit_text
    if recent_committed == "" then
        recent_committed = current_input
    end

    local prefix = {}
    for index = 1, math.min(#candidates, TOP_N) do
        prefix[#prefix + 1] = candidates[index]
    end
    local rerank_pool = build_rerank_pool(candidates, current_input, allow_recall)

    local rerank_result = model_bridge.rerank_candidates(env, {
        recent_committed = recent_committed,
        last_commit_text = last_commit_text,
        current_input = current_input,
        candidates = summarize_candidates(rerank_pool),
    })

    if not rerank_result.available then
        for _, cand in ipairs(candidates) do
            yield(wrap_candidate(cand))
        end
        return
    end

    local decorated, score_map = build_sorted_prefix(rerank_pool, rerank_result.ranked_scores)
    if not should_apply_reorder(prefix, decorated, score_map, rerank_result.confidence) then
        for _, cand in ipairs(candidates) do
            yield(wrap_candidate(cand))
        end
        return
    end

    local yielded = {}
    local consumed = {}
    for _, item in ipairs(decorated) do
        if #yielded < TOP_N then
            yielded[#yielded + 1] = item.candidate
            consumed[item.original_index] = true
        end
    end
    for index = 1, #candidates do
        if not consumed[index] then
            yielded[#yielded + 1] = candidates[index]
        end
    end

    for index = 1, #yielded do
        local cand = yielded[index]
        if cand then
            yield(wrap_candidate(cand))
        end
    end
end

local function fini(env)
end

return { init = init, func = filter, fini = fini }
