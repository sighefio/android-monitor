# android-monitor

Use an Android phone or tablet as an external monitor for macOS (Linux support planned).

## Goal

Lowest possible glass-to-glass latency. Every API and architecture choice is made to serve that goal. Do not introduce abstractions or dependencies that add latency.

## Scope — v1 is mirror-only

**v1 mirrors an existing macOS display; it does not create a new one.** The Android device will **not** appear in **System Settings → Displays** and cannot be used as an extended desktop. You pick one of the real `SCDisplay`s the host enumerates (built-in, or an attached monitor), and that display's pixels stream to Android. Touch and keyboard events are injected back into the same display.

Why: `ScreenCaptureKit` is a one-way *read* API. macOS has no public API for third parties to publish a virtual display. Apps that *do* show up in Display Settings (Sidecar, Duet, Luna, Astropad) either use Apple-private frameworks or a signed DriverKit system extension, both of which are out of scope for v1.

A future "virtual display" milestone is tracked separately (see `docs/ARCHITECTURE.md` → Roadmap). It would add a `Sources/VirtualDisplay/` module that publishes a `CGDirectDisplayID` — likely via a DriverKit `.dext` — and point `CaptureSession` at that ID instead of a physical one. The encoder, network, decoder, and input layers stay unchanged. **Do not start that work without explicit direction**; it requires Apple entitlements and a system extension review path that v1 does not need.

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐     TCP port 7878
│  macOS Host Daemon (Swift)                  │ ←───────────────── Android App (Kotlin)
│                                             │                      │
│  ScreenCaptureKit → VideoToolbox (H.264)    │ ──VIDEO_FRAME──────► │  MediaCodec → SurfaceView
│  SCK system audio → AudioConverter (AAC)   │ ──AUDIO_FRAME──────► │  MediaCodec → AudioTrack (low-latency)
│  CGEvent injection ←────────────────────── │ ◄─TOUCH_EVENT────── │  MotionEvent capture
│  CGEvent injection ←────────────────────── │ ◄─KEY_EVENT──────── │  InputConnection
└─────────────────────────────────────────────┘                      │
         ▲                                                            │
         │  USB mode: adb forward tcp:7878 tcp:7878                  │
         │  WiFi mode: direct TCP to host IP                         │
         └────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
