-- ============================================================
-- hybrid_filter.lua — 混合候选重排 Filter
-- 根据上下文类型对候选列表进行智能重排
-- ============================================================

local utils = require("utils")
local detector = require("context_detector")

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

local function record_commit(env, text)
    if not text or text == "" then
        return
    end

    env.filter_state.last_synced_commit_text = text
    env.filter_state.recent_committed =
        ((env.filter_state.recent_committed or "") .. text)
    if #env.filter_state.recent_committed > 200 then
        env.filter_state.recent_committed = env.filter_state.recent_committed:sub(-200)
    end
end

local function sync_commit_state(env, context)
    local text = latest_commit_text(context)
    if text ~= "" and text ~= env.filter_state.last_synced_commit_text then
        record_commit(env, text)
    end
    return text
end

-- ============================================================
-- 初始化
-- ============================================================

local function init(env)
    env.filter_state = {
        recent_committed = "",
        last_synced_commit_text = nil,
    }

    local context = env.engine and env.engine.context
    if context and context.commit_notifier and context.commit_notifier.connect then
        env.commit_notifier = context.commit_notifier:connect(function(ctx)
            sync_commit_state(env, ctx)
        end)
    end
end

--- 包装候选而不丢失原始候选的元数据。
--- 在 Rime filter 中优先使用 ShadowCandidate，避免把候选降级成 SimpleCandidate。
--- @param cand userdata
--- @param text string|nil
--- @param comment string|nil
--- @return userdata
local function wrap_candidate(cand, text, comment)
    local new_text = text or cand.text
    local new_comment = comment
    if new_comment == nil then
        new_comment = cand.comment
    end

    if ShadowCandidate then
        return ShadowCandidate(cand, cand.type, new_text, new_comment)
    end

    local new_cand = Candidate(
        cand.type,
        cand.start,
        cand._end,
        new_text,
        new_comment
    )
    if new_cand and cand.quality ~= nil then
        new_cand.quality = cand.quality
    end
    return new_cand
end

-- ============================================================
-- 候选评分
-- ============================================================

--- 为候选计算上下文相关的加权分数
--- @param cand userdata Rime 候选对象
--- @param lang_context string 当前语言上下文 "chinese"|"english"|"mixed"
--- @param input string 当前输入
--- @return number score_bonus 加分值
local function compute_score_bonus(cand, lang_context, input)
    local text = cand.text
    local bonus = 0

    if not text or text == "" then return 0 end

    -- 分析候选内容
    local is_pure_zh = true
    local is_pure_en = true
    local has_zh = false
    local has_en = false

    for c in utils.utf8_chars(text) do
        if utils.is_chinese_char(c) then
            has_zh = true
            is_pure_en = false
        elseif utils.is_ascii_letter(c) then
            has_en = true
            is_pure_zh = false
        elseif not utils.is_whitespace(c) and not utils.is_digit(c) then
            is_pure_zh = false
            is_pure_en = false
        end
    end

    -- 技术术语检测
    local lower_text = text:lower()
    local token_type = detector.classify_token(text)
    local is_tech = (token_type == detector.TOKEN_TECH_TERM)

    -- ========================================
    -- 评分规则
    -- ========================================

    if lang_context == "chinese" then
        -- 中文语境：中文候选优先
        if is_pure_zh then
            bonus = bonus + 10
        end
        -- 技术术语在中文语境中应明显靠前，
        -- 但不能压过普通中文拼音候选。
        if is_tech then
            bonus = bonus + 8
        end
        -- 纯英文在中文语境下降权
        if is_pure_en and not is_tech then
            bonus = bonus - 5
        end
    elseif lang_context == "english" then
        -- 英文语境：英文候选优先
        if is_pure_en then
            bonus = bonus + 10
        end
        if is_tech then
            bonus = bonus + 8
        end
        if is_pure_zh then
            bonus = bonus - 5
        end
    else
        -- mixed: 技术术语优先，其他按原权重
        if is_tech then
            bonus = bonus + 8
        end
    end

    -- 候选长度与输入长度匹配加分
    local input_len = #(input or "")
    local text_ascii_len = 0
    for c in utils.utf8_chars(text) do
        if utils.is_ascii_letter(c) then
            text_ascii_len = text_ascii_len + 1
        end
    end
    if is_pure_en and text_ascii_len == input_len then
        bonus = bonus + 3  -- 完全匹配加分
    end

    return bonus
end

-- ============================================================
-- Filter 主逻辑
-- ============================================================

local function filter(input, env)
    -- 检查开关
    local context = env.engine.context
    local hybrid_on = true
    if context then
        local opt = context:get_option("hybrid_mode")
        if opt == false then
            hybrid_on = false
        end
    end

    -- 如果混合模式关闭，原样输出
    if not hybrid_on then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    -- 获取当前语言上下文
    if context then
        sync_commit_state(env, context)
    end
    local recent = env.filter_state.recent_committed or ""

    local lang_context = detector.detect_language_context(recent)
    local current_input = context and context.input or ""

    -- 收集所有候选并评分
    local candidates = {}
    for cand in input:iter() do
        local bonus = compute_score_bonus(cand, lang_context, current_input)
        table.insert(candidates, {
            candidate = cand,
            bonus = bonus,
            original_index = #candidates + 1,
        })
    end

    -- 按 (quality + bonus) 降序排列，保持稳定排序
    table.sort(candidates, function(a, b)
        local score_a = (a.candidate.quality or 0) + a.bonus
        local score_b = (b.candidate.quality or 0) + b.bonus
        if score_a ~= score_b then
            return score_a > score_b
        end
        -- 分数相同时保持原始顺序
        return a.original_index < b.original_index
    end)

    -- 输出排序后的候选
    for _, item in ipairs(candidates) do
        local cand = item.candidate

        -- 为技术术语添加标签提示
        local token_type = detector.classify_token(cand.text)
        if token_type == detector.TOKEN_TECH_TERM then
            if cand.comment == "" or cand.comment == nil then
                yield(wrap_candidate(cand, cand.text, "⚙"))
            else
                yield(cand)
            end
        else
            yield(cand)
        end
    end
end

local function fini(env)
    if env.commit_notifier and env.commit_notifier.disconnect then
        pcall(function()
            env.commit_notifier:disconnect()
        end)
    end
end

return { init = init, func = filter, fini = fini }
