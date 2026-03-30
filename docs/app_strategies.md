# App 策略文档

## 概述

开发专用输入法 通过 Squirrel 的 `app_options` 机制为不同类型的应用设置不同的默认输入行为。

## 策略分类

### 🖥️ 开发类 App（默认英文模式）

代码编辑为主，默认进入 ASCII 模式。用户在写注释时手动切换到中文。

| App | Bundle ID | 默认模式 |
|:----|:----------|:---------|
| VS Code | `com.microsoft.VSCode` | 英文 |
| Cursor | `com.todesktop.230313mzl4w4u92` | 英文 |
| Terminal | `com.apple.Terminal` | 英文 |
| iTerm2 | `com.googlecode.iterm2` | 英文 |
| IntelliJ IDEA | `com.jetbrains.intellij` | 英文 |
| WebStorm | `com.jetbrains.WebStorm` | 英文 |
| PyCharm | `com.jetbrains.pycharm` | 英文 |
| Sublime Text | `com.sublimetext.4` | 英文 |

### 💬 聊天类 App（默认中文模式）

中文交流为主，启用全部智能功能。

| App | Bundle ID | 默认模式 |
|:----|:----------|:---------|
| 微信 | `com.tencent.xinWeChat` | 中文 |
| Slack | `com.tinyspeck.slackmacgap` | 中文 |
| Telegram | `ru.keepcoder.Telegram` | 中文 |
| iMessage | `com.apple.MobileSMS` | 中文 |

### 📄 文档类 App（默认中文模式）

文档撰写为主，启用标点智能和自动空格。

| App | Bundle ID | 默认模式 |
|:----|:----------|:---------|
| Notes | `com.apple.Notes` | 中文 |
| Obsidian | `md.obsidian` | 中文 |
| Logseq | `com.electron.logseq` | 中文 |
| Notion | `notion.id` | 中文 |
| Pages | `com.apple.iWork.Pages` | 中文 |

### 🌐 浏览器（默认中文模式）

浏览器中混合输入场景多（搜索、AI 对话、社交），默认中文。

| App | Bundle ID | 默认模式 |
|:----|:----------|:---------|
| Chrome | `com.google.Chrome` | 中文 |
| Safari | `com.apple.Safari` | 中文 |
| Firefox | `com.mozilla.firefox` | 中文 |

## 智能功能各场景开关建议

| 功能 | 开发 App | 聊天 App | 文档 App | 终端 |
|:-----|:---------|:---------|:---------|:-----|
| 中文标点替换 | ⚠️ 仅中文连续输入时 | ✅ 开启 | ✅ 开启 | ❌ 关闭 |
| 自动空格 | ⚠️ 谨慎 | ✅ 开启 | ✅ 开启 | ❌ 关闭 |
| 混合候选 | ✅ 开启 | ✅ 开启 | ✅ 开启 | ⚠️ 基础 |
| 保护规则 | ✅ 强化 | ✅ 标准 | ✅ 标准 | ✅ 强化 |
| 引号/括号智能 | ❌ 关闭 | ⚠️ 可选 | ⚠️ 可选 | ❌ 关闭 |

## 配置方式

在 `squirrel.custom.yaml` 中的 `app_options` 部分配置：

```yaml
app_options:
  <Bundle ID>:
    ascii_mode: true/false
```

### 查找 App Bundle ID

```bash
# 方法1: 通过 mdls 命令
mdls -name kMDItemCFBundleIdentifier /Applications/AppName.app

# 方法2: 查看 Info.plist
defaults read /Applications/AppName.app/Contents/Info.plist CFBundleIdentifier
```

## 后续规划

- 支持更细粒度的 App 策略（不仅限于 ascii_mode）
- 支持用户自定义 App 策略
- 支持 App 内不同输入框的策略切换
