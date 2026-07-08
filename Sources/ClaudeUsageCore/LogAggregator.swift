import Foundation

/// 대시보드 1회 로드 결과: 요약(rollup) + 전체 원시 엔트리.
/// 일/월/연 시계열·프로젝트 드릴다운은 엔트리에서 그때그때 재집계.
public struct DashboardData: Sendable {
    public let cost: UsageCost
    public let entries: [UsageEntry]
    public init(cost: UsageCost, entries: [UsageEntry]) {
        self.cost = cost
        self.entries = entries
    }
}

public struct LogAggregator: Sendable {
    let projectsDir: URL
    let indexPath: URL

    public init(
        projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        indexPath: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar/log-index.json")
    ) {
        self.projectsDir = projectsDir
        self.indexPath = indexPath
    }

    struct FileEntry: Codable { var mtime: Double; var size: Int; var entries: [Cached] }
    // ⚠ project는 파일 "위치"에서 매번 재도출한다(캐시 저장 X). 폴더를 바꾸면 같은 파일이
    //   다른 projectsDir 기준으로 다르게 태깅되어야 하므로 캐시된 project를 신뢰하면 안 됨.
    struct Cached: Codable {
        var dayKey: String; var category: String
        var input: Int; var output: Int; var cacheWrite: Int; var cacheRead: Int
        var cost: Double; var dedupKey: String; var hour: Int
    }

    /// 월/주 요약만 (기존 개인용 앱 호환). cutoff = 월/주 시작 중 이른 것 - 1일.
    public func compute(now: Date = Date()) -> UsageCost {
        let cutoff = Self.rollupCutoffDate(now: now)
            .addingTimeInterval(-86400).timeIntervalSince1970
        return CostRollup.rollup(entries: loadEntries(cutoff: cutoff), now: now)
    }

    /// 요약(rollup) + 전체 원시 엔트리. 월/연 뷰·좌우 페이징 위해 전체 이력을 로드한다
    /// (mtime/size 인덱스 캐시로 변경분만 재파싱하므로 2회차부턴 저렴).
    public func computeDashboard(now: Date = Date()) -> DashboardData {
        let entries = loadEntries(cutoff: 0)
        return DashboardData(cost: CostRollup.rollup(entries: entries, now: now), entries: entries)
    }

    /// 월/주 rollup용 cutoff 기준일 (월시작·주시작 중 이른 것).
    private static func rollupCutoffDate(now: Date) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        let weekStart = cal.date(from: cal.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: today))!
        return min(monthStart, weekStart)
    }

    /// cutoff(파일 mtime 하한) 이후 파일만 파싱. mtime/size 인덱스 캐시로 변경분만 재파싱.
    /// project는 캐시 히트/미스 무관하게 현재 위치에서 재도출.
    private func loadEntries(cutoff: Double) -> [UsageEntry] {
        let fm = FileManager.default
        var oldIndex: [String: FileEntry] = [:]
        if let d = try? Data(contentsOf: indexPath),
           let idx = try? JSONDecoder().decode([String: FileEntry].self, from: d) {
            oldIndex = idx
        }

        var newIndex: [String: FileEntry] = [:]
        var allEntries: [UsageEntry] = []

        // 사용자가 projects 루트가 아니라 특정 프로젝트 폴더를 골랐을 때(파일이 바로 아래)
        // 프로젝트명이 ""가 되어 "(unknown)"으로 뭉치는 것 방지 → 고른 폴더명으로 폴백.
        let baseName = projectsDir.lastPathComponent
        let files = (try? fm.subpathsOfDirectory(atPath: projectsDir.path)) ?? []
        for rel in files where rel.hasSuffix(".jsonl") {
            let path = projectsDir.appendingPathComponent(rel).path
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970,
                  let size = attrs[.size] as? Int, mtime >= cutoff else { continue }

            let named = ProjectPath.name(fromRelative: rel)
            let project = named.isEmpty ? baseName : named
            if let cached = oldIndex[path], cached.mtime == mtime, cached.size == size {
                newIndex[path] = cached
                allEntries.append(contentsOf: cached.entries.map { toEntry($0, project: project) })
            } else {
                let parsed = parseFile(path, project: project)
                newIndex[path] = FileEntry(mtime: mtime, size: size,
                                           entries: parsed.map { toCached($0) })
                allEntries.append(contentsOf: parsed)
            }
        }

        try? fm.createDirectory(at: indexPath.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(newIndex) { try? d.write(to: indexPath) }

        return allEntries
    }

    private func parseFile(_ path: String, project: String) -> [UsageEntry] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var out: [UsageEntry] = []
        var seen = Set<String>()
        content.enumerateLines { line, _ in
            if let e = LogParser.parseLine(line, project: project), seen.insert(e.dedupKey).inserted {
                out.append(e)
            }
        }
        return out
    }

    private func toCached(_ e: UsageEntry) -> Cached {
        Cached(dayKey: e.dayKey, category: e.category.rawValue, input: e.input,
               output: e.output, cacheWrite: e.cacheWrite, cacheRead: e.cacheRead,
               cost: e.cost, dedupKey: e.dedupKey, hour: e.hour)
    }
    /// 캐시된 사용량 + 현재 위치 기준 project로 엔트리 복원.
    private func toEntry(_ c: Cached, project: String) -> UsageEntry {
        UsageEntry(dayKey: c.dayKey, category: ModelCategory(rawValue: c.category) ?? .sonnet,
                   input: c.input, output: c.output, cacheWrite: c.cacheWrite,
                   cacheRead: c.cacheRead, cost: c.cost, dedupKey: c.dedupKey,
                   project: project, hour: c.hour)
    }
}
