import Foundation
@preconcurrency import ScreenCaptureKit

@available(macOS 13.0, *)
public actor DisplayPicker {
    private var displays: [SCDisplay] = []
    private var selected: SCDisplay?

    public init() {}

    public func refresh(using manager: ScreenCaptureManager) async throws -> [DisplayDescriptor] {
        displays = try await manager.availableDisplays()
        if selected == nil {
            selected = displays.first
        }
        return await manager.describe(displays)
    }

    public func select(displayId: UInt32) -> SCDisplay? {
        if let match = displays.first(where: { UInt32($0.displayID) == displayId }) {
            selected = match
            return match
        }
        return nil
    }

    public func currentSelection() -> SCDisplay? {
        selected
    }

    public func currentDisplays() -> [SCDisplay] {
        displays
    }
}
