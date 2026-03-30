#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="BulingIsland"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

echo "结束旧进程（若正在运行）…"
killall "$APP_NAME" 2>/dev/null || true
sleep 0.45

"$SCRIPT_DIR/build.sh"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "错误: 未找到 $APP_BUNDLE"
  exit 1
fi

if [[ -d "$DEST" ]]; then
  echo "备份现有版本到 ${DEST}.backup …"
  rm -rf "${DEST}.backup"
  mv "$DEST" "${DEST}.backup"
fi

echo "安装到 $DEST …"
cp -R "$APP_BUNDLE" "$DEST"

echo "启动 $APP_NAME …"
open "$DEST"

echo ""
echo "已完成：安装并启动新版本。"
