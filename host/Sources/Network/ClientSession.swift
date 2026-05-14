import Foundation
import Network

public protocol ClientSessionDelegate: AnyObject, Sendable {
    func session(_ session: ClientSession, didReceiveHandshake request: HandshakeRequest) async
    func session(_ session: ClientSession, didSelectDisplay id: UInt32) async
    func session(_ session: ClientSession, didReceiveTouch packet: TouchPacket) async
    func session(_ session: ClientSession, didReceiveKey packet: KeyPacket) async
    func session(_ session: ClientSession, didClose error: Error?) async
}

public actor ClientSession {
    public let id: UUID
    private let log: Log
    private let connection: NWConnection
    private weak var delegate: ClientSessionDelegate?
    private var sendSequence: UInt64 = 0
    private var receiveBuffer = Data()
    private var isOpen = true

    public init(connection: NWConnection, delegate: ClientSessionDelegate) {
        self.id = UUID()
        self.connection = connection
        self.delegate = delegate
        self.log = Log(category: "net.session")
    }

    public func start() {
        let queue = DispatchQueue(label: "com.androidmonitor.session.\(id.uuidString)", qos: .userInteractive)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleState(state) }
        }
        connection.start(queue: queue)
        Task { await receiveLoop() }
    }

    public func close(error: Error? = nil) async {
        guard isOpen else { return }
        isOpen = false
        connection.cancel()
        await delegate?.session(self, didClose: error)
    }

    public func sendVideo(displayId: UInt32, sample: EncodedVideoSample) async {
        let payload = NALPacketizer.makeVideoPayload(displayId: displayId, sample: sample)
        var flags: PacketFlags = [.frameStart, .frameEnd]
        if sample.isKeyframe { flags.insert(.keyFrame) }
        let data = ProtocolEncoder.encode(type: .videoFrame, flags: flags, sequence: nextSequence(), payload: payload)
        await sendRaw(data)
    }

    public func sendAudio(_ sample: EncodedAudioSample) async {
        let payload = AACPacketizer.makeAudioPayload(sample)
        let data = ProtocolEncoder.encode(type: .audioFrame, flags: [], sequence: nextSequence(), payload: payload)
        await sendRaw(data)
    }

    public func sendHandshakeAck(_ ack: HandshakeAck) async throws {
        let data = try ProtocolEncoder.encodeJSON(type: .handshakeAck, sequence: nextSequence(), value: ack)
        await sendRaw(data)
    }

    public func sendHandshakeError(_ err: HandshakeError) async throws {
        let data = try ProtocolEncoder.encodeJSON(type: .handshakeErr, sequence: nextSequence(), value: err)
        await sendRaw(data)
    }

    public func sendDisplayList(_ displays: [DisplayDescriptor]) async throws {
        let data = try ProtocolEncoder.encodeJSON(type: .displayList, sequence: nextSequence(), value: displays)
        await sendRaw(data)
    }

    public func sendPong(payload: Data) async {
        let data = ProtocolEncoder.encode(type: .pong, flags: [], sequence: nextSequence(), payload: payload)
        await sendRaw(data)
    }

    private func nextSequence() -> UInt64 {
        sendSequence &+= 1
        return sendSequence
    }

    private func sendRaw(_ data: Data) async {
        guard isOpen else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }

    private func handleState(_ state: NWConnection.State) async {
        switch state {
        case .ready:
            log.info("session \(id.uuidString) ready")
        case .failed(let error):
            log.warn("session \(id.uuidString) failed: \(error.localizedDescription)")
            await close(error: error)
        case .cancelled:
            await close(error: nil)
        default:
            break
        }
    }

    private func receiveLoop() async {
        while isOpen {
            let chunk: Data? = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let error {
                        Task { [weak self] in await self?.close(error: error) }
                        continuation.resume(returning: nil)
                        return
                    }
                    if isComplete {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: data)
                }
            }
            guard let chunk, !chunk.isEmpty else { break }
            receiveBuffer.append(chunk)
            await drainBuffer()
        }
        await close(error: nil)
    }

    private func drainBuffer() async {
        while receiveBuffer.count >= Protocol.headerSize {
            let headerSlice = Array(receiveBuffer.prefix(Protocol.headerSize))[...]
            let header: PacketHeader
            do {
                header = try PacketCodec.decodeHeader(headerSlice)
            } catch {
                log.warn("invalid header: \(error)")
                await close(error: error)
                return
            }
            let totalPacket = Protocol.headerSize + Int(header.length)
            if receiveBuffer.count < totalPacket { return }
            let payload = receiveBuffer.subdata(in: Protocol.headerSize..<totalPacket)
            receiveBuffer.removeFirst(totalPacket)
            await dispatch(header: header, payload: payload)
        }
    }

    private func dispatch(header: PacketHeader, payload: Data) async {
        switch header.type {
        case .handshakeReq:
            decodeJSON(HandshakeRequest.self, payload) { [weak self] req in
                guard let self else { return }
                Task { await self.delegate?.session(self, didReceiveHandshake: req) }
            }
        case .selectDisplay:
            decodeJSON(SelectDisplayMessage.self, payload) { [weak self] msg in
                guard let self else { return }
                Task { await self.delegate?.session(self, didSelectDisplay: msg.displayId) }
            }
        case .touchEvent:
            do {
                let packet = try PacketCodec.decodeTouchPayload(Array(payload)[...])
                await delegate?.session(self, didReceiveTouch: packet)
            } catch {
                log.warn("touch decode failed: \(error)")
            }
        case .keyEvent:
            do {
                let packet = try PacketCodec.decodeKeyPayload(Array(payload)[...])
                await delegate?.session(self, didReceiveKey: packet)
            } catch {
                log.warn("key decode failed: \(error)")
            }
        case .ping:
            await sendPong(payload: payload)
        default:
            log.debug("unhandled packet \(header.type.rawValue)")
        }
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, _ data: Data, _ handler: (T) -> Void) {
        do {
            let value = try JSONDecoder().decode(type, from: data)
            handler(value)
        } catch {
            log.warn("JSON decode failed for \(type): \(error.localizedDescription)")
        }
    }
}
