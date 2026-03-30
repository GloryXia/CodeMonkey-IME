-- ============================================================
-- test_context_detector.lua — context_detector.lua 单元测试
-- 运行: lua tests/test_context_detector.lua
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

local function assert_false(value, msg)
    assert_eq(value, false, msg)
end

package.path = package.path .. ";lua/?.lua"
local detector = require("context_detector")

print("Testing context_detector.lua...")
print("")

-- ============================================================
-- Token 分类测试
-- ============================================================
print("  classify_token:")

-- URL
assert_eq(detector.classify_token("https://example.com"), detector.TOKEN_PATH_URL, "url https")
assert_eq(detector.classify_token("http://localhost:3000"), detector.TOKEN_PATH_URL, "url http")
assert_eq(detector.classify_token("ftp://files.com"), detector.TOKEN_PATH_URL, "url ftp")

-- 路径
assert_eq(detector.classify_token("~/Downloads/test"), detector.TOKEN_PATH_URL, "path home")
assert_eq(detector.classify_token("./config.yaml"), detector.TOKEN_PATH_URL, "path relative")
assert_eq(detector.classify_token("/usr/local/bin"), detector.TOKEN_PATH_URL, "path absolute")

-- 命令行 flag
assert_eq(detector.classify_token("--force"), detector.TOKEN_COMMAND, "flag --force")
assert_eq(detector.classify_token("-v"), detector.TOKEN_COMMAND, "flag -v")

-- 版本号
assert_eq(detector.classify_token("v1.2.3"), detector.TOKEN_NUMBER, "version v1.2.3")
assert_eq(detector.classify_token("2.0.1"), detector.TOKEN_NUMBER, "version 2.0.1")

-- 纯数字
assert_eq(detector.classify_token("12345"), detector.TOKEN_NUMBER, "number 12345")

-- 变量名
assert_eq(detector.classify_token("user_id"), detector.TOKEN_CODE, "var snake_case")
assert_eq(detector.classify_token("refreshToken"), detector.TOKEN_CODE, "var camelCase")

-- 技术术语
assert_eq(detector.classify_token("React"), detector.TOKEN_TECH_TERM, "tech React")
assert_eq(detector.classify_token("docker"), detector.TOKEN_TECH_TERM, "tech docker")
assert_eq(detector.classify_token("API"), detector.TOKEN_TECH_TERM, "tech API")
assert_eq(detector.classify_token("npm"), detector.TOKEN_TECH_TERM, "tech npm")
assert_eq(detector.classify_token("git"), detector.TOKEN_TECH_TERM, "tech git")
assert_eq(detector.classify_token("token"), detector.TOKEN_TECH_TERM, "tech token")

-- 英文
assert_eq(detector.classify_token("hello"), detector.TOKEN_EN_TEXT, "english hello")
assert_eq(detector.classify_token("world"), detector.TOKEN_EN_TEXT, "english world")

-- ============================================================
-- 保护模式测试
-- ============================================================
print("  is_protected:")

local protected, reason

protected, reason = detector.is_protected("", "https://example.com")
assert_true(protected, "url protected")
assert_eq(reason, "url", "url reason")

protected, reason = detector.is_protected("", "~/Downloads/test")
assert_true(protected, "path protected")
assert_eq(reason, "filepath", "filepath reason")

protected, reason = detector.is_protected("", "--force")
assert_true(protected, "flag protected")
assert_eq(reason, "cli_flag", "cli_flag reason")

protected, reason = detector.is_protected("", "user_id")
assert_true(protected, "variable protected")
assert_eq(reason, "variable", "variable reason")

protected, reason = detector.is_protected("你好", "")
assert_false(protected, "chinese not protected")

protected, reason = detector.is_protected("", "hello")
assert_false(protected, "simple english not protected")

-- ============================================================
-- 上一字符类型测试
-- ============================================================
print("  get_prev_char_type:")

assert_eq(detector.get_prev_char_type("中"), "chinese", "chinese char")
assert_eq(detector.get_prev_char_type("。"), "chinese", "chinese punct → chinese context")
assert_eq(detector.get_prev_char_type("a"), "english", "english char")
assert_eq(detector.get_prev_char_type("Z"), "english", "english upper")
assert_eq(detector.get_prev_char_type("5"), "number", "digit")
assert_eq(detector.get_prev_char_type("."), "punct", "ascii punct")
assert_eq(detector.get_prev_char_type(""), "unknown", "empty")

-- ============================================================
-- 语言上下文检测测试
-- ============================================================
print("  detect_language_context:")

assert_eq(detector.detect_language_context("你好世界这是中文"), "chinese", "chinese text")
assert_eq(detector.detect_language_context("hello world this is english"), "english", "english text")
assert_eq(detector.detect_language_context("你好 hello 世界 world"), "mixed", "mixed text")
assert_eq(detector.detect_language_context(""), "mixed", "empty text → mixed")

-- ============================================================
-- 验收语料场景测试
-- ============================================================
print("  PRD 验收语料 token 分类:")

-- 保护样例（PRD §23 语料 E）
assert_eq(detector.classify_token("user_id"), detector.TOKEN_CODE, "corpus: user_id")
-- refreshToken() 需要去掉括号才能正确分类
assert_eq(detector.classify_token("refreshToken"), detector.TOKEN_CODE, "corpus: refreshToken")
assert_eq(detector.classify_token("https://example.com/api/v1"), detector.TOKEN_PATH_URL, "corpus: url")
assert_eq(detector.classify_token("~/Downloads/test"), detector.TOKEN_PATH_URL, "corpus: path")
assert_eq(detector.classify_token("--force"), detector.TOKEN_COMMAND, "corpus: flag")
assert_eq(detector.classify_token("v1.2.3"), detector.TOKEN_NUMBER, "corpus: version")

-- ============================================================
-- 结果汇总
-- ============================================================
print("")
print(string.format("Results: %d passed, %d failed, %d total",
    pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
