-- ============================================================
-- test_utils.lua — utils.lua 单元测试
-- 运行: lua tests/test_utils.lua
-- ============================================================

-- 简易测试框架
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

local function assert_false(value, msg)
    assert_eq(value, false, msg)
end

-- 加载模块（设置 package.path）
package.path = package.path .. ";lua/?.lua"
local utils = require("utils")

print("Testing utils.lua...")
print("")

-- ============================================================
-- is_chinese_char 测试
-- ============================================================
print("  is_chinese_char:")
assert_true(utils.is_chinese_char("中"), "中")
assert_true(utils.is_chinese_char("文"), "文")
assert_true(utils.is_chinese_char("汉"), "汉")
assert_false(utils.is_chinese_char("a"), "a is not chinese")
assert_false(utils.is_chinese_char("1"), "1 is not chinese")
assert_false(utils.is_chinese_char("."), ". is not chinese")
assert_false(utils.is_chinese_char(""), "empty string")
assert_false(utils.is_chinese_char(nil), "nil")

-- ============================================================
-- is_ascii_letter 测试
-- ============================================================
print("  is_ascii_letter:")
assert_true(utils.is_ascii_letter("a"), "a")
assert_true(utils.is_ascii_letter("Z"), "Z")
assert_false(utils.is_ascii_letter("1"), "1")
assert_false(utils.is_ascii_letter("中"), "中")
assert_false(utils.is_ascii_letter(""), "empty")

-- ============================================================
-- is_digit 测试
-- ============================================================
print("  is_digit:")
assert_true(utils.is_digit("0"), "0")
assert_true(utils.is_digit("9"), "9")
assert_false(utils.is_digit("a"), "a")
assert_false(utils.is_digit(""), "empty")

-- ============================================================
-- is_convertible_punct 测试
-- ============================================================
print("  is_convertible_punct:")
assert_true(utils.is_convertible_punct(","), "comma")
assert_true(utils.is_convertible_punct("."), "period")
assert_true(utils.is_convertible_punct("?"), "question")
assert_true(utils.is_convertible_punct("!"), "exclamation")
assert_true(utils.is_convertible_punct(":"), "colon")
assert_true(utils.is_convertible_punct(";"), "semicolon")
assert_false(utils.is_convertible_punct("'"), "single quote - not convertible in MVP")
assert_false(utils.is_convertible_punct("\""), "double quote - not convertible in MVP")
assert_false(utils.is_convertible_punct("("), "parenthesis - not convertible in MVP")

-- ============================================================
-- UTF-8 工具测试
-- ============================================================
print("  utf8_len:")
assert_eq(utils.utf8_len("hello"), 5, "ascii string")
assert_eq(utils.utf8_len("你好"), 2, "chinese string")
assert_eq(utils.utf8_len("hello你好"), 7, "mixed string")
assert_eq(utils.utf8_len(""), 0, "empty string")

print("  utf8_last_char:")
assert_eq(utils.utf8_last_char("hello"), "o", "ascii last char")
assert_eq(utils.utf8_last_char("你好"), "好", "chinese last char")
assert_eq(utils.utf8_last_char("hello你"), "你", "mixed last char")
assert_eq(utils.utf8_last_char("a"), "a", "single char")

-- ============================================================
-- URL / Path / Email / Variable 检测
-- ============================================================
print("  is_url:")
assert_true(utils.is_url("https://example.com"), "https url")
assert_true(utils.is_url("http://localhost:3000"), "http localhost")
assert_true(utils.is_url("ftp://files.example.com"), "ftp url")
assert_false(utils.is_url("hello"), "not url")
assert_false(utils.is_url(""), "empty not url")

print("  is_filepath:")
assert_true(utils.is_filepath("~/Downloads/test"), "home path")
assert_true(utils.is_filepath("./config.yaml"), "relative path")
assert_true(utils.is_filepath("../parent/file"), "parent path")
assert_true(utils.is_filepath("/usr/local/bin"), "absolute path")
assert_false(utils.is_filepath("hello"), "not path")

print("  is_email:")
assert_true(utils.is_email("user@example.com"), "valid email")
assert_true(utils.is_email("test.user+tag@domain.co.uk"), "complex email")
assert_false(utils.is_email("not-email"), "not email")
assert_false(utils.is_email("@missing"), "invalid email")

print("  is_variable_name:")
assert_true(utils.is_variable_name("user_id"), "snake_case")
assert_true(utils.is_variable_name("refreshToken"), "camelCase")
assert_true(utils.is_variable_name("MyClass"), "PascalCase — has lower then upper")
assert_false(utils.is_variable_name("hello"), "plain word — not variable")
assert_false(utils.is_variable_name("123"), "number — not variable")

print("  is_cli_flag:")
assert_true(utils.is_cli_flag("--force"), "long flag")
assert_true(utils.is_cli_flag("-v"), "short flag")
assert_false(utils.is_cli_flag("hello"), "not flag")

print("  is_version:")
assert_true(utils.is_version("v1.2.3"), "version with v")
assert_true(utils.is_version("1.2.3"), "version without v")
assert_true(utils.is_version("v2.0"), "short version")
assert_false(utils.is_version("hello"), "not version")

-- ============================================================
-- 标点映射测试
-- ============================================================
print("  get_chinese_punct:")
assert_eq(utils.get_chinese_punct(","), "，", "comma mapping")
assert_eq(utils.get_chinese_punct("."), "。", "period mapping")
assert_eq(utils.get_chinese_punct("?"), "？", "question mapping")
assert_eq(utils.get_chinese_punct("!"), "！", "exclamation mapping")
assert_eq(utils.get_chinese_punct(":"), "：", "colon mapping")
assert_eq(utils.get_chinese_punct(";"), "；", "semicolon mapping")
assert_eq(utils.get_chinese_punct("'"), nil, "single quote — no mapping")

-- ============================================================
-- 结果汇总
-- ============================================================
print("")
print(string.format("Results: %d passed, %d failed, %d total",
    pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
