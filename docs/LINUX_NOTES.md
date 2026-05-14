# Linux port notes

This document accumulates design notes for adding Linux support. Linux code lives under `host/Sources/Capture/LinuxCapture/` and is excluded from the macOS build via `Package.swift`.

## Screen capture

Two pipelines, one chosen at runtime:

1. **PipeWire (Wayland and modern X11)**: use the `xdg-desktop-portal` ScreenCast API. Receives DMA-BUF or shared-memory frames; for low-latency we want DMA-BUF + hardware encode.
2. **X11/XCB direct**: legacy fallback using `XShmGetImage` for older systems. Higher CPU; no zero-copy.

## H.264 encode

- Intel/AMD: VAAPI (`libva-drm`) — direct DMA-BUF input.
- NVIDIA: NVENC via NVENC SDK.
- Software fallback: `libx264 --tune zerolatency` (last resort).

## Audio

PipeWire audio capture (PCM 48kHz stereo) → AAC encoder (libfdk-aac preferred; libavcodec AAC acceptable).

## Input injection

- Wayland: there is no general synthetic input API. Use `libei` (Emulated Input) where available, or fall back to `uinput` (`/dev/uinput`) which requires extra permissions.
- X11: `XTestFakeKeyEvent`, `XTestFakeMotionEvent`, `XTestFakeButtonEvent`.

## USB / ADB

Same as macOS: shell out to `adb forward tcp:7878 tcp:7878`. The Swift `Process` API works identically on Linux when building with the Swift Linux toolchain.

## Build

Swift on Linux is supported via `swift-corelibs-foundation` and `swift-corelibs-libdispatch`. Network.framework is **macOS-only**; the Linux port needs a separate networking abstraction (raw POSIX sockets or `NIO`).

Treat the networking layer as an abstraction boundary: introduce a `Transport` protocol in `Core` so the Linux port can swap implementations without touching the rest of the code.
