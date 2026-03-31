-- ============================================================
-- punctuation_processor.lua — 标点智能决策处理器
-- 根据上下文自动决策半角标点是否替换为中文全角标点
-- ============================================================

local utils = require("utils")
local detector = require("context_detector")
local model_bridge = require("model_bridge")
local runtime_state = require("hybrid_runtime_state")

-- Rime 按键返回值
local kRejected = 0  -- 明确拒绝当前按键
local kAccepted = 1  -- 已处理，吞掉按键
local kNoop = 2      -- 不处理，交给后续处理器

local PROP_LAST_COMMITTED_TEXT = "hybrid_last_committed_text"
local PROP_LAST_COMMITTED_CHAR = "hybrid_last_committed_char"
local PROP_LAST_SYNCED_TEXT = "hybrid_last_synced_commit_text"
local PROP_RECENT_COMMITTED = "hybrid_recent_committed"

local shifted_key_punct_map = {
    ["1"] = "!",
    ["2"] = "@",
    ["3"] = "#",
    ["4"] = "$",
    ["5"] = "%",
    ["6"] = "^",
    ["7"] = "&",
    ["8"] = "*",
    ["9"] = "(",
    ["0"] = ")",
    ["-"] = "_",
    ["="] = "+",
    ["["] = "{",
    ["]"] = "}",
    ["\\"] = "|",
    [";"] = ":",
    ["'"] = "\"",
    [","] = "<",
    ["."] = ">",
    ["/"] = "?",
    ["`"] = "~",
}

local record_commit

local url_scheme_set = {
    http = true,
    https = true,
    ftp = true,
    file = true,
    mailto = true,
    vscode = true,
    obsidian = true,
    raycast = true,
    smb = true,
}

