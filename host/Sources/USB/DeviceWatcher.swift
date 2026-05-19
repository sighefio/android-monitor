import Foundation
import IOKit
import IOKit.usb
import Core

public actor DeviceWatcher {
    private let log = Log(category: "usb.watcher")
    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var onDeviceConnected: (@Sendable () -> Void)?
    private var onDeviceDisconnected: (@Sendable () -> Void)?

    public init() {}

    public func start(onConnected: @escaping @Sendable () -> Void, onDisconnected: @escaping @Sendable () -> Void) {
        self.onDeviceConnected = onConnected
        self.onDeviceDisconnected = onDisconnected

        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.global(qos: .utility))
        self.notifyPort = port

        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        log.info("USB device watcher started")
        _ = matchingDict
    }

    public func stop() {
        if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let port = notifyPort { IONotificationPortDestroy(port); notifyPort = nil }
    }
}
