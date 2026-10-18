import AppKit
import XCTest
import HushCore
@testable import Hush

final class DimmerLayeringTests: XCTestCase {
    @MainActor
    func testInterruptedFadeDoesNotHideNewFocusAndAnimationsStopWhenDone() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a window server") }
        let window = NSWindow(contentRect: CGRect(x: screen.frame.midX - 100, y: screen.frame.midY - 100, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.orderFrontRegardless()
        let dimmer = Dimmer(); dimmer.fadeDuration = 0.08
        defer { dimmer.hide(); window.close() }
        let target = FocusedWindow(number: window.windowNumber, level: window.level.rawValue)
        dimmer.show(window: target)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        let panels = NSApp.windows.compactMap { $0 as? DimmerPanel }.filter(\.isVisible)
        XCTAssertFalse(panels.isEmpty)
        XCTAssertTrue(panels.allSatisfy { $0.contentView?.layer?.animation(forKey: "hush.fade") != nil })
        dimmer.hide(animated: true)
        dimmer.show(window: target)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(panels.allSatisfy(\.isVisible), "Completion of the interrupted fade must not hide the new focus")
        XCTAssertTrue(panels.allSatisfy { $0.contentView?.layer?.animationKeys()?.isEmpty != false })
        for panel in panels { XCTAssertEqual(panel.contentView?.layer?.opacity ?? -1, 0.45, accuracy: 0.001) }
        dimmer.hide(animated: true)
        dimmer.fadeDuration = 0
        XCTAssertTrue(panels.allSatisfy { !$0.isVisible }, "Turning fades off must finish a pending fade-out immediately")
        dimmer.fadeDuration = 0.08
        dimmer.show(window: target)
        dimmer.hide(animated: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(panels.allSatisfy { !$0.isVisible })
    }

    @MainActor
    func testDimmingStaysBehindWindowWithoutFollowingItsFrame() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a window server") }
        let frame = CGRect(x: screen.frame.midX - 220, y: screen.frame.midY - 140, width: 440, height: 280)
        let focused = NSWindow(contentRect: frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        focused.isReleasedWhenClosed = false
        focused.orderFrontRegardless()
        let dimmer = Dimmer()
        defer { dimmer.hide(); focused.close() }
        dimmer.show(window: FocusedWindow(number: focused.windowNumber, level: focused.level.rawValue))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        func assertWindowAboveDimmer(file: StaticString = #filePath, line: UInt = #line) throws {
            let info = try XCTUnwrap(CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]])
            let numbers = info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
            let focusedIndex = try XCTUnwrap(numbers.firstIndex(of: focused.windowNumber))
            let panels = NSApp.windows.compactMap { $0 as? DimmerPanel }.filter(\.isVisible)
            XCTAssertFalse(panels.isEmpty, file: file, line: line)
            for panel in panels {
                let panelIndex = try XCTUnwrap(numbers.firstIndex(of: panel.windowNumber))
                XCTAssertGreaterThan(panelIndex, focusedIndex,
                    "Dimming must sit behind the real window, so its native corners and fast dragging stay clear.", file: file, line: line)
            }
        }
        try assertWindowAboveDimmer()
        // A large drag and resize must work without any subsequent tracker update.
        focused.setFrame(frame.offsetBy(dx: 180, dy: -100).insetBy(dx: -70, dy: -40), display: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        try assertWindowAboveDimmer()
    }
}