android-monitor/
├── host/                              # macOS host daemon
│   ├── Package.swift                  # Swift Package Manager manifest
│   └── Sources/
│       ├── AndroidMonitorDaemon/      # Executable target (CLI daemon — not a menu-bar app)
│       │   ├── main.swift             # Entry point, argument parsing, SIGINT handler
│       │   └── StreamCoordinator.swift # Wires capture → encode → dispatcher → server; owns per-connection encoder lifecycle
│       ├── Core/                      # Shared library target
│       │   ├── Protocol.swift         # ALL wire format constants (magic, types, flags) — single source of truth
│       │   ├── Config.swift           # ServerConfig, ConnectionMode enum, port constant (7878)
│       │   └── Logger.swift           # os.log wrapper
│       ├── Capture/
│       │   ├── ScreenCaptureManager.swift   # SCShareableContent query, display enumeration
│       │   ├── DisplayPicker.swift           # Expose SCDisplay list to network layer
│       │   ├── CaptureSession.swift          # SCStreamOutput delegate — entry point for every frame
│       │   └── LinuxCapture/                 # Stub directory for future Linux port (not compiled on macOS)
│       ├── Encode/
│       │   ├── VideoEncoder.swift     # VTCompressionSession — converts CMSampleBuffer → AVCC NAL Data only
│       │   ├── EncoderConfig.swift    # Bitrate, keyframe interval, profile, resolution/fps settings
│       │   └── NALPacketizer.swift    # Wraps AVCC NAL Data into VIDEO_FRAME wire packet
│       ├── Audio/
│       │   ├── AudioCaptureManager.swift  # SCK capturesAudio=true (macOS 13+); AVAudioEngine fallback
│       │   ├── AudioEncoder.swift         # AudioConverter PCM → AAC-LC 128kbps
│       │   └── AACPacketizer.swift        # Wraps AAC ADTS into AUDIO_FRAME wire packet
│       ├── Network/
│       │   ├── ConnectionServer.swift     # NWListener (TCP) — accepts client connections
│       │   ├── ClientSession.swift        # Per-client NWConnection handler
│       │   ├── FrameDispatcher.swift      # Distributes encoded frames to active sessions
│       │   └── ProtocolEncoder.swift      # Serialize packet structs → wire bytes
│       ├── Input/
│       │   ├── InputDecoder.swift         # Deserialize TOUCH_EVENT / KEY_EVENT packets
│       │   ├── TouchEventInjector.swift   # CGEvent synthetic mouse events (dependency-injected for tests)
│       │   ├── KeyboardInjector.swift     # CGEvent keyboard injection (dependency-injected for tests)
│       │   └── KeycodeMap.swift           # Android keycode → CGKeyCode lookup table
│       └── USB/
│           ├── ADBForwardManager.swift    # Shells out to `adb forward tcp:7878 tcp:7878`
│           └── DeviceWatcher.swift        # IOKit IOUSBHost plug/unplug notifications
│   └── Tests/
│       ├── ProtocolTests/PacketSerializationTests.swift
│       ├── EncoderTests/VideoEncoderTests.swift
│       └── InputTests/TouchInjectorTests.swift
│
├── android/                           # Android app
│   ├── build.gradle.kts
│   ├── settings.gradle.kts
│   ├── gradle/libs.versions.toml      # Version catalog
│   └── app/src/main/kotlin/com/androidmonitor/
│       ├── MainActivity.kt
│       ├── App.kt                     # Application class
│       ├── ui/
│       │   ├── MainScreen.kt          # Jetpack Compose root
│       │   ├── DisplaySurface.kt      # SurfaceView embedded in Compose (AndroidView)
│       │   ├── ConnectScreen.kt
│       │   └── SettingsScreen.kt      # Resolution/FPS scaling controls
│       ├── connection/
│       │   ├── Protocol.kt            # ALL wire format constants — mirrors host/Sources/Core/Protocol.swift
│       │   ├── ConnectionManager.kt   # WiFi/USB mode switching, reconnect logic
│       │   ├── TcpClient.kt           # NIO-based TCP socket with Kotlin coroutines
│       │   ├── PacketReader.kt        # Frame delimiter, fragment reassembly, dispatch
│       │   └── PacketWriter.kt        # Serialize control/input packets → bytes
│       ├── codec/
│       │   ├── VideoDecoder.kt        # MediaCodec async API, KEY_LOW_LATENCY=1, Surface hand-off
│       │   ├── AudioPlayer.kt         # Oboe AudioStream (AAudio low-latency), PCM ring buffer
│       │   └── CodecConfig.kt         # Negotiated params from HANDSHAKE_ACK
│       ├── input/
│       │   ├── TouchHandler.kt        # MotionEvent → normalized TOUCH_EVENT packets
│       │   └── KeyboardHandler.kt     # InputConnection → KEY_EVENT packets
│       └── usb/
│           └── UsbModeInfo.kt         # UI: "Enable USB debugging / Connect cable" instructions
│
├── protocol/PROTOCOL.md               # Canonical wire format documentation
├── scripts/
│   ├── build-host.sh                  # swift build + codesign (screen-recording entitlement)
│   ├── build-android.sh               # ./gradlew assembleDebug
│   ├── install-android.sh             # build APK + adb install + adb forward tcp:7878 tcp:7878
│   ├── run-e2e.sh                     # Start daemon + deploy APK + connect (automated E2E)
│   └── gen-test-video.sh              # ffmpeg test pattern for codec unit tests
└── docs/
    ├── ARCHITECTURE.md
    ├── LATENCY.md                     # Measured glass-to-glass numbers per release
    └── LINUX_NOTES.md                 # Future Linux port notes (PipeWire/X11/Wayland)
