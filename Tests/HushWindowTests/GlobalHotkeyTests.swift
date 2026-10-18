import AppKit
import Carbon
import XCTest
import HushCore
@testable import Hush

final class GlobalHotkeyTests: XCTestCase {
    @MainActor
    func testEachHotkeyDispatchesOnlyItsOwnActionAndReleasesItsRegistration() throws {
        _ = NSApplication.shared
        let firstKey = KeyboardShortcut(keyCode: UInt32(kVK_F18), modifiers: 15, keyName: "F18")
        let secondKey = KeyboardShortcut(keyCode: UInt32(kVK_F19), modifiers: 15, keyName: "F19")
        var first: GlobalHotkey? = GlobalHotkey(shortcut: firstKey, id: 101)
        let second = GlobalHotkey(shortcut: secondKey, id: 102)
        guard first?.available == true, second.available else { throw XCTSkip("Test shortcut already in use on this Mac") }
        var firstCalls = 0, secondCalls = 0
        first?.action = { firstCalls += 1 }; second.action = { secondCalls += 1 }
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event), noErr)
        let created = try XCTUnwrap(event); defer { ReleaseEvent(created) }
        var identifier = EventHotKeyID(signature: 0x48555348, id: 101)
        XCTAssertEqual(SetEventParameter(created, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier), noErr)
        XCTAssertEqual(SendEventToEventTarget(created, GetApplicationEventTarget()), noErr)
        XCTAssertEqual(firstCalls, 1); XCTAssertEqual(secondCalls, 0)
        let duplicate = GlobalHotkey(shortcut: firstKey, id: 103)
        XCTAssertFalse(duplicate.available)
        first = nil
        let replacement = GlobalHotkey(shortcut: firstKey, id: 104)
        XCTAssertTrue(replacement.available)
    }
}
