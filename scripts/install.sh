#!/usr/bin/env bash
# ============================================================
# Hybrid IME — 安装脚本
# 将 Hybrid IME 配置安装到 macOS Rime (Squirrel) 用户目录
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
echo -e "${BLUE}║     Hybrid IME — 混合输入法 安装程序     ║${NC}"
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
cp "$PROJECT_DIR/schema/hybrid_ime.schema.yaml" "$RIME_DIR/"
cp "$PROJECT_DIR/schema/hybrid_ime.dict.yaml" "$RIME_DIR/"
cp "$PROJECT_DIR/schema/default.custom.yaml" "$RIME_DIR/"
cp "$PROJECT_DIR/schema/squirrel.custom.yaml" "$RIME_DIR/"
echo -e "${GREEN}  ✓ Schema 文件已安装${NC}"

# ============================================================
# 5. 复制 Lua 脚本和词典
# ============================================================
echo -e "${YELLOW}[5/6]${NC} 安装 Lua 脚本和词典..."

# 创建 lua 目录
mkdir -p "$RIME_DIR/lua"
cp "$PROJECT_DIR/lua/"*.lua "$RIME_DIR/lua/"
echo -e "  ✓ Lua 脚本已安装"

# 创建 rime.lua 入口（如果不存在）
if [ ! -f "$RIME_DIR/rime.lua" ]; then
    cat > "$RIME_DIR/rime.lua" << 'EOF'
-- Hybrid IME 入口
require("hybrid_init")
EOF
    echo -e "  ✓ rime.lua 已创建"
else
    # 检查是否已包含 hybrid_init
    if ! grep -q "hybrid_init" "$RIME_DIR/rime.lua"; then
        echo '' >> "$RIME_DIR/rime.lua"
        echo '-- Hybrid IME 入口' >> "$RIME_DIR/rime.lua"
        echo 'require("hybrid_init")' >> "$RIME_DIR/rime.lua"
        echo -e "  ✓ rime.lua 已更新（追加 hybrid_init）"
    else
        echo -e "  ✓ rime.lua 已包含 hybrid_init"
    fi
fi

# 复制自定义词典
mkdir -p "$RIME_DIR/dicts"
cp "$PROJECT_DIR/dicts/"*.yaml "$RIME_DIR/dicts/" 2>/dev/null || true
cp "$PROJECT_DIR/dicts/"*.txt "$RIME_DIR/dicts/" 2>/dev/null || true
echo -e "  ✓ 词典文件已安装"

# 复制中文词库（如果存在）
if [ -d "$PROJECT_DIR/cn_dicts" ]; then
    mkdir -p "$RIME_DIR/cn_dicts"
    cp -r "$PROJECT_DIR/cn_dicts/"* "$RIME_DIR/cn_dicts/" 2>/dev/null || true
    echo -e "  ✓ 中文词库已安装"
fi

# 复制英文词库（如果存在）
if [ -d "$PROJECT_DIR/en_dicts" ]; then
    mkdir -p "$RIME_DIR/en_dicts"
    cp -r "$PROJECT_DIR/en_dicts/"* "$RIME_DIR/en_dicts/" 2>/dev/null || true
    echo -e "  ✓ 英文词库已安装"
fi

echo -e "${GREEN}  ✓ 所有文件安装完成${NC}"

# ============================================================
# 6. 触发重新部署
# ============================================================
echo -e "${YELLOW}[6/6]${NC} 触发 Rime 重新部署..."

# 通过通知触发 Squirrel 重新部署
if command -v osascript &> /dev/null; then
    osascript -e 'tell application id "im.rime.inputmethod.Squirrel" to deploy' 2>/dev/null || true
    echo -e "${GREEN}  ✓ 已触发重新部署${NC}"
else
    echo -e "${YELLOW}  ⚠ 请手动在 Squirrel 菜单中点击「重新部署」${NC}"
fi

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Hybrid IME 安装成功！            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  使用提示："
echo -e "  1. 在系统设置 → 键盘 → 输入法 中添加 Squirrel"
echo -e "  2. 切换到 Squirrel 后，按 ${BLUE}Ctrl+\`${NC} 或 ${BLUE}F4${NC} 选择「混合输入法」"
echo -e "  3. 快捷键："
echo -e "     ${BLUE}Ctrl+Shift+H${NC} — 切换混合模式"
echo -e "     ${BLUE}Ctrl+Shift+P${NC} — 切换标点智能"
echo -e "     ${BLUE}Ctrl+Shift+S${NC} — 切换自动空格"
echo ""
echo -e "  备份位置: ${YELLOW}$BACKUP_DIR${NC}"
echo ""
