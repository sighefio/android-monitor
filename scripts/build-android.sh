#!/usr/bin/env bash
set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/android"
cd "$ANDROID_DIR"

VARIANT="${1:-Debug}"
./gradlew "assemble${VARIANT}"
echo "APK: $(find app/build/outputs/apk -name '*.apk' | head -1)"