local function shell_quote(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function cursor_left_helper_path(env)
    if env and env.cursor_left_helper_path and env.cursor_left_helper_path ~= "" then
        return env.cursor_left_helper_path
    end

    local home = os.getenv("HOME")
    if not home or home == "" then
        return nil
    end

    return home .. "/Library/Rime/bin/hybrid_cursor_left"
end

local function move_cursor_left(env, opts)
    opts = opts or {}
    local home = os.getenv("HOME")
    if not home then return false end
    local script = home .. "/Library/Rime/bin/hybrid_cursor_move.sh"
    local delay = tonumber(opts.delay_seconds) or 0.1
    local cmd = script .. " left " .. string.format("%.2f", delay) .. " &"
    local ok = pcall(os.execute, cmd)
    return ok
end

local function move_cursor_right(env, opts)
    opts = opts or {}
    local home = os.getenv("HOME")
    if not home then return false end
    local script = home .. "/Library/Rime/bin/hybrid_cursor_move.sh"
    local delay = tonumber(opts.delay_seconds) or 0.1
    local cmd = script .. " right " .. string.format("%.2f", delay) .. " &"
    local ok = pcall(os.execute, cmd)
    return ok
end

local function safe_shift(key_event)
    if not key_event.shift then
        return false
    end
    local ok, result = pcall(function()
        return key_event:shift()
    end)
    if ok then
        return result == true
    end
    return false
end

local function latest_commit_text(context)
    if not context then
        return ""
    end

    local commit_text = context:get_commit_text() or ""
    if commit_text ~= "" then
        return commit_text
    end

    local history = context.commit_history
    if history and history.latest_text then
        local ok, text = pcall(function()
            return history:latest_text()
        end)
        if ok and text and text ~= "" then
            return text
        end
    end

    return ""
end

local function ensure_shared_state(env)
    local shared_state = runtime_state.ensure()
    env.hybrid_state = shared_state
    return shared_state
end

local function read_context_property(context, name)
    if not context or not context.get_property then
        return nil
    end
    local ok, value = pcall(function()
        return context:get_property(name)
    end)
    if ok then
        return value
    end
    return nil
end

local function write_context_property(context, name, value)
    if not context or not context.set_property then
        return
    end
    pcall(function()
        context:set_property(name, value or "")
    end)
end

local function current_last_committed_text(env)
    local shared_state = ensure_shared_state(env)
    local context = env.engine and env.engine.context or nil
    local value = read_context_property(context, PROP_LAST_COMMITTED_TEXT)
    if value and value ~= "" then
        shared_state.last_committed_text = value
        return value
    end
    return shared_state.last_committed_text or env.last_committed_text or ""
end

local function current_recent_committed(env)
    local shared_state = ensure_shared_state(env)
    local context = env.engine and env.engine.context or nil
    local value = read_context_property(context, PROP_RECENT_COMMITTED)
    if value and value ~= "" then
        shared_state.recent_committed = value
        return value
    end
    return shared_state.recent_committed or env.recent_committed or ""
end

local function current_last_committed_char(env)
    local shared_state = ensure_shared_state(env)
    local context = env.engine and env.engine.context or nil
    local value = read_context_property(context, PROP_LAST_COMMITTED_CHAR)
    if value and value ~= "" then
        shared_state.last_committed_char = value
        return value
    end
    return shared_state.last_committed_char or env.last_committed_char
end

local function ensure_pending_closers(env)
    local shared_state = ensure_shared_state(env)
    if type(shared_state.pending_closers) ~= "table" then
        shared_state.pending_closers = {}
    end
    env.pending_closers = shared_state.pending_closers
    return shared_state.pending_closers
end

local function peek_pending_closer(env)
    local pending = ensure_pending_closers(env)
    return pending[#pending]
end

local function push_pending_closer(env, closer)
    if not closer or closer == "" then
        return
    end
    local pending = ensure_pending_closers(env)
    table.insert(pending, closer)
    while #pending > 16 do
        table.remove(pending, 1)
    end
end

local function pop_pending_closer(env, expected)
    local pending = ensure_pending_closers(env)
    local top = pending[#pending]
    if not top then
        return nil
    end
    if expected and top ~= expected then
        return nil
    end
    pending[#pending] = nil
    return top
end

-- 统一的待关闭符号映射：输入字符 → 可能匹配的 pending closer 列表
local input_to_possible_closers = {
    [")"] = { ")", "）" },
    ["]"] = { "]", "】" },
    ["}"] = { "}", "｝" },
    [">"] = { "》" },
    ["\""] = { "\"", "”" },
    ["'"]  = { "'", "’" },
}

--- 检查输入是否匹配一个待关闭的 pending closer（统一处理括号和引号）
local function check_pending_overtype(env, input_char)
    local possible_closers = input_to_possible_closers[input_char]
    if not possible_closers then
        return nil
    end
    local top = peek_pending_closer(env)
    if not top then
        return nil
    end
    for _, closer in ipairs(possible_closers) do
        if top == closer then
            return top
        end
    end
    return nil
end

-- ============================================================
-- 标点智能决策主逻辑
-- ============================================================

--- 获取已提交文本的最后一个字符
--- @param env table Rime 环境对象
--- @return string|nil
local function get_last_committed_char(env)
    local context = env.engine.context
    local commit_text = context:get_commit_text()
    if commit_text and commit_text ~= "" then
        return utils.utf8_last_char(commit_text)
    end

    -- 尝试从 commit history 获取
    return current_last_committed_char(env)

end

--- 记录最后提交的字符（在 commit 事件时调用）
--- @param env table
--- @param text string
record_commit = function(env, text, source)
    if text and text ~= "" then
        local shared_state = ensure_shared_state(env)
        local context = env.engine and env.engine.context or nil
        env.last_synced_commit_text = text
        env.last_committed_text = text
        env.last_committed_char = utils.utf8_last_char(text)
        shared_state.last_synced_commit_text = text
        shared_state.last_committed_text = text
        shared_state.last_committed_char = env.last_committed_char
        -- 记录最近提交的文本片段（用于上下文分析）
        env.recent_committed = ((env.recent_committed or "") .. text)
        shared_state.recent_committed = ((shared_state.recent_committed or "") .. text)
        -- 只保留最近 50 个字符
        if #(env.recent_committed or "") > 200 then
            env.recent_committed = env.recent_committed:sub(-200)
        end
        if #(shared_state.recent_committed or "") > 200 then
            shared_state.recent_committed = shared_state.recent_committed:sub(-200)
        end

        write_context_property(context, PROP_LAST_COMMITTED_TEXT, shared_state.last_committed_text)
        write_context_property(context, PROP_LAST_COMMITTED_CHAR, shared_state.last_committed_char)
        write_context_property(context, PROP_LAST_SYNCED_TEXT, shared_state.last_synced_commit_text)
        write_context_property(context, PROP_RECENT_COMMITTED, shared_state.recent_committed)

        if source ~= "punctuation" then
            model_bridge.record_commit(env, {
                text = text,
                source = source or "candidate",
                recent_committed = current_recent_committed(env),
                last_commit_text = current_last_committed_text(env) or text,
                current_input = "",
            })
        end
    end
end

local function sync_commit_state(env, context)
    local text = latest_commit_text(context)
    if text ~= "" and text ~= env.last_synced_commit_text then
        record_commit(env, text, "candidate")
    elseif text ~= "" then
        local shared_state = ensure_shared_state(env)
        env.last_committed_text = text
        env.last_committed_char = utils.utf8_last_char(text)
        shared_state.last_committed_text = text
        shared_state.last_committed_char = env.last_committed_char
        write_context_property(context, PROP_LAST_COMMITTED_TEXT, shared_state.last_committed_text)
        write_context_property(context, PROP_LAST_COMMITTED_CHAR, shared_state.last_committed_char)
    end
    return text
end

local function model_punct_preference(model_result)
    if type(model_result) ~= "table" or model_result.available ~= true then
        return nil
    end

    local confidence = tonumber(model_result.confidence) or 0
    if confidence < 0.6 then
        return nil
    end

    local scores = model_result.scores or {}
    local zh_prob = tonumber(scores.zh_punct_prob) or 0
    local en_prob = tonumber(scores.en_punct_prob)
    if en_prob == nil then
        en_prob = 1 - zh_prob
    end

    if zh_prob >= 0.75 then
        return "chinese"
    end
    if en_prob >= 0.75 then
        return "english"
    end
    return nil
end

local function apply_model_preference(model_pref, punct, chinese_punct)
    if model_pref == "chinese" then
        return true, chinese_punct, "model"
    end
    if model_pref == "english" then
        return true, punct, "model"
    end
    return false, nil, nil
end

local function should_keep_ascii_protocol_punct(last_text, punct)
    if punct ~= ":" then
        return false
    end

    local normalized = utils.trim(last_text or ""):lower()
    if normalized == "" then
        return false
    end

    return url_scheme_set[normalized] == true
end

--- 初始化函数
local function init(env)
    local shared_state = ensure_shared_state(env)
    ensure_pending_closers(env)
    local context = env.engine and env.engine.context or nil
    local recent = read_context_property(context, PROP_RECENT_COMMITTED)
    if recent and recent ~= "" then
        shared_state.recent_committed = recent
    end
    local last_text = read_context_property(context, PROP_LAST_COMMITTED_TEXT)
    if last_text and last_text ~= "" then
        shared_state.last_committed_text = last_text
    end
    local last_char = read_context_property(context, PROP_LAST_COMMITTED_CHAR)
    if last_char and last_char ~= "" then
        shared_state.last_committed_char = last_char
    end
    env.last_committed_char = shared_state.last_committed_char
    env.last_committed_text = shared_state.last_committed_text
    env.recent_committed = shared_state.recent_committed or ""
    env.last_punct_action = nil  -- 记录上次标点操作，用于撤销

    model_bridge.init(env)

    context = env.engine and env.engine.context
    if context and context.commit_notifier and context.commit_notifier.connect then
        env.commit_notifier = context.commit_notifier:connect(function()
            local active_context = env.engine and env.engine.context or context
            local text = latest_commit_text(active_context)
            if text ~= "" then
                record_commit(env, text, "candidate")
            end
        end)
    end
end

--- 根据当前语境解析标点最终输出。
--- @param punct string 半角标点字符
--- @param env table Rime 环境
--- @return boolean handled 是否由处理器直接处理
--- @return string|nil output 最终输出字符
--- @return string decision_source 决策来源
local function resolve_punct_output(punct, env, model_result)
    -- 1. 检查开关状态
    local context = env.engine.context
    if context then
        -- 检查 auto_punct 开关
        local auto_punct_on = context:get_option("auto_punct")
        if auto_punct_on == false then
            return false, nil, "rules"
        end

        -- 检查 hybrid_mode 开关
        local hybrid_on = context:get_option("hybrid_mode")
        if hybrid_on == false then
            return false, nil, "rules"
        end

        -- 如果当前在 ASCII 模式，不替换
        local ascii_mode = context:get_option("ascii_mode")
        if ascii_mode then
            return false, nil, "rules"
        end
    end

    -- 2. 如果有组合态内容（正在输入拼音），不拦截
    if context and context:is_composing() then
        return false, nil, "rules"
    end

    -- 3. 读取最近一次真实上屏内容。
    -- 不能只依赖本模块内部缓存，否则中文候选上屏后立刻输入标点时会丢上下文。
    local commit_text = sync_commit_state(env, context)
    local recent = current_recent_committed(env)
    local chinese_punct = utils.get_chinese_punct(punct, recent)
    if not chinese_punct then
        return false, nil, "rules"
    end
    local model_pref = model_punct_preference(model_result)

    -- 4. 检查保护模式
    local protected, reason = detector.is_protected(recent, "")
    if protected then
        return true, punct, "rules"
    end

    -- 5. 获取上一个已提交字符
    local last_char = utils.utf8_last_char(commit_text) or current_last_committed_char(env)
    if not last_char then
        -- 没有上文信息，默认保留英文/半角符号
        return true, punct, "rules"
    end

    -- 6. 根据上一字符类型决策
    local prev_type = detector.get_prev_char_type(last_char)
    local last_text = commit_text
    if last_text == "" then
        last_text = current_last_committed_text(env)
        if last_text == "" then
            last_text = last_char
        end
    end

    -- 特殊规则: "$" 仅在中文/中文标点后转成全角人民币符号。
    -- 英文内容后或无上文时，保留半角 "$"。
    if punct == "$" then
        local handled, output, decision_source = apply_model_preference(model_pref, punct, chinese_punct)
        if handled then
            return handled, output, decision_source
        end
        if prev_type == "chinese" then
            return true, chinese_punct, "rules"
        end
        return true, punct, "rules"
    end

    if prev_type == "chinese" then
        -- 上一字符是中文 → 替换
        return true, chinese_punct, "rules"
    end

    if prev_type == "english" then
        local handled, output, decision_source = apply_model_preference(model_pref, punct, chinese_punct)
        if handled then
            return handled, output, decision_source
        end

        -- sidecar 不可用时，协议前缀仍然保留 ASCII 冒号，避免 URL 退化。
        if should_keep_ascii_protocol_punct(last_text, punct) then
            return true, punct, "rules"
        end

        -- 普通英文词默认保留英文标点。
        -- 只有技术术语/代码式 token 嵌在中文句子里时，才沿用中文标点。
        local token_type = detector.classify_token(last_text)
        if token_type == detector.TOKEN_TECH_TERM
            or token_type == detector.TOKEN_CODE
            or token_type == detector.TOKEN_COMMAND
            or token_type == detector.TOKEN_MIXED then
            local lang_ctx = detector.detect_language_context(recent)
            if lang_ctx == "chinese" or lang_ctx == "mixed" then
                -- 例如：「先把 PR merge，」← 这里的逗号应替换
                return true, chinese_punct, "rules"
            end
        end
        return true, punct, "rules"
    end

    if prev_type == "number" then
        -- 数字后面：
        --   句号可能是小数点 → 不替换 "."
        --   逗号可能是千分位 → 不替换 ","
        if punct == "." or punct == "," then
            return true, punct, "rules"
        end
        local handled, output, decision_source = apply_model_preference(model_pref, punct, chinese_punct)
        if handled then
            return handled, output, decision_source
        end
        -- 其他标点在数字后按语境判断
        local lang_ctx = detector.detect_language_context(recent)
        if lang_ctx == "chinese" or lang_ctx == "mixed" then
            return true, chinese_punct, "rules"
        end
        return true, punct, "rules"
    end

    if prev_type == "punct" then
        -- 标点后面再跟标点 → 不替换（避免连续替换干扰）
        return true, punct, "rules"
    end

    local handled, output, decision_source = apply_model_preference(model_pref, punct, chinese_punct)
    if handled then
        return handled, output, decision_source
    end

    -- 7. 默认：保守保留英文/半角符号
    return true, punct, "rules"
end

--- 解析当前按键对应的 ASCII 字符。
--- macOS/Rime 下 Shift+数字有时上报原始数字键，需要在这里还原成符号。
--- @param key_event table
--- @return string|nil
local function get_key_char(key_event)
    local keycode = key_event.keycode
    if keycode < 0x20 or keycode > 0x7E then
        return nil
    end

    local key_char = string.char(keycode)
    local shifted = safe_shift(key_event)
    if shifted then
        local shifted_char = shifted_key_punct_map[key_char]
        if shifted_char then
            return shifted_char
        end
    end

    return key_char
end

local function build_pair_output(input_punct, output_punct)
    if not utils.should_auto_pair(input_punct, output_punct) then
        return output_punct, false
    end

    local close_punct = utils.get_pair_close(input_punct, output_punct)
    if not close_punct then
        return output_punct, false
    end

    return output_punct .. close_punct, true
end

--- Rime processor 入口函数
--- @param key_event table 按键事件
--- @param env table Rime 环境
--- @return number 处理结果
local function processor(key_event, env)
    -- 只处理按下事件，不处理释放事件
    if key_event:release() then
        return kNoop
    end

    -- 获取按键对应的字符
    local key_char = get_key_char(key_event)

    if not key_char then
        return kNoop
    end

    -- 检查是否是待决策标点
    if not utils.is_convertible_punct(key_char) then
        -- 不是待决策标点，但如果是其他字符，记录它
        return kNoop
    end

    local context = env.engine and env.engine.context or nil

    -- ========================================
    -- Overtype 检查：输入关闭符号时，跳过已自动补全的关闭符号
    -- ========================================
    local overtype_closer = check_pending_overtype(env, key_char)
    if overtype_closer then
        move_cursor_right(env, { delay_seconds = 0.05 })
        pop_pending_closer(env, overtype_closer)
        -- 记录关闭符号以保持引号计数平衡
        record_commit(env, overtype_closer, "punctuation")
        return kAccepted
    end

    local last_commit_text = latest_commit_text(context)
    if last_commit_text == "" then
        last_commit_text = current_last_committed_text(env)
    end
    local recent_committed = current_recent_committed(env)

    local context_score = model_bridge.score_context(env, {
        mode = "punctuation_context",
        recent_committed = recent_committed,
        last_commit_text = last_commit_text,
        current_input = "",
        target_punct = key_char,
    })

    -- 执行标点决策
    local handled, output, decision_source = resolve_punct_output(key_char, env, context_score)
    if handled and output then
        local committed_text, paired = build_pair_output(key_char, output)
        local close_punct = paired and utils.get_pair_close(key_char, output) or nil
        local moved_cursor = false
        local shifted_input = safe_shift(key_event)

        -- 记录操作（用于可能的撤销）
        env.last_punct_action = {
            original = key_char,
            converted = committed_text,
        }

        -- 直接提交最终标点（配对时一次性提交开闭两个符号）
        env.engine:commit_text(committed_text)

        if paired then
            moved_cursor = move_cursor_left(env, { delay_seconds = 0.05 })
        end

        -- 更新已提交字符记录
        local state_text = committed_text
        if paired and moved_cursor then
            state_text = output
        end
        record_commit(env, state_text, "punctuation")

        if paired and moved_cursor and close_punct then
            push_pending_closer(env, close_punct)
        end

        model_bridge.record_punctuation_decision(env, {
            input_punct = key_char,
            output_text = committed_text,
            decision_source = decision_source or "rules",
            recent_committed = current_recent_committed(env),
            last_commit_text = current_last_committed_text(env),
            current_input = "",
            used_model = decision_source == "model",
        })

        return kAccepted
    end

    -- 不替换，让后续处理器处理
    -- 但仍然记录这个字符
    -- (会在 commit 时由 hybrid_processor 记录)
    return kNoop
end

local function fini(env)
    if env.commit_notifier and env.commit_notifier.disconnect then
        pcall(function()
            env.commit_notifier:disconnect()
        end)
    end
end

return { init = init, func = processor, fini = fini }
