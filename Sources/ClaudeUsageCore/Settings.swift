import Foundation

public enum DisplayMode: String, CaseIterable, Sendable {
    case rotate       // 5h ⇄ 1W 순환 (기본)
    case both         // 5h · 1W 한 줄
    case sessionOnly
    case weeklyOnly
    public var label: String {
        switch self {
        case .rotate: return "순환 (5h ⇄ 1W)"
        case .both: return "둘 다 (5h · 1W)"
        case .sessionOnly: return "5h만"
        case .weeklyOnly: return "1W만"
        }
    }
}

public final class SettingsStore: @unchecked Sendable {
    private let d: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.d = defaults }

    public var displayMode: DisplayMode {
        get { DisplayMode(rawValue: d.string(forKey: "displayMode") ?? "") ?? .rotate }
        set { d.set(newValue.rawValue, forKey: "displayMode") }
    }
    public var pollSeconds: Int {
        get { let v = d.integer(forKey: "pollSeconds"); return v == 0 ? 60 : v }
        set { d.set(newValue, forKey: "pollSeconds") }
    }
    public var chargingThrottle: Bool {
        get { d.bool(forKey: "chargingThrottle") }
        set { d.set(newValue, forKey: "chargingThrottle") }
    }
    public var accentHex: String? {
        get { d.string(forKey: "accentHex") }
        set { d.set(newValue, forKey: "accentHex") }
    }
}
