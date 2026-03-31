#!/usr/bin/env bash
# ============================================================
# 程序猿输入法 — 安装脚本
# 将 程序猿输入法 配置安装到 macOS Rime (Squirrel) 用户目录
# ============================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Rime 用户配置目录
RIME_DIR="$HOME/Library/Rime"
# 项目根目录（脚本所在目录的上一级）
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# 备份目录
BACKUP_DIR="$RIME_DIR/.hybrid_ime_backup_$(date +%Y%m%d_%H%M%S)"

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     程序猿输入法 — 程序猿输入法 安装程序     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# 1. 检测 Squirrel 是否安装
# ============================================================
echo -e "${YELLOW}[1/6]${NC} 检测 Squirrel 输入法..."

if [ -d "/Library/Input Methods/Squirrel.app" ]; then
    echo -e "${GREEN}  ✓ Squirrel 已安装${NC}"
elif command -v brew &> /dev/null; then
    echo -e "${RED}  ✗ 未检测到 Squirrel${NC}"
    echo ""
    read -p "  是否通过 Homebrew 安装 Squirrel？(y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "  正在安装 Squirrel..."
        brew install --cask squirrel
        echo -e "${GREEN}  ✓ Squirrel 安装完成${NC}"
        echo -e "${YELLOW}  ⚠ 请重新登录或重启 Mac 以激活 Squirrel${NC}"
    else
        echo -e "${RED}  安装已取消。请先安装 Squirrel 后重试。${NC}"
        exit 1
    fi
else
    echo -e "${RED}  ✗ 未检测到 Squirrel，且未安装 Homebrew${NC}"
    echo -e "  请访问 https://github.com/rime/squirrel 手动安装"
    exit 1
fi

# ============================================================
# 2. 检查 Rime 目录
# ============================================================
echo -e "${YELLOW}[2/6]${NC} 检查 Rime 配置目录..."

if [ ! -d "$RIME_DIR" ]; then
    echo -e "  创建 Rime 目录: $RIME_DIR"
    mkdir -p "$RIME_DIR"
fi
echo -e "${GREEN}  ✓ Rime 目录: $RIME_DIR${NC}"

# ============================================================
# 3. 备份现有配置
# ============================================================
echo -e "${YELLOW}[3/6]${NC} 备份现有配置..."

mkdir -p "$BACKUP_DIR"

# 备份可能被覆盖的文件
for file in default.custom.yaml squirrel.custom.yaml; do
    if [ -f "$RIME_DIR/$file" ]; then
        cp "$RIME_DIR/$file" "$BACKUP_DIR/"
        echo -e "  备份: $file"
    fi
done

# 备份已有的 hybrid_ime 文件
for file in hybrid_ime.schema.yaml hybrid_ime.dict.yaml; do
    if [ -f "$RIME_DIR/$file" ]; then
        cp "$RIME_DIR/$file" "$BACKUP_DIR/"
        echo -e "  备份: $file"
    fi
done

echo -e "${GREEN}  ✓ 备份完成: $BACKUP_DIR${NC}"

# ============================================================
# 4. 复制 Schema 配置
# ============================================================
echo -e "${YELLOW}[4/6]${NC} 安装 Schema 配置..."

# 复制 schema 文件到 Rime 目录
# 当前稳定版直接复用官方 luna_pinyin 作为中文主词库，
# 暂不安装实验性的 hybrid_ime.dict.yaml，避免大词库中的脏数据破坏部署。
for yaml_file in "$PROJECT_DIR/schema/"*.yaml; do
    if [ -f "$yaml_file" ]; then
        if [ "$(basename "$yaml_file")" = "hybrid_ime.dict.yaml" ]; then
            continue
        fi
        cp "$yaml_file" "$RIME_DIR/"
        echo -e "  安装: $(basename "$yaml_file")"
    fi
done
echo -e "${GREEN}  ✓ Schema 文件已安装${NC}"

# ============================================================
# 5. 复制 Lua 脚本和词典
# ============================================================
echo -e "${YELLOW}[5/6]${NC} 安装 Lua 脚本和词典..."

# 创建 lua 目录
mkdir -p "$RIME_DIR/lua"
cp "$PROJECT_DIR/lua/"*.lua "$RIME_DIR/lua/"
echo -e "  ✓ Lua 脚本已安装"

