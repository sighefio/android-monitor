import XCTest
import CoreGraphics
@testable import Input
@testable import Core

final class RecordingPoster: EventPosterProtocol, @unchecked Sendable {
    var events: [(type: CGEventType, position: CGPoint)] = []
    func post(_ event: CGEvent) {
        events.append((type: event.type, position: event.location))
    }
}

final class TouchInjectorTests: XCTestCase {
    func testInjectMapsNormalizedCoords() {
        let poster = RecordingPoster()
        let injector = TouchEventInjector(poster: poster)
        injector.updateDisplayBounds(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        injector.inject(TouchPacket(action: .down, pointerId: 0, xNorm: 0.5, yNorm: 0.5, pressure: 1.0))
        XCTAssertEqual(poster.events.count, 1)
        XCTAssertEqual(poster.events[0].type, .leftMouseDown)
        XCTAssertEqual(poster.events[0].position.x, 960)
        XCTAssertEqual(poster.events[0].position.y, 540)
    }

    func testNonPrimaryPointersAreIgnored() {
        let poster = RecordingPoster()
        let injector = TouchEventInjector(poster: poster)
        injector.updateDisplayBounds(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        injector.inject(TouchPacket(action: .down, pointerId: 1, xNorm: 0.5, yNorm: 0.5, pressure: 1.0))
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testDragGeneratedAfterDown() {
        let poster = RecordingPoster()
        let injector = TouchEventInjector(poster: poster)
        injector.updateDisplayBounds(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        injector.inject(TouchPacket(action: .down, pointerId: 0, xNorm: 0.1, yNorm: 0.1, pressure: 1.0))
        injector.inject(TouchPacket(action: .move, pointerId: 0, xNorm: 0.5, yNorm: 0.5, pressure: 1.0))
        injector.inject(TouchPacket(action: .up,   pointerId: 0, xNorm: 0.5, yNorm: 0.5, pressure: 0.0))
        XCTAssertEqual(poster.events.map { $0.type }, [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
    }
}
