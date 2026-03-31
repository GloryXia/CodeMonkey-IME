-- ============================================================
-- test_punctuation_processor.lua — punctuation_processor.lua 单元测试
-- 运行: lua tests/test_punctuation_processor.lua
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

local function assert_nil(value, msg)
    assert_eq(value, nil, msg)
end

package.path = package.path .. ";lua/?.lua"
local punctuation_processor = require("punctuation_processor")
local runtime_state = require("hybrid_runtime_state")

local function make_key_event(ch, opts)
    opts = opts or {}
    return {
        keycode = string.byte(ch),
        release = function() return opts.release == true end,
        shift = function() return opts.shift == true end,
    }
end

local function make_env(opts)
    local committed = {}
    local commit_callback = nil
    runtime_state.reset(opts.hybrid_state)
    local engine = {}
    local properties = {}
    local context = {
        get_option = function(_, name)
            return opts.options and opts.options[name]
        end,
        is_composing = function()
            return opts.is_composing == true
        end,
        get_commit_text = function()
            return opts.context_commit_text or ""
        end,
        commit_history = {
            latest_text = function()
                return opts.context_commit_text or ""
            end,
        },
        get_property = function(_, name)
            return properties[name]
        end,
        set_property = function(_, name, value)
            properties[name] = value
        end,
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
        engine = engine,
        model_bridge_config = opts.model_bridge_config or {
            mode = "log_only",
        },
    }
    env.engine.context = context
    env.engine.commit_text = function(_, text)
        table.insert(committed, text)
    end

    if opts.context_properties then
        for key, value in pairs(opts.context_properties) do
            properties[key] = value
        end
    end

    punctuation_processor.init(env)
    env.last_committed_char = opts.last_committed_char
    env.last_committed_text = opts.last_committed_text
    env.recent_committed = opts.recent_committed or ""
    env.move_cursor_left = opts.move_cursor_left or function()
        return false
    end

    return env, committed, function(text, emit_opts)
        emit_opts = emit_opts or {}
        opts.context_commit_text = emit_opts.empty_commit_text and "" or text
        context.commit_history.latest_text = function()
            return text
        end
        if commit_callback then
            commit_callback(emit_opts.callback_arg)
        end
    end
end

print("Testing punctuation_processor.lua...")
print("")

print("  chinese context converts comma:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        last_committed_char = "好",
        recent_committed = "你好",
    })
    local result = punctuation_processor.func(make_key_event(","), env)
    assert_eq(result, 1, "comma accepted in chinese context")
    assert_eq(committed[1], "，", "comma converted to chinese comma")
end

print("  english context keeps comma:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        last_committed_char = "e",
        recent_committed = "hello world",
    })
    local result = punctuation_processor.func(make_key_event(","), env)
    assert_eq(result, 1, "comma should be accepted in english context")
    assert_eq(committed[1], ",", "english context should commit ascii comma")
end

print("  mixed chinese context converts after english token:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        last_committed_char = "R",
        last_committed_text = "merge",
        recent_committed = "先把 PR merge",
    })
    local result = punctuation_processor.func(make_key_event(","), env)
    assert_eq(result, 1, "comma accepted in mixed chinese context")
    assert_eq(committed[1], "，", "mixed chinese context converts comma")
end

print("  plain english word keeps question mark:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "hello",
    })
    local result = punctuation_processor.func(make_key_event("/", { shift = true }), env)
    assert_eq(result, 1, "question mark should be accepted after plain english word")
    assert_eq(committed[1], "?", "plain english word should keep ascii question mark")
end

print("  plain english word keeps less-than sign:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "hello",
    })
    local result = punctuation_processor.func(make_key_event(",", { shift = true }), env)
    assert_eq(result, 1, "less-than should be accepted after plain english word")
    assert_eq(committed[1], "<", "plain english word should keep ascii less-than sign")
end

print("  model-assisted english context can choose chinese punctuation:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "hello",
        recent_committed = "hello",
        model_bridge_config = {
            mode = "sidecar",
            transport = function(request)
                return {
                    request_id = request.request_id,
                    source = "sidecar_stub",
                    context = "mixed",
                    confidence = 0.88,
                    ttl_ms = 900,
                    scores = {
                        zh_punct_prob = 0.91,
                        en_punct_prob = 0.09,
                    },
                }
            end,
        },
    })
    local result = punctuation_processor.func(make_key_event("/", { shift = true }), env)
    assert_eq(result, 1, "model-assisted question mark should be accepted")
    assert_eq(committed[1], "？", "model can promote chinese punctuation in ambiguous english context")
