import Foundation

public enum CostRollup {
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public static func rollup(entries: [UsageEntry], now: Date) -> UsageCost {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2   // 월요일 시작
        let today = cal.startOfDay(for: now)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        let weekStart = cal.date(from: cal.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: today))!

        let tKey = dayFmt.string(from: today)
        let wKey = dayFmt.string(from: weekStart)
        let mKey = dayFmt.string(from: monthStart)

        var out = UsageCost()
        var seen = Set<String>()
        func add(_ b: inout ModelBucket, _ e: UsageEntry) {
            b.cost += e.cost; b.input += e.input; b.output += e.output
            b.cacheWrite += e.cacheWrite; b.cacheRead += e.cacheRead
        }
        for e in entries {
            if !seen.insert(e.dedupKey).inserted { continue }   // 전역 dedup
            if e.dayKey >= mKey {
                add(&out.month, e)
                var bm = out.byModel[e.category] ?? ModelBucket()
                add(&bm, e); out.byModel[e.category] = bm
            }
            if e.dayKey >= wKey { add(&out.week, e) }
            if e.dayKey >= tKey { add(&out.day, e) }
        }
        return out
    }
}
