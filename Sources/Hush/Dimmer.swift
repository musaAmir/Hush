import AppKit
import QuartzCore
import HushCore

final class DimmerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Dimmer {
    private var panels: [DimmerPanel] = []
    private var veil: DimmerPanel?
    private var focusedWindow: FocusedWindow?
    private var transitionID = 0
    var fadeDuration: Double = 0 {
        didSet {
            if fadeDuration <= 0 {
                if focusedWindow == nil { hide() }
                else if let focusedWindow {
                    transitionID += 1; veil?.orderOut(nil); place(below: focusedWindow)
                    animate(to: Float(FocusGeometry.opacity(opacity)), duration: 0)
                }
            }
        }
    }
    var fadeCurve: FadeCurve = .smooth
    var opacity: Double = 0.45 {
        didSet {
            guard focusedWindow != nil else { return }
            transitionID += 1
            animate(to: Float(FocusGeometry.opacity(opacity)), duration: min(fadeDuration, 0.15))
        }
    }

    func hide(animated: Bool = false) {
        transitionID += 1
        let token = transitionID
        focusedWindow = nil
        veil?.orderOut(nil)
        guard animated, fadeDuration > 0, panels.contains(where: \.isVisible) else {
            animate(to: 0, duration: 0)
            panels.forEach { $0.orderOut(nil) }
            return
        }
        animate(to: 0, duration: fadeDuration) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.transitionID == token, self.focusedWindow == nil else { return }
                self.panels.forEach { $0.orderOut(nil) }
            }
        }
    }

    func show(window: FocusedWindow?) {
        guard let window, window.number > 0, window.level >= 0, window.level < 24 else { hide(animated: true); return }
        let screens = NSScreen.screens
        let screensChanged = panels.count != screens.count || zip(panels, screens).contains { $0.frame != $1.frame }
        if screensChanged {
            panels.forEach { $0.close() }
            panels = screens.map { makePanel(frame: $0.frame) }
        }
        guard screensChanged || focusedWindow != window || panels.contains(where: { !$0.isVisible }) else { return }
        transitionID += 1
        let token = transitionID
        let target = Float(FocusGeometry.opacity(opacity))
        let previous = focusedWindow
        let settled = !screensChanged && previous != nil && panels.allSatisfy(\.isVisible)
        focusedWindow = window
        veil?.orderOut(nil)
        // Windows already behind the shade stay dimmed. Only the window losing focus
        // fades down, under a veil of its own; then the shade moves behind the new window.
        if settled, let previous, fadeDuration > 0, let frame = Self.frame(of: previous) {
            place(below: previous)
            let veil = self.veil ?? makePanel(frame: frame, cornerRadius: 10)
            self.veil = veil
            veil.setFrame(frame, display: false)
            veil.level = NSWindow.Level(rawValue: previous.level)
            veil.order(.above, relativeTo: previous.number)
            animate(to: 0, duration: 0, layers: [veil])
            animate(to: target, duration: fadeDuration, layers: [veil]) { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.transitionID == token else { return }
                    self.place(below: window); veil.orderOut(nil)
                }
            }
            return
        }
        // Reset only when the shade first appears, never during window movement or resizing.
        // The real window stays above the shade throughout the fade.
        if !settled { animate(to: 0, duration: 0) }
        place(below: window)
        if !settled { animate(to: target, duration: fadeDuration) }
    }

    private func place(below window: FocusedWindow) {
        for panel in panels {
            panel.level = NSWindow.Level(rawValue: window.level)
            panel.order(.below, relativeTo: window.number)
        }
    }

    private func makePanel(frame: CGRect, cornerRadius: CGFloat = 0) -> DimmerPanel {
        let panel = DimmerPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.backgroundColor = .clear; panel.isOpaque = false
        panel.hasShadow = false; panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        let shade = NSView(frame: CGRect(origin: .zero, size: frame.size))
        shade.autoresizingMask = [.width, .height]
        shade.wantsLayer = true
        shade.layer?.backgroundColor = NSColor.black.cgColor
        shade.layer?.cornerRadius = cornerRadius; shade.layer?.cornerCurve = .continuous
        shade.layer?.opacity = 0
        panel.contentView = shade
        panel.setAccessibilityElement(false)
        return panel
    }

    // Window Server bounds (top-left origin) converted to AppKit screen coordinates.
    private static func frame(of window: FocusedWindow) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.number)) as? [[String: Any]])?.first,
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds),
              let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func animate(to value: Float, duration: Double, layers panels: [DimmerPanel]? = nil, completion: (() -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if duration > 0 { CATransaction.setCompletionBlock(completion) }
        for panel in panels ?? self.panels {
            guard let layer = panel.contentView?.layer else { continue }
            let current = layer.presentation()?.opacity ?? layer.opacity
            layer.removeAnimation(forKey: "hush.fade")
            layer.opacity = value
            if duration > 0 {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = current; animation.toValue = value
                animation.duration = duration
                animation.timingFunction = CAMediaTimingFunction(name: fadeCurve == .smooth ? .easeInEaseOut : .linear)
                layer.add(animation, forKey: "hush.fade")
            }
        }
        CATransaction.commit()
        if duration <= 0 { completion?() }
    }
}
