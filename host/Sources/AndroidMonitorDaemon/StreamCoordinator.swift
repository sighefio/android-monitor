import Foundation
@preconcurrency import ScreenCaptureKit
import CoreGraphics

@available(macOS 13.0, *)
public final class StreamCoordinator: ClientSessionDelegate, ConnectionServerDelegate, CaptureSink, @unchecked Sendable {
    private let log = Log(category: "daemon.coordinator")
    private let config: ServerConfig
    private let captureManager = ScreenCaptureManager()
    private let picker = DisplayPicker()
    private let dispatcher = FrameDispatcher()
    private let touchInjector = TouchEventInjector()
    private let keyboardInjector = KeyboardInjector()
    private let adb: ADBForwardManager

    private var server: ConnectionServer?
    private var videoEncoder: VideoEncoder?
    private var audioEncoder: AudioEncoder?
    private var captureSession: CaptureSession?
    private var currentDisplayId: UInt32?

    public init(config: ServerConfig = .default) {
        self.config = config
        self.adb = ADBForwardManager(port: config.port)
    }

    public func start() async throws {
        server = try ConnectionServer(port: config.port, delegate: self)
        try await server?.start()
        if config.connectionMode == .usb || config.connectionMode == .both {
            _ = await adb.enableForward()
        }
    }

    public func stop() async {
        await captureSession?.stop()
        videoEncoder?.invalidate()
        await server?.stop()
        await adb.disableForward()
    }

    // MARK: ConnectionServerDelegate

    public func server(_ server: ConnectionServer, didAcceptSession session: ClientSession) async {
        await dispatcher.register(session)
    }

    // MARK: ClientSessionDelegate

    public func session(_ session: ClientSession, didReceiveHandshake request: HandshakeRequest) async {
        do {
            let displays = try await picker.refresh(using: captureManager)
            guard let firstDisplay = await picker.currentDisplays().first else {
                try await session.sendHandshakeError(HandshakeError(code: 1, message: "No displays available"))
                return
            }
            let displayWidth = UInt32(firstDisplay.width)
            let displayHeight = UInt32(firstDisplay.height)
            let encoderConfig = VideoEncoderConfig.negotiate(
                clientWidth: request.screenW,
                clientHeight: request.screenH,
                clientFps: request.screenFps,
                displayWidth: displayWidth,
                displayHeight: displayHeight,
                userScalePercent: 100,
                userMaxFps: request.screenFps,
                bitrateKbps: config.defaultBitrateKbps,
                keyframeIntervalSeconds: Int32(config.keyframeIntervalSeconds)
            )
            let ack = HandshakeAck(
                version: Protocol.version,
                videoW: UInt32(encoderConfig.width),
                videoH: UInt32(encoderConfig.height),
                fps: UInt32(encoderConfig.fps),
                bitrateKbps: encoderConfig.bitrateKbps,
                audioSampleRate: config.audioSampleRate
            )
            try await session.sendHandshakeAck(ack)
            try await session.sendDisplayList(displays)
            try await beginStreaming(displayId: UInt32(firstDisplay.displayID), encoderConfig: encoderConfig)
        } catch {
            log.error("handshake handling failed: \(error.localizedDescription)")
            try? await session.sendHandshakeError(HandshakeError(code: 2, message: error.localizedDescription))
        }
    }

    public func session(_ session: ClientSession, didSelectDisplay id: UInt32) async {
        guard let display = await picker.select(displayId: id) else { return }
        currentDisplayId = id
        let bounds = display.frame
        touchInjector.updateDisplayBounds(bounds)
        let encoderConfig = VideoEncoderConfig(
            width: Int32(display.width),
            height: Int32(display.height),
            fps: Int32(60),
            bitrateKbps: config.defaultBitrateKbps,
            keyframeIntervalSeconds: Int32(config.keyframeIntervalSeconds)
        )
        try? await beginStreaming(displayId: id, encoderConfig: encoderConfig)
    }

    public func session(_ session: ClientSession, didReceiveTouch packet: TouchPacket) async {
        touchInjector.inject(packet)
    }

    public func session(_ session: ClientSession, didReceiveKey packet: KeyPacket) async {
        keyboardInjector.inject(packet)
    }

    public func session(_ session: ClientSession, didClose error: Error?) async {
        await dispatcher.unregister(session)
        if let error { log.warn("session closed: \(error.localizedDescription)") }
    }

    // MARK: CaptureSink

    public func onVideoFrame(_ frame: CaptureFrame) {
        do {
            try videoEncoder?.encode(sampleBuffer: frame.sampleBuffer)
        } catch {
            log.warn("encode failed: \(error)")
        }
    }

    public func onAudioFrame(_ audio: CaptureAudio) {
        audioEncoder?.encode(sampleBuffer: audio.sampleBuffer)
    }

    public func onCaptureError(_ error: Error) {
        log.error("capture error: \(error.localizedDescription)")
    }

    // MARK: Private

    private func beginStreaming(displayId: UInt32, encoderConfig: VideoEncoderConfig) async throws {
        await captureSession?.stop()
        videoEncoder?.invalidate()

        guard let display = await picker.select(displayId: displayId) else {
            throw NSError(domain: "StreamCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "display not found"])
        }
        touchInjector.updateDisplayBounds(display.frame)
        currentDisplayId = displayId

        let dispatcher = self.dispatcher
        let videoEncoder = try VideoEncoder(config: encoderConfig) { [weak dispatcher] sample in
            Task { await dispatcher?.broadcastVideo(displayId: displayId, sample: sample) }
        }
        self.videoEncoder = videoEncoder

        let audioEncoder = AudioEncoder(
            sampleRate: config.audioSampleRate,
            channels: 2,
            bitrateKbps: config.audioBitrateKbps
        ) { [weak dispatcher] sample in
            Task { await dispatcher?.broadcastAudio(sample) }
        }
        self.audioEncoder = audioEncoder

        let session = CaptureSession(displayId: displayId, sink: self)
        try await session.start(display: display, settings: CaptureSettings(
            width: Int(encoderConfig.width),
            height: Int(encoderConfig.height),
            fps: Int(encoderConfig.fps),
            captureAudio: true
        ))
        captureSession = session
    }
}
