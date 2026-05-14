# Architecture

## Data flow

```
macOS (host)                                        Android (client)
─────────────                                       ────────────────
ScreenCaptureKit (NV12 IOSurface)
   ↓ (no CPU copy)
VideoToolbox H.264 encoder
   ↓ AVCC NAL units + SPS/PPS on IDR
NALPacketizer → ProtocolEncoder
   ↓
NWConnection.send (TCP, NODELAY, KEEPALIVE)
   ↓
   ════════════════ TCP 7878 ════════════════→ Socket reader (NIO)
                                                  ↓
                                                PacketReader (fragment reassembly)
                                                  ↓
                                                VideoDecoder (MediaCodec async, LOW_LATENCY=1)
                                                  ↓
                                                SurfaceView → display compositor

SCK system audio (PCM 48kHz stereo)
   ↓
AudioConverter → AAC-LC + ADTS
   ↓
AACPacketizer → ProtocolEncoder
   ↓
   ════════════════ TCP 7878 ════════════════→ AudioPlayer
                                                  ↓
                                                MediaCodec AAC decoder
                                                  ↓
                                                AudioTrack (PERFORMANCE_MODE_LOW_LATENCY)

CGEvent injection ← TouchEventInjector ← InputDecoder ← ProtocolDecoder
                                                          ↑
                                                       TCP 7878
                                                          ↑
                                                        TouchHandler (View.OnTouchListener)
                                                          ↑
                                                        MotionEvent on SurfaceView
```

## Threading

### Host

- **SCStream** delivers samples on `videoQueue` (userInteractive) and `audioQueue` (userInteractive).
- **VideoToolbox encode** is synchronous on the calling queue (videoQueue); the output callback fires on VT's internal dispatch.
- **NWConnection.send** is non-blocking; serialization happens on `session.<uuid>` queue.
- **NWListener** accept fires on `global(qos: .userInteractive)`.
- **Frame dispatch** uses TaskGroup-based fanout to all sessions in parallel.

### Android

- **TcpClient** runs read and write loops on `Dispatchers.IO`.
- **VideoDecoder** has a dedicated HandlerThread at `Thread.MAX_PRIORITY` for MediaCodec async callbacks.
- **AudioPlayer** has a separate HandlerThread for the AAC decoder.
- **UI** runs on the main thread; touch events post directly to the writer (no main-thread blocking).

## Backpressure

The Android side never queues video frames beyond MediaCodec's input buffer. If MediaCodec is slow, frames pile up briefly in `ConcurrentLinkedQueue`; the host's TCP send blocks once the OS send buffer fills, naturally throttling capture.

The host can reduce bitrate live via `VTSessionSetProperty(kVTCompressionPropertyKey_AverageBitRate)` if PING/PONG RTT exceeds 20ms.

## Failure modes

- **Capture permission denied**: `SCShareableContent` throws; daemon emits `HANDSHAKE_ERR`, code 1.
- **Hardware encoder unavailable**: VT falls back to software (allowed; not preferred).
- **MediaCodec error**: `onError` logs; UI returns to ConnectScreen.
- **TCP disconnect**: both sides emit `Disconnected`; Android UI returns to ConnectScreen.
