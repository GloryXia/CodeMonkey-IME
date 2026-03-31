-- ============================================================
-- test_candidate_rerank_filter.lua — candidate_rerank_filter.lua 单元测试
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

_G.ShadowCandidate = function(cand, cand_type, text, comment)
    local wrapped = {}
    for key, value in pairs(cand) do
        wrapped[key] = value
    end
    wrapped.type = cand_type
    wrapped.text = text
    wrapped.comment = comment
    return wrapped
end

local rerank_filter = require("candidate_rerank_filter")

local function make_candidate(text, quality, comment)
    return {
        type = "test",
        start = 0,
        _end = #text,
        text = text,
        quality = quality or 0,
        comment = comment or "",
    }
end

local function make_input(candidates)
    return {
        iter = function()
            local index = 0
            return function()
                index = index + 1
                return candidates[index]
            end
        end,
    }
end

local function make_env(opts)
    opts = opts or {}
    local context = {
        get_option = function(_, name)
            return opts.options and opts.options[name]
        end,
        get_commit_text = function()
            return opts.context_commit_text or ""
        end,
        commit_history = {
            latest_text = function()
                return opts.context_commit_text or ""
            end,
        },
        is_composing = function()
            return opts.is_composing ~= false
        end,
        input = opts.input or "",
    }

    local env = {
        engine = {
            context = context,
        },
        model_bridge_config = opts.model_bridge_config or {
            mode = "log_only",
        },
    }
    rerank_filter.init(env)
    opts.context_commit_text = opts.last_commit_text or opts.context_commit_text or ""
    return env
end

