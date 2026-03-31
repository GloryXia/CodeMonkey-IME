-- ============================================================
-- model_logger.lua — 本地模型埋点日志
-- 以 JSONL 形式记录模型请求和用户行为，全部保留在本机
-- ============================================================

local M = {}

local function escape_json_string(value)
    local replacements = {
        ['\\'] = '\\\\',
        ['"'] = '\\"',
        ['\b'] = '\\b',
        ['\f'] = '\\f',
        ['\n'] = '\\n',
        ['\r'] = '\\r',
        ['\t'] = '\\t',
    }

    return value:gsub('[%z\1-\31\\"]', function(char)
        return replacements[char] or string.format("\\u%04x", char:byte())
    end)
end

local function is_array(tbl)
    local max_index = 0
    local count = 0

    for key, _ in pairs(tbl) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        if key > max_index then
            max_index = key
        end
        count = count + 1
    end

    return max_index == count
end

local function sorted_keys(tbl)
    local keys = {}
    for key, _ in pairs(tbl) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

function M.encode_json(value)
    local value_type = type(value)

    if value == nil then
        return "null"
    end

    if value_type == "boolean" then
        return value and "true" or "false"
    end

    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        return tostring(value)
    end

    if value_type == "string" then
        return '"' .. escape_json_string(value) .. '"'
    end

    if value_type == "table" then
        if is_array(value) then
            local items = {}
            for index = 1, #value do
                items[#items + 1] = M.encode_json(value[index])
            end
            return "[" .. table.concat(items, ",") .. "]"
        end

        local items = {}
        for _, key in ipairs(sorted_keys(value)) do
            items[#items + 1] = M.encode_json(tostring(key)) .. ":" .. M.encode_json(value[key])
        end
        return "{" .. table.concat(items, ",") .. "}"
    end

    return M.encode_json(tostring(value))
end

function M.default_log_path()
    local home = os.getenv("HOME")
    if home and home ~= "" then
        return home .. "/Library/Rime/hybrid_ime_model_events.jsonl"
    end
    return "/tmp/hybrid_ime_model_events.jsonl"
end

function M.append_event(event, opts)
    opts = opts or {}

    local payload = {}
    for key, value in pairs(event or {}) do
        payload[key] = value
    end
    if payload.ts == nil then
        payload.ts = opts.now or os.time()
    end

    local line = M.encode_json(payload) .. "\n"

    if opts.writer then
        opts.writer(line)
        return true
    end

    local path = opts.path or M.default_log_path()
    local file, err = io.open(path, "a")
    if not file then
        return false, err or "open_failed"
    end

    local ok, write_err = pcall(function()
        file:write(line)
        file:close()
    end)
    if not ok then
        pcall(function()
            file:close()
        end)
        return false, write_err
    end

    return true
end

return M
