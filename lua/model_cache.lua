-- ============================================================
-- model_cache.lua — 轻量 TTL 缓存
-- 用于 sidecar 请求的短时结果缓存，避免重复阻塞
-- ============================================================

local M = {}

local function now_seconds(cache)
    local provider = cache and cache.now or os.time
    return provider()
end

local function ttl_to_seconds(ttl_ms)
    local ttl = tonumber(ttl_ms) or 0
    if ttl <= 0 then
        return 1
    end
    return math.max(1, math.ceil(ttl / 1000))
end

function M.new(opts)
    opts = opts or {}
    return {
        now = opts.now or os.time,
        entries = {},
    }
end

function M.get(cache, key)
    local entry = cache.entries[key]
    if not entry then
        return nil
    end

    if entry.expires_at < now_seconds(cache) then
        cache.entries[key] = nil
        return nil
    end

    return entry.value
end

function M.put(cache, key, value, ttl_ms)
    cache.entries[key] = {
        value = value,
        expires_at = now_seconds(cache) + ttl_to_seconds(ttl_ms),
    }
    return value
end

function M.clear(cache)
    cache.entries = {}
end

return M
