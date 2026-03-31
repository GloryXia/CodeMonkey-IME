# Phase 2 Validation Matrix

目标：验证本地 sidecar 驱动的保守候选重排在真实输入中稳定工作，同时不破坏候选框。

## 自动化回归

当前自动化覆盖位于：

- `~/Desktop/developer/code/Hybrid-IME/tests/test_candidate_rerank_filter.lua`

已覆盖场景：

- 高置信度时提升可见前缀中的英文候选
- 低置信度时保持原顺序
- sidecar 不可用时安全回退
- 深层 exact-match 英文候选召回：`chi`
- 常见开发词深层 exact-match 英文候选召回：`ci` `pr` `bug` `json` `merge`

## 手工验收

使用 Squirrel 的“开发专用输入法”，保持 `hybrid_mode` 开启。

### 候选框稳定性

- 输入 `ni`
- 预期：候选框正常出现，不空白，不闪退

### 中文上下文中的英文 exact-match 提升

- 输入 `wo`，上屏 `我`，再输入 `chi`
- 预期：`chi` 进入前 3，当前已验证可到第 1

- 输入 `先跑一下`，上屏后输入 `ci`
- 预期：`ci` 进入前 3

- 输入 `提一个`，上屏后输入 `pr`
- 预期：`PR` 或 `pr` 进入前 3

- 输入 `这个`，上屏后输入 `bug`
- 预期：`bug` 进入前 3

- 输入 `解析`，上屏后输入 `json`
- 预期：`json` 进入前 3

- 输入 `先把这个`，上屏后输入 `merge`
- 预期：`merge` 进入前 3

### 英文语境不被中文干扰

- 直接输入 `bug`
- 预期：英文候选仍可正常出现

- 直接输入 `json`
- 预期：英文候选仍可正常出现

### 标点链路未回归

- 输入 `价格` 上屏后按 `Shift+4`
- 预期：输出 `￥`

- 输入 `price` 上屏后按 `Shift+4`
- 预期：输出 `$`

- 输入 `你好 hello` 后按 `Shift+/`
- 预期：在 P1 开启时可输出 `？`

## 日志核对

日志文件：

- `~/Library/Rime/hybrid_ime_model_events.jsonl`

候选重排生效时，应看到：

- `candidate_rerank_requested`
- `candidate_rerank_resolved`

重点字段：

- `current_input`
- `candidates`
- `response.ranked_scores`

如果 live 结果与预期不一致，先核对请求里是否真的包含 deep exact-match 英文候选；如果请求里没有，问题在 translator 候选流；如果请求里有但没排到前面，问题在 filter 落地逻辑或阈值。
