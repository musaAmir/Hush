import AppKit
import HushCore

final class DimmerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ShadeView: NSView {
    var opacity = 0.45 { didSet { needsDisplay = true } }
    var cutout: CGRect? { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        if let cutout { path.append(NSBezierPath(roundedRect: cutout, xRadius: 8, yRadius: 8)) }
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(opacity).setFill()
        path.fill()
    }
}

final class Dimmer {
    private var panels: [DimmerPanel] = []
    var opacity: Double = 0.45 { didSet { panels.forEach { ($0.contentView as? ShadeView)?.opacity = opacity } } }
    func hide() { panels.forEach { $0.orderOut(nil) } }
    func show(window: CGRect?) {
        guard let window else { hide(); return }
        if panels.count != NSScreen.screens.count || zip(panels, NSScreen.screens).contains(where: { $0.frame != $1.frame }) {
            panels.forEach { $0.close() }
            panels = NSScreen.screens.map { screen in
                let panel = DimmerPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                panel.backgroundColor = .clear; panel.isOpaque = false
                panel.hasShadow = false; panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.contentView = ShadeView(frame: CGRect(origin: .zero, size: screen.frame.size))
                panel.setAccessibilityElement(false)
                return panel
            }
        }
        for panel in panels {
            guard let view = panel.contentView as? ShadeView else { continue }
            view.opacity = opacity
            view.cutout = FocusGeometry.cutout(window: window.insetBy(dx: -2, dy: -2), screen: panel.frame)
            panel.orderFrontRegardless()
        }
    }
}
