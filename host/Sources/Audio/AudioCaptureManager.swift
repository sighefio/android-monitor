import Foundation
import AVFoundation

public struct AudioFormatDescriptor: Sendable {
    public let sampleRate: UInt32
    public let channelCount: UInt8
}

public actor AudioCaptureManager {
    private let log = Log(category: "audio.capture")

    public init() {}

    public func preferredFormat() -> AudioFormatDescriptor {
        AudioFormatDescriptor(sampleRate: 48_000, channelCount: 2)
    }
}
