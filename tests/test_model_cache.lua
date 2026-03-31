-- ============================================================
-- test_model_cache.lua — model_cache.lua 单元测试
-- 运行: lua tests/test_model_cache.lua
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
local model_cache = require("model_cache")

print("Testing model_cache.lua...")
print("")

print("  cache hit returns stored value:")
do
    local now = 100
    local cache = model_cache.new({
        now = function()
            return now
        end,
    })
    model_cache.put(cache, "ctx", "cached", 800)
    assert_eq(model_cache.get(cache, "ctx"), "cached", "cached value should be returned before ttl")
end

print("  cache entry expires after ttl:")
do
    local now = 100
    local cache = model_cache.new({
        now = function()
            return now
        end,
    })
    model_cache.put(cache, "ctx", "cached", 800)
    now = 102
    assert_eq(model_cache.get(cache, "ctx"), nil, "cache should expire after ttl window")
end

print("")
print(string.format("Results: %d passed, %d failed, %d total",
    pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
