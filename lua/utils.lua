-- ============================================================
-- utils.lua — 程序猿输入法 工具函数库
-- 提供字符判断、UTF-8 操作、模式匹配等基础工具
-- ============================================================

local M = {}

-- ============================================================
-- 字符判断函数
-- ============================================================

--- 判断字符是否为中文汉字（CJK Unified Ideographs 基本区）
--- @param c string 单个 UTF-8 字符
--- @return boolean
function M.is_chinese_char(c)
    if not c or c == "" then return false end
    local byte = c:byte(1)
    -- UTF-8 中文汉字: 3字节编码，首字节 0xE4-0xE9（覆盖 U+4E00-U+9FFF）
    -- 也包含扩展区 CJK Ext A (U+3400-U+4DBF)
    if byte == nil then return false end
    if #c == 3 then
        local b1, b2, b3 = c:byte(1, 3)
        -- 计算 Unicode 码点
        local codepoint = (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
        -- CJK 基本区 U+4E00 ~ U+9FFF
        if codepoint >= 0x4E00 and codepoint <= 0x9FFF then return true end
        -- CJK 扩展A U+3400 ~ U+4DBF
        if codepoint >= 0x3400 and codepoint <= 0x4DBF then return true end
        -- CJK 兼容字 U+F900 ~ U+FAFF
        if codepoint >= 0xF900 and codepoint <= 0xFAFF then return true end
        -- 中文标点（部分）
        if codepoint >= 0x3000 and codepoint <= 0x303F then return true end
    end
    if #c == 4 then
        local b1, b2, b3, b4 = c:byte(1, 4)
        local codepoint = (b1 - 0xF0) * 262144 + (b2 - 0x80) * 4096 + (b3 - 0x80) * 64 + (b4 - 0x80)
        -- CJK 扩展B U+20000 ~ U+2A6DF
        if codepoint >= 0x20000 and codepoint <= 0x2A6DF then return true end
    end
    return false
end

--- 判断字符是否为中文标点
--- @param c string 单个字符
--- @return boolean
function M.is_chinese_punct(c)
    if not c or c == "" then return false end
    if #c < 3 then return false end
    -- Compute Unicode codepoint from UTF-8
    local codepoint = 0
    if #c == 3 then
        local b1, b2, b3 = c:byte(1, 3)
        codepoint = (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
    elseif #c == 2 then
        local b1, b2 = c:byte(1, 2)
        codepoint = (b1 - 0xC0) * 64 + (b2 - 0x80)
    else
        return false
    end
    -- Chinese punctuation codepoints
    -- U+FF0C ，  U+3002 。  U+FF1F ？  U+FF01 ！  U+FF1A ：  U+FF1B ；
    -- U+3001 、  U+2026 …  U+2014 —
    -- U+201C "  U+201D "  U+2018 '  U+2019 '
    -- U+FF08 （  U+FF09 ）  U+3010 【  U+3011 】  U+300A 《  U+300B 》
    -- U+FF5E ～  U+FF5C ｜
    local zh_puncts = {
        [0xFF0C] = true, [0x3002] = true, [0xFF1F] = true, [0xFF01] = true,
        [0xFF1A] = true, [0xFF1B] = true, [0x3001] = true, [0x2026] = true,
        [0x2014] = true, [0x201C] = true, [0x201D] = true, [0x2018] = true,
        [0x2019] = true, [0xFF08] = true, [0xFF09] = true, [0x3010] = true,
        [0x3011] = true, [0x300A] = true, [0x300B] = true, [0xFF5E] = true,
        [0xFF5C] = true,
    }
    return zh_puncts[codepoint] == true
end
--- 判断字符是否为 ASCII 字母
--- @param c string 单个字符
--- @return boolean
function M.is_ascii_letter(c)
    if not c or #c ~= 1 then return false end
    local b = c:byte(1)
    return (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
end

--- 判断字符是否为数字
--- @param c string 单个字符
--- @return boolean
function M.is_digit(c)
    if not c or #c ~= 1 then return false end
    local b = c:byte(1)
    return b >= 48 and b <= 57
end

--- 判断字符是否为 ASCII 标点
--- @param c string 单个字符
--- @return boolean
function M.is_ascii_punct(c)
    if not c or #c ~= 1 then return false end
    local puncts = ",.?!:;'\"-/\\()[]{}|~`@#$%^&*_+=<>"
    return puncts:find(c, 1, true) ~= nil
end

--- 判断字符是否为待决策标点（适用于中文自动替换）
--- @param c string 单个字符
--- @return boolean
function M.is_convertible_punct(c)
    local convertible = {",", ".", "?", "!", ":", ";", "$", "(", ")", "<", ">", "\"", "'", "[", "]", "{", "}"}
    for _, p in ipairs(convertible) do
        if c == p then return true end
    end
    return false
end

--- 判断字符是否为空白字符
--- @param c string
--- @return boolean
function M.is_whitespace(c)
    if not c then return false end
    return c == " " or c == "\t" or c == "\n" or c == "\r"
end

-- ============================================================
-- UTF-8 工具
-- ============================================================

--- 获取 UTF-8 字符串长度（按字符计数）
--- @param s string
--- @return number
function M.utf8_len(s)
    if not s then return 0 end
    local len = 0
    local i = 1
    while i <= #s do
        local byte = s:byte(i)
        if byte < 0x80 then
            i = i + 1
        elseif byte < 0xC0 then
            -- 无效起始字节，跳过
            i = i + 1
        elseif byte < 0xE0 then
            i = i + 2
        elseif byte < 0xF0 then
            i = i + 3
        else
            i = i + 4
        end
        len = len + 1
    end
    return len
end

--- 获取 UTF-8 字符串的最后一个字符
--- @param s string
--- @return string|nil
function M.utf8_last_char(s)
    if not s or s == "" then return nil end
    local i = #s
    while i > 0 do
        local byte = s:byte(i)
        if byte < 0x80 or byte >= 0xC0 then
            return s:sub(i)
        end
        i = i - 1
    end
    return s:sub(1, 1)
end

--- 获取 UTF-8 字符串的前 n 个字符
--- @param s string
--- @param n number
--- @return string
function M.utf8_sub(s, n)
    if not s or s == "" then return "" end
    local i = 1
    local count = 0
    while i <= #s and count < n do
        local byte = s:byte(i)
        if byte < 0x80 then
            i = i + 1
        elseif byte < 0xE0 then
            i = i + 2
        elseif byte < 0xF0 then
            i = i + 3
        else
            i = i + 4
        end
        count = count + 1
    end
    return s:sub(1, i - 1)
end

--- 迭代 UTF-8 字符
--- @param s string
--- @return function iterator
function M.utf8_chars(s)
    local i = 1
    return function()
        if i > #s then return nil end
        local byte = s:byte(i)
        local char_len
        if byte < 0x80 then
            char_len = 1
        elseif byte < 0xE0 then
            char_len = 2
        elseif byte < 0xF0 then
            char_len = 3
        else
            char_len = 4
        end
        local char = s:sub(i, i + char_len - 1)
        i = i + char_len
        return char
    end
end

-- ============================================================
-- 模式匹配
-- ============================================================

--- 检测字符串是否是 URL
--- @param s string
--- @return boolean
function M.is_url(s)
    if not s then return false end
    -- 检查常见 URL 前缀
    if s:match("^https?://") or s:match("^ftp://") or s:match("^mailto:") then
        return true
    end
    -- 检查域名模式 (xxx.xxx) — 排除版本号
    if s:match("^%a[%w%-]+%.%a[%w%.%-]*%a$") then
        return true
    end
    return false
end

--- 检测字符串是否是文件路径
--- @param s string
--- @return boolean
function M.is_filepath(s)
    if not s then return false end
    if s:match("^~/") or s:match("^%./") or s:match("^%.%./") or s:match("^/[%w_]") then
        return true
    end
    return false
end

--- 检测字符串是否是邮箱
--- @param s string
--- @return boolean
function M.is_email(s)
    if not s then return false end
    return s:match("^[%w%.%+%-_]+@[%w%.%-]+%.[%a]+$") ~= nil
end

--- 检测字符串是否是命令行选项
--- @param s string
--- @return boolean
function M.is_cli_flag(s)
    if not s then return false end
    return s:match("^%-%-?[%w]") ~= nil
end

--- 检测字符串是否是变量名 (snake_case, camelCase, PascalCase)
--- @param s string
--- @return boolean
function M.is_variable_name(s)
    if not s then return false end
    -- snake_case: 包含下划线
    if s:match("^[%a_][%w_]*$") and s:find("_") then return true end
    -- camelCase: 小写开头+后续有大写
    if s:match("^%l[%w]*%u") then return true end
    -- PascalCase: 大写开头+后续有小写再有大写
    if s:match("^%u%l+%u") then return true end
    return false
end

--- 检测字符串是否是版本号
--- @param s string
--- @return boolean
function M.is_version(s)
    if not s then return false end
    return s:match("^v?%d+%.%d+") ~= nil
end

--- 检测字符串是否是数字序列（包括小数、版本号）
--- @param s string
--- @return boolean
function M.is_number_sequence(s)
    if not s then return false end
    return s:match("^%d[%d%.]*$") ~= nil
end

-- ============================================================
-- 标点映射
-- ============================================================

--- 半角标点到中文全角标点的映射
M.punct_map = {
    [","] = "，",
    ["."] = "。",
    ["?"] = "？",
    ["!"] = "！",
    [":"] = "：",
    [";"] = "；",
    ["$"] = "￥",
    ["("] = "（",
    [")"] = "）",
    ["<"] = "《",
    [">"] = "》",
    ["["] = "【",
    ["]"] = "】",
    ["{"] = "｛",
    ["}"] = "｝",
}

M.quote_pair_map = {
    ["\""] = { open = "“", close = "”" },
    ["'"] = { open = "‘", close = "’" },
}

M.auto_pair_map = {
    ["("] = { open = "(", close = ")" },
    ["["] = { open = "[", close = "]" },
    ["{"] = { open = "{", close = "}" },
    ["\""] = { open = "\"", close = "\"" },
    ["'"] = { open = "'", close = "'" },
}

M.chinese_auto_pair_map = {
    ["（"] = "）",
    ["【"] = "】",
    ["｛"] = "｝",
    ["《"] = "》",
    ["“"] = "”",
    ["‘"] = "’",
}

local function count_utf8_char(text, target)
    local count = 0
    for char in M.utf8_chars(text or "") do
        if char == target then
            count = count + 1
        end
    end
    return count
end

--- 获取对应中文标点
--- @param half_punct string 半角标点
--- @param recent_text string|nil 近期已提交文本
--- @return string|nil 对应的全角中文标点
function M.get_chinese_punct(half_punct, recent_text)
    local quote_pair = M.quote_pair_map[half_punct]
    if quote_pair then
        local open_count = count_utf8_char(recent_text, quote_pair.open)
        local close_count = count_utf8_char(recent_text, quote_pair.close)
        if open_count <= close_count then
            return quote_pair.open
        end
        return quote_pair.close
    end
    return M.punct_map[half_punct]
end

--- 判断当前输入是否应该触发成对补全
--- @param input_punct string 原始输入的半角符号
--- @param output_punct string 最终要提交的单个符号
--- @return boolean
function M.should_auto_pair(input_punct, output_punct)
    if not input_punct or not output_punct then
        return false
    end

    if input_punct == "<" then
        return output_punct == "《"
    end

    local ascii_pair = M.auto_pair_map[input_punct]
    if ascii_pair and ascii_pair.open == output_punct then
        return true
    end

    return M.chinese_auto_pair_map[output_punct] ~= nil
end

--- 根据当前开符号获取闭符号
--- @param input_punct string 原始输入的半角符号
--- @param output_punct string 最终要提交的开符号
--- @return string|nil
function M.get_pair_close(input_punct, output_punct)
    if not input_punct or not output_punct then
        return nil
    end

    local chinese_close = M.chinese_auto_pair_map[output_punct]
    if chinese_close then
        return chinese_close
    end

    local ascii_pair = M.auto_pair_map[input_punct]
    if ascii_pair and ascii_pair.open == output_punct then
        return ascii_pair.close
    end

    return nil
end

-- ============================================================
-- 字符串工具
-- ============================================================

--- 去除字符串首尾空白
--- @param s string
--- @return string
function M.trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$")
end

--- 判断字符串是否为空或仅空白
--- @param s string
--- @return boolean
function M.is_empty(s)
    return not s or M.trim(s) == ""
end

return M
