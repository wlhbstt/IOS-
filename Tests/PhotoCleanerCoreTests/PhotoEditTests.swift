import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import PhotoCleanerCore

final class PhotoEditTests: XCTestCase {
    func testCropUsesCenteredRatioInBothOrientations() {
        XCTAssertEqual(EditAspect.square.crop(in: CGRect(x: 10, y: 20, width: 400, height: 300)),
                       CGRect(x: 60, y: 20, width: 300, height: 300))
        XCTAssertEqual(EditAspect.landscape.crop(in: CGRect(x: 0, y: 0, width: 300, height: 500)),
                       CGRect(x: 0, y: 137.5, width: 300, height: 225))
    }

    func testAIAdjustmentsRespectBrightnessAndZeroStrength() {
        let low = EditEnhancement.suggest(brightness: 0.12, portrait: true)
        let bright = EditEnhancement.suggest(brightness: 0.82, portrait: false)
        XCTAssertGreaterThan(low.exposure, bright.exposure)
        XCTAssertGreaterThan(low.shadows, 0)
        XCTAssertLessThanOrEqual(low.exposure, 0.65)
        XCTAssertEqual(low.at(strength: 0), .init())
        XCTAssertEqual(low.at(strength: 2), low)
    }
}
