# Latency measurements

## Measurement methodology

End-to-end glass-to-glass latency is measured by:

1. Display a millisecond clock on the macOS side (e.g. `clock` shell pattern in a maximized terminal).
2. Point an Android camera at both the macOS screen AND the Android-monitor surface side-by-side.
3. Capture a 240fps slow-motion video.
4. Diff frame numbers between the two clocks across multiple sample points.

## Targets

- USB (ADB-forwarded): < 20 ms
- WiFi (5GHz, same AP): < 50 ms
- Audio: < 30 ms

## Recorded measurements

| Date | Commit | Mode | Resolution | FPS | Median (ms) | p95 (ms) | Notes |
|------|--------|------|------------|-----|-------------|----------|-------|
| —    | —      | —    | —          | —   | —           | —        | initial scaffold; no measurements yet |

Regressions exceeding 5ms must be referenced in the PR description.