end

print("  shared hybrid state preserves chinese context for mixed punctuation:")
do
    local captured_recent = nil
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "hello",
        hybrid_state = {
            last_committed_char = "o",
            last_committed_text = "hello",
            last_synced_commit_text = "hello",
            recent_committed = "你好hello",
        },
        model_bridge_config = {
            mode = "sidecar",
            transport = function(request)
                captured_recent = request.recent_committed
                return {
                    request_id = request.request_id,
                    source = "sidecar_stub",
                    context = "mixed",
                    confidence = 0.82,
                    ttl_ms = 900,
                    scores = {
                        zh_punct_prob = 0.8,
                        en_punct_prob = 0.2,
                    },
                }
            end,
        },
    })
    local result = punctuation_processor.func(make_key_event("/", { shift = true }), env)
    assert_eq(result, 1, "question mark should be accepted with shared mixed context")
    assert_eq(captured_recent, "你好hello", "shared hybrid state should be forwarded to sidecar")
    assert_eq(committed[1], "？", "shared mixed context should produce chinese question mark")
end

print("  context properties preserve chinese context for mixed punctuation:")
do
    local captured_recent = nil
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "hello",
        context_properties = {
            hybrid_last_committed_text = "hello",
            hybrid_last_committed_char = "o",
            hybrid_recent_committed = "你好hello",
        },
        model_bridge_config = {
            mode = "sidecar",
            transport = function(request)
                captured_recent = request.recent_committed
                return {
                    request_id = request.request_id,
                    source = "sidecar_stub",
                    context = "mixed",
                    confidence = 0.82,
                    ttl_ms = 900,
                    scores = {
                        zh_punct_prob = 0.8,
                        en_punct_prob = 0.2,
                    },
                }
            end,
        },
    })
    local result = punctuation_processor.func(make_key_event("/", { shift = true }), env)
    assert_eq(result, 1, "question mark should be accepted with context property state")
    assert_eq(captured_recent, "你好hello", "context properties should be forwarded to sidecar")
    assert_eq(committed[1], "？", "context property state should produce chinese question mark")
end

print("  chinese context converts opening double quote:")
do
    local move_count = 0
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_properties = {
            hybrid_last_committed_text = "你好",
            hybrid_last_committed_char = "好",
            hybrid_recent_committed = "你好",
        },
        move_cursor_left = function()
            move_count = move_count + 1
            return true
        end,
    })
    local result = punctuation_processor.func(make_key_event("'", { shift = true }), env)
    assert_eq(result, 1, "opening double quote should be accepted in chinese context")
    assert_eq(committed[1], "“”", "opening double quote should auto pair in chinese context")
    assert_eq(move_count, 1, "paired chinese double quote should move cursor left once")
    assert_eq(env.last_committed_text, "“", "state should track opening chinese quote before caret")
end

print("  chinese context converts closing double quote:")
do
    local move_count = 0
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        hybrid_state = {
            pending_closers = { "”" },
        },
        context_properties = {
            hybrid_last_committed_text = "内容",
            hybrid_last_committed_char = "容",
            hybrid_recent_committed = "内容",
        },
        move_cursor_left = function()
            move_count = move_count + 1
            return true
        end,
    })
    local result = punctuation_processor.func(make_key_event("'", { shift = true }), env)
    assert_eq(result, 1, "closing double quote should be accepted in chinese context")
    assert_eq(committed[1], "”", "closing double quote should convert to chinese quote")
    assert_eq(move_count, 0, "closing chinese double quote should not trigger auto pair")
    assert_eq(#env.hybrid_state.pending_closers, 0, "closing chinese double quote should clear pending closer")
end

print("  english context keeps double quote:")
do
    local move_count = 0
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_properties = {
            hybrid_last_committed_text = "hello",
            hybrid_last_committed_char = "o",
            hybrid_recent_committed = "hello",
        },
        move_cursor_left = function()
            move_count = move_count + 1
            return true
        end,
    })
    local result = punctuation_processor.func(make_key_event("'", { shift = true }), env)
    assert_eq(result, 1, "double quote should be accepted in english context")
    assert_eq(committed[1], "\"\"", "double quote should auto pair in english context")
    assert_eq(move_count, 1, "paired ascii double quote should move cursor left once")