```

### SPM Target Graph (host)

The host is split into 7 library targets plus one executable. Dependencies flow strictly upward — keep them that way when adding code.

```
Core ── (no deps)
 ├── Capture   (excludes LinuxCapture/ on macOS builds)
 ├── Encode
 ├── Audio
 ├── Input
 ├── USB
 └── Network   ── depends on Encode, Audio
AndroidMonitorDaemon ── depends on all of the above
```

Tests: `ProtocolTests` (→ Core), `EncoderTests` (→ Encode), `InputTests` (→ Input). When adding a new module, mirror this pattern in `host/Package.swift`.

---

## Wire Protocol

### Packet Header (24 bytes, always)

```
Offset  Size  Field
0       2     MAGIC: 0xAD 0x01
2       1     TYPE (see packet types below)
3       1     FLAGS (bitfield, see below)
4       4     LENGTH: payload size in bytes, uint32 big-endian (max 4 MB enforced by receiver)
8       8     SEQ: monotonically increasing uint64, big-endian, per-connection
16      8     TIMESTAMP_US: host mach_absolute_time in microseconds, uint64 big-endian
```

> Total header = 24 bytes. SEQ is per-connection (not per type). Gaps in SEQ indicate a connection reset, not packet loss (TCP guarantees delivery).

### Packet Types

| Value  | Name            | Direction       | Payload |
|--------|-----------------|-----------------|---------|
| `0x01` | HANDSHAKE_REQ   | Android → Host  | JSON: `{"version":1,"capabilities":["h264","aac"],"screen_w":<px>,"screen_h":<px>,"screen_fps":<int>}` |
| `0x02` | HANDSHAKE_ACK   | Host → Android  | JSON: `{"version":1,"video_w":<px>,"video_h":<px>,"fps":<int>,"bitrate_kbps":<int>,"audio_sample_rate":48000}` |
| `0x03` | HANDSHAKE_ERR   | Host → Android  | JSON: `{"code":<int>,"message":"<str>"}` |
| `0x10` | VIDEO_FRAME     | Host → Android  | `[DISPLAY_ID: 1B][AVCC NAL data]` |
| `0x11` | AUDIO_FRAME     | Host → Android  | `[CHANNEL_COUNT: 1B][SAMPLE_RATE_DIV100: 1B][AAC ADTS data]` |
| `0x20` | TOUCH_EVENT     | Android → Host  | 14 bytes fixed: `[ACTION:1B][PTR_ID:1B][X_NORM:f32BE][Y_NORM:f32BE][PRESSURE:f32BE]` |
| `0x21` | KEY_EVENT       | Android → Host  | 8 bytes fixed: `[ACTION:1B][MODIFIERS:1B][ANDROID_KEYCODE:2B BE][UNICODE_CHAR:4B BE UTF-32]` |
| `0x30` | DISPLAY_LIST    | Host → Android  | JSON array of display descriptors |
| `0x31` | SELECT_DISPLAY  | Android → Host  | JSON: `{"display_id":<int>}` |
| `0x40` | PING            | Either          | 8-byte uint64 echo payload |
| `0x41` | PONG            | Either          | Echo of PING payload |
| `0x50` | STREAM_PAUSE    | Either          | Empty |
| `0x51` | STREAM_RESUME   | Either          | Empty |

### FLAGS Bitfield

| Bit | Meaning |
|-----|---------|
| 0   | KEY_FRAME — video IDR/keyframe (SPS+PPS prepended) |
| 1   | FRAME_START — first packet of a fragmented frame |
| 2   | FRAME_END — last packet of a fragmented frame |
| 3   | COMPRESSED — payload is zstd-compressed (control packets only) |
| 4–7 | Reserved |

### Resolution / FPS Negotiation

The Android client reports its **physical display dimensions and refresh rate** in `HANDSHAKE_REQ` (`screen_w`, `screen_h`, `screen_fps`). The host replies in `HANDSHAKE_ACK` with the actual stream parameters, which must be **≤ the requested values**. This allows:

- **Default (full quality)**: host streams at the Android device's native resolution and refresh rate.
- **User-reduced quality**: `SettingsScreen.kt` exposes a scale factor (e.g. 50%, 75%, 100%) and max FPS selector. These override the values sent in `HANDSHAKE_REQ` before connecting.

The host never upscales beyond the Android screen's native resolution. `EncoderConfig.swift` clamps `videoWidth` and `videoHeight` to the values negotiated at handshake.

### Handshake Sequence

```
Android connects (TCP or ADB-forwarded TCP)
  → HANDSHAKE_REQ  (capabilities, Android screen geometry, desired fps)
  ← HANDSHAKE_ACK  (negotiated codec params: resolution ≤ Android native, fps ≤ Android native)
  ← DISPLAY_LIST   (available macOS displays)
  → SELECT_DISPLAY (chosen display)
  ← VIDEO_FRAME    (stream begins; first frame is IDR with SPS/PPS prepended)
  ← AUDIO_FRAME    (interleaved)
  → TOUCH_EVENT / KEY_EVENT  (as user interacts)
  ↔ PING/PONG      (every 5 seconds; dead-connection detection)
