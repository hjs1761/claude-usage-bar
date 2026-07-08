import Foundation

/// 표시용 포맷 (모두 추정치).
public enum Fmt {
    public static func usd(_ v: Double) -> String {
        if v >= 100 { return String(format: "$%.0f", v) }
        if v >= 1   { return String(format: "$%.2f", v) }
        if v > 0    { return String(format: "$%.3f", v) }
        return "$0"
    }
    public static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000     { return String(format: "%.1fK", d / 1_000) }
        return "\(n)"
    }
    public static func shortDay(_ ymd: String) -> String {
        let parts = ymd.split(separator: "-")
        guard parts.count == 3 else { return ymd }
        return "\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)"
    }
    private static let ymdFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    public static func date(_ ymd: String) -> Date { ymdFmt.date(from: ymd) ?? Date(timeIntervalSince1970: 0) }
}
