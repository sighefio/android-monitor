import Foundation

public enum NALPacketizer {
    public static func makeVideoPayload(displayId: UInt32, sample: EncodedVideoSample) -> Data {
        var payload = Data()
        payload.reserveCapacity(1 + (sample.parameterSets?.count ?? 0) + sample.data.count)
        payload.append(UInt8(displayId & 0xFF))
        if sample.isKeyframe, let ps = sample.parameterSets {
            payload.append(ps)
        }
        payload.append(sample.data)
        return payload
    }
}