```

### Touch Event Actions

`0x00=DOWN`, `0x01=MOVE`, `0x02=UP`, `0x03=CANCEL`. X/Y are normalized 0.0–1.0 relative to Android display size. macOS scales to the selected CGDisplay's pixel frame.

### Key Event Fields

`ACTION`: `0x00=DOWN`, `0x01=UP`. `MODIFIERS` bitmask: bit0=Shift, bit1=Ctrl, bit2=Alt/Option, bit3=Meta/Cmd. If `UNICODE_CHAR != 0`, macOS uses `CGEventKeyboardSetUnicodeString`; otherwise maps `ANDROID_KEYCODE` via `KeycodeMap.swift`.

---

## Port

**7878** (0x1EB6). Configured in `host/Sources/Core/Config.swift` and `android/.../connection/Protocol.kt`.

---

## Tech Stack Decisions

These choices are final. Do not propose alternatives without a measurable latency advantage.

### macOS: ScreenCaptureKit (not CGDisplayStream, not AVFoundation)

- Delivers frames as `CMSampleBuffer` wrapping an `IOSurface` — passed directly to VideoToolbox **without a CPU copy**.
- Built-in system audio capture (`SCStreamConfiguration.capturesAudio = true`, macOS 13+).
- Native NV12 (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`) output — VideoToolbox's preferred input format.
- Per-display, per-window, per-app filtering via `SCContentFilter`.
- ~1-frame latency vs ~3-4 frames for AVFoundation.

### macOS: VideoToolbox (not FFmpeg, not libx264)

- GPU hardware encoder (Apple Silicon VideoEncoderKit / Intel Media Engine).
- `kVTCompressionPropertyKey_MaxFrameDelayCount = 0` — zero frame buffer.
- Direct IOSurface input — no CPU readback.
- `kVTCompressionPropertyKey_RealTime = true`.
- No binary dependencies.

Key properties set at session init:

```swift
kVTCompressionPropertyKey_RealTime: true
kVTCompressionPropertyKey_MaxFrameDelayCount: 0
kVTCompressionPropertyKey_AllowFrameReordering: false   // NO B-frames — ever
kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel
kVTCompressionPropertyKey_H264EntropyMode: kVTH264EntropyMode_CABAC
kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: false  // graceful SW fallback
```

### macOS Audio: SCK system audio (not BlackHole, not Soundflower)

`SCStreamConfiguration.capturesAudio = true` captures system output directly since macOS 13. Audio and video arrive in the same delegate callback with a shared timebase — simplifies A/V sync. PCM → AAC-LC 128kbps via `AudioConverter`.

Fallback (macOS 12, guarded by `@available`): `AVAudioEngine` tap on output node (requires user-installed loopback driver).

### Android: MediaCodec async API with `KEY_LOW_LATENCY = 1`

