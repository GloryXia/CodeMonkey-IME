-- ============================================================
-- context_detector.lua — 上下文检测器
-- 根据已上屏文本和当前组合态判断 token 类型与保护模式
-- ============================================================

local utils = require("utils")

local M = {}

-- ============================================================
-- Token 类型常量
-- ============================================================
M.TOKEN_ZH_TEXT      = "zh_text"         -- 中文自然文本
M.TOKEN_EN_TEXT      = "en_text"         -- 英文自然文本
M.TOKEN_TECH_TERM   = "tech_term"       -- 技术术语
M.TOKEN_CODE         = "code_token"      -- 变量名/函数名/类名
M.TOKEN_COMMAND      = "command_token"   -- 命令/参数
M.TOKEN_PATH_URL     = "path_or_url"    -- 路径/URL/邮箱
M.TOKEN_NUMBER       = "number_token"    -- 数字/版本号
M.TOKEN_SYMBOL       = "symbol_pending"  -- 待决策标点
M.TOKEN_MIXED        = "mixed_phrase"    -- 中英混合短语
M.TOKEN_UNKNOWN      = "unknown"

-- ============================================================
-- 上下文状态
-- ============================================================
M.CTX_NORMAL         = "normal"          -- 普通输入
M.CTX_PROTECTED      = "protected"       -- 保护模式（禁止智能变换）
M.CTX_CODE_EDITOR    = "code_editor"     -- 代码编辑器上下文
M.CTX_TERMINAL       = "terminal"        -- 终端上下文
M.CTX_CHAT           = "chat"            -- 聊天上下文
M.CTX_DOCUMENT       = "document"        -- 文档上下文

-- ============================================================
-- 高频技术术语列表（用于 token 类型判断辅助）
-- 完整词库在 dict 文件中，这里保留高频词用于快速匹配
-- ============================================================
local tech_terms_set = {}
local tech_terms = {
    -- 编程语言
    "python", "javascript", "typescript", "java", "golang", "rust",
    "swift", "kotlin", "ruby", "php", "scala", "lua", "sql",
    "html", "css", "json", "yaml", "xml", "markdown",
    -- 框架/工具
    "react", "vue", "angular", "next", "nuxt", "vite", "webpack",
    "node", "deno", "bun", "flask", "django", "spring", "express",
    "docker", "kubernetes", "nginx", "redis", "mysql", "postgres",
    "mongodb", "graphql", "grpc", "kafka",
    -- 通用术语
    "api", "sdk", "cli", "gui", "ide", "orm", "mvp", "poc",
    "ci", "cd", "devops", "saas", "paas", "iaas",
    "git", "npm", "pip", "cargo", "brew", "yarn", "pnpm",
    "token", "auth", "oauth", "jwt", "csrf", "cors",
    "config", "env", "debug", "log", "logger", "test",
    "deploy", "build", "compile", "lint", "format",
    "merge", "rebase", "commit", "push", "pull", "fetch",
    "branch", "tag", "release", "hotfix",
    "bug", "fix", "patch", "issue", "pr", "review",
    "refactor", "optimize", "cache", "queue", "stack",
    "thread", "process", "async", "await", "promise",
    "callback", "middleware", "handler", "controller",
    "model", "view", "router", "plugin", "module",
    "import", "export", "require", "include",
    "interface", "abstract", "class", "struct", "enum",
    "function", "method", "property", "attribute",
    "string", "number", "boolean", "array", "object",
    "null", "undefined", "void", "type", "generic",
    "http", "https", "tcp", "udp", "websocket", "rest",
    "url", "uri", "dns", "ip", "port", "proxy",
    "frontend", "backend", "fullstack", "microservice",
    "container", "pod", "cluster", "namespace",
    "pipeline", "workflow", "action", "trigger",
    "timeout", "retry", "fallback", "circuit",
    "encrypt", "decrypt", "hash", "salt", "signature",
}

for _, term in ipairs(tech_terms) do
    tech_terms_set[term] = true
end

-- ============================================================
-- 核心检测函数
-- ============================================================

