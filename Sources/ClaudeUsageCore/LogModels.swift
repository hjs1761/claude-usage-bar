import Foundation

public struct UsageEntry: Sendable, Equatable {
    public let dayKey: String       // "YYYY-MM-DD" (로컬)
    public let category: ModelCategory
    public let input: Int
    public let output: Int
    public let cacheWrite: Int
    public let cacheRead: Int
    public let cost: Double
    public let dedupKey: String      // "\(msgId)|\(requestId)"
    public let project: String       // ~/.claude/projects/{folder}, 미상이면 ""
    public let hour: Int             // 0~23 (로컬) — 시간대별 드릴다운용
    public var tokens: Int { input + output + cacheWrite + cacheRead }

    public init(dayKey: String, category: ModelCategory, input: Int, output: Int,
                cacheWrite: Int, cacheRead: Int, cost: Double, dedupKey: String,
                project: String = "", hour: Int = 0) {
        self.dayKey = dayKey; self.category = category
        self.input = input; self.output = output
        self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
        self.cost = cost; self.dedupKey = dedupKey
        self.project = project; self.hour = hour
    }
}

public struct ModelBucket: Sendable {
    public var cost: Double = 0
    public var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    public var tokens: Int { input + output + cacheWrite + cacheRead }
    public init() {}
}

public struct UsageCost: Sendable {
    public var day = ModelBucket()
    public var week = ModelBucket()
    public var month = ModelBucket()
    public var byModel: [ModelCategory: ModelBucket] = [:]   // 이번 달 기준
    public var byProject: [String: ModelBucket] = [:]        // 이번 달 기준 (key=폴더명, ""=미상)
    public init() {}
}

/// 추이 차트용 구간 포인트 (일/월/연 공용).
public struct SeriesPoint: Sendable, Equatable, Identifiable {
    public let date: Date      // 구간 대표 시각 (일=그날, 월=1일, 연=1월1일) — 차트 x축·정렬
    public let label: String   // "2026-07-15" / "2026-07" / "2026"
    public let cost: Double
    public let tokens: Int
    public var id: String { label }
    public init(date: Date, label: String, cost: Double, tokens: Int) {
        self.date = date; self.label = label; self.cost = cost; self.tokens = tokens
    }
}
