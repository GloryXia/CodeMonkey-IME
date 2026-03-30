-- ============================================================
-- auto_space_filter.lua — 自动空格 Filter
-- 在中英混排时自动补充中英文之间的空格
-- ============================================================

local utils = require("utils")
local detector = require("context_detector")

-- ============================================================
-- 初始化
-- ============================================================

local function init(env)
    env.auto_space_state = {
        last_committed_char = nil,
        recent_committed = "",
    }
end

-- ============================================================
-- 判断是否需要在候选前添加空格
-- ============================================================

--- 判断候选文本上屏前是否需要在前面补一个空格
--- @param cand_text string 候选文字
--- @param env table Rime 环境
--- @return boolean
local function need_space_before(cand_text, env)
    if not cand_text or cand_text == "" then return false end

    -- 获取已提交文本的最后一个字符
    local last_char = env.auto_space_state.last_committed_char
    if not last_char or last_char == "" then return false end

    local first_cand_char = nil
    for c in utils.utf8_chars(cand_text) do
        first_cand_char = c
        break
    end
    if not first_cand_char then return false end

    -- 规则1: 英文/数字后 + 中文候选 → 加空格
    if (utils.is_ascii_letter(last_char) or utils.is_digit(last_char))
       and utils.is_chinese_char(first_cand_char) then
        return true
    end

    -- 规则2: 中文后 + 英文/数字候选 → 加空格
    if utils.is_chinese_char(last_char)
       and (utils.is_ascii_letter(first_cand_char) or utils.is_digit(first_cand_char)) then
        return true
    end

    return false
end

--- 检查是否处于不应添加空格的保护场景
--- @param env table
--- @return boolean
local function is_space_protected(env)
    local recent = env.auto_space_state.recent_committed or ""
    local protected, reason = detector.is_protected(recent, "")
    return protected
end

-- ============================================================
-- Filter 主逻辑
-- ============================================================

--- Rime filter 入口函数
--- 遍历候选列表，在需要时为候选文本前添加空格
--- @param input userdata 候选迭代器
--- @param env table Rime 环境
local function filter(input, env)
    -- 检查开关
    local context = env.engine.context
    local auto_space_on = true
    if context then
        local opt = context:get_option("auto_space")
        if opt == false then
            auto_space_on = false
        end

        local hybrid_on = context:get_option("hybrid_mode")
        if hybrid_on == false then
            auto_space_on = false
        end
    end

    -- 尝试从共享状态获取已提交信息
    -- (hybrid_processor 会更新这些)
    if env.engine and env.engine.context then
        local commit_text = env.engine.context:get_commit_text()
        if commit_text and commit_text ~= "" then
            env.auto_space_state.last_committed_char = utils.utf8_last_char(commit_text)
            env.auto_space_state.recent_committed =
                ((env.auto_space_state.recent_committed or "") .. commit_text)
            if #env.auto_space_state.recent_committed > 200 then
                env.auto_space_state.recent_committed =
                    env.auto_space_state.recent_committed:sub(-200)
            end
        end
    end

    -- 如果自动空格关闭或处于保护场景，原样输出
    if not auto_space_on or is_space_protected(env) then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    -- 遍历候选，必要时修改候选文本
    for cand in input:iter() do
        local text = cand.text

        if need_space_before(text, env) then
            -- 在候选文本前加空格
            -- 创建新候选，文本前加空格
            local new_cand = Candidate(
                cand.type,
                cand.start,
                cand._end,
                " " .. text,
                cand.comment
            )
            new_cand.quality = cand.quality
            yield(new_cand)
        else
            yield(cand)
        end
    end
end

return { init = init, func = filter }
