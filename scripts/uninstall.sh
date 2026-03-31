#!/usr/bin/env bash
# ============================================================
# 程序猿输入法 — 卸载脚本
# 从 macOS Rime (Squirrel) 用户目录移除 程序猿输入法
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

RIME_DIR="$HOME/Library/Rime"

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     程序猿输入法 — 程序猿输入法 卸载程序     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

read -p "确认卸载 程序猿输入法？(y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}卸载已取消${NC}"
    exit 0
fi

echo -e "${YELLOW}[1/4]${NC} 删除 Schema 文件..."
rm -f "$RIME_DIR/hybrid_ime.schema.yaml"
rm -f "$RIME_DIR/hybrid_ime.dict.yaml"
echo -e "${GREEN}  ✓ Schema 文件已删除${NC}"

echo -e "${YELLOW}[2/4]${NC} 删除 Lua 脚本..."
rm -f "$RIME_DIR/lua/hybrid_init.lua"
rm -f "$RIME_DIR/lua/hybrid_processor.lua"
rm -f "$RIME_DIR/lua/punctuation_processor.lua"
rm -f "$RIME_DIR/lua/auto_space_filter.lua"
rm -f "$RIME_DIR/lua/hybrid_filter.lua"
rm -f "$RIME_DIR/lua/context_detector.lua"
rm -f "$RIME_DIR/lua/utils.lua"
echo -e "${GREEN}  ✓ Lua 脚本已删除${NC}"

echo -e "${YELLOW}[3/4]${NC} 清理 rime.lua..."
if [ -f "$RIME_DIR/rime.lua" ]; then
    # 移除 hybrid_init 相关行
    sed -i '' '/hybrid_init/d' "$RIME_DIR/rime.lua" 2>/dev/null || true
    sed -i '' '/程序猿输入法/d' "$RIME_DIR/rime.lua" 2>/dev/null || true
    echo -e "${GREEN}  ✓ rime.lua 已清理${NC}"
fi

echo -e "${YELLOW}[4/4]${NC} 恢复备份..."
# 查找最新备份
LATEST_BACKUP=$(ls -td "$RIME_DIR"/.hybrid_ime_backup_* 2>/dev/null | head -1)
if [ -n "$LATEST_BACKUP" ] && [ -d "$LATEST_BACKUP" ]; then
    read -p "  发现备份 $LATEST_BACKUP，是否恢复？(y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "$LATEST_BACKUP/"* "$RIME_DIR/" 2>/dev/null || true
        echo -e "${GREEN}  ✓ 备份已恢复${NC}"
    fi
else
    echo -e "  未找到备份文件"
fi

# 触发重新部署
echo ""
echo -e "触发 Rime 重新部署..."
osascript -e 'tell application id "im.rime.inputmethod.Squirrel" to deploy' 2>/dev/null || true

echo ""
echo -e "${GREEN}程序猿输入法 已成功卸载${NC}"
echo -e "注：自定义词典目录 $RIME_DIR/dicts 未删除，如需请手动删除"
echo ""
