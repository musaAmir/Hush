import AppKit
import HushCore

final class DimmerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Dimmer {
    private var panels: [DimmerPanel] = []
    private var focusedWindow: FocusedWindow?
    var opacity: Double = 0.45 {
        didSet { panels.forEach { $0.alphaValue = FocusGeometry.opacity(opacity) } }
    }
    func hide() {
        panels.forEach { $0.orderOut(nil) }
        focusedWindow = nil
    }
    func show(window: FocusedWindow?) {
        guard let window, window.number > 0, window.level >= 0, window.level < 24 else { hide(); return }
        let screens = NSScreen.screens
        let screensChanged = panels.count != screens.count || zip(panels, screens).contains { $0.frame != $1.frame }
        if screensChanged {
            panels.forEach { $0.close() }
            panels = screens.map { screen in
                let panel = DimmerPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                panel.animationBehavior = .none
                panel.backgroundColor = .black; panel.isOpaque = true
                panel.alphaValue = FocusGeometry.opacity(opacity)
                panel.hasShadow = false; panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.setAccessibilityElement(false)
                return panel
            }
        }
        guard screensChanged || focusedWindow != window || panels.contains(where: { !$0.isVisible }) else { return }
        for panel in panels {
            panel.level = NSWindow.Level(rawValue: window.level)
            // The real window is above the shade. Its native corners, transparency
            // and drag position are composited by macOS without a moving cutout.
            panel.order(.below, relativeTo: window.number)
        }
        focusedWindow = window
    }
}
