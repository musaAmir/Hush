import Foundation
import CoreGraphics

public enum FocusGeometry {
    public static func cocoaRect(fromAccessibility rect: CGRect, primaryHeight: CGFloat) -> CGRect? {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0 else { return nil }
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    public static func cutout(window: CGRect, screen: CGRect) -> CGRect? {
        let intersection = window.intersection(screen)
        guard !intersection.isNull, !intersection.isEmpty else { return nil }
        return intersection.offsetBy(dx: -screen.minX, dy: -screen.minY)
    }
    public static func opacity(_ value: Double) -> Double {
        value.isFinite ? min(0.85, max(0.05, value)) : 0.45
    }
}
