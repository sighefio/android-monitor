import Foundation
import CoreGraphics
import Core

public protocol EventPosterProtocol: Sendable {
    func post(_ event: CGEvent)
}

public struct DefaultEventPoster: EventPosterProtocol {
    public init() {}
    public func post(_ event: CGEvent) {
        event.post(tap: .cghidEventTap)
    }
}

public final class TouchEventInjector: @unchecked Sendable {
    private let log = Log(category: "input.touch")
    private let poster: EventPosterProtocol
    private var isButtonDown = false
    private var displayBounds: CGRect = .zero

    public init(poster: EventPosterProtocol = DefaultEventPoster()) {
        self.poster = poster
    }

    public func updateDisplayBounds(_ bounds: CGRect) {
        displayBounds = bounds
    }

    public func inject(_ packet: TouchPacket) {
        guard packet.pointerId == 0 else { return }
        let x = CGFloat(packet.xNorm) * displayBounds.width + displayBounds.origin.x
        let y = CGFloat(packet.yNorm) * displayBounds.height + displayBounds.origin.y
        let location = CGPoint(x: x, y: y)

        let type: CGEventType
        switch packet.action {
        case .down:
            type = .leftMouseDown
            isButtonDown = true
        case .up, .cancel:
            type = .leftMouseUp
            isButtonDown = false
        case .move:
            type = isButtonDown ? .leftMouseDragged : .mouseMoved
        }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left) else { return }
        poster.post(event)
    }
}
