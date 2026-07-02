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
    public var tokens: Int { input + output + cacheWrite + cacheRead }

    public init(dayKey: String, category: ModelCategory, input: Int, output: Int,
                cacheWrite: Int, cacheRead: Int, cost: Double, dedupKey: String) {
        self.dayKey = dayKey; self.category = category
        self.input = input; self.output = output
        self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
        self.cost = cost; self.dedupKey = dedupKey
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
    public init() {}
}
