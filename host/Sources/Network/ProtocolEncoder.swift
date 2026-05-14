import Foundation

public enum ProtocolEncoder {
    public static func encode(type: PacketType, flags: PacketFlags, sequence: UInt64, payload: Data) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Protocol.headerSize + payload.count)
        let header = PacketHeader(
            type: type,
            flags: flags,
            length: UInt32(payload.count),
            sequence: sequence,
            timestampUs: Timestamp.monotonicMicroseconds()
        )
        PacketCodec.encodeHeader(header, into: &bytes)
        var data = Data(bytes)
        data.append(payload)
        return data
    }

    public static func encodeJSON<T: Encodable>(
        type: PacketType,
        flags: PacketFlags = [],
        sequence: UInt64,
        value: T
    ) throws -> Data {
        let encoder = JSONEncoder()
        let payload = try encoder.encode(value)
        return encode(type: type, flags: flags, sequence: sequence, payload: payload)
    }

    public static func encodeEmpty(type: PacketType, sequence: UInt64) -> Data {
        encode(type: type, flags: [], sequence: sequence, payload: Data())
    }
}