end

print("  chinese context converts opening single quote:")
do
    local move_count = 0
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_properties = {
            hybrid_last_committed_text = "你好",
            hybrid_last_committed_char = "好",
            hybrid_recent_committed = "你好",
        },
        move_cursor_left = function()
            move_count = move_count + 1
            return true
        end,
    })
    local result = punctuation_processor.func(make_key_event("'"), env)
    assert_eq(result, 1, "opening single quote should be accepted in chinese context")
    assert_eq(committed[1], "‘’", "opening single quote should auto pair in chinese context")
    assert_eq(move_count, 1, "paired chinese single quote should move cursor left once")
end

print("  stale recent text still opens a fresh chinese double quote pair:")
do
    local move_count = 0
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_properties = {
            hybrid_last_committed_text = "他说",
            hybrid_last_committed_char = "说",
            hybrid_recent_committed = "旧上下文里残留了一个“",
        },
        move_cursor_left = function()
            move_count = move_count + 1
            return true
        end,
    })
    local result = punctuation_processor.func(make_key_event("'", { shift = true }), env)
    assert_eq(result, 1, "fresh chinese double quote should still be accepted with stale recent text")
    assert_eq(committed[1], "“”", "fresh chinese double quote should open a new pair")
    assert_eq(move_count, 1, "fresh chinese double quote should still move cursor left")
    assert_eq(env.hybrid_state.pending_closers[1], "”", "fresh chinese double quote should register pending closer")
end

print("  chinese context converts square brackets:")
do
    local move_count = 0
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_properties = {
            hybrid_last_committed_text = "标题",
            hybrid_last_committed_char = "题",
            hybrid_recent_committed = "标题",
        },
        move_cursor_left = function()
            move_count = move_count + 1
            return true
        end,
    })
    local left_result = punctuation_processor.func(make_key_event("["), env)
    assert_eq(left_result, 1, "left square bracket should be accepted in chinese context")
    assert_eq(committed[1], "【】", "left square bracket should auto pair chinese bracket")
    assert_eq(move_count, 1, "paired chinese bracket should move cursor left once")
end

print("  model-assisted mixed context converts semicolon:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "hello",
        context_properties = {
            hybrid_last_committed_text = "hello",
            hybrid_last_committed_char = "o",
            hybrid_recent_committed = "你好hello",
        },
        model_bridge_config = {
            mode = "sidecar",
            transport = function(request)
                return {
                    request_id = request.request_id,
                    source = "sidecar_stub",
                    context = "mixed",
                    confidence = 0.83,
                    ttl_ms = 900,
                    scores = {
                        zh_punct_prob = request.target_punct == ";" and 0.82 or 0.18,
                        en_punct_prob = request.target_punct == ";" and 0.18 or 0.82,
                    },
                }
            end,
        },
    })
    local result = punctuation_processor.func(make_key_event(";"), env)
    assert_eq(result, 1, "semicolon should be accepted in mixed context")
    assert_eq(committed[1], "；", "semicolon should follow model-assisted chinese punctuation")
end

print("  protected url keeps period:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        last_committed_char = "m",
        recent_committed = "https://example.com",
    })
    local result = punctuation_processor.func(make_key_event("."), env)
    assert_eq(result, 1, "url context should be accepted and keep half width period")
    assert_eq(committed[1], ".", "url context should commit ascii period")
end

print("  ascii mode disables conversion:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = true },
        last_committed_char = "好",
        recent_committed = "你好",
    })
    local result = punctuation_processor.func(make_key_event(","), env)
    assert_eq(result, 2, "ascii mode should noop")
    assert_nil(committed[1], "ascii mode should not commit chinese punct")
end

print("  composing state defers to Rime:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        is_composing = true,
        last_committed_char = "好",
        recent_committed = "你好",
    })
    local result = punctuation_processor.func(make_key_event(","), env)
    assert_eq(result, 2, "composing state should noop")
    assert_nil(committed[1], "composing state should not commit chinese punct")
end

print("  regular letters must pass through:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        recent_committed = "你好",
    })
    local result = punctuation_processor.func(make_key_event("w"), env)
    assert_eq(result, 2, "non-punctuation key should noop")
    assert_nil(committed[1], "non-punctuation key should not commit text")
end

