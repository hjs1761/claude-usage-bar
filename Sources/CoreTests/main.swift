import Foundation
import ClaudeUsageCore

let h = Harness()

// MARK: - ModelCategory
h.run("ModelCategory.classify") {
    h.expectEqual(ModelCategory.from(model: "claude-opus-4"), .opus, "opus")
    h.expectEqual(ModelCategory.from(model: "claude-haiku-4-5"), .haiku, "haiku")
    h.expectEqual(ModelCategory.from(model: "claude-sonnet-4-6"), .sonnet, "sonnet")
    h.expectEqual(ModelCategory.from(model: nil), .sonnet, "nil→sonnet")
    h.expectEqual(ModelCategory.from(model: "claude-fable-5"), .fable, "fable 5")
    h.expectEqual(ModelCategory.from(model: "claude-fable-5-1"), .fable, "fable 5.1")
}
h.run("ModelCategory.prices") {
    h.expectEqual(ModelCategory.fable.basePrice, 10e-6, "fable price")
    h.expectEqual(ModelCategory.opus.basePrice, 5e-6, "opus price")
    h.expectEqual(ModelCategory.sonnet.basePrice, 3e-6, "sonnet price")
    h.expectEqual(ModelCategory.haiku.basePrice, 1e-6, "haiku price")
}
h.run("ModelCategory.pricePerModel") {
    // 카테고리 기본값에서 벗어나는 모델 (base USD/token, 캐시읽기 배수)
    h.expectEqual(ModelCategory.price(model: "claude-fable-5-1"), ModelPrice(base: 10e-6, cacheRead: 0.025), "fable 5.1")
    h.expectEqual(ModelCategory.price(model: "claude-fable-5-1[1m]"), ModelPrice(base: 10e-6, cacheRead: 0.025), "fable 5.1 [1m]")
    h.expectEqual(ModelCategory.price(model: "claude-fable-5"), ModelPrice(base: 10e-6, cacheRead: 0.1), "fable 5")
    h.expectEqual(ModelCategory.price(model: "claude-opus-5-5"), ModelPrice(base: 4e-6, cacheRead: 0.05), "opus 5.5")
    h.expectEqual(ModelCategory.price(model: "claude-opus-5-5[1m]"), ModelPrice(base: 4e-6, cacheRead: 0.05), "opus 5.5 [1m]")
    h.expectEqual(ModelCategory.price(model: "claude-opus-5"), ModelPrice(base: 5e-6, cacheRead: 0.1), "opus 5")
    h.expectEqual(ModelCategory.price(model: "claude-opus-4-5"), ModelPrice(base: 5e-6, cacheRead: 0.1), "opus 4.5 ≠ 5.5")
    h.expectEqual(ModelCategory.price(model: "claude-sonnet-5"), ModelPrice(base: 2e-6, cacheRead: 0.1), "sonnet 5")
    h.expectEqual(ModelCategory.price(model: "claude-sonnet-4-6"), ModelPrice(base: 3e-6, cacheRead: 0.1), "sonnet 4.6")
    h.expectEqual(ModelCategory.price(model: "claude-sonnet-4-5"), ModelPrice(base: 3e-6, cacheRead: 0.1), "sonnet 4.5 ≠ 5")
    h.expectEqual(ModelCategory.price(model: nil), ModelPrice(base: 3e-6, cacheRead: 0.1), "nil→sonnet 기본")
}

// MARK: - ColorAdapt
testColorAdapt(h)

// MARK: - Credentials
testCredentials(h)

// MARK: - UsageData
testUsageData(h)

// MARK: - LogParser + CostRollup
testLogParser(h)
testProjectTagging(h)
testCostRollup(h)
testDailyAndProject(h)
testAggregatorIntegration(h)

// MARK: - Settings
testSettings(h)

// MARK: - BurnEstimator (소진 예측)
testBurnEstimator(h)

// MARK: - Version
testVersion(h)

// MARK: - ReleaseParser
testReleaseParser(h)

// MARK: - Contact
testContact(h)

// MARK: - FileAttribution
testFileAttribution(h)

h.finish()
