import Foundation

public struct VideoEncoderConfig: Sendable {
    public var width: Int32
    public var height: Int32
    public var fps: Int32
    public var bitrateKbps: UInt32
    public var keyframeIntervalSeconds: Int32

    public init(width: Int32, height: Int32, fps: Int32, bitrateKbps: UInt32, keyframeIntervalSeconds: Int32) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateKbps = bitrateKbps
        self.keyframeIntervalSeconds = keyframeIntervalSeconds
    }

    public static func negotiate(
        clientWidth: UInt32,
        clientHeight: UInt32,
        clientFps: UInt32,
        displayWidth: UInt32,
        displayHeight: UInt32,
        userScalePercent: UInt32,
        userMaxFps: UInt32,
        bitrateKbps: UInt32,
        keyframeIntervalSeconds: Int32
    ) -> VideoEncoderConfig {
        let scale = max(50, min(100, userScalePercent))
        let targetW = min(clientWidth, displayWidth) * scale / 100
        let targetH = min(clientHeight, displayHeight) * scale / 100
        let evenW = Int32(targetW & ~1)
        let evenH = Int32(targetH & ~1)
        let targetFps = max(30, min(clientFps, userMaxFps))
        return VideoEncoderConfig(
            width: evenW,
            height: evenH,
            fps: Int32(targetFps),
            bitrateKbps: bitrateKbps,
            keyframeIntervalSeconds: keyframeIntervalSeconds
        )
    }
}
