import AppKit
import ApplicationServices
import HushCore

@main enum HushApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = HushSettings()
    private let tracker = FocusTracker()
    private let dimmer = Dimmer()
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var resumeItem: NSMenuItem!
    private var hotkeys: [ShortcutAction: GlobalHotkey] = [:]
    private var shortcutWarnings: [ShortcutAction: String] = [:]
    private var settingsWindow: SettingsWindowController?
    private var enabled = true
    private var pausedUntil: Date?
    private var pauseTimer: Timer?
    private var recordingShortcut = false
    private var displayObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        enabled = settings.enabledAtLaunch
        settings.enabled = enabled
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "Hush"
        statusItem.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Hush")
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        toggleItem = item("Enable Dimming", #selector(toggle)); menu.addItem(toggleItem)
        pauseItem = NSMenuItem(title: "Pause Dimming", action: nil, keyEquivalent: "")
        let pauses = NSMenu(); pauses.autoenablesItems = false
        for (title, minutes) in [("5 minutes", 5), ("15 minutes", 15), ("1 hour", 60)] {
            let choice = item(title, #selector(pauseFromMenu(_:))); choice.tag = minutes; pauses.addItem(choice)
        }
        pauseItem.submenu = pauses; menu.addItem(pauseItem)
        resumeItem = item("Resume Dimming", #selector(resume)); menu.addItem(resumeItem)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Quit Hush", #selector(quit), key: "q"))
        statusItem.menu = menu
        tracker.shouldDimApplication = { [weak self] id in self?.settings.isExcluded(id) != true }
        tracker.onWindow = { [weak self] window in
            guard let self, self.enabled, self.pausedUntil == nil else { return }
            self.dimmer.show(window: window)
        }
        tracker.onPermission = { [weak self] _ in self?.syncControls() }
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.applyAppearance() }
        applyAppearance(); registerShortcuts(); applyEnabled()
        if !AXIsProcessTrusted() { showSettings() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        pauseTimer?.invalidate(); settingsWindow?.cancelRecording(); hotkeys.removeAll()
        tracker.stop(); dimmer.hide()
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return false }
    func applicationDidBecomeActive(_ notification: Notification) {
        if let pausedUntil, pausedUntil <= Date() { pause(minutes: nil) }
        syncControls(); tracker.refresh()
    }
    func applicationDidResignActive(_ notification: Notification) { settingsWindow?.cancelRecording() }
    func menuWillOpen(_ menu: NSMenu) { syncControls() }
    private func item(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let value = NSMenuItem(title: title, action: selector, keyEquivalent: key); value.target = self; return value
    }
    @objc private func toggle() { setEnabled(!enabled || pausedUntil != nil) }
    private func setEnabled(_ value: Bool) {
        enabled = value; settings.enabled = value
        pauseTimer?.invalidate(); pauseTimer = nil; pausedUntil = nil
        applyEnabled()
        if enabled && !AXIsProcessTrusted() { showSettings() }
    }
    private func applyEnabled() {
        if enabled && pausedUntil == nil { tracker.start() }
        else { tracker.stop(); dimmer.hide(animated: true) }
        syncControls()
    }
    private func applyAppearance() {
        dimmer.fadeDuration = settings.effectiveFadeDuration(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        dimmer.fadeCurve = settings.fadeCurve
        dimmer.opacity = settings.intensity
    }
    @objc private func pauseFromMenu(_ sender: NSMenuItem) { pause(minutes: sender.tag) }
    @objc private func resume() { pause(minutes: nil) }
    private func pause(minutes: Int?) {
        pauseTimer?.invalidate(); pauseTimer = nil
        if let minutes, enabled {
            pausedUntil = Date().addingTimeInterval(Double(minutes) * 60)
            let timer = Timer(timeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in self?.pause(minutes: nil) }
            RunLoop.main.add(timer, forMode: .common); pauseTimer = timer
        } else { pausedUntil = nil }
        applyEnabled()
    }
    private func syncControls() {
        toggleItem?.state = enabled && pausedUntil == nil ? .on : .off
        pauseItem?.isEnabled = enabled && pausedUntil == nil
        resumeItem?.isHidden = pausedUntil == nil
        statusItem?.button?.toolTip = pausedUntil != nil ? "Hush · Paused" : enabled ? "Hush · Dimming on" : "Hush · Dimming off"
        settingsWindow?.updateState(enabled: enabled, pausedUntil: pausedUntil, trusted: AXIsProcessTrusted(), warnings: ShortcutAction.allCases.compactMap { shortcutWarnings[$0] })
    }
    private func makeHotkey(_ shortcut: KeyboardShortcut, action: ShortcutAction) -> GlobalHotkey {
        let hotkey = GlobalHotkey(shortcut: shortcut, id: action.identifier)
        hotkey.action = { [weak self] in
            switch action { case .toggle: self?.toggle(); case .enable: self?.setEnabled(true); case .disable: self?.setEnabled(false) }
        }
        return hotkey
    }
    private func registerShortcuts() {
        hotkeys.removeAll(); shortcutWarnings.removeAll()
        guard !recordingShortcut else { return }
        for action in ShortcutAction.allCases {
            guard let shortcut = settings.shortcut(for: action) else { continue }
            let hotkey = makeHotkey(shortcut, action: action)
            if hotkey.available { hotkeys[action] = hotkey }
            else { shortcutWarnings[action] = "\(action.title): \(shortcut.display) is unavailable. Choose another shortcut." }
        }
        syncControls()
    }
    private func changeShortcut(_ action: ShortcutAction, to shortcut: KeyboardShortcut?) -> String? {
        if let shortcut {
            guard shortcut.isValid else { return "Include Control, Option or Command with your key." }
            if ShortcutAction.allCases.contains(where: { $0 != action && settings.shortcut(for: $0).map(shortcut.matches) == true }) {
                return "That shortcut is assigned to another Hush action. Choose a different combination."
            }
            if let previous = settings.shortcut(for: action), previous.matches(shortcut), hotkeys[action]?.available == true { return nil }
            let replacement = makeHotkey(shortcut, action: action)
            guard replacement.available else { return "That shortcut is already in use. Your previous shortcut was kept." }
            settings.setShortcut(shortcut, for: action)
            if !recordingShortcut { hotkeys[action] = replacement }
        } else { settings.setShortcut(nil, for: action); hotkeys.removeValue(forKey: action) }
        shortcutWarnings.removeValue(forKey: action)
        syncControls()
        return nil
    }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController(settings: settings)
            controller.onEnabledChange = { [weak self] in self?.setEnabled($0) }
            controller.onPause = { [weak self] in self?.pause(minutes: $0) }
            controller.onChange = { [weak self] in self?.applyAppearance(); self?.tracker.refresh(); self?.syncControls() }
            controller.onShortcutChange = { [weak self] action, shortcut in self?.changeShortcut(action, to: shortcut) }
            controller.onRecordingChange = { [weak self] value in self?.recordingShortcut = value; self?.registerShortcuts() }
            controller.onRequestAccess = {
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            }
            controller.onClose = { [weak self] in self?.settingsWindow = nil }
            settingsWindow = controller
        }
        syncControls(); settingsWindow?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
