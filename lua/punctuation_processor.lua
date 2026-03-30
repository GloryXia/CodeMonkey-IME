-- ============================================================
-- punctuation_processor.lua — 标点智能决策处理器
-- 根据上下文自动决策半角标点是否替换为中文全角标点
-- ============================================================

local utils = require("utils")
local detector = require("context_detector")

-- Rime 按键返回值
local kRejected = 0  -- 不处理，交给后续处理器
local kAccepted = 1  -- 已处理，吞掉按键

-- ============================================================
-- 标点智能决策主逻辑
-- ============================================================

--- 获取已提交文本的最后一个字符
--- @param env table Rime 环境对象
--- @return string|nil
local function get_last_committed_char(env)
    local context = env.engine.context
    local commit_text = context:get_commit_text()
    if commit_text and commit_text ~= "" then
        return utils.utf8_last_char(commit_text)
    end

    -- 尝试从 commit history 获取
    if env.last_committed_char then
        return env.last_committed_char
    end

    return nil
end

--- 记录最后提交的字符（在 commit 事件时调用）
--- @param env table
--- @param text string
local function record_commit(env, text)
    if text and text ~= "" then
        env.last_committed_char = utils.utf8_last_char(text)
        -- 记录最近提交的文本片段（用于上下文分析）
        env.recent_committed = ((env.recent_committed or "") .. text)
        -- 只保留最近 50 个字符
        if #(env.recent_committed or "") > 200 then
            env.recent_committed = env.recent_committed:sub(-200)
        end
    end
end

--- 初始化函数
local function init(env)
    env.last_committed_char = nil
    env.recent_committed = ""
    env.last_punct_action = nil  -- 记录上次标点操作，用于撤销
end

--- 判断是否应该将半角标点替换为中文标点
--- @param punct string 半角标点字符
--- @param env table Rime 环境
--- @return boolean should_convert 是否替换
--- @return string|nil chinese_punct 替换后的中文标点
local function should_convert_punct(punct, env)
    -- 0. 检查是否有对应的中文标点映射
    local chinese_punct = utils.get_chinese_punct(punct)
    if not chinese_punct then
        return false, nil
    end

    -- 1. 检查开关状态
    local context = env.engine.context
    if context then
        -- 检查 auto_punct 开关
        local auto_punct_on = context:get_option("auto_punct")
        if auto_punct_on == false then
            return false, nil
        end

        -- 检查 hybrid_mode 开关
        local hybrid_on = context:get_option("hybrid_mode")
        if hybrid_on == false then
            return false, nil
        end

        -- 如果当前在 ASCII 模式，不替换
        local ascii_mode = context:get_option("ascii_mode")
        if ascii_mode then
            return false, nil
        end
    end

    -- 2. 如果有组合态内容（正在输入拼音），不拦截
    if context and context:is_composing() then
        return false, nil
    end

    -- 3. 检查保护模式
    local recent = env.recent_committed or ""
    local protected, reason = detector.is_protected(recent, "")
    if protected then
        return false, nil
    end

    -- 4. 获取上一个已提交字符
    local last_char = env.last_committed_char
    if not last_char then
        -- 没有上文信息，保守不替换
        return false, nil
    end

    -- 5. 根据上一字符类型决策
    local prev_type = detector.get_prev_char_type(last_char)

    if prev_type == "chinese" then
        -- 上一字符是中文 → 替换
        return true, chinese_punct
    end

    if prev_type == "english" then
        -- 上一字符是英文 → 需要进一步判断语境
        -- 检测近期文本的主要语言
        local lang_ctx = detector.detect_language_context(recent)
        if lang_ctx == "chinese" or lang_ctx == "mixed" then
            -- 中文或混合语境中的英文单词后 → 替换
            -- 例如：「先把 PR merge，」← 这里的逗号应替换
            return true, chinese_punct
        end
        -- 纯英文语境 → 不替换
        return false, nil
    end

    if prev_type == "number" then
        -- 数字后面：
        --   句号可能是小数点 → 不替换 "."
        --   逗号可能是千分位 → 不替换 ","
        if punct == "." or punct == "," then
            return false, nil
        end
        -- 其他标点在数字后按语境判断
        local lang_ctx = detector.detect_language_context(recent)
        if lang_ctx == "chinese" or lang_ctx == "mixed" then
            return true, chinese_punct
        end
        return false, nil
    end

    if prev_type == "punct" then
        -- 标点后面再跟标点 → 不替换（避免连续替换干扰）
        return false, nil
    end

    -- 6. 默认：保守不替换
    return false, nil
end

--- Rime processor 入口函数
--- @param key_event table 按键事件
--- @param env table Rime 环境
--- @return number 处理结果
local function processor(key_event, env)
    -- 只处理按下事件，不处理释放事件
    if key_event:release() then
        return kRejected
    end

    -- 获取按键对应的字符
    local key_char = nil
    local keycode = key_event.keycode

    -- 检查是否是可转换的标点
    if keycode >= 0x20 and keycode <= 0x7E then
        key_char = string.char(keycode)
    end

    if not key_char then
        return kRejected
    end

    -- 检查是否是待决策标点
    if not utils.is_convertible_punct(key_char) then
        -- 不是待决策标点，但如果是其他字符，记录它
        return kRejected
    end

    -- 执行标点决策
    local should_convert, chinese_punct = should_convert_punct(key_char, env)

    if should_convert and chinese_punct then
        -- 记录操作（用于可能的撤销）
        env.last_punct_action = {
            original = key_char,
            converted = chinese_punct,
        }

        -- 直接提交中文标点
        env.engine:commit_text(chinese_punct)

        -- 更新已提交字符记录
        record_commit(env, chinese_punct)

        return kAccepted
    end

    -- 不替换，让后续处理器处理
    -- 但仍然记录这个字符
    -- (会在 commit 时由 hybrid_processor 记录)
    return kRejected
end

return { init = init, func = processor }
