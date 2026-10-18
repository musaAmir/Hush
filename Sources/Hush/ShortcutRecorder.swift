import AppKit
import Carbon
import HushCore

final class ShortcutRecorder: NSButton {
    var shortcut: KeyboardShortcut? { didSet { updateTitle() } }
    var onChange: ((KeyboardShortcut?) -> String?)?
    var onMessage: ((String) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private var monitor: Any?
    private static weak var active: ShortcutRecorder?

    init(shortcut: KeyboardShortcut?) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded; target = self; action = #selector(record)
        setAccessibilityLabel("Record keyboard shortcut")
        updateTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stop() }
        super.viewWillMove(toWindow: newWindow)
    }
    @objc private func record() {
        if monitor != nil { stop(); return }
        Self.active?.stop()
        Self.active = self
        onRecordingChange?(true)
        title = "Press shortcut…"
        onMessage?("Press a key with Control, Option or Command. Escape cancels; Delete clears.")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window, self.window?.isKeyWindow == true else { self.stop(); return event }
            if event.keyCode == UInt16(kVK_Escape) { self.stop(); self.onMessage?(""); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let clear = event.keyCode == UInt16(kVK_Delete) && flags.intersection([.control, .option, .command, .shift]).isEmpty
            var modifiers: UInt32 = 0
            for (flag, mask) in [(NSEvent.ModifierFlags.control, KeyboardShortcut.control), (.option, KeyboardShortcut.option),
                                 (.shift, KeyboardShortcut.shift), (.command, KeyboardShortcut.command)] {
                if flags.contains(flag) { modifiers |= mask }
            }
            let candidate = KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyName: Self.keyName(event))
            guard clear || candidate.isValid else {
                self.onMessage?("Include Control, Option or Command with your key."); NSSound.beep(); return nil
            }
            let error = self.onChange?(clear ? nil : candidate)
            if let error { self.onMessage?(error); NSSound.beep() }
            else { self.shortcut = clear ? nil : candidate; self.onMessage?(clear ? "Shortcut cleared." : "Shortcut saved.") }
            self.stop()
            return nil
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil; onRecordingChange?(false) }
        if Self.active === self { Self.active = nil }
        updateTitle()
    }
    private func updateTitle() { title = shortcut?.display ?? "Record Shortcut…" }
    private static func keyName(_ event: NSEvent) -> String {
        let names: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 76: "⌤", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        if let name = names[event.keyCode] { return name }
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = unsafeBitCast(raw, to: CFData.self)
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKey: UInt32 = 0, length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            if UCKeyTranslate(layout, event.keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                              OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKey, characters.count, &length, &characters) == noErr, length > 0 {
                return String(utf16CodeUnits: characters, count: length).uppercased()
            }
        }
        return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}
