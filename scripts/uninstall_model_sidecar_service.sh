#!/usr/bin/env bash
# ============================================================
# 卸载本地模型 sidecar 的 macOS 用户级 launchd 服务
# ============================================================

set -euo pipefail

LABEL="com.hybridime.modeld"
RIME_DIR="${HOME}/Library/Rime"
MODEL_DIR="${RIME_DIR}/modeld"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"

launchctl bootout "gui/${UID}/${LABEL}" >/dev/null 2>&1 || true
rm -f "${PLIST_PATH}"
rm -f "${MODEL_DIR}/run_model_sidecar.sh"
rm -f "${MODEL_DIR}/model_sidecar_stub.py"

echo "✓ sidecar 服务已卸载: ${LABEL}"
echo "  已删除: ${PLIST_PATH}"
echo "  保留日志目录: ${MODEL_DIR}"
