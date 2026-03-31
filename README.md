# 开发专用输入法 — 开发专用输入法

> 为开发者设计的中英混合表达输入法

[![Platform](https://img.shields.io/badge/platform-macOS-blue)]()
[![Engine](https://img.shields.io/badge/engine-Rime%20%2F%20Squirrel-green)]()
[![License](https://img.shields.io/badge/license-MIT-yellow)]()

## ✨ 特性

- **🔄 单输入流**：中英文、术语、路径、命令在同一输入流中自然切换，无需手动切换输入法
- **📝 标点智能**：根据上下文自动决策标点样式——中文语境用中文标点，代码/命令/路径中保留半角
- **🎯 自动配对 & Overtype**：输入成对符号（如 `<`、`(`、`[`、`"`）自动成对输出并让光标异步居中；再次输入右半边符号时自动跳出（Overtype），提供 IDE 级的无缝编码体验
- **⎵ 自动空格**：中英混排自动补充空格（`这个 bug` 而非 `这个bug`）
- **🛡️ 代码保护**：变量名、路径、URL、命令行参数等内容严格保护，不被误改
- **🔄 混合候选**：中文词与英文技术术语混合排列，上下文感知重排
- **⚡ App 感知**：不同应用自动切换策略（VS Code 默认英文，微信默认中文）

## 🎬 适用场景

| 场景 | 示例 | 效果 |
|:-----|:-----|:-----|
| 代码注释 | 这里先读取 config，再初始化 logger。 | ✅ 术语不切换，标点自动中文 |
| 技术聊天 | 先把 PR merge，再跑一下 CI。 | ✅ 一气呵成 |
| 文档写作 | 配置文件位于 ~/Library/Application Support/demo。 | ✅ 路径保护，标点正确 |
| AI 对话 | 帮我分析一下这段 Python code 为什么会报错。 | ✅ 中英无缝混合 |
| 命令混排 | 执行 `npm run build`，然后检查 dist 目录。 | ✅ 命令半角保护 |

## 📦 安装

### 前置条件

- macOS 12+
- [Squirrel](https://github.com/rime/squirrel)（Rime macOS 前端）

```bash
# 安装 Squirrel
brew install --cask squirrel
```

### 安装 开发专用输入法

```bash
# 克隆仓库
git clone https://github.com/GloryXia/Dev-IME.git
cd Dev-IME

# 同步词库（首次安装需要）
make sync-dicts

# 一键安装
make install
```

安装完成后：
1. 在系统设置 → 键盘 → 输入法 中添加 Squirrel
2. 按 `Ctrl+`` 或 `F4` 选择「开发专用输入法」

## ⌨️ 快捷键

| 快捷键 | 备用键 | 功能 |
|:-------|:-------|:-----|
| `Ctrl+Shift+1` | `F5` | 切换混合模式（开/关） |
| `Ctrl+Shift+2` | `F6` | 切换标点智能（中文标点自动替换） |
| `Ctrl+Shift+3` | `F7` | 切换自动空格 |
| `Ctrl+Shift+4` | — | 切换简繁 |
| `Ctrl+`` / `F4` | — | 切换输入方案 |

> **提示**：也可以按 `Ctrl+`` 或 `F4` 打开方案菜单，直接勾选/取消各项开关。

## 🌟 深度特性：IDE 级标点体验

在 macOS 上，输入法架构（InputMethodKit）原本无法控制宿主应用的光标位置。本输入法打破了这一限制，为你提供代码编辑器级别的内容输入体验：

1. **配对直接上屏**：在中文语境下输入 `<`，自动输出完整的 `《》`。
2. **异步物理光标居中**：提交字符后，通过后台派发延时异步任务，调用 AppleScript（`System Events`）模拟硬键盘「左箭头」事件，极速将光标完美拉回括号中间（适用于备忘录、微信等绝大部分支持 Apple Event 的 App）。
3. **Overtype（闭合符号智能跳出）**：光标在 `《|》` 时，如果你顺手输入了右侧的 `>`，输入法不会输出冗余的 `》`（避免变成 `《内容》》`），而是直接丢弃按键并发送「右箭头」光标事件，让你“滑出”括号，一气呵成。

## 🏗️ 架构

```
用户按键 → Rime Engine
  → hybrid_processor（状态管理）
  → punctuation_processor（标点决策）
  → speller + translator（拼音翻译）
  → hybrid_filter（候选重排）
  → auto_space_filter（自动空格）
  → 候选窗展示 → 用户选择上屏
```

### 核心模块

| 模块 | 文件 | 职责 |
|:-----|:-----|:-----|
| 工具库 | `lua/utils.lua` | UTF-8 操作、字符判断、模式匹配 |
| 上下文检测 | `lua/context_detector.lua` | Token 分类、保护模式检测 |
| 标点处理 | `lua/punctuation_processor.lua` | 上下文感知标点决策 |
| 状态管理 | `lua/hybrid_processor.lua` | 输入状态跟踪、回退 |
| 模型桥接 | `lua/model_bridge.lua` | 本地 sidecar 调用、缓存与安全回退 |
| 候选重排 | `lua/hybrid_filter.lua` | 混合候选智能排序 |
| 自动空格 | `lua/auto_space_filter.lua` | 中英混排空格补充 |

## 🔧 配置

### App 策略

在 `schema/squirrel.custom.yaml` 中的 `app_options` 配置不同 App 的默认行为：

```yaml
app_options:
  com.microsoft.VSCode:
    ascii_mode: true       # VS Code 默认英文
  com.tencent.xinWeChat:
    ascii_mode: false      # 微信默认中文
```

### 标点映射

| 输入 | 中文语境 | 代码/命令/路径 |
|:-----|:---------|:--------------|
| `,` | `，` | `,` |
| `.` | `。` | `.` |
| `?` | `？` | `?` |
| `!` | `！` | `!` |
| `:` | `：` | `:` |
| `;` | `；` | `;` |

### 保护的内容类型

以下内容不会被智能变换：
- 变量名：`user_id`、`refreshToken`
- 路径：`~/Downloads/test`
- URL：`https://example.com`
- 命令参数：`--force`、`-v`
- 版本号：`v1.2.3`
- 邮箱：`user@example.com`

## 🧪 测试

```bash
# 运行单元测试
make test

# 检查安装状态
make status
```

Phase 0 本地模型埋点默认写入：

```text
~/Library/Rime/hybrid_ime_model_events.jsonl
```

Phase 1 sidecar stub 默认监听：

```text
http://127.0.0.1:39571/score_context
```

可选本地配置文件：

```text
~/Library/Rime/hybrid_ime_model.conf
```

示例：

```ini
enabled=true
endpoint=http://127.0.0.1:39571/score_context
timeout_ms=200
cache_ttl_ms=800
```

启动本地 stub：

```bash
make model-sidecar
```

安装为自动启动的用户级服务：

```bash
make model-sidecar-service-install
```

查看服务状态：

```bash
make model-sidecar-service-status
```

卸载服务：

```bash
make model-sidecar-service-uninstall
```

## 📁 项目结构

```
Dev-IME/
├── schema/                 # Rime 方案配置
│   ├── hybrid_ime.schema.yaml
│   ├── hybrid_ime.dict.yaml
│   ├── default.custom.yaml
│   └── squirrel.custom.yaml
├── lua/                    # Lua 扩展脚本
│   ├── hybrid_init.lua
│   ├── utils.lua
│   ├── context_detector.lua
│   ├── model_feature_extractor.lua
│   ├── model_cache.lua
│   ├── model_json.lua
│   ├── model_logger.lua
│   ├── model_bridge.lua
│   ├── model_sidecar_client.lua
│   ├── punctuation_processor.lua
│   ├── hybrid_processor.lua
│   ├── hybrid_filter.lua
│   └── auto_space_filter.lua
├── dicts/                  # 自定义词典
│   ├── tech_terms.dict.yaml
│   ├── mixed_phrases.dict.yaml
│   └── protected_patterns.txt
├── tests/                  # 测试用例
├── scripts/                # 安装与系统辅助脚本
│   ├── hybrid_cursor_left.m
│   ├── hybrid_cursor_move.sh
│   └── start_model_sidecar.sh
├── docs/                   # 设计文档
├── tools/                  # 本地 sidecar 原型
│   └── modeld/
│       └── model_sidecar_stub.py
└── Makefile
```

## 🗺️ 路线图

- [x] **Phase 1**: 基础输入宿主
- [x] **Phase 2**: 标点智能决策
- [x] **Phase 3**: 自动空格
- [x] **Phase 4**: 混合候选重排
- [x] **Phase 5**: 保护规则
- [x] **Phase 6**: App 级策略
- [x] **Phase 7**: 本地模型埋点基础设施
- [ ] **Phase 8**: 个性化学习
- [ ] **Phase 9**: 端侧 AI 重排

## 📄 License

MIT License

## 🙏 致谢

- [Rime 输入法引擎](https://rime.im/)
- [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice) — 词库来源
- [librime-lua](https://github.com/hchunhui/librime-lua) — Lua 扩展支
