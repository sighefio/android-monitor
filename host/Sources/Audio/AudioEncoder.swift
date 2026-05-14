import Foundation
import AudioToolbox
import CoreMedia

public struct EncodedAudioSample: Sendable {
    public let data: Data
    public let presentationTimeUs: UInt64
    public let channels: UInt8
    public let sampleRate: UInt32
}

public enum AudioEncoderError: Error, Sendable {
    case converterCreationFailed(OSStatus)
    case conversionFailed(OSStatus)
    case unsupportedFormat
}

public final class AudioEncoder: @unchecked Sendable {
    public typealias SampleHandler = @Sendable (EncodedAudioSample) -> Void

    private let log = Log(category: "audio.encoder")
    private let outputSampleRate: UInt32
    private let outputChannels: UInt8
    private let outputBitrate: UInt32
    private var converter: AudioConverterRef?
    private let handler: SampleHandler
    private let queue = DispatchQueue(label: "com.androidmonitor.audio.encoder", qos: .userInteractive)
    private var inputBuffer = Data()
    private var sourceFormat = AudioStreamBasicDescription()

    public init(sampleRate: UInt32 = 48_000, channels: UInt8 = 2, bitrateKbps: UInt32 = 128, handler: @escaping SampleHandler) {
        self.outputSampleRate = sampleRate
        self.outputChannels = channels
        self.outputBitrate = bitrateKbps
        self.handler = handler
    }

    deinit {
        if let converter {
            AudioConverterDispose(converter)
        }
    }

    public func encode(sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            self?.encodeSync(sampleBuffer: sampleBuffer)
        }
    }

    private func encodeSync(sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }
        if converter == nil {
            sourceFormat = asbdPtr.pointee
            do {
                try createConverter()
            } catch {
                log.error("converter create failed: \(error)")
                return
            }
        }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        if status != noErr { return }

        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        for buffer in buffers {
            if let data = buffer.mData {
                inputBuffer.append(Data(bytes: data, count: Int(buffer.mDataByteSize)))
            }
        }
        drainConverter(presentationTimeUs: Timestamp.monotonicMicroseconds())
    }

    private func createConverter() throws {
        var dst = AudioStreamBasicDescription(
            mSampleRate: Float64(outputSampleRate),
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(outputChannels),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        var convOpt: AudioConverterRef?
        let status = AudioConverterNew(&sourceFormat, &dst, &convOpt)
        guard status == noErr, let conv = convOpt else {
            throw AudioEncoderError.converterCreationFailed(status)
        }
        var bitrate = UInt32(outputBitrate * 1000)
        AudioConverterSetProperty(conv, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &bitrate)
        self.converter = conv
    }

    private func drainConverter(presentationTimeUs: UInt64) {
        guard let converter else { return }
        let framesPerPacket: UInt32 = 1024
        let bytesPerFrame = sourceFormat.mBytesPerFrame == 0
            ? UInt32(MemoryLayout<Float32>.size) * UInt32(outputChannels)
            : sourceFormat.mBytesPerFrame
        let requiredInputBytes = Int(framesPerPacket * bytesPerFrame)

        while inputBuffer.count >= requiredInputBytes {
            var outBytes = [UInt8](repeating: 0, count: 4096)
            var packetCount: UInt32 = 1
            var outBufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: UInt32(outputChannels),
                    mDataByteSize: UInt32(outBytes.count),
                    mData: UnsafeMutableRawPointer(mutating: outBytes)
                )
            )
            let chunk = inputBuffer.prefix(requiredInputBytes)
            let context = ConverterContext(source: Data(chunk), bytesPerFrame: bytesPerFrame, framesPerPacket: framesPerPacket)
            let contextPtr = Unmanaged.passUnretained(context).toOpaque()

            let status = withUnsafeMutablePointer(to: &outBufferList) { bufferListPtr in
                AudioConverterFillComplexBuffer(
                    converter,
                    converterInputCallback,
                    contextPtr,
                    &packetCount,
                    bufferListPtr,
                    nil
                )
            }
            if status != noErr {
                log.warn("audio convert status \(status)")
                inputBuffer.removeFirst(requiredInputBytes)
                continue
            }
            let outSize = Int(outBufferList.mBuffers.mDataByteSize)
            if outSize > 0 {
                let aacData = Data(bytes: outBytes, count: outSize)
                let adts = AudioEncoder.buildADTSHeader(payloadSize: outSize, sampleRate: outputSampleRate, channels: outputChannels)
                var combined = Data()
                combined.append(adts)
                combined.append(aacData)
                handler(EncodedAudioSample(
                    data: combined,
                    presentationTimeUs: presentationTimeUs,
                    channels: outputChannels,
                    sampleRate: outputSampleRate
                ))
            }
            inputBuffer.removeFirst(requiredInputBytes)
        }
    }

    private static func buildADTSHeader(payloadSize: Int, sampleRate: UInt32, channels: UInt8) -> Data {
        let profile: UInt8 = 1
        let freqIndex: UInt8 = sampleRateIndex(sampleRate)
        let frameLength = UInt16(payloadSize + 7)
        var header = [UInt8](repeating: 0, count: 7)
        header[0] = 0xFF
        header[1] = 0xF1
        header[2] = ((profile) << 6) | ((freqIndex & 0x0F) << 2) | ((channels >> 2) & 0x01)
        header[3] = ((channels & 0x03) << 6) | UInt8((frameLength >> 11) & 0x03)
        header[4] = UInt8((frameLength >> 3) & 0xFF)
        header[5] = UInt8((frameLength & 0x07) << 5) | 0x1F
        header[6] = 0xFC
        return Data(header)
    }

    private static func sampleRateIndex(_ rate: UInt32) -> UInt8 {
        switch rate {
        case 96_000: return 0
        case 88_200: return 1
        case 64_000: return 2
        case 48_000: return 3
        case 44_100: return 4
        case 32_000: return 5
        case 24_000: return 6
        case 22_050: return 7
        case 16_000: return 8
        case 12_000: return 9
        case 11_025: return 10
        case 8_000:  return 11
        default:     return 3
        }
    }
}

private final class ConverterContext {
    let pointer: UnsafeMutableRawPointer
    let byteCount: Int
    let bytesPerFrame: UInt32
    let framesPerPacket: UInt32
    var consumed = false

    init(source: Data, bytesPerFrame: UInt32, framesPerPacket: UInt32) {
        let count = source.count
        let raw = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        source.withUnsafeBytes { src in
            if let base = src.baseAddress { raw.copyMemory(from: base, byteCount: count) }
        }
        self.pointer = raw
        self.byteCount = count
        self.bytesPerFrame = bytesPerFrame
        self.framesPerPacket = framesPerPacket
    }

    deinit {
        pointer.deallocate()
    }
}

private func converterInputCallback(
    _ converter: AudioConverterRef,
    _ ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
    _ ioData: UnsafeMutablePointer<AudioBufferList>,
    _ outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    _ inUserData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inUserData else {
        ioNumberDataPackets.pointee = 0
        return noErr
    }
    let context = Unmanaged<ConverterContext>.fromOpaque(inUserData).takeUnretainedValue()
    if context.consumed {
        ioNumberDataPackets.pointee = 0
        return noErr
    }
    ioData.pointee.mBuffers.mDataByteSize = UInt32(context.byteCount)
    ioData.pointee.mBuffers.mData = context.pointer
    ioNumberDataPackets.pointee = context.framesPerPacket
    context.consumed = true
    return noErr
}
