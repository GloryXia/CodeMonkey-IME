#!/usr/bin/env bash
# ============================================================
# 安装本地模型 sidecar 为 macOS 用户级 launchd 服务
# ============================================================

set -euo pipefail

LABEL="com.hybridime.modeld"
RIME_DIR="${HOME}/Library/Rime"
MODEL_DIR="${RIME_DIR}/modeld"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
RUNNER_PATH="${MODEL_DIR}/run_model_sidecar.sh"
STUB_PATH="${MODEL_DIR}/model_sidecar_stub.py"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_STUB="${PROJECT_DIR}/tools/modeld/model_sidecar_stub.py"
CONFIG_PATH="${RIME_DIR}/hybrid_ime_model.conf"
DEFAULT_ENDPOINT="http://127.0.0.1:39571/score_context"
PYTHON_BIN="$(command -v python3 || true)"

if [[ -z "${PYTHON_BIN}" ]]; then
  echo "✗ 未找到 python3，无法安装 sidecar 服务"
  exit 1
fi

mkdir -p "${MODEL_DIR}" "${LAUNCH_AGENTS_DIR}"
cp "${SOURCE_STUB}" "${STUB_PATH}"

cat > "${RUNNER_PATH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

exec "${PYTHON_BIN}" "${STUB_PATH}" --host 127.0.0.1 --port 39571
EOF
chmod +x "${RUNNER_PATH}"

cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${RUNNER_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${MODEL_DIR}</string>
  <key>StandardOutPath</key>
  <string>${MODEL_DIR}/model_sidecar.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${MODEL_DIR}/model_sidecar.stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>
</dict>
</plist>
EOF

if [[ ! -f "${CONFIG_PATH}" ]]; then
  cat > "${CONFIG_PATH}" <<EOF
enabled=true
endpoint=${DEFAULT_ENDPOINT}
timeout_ms=200
cache_ttl_ms=800
EOF
fi

launchctl bootout "gui/${UID}/${LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/${UID}" "${PLIST_PATH}"
launchctl kickstart -k "gui/${UID}/${LABEL}"

for _ in {1..10}; do
  if /usr/bin/curl --silent --show-error --fail http://127.0.0.1:39571/health >/dev/null 2>&1; then
    echo "✓ sidecar 服务已启动: ${LABEL}"
    echo "  plist: ${PLIST_PATH}"
    echo "  config: ${CONFIG_PATH}"
    exit 0
  fi
  sleep 1
done

echo "✗ sidecar 服务启动超时，请检查:"
echo "  stdout: ${MODEL_DIR}/model_sidecar.stdout.log"
echo "  stderr: ${MODEL_DIR}/model_sidecar.stderr.log"
exit 1
