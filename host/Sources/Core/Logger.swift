import Foundation
import os

public struct Log: Sendable {
    private let logger: Logger

    public init(subsystem: String = "com.androidmonitor.daemon", category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func debug(_ message: @autoclosure () -> String) {
        logger.debug("\(message(), privacy: .public)")
    }

    public func info(_ message: @autoclosure () -> String) {
        logger.info("\(message(), privacy: .public)")
    }

    public func warn(_ message: @autoclosure () -> String) {
        logger.warning("\(message(), privacy: .public)")
    }

    public func error(_ message: @autoclosure () -> String) {
        logger.error("\(message(), privacy: .public)")
    }
}

public enum Timestamp {
    public static func monotonicMicroseconds() -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let ticks = mach_absolute_time()
        let nanos = ticks &* UInt64(info.numer) / UInt64(info.denom)
        return nanos / 1_000
    }
}
