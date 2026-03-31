-- ============================================================
-- model_sidecar_client.lua — 本地 sidecar 请求客户端
-- 默认通过 curl 调本机 HTTP stub；缺失或失败时安全回退
-- ============================================================

local json = require("model_json")
local logger = require("model_logger")

local M = {}

local function shell_quote(value)
    return "'" .. tostring(value or ""):gsub("'", "'\"'\"'") .. "'"
end

local function request_timeout_seconds(timeout_ms)
    local ms = tonumber(timeout_ms) or 15
    if ms < 1 then
        ms = 1
    end
    return string.format("%.3f", ms / 1000)
end

local function default_transport(request, opts)
    local body = logger.encode_json(request)
    local endpoint = opts.endpoint or "http://127.0.0.1:39571/score_context"
    local command = string.format(
        "printf %%s %s | /usr/bin/curl --silent --show-error --fail --max-time %s -H 'Content-Type: application/json' --data-binary @- %s 2>/dev/null",
        shell_quote(body),
        request_timeout_seconds(opts.timeout_ms),
        shell_quote(endpoint)
    )

    local pipe = io.popen(command, "r")
    if not pipe then
        return nil, "transport_unavailable"
    end

    local response = pipe:read("*a") or ""
    local ok = pipe:close()
    if ok == nil or ok == false or response == "" then
        return nil, "transport_failed"
    end

    local decoded, err = json.decode(response)
    if not decoded then
        return nil, err or "decode_failed"
    end

    return decoded
end

function M.request(request, opts)
    opts = opts or {}
    local transport = opts.transport or default_transport
    return transport(request, opts)
end

return M
