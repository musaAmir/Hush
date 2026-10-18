import AppKit
import QuartzCore
import ServiceManagement
import UniformTypeIdentifiers
import HushCore
import Sparkle

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onEnabledChange: ((Bool) -> Void)?
    var onPause: ((Int?) -> Void)?
    var onChange: (() -> Void)?
    var onShortcutChange: ((ShortcutAction, KeyboardShortcut?) -> String?)?
    var onRecordingChange: ((Bool) -> Void)?
    var onRequestAccess: (() -> Void)?
    var onClose: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    private let settings: HushSettings
    private let updater: SPUUpdater
    private let tabs = NSTabView()
    private let navigation = NSTableView()
    private let sections: [(title: String, symbol: String, color: NSColor)] = [
        ("General", "gearshape.fill", .systemGray), ("Appearance", "circle.lefthalf.filled", .systemPink),
        ("Shortcuts", "command", .systemTeal), ("Exceptions", "app.badge.checkmark.fill", .systemIndigo)
    ]
    private let status = NSTextField(wrappingLabelWithString: "")
    private let permission = NSTextField(wrappingLabelWithString: "")
    private let shortcutMessage = NSTextField(wrappingLabelWithString: "")
    private let generalMessage = NSTextField(wrappingLabelWithString: "")
    private let enabledButton = NSSwitch()
    private let pauseButton = NSButton(title: "Pause", target: nil, action: nil)
    private let resumeButton = NSButton(title: "Resume", target: nil, action: nil)
    private let pauseLength = NSPopUpButton()
    private let duration = NSSlider(value: 0.5, minValue: 0.05, maxValue: 2, target: nil, action: nil)
    private let durationLabel = NSTextField(labelWithString: "")
    private let intensityLabel = NSTextField(labelWithString: "")
    private let curve = NSPopUpButton()
    private let preview = FadePreviewView(frame: CGRect(x: 0, y: 0, width: 540, height: 150))
    private var recorders: [ShortcutAction: ShortcutRecorder] = [:]
    private let exclusionList = SettingsListView()
    // Width of a row inside a card; cards add 14pt padding on each side.
    private let width: CGFloat = 512
    private static let cardColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.04)
    }

    init(settings: HushSettings, updater: SPUUpdater) {
        self.settings = settings; self.updater = updater
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Hush Settings"; window.isReleasedWhenClosed = false
        // An empty toolbar puts the page title beside the sidebar, as in System Settings.
        window.toolbar = NSToolbar(identifier: "HushSettings")
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 780, height: 480)
        super.init(window: window)
        window.delegate = self

        let sidebar = NSViewController(); sidebar.view = NSView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        navigation.addTableColumn(column); navigation.headerView = nil
        navigation.style = .sourceList; navigation.rowHeight = 32
        navigation.intercellSpacing = NSSize(width: 0, height: 2)
        navigation.backgroundColor = .clear
        navigation.allowsEmptySelection = false; navigation.allowsMultipleSelection = false
        navigation.focusRingType = .none; navigation.delegate = self; navigation.dataSource = self
        navigation.setAccessibilityLabel("Settings sections")
        let navigationScroll = NSScrollView()
        navigationScroll.drawsBackground = false; navigationScroll.documentView = navigation
        navigationScroll.automaticallyAdjustsContentInsets = false
        navigationScroll.translatesAutoresizingMaskIntoConstraints = false; sidebar.view.addSubview(navigationScroll)
        NSLayoutConstraint.activate([
            navigationScroll.topAnchor.constraint(equalTo: sidebar.view.safeAreaLayoutGuide.topAnchor, constant: 6),
            navigationScroll.leadingAnchor.constraint(equalTo: sidebar.view.leadingAnchor),
            navigationScroll.trailingAnchor.constraint(equalTo: sidebar.view.trailingAnchor),
            navigationScroll.bottomAnchor.constraint(equalTo: sidebar.view.bottomAnchor, constant: -12)
        ])

        tabs.tabViewType = .noTabsNoBorder
        let pages = [general(), appearance(), shortcuts(), exceptions()]
        for (index, content) in pages.enumerated() {
            let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
            let document = SettingsDocumentView()
            content.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(content)
            scroll.documentView = document
            NSLayoutConstraint.activate([
                document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                content.widthAnchor.constraint(equalToConstant: width + 28),
                content.centerXAnchor.constraint(equalTo: document.centerXAnchor),
                content.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
                content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
            ])
            let item = NSTabViewItem(identifier: index); item.view = scroll; tabs.addTabViewItem(item)
        }
        let detail = NSViewController(); detail.view = tabs
        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 200; sidebarItem.maximumThickness = 230
        sidebarItem.canCollapse = false
        split.addSplitViewItem(sidebarItem)
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.titlebarSeparatorStyle = .none
        split.addSplitViewItem(detailItem)
        window.contentViewController = split
        navigation.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        window.title = sections[max(navigation.selectedRow, 0)].title
        window.setContentSize(NSSize(width: 800, height: 640))
        window.center(); updateAppearance()
        // Pages taller than the window otherwise open scrolled under the toolbar.
        window.layoutIfNeeded()
        for case let scroll as NSScrollView in tabs.tabViewItems.compactMap(\.view) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateState(enabled: Bool, pausedUntil: Date?, trusted: Bool, warnings: [String]) {
        enabledButton.state = enabled ? .on : .off
        pauseButton.isEnabled = enabled && pausedUntil == nil
        resumeButton.isEnabled = pausedUntil != nil
        if let pausedUntil { status.stringValue = "Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))." }
        else { status.stringValue = enabled ? "Dimming is on. Switch to another app to focus its window." : "Dimming is off. Your settings are kept for next time." }
        permission.stringValue = trusted ? "Accessibility is enabled." : "Enable Accessibility to follow windows in other apps."
        if !warnings.isEmpty { showMessage(warnings.joined(separator: "\n"), in: shortcutMessage) }
        for (action, recorder) in recorders { recorder.shortcut = settings.shortcut(for: action) }
    }
    func cancelRecording() { recorders.values.forEach { $0.stop() } }
    func windowDidResignKey(_ notification: Notification) { cancelRecording() }
    func windowWillClose(_ notification: Notification) { cancelRecording(); onClose?() }
    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let badge = NSView(); badge.wantsLayer = true
        badge.layer?.backgroundColor = sections[row].color.cgColor
        badge.layer?.cornerRadius = 6; badge.layer?.cornerCurve = .continuous
        let image = symbol(sections[row].symbol, size: 12); image.contentTintColor = .white
        let text = NSTextField(labelWithString: sections[row].title)
        cell.textField = text
        [badge, image, text].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        badge.addSubview(image); cell.addSubview(badge); cell.addSubview(text)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 22), badge.heightAnchor.constraint(equalToConstant: 22),
            image.centerXAnchor.constraint(equalTo: badge.centerXAnchor), image.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8)
        ])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let index = navigation.selectedRow
        guard sections.indices.contains(index), tabs.numberOfTabViewItems > index else { return }
        cancelRecording(); tabs.selectTabViewItem(at: index); window?.title = sections[index].title
    }

    private func general() -> NSView {
        let stack = page()
        enabledButton.target = self; enabledButton.action = #selector(changeEnabled(_:))
        enabledButton.setAccessibilityLabel("Enable dimming")
        styleDetail(status)
        pauseLength.addItems(withTitles: ["5 minutes", "15 minutes", "1 hour"]); pauseLength.selectItem(at: 1)
        pauseLength.setAccessibilityLabel("Pause duration")
        pauseButton.target = self; pauseButton.action = #selector(pause)
        resumeButton.target = self; resumeButton.action = #selector(resume)
        stack.addArrangedSubview(group("Dimming", [row(label("Enable dimming"), enabledButton), row(label("Take a break"), pauseLength, pauseButton, resumeButton)], footer: [status]))

        let startup = NSPopUpButton(); startup.addItems(withTitles: ["Remember previous state", "Always enable dimming", "Start with dimming off"])
        startup.selectItem(at: StartupBehavior.allCases.firstIndex(of: settings.startup) ?? 0)
        startup.setAccessibilityLabel("Dimming at launch")
        startup.target = self; startup.action = #selector(changeStartup(_:))
        let login = NSSwitch(); login.target = self; login.action = #selector(changeLogin(_:))
        login.setAccessibilityLabel("Launch Hush at login")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        styleDetail(generalMessage)
        stack.addArrangedSubview(group("Startup", [row(label("Dimming at launch"), startup), row(label("Launch Hush at login"), login)], footer: [generalMessage]))
        showMessage("", in: generalMessage)

        styleDetail(permission)
        let access = row(label("Window access"), NSButton(title: "Enable Accessibility…", target: self, action: #selector(requestAccess)), NSButton(title: "Open System Settings", target: self, action: #selector(openAccess)))
        stack.addArrangedSubview(group("Accessibility", [access], footer: [permission, detail("Hush uses window events. It never records your screen or sends data anywhere.")]))

        let automatic = NSSwitch(); automatic.target = self; automatic.action = #selector(changeAutomaticUpdates(_:))
        automatic.state = updater.automaticallyChecksForUpdates ? .on : .off
        automatic.setAccessibilityLabel("Check for updates automatically")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        stack.addArrangedSubview(group("Updates", [
            row(label("Check for updates automatically"), automatic),
            row(label("Hush \(version)"), NSButton(title: "Check Now", target: self, action: #selector(checkForUpdates)))
        ], footer: [detail("Updates come from Hush releases on GitHub.")]))
        return stack
    }
    private func appearance() -> NSView {
        let stack = page()
        preview.widthAnchor.constraint(equalToConstant: width + 28).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 150).isActive = true
        stack.addArrangedSubview(preview)
        let intensity = NSSlider(value: settings.intensity, minValue: 0.05, maxValue: 0.85, target: self, action: #selector(changeIntensity(_:)))
        intensity.isContinuous = true; intensity.setAccessibilityLabel("Dimming intensity")
        intensity.widthAnchor.constraint(equalToConstant: 240).isActive = true
        valueLabel(intensityLabel)
        stack.addArrangedSubview(group("Background", [row(label("Dimming intensity"), intensity, intensityLabel)]))

        let fade = NSSwitch(); fade.target = self; fade.action = #selector(changeFade(_:))
        fade.state = settings.fadesEnabled ? .on : .off; fade.setAccessibilityLabel("Fade between windows")
        duration.target = self; duration.action = #selector(changeDuration(_:)); duration.isContinuous = true
        duration.doubleValue = settings.fadeDuration; duration.setAccessibilityLabel("Fade duration")
        duration.widthAnchor.constraint(equalToConstant: 240).isActive = true
        valueLabel(durationLabel)
        curve.addItems(withTitles: ["Smooth", "Linear"]); curve.selectItem(at: settings.fadeCurve == .smooth ? 0 : 1)
        curve.setAccessibilityLabel("Transition curve")
        curve.target = self; curve.action = #selector(changeCurve(_:))
        stack.addArrangedSubview(group("Transitions", [
            row(label("Fade between windows"), fade),
            row(label("Fade duration"), duration, durationLabel),
            row(label("Transition curve"), curve, NSButton(title: "Preview Fade", target: self, action: #selector(previewFade)))
        ], footer: [detail("Fades respect Reduce Motion. Moving a window always stays immediate.")]))
        return stack
    }
    private func shortcuts() -> NSView {
        let stack = page()
        var rows: [NSView] = []
        for action in ShortcutAction.allCases {
            let recorder = ShortcutRecorder(shortcut: settings.shortcut(for: action))
            recorder.onChange = { [weak self] value in self?.onShortcutChange?(action, value) }
            recorder.onMessage = { [weak self] value in
                guard let self else { return }
                self.showMessage(value, in: self.shortcutMessage)
            }
            recorder.onRecordingChange = { [weak self] value in self?.onRecordingChange?(value) }
            recorder.setAccessibilityLabel("\(action.title) shortcut")
            recorders[action] = recorder
            let clear = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(clearShortcut(_:)))
            clear.isBordered = false; clear.contentTintColor = .tertiaryLabelColor
            clear.tag = ShortcutAction.allCases.firstIndex(of: action) ?? 0
            clear.setAccessibilityLabel("Clear \(action.title.lowercased()) shortcut")
            rows.append(row(label(action.title), recorder, clear))
        }
        styleDetail(shortcutMessage); shortcutMessage.isHidden = true
        stack.addArrangedSubview(group("Keyboard Shortcuts", rows, footer: [detail("Click a shortcut to record. Include Control, Option or Command. Press Escape to cancel or Delete to clear."), shortcutMessage]))
        let restore = row(label("Default toggle (⌃⌥D)"), NSButton(title: "Restore", target: self, action: #selector(defaultShortcut)))
        stack.addArrangedSubview(group("Defaults", [restore], footer: [detail("If a combination is unavailable, your previous shortcut is kept. Menu bar controls are always available.")]))
        return stack
    }
    private func exceptions() -> NSView {
        let stack = page()
        exclusionList.orientation = .vertical; exclusionList.alignment = .leading; exclusionList.spacing = 10
        let add = NSButton(title: "Add App…", target: self, action: #selector(addExclusion))
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil); add.imagePosition = .imageLeading; add.setAccessibilityLabel("Add app to exceptions")
        stack.addArrangedSubview(group("Excluded Apps", [exclusionList], footer: [detail("Dimming pauses while an excluded app is active and resumes when you switch away.")]))
        let actions = NSStackView(); actions.setViews([add], in: .trailing)
        actions.widthAnchor.constraint(equalToConstant: width + 28).isActive = true
        stack.addArrangedSubview(actions)
        reloadExclusions()
        return stack
    }
    private func reloadExclusions() {
        exclusionList.arrangedSubviews.forEach { exclusionList.removeArrangedSubview($0); $0.removeFromSuperview() }
        let values = settings.exclusions
        if values.isEmpty {
            let empty = vertical(spacing: 6); empty.alignment = .centerX
            empty.edgeInsets = NSEdgeInsets(top: 18, left: 0, bottom: 18, right: 0)
            empty.widthAnchor.constraint(equalToConstant: width).isActive = true
            let icon = symbol("square.dashed", size: 24); icon.contentTintColor = .tertiaryLabelColor
            empty.addArrangedSubview(icon)
            empty.addArrangedSubview(label("No excluded apps", weight: .medium))
            empty.addArrangedSubview(detail("Dimming works in every app."))
            exclusionList.addArrangedSubview(empty)
        }
        for (index, app) in values.enumerated() {
            if index > 0 { exclusionList.addArrangedSubview(divider()) }
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeExclusion(_:))); remove.tag = index
            let name = vertical(spacing: 2); name.addArrangedSubview(label(app.name)); name.addArrangedSubview(detail(app.bundleID))
            remove.setAccessibilityLabel("Remove \(app.name) from exceptions")
            let icon = NSImageView()
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                icon.image = NSWorkspace.shared.icon(forFile: url.path)
            } else { icon.image = NSImage(systemSymbolName: "app", accessibilityDescription: nil) }
            icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 26).isActive = true
            name.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let line = NSStackView(views: [icon, name, remove]); line.spacing = 10; line.alignment = .centerY
            line.distribution = .fill
            line.widthAnchor.constraint(equalToConstant: width).isActive = true
            exclusionList.addArrangedSubview(line)
        }
    }

    @objc private func changeEnabled(_ sender: NSSwitch) { onEnabledChange?(sender.state == .on) }
    @objc private func pause() { onPause?([5, 15, 60][pauseLength.indexOfSelectedItem]) }
    @objc private func resume() { onPause?(nil) }
    @objc private func changeStartup(_ sender: NSPopUpButton) { settings.startup = StartupBehavior.allCases[sender.indexOfSelectedItem] }
    @objc private func changeIntensity(_ sender: NSSlider) { settings.intensity = sender.doubleValue; updateAppearance(); onChange?() }
    @objc private func changeFade(_ sender: NSSwitch) { settings.fadesEnabled = sender.state == .on; updateAppearance(); onChange?() }
    @objc private func changeDuration(_ sender: NSSlider) { settings.fadeDuration = sender.doubleValue; updateAppearance(); onChange?() }
    @objc private func changeCurve(_ sender: NSPopUpButton) { settings.fadeCurve = sender.indexOfSelectedItem == 0 ? .smooth : .linear; updateAppearance(); onChange?() }
    @objc private func previewFade() { preview.play(duration: settings.effectiveFadeDuration(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion), curve: settings.fadeCurve) }
    private func updateAppearance() {
        intensityLabel.stringValue = "\(Int((settings.intensity * 100).rounded()))%"
        durationLabel.stringValue = String(format: "%.2f s", settings.fadeDuration)
        duration.isEnabled = settings.fadesEnabled; curve.isEnabled = settings.fadesEnabled
        preview.intensity = settings.intensity
    }
    @objc private func changeAutomaticUpdates(_ sender: NSSwitch) { updater.automaticallyChecksForUpdates = sender.state == .on }
    @objc private func checkForUpdates() { onCheckForUpdates?() }
    @objc private func requestAccess() { onRequestAccess?() }
    @objc private func openAccess() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    @objc private func changeLogin(_ sender: NSSwitch) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            showMessage("", in: generalMessage)
        } catch { showMessage(error.localizedDescription, in: generalMessage) }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc private func clearShortcut(_ sender: NSButton) {
        cancelRecording()
        let action = ShortcutAction.allCases[sender.tag]
        showMessage(onShortcutChange?(action, nil) ?? "Shortcut cleared.", in: shortcutMessage)
        recorders[action]?.shortcut = settings.shortcut(for: action)
    }
    @objc private func defaultShortcut() {
        cancelRecording()
        showMessage(onShortcutChange?(.toggle, .defaultToggle) ?? "Default toggle restored.", in: shortcutMessage)
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
        let stack = NSStackView(); stack.alignment = .centerY; stack.spacing = 10
        stack.distribution = .fill
        for (index, view) in views.enumerated() {
            stack.addArrangedSubview(view)
            if index == 0 && views.count > 1 {
                let spacer = NSView()
                spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
                spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
                stack.addArrangedSubview(spacer)
            }
        }
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        return stack
    }
    private func showMessage(_ text: String, in field: NSTextField) {
        field.stringValue = text; field.isHidden = text.isEmpty
        // Collapse a footer whose only notes are empty messages.
        if let notes = field.superview as? NSStackView { notes.isHidden = notes.arrangedSubviews.allSatisfy(\.isHidden) }
    }
    private func page() -> NSStackView { vertical(spacing: 24) }
    // A bold heading, a rounded card of rows split by hairlines, then optional footnotes.
    private func group(_ title: String, _ rows: [NSView], footer: [NSView] = []) -> NSView {
        let section = vertical(spacing: 8)
        let heading = NSStackView(views: [label(title, weight: .semibold)])
        heading.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        section.addArrangedSubview(heading)
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
        box.fillColor = Self.cardColor; box.borderWidth = 0
        box.cornerRadius = 10; box.contentViewMargins = .zero
        let contents = vertical(spacing: 10)
        for (index, view) in rows.enumerated() {
            if index > 0 { contents.addArrangedSubview(divider()) }
            contents.addArrangedSubview(view)
        }
        contents.translatesAutoresizingMaskIntoConstraints = false
        let interior = box.contentView!; interior.addSubview(contents)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: width + 28),
            contents.widthAnchor.constraint(equalToConstant: width),
            contents.leadingAnchor.constraint(equalTo: interior.leadingAnchor, constant: 14),
            contents.trailingAnchor.constraint(equalTo: interior.trailingAnchor, constant: -14),
            contents.topAnchor.constraint(equalTo: interior.topAnchor, constant: 10),
            contents.bottomAnchor.constraint(equalTo: interior.bottomAnchor, constant: -10)
        ])
        section.addArrangedSubview(box)
        if !footer.isEmpty {
            let notes = vertical(spacing: 4)
            notes.edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 0, right: 10)
            footer.forEach { notes.addArrangedSubview($0) }
            section.addArrangedSubview(notes)
        }
        return section
    }
    private func divider() -> NSView {
        let line = NSBox(); line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: width).isActive = true
        return line
    }
    private func symbol(_ name: String, size: CGFloat) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
        view.symbolConfiguration = .init(pointSize: size, weight: .medium)
        view.contentTintColor = .controlAccentColor
        view.setAccessibilityElement(false)
        return view
    }
    private func valueLabel(_ field: NSTextField) {
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular); field.textColor = .secondaryLabelColor
        field.alignment = .right; field.widthAnchor.constraint(equalToConstant: 48).isActive = true
    }
    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: size, weight: weight); return label
    }
    private func detail(_ text: String) -> NSTextField { let label = NSTextField(wrappingLabelWithString: text); styleDetail(label); return label }
    private func styleDetail(_ label: NSTextField) { label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor; label.preferredMaxLayoutWidth = width + 8 }

}

extension ShortcutAction {
    var title: String { switch self { case .toggle: return "Toggle dimming"; case .enable: return "Enable dimming"; case .disable: return "Disable dimming" } }
    var identifier: UInt32 { switch self { case .toggle: return 1; case .enable: return 2; case .disable: return 3 } }
}

private final class SettingsListView: NSStackView {
    override var isFlipped: Bool { true }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); translatesAutoresizingMaskIntoConstraints = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
