#!/usr/bin/env bash
set -euo pipefail

HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/host"
cd "$HOST_DIR"

CONFIG="${1:-debug}"
case "$CONFIG" in
  debug)   swift build ;;
  release) swift build -c release ;;
  *)       echo "usage: $0 [debug|release]"; exit 2 ;;
esac

BIN_PATH=".build/${CONFIG}/AndroidMonitorDaemon"
if [[ -f "$BIN_PATH" ]]; then
  codesign --force --sign - --entitlements <(cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <false/>
</dict>
</plist>
EOF
) "$BIN_PATH"
  echo "built and signed: $BIN_PATH"
else
  echo "build artifact not found: $BIN_PATH" >&2
  exit 1
fi