print("  chinese context converts dollar to yuan:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        last_committed_char = "好",
        recent_committed = "你好",
    })
    local result = punctuation_processor.func(make_key_event("$"), env)
    assert_eq(result, 1, "dollar should be accepted in chinese context")
    assert_eq(committed[1], "￥", "dollar should convert to yuan sign")
end

print("  chinese context converts left parenthesis:")
do
    local move_count = 0
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        last_committed_char = "格",
        recent_committed = "价格",
        move_cursor_left = function()
            move_count = move_count + 1
            return true
        end,
    })
    local result = punctuation_processor.func(make_key_event("("), env)
    assert_eq(result, 1, "left parenthesis should be accepted in chinese context")
    assert_eq(committed[1], "（）", "left parenthesis should auto pair in chinese context")
    assert_eq(move_count, 1, "paired chinese parenthesis should move cursor left once")
    assert_eq(env.last_committed_text, "（", "state should track text before caret after paired chinese parenthesis")
end

print("  english context keeps left parenthesis:")
do
    local move_count = 0
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        last_committed_char = "e",
        recent_committed = "price",
        move_cursor_left = function()
            move_count = move_count + 1
            return true
        end,
    })
    local result = punctuation_processor.func(make_key_event("("), env)
    assert_eq(result, 1, "left parenthesis should be accepted in english context")
    assert_eq(committed[1], "()", "left parenthesis should auto pair in english context")
    assert_eq(move_count, 1, "paired ascii parenthesis should move cursor left once")
    assert_eq(env.last_committed_text, "(", "state should track text before caret after paired ascii parenthesis")
end

print("  chinese punctuation context converts dollar to yuan:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        last_committed_char = "。",
        recent_committed = "你好。",
    })
    local result = punctuation_processor.func(make_key_event("$"), env)
    assert_eq(result, 1, "dollar should be accepted after chinese punctuation")
    assert_eq(committed[1], "￥", "dollar should convert after chinese punctuation")
end

print("  english context keeps dollar:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        last_committed_char = "d",
        recent_committed = "world",
    })
    local result = punctuation_processor.func(make_key_event("$"), env)
    assert_eq(result, 1, "dollar should be accepted in english context")
    assert_eq(committed[1], "$", "english context should commit half width dollar")
end

print("  empty context keeps dollar:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
    })
    local result = punctuation_processor.func(make_key_event("$"), env)
    assert_eq(result, 1, "dollar should be accepted with no previous context")
    assert_eq(committed[1], "$", "empty context should commit half width dollar")
end

print("  committed chinese text converts dollar to yuan:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "价格",
    })
    local result = punctuation_processor.func(make_key_event("$"), env)
    assert_eq(result, 1, "recent committed chinese text should trigger yuan sign")
    assert_eq(committed[1], "￥", "committed chinese text should convert dollar")
end

print("  committed english text keeps dollar:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "price",
    })
    local result = punctuation_processor.func(make_key_event("$"), env)
    assert_eq(result, 1, "recent committed english text should commit dollar")
    assert_eq(committed[1], "$", "committed english text should keep dollar")
end

print("  url scheme keeps ascii colon in chinese context:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "https",
        recent_committed = "你打开一下这个网站https",
        model_bridge_config = {
            mode = "sidecar",
            transport = function(request)
                local zh_prob = 0.94
                local en_prob = 0.06
                if request.target_punct == ":" and request.last_commit_text == "https" then
                    zh_prob = 0.04
                    en_prob = 0.96
                end
                return {
                    request_id = request.request_id,
                    source = "sidecar_stub",
                    context = "protocol_hint",
                    confidence = 0.95,
                    ttl_ms = 900,
                    scores = {
                        zh_punct_prob = zh_prob,
                        en_punct_prob = en_prob,
                    },
                }
            end,
        },
    })
    local result = punctuation_processor.func(make_key_event(":"), env)
    assert_eq(result, 1, "url scheme colon should be accepted")
    assert_eq(committed[1], ":", "url scheme should keep ascii colon via model decision")
end

print("  custom protocol keeps ascii colon:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "vscode",
        recent_committed = "请打开vscode",
    })
    local result = punctuation_processor.func(make_key_event(":"), env)
    assert_eq(result, 1, "custom protocol colon should be accepted")
    assert_eq(committed[1], ":", "custom protocol should keep ascii colon")
end

