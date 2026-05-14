import Foundation

public enum Protocol {
    public static let magic0: UInt8 = 0xAD
    public static let magic1: UInt8 = 0x01
    public static let headerSize: Int = 22
    public static let maxPayloadSize: Int = 4 * 1024 * 1024
    public static let version: UInt32 = 1
}

public enum PacketType: UInt8, Sendable {
    case handshakeReq    = 0x01
    case handshakeAck    = 0x02
    case handshakeErr    = 0x03
    case videoFrame      = 0x10
    case audioFrame      = 0x11
    case touchEvent      = 0x20
    case keyEvent        = 0x21
    case displayList     = 0x30
    case selectDisplay   = 0x31
    case ping            = 0x40
    case pong            = 0x41
    case streamPause     = 0x50
    case streamResume    = 0x51
}

public struct PacketFlags: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let keyFrame    = PacketFlags(rawValue: 1 << 0)
    public static let frameStart  = PacketFlags(rawValue: 1 << 1)
    public static let frameEnd    = PacketFlags(rawValue: 1 << 2)
    public static let compressed  = PacketFlags(rawValue: 1 << 3)
}

public struct PacketHeader: Sendable {
    public let type: PacketType
    public let flags: PacketFlags
    public let length: UInt32
    public let sequence: UInt64
    public let timestampUs: UInt64

    public init(type: PacketType, flags: PacketFlags, length: UInt32, sequence: UInt64, timestampUs: UInt64) {
        self.type = type
        self.flags = flags
        self.length = length
        self.sequence = sequence
        self.timestampUs = timestampUs
    }
}

public enum TouchAction: UInt8, Sendable {
    case down   = 0x00
    case move   = 0x01
    case up     = 0x02
    case cancel = 0x03
}

public enum KeyAction: UInt8, Sendable {
    case down = 0x00
    case up   = 0x01
}

public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let ctrl  = KeyModifiers(rawValue: 1 << 1)
    public static let alt   = KeyModifiers(rawValue: 1 << 2)
    public static let meta  = KeyModifiers(rawValue: 1 << 3)
}

public struct TouchPacket: Sendable {
    public let action: TouchAction
    public let pointerId: UInt8
    public let xNorm: Float
    public let yNorm: Float
    public let pressure: Float
}

public struct KeyPacket: Sendable {
    public let action: KeyAction
    public let modifiers: KeyModifiers
    public let androidKeycode: UInt16
    public let unicodeChar: UInt32
}

public struct HandshakeRequest: Codable, Sendable {
    public let version: UInt32
    public let capabilities: [String]
    public let screenW: UInt32
    public let screenH: UInt32
    public let screenFps: UInt32

    enum CodingKeys: String, CodingKey {
        case version
        case capabilities
        case screenW = "screen_w"
        case screenH = "screen_h"
        case screenFps = "screen_fps"
    }
}

public struct HandshakeAck: Codable, Sendable {
    public let version: UInt32
    public let videoW: UInt32
    public let videoH: UInt32
    public let fps: UInt32
    public let bitrateKbps: UInt32
    public let audioSampleRate: UInt32

    enum CodingKeys: String, CodingKey {
        case version
        case videoW = "video_w"
        case videoH = "video_h"
        case fps
        case bitrateKbps = "bitrate_kbps"
        case audioSampleRate = "audio_sample_rate"
    }

    public init(version: UInt32, videoW: UInt32, videoH: UInt32, fps: UInt32, bitrateKbps: UInt32, audioSampleRate: UInt32) {
        self.version = version
        self.videoW = videoW
        self.videoH = videoH
        self.fps = fps
        self.bitrateKbps = bitrateKbps
        self.audioSampleRate = audioSampleRate
    }
}

public struct HandshakeError: Codable, Sendable {
    public let code: Int
    public let message: String
}

public struct DisplayDescriptor: Codable, Sendable {
    public let displayId: UInt32
    public let name: String
    public let width: UInt32
    public let height: UInt32
    public let isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case displayId = "display_id"
        case name
        case width
        case height
        case isPrimary = "is_primary"
    }
}

public struct SelectDisplayMessage: Codable, Sendable {
    public let displayId: UInt32
    enum CodingKeys: String, CodingKey { case displayId = "display_id" }
}

public enum ProtocolError: Error, Sendable {
    case shortRead
    case invalidMagic
    case unknownPacketType(UInt8)
    case payloadTooLarge(UInt32)
    case payloadSizeMismatch(expected: Int, actual: Int)
    case decodeFailed(String)
}

public enum PacketCodec {
    public static func encodeHeader(_ header: PacketHeader, into buffer: inout [UInt8]) {
        buffer.append(Protocol.magic0)
        buffer.append(Protocol.magic1)
        buffer.append(header.type.rawValue)
        buffer.append(header.flags.rawValue)
        appendBigEndian(header.length, into: &buffer)
        appendBigEndian(header.sequence, into: &buffer)
        appendBigEndian(header.timestampUs, into: &buffer)
    }

