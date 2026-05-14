import XCTest
@testable import Encode

final class VideoEncoderTests: XCTestCase {
    func testEncoderConfigNegotiation() {
        let cfg = VideoEncoderConfig.negotiate(
            clientWidth: 2400,
            clientHeight: 1080,
            clientFps: 120,
            displayWidth: 3024,
            displayHeight: 1964,
            userScalePercent: 75,
            userMaxFps: 60,
            bitrateKbps: 8000,
            keyframeIntervalSeconds: 2
        )
        XCTAssertEqual(cfg.width, 1800)
        XCTAssertEqual(cfg.height, 810)
        XCTAssertEqual(cfg.fps, 60)
        XCTAssertEqual(cfg.bitrateKbps, 8000)
    }

    func testNegotiationClampsToDisplay() {
        let cfg = VideoEncoderConfig.negotiate(
            clientWidth: 7680,
            clientHeight: 4320,
            clientFps: 60,
            displayWidth: 1920,
            displayHeight: 1080,
            userScalePercent: 100,
            userMaxFps: 60,
            bitrateKbps: 8000,
            keyframeIntervalSeconds: 2
        )
        XCTAssertEqual(cfg.width, 1920)
        XCTAssertEqual(cfg.height, 1080)
    }

    func testEvenDimensions() {
        let cfg = VideoEncoderConfig.negotiate(
            clientWidth: 1001,
            clientHeight: 999,
            clientFps: 60,
            displayWidth: 2000,
            displayHeight: 2000,
            userScalePercent: 100,
            userMaxFps: 60,
            bitrateKbps: 8000,
            keyframeIntervalSeconds: 2
        )
        XCTAssertEqual(cfg.width % 2, 0)
        XCTAssertEqual(cfg.height % 2, 0)
    }
}
