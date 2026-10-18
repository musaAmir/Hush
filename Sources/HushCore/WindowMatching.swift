import CoreGraphics

public struct FocusedWindow: Equatable {
    public let number: Int
    public let level: Int
    public init(number: Int, level: Int) { self.number = number; self.level = level }
}

public struct WindowCandidate {
    public let window: FocusedWindow
    public let ownerPID: Int32
    public let frame: CGRect
    public let alpha: Double
    public init(number: Int, level: Int, ownerPID: Int32, frame: CGRect, alpha: Double = 1) {
        self.window = FocusedWindow(number: number, level: level)
        self.ownerPID = ownerPID; self.frame = frame; self.alpha = alpha
    }
}

public enum WindowMatching {
    // AX and Window Server bounds both use top-left display coordinates. No
    // Retina scaling or primary-display transform is needed to identify a window.
    public static func focusedWindow(ownerPID: Int32, frame: CGRect, candidates: [WindowCandidate]) -> FocusedWindow? {
        guard valid(frame) else { return nil }
        return candidates.first { candidate in
            candidate.ownerPID == ownerPID && candidate.window.number > 0 &&
            candidate.window.level >= 0 && candidate.window.level < 24 &&
            candidate.alpha > 0 && valid(candidate.frame) &&
            abs(candidate.frame.minX - frame.minX) <= 2 && abs(candidate.frame.minY - frame.minY) <= 2 &&
            abs(candidate.frame.width - frame.width) <= 2 && abs(candidate.frame.height - frame.height) <= 2
        }?.window
    }
    private static func valid(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
}
