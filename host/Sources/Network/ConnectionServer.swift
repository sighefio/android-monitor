import Foundation
import Network

public protocol ConnectionServerDelegate: ClientSessionDelegate {
    func server(_ server: ConnectionServer, didAcceptSession session: ClientSession) async
}

public actor ConnectionServer {
    private let log = Log(category: "net.server")
    private var listener: NWListener?
    private weak var delegate: ConnectionServerDelegate?
    private let port: NWEndpoint.Port

    public init(port: UInt16, delegate: ConnectionServerDelegate) throws {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "ConnectionServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid port"])
        }
        self.port = port
        self.delegate = delegate
    }

    public func start() throws {
        let params = NWParameters.tcp
        if let tcpOptions = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 10
            tcpOptions.keepaliveInterval = 5
            tcpOptions.keepaliveCount = 3
        }
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleNewConnection(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleListenerState(state) }
        }
        listener.start(queue: .global(qos: .userInteractive))
        self.listener = listener
        log.info("listening on port \(self.port.rawValue)")
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
    }

    private func handleNewConnection(_ connection: NWConnection) async {
        guard let delegate else {
            connection.cancel()
            return
        }
        let session = ClientSession(connection: connection, delegate: delegate)
        await session.start()
        await delegate.server(self, didAcceptSession: session)
    }

    private func handleListenerState(_ state: NWListener.State) async {
        switch state {
        case .failed(let error):
            log.error("listener failed: \(error.localizedDescription)")
        case .cancelled:
            log.info("listener cancelled")
        default:
            break
        }
    }
}
