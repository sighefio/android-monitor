import Foundation
import Encode
import Audio

public actor FrameDispatcher {
    private var sessions: [UUID: ClientSession] = [:]

    public init() {}

    public func register(_ session: ClientSession) {
        sessions[session.id] = session
    }

    public func unregister(_ session: ClientSession) {
        sessions.removeValue(forKey: session.id)
    }

    public func broadcastVideo(displayId: UInt32, sample: EncodedVideoSample) async {
        let snapshot = Array(sessions.values)
        await withTaskGroup(of: Void.self) { group in
            for session in snapshot {
                group.addTask { await session.sendVideo(displayId: displayId, sample: sample) }
            }
        }
    }

    public func broadcastAudio(_ sample: EncodedAudioSample) async {
        let snapshot = Array(sessions.values)
        await withTaskGroup(of: Void.self) { group in
            for session in snapshot {
                group.addTask { await session.sendAudio(sample) }
            }
        }
    }
}
