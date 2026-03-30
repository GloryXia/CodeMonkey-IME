-- ============================================================
-- hybrid_processor.lua — 混合输入状态管理处理器
-- 管理输入状态、记录已提交文本、处理快捷键切换
-- ============================================================

local utils = require("utils")
local detector = require("context_detector")

local kRejected = 0
local kAccepted = 1

-- ============================================================
-- 初始化
-- ============================================================

local function init(env)
    -- 跟踪已提交的文本历史
    env.commit_history = {}      -- 最近的提交记录列表
    env.max_history = 20         -- 保留最近 20 条

    -- 撤销栈
    env.undo_stack = {}

    -- 共享状态（与其他 Lua 模块共享）
    env.hybrid_state = {
        last_committed_char = nil,
        recent_committed = "",
        is_protected = false,
        current_app = nil,
    }
end

-- ============================================================
-- 提交记录管理
-- ============================================================

--- 记录一次提交
local function record_commit(env, text, source)
    if not text or text == "" then return end

    table.insert(env.commit_history, {
        text = text,
        source = source or "normal",
        timestamp = os.time(),
    })

    -- 限制历史长度
    while #env.commit_history > env.max_history do
        table.remove(env.commit_history, 1)
    end

    -- 更新最后提交字符
    env.hybrid_state.last_committed_char = utils.utf8_last_char(text)

    -- 更新近期提交文本
    env.hybrid_state.recent_committed =
        ((env.hybrid_state.recent_committed or "") .. text)
    if #env.hybrid_state.recent_committed > 200 then
        env.hybrid_state.recent_committed =
            env.hybrid_state.recent_committed:sub(-200)
    end
end

-- ============================================================
-- 选项切换辅助函数
-- ============================================================

--- 切换一个 Rime 选项并通过 commit_text 提示用户当前状态
--- @param env table Rime 环境
--- @param option_name string 选项名称
--- @param on_label string 开启时的显示文字
--- @param off_label string 关闭时的显示文字
--- @return boolean 是否成功切换
local function toggle_option(env, option_name, on_label, off_label)
    local context = env.engine.context
    if not context then return false end

    local current = context:get_option(option_name)
    -- 如果是 nil（首次访问），视为开启状态
    if current == nil then current = true end

    local new_value = not current
    context:set_option(option_name, new_value)

    -- 注: Rime 会在状态栏自动显示 switches 中定义的 states 标签
    -- 无需额外提示

    return true
end

-- ============================================================
-- 快捷键检测
-- ============================================================

--- 检测按键是否匹配 Ctrl+Shift+数字
--- @param key_event table
--- @return number|nil 匹配的数字 (1-9)，不匹配返回 nil
local function detect_ctrl_shift_number(key_event)
    if not (key_event:ctrl() and key_event:shift()) then
        return nil
    end
    -- 数字键 1-9 的 keycode
    -- 在 Rime 中，按下 Ctrl+Shift+1 时:
    --   keycode 可能是 0x31 ('1') 或对应的 XK 符号
    local keycode = key_event.keycode

    -- ASCII 数字 '1'-'9' = 0x31 - 0x39
    if keycode >= 0x31 and keycode <= 0x39 then
        return keycode - 0x30
    end

    -- 某些系统上 Shift+数字 会产生符号键 (!@#$...)
    -- Shift+1 = ! (0x21), Shift+2 = @ (0x40), Shift+3 = # (0x23)
    -- Shift+4 = $ (0x24)
    local shift_num_map = {
        [0x21] = 1,  -- !
        [0x40] = 2,  -- @
        [0x23] = 3,  -- #
        [0x24] = 4,  -- $
        [0x25] = 5,  -- %
        [0x5E] = 6,  -- ^
        [0x26] = 7,  -- &
        [0x2A] = 8,  -- *
        [0x28] = 9,  -- (
    }
    if shift_num_map[keycode] then
        return shift_num_map[keycode]
    end

    return nil
end

--- 检测 F5/F6/F7 功能键
--- @param key_event table
--- @return number|nil F键编号 (5/6/7)
local function detect_function_key(key_event)
    local keycode = key_event.keycode
    -- F5 = 0xFFC2, F6 = 0xFFC3, F7 = 0xFFC4 (X11 keysym)
    -- 在 Rime/macOS 中也可能是其他值
    -- librime 使用 XK_F5=0xFFC2 等
    if keycode == 0xFFC2 then return 5 end
    if keycode == 0xFFC3 then return 6 end
    if keycode == 0xFFC4 then return 7 end
    return nil
end

-- ============================================================
-- 主处理器逻辑
-- ============================================================

local function processor(key_event, env)
    -- 只处理按下事件
    if key_event:release() then
        return kRejected
    end

    local context = env.engine.context

    -- ========================================
    -- 快捷键处理: Ctrl+Shift+数字
    -- ========================================
    local num = detect_ctrl_shift_number(key_event)
    if num then
        if num == 1 then
            toggle_option(env, "hybrid_mode", "混合模式", "标准模式")
            return kAccepted
        elseif num == 2 then
            toggle_option(env, "auto_punct", "标点智能", "标点手动")
            return kAccepted
        elseif num == 3 then
            toggle_option(env, "auto_space", "空格智能", "空格手动")
            return kAccepted
        elseif num == 4 then
            toggle_option(env, "simplification", "简体", "繁体")
            return kAccepted
        end
    end

    -- ========================================
    -- 快捷键处理: F5/F6/F7
    -- ========================================
    local fkey = detect_function_key(key_event)
    if fkey then
        if fkey == 5 then
            toggle_option(env, "hybrid_mode", "混合模式", "标准模式")
            return kAccepted
        elseif fkey == 6 then
            toggle_option(env, "auto_punct", "标点智能", "标点手动")
            return kAccepted
        elseif fkey == 7 then
            toggle_option(env, "auto_space", "空格智能", "空格手动")
            return kAccepted
        end
    end

    -- ========================================
    -- 监听提交事件：当候选被选中上屏时
    -- ========================================
    if context then
        local commit_text = context:get_commit_text()
        if commit_text and commit_text ~= "" then
            record_commit(env, commit_text, "candidate")
        end
    end

    -- ========================================
    -- 检测当前输入是否进入保护模式
    -- ========================================
    if context and context:is_composing() then
        local input = context.input
        if input then
            local protected, reason = detector.is_protected(
                env.hybrid_state.recent_committed or "",
                input
            )
            env.hybrid_state.is_protected = protected
        end
    end

    -- 不拦截其他按键，仅管理状态
    return kRejected
end

return { init = init, func = processor }
