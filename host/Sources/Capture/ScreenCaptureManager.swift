import Foundation
@preconcurrency import ScreenCaptureKit
import CoreGraphics

@available(macOS 13.0, *)
public actor ScreenCaptureManager {
    private let log = Log(category: "capture.manager")

    public init() {}

    public func availableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        return content.displays
    }

    public func describe(_ displays: [SCDisplay]) -> [DisplayDescriptor] {
        displays.map { display in
            DisplayDescriptor(
                displayId: UInt32(display.displayID),
                name: "Display \(display.displayID) (\(display.width)x\(display.height))",
                width: UInt32(display.width),
                height: UInt32(display.height),
                isPrimary: display.displayID == CGMainDisplayID()
            )
        }
    }

    public func display(withId id: UInt32, from displays: [SCDisplay]) -> SCDisplay? {
        displays.first { UInt32($0.displayID) == id }
    }
}
