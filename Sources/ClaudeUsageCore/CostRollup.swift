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
                var bp = out.byProject[e.project] ?? ModelBucket()
                add(&bp, e); out.byProject[e.project] = bp
            }
            if e.dayKey >= wKey { add(&out.week, e) }
            if e.dayKey >= tKey { add(&out.day, e) }
        }
        return out
    }

    /// `days`일 일별 시계열(‥endingAt 포함, 오름차순). 빈 날 0채움 + 전역 dedup.
    /// endingAt을 과거로 옮기면 좌우 페이징이 된다.
    public static func dailySeries(entries: [UsageEntry], days: Int, endingAt: Date) -> [SeriesPoint] {
        guard days > 0 else { return [] }
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let end = cal.startOfDay(for: endingAt)

        var keys: [String] = []; var dates: [Date] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -offset, to: end)!
            keys.append(dayFmt.string(from: d)); dates.append(d)
        }
        let (costBy, tokBy) = bucket(entries) { Set(keys).contains($0.dayKey) ? $0.dayKey : nil }
        return zip(keys, dates).map { k, d in
            SeriesPoint(date: d, label: k, cost: costBy[k] ?? 0, tokens: tokBy[k] ?? 0)
        }
    }

    /// `year`의 1~12월 월별 시계열 (빈 달 0채움).
    public static func monthlySeries(entries: [UsageEntry], year: Int) -> [SeriesPoint] {
        let prefix = String(format: "%04d-", year)
        let (costBy, tokBy) = bucket(entries) {
            $0.dayKey.hasPrefix(prefix) ? String($0.dayKey.prefix(7)) : nil   // "yyyy-MM"
        }
        let cal = Calendar(identifier: .gregorian)
        return(1...12).map { m in
            let key = String(format: "%04d-%02d", year, m)
            let date = cal.date(from: DateComponents(year: year, month: m, day: 1))
                ?? Date(timeIntervalSince1970: 0)
            return SeriesPoint(date: date, label: key, cost: costBy[key] ?? 0, tokens: tokBy[key] ?? 0)
        }
    }

    /// 데이터가 존재하는 최소~최대 연도의 연별 시계열 (빈 해 0채움). 없으면 [].
    public static func yearlySeries(entries: [UsageEntry]) -> [SeriesPoint] {
        var minY = Int.max, maxY = Int.min
        var seen = Set<String>()
        for e in entries {
            if !seen.insert(e.dedupKey).inserted { continue }
            if let y = Int(e.dayKey.prefix(4)) { minY = min(minY, y); maxY = max(maxY, y) }
        }
        guard minY <= maxY else { return [] }
        let (costBy, tokBy) = bucket(entries) { String($0.dayKey.prefix(4)) }   // "yyyy"
        let cal = Calendar(identifier: .gregorian)
        return(minY...maxY).map { y in
            let key = String(format: "%04d", y)
            let date = cal.date(from: DateComponents(year: y, month: 1, day: 1))
                ?? Date(timeIntervalSince1970: 0)
            return SeriesPoint(date: date, label: key, cost: costBy[key] ?? 0, tokens: tokBy[key] ?? 0)
        }
    }

    /// `year`-`month`의 1일~말일 일별 시계열 (드릴다운: 월→일).
    public static func dailySeriesOfMonth(entries: [UsageEntry], year: Int, month: Int) -> [SeriesPoint] {
        let cal = Calendar(identifier: .gregorian)
        guard let monthDate = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = cal.range(of: .day, in: .month, for: monthDate) else { return [] }
        let prefix = String(format: "%04d-%02d", year, month)
        let (costBy, tokBy) = bucket(entries) { $0.dayKey.hasPrefix(prefix) ? $0.dayKey : nil }
        return range.map { d in
            let key = String(format: "%04d-%02d-%02d", year, month, d)
            let date = cal.date(from: DateComponents(year: year, month: month, day: d))
                ?? Date(timeIntervalSince1970: 0)
            return SeriesPoint(date: date, label: key, cost: costBy[key] ?? 0, tokens: tokBy[key] ?? 0)
        }
    }

    /// `year`-`month`-`day`의 0~23시 시간대별 시계열 (드릴다운: 일→시간).
    public static func hourlySeries(entries: [UsageEntry], year: Int, month: Int, day: Int) -> [SeriesPoint] {
        let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
        var costBy = [Int: Double](); var tokBy = [Int: Int]()
        var seen = Set<String>()
        for e in entries {
            if !seen.insert(e.dedupKey).inserted { continue }
            guard e.dayKey == dayKey else { continue }
            costBy[e.hour, default: 0] += e.cost
            tokBy[e.hour, default: 0] += e.tokens
        }
        let cal = Calendar(identifier: .gregorian)
        return (0..<24).map { h in
            let date = cal.date(from: DateComponents(year: year, month: month, day: day, hour: h))
                ?? Date(timeIntervalSince1970: 0)
            return SeriesPoint(date: date, label: String(format: "%02d", h),
                               cost: costBy[h] ?? 0, tokens: tokBy[h] ?? 0)
        }
    }

    // MARK: 임의 엔트리 집합 집계 (드릴다운한 기간의 모델별/프로젝트별/합계)

    /// 전역 dedup 후 `keyFor` 버킷별 ModelBucket 누적.
    public static func totals<K: Hashable>(_ entries: [UsageEntry],
                                           by keyFor: (UsageEntry) -> K?) -> [K: ModelBucket] {
        var out: [K: ModelBucket] = [:]
        var seen = Set<String>()
        for e in entries {
            guard seen.insert(e.dedupKey).inserted, let k = keyFor(e) else { continue }
            var b = out[k] ?? ModelBucket()
            b.cost += e.cost; b.input += e.input; b.output += e.output
            b.cacheWrite += e.cacheWrite; b.cacheRead += e.cacheRead
            out[k] = b
        }
        return out
    }
    public static func totalsByModel(_ e: [UsageEntry]) -> [ModelCategory: ModelBucket] { totals(e) { $0.category } }
    public static func totalsByProject(_ e: [UsageEntry]) -> [String: ModelBucket] { totals(e) { $0.project } }
    /// 전체 합계(단일 버킷).
    public static func total(_ entries: [UsageEntry]) -> ModelBucket {
        var b = ModelBucket(); var seen = Set<String>()
        for e in entries where seen.insert(e.dedupKey).inserted {
            b.cost += e.cost; b.input += e.input; b.output += e.output
            b.cacheWrite += e.cacheWrite; b.cacheRead += e.cacheRead
        }
        return b
    }

    /// 전역 dedup 후 `keyFor`가 주는 버킷키로 비용/토큰 합산. nil이면 제외.
    private static func bucket(_ entries: [UsageEntry],
                              _ keyFor: (UsageEntry) -> String?) -> ([String: Double], [String: Int]) {
        var cost: [String: Double] = [:]; var tok: [String: Int] = [:]
        var seen = Set<String>()
        for e in entries {
            if !seen.insert(e.dedupKey).inserted { continue }
            guard let k = keyFor(e) else { continue }
            cost[k, default: 0] += e.cost
            tok[k, default: 0] += e.tokens
        }
        return (cost, tok)
    }
}