print("  http scheme keeps ascii colon in chinese context:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "http",
        recent_committed = "你打开一下这个网站http",
        model_bridge_config = {
            mode = "sidecar",
            transport = function(request)
                local zh_prob = 0.94
                local en_prob = 0.06
                if request.target_punct == ":" and request.last_commit_text == "http" then
                    zh_prob = 0.04
                    en_prob = 0.96
                end
                return {
                    request_id = request.request_id,
                    source = "sidecar_stub",
                    context = "protocol_hint",
                    confidence = 0.95,
                    ttl_ms = 900,
                    scores = {
                        zh_punct_prob = zh_prob,
                        en_punct_prob = en_prob,
                    },
                }
            end,
        },
    })
    local result = punctuation_processor.func(make_key_event(":"), env)
    assert_eq(result, 1, "http scheme colon should be accepted")
    assert_eq(committed[1], ":", "http scheme should keep ascii colon")
end

print("  slash after protocol colon passes through:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_properties = {
            hybrid_last_committed_text = ":",
            hybrid_last_committed_char = ":",
            hybrid_recent_committed = "https:",
        },
    })
    local result = punctuation_processor.func(make_key_event("/"), env)
    assert_eq(result, 2, "slash should pass through to downstream url input")
    assert_nil(committed[1], "slash should not be intercepted by punctuation processor")
end

print("  model can keep ascii colon after tech token in chinese context:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "merge",
        recent_committed = "先把这个merge",
        model_bridge_config = {
            mode = "sidecar",
            transport = function(request)
                local zh_prob = 0.91
                local en_prob = 0.09
                if request.target_punct == ":" then
                    zh_prob = 0.08
                    en_prob = 0.92
                end
                return {
                    request_id = request.request_id,
                    source = "sidecar_stub",
                    context = "tech_mixed",
                    confidence = 0.89,
                    ttl_ms = 900,
                    scores = {
                        zh_punct_prob = zh_prob,
                        en_punct_prob = en_prob,
                    },
                }
            end,
        },
    })
    local result = punctuation_processor.func(make_key_event(":"), env)
    assert_eq(result, 1, "tech token colon should be accepted")
    assert_eq(committed[1], ":", "model can keep ascii colon after tech token in chinese context")
end

print("  shifted 4 is recognized as dollar:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
    })
    local result = punctuation_processor.func(make_key_event("4", { shift = true }), env)
    assert_eq(result, 1, "shifted 4 should be accepted as dollar")
    assert_eq(committed[1], "$", "shifted 4 should commit half width dollar")
end

print("  shifted 4 after chinese text becomes yuan:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "价格",
    })
    local result = punctuation_processor.func(make_key_event("4", { shift = true }), env)
    assert_eq(result, 1, "shifted 4 should be accepted after chinese text")
    assert_eq(committed[1], "￥", "shifted 4 should convert to yuan after chinese text")
end

print("  shifted slash becomes question mark in chinese context:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "你好",
    })
    local result = punctuation_processor.func(make_key_event("/", { shift = true }), env)
    assert_eq(result, 1, "shifted slash should be accepted in chinese context")
    assert_eq(committed[1], "？", "shifted slash should convert to chinese question mark")
end

print("  shifted comma becomes left book title mark in chinese context:")
do
    local move_count = 0
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "书名",
        move_cursor_left = function()
            move_count = move_count + 1
            return true
        end,
    })
    local result = punctuation_processor.func(make_key_event(",", { shift = true }), env)
    assert_eq(result, 1, "shifted comma should be accepted in chinese context")
    assert_eq(committed[1], "《》", "shifted comma should auto pair chinese book title marks")
    assert_eq(move_count, 1, "paired book title marks should move cursor left once")
end

print("  shifted comma stays ascii in english context:")
do
    local env, committed = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
        context_commit_text = "title",
    })
    local result = punctuation_processor.func(make_key_event(",", { shift = true }), env)
    assert_eq(result, 1, "shifted comma should be accepted in english context")
    assert_eq(committed[1], "<", "shifted comma should stay ascii in english context")
end

print("  commit notifier ignores missing callback context:")
do
    local env, _, emit_commit = make_env({
        options = { auto_punct = true, hybrid_mode = true, ascii_mode = false },
    })
    emit_commit("我", { callback_arg = nil })
    assert_eq(env.last_committed_text, "我", "commit notifier should read engine context when callback arg is nil")
    assert_eq(env.last_committed_char, "我", "commit notifier should update last committed char")
end

print("")
print(string.format("Results: %d passed, %d failed, %d total",
    pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
