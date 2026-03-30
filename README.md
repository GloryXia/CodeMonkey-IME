# Hybrid IME — 混合输入法

> 为开发者设计的中英混合表达输入法

[![Platform](https://img.shields.io/badge/platform-macOS-blue)]()
[![Engine](https://img.shields.io/badge/engine-Rime%20%2F%20Squirrel-green)]()
[![License](https://img.shields.io/badge/license-MIT-yellow)]()

## ✨ 特性

- **🔄 单输入流**：中英文、术语、路径、命令在同一输入流中自然切换，无需手动切换输入法
- **📝 标点智能**：根据上下文自动决策标点样式——中文语境用中文标点，代码/命令/路径中保留半角
- **⎵ 自动空格**：中英混排自动补充空格（`这个 bug` 而非 `这个bug`）
- **🛡️ 代码保护**：变量名、路径、URL、命令行参数等内容严格保护，不被误改
- **🎯 混合候选**：中文词与英文技术术语混合排列，上下文感知重排
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

### 安装 Hybrid IME

```bash
# 克隆仓库
git clone https://github.com/GloryXia/Hybrid-IME.git
cd Hybrid-IME

# 同步词库（首次安装需要）
make sync-dicts

# 一键安装
make install
```

安装完成后：
1. 在系统设置 → 键盘 → 输入法 中添加 Squirrel
2. 按 `Ctrl+`` 或 `F4` 选择「混合输入法」

## ⌨️ 快捷键

| 快捷键 | 功能 |
|:-------|:-----|
| `Ctrl+Shift+H` | 切换混合模式（开/关） |
| `Ctrl+Shift+P` | 切换标点智能（中文标点自动替换） |
| `Ctrl+Shift+S` | 切换自动空格 |
| `Ctrl+Shift+F` | 切换简繁 |
| `Ctrl+`` / `F4` | 切换输入方案 |

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

## 📁 项目结构

```
Hybrid-IME/
├── schema/                 # Rime 方案配置
│   ├── hybrid_ime.schema.yaml
│   ├── hybrid_ime.dict.yaml
│   ├── default.custom.yaml
│   └── squirrel.custom.yaml
├── lua/                    # Lua 扩展脚本
│   ├── hybrid_init.lua
│   ├── utils.lua
│   ├── context_detector.lua
│   ├── punctuation_processor.lua
│   ├── hybrid_processor.lua
│   ├── hybrid_filter.lua
│   └── auto_space_filter.lua
├── dicts/                  # 自定义词典
│   ├── tech_terms.dict.yaml
│   ├── mixed_phrases.dict.yaml
│   └── protected_patterns.txt
├── tests/                  # 测试用例
├── scripts/                # 安装/卸载脚本
├── docs/                   # 设计文档
└── Makefile
```

## 🗺️ 路线图

- [x] **Phase 1**: 基础输入宿主
- [x] **Phase 2**: 标点智能决策
- [x] **Phase 3**: 自动空格
- [x] **Phase 4**: 混合候选重排
- [x] **Phase 5**: 保护规则
- [x] **Phase 6**: App 级策略
- [ ] **Phase 7**: 个性化学习
- [ ] **Phase 8**: 端侧 AI 重排

## 📄 License

MIT License

## 🙏 致谢

- [Rime 输入法引擎](https://rime.im/)
- [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice) — 词库来源
- [librime-lua](https://github.com/hchunhui/librime-lua) — Lua 扩展支持
