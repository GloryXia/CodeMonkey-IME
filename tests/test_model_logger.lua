-- ============================================================
-- test_model_logger.lua — model_logger.lua 单元测试
-- 运行: lua tests/test_model_logger.lua
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

local function assert_true(value, msg)
    assert_eq(value, true, msg)
end

package.path = package.path .. ";lua/?.lua"
local logger = require("model_logger")

print("Testing model_logger.lua...")
print("")

print("  encode_json:")
do
    local encoded = logger.encode_json({
        event = "commit_observed",
        ok = true,
        count = 2,
        nested = { "a", "b" },
    })
    assert_eq(encoded, '{"count":2,"event":"commit_observed","nested":["a","b"],"ok":true}', "json encoding is stable")
end

print("  append_event with custom writer:")
do
    local lines = {}
    local ok = logger.append_event({
        event = "context_score_requested",
    }, {
        now = 123456,
        writer = function(line)
            lines[#lines + 1] = line
        end,
    })
    assert_true(ok, "append_event should succeed with custom writer")
    assert_eq(lines[1], '{"event":"context_score_requested","ts":123456}\n', "writer receives jsonl line")
end

print("")
print(string.format("Results: %d passed, %d failed, %d total",
    pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
