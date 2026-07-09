import Foundation
import ClaudeUsageCore

let h = Harness()

// MARK: - ModelCategory
h.run("ModelCategory.classify") {
    h.expectEqual(ModelCategory.from(model: "claude-opus-4"), .opus, "opus")
    h.expectEqual(ModelCategory.from(model: "claude-haiku-4-5"), .haiku, "haiku")
    h.expectEqual(ModelCategory.from(model: "claude-sonnet-4-6"), .sonnet, "sonnet")
    h.expectEqual(ModelCategory.from(model: nil), .sonnet, "nil→sonnet")
}
h.run("ModelCategory.prices") {
    h.expectEqual(ModelCategory.opus.basePrice, 5e-6, "opus price")
    h.expectEqual(ModelCategory.sonnet.basePrice, 3e-6, "sonnet price")
    h.expectEqual(ModelCategory.haiku.basePrice, 1e-6, "haiku price")
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

h.finish()
