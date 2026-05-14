import Foundation
import CoreGraphics

public final class KeyboardInjector: @unchecked Sendable {
    private let log = Log(category: "input.keyboard")
    private let poster: EventPosterProtocol

    public init(poster: EventPosterProtocol = DefaultEventPoster()) {
        self.poster = poster
    }

    public func inject(_ packet: KeyPacket) {
        let keyDown = packet.action == .down

        if packet.unicodeChar != 0 {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown) else { return }
            var scalar = UniChar(packet.unicodeChar & 0xFFFF)
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &scalar)
            event.flags = cgFlags(for: packet.modifiers)
            poster.post(event)
            return
        }

        guard let mac = KeycodeMap.macKeyCode(forAndroidKeycode: packet.androidKeycode) else {
            log.debug("no mac keycode for android \(packet.androidKeycode)")
            return
        }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: mac, keyDown: keyDown) else { return }
        event.flags = cgFlags(for: packet.modifiers)
        poster.post(event)
    }

    private func cgFlags(for modifiers: KeyModifiers) -> CGEventFlags {
        var flags = CGEventFlags()
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.ctrl)  { flags.insert(.maskControl) }
        if modifiers.contains(.alt)   { flags.insert(.maskAlternate) }
        if modifiers.contains(.meta)  { flags.insert(.maskCommand) }
        return flags
    }
}
