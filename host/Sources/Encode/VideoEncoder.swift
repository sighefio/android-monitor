import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

public struct EncodedVideoSample: Sendable {
    public let data: Data
    public let isKeyframe: Bool
    public let presentationTimeUs: UInt64
    public let parameterSets: Data?
}

public enum VideoEncoderError: Error, Sendable {
    case sessionCreationFailed(OSStatus)
    case propertySetFailed(String, OSStatus)
    case encodeFailed(OSStatus)
    case noPixelBuffer
    case parameterSetExtractionFailed(OSStatus)
}

public final class VideoEncoder: @unchecked Sendable {
    public typealias SampleHandler = @Sendable (EncodedVideoSample) -> Void

    private let log = Log(category: "encode.video")
    private var session: VTCompressionSession?
    private var config: VideoEncoderConfig
    private let handler: SampleHandler
    private var cachedParameterSets: Data?
    private let sessionLock = NSLock()

    public init(config: VideoEncoderConfig, handler: @escaping SampleHandler) throws {
        self.config = config
        self.handler = handler
        try createSession()
    }

    deinit {
        invalidate()
    }

    public func encode(sampleBuffer: CMSampleBuffer) throws {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw VideoEncoderError.noPixelBuffer
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        sessionLock.lock()
        let session = self.session
        sessionLock.unlock()
        guard let session else { return }

        var flags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        if status != noErr {
            throw VideoEncoderError.encodeFailed(status)
        }
    }

    public func requestKeyframe() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        guard let session else { return }
        _ = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        cachedParameterSets = nil
    }

    public func updateBitrate(_ kbps: UInt32) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        guard let session else { return }
        let bps = NSNumber(value: kbps * 1000)
        _ = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bps)
        let dataLimit = NSNumber(value: kbps * 1000 / 8 * 2)
        let limits: [NSNumber] = [dataLimit, NSNumber(value: 1)]
        _ = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits as CFArray)
    }

    public func invalidate() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }

    private func createSession() throws {
        var newSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: config.width,
            height: config.height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpecification(),
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encoderOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &newSession
        )
        guard status == noErr, let session = newSession else {
            throw VideoEncoderError.sessionCreationFailed(status)
        }

        try setProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        try setProperty(session, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        try setProperty(session, kVTCompressionPropertyKey_MaxFrameDelayCount, NSNumber(value: 0))
        try setProperty(session, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        try setProperty(session, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC)
        try setProperty(session, kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: config.bitrateKbps * 1000))
        try setProperty(session, kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: config.fps))
        try setProperty(session, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: config.keyframeIntervalSeconds))
        try setProperty(session, kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: config.fps * config.keyframeIntervalSeconds))

        VTCompressionSessionPrepareToEncodeFrames(session)
        self.session = session
        log.info("encoder ready: \(config.width)x\(config.height)@\(config.fps) bitrate=\(config.bitrateKbps)kbps")
    }

    private func encoderSpecification() -> CFDictionary {
        let spec: [String: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: kCFBooleanTrue!,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: kCFBooleanFalse!
        ]
        return spec as CFDictionary
    }

    private func setProperty(_ session: VTCompressionSession, _ key: CFString, _ value: CFTypeRef) throws {
        let status = VTSessionSetProperty(session, key: key, value: value)
        if status != noErr {
            throw VideoEncoderError.propertySetFailed(key as String, status)
        }
    }

    fileprivate func handleEncoded(status: OSStatus, sampleBuffer: CMSampleBuffer?) {
        guard status == noErr, let buffer = sampleBuffer, CMSampleBufferDataIsReady(buffer) else {
            if status != noErr { log.error("encoder output status \(status)") }
            return
        }
        let isKeyframe = isKeyframeSample(buffer)
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        let presentationTimeUs = UInt64(max(0, CMTimeGetSeconds(pts) * 1_000_000))

        var paramSets: Data?
        if isKeyframe {
            do {
                paramSets = try extractParameterSets(buffer)
                cachedParameterSets = paramSets
            } catch {
                log.warn("parameter set extraction failed: \(error)")
            }
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(buffer) else { return }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let ptr = dataPointer else { return }
        let payload = Data(bytes: ptr, count: totalLength)

        let sample = EncodedVideoSample(
            data: payload,
            isKeyframe: isKeyframe,
            presentationTimeUs: presentationTimeUs,
            parameterSets: paramSets
        )
        handler(sample)
    }

    private func isKeyframeSample(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[CFString: Any]],
              let attach = attachments.first else {
            return true
        }
        if let notSync = attach[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync
        }
        return true
    }

    private func extractParameterSets(_ buffer: CMSampleBuffer) throws -> Data {
        guard let formatDescription = CMSampleBufferGetFormatDescription(buffer) else {
            throw VideoEncoderError.parameterSetExtractionFailed(-1)
        }
        var paramCount = 0
        var nalUnitHeaderLength: Int32 = 0
        let countStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription, parameterSetIndex: 0,
            parameterSetPointerOut: nil, parameterSetSizeOut: nil,
            parameterSetCountOut: &paramCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength
        )
        if countStatus != noErr {
            throw VideoEncoderError.parameterSetExtractionFailed(countStatus)
        }
        var out = Data()
        for i in 0..<paramCount {
            var psPointer: UnsafePointer<UInt8>?
            var psSize = 0
            let s = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription, parameterSetIndex: i,
                parameterSetPointerOut: &psPointer, parameterSetSizeOut: &psSize,
                parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
            )
            if s != noErr {
                throw VideoEncoderError.parameterSetExtractionFailed(s)
            }
            if let psPointer {
                let lengthBytes = withUnsafeBytes(of: UInt32(psSize).bigEndian) { Array($0) }
                out.append(contentsOf: lengthBytes)
                out.append(psPointer, count: psSize)
            }
        }
        return out
    }
}

private func encoderOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard let outputCallbackRefCon else { return }
    let encoder = Unmanaged<VideoEncoder>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
    encoder.handleEncoded(status: status, sampleBuffer: sampleBuffer)
}
