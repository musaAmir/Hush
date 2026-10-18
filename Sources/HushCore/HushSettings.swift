import Foundation

public enum StartupBehavior: String, CaseIterable { case remember, enabled, disabled }
public enum FadeCurve: String, CaseIterable { case smooth, linear }
public enum ShortcutAction: String, CaseIterable { case toggle, enable, disable }

public struct KeyboardShortcut: Codable, Equatable {
    public static let shift: UInt32 = 1, control: UInt32 = 2, option: UInt32 = 4, command: UInt32 = 8
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let keyName: String
    public init(keyCode: UInt32, modifiers: UInt32, keyName: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyName = keyName
    }
    public var isValid: Bool {
        keyCode < 128 && !(54...63).contains(keyCode) && keyCode != 53 &&
        modifiers & ~UInt32(15) == 0 && modifiers & 14 != 0 && !keyName.isEmpty && keyName.count <= 12
    }
    public func matches(_ other: KeyboardShortcut) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    public var display: String {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + keyName
    }
    public static let defaultToggle = KeyboardShortcut(keyCode: 2, modifiers: control | option, keyName: "D")
}

public struct ExcludedApplication: Codable, Equatable {
    public let bundleID: String
    public let name: String
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
}

public final class HushSettings {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    public var startup: StartupBehavior {
        get { StartupBehavior(rawValue: defaults.string(forKey: "startupBehavior") ?? "") ?? .remember }
        set { defaults.set(newValue.rawValue, forKey: "startupBehavior") }
    }
    public var enabledAtLaunch: Bool {
        switch startup { case .remember: return enabled; case .enabled: return true; case .disabled: return false }
    }
    public var intensity: Double {
        get { FocusGeometry.opacity(defaults.object(forKey: "intensity") as? Double ?? 0.45) }
        set { defaults.set(FocusGeometry.opacity(newValue), forKey: "intensity") }
    }
    public var fadesEnabled: Bool {
        get { defaults.object(forKey: "fadesEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fadesEnabled") }
    }
    public var fadeDuration: Double {
        get { Self.duration(defaults.object(forKey: "fadeDuration") as? Double ?? 0.5) }
        set { defaults.set(Self.duration(newValue), forKey: "fadeDuration") }
    }
    public var fadeCurve: FadeCurve {
        get { FadeCurve(rawValue: defaults.string(forKey: "fadeCurve") ?? "") ?? .smooth }
        set { defaults.set(newValue.rawValue, forKey: "fadeCurve") }
    }
    public func effectiveFadeDuration(reduceMotion: Bool) -> Double { fadesEnabled && !reduceMotion ? fadeDuration : 0 }
    public func shortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        let key = "shortcut.\(action.rawValue)"
        guard defaults.object(forKey: key) != nil else { return action == .toggle ? .defaultToggle : nil }
        guard let data = defaults.data(forKey: key), let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data), shortcut.isValid else { return nil }
        return shortcut
    }
    public func setShortcut(_ shortcut: KeyboardShortcut?, for action: ShortcutAction) {
        guard let shortcut else { defaults.set(Data(), forKey: "shortcut.\(action.rawValue)"); return }
        guard shortcut.isValid, let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: "shortcut.\(action.rawValue)")
    }
    public var exclusions: [ExcludedApplication] {
        get {
            guard let data = defaults.data(forKey: "excludedApplications"), let values = try? JSONDecoder().decode([ExcludedApplication].self, from: data) else { return [] }
            return values.filter { !$0.bundleID.isEmpty }
        }
        set {
            var seen = Set<String>()
            let values = newValue.filter { !$0.bundleID.isEmpty && seen.insert($0.bundleID).inserted }
            if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: "excludedApplications") }
        }
    }
    public func isExcluded(_ bundleID: String?) -> Bool { bundleID.map { id in exclusions.contains { $0.bundleID == id } } ?? false }
    private static func duration(_ value: Double) -> Double { value.isFinite ? min(2, max(0.05, value)) : 0.5 }
}
