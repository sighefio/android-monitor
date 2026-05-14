# android-monitor wire protocol

Version 1. Custom binary protocol over TCP. Used identically over WiFi and ADB-forwarded USB (port 7878).

## Header (22 bytes, big-endian)

```
0       1       2       3       4       5       6       7       8
+-------+-------+-------+-------+-------+-------+-------+-------+
| MAGIC_0 (0xAD)| MAGIC_1 (0x01)| TYPE  | FLAGS | LENGTH (u32) |
+-------+-------+-------+-------+-------+-------+-------+-------+
| SEQUENCE NUMBER (u64)                                         |
+-------+-------+-------+-------+-------+-------+-------+-------+
| TIMESTAMP_US (u64, host mach_absolute_time in microseconds)   |
+-------+-------+-------+-------+-------+-------+-------+-------+
```

- LENGTH ≤ 4 MB. Receivers must reject anything larger.
- SEQUENCE is monotonically increasing per-connection (not per-type). Gaps imply a connection reset.
- TIMESTAMP_US is used for A/V sync only; not for display timing.

## Packet Types

| Hex   | Name           | Direction       |
|-------|----------------|-----------------|
| 0x01  | HANDSHAKE_REQ  | Android → Host  |
| 0x02  | HANDSHAKE_ACK  | Host → Android  |
| 0x03  | HANDSHAKE_ERR  | Host → Android  |
| 0x10  | VIDEO_FRAME    | Host → Android  |
| 0x11  | AUDIO_FRAME    | Host → Android  |
| 0x20  | TOUCH_EVENT    | Android → Host  |
| 0x21  | KEY_EVENT      | Android → Host  |
| 0x30  | DISPLAY_LIST   | Host → Android  |
| 0x31  | SELECT_DISPLAY | Android → Host  |
| 0x40  | PING           | Either          |
| 0x41  | PONG           | Either          |
| 0x50  | STREAM_PAUSE   | Either          |
| 0x51  | STREAM_RESUME  | Either          |

## FLAGS

- bit 0 (0x01): KEY_FRAME — H.264 IDR (SPS/PPS prepended)
- bit 1 (0x02): FRAME_START — first packet of fragmented frame
- bit 2 (0x04): FRAME_END — last packet of fragmented frame
- bit 3 (0x08): COMPRESSED — payload is zstd-compressed (control packets only)

## Payloads

### HANDSHAKE_REQ (JSON)
```json
{ "version": 1, "capabilities": ["h264", "aac"], "screen_w": 2400, "screen_h": 1080, "screen_fps": 120 }
```

### HANDSHAKE_ACK (JSON)
```json
{ "version": 1, "video_w": 1920, "video_h": 1080, "fps": 60, "bitrate_kbps": 8000, "audio_sample_rate": 48000 }
```

Resolution and FPS are negotiated from the Android device's physical display reported in `HANDSHAKE_REQ`. The host streams at values ≤ what the Android reported.

### HANDSHAKE_ERR (JSON)
```json
{ "code": 1, "message": "no displays available" }
```

### VIDEO_FRAME
```
[DISPLAY_ID: 1B][AVCC NAL data]
```
SPS/PPS are prepended (length-prefixed) before the IDR slice on every keyframe.

### AUDIO_FRAME
```
[CHANNEL_COUNT: 1B][SAMPLE_RATE_DIV100: 1B][AAC ADTS data]
```
e.g. for 48 kHz stereo: `02 1E [AAC...]` (480 = 1E0... we clamp to 255 by using divisor 100, so 480 ⇒ 4.80 ⇒ 4; receivers should treat this as a hint and trust HANDSHAKE_ACK).

### TOUCH_EVENT (14 bytes fixed)
```
[ACTION: 1B][POINTER_ID: 1B][X_NORM: f32 BE][Y_NORM: f32 BE][PRESSURE: f32 BE]
```
ACTION: 0x00 DOWN, 0x01 MOVE, 0x02 UP, 0x03 CANCEL. X/Y are 0.0..1.0 relative to the Android display.

### KEY_EVENT (8 bytes fixed)
```
[ACTION: 1B][MODIFIERS: 1B][ANDROID_KEYCODE: u16 BE][UNICODE_CHAR: u32 BE UTF-32]
```
ACTION: 0x00 DOWN, 0x01 UP. MODIFIERS bitmask: bit0 Shift, bit1 Ctrl, bit2 Alt/Option, bit3 Meta/Cmd. If UNICODE_CHAR != 0, the host injects via `CGEventKeyboardSetUnicodeString`; otherwise it looks up `ANDROID_KEYCODE` in the keycode map.

### DISPLAY_LIST (JSON array)
```json
[
  { "display_id": 1, "name": "Display 1 (3024x1964)", "width": 3024, "height": 1964, "is_primary": true }
]
```

### SELECT_DISPLAY (JSON)
```json
{ "display_id": 1 }
```

### PING / PONG
8-byte uint64 payload echoed back. Used as a heartbeat every 5 seconds; round-trip exceeding 20ms triggers adaptive bitrate reduction.

## Handshake Flow

```
Android: TCP connect
Android → Host: HANDSHAKE_REQ
Host → Android: HANDSHAKE_ACK
Host → Android: DISPLAY_LIST
Android → Host: SELECT_DISPLAY (optional, defaults to display 0)
Host → Android: VIDEO_FRAME stream (starts with IDR + SPS/PPS)
Host → Android: AUDIO_FRAME stream
Android → Host: TOUCH_EVENT / KEY_EVENT (as user interacts)
Either ↔: PING / PONG (every 5s)
```

## Versioning

If `version` in `HANDSHAKE_REQ` does not match `Protocol.VERSION`, the host replies with `HANDSHAKE_ERR` and closes the connection. Adding new packet TYPE values is backward compatible; existing TYPE values are permanent.
