-- ============================================================
-- hybrid_processor.lua — 混合输入状态管理处理器
-- 管理输入状态、记录已提交文本、处理回退逻辑
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
-- 主处理器逻辑
-- ============================================================

local function processor(key_event, env)
    -- 只处理按下事件
    if key_event:release() then
        return kRejected
    end

    local context = env.engine.context

    -- ========================================
    -- 快捷键：Ctrl+Z 撤销上次智能替换
    -- ========================================
    if key_event:ctrl() and key_event.keycode == 0x7A then -- 'z'
        if #env.undo_stack > 0 then
            local last_action = table.remove(env.undo_stack)
            if last_action then
                -- 这里的撤销是有限的：只能提示用户
                -- Rime 本身不支持回退已提交文本
                -- 未来可通过更复杂的机制实现
            end
        end
        -- 不拦截，让系统 Ctrl+Z 正常工作
        return kRejected
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

    -- 不拦截任何按键，仅管理状态
    return kRejected
end

return { init = init, func = processor }