```kotlin
val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
    setInteger(MediaFormat.KEY_LOW_LATENCY, 1)     // disables internal reorder buffer
    setInteger(MediaFormat.KEY_PRIORITY, 0)         // realtime priority
    setInteger(MediaFormat.KEY_OPERATING_RATE, fps) // hint to codec scheduler
}
codec.configure(format, surface, null, 0)
codec.setCallback(callback, handler)
```

`releaseOutputBuffer(index, true)` renders directly to the `Surface` — no CPU readback.

### Android Audio: AudioTrack with `PERFORMANCE_MODE_LOW_LATENCY` (Oboe upgrade planned)

Initial scaffold uses `AudioTrack.Builder().setPerformanceMode(PERFORMANCE_MODE_LOW_LATENCY)` which on API 26+ routes through AAudio under the hood (~10–20ms latency). AAC is decoded by a second `MediaCodec` instance; PCM is fed into the AudioTrack with `WRITE_NON_BLOCKING`.

A future migration to Oboe (NDK/JNI) is planned for sub-10ms latency. Until then, do not introduce extra audio buffering — keep the MediaCodec → AudioTrack hand-off direct.

### Networking: Network.framework on host, raw NIO sockets on Android

No third-party networking libraries on either side.

---

## Performance Targets

| Metric | Target |
|--------|--------|
| Glass-to-glass latency (WiFi) | < 50ms |
| Glass-to-glass latency (USB) | < 20ms |
| Default FPS | Android device native (e.g. 60 or 120 Hz) |
| Minimum FPS | 30 fps (user-selectable) |
| Default resolution | Android device native |
| Minimum resolution | 50% scale (user-selectable) |
| Default bitrate | 8 Mbps |
| Adaptive bitrate floor (WiFi) | 2 Mbps |
| USB bitrate ceiling | 20 Mbps |
| Host daemon RSS | < 100 MB |
| Android app RSS | < 150 MB |

Latency budget breakdown (WiFi, 60fps):

| Stage | Budget |
|-------|--------|
| ScreenCaptureKit capture | ~4ms |
| VideoToolbox H.264 encode | ~3ms |
| TCP send over WiFi | ~5ms |
| TCP receive + reassemble | ~1ms |
| MediaCodec H.264 decode | ~4ms |
| Surface → display (compositor) | ~8ms |
| **Total** | **~25ms typical** |

---

## Development Commands

### Host Daemon (macOS)

```bash
# Debug build
cd host && swift build

# Release build
cd host && swift build -c release

# Run (requires Screen Recording permission in System Settings)
# Flags: --port <port> (default 7878), --bitrate <kbps>, --mode <wifi|usb|both>
.build/debug/AndroidMonitorDaemon --port 7878 --bitrate 8000 --mode both

# Run tests
swift test

# Build + codesign for Screen Recording entitlement
scripts/build-host.sh
```

### Android App

```bash
cd android

# Build debug APK
./gradlew assembleDebug

# Install to connected device
./gradlew installDebug

# Unit tests (JVM)
./gradlew test

# Instrumentation tests (device required)
./gradlew connectedAndroidTest
```

### End-to-End Testing

```bash
# USB mode (device connected via cable)
scripts/install-android.sh
# Runs: ./gradlew installDebug && adb install ... && adb forward tcp:7878 tcp:7878
# Then: adb shell am start -n com.androidmonitor/.MainActivity

# Full automated E2E
scripts/run-e2e.sh

# WiFi mode
ipconfig getifaddr en0   # get Mac IP
# Start daemon, then enter IP in Android app: Settings → Connection → WiFi
```

### Codec Smoke Test (no Android device needed)

```bash
scripts/gen-test-video.sh | nc localhost 7878
```

---

## Hard Constraints — Never Violate

