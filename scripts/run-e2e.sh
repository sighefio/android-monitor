#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-7878}"

cleanup() {
  if [[ -n "${DAEMON_PID:-}" ]] && kill -0 "$DAEMON_PID" 2>/dev/null; then
    kill "$DAEMON_PID" || true
  fi
  adb forward --remove tcp:"$PORT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

bash "$ROOT/scripts/build-host.sh" debug

"$ROOT/host/.build/debug/AndroidMonitorDaemon" --port "$PORT" &
DAEMON_PID=$!

sleep 1
bash "$ROOT/scripts/install-android.sh"

echo "daemon PID $DAEMON_PID — press Ctrl-C to stop"
wait "$DAEMON_PID"
