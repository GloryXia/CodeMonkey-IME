-- ============================================================
-- model_json.lua — 极简 JSON 编解码辅助
-- 仅用于本地 sidecar 请求/响应，不依赖第三方库
-- ============================================================

local M = {}

local function decode_error(index, reason)
    return nil, string.format("json_decode_error@%d:%s", index or 0, reason or "invalid")
end

local function skip_ws(text, index)
    local length = #text
    while index <= length do
        local char = text:sub(index, index)
        if char ~= " " and char ~= "\n" and char ~= "\r" and char ~= "\t" then
            break
        end
        index = index + 1
    end
    return index
end

local function unicode_to_utf8(codepoint)
    if utf8 and utf8.char then
        local ok, value = pcall(function()
            return utf8.char(codepoint)
        end)
        if ok and value then
            return value
        end
    end
    if codepoint <= 0x7F then
        return string.char(codepoint)
    end
    return "?"
end

local parse_value

local function parse_string(text, index)
    local parts = {}
    index = index + 1

    while index <= #text do
        local char = text:sub(index, index)
        if char == "\"" then
            return table.concat(parts), index + 1
        end

        if char == "\\" then
            local esc = text:sub(index + 1, index + 1)
            if esc == "\"" or esc == "\\" or esc == "/" then
                parts[#parts + 1] = esc
                index = index + 2
            elseif esc == "b" then
                parts[#parts + 1] = "\b"
                index = index + 2
            elseif esc == "f" then
                parts[#parts + 1] = "\f"
                index = index + 2
            elseif esc == "n" then
                parts[#parts + 1] = "\n"
                index = index + 2
            elseif esc == "r" then
                parts[#parts + 1] = "\r"
                index = index + 2
            elseif esc == "t" then
                parts[#parts + 1] = "\t"
                index = index + 2
            elseif esc == "u" then
                local hex = text:sub(index + 2, index + 5)
                if #hex ~= 4 or not hex:match("^[0-9a-fA-F]+$") then
                    return decode_error(index, "invalid_unicode_escape")
                end
                parts[#parts + 1] = unicode_to_utf8(tonumber(hex, 16))
                index = index + 6
            else
                return decode_error(index, "invalid_escape")
            end
        else
            parts[#parts + 1] = char
            index = index + 1
        end
    end

    return decode_error(index, "unterminated_string")
end

local function parse_number(text, index)
    local rest = text:sub(index)
    local token = rest:match("^-?%d+%.?%d*[eE]?[+-]?%d*")
    if not token or token == "" or token == "-" then
        return decode_error(index, "invalid_number")
    end

    local value = tonumber(token)
    if value == nil then
        return decode_error(index, "invalid_number")
    end

    return value, index + #token
end

local function parse_array(text, index)
    local result = {}
    index = index + 1
    index = skip_ws(text, index)

    if text:sub(index, index) == "]" then
        return result, index + 1
    end

    while index <= #text do
        local value, next_index = parse_value(text, index)
        if next_index == nil then
            return value, next_index
        end
        result[#result + 1] = value
        index = skip_ws(text, next_index)

        local char = text:sub(index, index)
        if char == "]" then
            return result, index + 1
        end
        if char ~= "," then
            return decode_error(index, "expected_array_separator")
        end
        index = skip_ws(text, index + 1)
    end

    return decode_error(index, "unterminated_array")
end

local function parse_object(text, index)
    local result = {}
    index = index + 1
    index = skip_ws(text, index)

    if text:sub(index, index) == "}" then
        return result, index + 1
    end

    while index <= #text do
        if text:sub(index, index) ~= "\"" then
            return decode_error(index, "expected_object_key")
        end

        local key, key_index = parse_string(text, index)
        if key_index == nil then
            return key, key_index
        end

        index = skip_ws(text, key_index)
        if text:sub(index, index) ~= ":" then
            return decode_error(index, "expected_colon")
        end

        index = skip_ws(text, index + 1)
        local value, next_index = parse_value(text, index)
        if next_index == nil then
            return value, next_index
        end
        result[key] = value
        index = skip_ws(text, next_index)

        local char = text:sub(index, index)
        if char == "}" then
            return result, index + 1
        end
        if char ~= "," then
            return decode_error(index, "expected_object_separator")
        end
        index = skip_ws(text, index + 1)
    end

    return decode_error(index, "unterminated_object")
end

parse_value = function(text, index)
    index = skip_ws(text, index)
    local char = text:sub(index, index)

    if char == "" then
        return decode_error(index, "unexpected_eof")
    end
    if char == "\"" then
        return parse_string(text, index)
    end
    if char == "{" then
        return parse_object(text, index)
    end
    if char == "[" then
        return parse_array(text, index)
    end
    if char == "t" and text:sub(index, index + 3) == "true" then
        return true, index + 4
    end
    if char == "f" and text:sub(index, index + 4) == "false" then
        return false, index + 5
    end
    if char == "n" and text:sub(index, index + 3) == "null" then
        return nil, index + 4
    end
    return parse_number(text, index)
end

function M.decode(text)
    if type(text) ~= "string" then
        return nil, "json_decode_error@0:non_string"
    end

    local value, index = parse_value(text, 1)
    if index == nil then
        return value, index
    end

    index = skip_ws(text, index)
    if index <= #text then
        return decode_error(index, "trailing_garbage")
    end
    return value
end

return M
