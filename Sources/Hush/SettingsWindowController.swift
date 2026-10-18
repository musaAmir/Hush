import AppKit
import QuartzCore
import ServiceManagement
import UniformTypeIdentifiers
import HushCore

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onEnabledChange: ((Bool) -> Void)?
    var onPause: ((Int?) -> Void)?
    var onChange: (() -> Void)?
    var onShortcutChange: ((ShortcutAction, KeyboardShortcut?) -> String?)?
    var onRecordingChange: ((Bool) -> Void)?
    var onRequestAccess: (() -> Void)?
    var onClose: (() -> Void)?
    private let settings: HushSettings
    private let tabs = NSTabView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let permission = NSTextField(wrappingLabelWithString: "")
    private let shortcutMessage = NSTextField(wrappingLabelWithString: "")
    private let generalMessage = NSTextField(wrappingLabelWithString: "")
    private let enabledButton = NSButton(checkboxWithTitle: "Enable dimming", target: nil, action: nil)
    private let pauseButton = NSButton(title: "Pause", target: nil, action: nil)
    private let resumeButton = NSButton(title: "Resume", target: nil, action: nil)
    private let pauseLength = NSPopUpButton()
    private let duration = NSSlider(value: 0.5, minValue: 0.05, maxValue: 2, target: nil, action: nil)
    private let durationLabel = NSTextField(labelWithString: "")
    private let intensityLabel = NSTextField(labelWithString: "")
    private let curve = NSPopUpButton()
    private let preview = FadePreviewView(frame: CGRect(x: 0, y: 0, width: 520, height: 150))
    private var recorders: [ShortcutAction: ShortcutRecorder] = [:]
    private let exclusionList = NSStackView()
    private let width: CGFloat = 520

    init(settings: HushSettings) {
        self.settings = settings
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 576, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Hush Settings"; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let content = vertical(spacing: 18)
        let title = label("Hush", size: 28, weight: .semibold)
        content.addArrangedSubview(title)
        content.addArrangedSubview(detail("A quieter backdrop. Your way."))
        let navigation = NSSegmentedControl(labels: ["General", "Appearance", "Shortcuts", "Exceptions"], trackingMode: .selectOne, target: self, action: #selector(selectTab(_:)))
        navigation.selectedSegment = 0
        navigation.widthAnchor.constraint(equalToConstant: width).isActive = true
        content.addArrangedSubview(navigation)
        tabs.tabViewType = .noTabsNoBorder
        let views = [general(), appearance(), shortcuts(), exceptions()]
        for (index, view) in views.enumerated() {
            let page = NSView(); view.translatesAutoresizingMaskIntoConstraints = false; page.addSubview(view)
            NSLayoutConstraint.activate([view.topAnchor.constraint(equalTo: page.topAnchor), view.leadingAnchor.constraint(equalTo: page.leadingAnchor), view.trailingAnchor.constraint(equalTo: page.trailingAnchor)])
            let item = NSTabViewItem(identifier: index); item.view = page; tabs.addTabViewItem(item)
        }
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.widthAnchor.constraint(equalToConstant: width).isActive = true
        tabs.heightAnchor.constraint(equalToConstant: 480).isActive = true
        content.addArrangedSubview(tabs)
        let container = NSView(); content.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28), content.topAnchor.constraint(equalTo: container.topAnchor, constant: 24), content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28)])
        window.contentView = container; window.center()
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateState(enabled: Bool, pausedUntil: Date?, trusted: Bool, warnings: [String]) {
        enabledButton.state = enabled ? .on : .off
        pauseButton.isEnabled = enabled && pausedUntil == nil
        resumeButton.isEnabled = pausedUntil != nil
        if let pausedUntil { status.stringValue = "Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))." }
        else { status.stringValue = enabled ? "Dimming is on. Switch to another app to focus its window." : "Dimming is off. Your settings are kept for next time." }
        permission.stringValue = trusted ? "Accessibility is enabled." : "Enable Accessibility to follow windows in other apps."
        if !warnings.isEmpty { shortcutMessage.stringValue = warnings.joined(separator: "\n") }
        for (action, recorder) in recorders { recorder.shortcut = settings.shortcut(for: action) }
    }
    func cancelRecording() { recorders.values.forEach { $0.stop() } }
    func windowDidResignKey(_ notification: Notification) { cancelRecording() }
    func windowWillClose(_ notification: Notification) { cancelRecording(); onClose?() }
    @objc private func selectTab(_ sender: NSSegmentedControl) { cancelRecording(); tabs.selectTabViewItem(at: sender.selectedSegment) }

    private func general() -> NSView {
        let stack = vertical(spacing: 16)
        stack.addArrangedSubview(heading("Dimming"))
        enabledButton.target = self; enabledButton.action = #selector(changeEnabled(_:)); stack.addArrangedSubview(enabledButton)
        styleDetail(status); stack.addArrangedSubview(status)
        pauseLength.addItems(withTitles: ["5 minutes", "15 minutes", "1 hour"]); pauseLength.selectItem(at: 1)
        pauseButton.target = self; pauseButton.action = #selector(pause)
        resumeButton.target = self; resumeButton.action = #selector(resume)
        stack.addArrangedSubview(row(pauseLength, pauseButton, resumeButton))
        stack.addArrangedSubview(heading("On startup"))
        let startup = NSPopUpButton(); startup.addItems(withTitles: ["Remember previous state", "Always enable dimming", "Start with dimming off"])
        startup.selectItem(at: StartupBehavior.allCases.firstIndex(of: settings.startup) ?? 0)
        startup.target = self; startup.action = #selector(changeStartup(_:))
        stack.addArrangedSubview(row(label("Dimming at launch"), startup))
        let login = NSButton(checkboxWithTitle: "Launch Hush at login", target: self, action: #selector(changeLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off; stack.addArrangedSubview(login)
        styleDetail(generalMessage); stack.addArrangedSubview(generalMessage)
        stack.addArrangedSubview(heading("Access"))
        styleDetail(permission); stack.addArrangedSubview(permission)
        stack.addArrangedSubview(row(NSButton(title: "Enable Accessibility…", target: self, action: #selector(requestAccess)), NSButton(title: "Open System Settings", target: self, action: #selector(openAccess))))
        stack.addArrangedSubview(detail("Hush uses window events. It does not record your screen or send data anywhere."))
        return stack
    }
    private func appearance() -> NSView {
        let stack = vertical(spacing: 12)
        preview.widthAnchor.constraint(equalToConstant: width).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 140).isActive = true
        stack.addArrangedSubview(preview)
        let intensity = NSSlider(value: settings.intensity, minValue: 0.05, maxValue: 0.85, target: self, action: #selector(changeIntensity(_:)))
        intensity.isContinuous = true; intensity.setAccessibilityLabel("Dimming intensity")
        intensity.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(row(label("Dimming intensity", weight: .medium), intensityLabel))
        stack.addArrangedSubview(row(intensity))
        let fade = NSButton(checkboxWithTitle: "Fade when switching windows and toggling dimming", target: self, action: #selector(changeFade(_:)))
        fade.state = settings.fadesEnabled ? .on : .off; stack.addArrangedSubview(fade)
        duration.target = self; duration.action = #selector(changeDuration(_:)); duration.isContinuous = true
        duration.doubleValue = settings.fadeDuration; duration.setAccessibilityLabel("Fade duration")
        duration.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(row(label("Fade duration", weight: .medium), durationLabel))
        stack.addArrangedSubview(row(duration))
        curve.addItems(withTitles: ["Smooth", "Linear"]); curve.selectItem(at: settings.fadeCurve == .smooth ? 0 : 1)
        curve.target = self; curve.action = #selector(changeCurve(_:))
        stack.addArrangedSubview(row(label("Transition curve"), curve, NSButton(title: "Preview Fade", target: self, action: #selector(previewFade))))
        stack.addArrangedSubview(detail("Fades follow your Mac’s Reduce Motion setting. Window movement stays immediate."))
        return stack
    }
    private func shortcuts() -> NSView {
        let stack = vertical(spacing: 18)
        stack.addArrangedSubview(heading("Keyboard shortcuts"))
        stack.addArrangedSubview(detail("Click a shortcut to record a new combination. Include Control, Option or Command."))
        for action in ShortcutAction.allCases {
            let recorder = ShortcutRecorder(shortcut: settings.shortcut(for: action))
            recorder.onChange = { [weak self] value in self?.onShortcutChange?(action, value) }
            recorder.onMessage = { [weak self] value in self?.shortcutMessage.stringValue = value }
            recorder.onRecordingChange = { [weak self] value in self?.onRecordingChange?(value) }
            recorder.setAccessibilityLabel("\(action.title) shortcut")
            recorders[action] = recorder
            let clear = NSButton(title: "Clear", target: self, action: #selector(clearShortcut(_:))); clear.tag = ShortcutAction.allCases.firstIndex(of: action) ?? 0
            stack.addArrangedSubview(row(label(action.title), recorder, clear))
        }
        stack.addArrangedSubview(NSButton(title: "Use Default Toggle (⌃⌥D)", target: self, action: #selector(defaultShortcut)))
        styleDetail(shortcutMessage); stack.addArrangedSubview(shortcutMessage)
        stack.addArrangedSubview(detail("Escape cancels recording; Delete clears a shortcut. If a combination is unavailable, your previous shortcut is kept. The menu bar controls always work."))
        return stack
    }
    private func exceptions() -> NSView {
        let stack = vertical(spacing: 16)
        stack.addArrangedSubview(heading("Excluded apps"))
        stack.addArrangedSubview(detail("Pause dimming while these apps are active. Hush resumes automatically when you switch away."))
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: width).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 260).isActive = true
        exclusionList.orientation = .vertical; exclusionList.alignment = .leading; exclusionList.spacing = 12
        scroll.documentView = exclusionList
        stack.addArrangedSubview(scroll)
        stack.addArrangedSubview(NSButton(title: "Add App…", target: self, action: #selector(addExclusion)))
        reloadExclusions()
        return stack
    }
    private func reloadExclusions() {
        exclusionList.arrangedSubviews.forEach { exclusionList.removeArrangedSubview($0); $0.removeFromSuperview() }
        let values = settings.exclusions
        if values.isEmpty { exclusionList.addArrangedSubview(detail("No excluded apps.")) }
        for (index, app) in values.enumerated() {
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeExclusion(_:))); remove.tag = index
            let name = vertical(spacing: 3); name.addArrangedSubview(label(app.name, weight: .medium)); name.addArrangedSubview(detail(app.bundleID))
            let line = NSStackView(views: [name, remove]); line.spacing = 12; line.alignment = .centerY
            line.widthAnchor.constraint(equalToConstant: width - 28).isActive = true
            exclusionList.addArrangedSubview(line)
        }
        exclusionList.frame = CGRect(x: 12, y: 0, width: width - 24, height: max(40, CGFloat(values.count) * 58))
    }

    @objc private func changeEnabled(_ sender: NSButton) { onEnabledChange?(sender.state == .on) }
    @objc private func pause() { onPause?([5, 15, 60][pauseLength.indexOfSelectedItem]) }
    @objc private func resume() { onPause?(nil) }
    @objc private func changeStartup(_ sender: NSPopUpButton) { settings.startup = StartupBehavior.allCases[sender.indexOfSelectedItem] }
    @objc private func changeIntensity(_ sender: NSSlider) { settings.intensity = sender.doubleValue; updateAppearance(); onChange?() }
    @objc private func changeFade(_ sender: NSButton) { settings.fadesEnabled = sender.state == .on; updateAppearance(); onChange?() }
    @objc private func changeDuration(_ sender: NSSlider) { settings.fadeDuration = sender.doubleValue; updateAppearance(); onChange?() }
    @objc private func changeCurve(_ sender: NSPopUpButton) { settings.fadeCurve = sender.indexOfSelectedItem == 0 ? .smooth : .linear; updateAppearance(); onChange?() }
    @objc private func previewFade() { preview.play(duration: settings.effectiveFadeDuration(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion), curve: settings.fadeCurve) }
    private func updateAppearance() {
        intensityLabel.stringValue = "\(Int((settings.intensity * 100).rounded()))%"
        durationLabel.stringValue = String(format: "%.2f s", settings.fadeDuration)
        duration.isEnabled = settings.fadesEnabled; curve.isEnabled = settings.fadesEnabled
        preview.intensity = settings.intensity
    }
    @objc private func requestAccess() { onRequestAccess?() }
    @objc private func openAccess() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    @objc private func changeLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            generalMessage.stringValue = ""
        } catch { generalMessage.stringValue = error.localizedDescription }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc private func clearShortcut(_ sender: NSButton) {
        cancelRecording()
        let action = ShortcutAction.allCases[sender.tag]
        shortcutMessage.stringValue = onShortcutChange?(action, nil) ?? "Shortcut cleared."
        recorders[action]?.shortcut = settings.shortcut(for: action)
    }
    @objc private func defaultShortcut() {
        cancelRecording()
        shortcutMessage.stringValue = onShortcutChange?(.toggle, .defaultToggle) ?? "Default toggle restored."
        recorders[.toggle]?.shortcut = settings.shortcut(for: .toggle)
    }
    @objc private func addExclusion() {
        guard let window else { return }
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.applicationBundle]; picker.canChooseDirectories = false
        picker.canChooseFiles = true; picker.allowsMultipleSelection = true; picker.prompt = "Add Apps"
        picker.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK else { return }
            var values = self.settings.exclusions
            for url in picker.urls {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                values.append(ExcludedApplication(bundleID: id, name: name))
            }
            self.settings.exclusions = values; self.reloadExclusions(); self.onChange?()
        }
    }
    @objc private func removeExclusion(_ sender: NSButton) {
        var values = settings.exclusions
        guard values.indices.contains(sender.tag) else { return }
        values.remove(at: sender.tag); settings.exclusions = values; reloadExclusions(); onChange?()
    }

    private func vertical(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing; return stack
    }
    private func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views); stack.alignment = .centerY; stack.spacing = 12
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        if let first = views.first { first.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        return stack
    }
    private func heading(_ text: String) -> NSTextField { label(text, size: 15, weight: .semibold) }
    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: size, weight: weight); return label
    }
    private func detail(_ text: String) -> NSTextField { let label = NSTextField(wrappingLabelWithString: text); styleDetail(label); return label }
    private func styleDetail(_ label: NSTextField) { label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor; label.preferredMaxLayoutWidth = width }
}

extension ShortcutAction {
    var title: String { switch self { case .toggle: return "Toggle dimming"; case .enable: return "Enable dimming"; case .disable: return "Disable dimming" } }
    var identifier: UInt32 { switch self { case .toggle: return 1; case .enable: return 2; case .disable: return 3 } }
}

private final class FadePreviewView: NSView {
    var intensity: Double = 0.45 { didSet { setShade() } }
    private let shade = NSView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.backgroundColor = NSColor(calibratedRed: 0.84, green: 0.82, blue: 0.79, alpha: 1).cgColor
        layer?.cornerRadius = 14; layer?.masksToBounds = true
        let background = NSView(frame: CGRect(x: 28, y: 38, width: 235, height: 90))
        background.wantsLayer = true; background.layer?.backgroundColor = NSColor.white.cgColor; background.layer?.cornerRadius = 10
        addSubview(background)
        let backText = NSTextField(labelWithString: "Other windows"); backText.textColor = .darkGray; backText.frame = CGRect(x: 48, y: 92, width: 160, height: 18); addSubview(backText)
        shade.frame = bounds; shade.autoresizingMask = [.width, .height]; shade.wantsLayer = true; shade.layer?.backgroundColor = NSColor.black.cgColor; addSubview(shade)
        let front = NSView(frame: CGRect(x: 256, y: 18, width: 236, height: 110))
        front.wantsLayer = true; front.layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 1).cgColor; front.layer?.cornerRadius = 12
        addSubview(front)
        let text = NSTextField(labelWithString: "Room to focus."); text.font = .systemFont(ofSize: 15, weight: .medium); text.textColor = .darkGray; text.frame = CGRect(x: 28, y: 51, width: 180, height: 22); front.addSubview(text)
        setShade()
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("Dimming preview")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func setShade() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shade.layer?.removeAnimation(forKey: "preview.fade"); shade.layer?.opacity = Float(intensity)
        CATransaction.commit()
    }
    func play(duration: Double, curve: FadeCurve) {
        setShade()
        guard duration > 0 else { return }
        let animation = CABasicAnimation(keyPath: "opacity"); animation.fromValue = 0; animation.toValue = Float(intensity); animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: curve == .smooth ? .easeInEaseOut : .linear)
        shade.layer?.add(animation, forKey: "preview.fade")
    }
}