    public static func decodeHeader(_ bytes: ArraySlice<UInt8>) throws -> PacketHeader {
        guard bytes.count >= Protocol.headerSize else { throw ProtocolError.shortRead }
        let base = bytes.startIndex
        guard bytes[base] == Protocol.magic0, bytes[base + 1] == Protocol.magic1 else {
            throw ProtocolError.invalidMagic
        }
        let typeByte = bytes[base + 2]
        guard let type = PacketType(rawValue: typeByte) else {
            throw ProtocolError.unknownPacketType(typeByte)
        }
        let flags = PacketFlags(rawValue: bytes[base + 3])
        let length: UInt32 = readBigEndian(bytes, offset: base + 4)
        let sequence: UInt64 = readBigEndian(bytes, offset: base + 8)
        let timestampUs: UInt64 = readBigEndian(bytes, offset: base + 16)
        guard length <= Protocol.maxPayloadSize else {
            throw ProtocolError.payloadTooLarge(length)
        }
        return PacketHeader(type: type, flags: flags, length: length, sequence: sequence, timestampUs: timestampUs)
    }

    public static func encodeTouchPayload(_ packet: TouchPacket) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(14)
        bytes.append(packet.action.rawValue)
        bytes.append(packet.pointerId)
        appendBigEndian(packet.xNorm.bitPattern, into: &bytes)
        appendBigEndian(packet.yNorm.bitPattern, into: &bytes)
        appendBigEndian(packet.pressure.bitPattern, into: &bytes)
        return bytes
    }

    public static func decodeTouchPayload(_ bytes: ArraySlice<UInt8>) throws -> TouchPacket {
        guard bytes.count == 14 else {
            throw ProtocolError.payloadSizeMismatch(expected: 14, actual: bytes.count)
        }
        let base = bytes.startIndex
        guard let action = TouchAction(rawValue: bytes[base]) else {
            throw ProtocolError.decodeFailed("touch action \(bytes[base])")
        }
        let pointerId = bytes[base + 1]
        let xBits: UInt32 = readBigEndian(bytes, offset: base + 2)
        let yBits: UInt32 = readBigEndian(bytes, offset: base + 6)
        let pBits: UInt32 = readBigEndian(bytes, offset: base + 10)
        return TouchPacket(
            action: action,
            pointerId: pointerId,
            xNorm: Float(bitPattern: xBits),
            yNorm: Float(bitPattern: yBits),
            pressure: Float(bitPattern: pBits)
        )
    }

    public static func encodeKeyPayload(_ packet: KeyPacket) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(8)
        bytes.append(packet.action.rawValue)
        bytes.append(packet.modifiers.rawValue)
        appendBigEndian(packet.androidKeycode, into: &bytes)
        appendBigEndian(packet.unicodeChar, into: &bytes)
        return bytes
    }

    public static func decodeKeyPayload(_ bytes: ArraySlice<UInt8>) throws -> KeyPacket {
        guard bytes.count == 8 else {
            throw ProtocolError.payloadSizeMismatch(expected: 8, actual: bytes.count)
        }
        let base = bytes.startIndex
        guard let action = KeyAction(rawValue: bytes[base]) else {
            throw ProtocolError.decodeFailed("key action \(bytes[base])")
        }
        let modifiers = KeyModifiers(rawValue: bytes[base + 1])
        let keycode: UInt16 = readBigEndian(bytes, offset: base + 2)
        let unicode: UInt32 = readBigEndian(bytes, offset: base + 4)
        return KeyPacket(action: action, modifiers: modifiers, androidKeycode: keycode, unicodeChar: unicode)
    }
}

@inline(__always)
private func appendBigEndian(_ value: UInt32, into buffer: inout [UInt8]) {
    buffer.append(UInt8((value >> 24) & 0xFF))
    buffer.append(UInt8((value >> 16) & 0xFF))
    buffer.append(UInt8((value >> 8) & 0xFF))
    buffer.append(UInt8(value & 0xFF))
}

@inline(__always)
private func appendBigEndian(_ value: UInt64, into buffer: inout [UInt8]) {
    for shift in stride(from: 56, through: 0, by: -8) {
        buffer.append(UInt8((value >> shift) & 0xFF))
    }
}

@inline(__always)
private func appendBigEndian(_ value: UInt16, into buffer: inout [UInt8]) {
    buffer.append(UInt8((value >> 8) & 0xFF))
    buffer.append(UInt8(value & 0xFF))
}

@inline(__always)
private func readBigEndian(_ bytes: ArraySlice<UInt8>, offset: Int) -> UInt32 {
    return (UInt32(bytes[offset]) << 24)
         | (UInt32(bytes[offset + 1]) << 16)
         | (UInt32(bytes[offset + 2]) << 8)
         |  UInt32(bytes[offset + 3])
}

@inline(__always)
private func readBigEndian(_ bytes: ArraySlice<UInt8>, offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for i in 0..<8 {
        value = (value << 8) | UInt64(bytes[offset + i])
    }
    return value
}

@inline(__always)
private func readBigEndian(_ bytes: ArraySlice<UInt8>, offset: Int) -> UInt16 {
    return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
}
