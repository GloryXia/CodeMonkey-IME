-- ============================================================
-- test_hybrid_filter.lua — hybrid_filter.lua 单元测试
-- 运行: lua tests/test_hybrid_filter.lua
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

_G.ShadowCandidate = function(cand, cand_type, text, comment)
    local wrapped = {}
    for k, v in pairs(cand) do
        wrapped[k] = v
    end
    wrapped.type = cand_type
    wrapped.text = text
    wrapped.comment = comment
    return wrapped
end

local hybrid_filter = require("hybrid_filter")

local function make_candidate(text, quality, comment)
    return {
        type = "test",
        start = 0,
        _end = #text,
        text = text,
        quality = quality or 0,
        comment = comment,
    }
end

local function make_input(candidates)
    return {
        iter = function()
            local index = 0
            return function()
                index = index + 1
                return candidates[index]
            end
        end,
    }
end

local function make_env(opts)
    opts = opts or {}
    local context = {
        get_option = function(_, name)
            return opts.options and opts.options[name]
        end,
        get_commit_text = function()
            return opts.context_commit_text or ""
        end,
        input = opts.input or "",
    }

    local env = {
        engine = {
            context = context,
        },
    }
    hybrid_filter.init(env)
    env.filter_state.recent_committed = opts.recent_committed or ""
    env.filter_state.last_synced_commit_text = opts.last_synced_commit_text
    return env
end

local function run_filter(candidates, env)
    local yielded = {}
    _G.yield = function(cand)
        table.insert(yielded, cand)
    end
    hybrid_filter.func(make_input(candidates), env)
    _G.yield = nil
    return yielded
end

print("Testing hybrid_filter.lua...")
print("")

print("  english context promotes english candidates:")
do
    local env = make_env({
        options = { hybrid_mode = true },
        recent_committed = "hello world",
        input = "price",
    })
    local yielded = run_filter({
        make_candidate("价格", 0),
        make_candidate("price", 0),
    }, env)
    assert_eq(yielded[1].text, "price", "english candidate should rank first in english context")
end

print("  chinese context promotes chinese candidates:")
do
    local env = make_env({
        options = { hybrid_mode = true },
        recent_committed = "这是中文语境",
        input = "jia",
    })
    local yielded = run_filter({
        make_candidate("java", 0),
        make_candidate("家", 0),
    }, env)
    assert_eq(yielded[1].text, "家", "chinese candidate should rank first in chinese context")
end

print("  mixed context promotes tech terms:")
do
    local env = make_env({
        options = { hybrid_mode = true },
        recent_committed = "先把这个处理一下",
        input = "merge",
    })
    local yielded = run_filter({
        make_candidate("合并", 0),
        make_candidate("merge", 0, ""),
    }, env)
    assert_eq(yielded[1].text, "merge", "tech term should rank first in mixed context")
    assert_eq(yielded[1].comment, "⚙", "tech term should get comment marker when empty")
end

print("  hybrid mode off keeps original order:")
do
    local env = make_env({
        options = { hybrid_mode = false },
        recent_committed = "hello",
        input = "world",
    })
    local yielded = run_filter({
        make_candidate("世界", 0),
        make_candidate("world", 0),
    }, env)
    assert_eq(yielded[1].text, "世界", "original order should be preserved when hybrid mode is off")
end

print("")
print(string.format("Results: %d passed, %d failed, %d total",
    pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