# 构建原生光标左移 helper，避免 Shift+符号时退化为 Shift+Left 选中
mkdir -p "$RIME_DIR/bin"
if command -v clang >/dev/null 2>&1; then
    if [ -f "$PROJECT_DIR/scripts/hybrid_cursor_left.m" ]; then
        clang \
            "$PROJECT_DIR/scripts/hybrid_cursor_left.m" \
            -framework AppKit \
            -framework ApplicationServices \
            -o "$RIME_DIR/bin/hybrid_cursor_left" >/dev/null 2>&1 || true
    else
        clang \
            "$PROJECT_DIR/scripts/hybrid_cursor_left.c" \
            -framework ApplicationServices \
            -o "$RIME_DIR/bin/hybrid_cursor_left" >/dev/null 2>&1 || true
    fi
fi
if [ -x "$RIME_DIR/bin/hybrid_cursor_left" ]; then
    echo -e "  ✓ 光标移动 helper 已安装"
else
    echo -e "  ${YELLOW}⚠ 光标移动 helper 构建失败，将回退到 osascript${NC}"
fi

# 创建 rime.lua 入口（如果不存在）
if [ ! -f "$RIME_DIR/rime.lua" ]; then
    cat > "$RIME_DIR/rime.lua" << 'EOF'
-- 程序猿输入法 入口
require("hybrid_init")
EOF
    echo -e "  ✓ rime.lua 已创建"
else
    # 检查是否已包含 hybrid_init
    if ! grep -q "hybrid_init" "$RIME_DIR/rime.lua"; then
        echo '' >> "$RIME_DIR/rime.lua"
        echo '-- 程序猿输入法 入口' >> "$RIME_DIR/rime.lua"
        echo 'require("hybrid_init")' >> "$RIME_DIR/rime.lua"
        echo -e "  ✓ rime.lua 已更新（追加 hybrid_init）"
    else
        echo -e "  ✓ rime.lua 已包含 hybrid_init"
    fi
fi

# 当前稳定版不安装自定义中文大词库和混合短语词库，
# 先确保中文候选基于官方词典稳定工作。

# 安装安全的小型开发词典（不包含实验性中文大词库）
if [ -d "$PROJECT_DIR/dicts" ]; then
    mkdir -p "$RIME_DIR/dicts"
    cp "$PROJECT_DIR/dicts/"*.dict.yaml "$RIME_DIR/dicts/" 2>/dev/null || true
    cp "$PROJECT_DIR/dicts/"*.txt "$RIME_DIR/dicts/" 2>/dev/null || true
    echo -e "  ✓ 开发词典已安装"
fi

# 复制英文词库（如果存在）
if [ -d "$PROJECT_DIR/en_dicts" ]; then
    mkdir -p "$RIME_DIR/en_dicts"
    cp -r "$PROJECT_DIR/en_dicts/"* "$RIME_DIR/en_dicts/" 2>/dev/null || true
    echo -e "  ✓ 英文词库已安装"
fi

echo -e "${GREEN}  ✓ 所有文件安装完成${NC}"

# 如果本地模型 sidecar 服务已经安装，则同步刷新其 stub 代码
if [ -f "$HOME/Library/LaunchAgents/com.hybridime.modeld.plist" ]; then
    if [ -x "$PROJECT_DIR/scripts/install_model_sidecar_service.sh" ]; then
        echo -e "  ✓ 检测到已安装的 sidecar 服务，正在刷新模型服务代码..."
        bash "$PROJECT_DIR/scripts/install_model_sidecar_service.sh" >/dev/null 2>&1 || true
    fi
fi

# ============================================================
# 6. 触发重新部署
# ============================================================
echo -e "${YELLOW}[6/6]${NC} 触发 Rime 重新部署..."

# 由于 Squirrel 自动化部署在较新 macOS 上常因为权限问题失败，这里改为通知用户手动操作
if command -v osascript &> /dev/null; then
    osascript -e 'display notification "请点击右上角输入法图标 → 重新部署" with title "程序猿输入法 安装完成"' 2>/dev/null || true
fi
echo -e "${YELLOW}  ⚠ 请手动点击右上角 Squirrel 菜单图标，选择「重新部署」${NC}"

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         程序猿输入法 安装成功！            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  使用提示："
echo -e "  1. 在系统设置 → 键盘 → 输入法 中添加 Squirrel"
echo -e "  2. 切换到 Squirrel 后，按 ${BLUE}Ctrl+\`${NC} 或 ${BLUE}F4${NC} 选择「程序猿输入法」"
echo -e "  3. 快捷键："
echo -e "     ${BLUE}Ctrl+Shift+1${NC} 或 ${BLUE}F5${NC} — 切换混合模式"
echo -e "     ${BLUE}Ctrl+Shift+2${NC} 或 ${BLUE}F6${NC} — 切换标点智能"
echo -e "     ${BLUE}Ctrl+Shift+3${NC} 或 ${BLUE}F7${NC} — 切换自动空格"
echo ""
echo -e "  备份位置: ${YELLOW}$BACKUP_DIR${NC}"
echo ""
