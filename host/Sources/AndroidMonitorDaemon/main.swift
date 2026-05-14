import Foundation

@available(macOS 13.0, *)
func runDaemon() async {
    let args = CommandLine.arguments
    var config = ServerConfig.default
    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--port":
            index += 1
            if index < args.count, let port = UInt16(args[index]) {
                config.port = port
            }
        case "--bitrate":
            index += 1
            if index < args.count, let kbps = UInt32(args[index]) {
                config.defaultBitrateKbps = kbps
            }
        case "--mode":
            index += 1
            if index < args.count, let mode = ConnectionMode(rawValue: args[index]) {
                config.connectionMode = mode
            }
        case "--help", "-h":
            print("""
            AndroidMonitorDaemon
              --port <port>      TCP port (default 7878)
              --bitrate <kbps>   default video bitrate
              --mode <wifi|usb|both>  connection mode (default both)
            """)
            return
        default:
            FileHandle.standardError.write("unknown arg: \(arg)\n".data(using: .utf8) ?? Data())
        }
        index += 1
    }

    let coordinator = StreamCoordinator(config: config)
    do {
        try await coordinator.start()
    } catch {
        FileHandle.standardError.write("start failed: \(error)\n".data(using: .utf8) ?? Data())
        exit(1)
    }

    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signalSource.setEventHandler {
        Task {
            await coordinator.stop()
            exit(0)
        }
    }
    signal(SIGINT, SIG_IGN)
    signalSource.resume()

    try? await Task.sleep(nanoseconds: UInt64.max)
}

if #available(macOS 13.0, *) {
    await runDaemon()
} else {
    FileHandle.standardError.write("AndroidMonitorDaemon requires macOS 13.0+\n".data(using: .utf8) ?? Data())
    exit(1)
}
