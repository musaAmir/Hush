import AppKit
import QuartzCore
import HushCore

final class DimmerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Dimmer {
    private var panels: [DimmerPanel] = []
    private var focusedWindow: FocusedWindow?
    private var transitionID = 0
    var fadeDuration: Double = 0 {
        didSet {
            if fadeDuration <= 0 {
                if focusedWindow == nil { hide() }
                else { transitionID += 1; animate(to: Float(FocusGeometry.opacity(opacity)), duration: 0) }
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
            panels = screens.map { screen in
                let panel = DimmerPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                panel.animationBehavior = .none
                panel.backgroundColor = .clear; panel.isOpaque = false
                panel.hasShadow = false; panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                let shade = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
                shade.wantsLayer = true
                shade.layer?.backgroundColor = NSColor.black.cgColor
                shade.layer?.opacity = 0
                panel.contentView = shade
                panel.setAccessibilityElement(false)
                return panel
            }
        }
        guard screensChanged || focusedWindow != window || panels.contains(where: { !$0.isVisible }) else { return }
        transitionID += 1
        // Reset only on a focus change, never during window movement or resizing.
        // The real window stays above the shade throughout the fade.
        animate(to: 0, duration: 0)
        for panel in panels {
            panel.level = NSWindow.Level(rawValue: window.level)
            panel.order(.below, relativeTo: window.number)
        }
        focusedWindow = window
        animate(to: Float(FocusGeometry.opacity(opacity)), duration: fadeDuration)
    }

    private func animate(to value: Float, duration: Double, completion: (() -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if duration > 0 { CATransaction.setCompletionBlock(completion) }
        for panel in panels {
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