--- 判断文本片段的 token 类型
--- @param text string 当前输入文本片段
--- @return string token_type
function M.classify_token(text)
    if not text or text == "" then
        return M.TOKEN_UNKNOWN
    end

    local trimmed = utils.trim(text)
    local lower = trimmed:lower()

    -- 1. 路径 / URL / 邮箱 检测（最高优先级保护）
    if utils.is_url(trimmed) then
        return M.TOKEN_PATH_URL
    end
    if utils.is_filepath(trimmed) then
        return M.TOKEN_PATH_URL
    end
    if utils.is_email(trimmed) then
        return M.TOKEN_PATH_URL
    end

    -- 2. 命令行 flag
    if utils.is_cli_flag(trimmed) then
        return M.TOKEN_COMMAND
    end

    -- 3. 版本号
    if utils.is_version(trimmed) then
        return M.TOKEN_NUMBER
    end

    -- 4. 纯数字序列
    if utils.is_number_sequence(trimmed) then
        return M.TOKEN_NUMBER
    end

    -- 5. 变量名模式（snake_case, camelCase）
    if utils.is_variable_name(trimmed) then
        return M.TOKEN_CODE
    end

    -- 6. 技术术语
    if tech_terms_set[lower] then
        return M.TOKEN_TECH_TERM
    end

    -- 7. 纯 ASCII 字母
    if trimmed:match("^[a-zA-Z]+$") then
        return M.TOKEN_EN_TEXT
    end

    -- 8. 中文字符开头
    local first_char = nil
    for c in utils.utf8_chars(trimmed) do
        first_char = c
        break
    end
    if first_char and utils.is_chinese_char(first_char) then
        return M.TOKEN_ZH_TEXT
    end

    -- 9. 混合内容
    local has_zh = false
    local has_en = false
    for c in utils.utf8_chars(trimmed) do
        if utils.is_chinese_char(c) then has_zh = true end
        if utils.is_ascii_letter(c) then has_en = true end
    end
    if has_zh and has_en then
        return M.TOKEN_MIXED
    end

    return M.TOKEN_UNKNOWN
end

--- 检测当前上下文是否处于保护模式
--- 保护模式下禁止所有智能变换（标点替换、自动空格等）
--- @param commit_text string 已上屏文本（最近一段）
--- @param input string 当前组合态输入
--- @return boolean is_protected
--- @return string reason 保护原因
function M.is_protected(commit_text, input)
    local text = (commit_text or "") .. (input or "")

    if utils.is_empty(text) then
        return false, ""
    end

    -- 检查是否在 URL 中
    if utils.is_url(text) then
        return true, "url"
    end

    -- 检查是否在路径中
    if utils.is_filepath(text) then
        return true, "filepath"
    end

    -- 检查是否在邮箱中
    if utils.is_email(text) then
        return true, "email"
    end

    -- 检查是否在命令行 flag 中
    if utils.is_cli_flag(text) then
        return true, "cli_flag"
    end

    -- 检查是否在变量名中
    if utils.is_variable_name(text) then
        return true, "variable"
    end

    -- 检查是否在版本号中
    if utils.is_version(text) then
        return true, "version"
    end

    return false, ""
end

--- 根据最后一个已上屏字符判断当前语境（简化版本）
--- @param last_char string 最后一个已提交的字符
--- @return string "chinese" | "english" | "number" | "punct" | "unknown"
function M.get_prev_char_type(last_char)
    if not last_char or last_char == "" then
        return "unknown"
    end

    if utils.is_chinese_char(last_char) then
        return "chinese"
    end

    if utils.is_chinese_punct(last_char) then
        return "chinese"  -- 中文标点后仍视为中文语境
    end

    if utils.is_ascii_letter(last_char) then
        return "english"
    end

    if utils.is_digit(last_char) then
        return "number"
    end

    if utils.is_ascii_punct(last_char) then
        return "punct"
    end

    return "unknown"
end

--- 检测近期文本的主要语言
--- 通过统计中英字符比例判断
--- @param text string 近期已上屏文本
--- @return string "chinese" | "english" | "mixed"
function M.detect_language_context(text)
    if utils.is_empty(text) then
        return "mixed"
    end

    local zh_count = 0
    local en_count = 0

    for c in utils.utf8_chars(text) do
        if utils.is_chinese_char(c) or utils.is_chinese_punct(c) then
            zh_count = zh_count + 1
        elseif utils.is_ascii_letter(c) then
            en_count = en_count + 1
        end
    end

    -- Chinese chars have higher semantic density (1 char ≈ 1 word)
    -- vs English letters (4-5 letters ≈ 1 word). Weight accordingly.
    local zh_weight = zh_count * 2.5
    local en_weight = en_count

    local total = zh_weight + en_weight
    if total == 0 then return "mixed" end

    local zh_ratio = zh_weight / total
    if zh_ratio > 0.55 then return "chinese" end
    if zh_ratio < 0.2 then return "english" end
    return "mixed"
end

return M
