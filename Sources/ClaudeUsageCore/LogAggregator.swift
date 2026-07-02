import Foundation

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
    struct Cached: Codable {
        var dayKey: String; var category: String
        var input: Int; var output: Int; var cacheWrite: Int; var cacheRead: Int
        var cost: Double; var dedupKey: String
    }

    public func compute(now: Date = Date()) -> UsageCost {
        let fm = FileManager.default
        // cutoff: 이번달/이번주 시작 중 이른 것 - 하루
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        let weekStart = cal.date(from: cal.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: today))!
        let cutoff = min(monthStart, weekStart).addingTimeInterval(-86400).timeIntervalSince1970

        var oldIndex: [String: FileEntry] = [:]
        if let d = try? Data(contentsOf: indexPath),
           let idx = try? JSONDecoder().decode([String: FileEntry].self, from: d) {
            oldIndex = idx
        }

        var newIndex: [String: FileEntry] = [:]
        var allEntries: [UsageEntry] = []

        let files = (try? fm.subpathsOfDirectory(atPath: projectsDir.path)) ?? []
        for rel in files where rel.hasSuffix(".jsonl") {
            let path = projectsDir.appendingPathComponent(rel).path
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970,
                  let size = attrs[.size] as? Int, mtime >= cutoff else { continue }

            if let cached = oldIndex[path], cached.mtime == mtime, cached.size == size {
                newIndex[path] = cached
                allEntries.append(contentsOf: cached.entries.map { toEntry($0) })
            } else {
                let parsed = parseFile(path)
                newIndex[path] = FileEntry(mtime: mtime, size: size,
                                           entries: parsed.map { toCached($0) })
                allEntries.append(contentsOf: parsed)
            }
        }

        try? fm.createDirectory(at: indexPath.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(newIndex) { try? d.write(to: indexPath) }

        return CostRollup.rollup(entries: allEntries, now: now)
    }

    private func parseFile(_ path: String) -> [UsageEntry] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var out: [UsageEntry] = []
        var seen = Set<String>()
        content.enumerateLines { line, _ in
            if let e = LogParser.parseLine(line), seen.insert(e.dedupKey).inserted {
                out.append(e)
            }
        }
        return out
    }

    private func toCached(_ e: UsageEntry) -> Cached {
        Cached(dayKey: e.dayKey, category: e.category.rawValue, input: e.input,
               output: e.output, cacheWrite: e.cacheWrite, cacheRead: e.cacheRead,
               cost: e.cost, dedupKey: e.dedupKey)
    }
    private func toEntry(_ c: Cached) -> UsageEntry {
        UsageEntry(dayKey: c.dayKey, category: ModelCategory(rawValue: c.category) ?? .sonnet,
                   input: c.input, output: c.output, cacheWrite: c.cacheWrite,
                   cacheRead: c.cacheRead, cost: c.cost, dedupKey: c.dedupKey)
    }
}
