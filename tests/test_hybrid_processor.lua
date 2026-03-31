-- ============================================================
-- test_hybrid_processor.lua — hybrid_processor.lua 单元测试
-- 运行: lua tests/test_hybrid_processor.lua
-- ============================================================

local pass_count = 0
local fail_count = 0

local function assert_eq(actual, expected, msg)
    if actual == expected then
        pass_count = pass_count + 1
    else
        fail_count = fail_count + 1
        print(string.format("  FAIL: %s — expected: %s, got: %s", msg, tostring(expected), tostring(actual)))
    end
end

package.path = package.path .. ";lua/?.lua"
local hybrid_processor = require("hybrid_processor")
local runtime_state = require("hybrid_runtime_state")

local function make_key_event(opts)
    return {
        keycode = opts.keycode,
        release = function() return opts.release == true end,
        ctrl = function() return opts.ctrl == true end,
        shift = function() return opts.shift == true end,
    }
end

local function make_env()
    runtime_state.reset()
    local options = {}
    local properties = {}
    local commit_callback = nil
    local context = {
        get_option = function(_, name)
            return options[name]
        end,
        set_option = function(_, name, value)
            options[name] = value
        end,
        get_commit_text = function()
            return ""
        end,
        commit_history = {
            latest_text = function()
                return ""
            end,
        },
        is_composing = function()
            return false
        end,
        get_property = function(_, name)
            return properties[name]
        end,
        set_property = function(_, name, value)
            properties[name] = value
        end,
        input = "",
        commit_notifier = {
            connect = function(_, callback)
                commit_callback = callback
                return {
                    disconnect = function() end,
                }
            end,
        },
    }

    local env = {
        engine = {
            context = context,
        },
    }

    hybrid_processor.init(env)
    return env, options, properties, function(text, opts)
        opts = opts or {}
        context.get_commit_text = function()
            if opts.empty_commit_text then
                return ""
            end
            return text
        end
        context.commit_history.latest_text = function()
            return text
        end
        if commit_callback then
            commit_callback(opts.callback_arg)
        end
    end
end

print("Testing hybrid_processor.lua...")
print("")

print("  init forces ascii_mode off:")
do
    local _, options = make_env()
    assert_eq(options.ascii_mode, false, "init should disable ascii_mode passthrough")
end

print("  regular letters must pass through:")
do
    local env = make_env()
    local result = hybrid_processor.func(make_key_event({ keycode = string.byte("w") }), env)
    assert_eq(result, 2, "plain letter should noop")
end

print("  release events must pass through:")
do
    local env = make_env()
    local result = hybrid_processor.func(make_key_event({ keycode = string.byte("w"), release = true }), env)
    assert_eq(result, 2, "release event should noop")
end

print("  toggle hotkey is accepted:")
do
    local env, options = make_env()
    options.hybrid_mode = true
    local result = hybrid_processor.func(make_key_event({
        keycode = string.byte("1"),
        ctrl = true,
        shift = true,
    }), env)
    assert_eq(result, 1, "toggle hotkey should be accepted")
    assert_eq(options.hybrid_mode, false, "toggle hotkey should flip hybrid_mode")
end

print("  commit notifier records committed text:")
do
    local env, _, _, emit_commit = make_env()
    emit_commit("我")
    assert_eq(env.hybrid_state.last_committed_text, "我", "commit notifier should update last committed text")
    assert_eq(env.hybrid_state.last_committed_char, "我", "commit notifier should update last committed char")
end

print("  commit notifier falls back to commit history:")
do
    local env, _, _, emit_commit = make_env()
    emit_commit("价格", { empty_commit_text = true })
    assert_eq(env.hybrid_state.last_committed_text, "价格", "commit history fallback should update last committed text")
end

print("  commit notifier ignores missing callback context:")
do
    local env, _, _, emit_commit = make_env()
    emit_commit("我", { callback_arg = nil })
    assert_eq(env.hybrid_state.last_committed_text, "我", "commit notifier should read engine context when callback arg is nil")
end

print("  commit notifier writes context properties:")
do
    local env, _, properties, emit_commit = make_env()
    emit_commit("你好")
    assert_eq(properties.hybrid_last_committed_text, "你好", "commit notifier should store last text on context")
    assert_eq(properties.hybrid_recent_committed, "你好", "commit notifier should store recent text on context")
end

print("")
print(string.format("Results: %d passed, %d failed, %d total",
    pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
