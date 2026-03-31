-- ============================================================
-- test_model_bridge.lua — model_bridge.lua 单元测试
-- 运行: lua tests/test_model_bridge.lua
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
local bridge = require("model_bridge")

local function make_env()
    return {
        engine = {
            context = {
                input = "mer",
                get_option = function(_, name)
                    local options = {
                        hybrid_mode = true,
                        auto_punct = true,
                        auto_space = true,
                        ascii_mode = false,
                    }
                    return options[name]
                end,
            },
        },
        hybrid_state = {
            recent_committed = "先把 PR merge",
            last_committed_text = "merge",
        },
        model_bridge_config = {
            mode = "log_only",
        },
    }
end

print("Testing model_bridge.lua...")
print("")

print("  score_context falls back safely:")
do
    local env = make_env()
    local events = {}
    local result = bridge.score_context(env, {
        logger = {
            append_event = function(event)
                events[#events + 1] = event
                return true
            end,
        },
    })
    assert_eq(result.available, false, "bridge should not enable model inference in phase 0")
    assert_eq(result.source, "log_only", "bridge should return log_only source")
    assert_eq(events[1].event, "context_score_requested", "bridge logs context score request")
end

print("  score_context can use sidecar response:")
do
    local env = make_env()
    local events = {}
    local transport_calls = 0
    env.model_bridge_config = {
        mode = "sidecar",
        cache_ttl_ms = 800,
        transport = function(request)
            transport_calls = transport_calls + 1
            return {
                request_id = request.request_id,
                source = "sidecar_stub",
                context = "tech_mixed",
                confidence = 0.84,
                ttl_ms = 900,
                scores = {
                    zh_punct_prob = 0.81,
                    en_punct_prob = 0.19,
                },
            }
        end,
    }
    local result = bridge.score_context(env, {
        logger = {
            append_event = function(event)
                events[#events + 1] = event
                return true
            end,
        },
    })
    assert_eq(result.available, true, "sidecar result should be available")
    assert_eq(result.source, "sidecar_stub", "sidecar source is preserved")
    assert_eq(result.context, "tech_mixed", "sidecar context is returned")
    assert_eq(transport_calls, 1, "sidecar should be called once")
    assert_eq(events[2].event, "context_score_resolved", "sidecar success should be logged")
end

print("  score_context forwards target punct:")
do
    local env = make_env()
    local captured_request = nil
    env.model_bridge_config = {
        mode = "sidecar",
        transport = function(request)
            captured_request = request
            return {
                request_id = request.request_id,
                source = "sidecar_stub",
                context = "protocol_hint",
                confidence = 0.93,
                ttl_ms = 900,
                scores = {
                    zh_punct_prob = 0.05,
                    en_punct_prob = 0.95,
                },
            }
        end,
    }
    bridge.score_context(env, {
        target_punct = ":",
        logger = {
            append_event = function()
                return true
            end,
        },
    })
    assert_eq(captured_request.target_punct, ":", "target punct should be passed to sidecar")
end

print("  score_context caches repeated requests:")
do
    local env = make_env()
    local transport_calls = 0
    env.model_bridge_config = {
        mode = "sidecar",
        cache_ttl_ms = 800,
        transport = function(request)
            transport_calls = transport_calls + 1
            return {
                request_id = request.request_id,
                source = "sidecar_stub",
                context = "tech_mixed",
                confidence = 0.9,
                ttl_ms = 900,
                scores = {
                    zh_punct_prob = 0.78,
                    en_punct_prob = 0.22,
                },
            }
        end,
    }

    local sink = {
        append_event = function()
            return true
        end,
    }
    bridge.score_context(env, { logger = sink })
    bridge.score_context(env, { logger = sink })
    assert_eq(transport_calls, 1, "identical context should hit cache")
end

print("  sidecar failure falls back safely:")
do
    local env = make_env()
    local events = {}
    env.model_bridge_config = {
        mode = "sidecar",
        transport = function()
            return nil, "timeout"
        end,
    }
    local result = bridge.score_context(env, {
        logger = {
            append_event = function(event)
                events[#events + 1] = event
                return true
            end,
        },
    })
    assert_eq(result.available, false, "failed sidecar should fallback")
    assert_eq(result.source, "sidecar_fallback", "failed sidecar should report fallback source")
    assert_eq(events[2].event, "context_score_failed", "sidecar failure should be logged")
end

print("  rerank_candidates can use sidecar response:")
do
    local env = make_env()
    local events = {}
    env.model_bridge_config = {
        mode = "sidecar",
        transport = function(request)
            return {
                request_id = request.request_id,
                source = "sidecar_stub",
                confidence = 0.87,
                ttl_ms = 900,
                ranked_scores = {
                    { id = "1", score = 0.41 },
                    { id = "2", score = 0.93 },
                },
            }
        end,
    }
    local result = bridge.rerank_candidates(env, {
        candidates = {
            { id = "1", text = "合并", type = "zh", quality = 0.4 },
            { id = "2", text = "merge", type = "tech", quality = 0.5 },
        },
        logger = {
            append_event = function(event)
                events[#events + 1] = event
                return true
            end,
        },
    })
    assert_eq(result.available, true, "rerank result should be available")
    assert_eq(result.ranked_scores[2].score, 0.93, "rerank scores should be preserved")
    assert_eq(events[1].event, "candidate_rerank_requested", "rerank request should be logged")
    assert_eq(events[2].event, "candidate_rerank_resolved", "rerank response should be logged")
end

print("  record_commit logs payload:")
do
    local env = make_env()
    local events = {}
    bridge.record_commit(env, {
        text = "merge",
        source = "candidate",
        logger = {
            append_event = function(event)
                events[#events + 1] = event
                return true
            end,
        },
    })
    assert_eq(events[1].event, "commit_observed", "commit event logged")
    assert_eq(events[1].payload.committed_text, "merge", "commit payload includes committed text")
end

print("  record_punctuation_decision logs payload:")
do
    local env = make_env()
    local events = {}
    bridge.record_punctuation_decision(env, {
        input_punct = ",",
        output_text = "，",
        decision_source = "rules",
        logger = {
            append_event = function(event)
                events[#events + 1] = event
                return true
            end,
        },
    })
    assert_eq(events[1].event, "punctuation_decided", "punctuation event logged")
    assert_eq(events[1].payload.output_text, "，", "punctuation payload includes output")
end

print("")
print(string.format("Results: %d passed, %d failed, %d total",
    pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
