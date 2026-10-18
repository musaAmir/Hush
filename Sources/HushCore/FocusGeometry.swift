import Foundation
import CoreGraphics

public enum FocusGeometry {
    public static func opacity(_ value: Double) -> Double {
        value.isFinite ? min(0.85, max(0.05, value)) : 0.45
    }
}
