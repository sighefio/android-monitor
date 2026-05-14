#!/usr/bin/env bash
set -euo pipefail

WIDTH="${WIDTH:-1920}"
HEIGHT="${HEIGHT:-1080}"
FPS="${FPS:-60}"
DURATION="${DURATION:-10}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg required for test pattern generation" >&2
  exit 1
fi

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i "testsrc=size=${WIDTH}x${HEIGHT}:rate=${FPS}" \
  -t "$DURATION" \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -bsf:v h264_mp4toannexb \
  -profile:v high -pix_fmt yuv420p \
  -g "$((FPS * 2))" -keyint_min "$FPS" -bf 0 \
  -f h264 -
