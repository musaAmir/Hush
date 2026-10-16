import AppKit
import ApplicationServices
import Carbon
import ServiceManagement
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let tracker = FocusTracker()
    private let dimmer = Dimmer()
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var hotkey: GlobalHotkey?
    private var preferences: NSWindow?
    private var permissionLabel: NSTextField?
    private var preview: PreviewView?
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
    private var intensity = FocusGeometry.opacity(UserDefaults.standard.object(forKey: "intensity") as? Double ?? 0.45)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "Hush"
        statusItem.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Hush")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "Hush · Focus dimmer"
        let menu = NSMenu(); menu.delegate = self
        toggleItem = NSMenuItem(title: "Enable Dimming", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self; menu.addItem(toggleItem)
        menu.addItem(.separator())
        for (title, selector) in [("Preferences…", #selector(showPreferences)), ("Quit Hush", #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: title.hasPrefix("Quit") ? "q" : ",")
            item.target = self; menu.addItem(item)
        }
        statusItem.menu = menu
        hotkey = GlobalHotkey(key: UInt32(kVK_ANSI_D), signature: 0x48555348)
        hotkey?.action = { [weak self] in self?.toggle() }
        tracker.onWindow = { [weak self] in self?.dimmer.show(window: $0) }
        tracker.onPermission = { [weak self] in self?.updatePermission($0) }
        dimmer.opacity = intensity
        applyEnabled()
        if !AXIsProcessTrusted() { showPreferences() }
    }
    func applicationWillTerminate(_ notification: Notification) { tracker.stop(); dimmer.hide(); hotkey = nil }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPreferences(); return false }
    func applicationDidBecomeActive(_ notification: Notification) { updatePermission(AXIsProcessTrusted()); tracker.refresh() }
    func menuWillOpen(_ menu: NSMenu) { toggleItem.state = enabled ? .on : .off; tracker.refresh() }
    @objc private func toggle() {
        enabled.toggle(); UserDefaults.standard.set(enabled, forKey: "enabled"); applyEnabled()
        if enabled && !AXIsProcessTrusted() { showPreferences() }
    }
    private func applyEnabled() {
        toggleItem?.state = enabled ? .on : .off
        if enabled { tracker.start() } else { tracker.stop() }
    }
    private func updatePermission(_ trusted: Bool) {
        permissionLabel?.stringValue = trusted ? "Accessibility enabled. Hush follows the active window." : "Enable Accessibility so Hush can follow the active window."
    }
    @objc private func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func changeIntensity(_ sender: NSSlider) {
        intensity = FocusGeometry.opacity(sender.doubleValue)
        dimmer.opacity = intensity; preview?.opacity = intensity
        UserDefaults.standard.set(intensity, forKey: "intensity")
    }
    @objc private func launchAtLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Couldn’t change Launch at Login"; alert.informativeText = error.localizedDescription; alert.runModal()
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc private func showPreferences() {
        if let preferences { preferences.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: size, weight: weight); return label
        }
        stack.addArrangedSubview(label("Hush", size: 28, weight: .semibold))
        let subtitle = label("A quieter backdrop for the window that matters.", size: 13); subtitle.textColor = .secondaryLabelColor; stack.addArrangedSubview(subtitle)
        let illustration = PreviewView(frame: .zero); illustration.opacity = intensity
        illustration.translatesAutoresizingMaskIntoConstraints = false; illustration.heightAnchor.constraint(equalToConstant: 160).isActive = true
        illustration.widthAnchor.constraint(equalToConstant: 360).isActive = true; stack.addArrangedSubview(illustration); preview = illustration
        stack.addArrangedSubview(label("Dimming intensity", size: 13, weight: .medium))
        let slider = NSSlider(value: intensity, minValue: 0.05, maxValue: 0.85, target: self, action: #selector(changeIntensity(_:)))
        slider.isContinuous = true; slider.setAccessibilityLabel("Dimming intensity"); slider.widthAnchor.constraint(equalToConstant: 360).isActive = true
        stack.addArrangedSubview(slider)
        let permission = label("", size: 12); permission.textColor = .secondaryLabelColor; stack.addArrangedSubview(permission); permissionLabel = permission
        let buttons = NSStackView(views: [NSButton(title: "Enable Accessibility…", target: self, action: #selector(requestPermission)), NSButton(title: "Open Settings", target: self, action: #selector(openAccessibility))]); buttons.spacing = 10; stack.addArrangedSubview(buttons)
        let login = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(launchAtLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off; stack.addArrangedSubview(login)
        let shortcut = hotkey?.available == true ? "⌃⌥D toggles dimming." : "⌃⌥D is in use by another app. Use the Hush menu to toggle."
        let detail = label(shortcut + "\nHush reacts to window events. It doesn’t capture your screen.", size: 11); detail.textColor = .secondaryLabelColor; stack.addArrangedSubview(detail)
        let container = NSView(); stack.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 26), stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -26), stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 26), stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -26)])
        let window = NSWindow(contentRect: CGRect(x: 0,y: 0,width: 412,height: 570), styleMask: [.titled,.closable], backing: .buffered, defer: false)
        window.title = "Hush"; window.contentView = container; window.isReleasedWhenClosed = false; window.delegate = self
        window.center(); preferences = window; updatePermission(AXIsProcessTrusted()); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        preferences = nil; permissionLabel = nil; preview = nil
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

final class PreviewView: NSView {
    var opacity = 0.45 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor(calibratedRed: 0.84, green: 0.82, blue: 0.79, alpha: 1).setFill(); background.fill()
        let back = CGRect(x: 25, y: 45, width: 180, height: 92)
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill(); NSBezierPath(roundedRect: back, xRadius: 7,yRadius: 7).fill()
        let front = CGRect(x: 140,y: 22,width: 195,height: 110)
        let shade = NSBezierPath(roundedRect: bounds, xRadius: 14,yRadius: 14); shade.append(NSBezierPath(roundedRect: front,xRadius: 7,yRadius: 7)); shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(opacity).setFill(); shade.fill()
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill(); NSBezierPath(roundedRect: front,xRadius: 7,yRadius: 7).fill()
        let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize: 13,weight:.medium),.foregroundColor:NSColor.darkGray]
        ("Room to focus." as NSString).draw(at: CGPoint(x: 165,y: 72),withAttributes: attrs)
        NSColor(calibratedWhite: 0.8,alpha: 1).setFill()
        for y in [55,44] { NSBezierPath(roundedRect: CGRect(x:165,y:y,width:120,height:3),xRadius:1.5,yRadius:1.5).fill() }
    }
}
