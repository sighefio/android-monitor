import XCTest
@testable import Core

final class PacketSerializationTests: XCTestCase {
    func testHeaderRoundTrip() throws {
        let original = PacketHeader(
            type: .videoFrame,
            flags: [.keyFrame, .frameStart, .frameEnd],
            length: 1234,
            sequence: 99,
            timestampUs: 1_700_000_000_000_000
        )
        var bytes: [UInt8] = []
        PacketCodec.encodeHeader(original, into: &bytes)
        XCTAssertEqual(bytes.count, Protocol.headerSize)
        let decoded = try PacketCodec.decodeHeader(bytes[...])
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.flags.rawValue, original.flags.rawValue)
        XCTAssertEqual(decoded.length, original.length)
        XCTAssertEqual(decoded.sequence, original.sequence)
        XCTAssertEqual(decoded.timestampUs, original.timestampUs)
    }

    func testTouchPayloadRoundTrip() throws {
        let original = TouchPacket(action: .move, pointerId: 1, xNorm: 0.25, yNorm: 0.75, pressure: 0.5)
        let bytes = PacketCodec.encodeTouchPayload(original)
        XCTAssertEqual(bytes.count, 14)
        let decoded = try PacketCodec.decodeTouchPayload(bytes[...])
        XCTAssertEqual(decoded.action, original.action)
        XCTAssertEqual(decoded.pointerId, original.pointerId)
        XCTAssertEqual(decoded.xNorm, original.xNorm)
        XCTAssertEqual(decoded.yNorm, original.yNorm)
        XCTAssertEqual(decoded.pressure, original.pressure)
    }

    func testKeyPayloadRoundTrip() throws {
        let original = KeyPacket(action: .down, modifiers: [.shift, .meta], androidKeycode: 66, unicodeChar: 0x1F600)
        let bytes = PacketCodec.encodeKeyPayload(original)
        XCTAssertEqual(bytes.count, 8)
        let decoded = try PacketCodec.decodeKeyPayload(bytes[...])
        XCTAssertEqual(decoded.action, original.action)
        XCTAssertEqual(decoded.modifiers.rawValue, original.modifiers.rawValue)
        XCTAssertEqual(decoded.androidKeycode, original.androidKeycode)
        XCTAssertEqual(decoded.unicodeChar, original.unicodeChar)
    }

    func testInvalidMagicIsRejected() {
        var bytes = [UInt8](repeating: 0, count: Protocol.headerSize)
        bytes[0] = 0xFF
        bytes[1] = 0xFF
        XCTAssertThrowsError(try PacketCodec.decodeHeader(bytes[...]))
    }

    func testOversizedPayloadIsRejected() {
        let header = PacketHeader(
            type: .videoFrame,
            flags: [],
            length: UInt32(Protocol.maxPayloadSize + 1),
            sequence: 1,
            timestampUs: 0
        )
        var bytes: [UInt8] = []
        PacketCodec.encodeHeader(header, into: &bytes)
        XCTAssertThrowsError(try PacketCodec.decodeHeader(bytes[...]))
    }
}
