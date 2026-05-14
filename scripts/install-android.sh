#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-7878}"

cd "$ROOT/android"
./gradlew installDebug

adb forward tcp:"$PORT" tcp:"$PORT"
echo "adb forward tcp:$PORT tcp:$PORT installed"

adb shell am start -n com.androidmonitor/.MainActivity
