import Foundation

public struct UsageData: Decodable, Sendable {
    public struct ModelScope: Decodable, Sendable {
        public struct Model: Decodable, Sendable {
            public let displayName: String?
            enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }
        public let model: Model?
    }
    public struct Limit: Decodable, Sendable {
        public let kind: String?
        public let percent: Double?
        public let resetsAt: String?
        public let severity: String?
        public let scope: ModelScope?
        enum CodingKeys: String, CodingKey {
            case kind, percent, severity, scope
            case resetsAt = "resets_at"
        }
    }
    public struct ExtraUsage: Decodable, Sendable {
        public let isEnabled: Bool?
        public let utilization: Double?
        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case utilization
        }
    }

    public let limits: [Limit]
    public let extraUsage: ExtraUsage?
    enum CodingKeys: String, CodingKey {
        case limits
        case extraUsage = "extra_usage"
    }

    public static func decode(_ data: Data) throws -> UsageData {
        try JSONDecoder().decode(UsageData.self, from: data)
    }

    public func limit(kind: String) -> Limit? { limits.first { $0.kind == kind } }
    public var sessionPercent: Double? { limit(kind: "session")?.percent }
    public var weeklyPercent: Double? { limit(kind: "weekly_all")?.percent }
}

public extension UsageData.Limit {
    /// resets_at 까지 남은 시간 "1d2h" / "3h04m" / "12m".
    func remaining(now: Date = Date()) -> String? {
        guard let iso = resetsAt, let d = ISODate.parse(iso) else { return nil }
        let secs = d.timeIntervalSince(now)
        if secs <= 0 { return "0m" }
        let day = Int(secs / 86400)
        let hh = Int(secs.truncatingRemainder(dividingBy: 86400) / 3600)
        let mm = Int(secs.truncatingRemainder(dividingBy: 3600) / 60)
        if day > 0 { return "\(day)d\(hh)h" }
        if hh > 0 { return String(format: "%dh%02dm", hh, mm) }
        return "\(mm)m"
    }
}
