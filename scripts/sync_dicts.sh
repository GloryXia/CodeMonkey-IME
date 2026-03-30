#!/usr/bin/env bash
# ============================================================
# Hybrid IME — 词库同步脚本
# 从 rime-ice 仓库同步中英文词库
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RIME_ICE_REPO="https://github.com/iDvel/rime-ice.git"
TEMP_DIR="$PROJECT_DIR/.tmp_rime_ice"

echo -e "${BLUE}Hybrid IME — 词库同步${NC}"
echo ""

# 克隆 rime-ice（浅克隆）
echo -e "${YELLOW}[1/3]${NC} 下载 rime-ice 词库..."
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi
git clone --depth 1 "$RIME_ICE_REPO" "$TEMP_DIR"
echo -e "${GREEN}  ✓ 下载完成${NC}"

# 同步中文词库
echo -e "${YELLOW}[2/3]${NC} 同步中文词库..."
mkdir -p "$PROJECT_DIR/cn_dicts"
cp "$TEMP_DIR/cn_dicts/"*.yaml "$PROJECT_DIR/cn_dicts/" 2>/dev/null || true
echo -e "${GREEN}  ✓ 中文词库已同步${NC}"

# 同步英文词库
echo -e "${YELLOW}[3/3]${NC} 同步英文词库..."
mkdir -p "$PROJECT_DIR/en_dicts"
cp "$TEMP_DIR/en_dicts/"*.yaml "$PROJECT_DIR/en_dicts/" 2>/dev/null || true

# 同步英文方案
cp "$TEMP_DIR/melt_eng.schema.yaml" "$PROJECT_DIR/schema/" 2>/dev/null || true
cp "$TEMP_DIR/melt_eng.dict.yaml" "$PROJECT_DIR/schema/" 2>/dev/null || true
echo -e "${GREEN}  ✓ 英文词库已同步${NC}"

# 清理临时目录
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}词库同步完成！${NC}"
echo -e "  中文词库: $PROJECT_DIR/cn_dicts/"
echo -e "  英文词库: $PROJECT_DIR/en_dicts/"
echo ""
echo -e "运行 ${BLUE}make install${NC} 将词库安装到 Rime"
