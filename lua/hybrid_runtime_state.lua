-- ============================================================
-- hybrid_runtime_state.lua — DevCn-IME 运行时共享状态
-- 在不同 Lua 组件之间共享最近提交文本与上下文快照
-- ============================================================

local M = {}

local function default_state()
    return {
        last_committed_char = nil,
        last_committed_text = nil,
        last_synced_commit_text = nil,
        recent_committed = "",
        pending_closers = {},
        is_protected = false,
        current_app = nil,
    }
end

local state = default_state()

local function merge(seed)
    if type(seed) ~= "table" then
        return
    end
    for key, value in pairs(seed) do
        state[key] = value
    end
end

function M.ensure(seed)
    merge(seed)
    return state
end

function M.reset(seed)
    state = default_state()
    merge(seed)
    return state
end

return M
