import XCTest
import CoreGraphics
@testable import HushCore

final class FocusGeometryTests: XCTestCase {
    func testAccessibilityCoordinatesFlipAroundPrimaryDisplay() {
        XCTAssertEqual(FocusGeometry.cocoaRect(fromAccessibility:CGRect(x:30,y:100,width:600,height:400),primaryHeight:1080),CGRect(x:30,y:580,width:600,height:400))
    }
    func testDisplayAbovePrimaryAndLeftOfPrimary() {
        XCTAssertEqual(FocusGeometry.cocoaRect(fromAccessibility:CGRect(x:-900,y:-700,width:800,height:500),primaryHeight:1080),CGRect(x:-900,y:1280,width:800,height:500))
    }
    func testCutoutClipsWindowAcrossTwoDisplays() {
        let window = CGRect(x:800,y:200,width:700,height:600)
        XCTAssertEqual(FocusGeometry.cutout(window:window,screen:CGRect(x:0,y:0,width:1000,height:1000)),CGRect(x:800,y:200,width:200,height:600))
        XCTAssertEqual(FocusGeometry.cutout(window:window,screen:CGRect(x:1000,y:0,width:1000,height:1000)),CGRect(x:0,y:200,width:500,height:600))
    }
    func testOtherDisplayHasNoCutout() {
        XCTAssertNil(FocusGeometry.cutout(window:CGRect(x:0,y:0,width:500,height:500),screen:CGRect(x:1000,y:0,width:1000,height:1000)))
    }
    func testInvalidGeometryAndOpacityCannotBlankTheScreen() {
        XCTAssertNil(FocusGeometry.cocoaRect(fromAccessibility:.zero,primaryHeight:1080))
        XCTAssertNil(FocusGeometry.cocoaRect(fromAccessibility:CGRect(x:Double.nan,y:0,width:500,height:500),primaryHeight:1080))
        XCTAssertEqual(FocusGeometry.opacity(.nan),0.45)
        XCTAssertEqual(FocusGeometry.opacity(1),0.85)
        XCTAssertEqual(FocusGeometry.opacity(-1),0.05)
    }
}