local function run_filter(candidates, env)
    local yielded = {}
    _G.yield = function(cand)
        yielded[#yielded + 1] = cand
    end
    rerank_filter.func(make_input(candidates), env)
    _G.yield = nil
    return yielded
end

local function build_deep_recall_candidates(top_prefix, filler_until, exact_match)
    local candidates = {}
    for _, item in ipairs(top_prefix) do
        candidates[#candidates + 1] = make_candidate(item.text, item.quality)
    end
    for index = #candidates + 1, filler_until - 1 do
        candidates[#candidates + 1] = make_candidate("候选" .. tostring(index), 0.1 - (index * 0.001))
    end
    candidates[#candidates + 1] = make_candidate(exact_match.text, exact_match.quality)
    return candidates
end

local function run_exact_match_recall_case(opts)
    local env = make_env({
        options = { hybrid_mode = true },
        recent_committed = opts.recent_committed,
        last_commit_text = opts.last_commit_text,
        input = opts.input,
        model_bridge_config = {
            mode = "sidecar",
            transport = function(request)
                assert_eq(request.current_input, opts.input, opts.input .. " request should keep current input")
                assert_eq(request.candidates[#request.candidates].id, tostring(opts.deep_index), opts.input .. " should recall deep exact-match candidate")

                local ranked_scores = {}
                for index = 1, 6 do
                    ranked_scores[#ranked_scores + 1] = {
                        id = tostring(index),
                        score = 0.70 - (index * 0.01),
                    }
                end
                ranked_scores[#ranked_scores + 1] = {
                    id = tostring(opts.deep_index),
                    score = 1.46,
                }

                return {
                    source = "sidecar_stub",
                    confidence = 0.86,
                    ttl_ms = 800,
                    ranked_scores = ranked_scores,
                }
            end,
        },
    })

    local yielded = run_filter(build_deep_recall_candidates(opts.top_prefix, opts.deep_index, {
        text = opts.exact_match_text,
        quality = opts.exact_match_quality or 0.10,
    }), env)

    assert_eq(yielded[1].text, opts.expected_first or opts.exact_match_text, opts.input .. " should promote exact-match english candidate")
    assert_eq(yielded[2].text, opts.top_prefix[1].text, opts.input .. " should keep original top chinese candidate after promotion")
end

print("Testing candidate_rerank_filter.lua...")
print("")

print("  high-confidence sidecar reorders top candidates:")
do
    local env = make_env({
        options = { hybrid_mode = true },
        recent_committed = "先把这个 PR",
        last_commit_text = "PR",
        input = "merge",
        model_bridge_config = {
            mode = "sidecar",
            transport = function()
                return {
                    source = "sidecar_stub",
                    confidence = 0.91,
                    ttl_ms = 800,
                    ranked_scores = {
                        { id = "1", score = 0.42 },
                        { id = "2", score = 0.96 },
                    },
                }
            end,
        },
    })
    local yielded = run_filter({
        make_candidate("合并", 0.5),
        make_candidate("merge", 0.4),
        make_candidate("合并到", 0.3),
    }, env)
    assert_eq(yielded[1].text, "merge", "sidecar should promote english tech term")
    assert_eq(yielded[2].text, "合并", "remaining candidates keep stable relative order")
end

print("  low-confidence sidecar keeps original order:")
do
    local env = make_env({
        options = { hybrid_mode = true },
        recent_committed = "先把这个 PR",
        last_commit_text = "PR",
        input = "merge",
        model_bridge_config = {
            mode = "sidecar",
            transport = function()
                return {
                    source = "sidecar_stub",
                    confidence = 0.63,
                    ttl_ms = 800,
                    ranked_scores = {
                        { id = "1", score = 0.40 },
                        { id = "2", score = 0.98 },
                    },
                }
            end,
        },
    })
    local yielded = run_filter({
        make_candidate("合并", 0.5),
        make_candidate("merge", 0.4),
    }, env)
    assert_eq(yielded[1].text, "合并", "low confidence should preserve original order")
end

print("  unavailable sidecar keeps original order:")
do
    local env = make_env({
        options = { hybrid_mode = true },
        recent_committed = "先把这个 PR",
        last_commit_text = "PR",
        input = "merge",
        model_bridge_config = {
            mode = "sidecar",
            transport = function()
                return nil, "timeout"
            end,
        },
    })
    local yielded = run_filter({
        make_candidate("合并", 0.5),
        make_candidate("merge", 0.4),
    }, env)
    assert_eq(yielded[1].text, "合并", "failed sidecar should preserve original order")
end

print("  exact-match english beyond visible prefix is recalled safely:")
do
    run_exact_match_recall_case({
        input = "chi",
        recent_committed = "我",
        last_commit_text = "我",
        top_prefix = {
            { text = "吃", quality = 0.60 },
            { text = "持", quality = 0.59 },
            { text = "池", quality = 0.58 },
            { text = "迟", quality = 0.57 },
            { text = "赤", quality = 0.56 },
            { text = "尺", quality = 0.55 },
        },
        deep_index = 30,
        exact_match_text = "chi",
    })
end

print("  validation matrix covers common dev tokens:")
do
    local cases = {
        {
            input = "ci",
            recent_committed = "先跑一下",
            last_commit_text = "先跑一下",
            top_prefix = {
                { text = "次", quality = 0.66 },
                { text = "此", quality = 0.65 },
                { text = "词", quality = 0.64 },
                { text = "磁", quality = 0.63 },
                { text = "辞", quality = 0.62 },
                { text = "慈", quality = 0.61 },
            },
            deep_index = 18,
            exact_match_text = "CI",
            expected_first = "CI",
        },
        {
            input = "pr",
            recent_committed = "提一个",
            last_commit_text = "提一个",
            top_prefix = {
                { text = "譬如", quality = 0.66 },
                { text = "皮肉", quality = 0.65 },
                { text = "疲软", quality = 0.64 },
                { text = "僻儒", quality = 0.63 },
                { text = "霹雳", quality = 0.62 },
                { text = "匹染", quality = 0.61 },
            },
            deep_index = 22,
            exact_match_text = "PR",
            expected_first = "PR",
        },
        {
            input = "bug",
            recent_committed = "这个",
            last_commit_text = "这个",
            top_prefix = {
                { text = "不够", quality = 0.66 },
                { text = "不过", quality = 0.65 },
                { text = "布局", quality = 0.64 },
                { text = "补给", quality = 0.63 },
                { text = "布告", quality = 0.62 },
                { text = "步伐", quality = 0.61 },
            },
            deep_index = 16,
            exact_match_text = "bug",
        },
        {
            input = "json",
            recent_committed = "解析",
            last_commit_text = "解析",
            top_prefix = {
                { text = "解释哦嗯", quality = 0.66 },
                { text = "技术债", quality = 0.65 },
                { text = "计算哦呢", quality = 0.64 },
                { text = "寄送", quality = 0.63 },
                { text = "接收", quality = 0.62 },
                { text = "简述", quality = 0.61 },
            },
            deep_index = 26,
            exact_match_text = "json",
        },
        {
            input = "merge",
            recent_committed = "先把这个",
            last_commit_text = "先把这个",
            top_prefix = {
                { text = "没人接", quality = 0.66 },
                { text = "每日更", quality = 0.65 },
                { text = "没结果", quality = 0.64 },
                { text = "美人歌", quality = 0.63 },
                { text = "煤热管", quality = 0.62 },
                { text = "美人关", quality = 0.61 },
            },
            deep_index = 28,
            exact_match_text = "merge",
        },
    }

    for _, case in ipairs(cases) do
        run_exact_match_recall_case(case)
    end
end

print("")
print(string.format("Results: %d passed, %d failed, %d total",
    pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
