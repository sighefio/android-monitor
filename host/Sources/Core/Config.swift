import Foundation

public enum ConnectionMode: String, Sendable {
    case wifi
    case usb
    case both
}

public struct ServerConfig: Sendable {
    public var port: UInt16
    public var bindHost: String
    public var defaultBitrateKbps: UInt32
    public var minBitrateKbps: UInt32
    public var maxBitrateKbps: UInt32
    public var keyframeIntervalSeconds: Int
    public var audioSampleRate: UInt32
    public var audioBitrateKbps: UInt32
    public var pingIntervalSeconds: Int
    public var connectionMode: ConnectionMode

    public static let defaultPort: UInt16 = 7878

    public static let `default` = ServerConfig(
        port: defaultPort,
        bindHost: "0.0.0.0",
        defaultBitrateKbps: 8000,
        minBitrateKbps: 2000,
        maxBitrateKbps: 20000,
        keyframeIntervalSeconds: 2,
        audioSampleRate: 48000,
        audioBitrateKbps: 128,
        pingIntervalSeconds: 5,
        connectionMode: .both
    )
}
