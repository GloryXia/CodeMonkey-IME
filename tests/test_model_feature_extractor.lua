-- ============================================================
-- test_model_feature_extractor.lua — model_feature_extractor.lua 单元测试
-- 运行: lua tests/test_model_feature_extractor.lua
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
local extractor = require("model_feature_extractor")

print("Testing model_feature_extractor.lua...")
print("")

print("  build_context_snapshot:")
do
    local snapshot = extractor.build_context_snapshot({
        app_id = "com.openai.codex",
        recent_committed = "先把 PR merge",
        last_commit_text = "merge",
        current_input = "mer",
        options = { hybrid_mode = true },
    })
    assert_eq(snapshot.app_id, "com.openai.codex", "app id")
    assert_eq(snapshot.language_context, "mixed", "mixed language context")
    assert_eq(snapshot.last_token_type, "tech_term", "last token classified as tech term")
    assert_eq(snapshot.protected, false, "mixed chat text not protected")
end

print("  protected context is preserved:")
do
    local snapshot = extractor.build_context_snapshot({
        recent_committed = "https://example.com",
        last_commit_text = "https://example.com",
        current_input = "",
    })
    assert_eq(snapshot.protected, true, "url snapshot protected")
    assert_eq(snapshot.protected_reason, "url", "url protected reason")
end

print("  summarize_candidates limits and trims:")
do
    local summary = extractor.summarize_candidates({
        { text = "merge", comment = "tech", quality = 0.7, type = "en" },
        { text = "合并", comment = "zh", quality = 0.6, type = "zh" },
    }, 1)
    assert_eq(#summary, 1, "candidate summary limited to requested length")
    assert_eq(summary[1].text, "merge", "first candidate text kept")
end

print("")
print(string.format("Results: %d passed, %d failed, %d total",
    pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
