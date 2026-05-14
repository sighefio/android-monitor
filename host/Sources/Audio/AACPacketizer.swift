import Foundation

public enum AACPacketizer {
    public static func makeAudioPayload(_ sample: EncodedAudioSample) -> Data {
        var payload = Data()
        payload.reserveCapacity(2 + sample.data.count)
        payload.append(sample.channels)
        payload.append(UInt8(sample.sampleRate / 100 > 255 ? 255 : sample.sampleRate / 100))
        payload.append(sample.data)
        return payload
    }
}
