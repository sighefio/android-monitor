import Foundation
import CoreMedia
import CoreVideo
@preconcurrency import ScreenCaptureKit
import Core

public struct CaptureFrame: Sendable {
    public let sampleBuffer: CMSampleBuffer
    public let displayId: UInt32
    public let captureTimeUs: UInt64

    public init(sampleBuffer: CMSampleBuffer, displayId: UInt32, captureTimeUs: UInt64) {
        self.sampleBuffer = sampleBuffer
        self.displayId = displayId
        self.captureTimeUs = captureTimeUs
    }
}

public struct CaptureAudio: Sendable {
    public let sampleBuffer: CMSampleBuffer
    public let captureTimeUs: UInt64
}

public struct CaptureSettings: Sendable {
    public var width: Int
    public var height: Int
    public var fps: Int
    public var captureAudio: Bool

    public init(width: Int, height: Int, fps: Int, captureAudio: Bool) {
        self.width = width
        self.height = height
        self.fps = fps
        self.captureAudio = captureAudio
    }
}

public protocol CaptureSink: AnyObject, Sendable {
    func onVideoFrame(_ frame: CaptureFrame)
    func onAudioFrame(_ audio: CaptureAudio)
    func onCaptureError(_ error: Error)
}

@available(macOS 13.0, *)
public final class CaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let log = Log(category: "capture.session")
    private let displayId: UInt32
    private weak var sink: CaptureSink?
    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "com.androidmonitor.capture.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.androidmonitor.capture.audio", qos: .userInteractive)

    public init(displayId: UInt32, sink: CaptureSink) {
        self.displayId = displayId
        self.sink = sink
        super.init()
    }

    public func start(display: SCDisplay, settings: CaptureSettings) async throws {
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = settings.width
        config.height = settings.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
        config.queueDepth = 5
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.showsCursor = true
        config.capturesAudio = settings.captureAudio
        if settings.captureAudio {
            config.sampleRate = 48_000
            config.channelCount = 2
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        if settings.captureAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        try await stream.startCapture()
        self.stream = stream
        log.info("capture started: \(settings.width)x\(settings.height)@\(settings.fps) audio=\(settings.captureAudio)")
    }

    public func stop() async {
        guard let stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            log.warn("stopCapture error: \(error.localizedDescription)")
        }
        self.stream = nil
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let ts = Timestamp.monotonicMicroseconds()
        switch type {
        case .screen:
            sink?.onVideoFrame(CaptureFrame(sampleBuffer: sampleBuffer, displayId: displayId, captureTimeUs: ts))
        case .audio:
            sink?.onAudioFrame(CaptureAudio(sampleBuffer: sampleBuffer, captureTimeUs: ts))
        @unknown default:
            break
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("stream stopped with error: \(error.localizedDescription)")
        sink?.onCaptureError(error)
    }
}
