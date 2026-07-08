import Foundation
import SwiftUI
import ClaudeUsageCore

/// 사용량 대시보드 상태 + 드릴다운(연→월→일→시간). 데이터원은 `loader`로 주입
/// (개인용 앱=직접경로, TokenTally=security-scoped bookmark). 온보딩/샌드박스는 앱이 담당.
@MainActor
public final class DashboardModel: ObservableObject {
    struct Focus: Equatable { var year: Int?; var month: Int?; var day: Int? }
    enum Level { case years, months, days, hours }

    @Published var cost = UsageCost()
    @Published var entries: [UsageEntry] = []
    @Published var series: [SeriesPoint] = []
    @Published var modelSlices: [ModelSlice] = []
    @Published var projectRanking: [ProjectRow] = []
    @Published var focusedTotal = ModelBucket()
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published private(set) var oldestDayKey: String?
    @Published private(set) var focus = Focus()

    /// 표시용 폴더 경로 (앱이 세팅). 푸터에 표시.
    @Published public var folderPath: String?

    private let loader: () -> DashboardData?
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c }
    private var thisYear: Int { cal.component(.year, from: Date()) }

    /// - loader: 백그라운드에서 호출되어 집계 결과를 반환 (nil=접근 실패).
    public init(folderPath: String? = nil, loader: @escaping () -> DashboardData?) {
        self.folderPath = folderPath
        self.loader = loader
        let now = Date(); let c = Calendar(identifier: .gregorian)
        focus = Focus(year: c.component(.year, from: now), month: c.component(.month, from: now), day: nil)
    }

    public var isEmpty: Bool { cost.month.cost == 0 && entries.isEmpty }

    public func reload() {
        guard !isLoading else { return }
        isLoading = true
        let load = loader
        Task.detached(priority: .userInitiated) {
            let result = load()
            await MainActor.run {
                if let r = result {
                    self.cost = r.cost
                    self.entries = r.entries
                    self.oldestDayKey = r.entries.map(\.dayKey).min()
                }
                self.lastUpdated = Date()
                self.isLoading = false
                self.refreshSeries()
            }
        }
    }

    // MARK: 레벨 / 시리즈
    var level: Level {
        if focus.day != nil { return .hours }
        if focus.month != nil { return .days }
        if focus.year != nil { return .months }
        return .years
    }
    var chartUnit: Calendar.Component {
        switch level { case .years: .year; case .months: .month; case .days: .day; case .hours: .hour }
    }
    var canDrillDown: Bool { level != .hours }

    func refreshSeries() {
        let y = focus.year ?? thisYear, m = focus.month ?? 1, d = focus.day ?? 1
        let fe: [UsageEntry]
        switch level {
        case .years:
            series = CostRollup.yearlySeries(entries: entries); fe = entries
        case .months:
            series = CostRollup.monthlySeries(entries: entries, year: y)
            fe = entries.filter { $0.dayKey.hasPrefix(String(format: "%04d-", y)) }
        case .days:
            series = CostRollup.dailySeriesOfMonth(entries: entries, year: y, month: m)
            fe = entries.filter { $0.dayKey.hasPrefix(String(format: "%04d-%02d", y, m)) }
        case .hours:
            series = CostRollup.hourlySeries(entries: entries, year: y, month: m, day: d)
            fe = entries.filter { $0.dayKey == String(format: "%04d-%02d-%02d", y, m, d) }
        }
        focusedTotal = CostRollup.total(fe)
        modelSlices = CostRollup.totalsByModel(fe)
            .map { ModelSlice(name: $0.key.displayName, cost: $0.value.cost) }
            .filter { $0.cost > 0 }.sorted { $0.cost > $1.cost }
        projectRanking = CostRollup.totalsByProject(fe)
            .map { ProjectRow(raw: $0.key, name: ProjectPath.friendly($0.key), cost: $0.value.cost) }
            .filter { $0.cost > 0 }.sorted { $0.cost > $1.cost }.prefix(12).map { $0 }
    }

    // MARK: 드릴 / 브레드크럼 / 형제이동
    func drill(_ p: SeriesPoint) {
        guard canDrillDown else { return }
        switch level {
        case .years:  if let v = Int(p.label) { focus = Focus(year: v) }
        case .months: if let v = Int(p.label.suffix(2)) { focus.month = v; focus.day = nil }
        case .days:   if let v = Int(p.label.suffix(2)) { focus.day = v }
        case .hours:  break
        }
        refreshSeries()
    }
    func point(label: String) -> SeriesPoint? { series.first { $0.label == label } }

    /// 축에 표시할 라벨(과밀 방지, ~7개로 솎음). 카테고리 x축용.
    var axisTickLabels: [String] {
        let labels = series.map(\.label)
        guard labels.count > 8 else { return labels }
        let step = Int((Double(labels.count) / 7).rounded(.up))
        return labels.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
    }
    /// 라벨 → 축 표시 문자열 (연=2026, 월=7월, 일=15, 시=9시).
    func axisLabel(_ label: String) -> String {
        switch level {
        case .years:  return label
        case .months: return "\(Int(label.suffix(2)) ?? 0)월"
        case .days:   return "\(Int(label.suffix(2)) ?? 0)"
        case .hours:  return "\(Int(label) ?? 0)시"
        }
    }

    struct Crumb: Identifiable { let id: Int; let label: String }
    var breadcrumbs: [Crumb] {
        var out = [Crumb(id: 0, label: "전체")]
        if let y = focus.year  { out.append(Crumb(id: 1, label: "\(y)")) }
        if let m = focus.month { out.append(Crumb(id: 2, label: "\(m)월")) }
        if let d = focus.day   { out.append(Crumb(id: 3, label: "\(d)일")) }
        return out
    }
    func popTo(depth: Int) {
        focus.year  = depth >= 1 ? focus.year  : nil
        focus.month = depth >= 2 ? focus.month : nil
        focus.day   = depth >= 3 ? focus.day   : nil
        refreshSeries()
    }

    private var monthDate: Date? {
        guard let y = focus.year, let m = focus.month else { return nil }
        return cal.date(from: DateComponents(year: y, month: m, day: 1))
    }
    private var dayDate: Date? {
        guard let y = focus.year, let m = focus.month, let d = focus.day else { return nil }
        return cal.date(from: DateComponents(year: y, month: m, day: d))
    }
    var canLateralForward: Bool {
        let c = cal, now = Date()
        switch level {
        case .years:  return false
        case .months: return (focus.year ?? 0) < c.component(.year, from: now)
        case .days:
            guard let md = monthDate else { return false }
            return md < c.date(from: c.dateComponents([.year, .month], from: now))!
        case .hours:
            guard let dd = dayDate else { return false }
            return dd < c.startOfDay(for: now)
        }
    }
    var canLateralBack: Bool { level != .years }
    func lateral(_ delta: Int) {
        let c = cal
        switch level {
        case .years: return
        case .months: if let y = focus.year { focus.year = y + delta }
        case .days:
            if let base = monthDate, let nd = c.date(byAdding: .month, value: delta, to: base) {
                focus.year = c.component(.year, from: nd); focus.month = c.component(.month, from: nd)
            }
        case .hours:
            if let base = dayDate, let nd = c.date(byAdding: .day, value: delta, to: base) {
                focus.year = c.component(.year, from: nd)
                focus.month = c.component(.month, from: nd)
                focus.day = c.component(.day, from: nd)
            }
        }
        refreshSeries()
    }

    // MARK: 표시 보조
    var rangeTitle: String {
        switch level {
        case .years:  return "전체 연도"
        case .months: return "\(focus.year ?? thisYear)년"
        case .days:   return "\(focus.year ?? thisYear)년 \(focus.month ?? 0)월"
        case .hours:  return "\(focus.month ?? 0)월 \(focus.day ?? 0)일 (시간대)"
        }
    }
    var periodShort: String {
        switch level {
        case .years:  return "전체"
        case .months: return "\(focus.year ?? thisYear)년"
        case .days:
            let c = cal, now = Date()
            if focus.year == c.component(.year, from: now), focus.month == c.component(.month, from: now) {
                return "이번 달"
            }
            return "\(focus.year ?? thisYear)년 \(focus.month ?? 0)월"
        case .hours:  return "\(focus.month ?? 0)/\(focus.day ?? 0)"
        }
    }
    var avgLabel: String {
        switch level { case .years: "연평균"; case .months: "월평균"; case .days: "일평균"; case .hours: "시간평균" }
    }
    var seriesTotal: Double { series.reduce(0) { $0 + $1.cost } }
    var seriesAvg: Double {
        let n = series.filter { $0.cost > 0 }.count
        return n > 0 ? seriesTotal / Double(n) : 0
    }
    func pointLabel(_ p: SeriesPoint) -> String {
        switch level {
        case .years:  return p.label
        case .months: return "\(Int(p.label.suffix(2)) ?? 0)월"
        case .days:   return "\(Int(p.label.suffix(2)) ?? 0)일"
        case .hours:  return "\(Int(p.label) ?? 0)시"
        }
    }
    var cacheRatio: Double {
        let b = focusedTotal
        return b.tokens > 0 ? Double(b.cacheRead + b.cacheWrite) / Double(b.tokens) : 0
    }

    func detail(for rawKey: String) -> ProjectDetail {
        let sub = entries.filter { $0.project == rawKey }
        let now = Date()
        return ProjectDetail(
            raw: rawKey, name: ProjectPath.friendly(rawKey),
            cost: CostRollup.rollup(entries: sub, now: now),
            daily: CostRollup.dailySeries(entries: sub, days: 30, endingAt: now)
        )
    }
}

// MARK: - 파생 데이터 (모듈 내부)

struct ModelSlice: Identifiable { let id = UUID(); let name: String; let cost: Double }
struct ProjectRow: Identifiable { let id = UUID(); let raw: String; let name: String; let cost: Double }
struct ProjectDetail { let raw: String; let name: String; let cost: UsageCost; let daily: [SeriesPoint] }