1. **No WebRTC, GStreamer, or FFmpeg** in the encode/decode critical path. `scripts/` is the only place FFmpeg is permitted (test pattern generation).
2. **No B-frames.** `kVTCompressionPropertyKey_AllowFrameReordering` must always be `false`. The protocol assumes decode order = display order.
3. **No third-party networking** on the host. Network.framework (`NWListener`/`NWConnection`) only.
4. **Never buffer video frames** on the Android side beyond the MediaCodec input queue. `PacketReader` must call `VideoDecoder.queueNAL()` on the IO thread with no intermediate queue.
5. **All protocol constants** (magic bytes, type values, flag bits, port) live exclusively in `host/Sources/Core/Protocol.swift` and `android/.../connection/Protocol.kt`. No magic numbers elsewhere.
6. **Packet TYPE byte values are permanent** once assigned. Add new types; never repurpose existing ones.
7. **`VideoEncoder.swift` has exactly one job**: convert `CMSampleBuffer` → `Data` (AVCC NAL). It does not know about TCP. `NALPacketizer.swift` wraps that data into a wire packet. Keep these layers separate.
8. **Resolution and FPS are negotiated per-connection** based on the Android device's physical display settings. The host never streams at a higher resolution or FPS than the Android client reported. The user may request lower values.

---

## Code Style

### Swift (host)

- `async/await` for all async operations — no completion-handler chains.
- `actor` for shared mutable state (`ConnectionServer`, `VideoEncoder`, `FrameDispatcher`).
- No force-unwraps (`!`) in production code paths. Use `guard let` or `Result<>`.
- Follow Swift API Design Guidelines.
- Minimum deployment target: **macOS 13.0**. All SCK audio APIs behind `@available(macOS 13.0, *)`.

### Kotlin (Android)

- `Flow` (not `LiveData`) for stream pipelines.
- `Dispatchers.IO` for socket operations; `Dispatchers.Default` for codec work.
- No `runBlocking` in production code paths.
- Follow Kotlin coding conventions.
- `minSdk = 28`. APIs above minSdk require `@RequiresApi` annotations and runtime guards.

---

## File Organization Rules

- `host/Sources/Core/Protocol.swift` — all wire format constants, packet type enums, header serialization/deserialization.
- `android/.../connection/Protocol.kt` — mirrors the above exactly. When you change one, change both.
- `host/Sources/Capture/LinuxCapture/` — future Linux port stub. Do **not** add `#if os(Linux)` guards into existing macOS files; add new files in this directory.
- `TouchEventInjector.swift` and `KeyboardInjector.swift` must be independently testable via dependency-injected CGEvent factory.

---

## Testing Conventions

- Every new packet type requires round-trip serialization tests in:
  - `host/Tests/ProtocolTests/PacketSerializationTests.swift`
  - `android/app/src/test/.../PacketReaderTest.kt`
- `VideoEncoder` and `VideoDecoder` integration tests run against a pre-encoded H.264 file from `scripts/gen-test-video.sh`. These must pass before any codec-touching commit.
- Latency regressions > 5ms must be noted in the PR description with a reference measurement in `docs/LATENCY.md`.

---

## USB Mode

ADB reuses the exact same TCP protocol — it creates a port-forward tunnel over the USB cable:

```bash
adb forward tcp:7878 tcp:7878
```

This maps `localhost:7878` on the Mac to `localhost:7878` on the Android device. The Android app's `ConnectionManager.kt` connects to `127.0.0.1:7878` in USB mode and the macOS IP in WiFi mode — the rest of the stack is identical.

`DeviceWatcher.swift` uses IOKit `IOUSBHost` notifications to detect Android devices and triggers `ADBForwardManager.swift` automatically. `ADBForwardManager` also calls `adb forward --remove tcp:7878` on disconnect.

---

## Linux Port (Future)

Screen capture for Linux lives in `host/Sources/Capture/LinuxCapture/` (stub directory, not compiled on macOS). Planned capture APIs: PipeWire (Wayland), X11/XCB (X11). Encode: VAAPI (Intel/AMD) or NVENC (NVIDIA) via a thin C wrapper. Do not add Linux-specific code to existing macOS files.

See `docs/LINUX_NOTES.md` for notes as they accumulate.
