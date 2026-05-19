import Foundation
import Core

public enum InputDecoder {
    public static func decodeTouch(_ payload: Data) throws -> TouchPacket {
        try PacketCodec.decodeTouchPayload(Array(payload)[...])
    }

    public static func decodeKey(_ payload: Data) throws -> KeyPacket {
        try PacketCodec.decodeKeyPayload(Array(payload)[...])
    }
}
