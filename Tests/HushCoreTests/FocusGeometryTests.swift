import XCTest
import CoreGraphics
@testable import HushCore

final class FocusGeometryTests: XCTestCase {
    func testOpacityCannotBlankTheScreen() {
        XCTAssertEqual(FocusGeometry.opacity(.nan),0.45)
        XCTAssertEqual(FocusGeometry.opacity(1),0.85)
        XCTAssertEqual(FocusGeometry.opacity(-1),0.05)
    }

    func testWindowMatchingUsesOwnershipAndUnscaledTopLeftCoordinates() {
        let frame = CGRect(x: -900, y: -700, width: 800, height: 500)
        let candidates = [WindowCandidate(number: 10, level: 0, ownerPID: 999, frame: frame),
                          WindowCandidate(number: 11, level: 0, ownerPID: 42, frame: frame)]
        XCTAssertEqual(WindowMatching.focusedWindow(ownerPID: 42, frame: frame, candidates: candidates), FocusedWindow(number: 11, level: 0))
    }

    func testWindowMatchingRejectsStaleBoundsAndInvalidWindows() {
        let frame = CGRect(x: 300, y: 100, width: 600, height: 400)
        let candidates = [WindowCandidate(number: 1, level: 0, ownerPID: 42, frame: frame.offsetBy(dx: 20, dy: 0)),
                          WindowCandidate(number: 2, level: 0, ownerPID: 42, frame: frame, alpha: 0),
                          WindowCandidate(number: 3, level: 24, ownerPID: 42, frame: frame),
                          WindowCandidate(number: 0, level: 0, ownerPID: 42, frame: frame)]
        XCTAssertNil(WindowMatching.focusedWindow(ownerPID: 42, frame: frame, candidates: candidates))
        XCTAssertNil(WindowMatching.focusedWindow(ownerPID: 42, frame: .zero, candidates: candidates))
        XCTAssertNil(WindowMatching.focusedWindow(ownerPID: 42, frame: CGRect(x: Double.nan, y: 0, width: 600, height: 400), candidates: candidates))
    }

    func testMatchingPreservesFloatingWindowLevelAndFrontToBackOrder() {
        let frame = CGRect(x: 20, y: 100, width: 600, height: 400)
        let candidates = [WindowCandidate(number: 12, level: 8, ownerPID: 42, frame: frame.insetBy(dx: -0.5, dy: -0.5)),
                          WindowCandidate(number: 13, level: 0, ownerPID: 42, frame: frame)]
        XCTAssertEqual(WindowMatching.focusedWindow(ownerPID: 42, frame: frame, candidates: candidates), FocusedWindow(number: 12, level: 8))
    }
}
