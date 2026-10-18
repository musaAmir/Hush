import XCTest
@testable import HushCore

final class HushSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "HushTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite); defaults = nil }

    func testExistingPreferencesSurviveAndStartupPolicyIsIndependent() {
        defaults.set(false, forKey: "enabled"); defaults.set(0.63, forKey: "intensity")
        let settings = HushSettings(defaults: defaults)
        XCTAssertFalse(settings.enabledAtLaunch); XCTAssertEqual(settings.intensity, 0.63)
        settings.startup = .enabled; XCTAssertTrue(settings.enabledAtLaunch)
        XCTAssertFalse(settings.enabled)
        settings.startup = .disabled; settings.enabled = true; XCTAssertFalse(settings.enabledAtLaunch)
        settings.startup = .remember; XCTAssertTrue(settings.enabledAtLaunch)
    }
    func testFadeBoundsAndReduceMotionOverride() {
        let settings = HushSettings(defaults: defaults)
        XCTAssertEqual(settings.fadeDuration, 0.5)
        settings.fadeDuration = 100; XCTAssertEqual(settings.fadeDuration, 2)
        settings.fadeDuration = -1; XCTAssertEqual(settings.fadeDuration, 0.05)
        settings.fadeDuration = .nan; XCTAssertEqual(settings.fadeDuration, 0.5)
        XCTAssertEqual(settings.effectiveFadeDuration(reduceMotion: true), 0)
        settings.fadesEnabled = false; XCTAssertEqual(settings.effectiveFadeDuration(reduceMotion: false), 0)
        settings.fadesEnabled = true; XCTAssertEqual(settings.effectiveFadeDuration(reduceMotion: false), 0.5)
    }
    func testClearedShortcutDoesNotReturnAfterRelaunchAndInvalidDataIsSafe() {
        let settings = HushSettings(defaults: defaults)
        XCTAssertEqual(settings.shortcut(for: .toggle), .defaultToggle)
        settings.setShortcut(nil, for: .toggle)
        XCTAssertNil(HushSettings(defaults: defaults).shortcut(for: .toggle))
        let shortcut = KeyboardShortcut(keyCode: 40, modifiers: KeyboardShortcut.command | KeyboardShortcut.shift, keyName: "K")
        settings.setShortcut(shortcut, for: .enable)
        XCTAssertEqual(HushSettings(defaults: defaults).shortcut(for: .enable), shortcut)
        defaults.set(Data("bad data".utf8), forKey: "shortcut.disable")
        XCTAssertNil(settings.shortcut(for: .disable))
        settings.setShortcut(KeyboardShortcut(keyCode: 0, modifiers: 0, keyName: "A"), for: .enable)
        XCTAssertEqual(settings.shortcut(for: .enable), shortcut)
    }
    func testShortcutsRequireARealModifierAndMatchPhysicalCombination() {
        XCTAssertFalse(KeyboardShortcut(keyCode: 0, modifiers: 0, keyName: "A").isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 0, modifiers: KeyboardShortcut.shift, keyName: "A").isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 55, modifiers: KeyboardShortcut.control, keyName: "⌘").isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 0, modifiers: 32, keyName: "A").isValid)
        XCTAssertTrue(KeyboardShortcut.defaultToggle.matches(KeyboardShortcut(keyCode: 2, modifiers: 6, keyName: "d")))
        XCTAssertEqual(KeyboardShortcut.defaultToggle.display, "⌃⌥D")
    }
    func testExclusionsPersistDeduplicateAndResumeOtherApps() {
        let settings = HushSettings(defaults: defaults)
        let finder = ExcludedApplication(bundleID: "com.apple.finder", name: "Finder")
        settings.exclusions = [finder, finder, ExcludedApplication(bundleID: "", name: "Invalid")]
        let reloaded = HushSettings(defaults: defaults)
        XCTAssertEqual(reloaded.exclusions, [finder])
        XCTAssertTrue(reloaded.isExcluded("com.apple.finder"))
        XCTAssertFalse(reloaded.isExcluded("com.apple.Safari")); XCTAssertFalse(reloaded.isExcluded(nil))
        settings.exclusions = []; XCTAssertFalse(reloaded.isExcluded("com.apple.finder"))
    }
}
