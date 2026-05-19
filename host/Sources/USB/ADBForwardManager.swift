import Foundation
import Core

public actor ADBForwardManager {
    private let log = Log(category: "usb.adb")
    private let port: UInt16
    private var adbPath: String?

    public init(port: UInt16) {
        self.port = port
    }

    public func locateAdb() -> String? {
        if let cached = adbPath { return cached }
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb",
            (ProcessInfo.processInfo.environment["ANDROID_HOME"] ?? "") + "/platform-tools/adb",
            (ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"] ?? "") + "/platform-tools/adb"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            adbPath = path
            return path
        }
        return runWhich("adb")
    }

    public func enableForward() async -> Bool {
        guard let adb = locateAdb() else {
            log.warn("adb not found in PATH or known locations")
            return false
        }
        let ok = await run(adb, ["forward", "tcp:\(port)", "tcp:\(port)"])
        if ok {
            let p = port
            log.info("adb forward tcp:\(p) tcp:\(p) installed")
        }
        return ok
    }

    public func disableForward() async {
        guard let adb = locateAdb() else { return }
        _ = await run(adb, ["forward", "--remove", "tcp:\(port)"])
    }

    private func runWhich(_ name: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private func run(_ executable: String, _ arguments: [String]) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: executable)
                task.arguments = arguments
                task.standardOutput = Pipe()
                task.standardError = Pipe()
                do {
                    try task.run()
                    task.waitUntilExit()
                    cont.resume(returning: task.terminationStatus == 0)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }
}
