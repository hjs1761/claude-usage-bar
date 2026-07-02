import Foundation
import ClaudeUsageCore

func testLogParser(_ h: Harness) {
    // opus 라인: in100 out200 cacheRead1000 cc5m50 cc1h10
    let line = #"{"type":"assistant","timestamp":"2026-07-02T09:00:00Z","requestId":"req1","message":{"id":"m1","model":"claude-opus-4","usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":50,"ephemeral_1h_input_tokens":10}}}}"#

    h.run("LogParser.costExact") {
        if let e = LogParser.parseLine(line) {
            // 100*5e-6 + 200*5*5e-6 + 1000*0.1*5e-6 + 50*1.25*5e-6 + 10*2*5e-6 = 0.0064125
            h.expectClose(e.cost, 0.0064125, accuracy: 1e-9, "opus cost")
            h.expectEqual(e.category, .opus, "category")
            h.expectEqual(e.tokens, 1360, "tokens 100+200+60+1000")
            h.expectEqual(e.dedupKey, "m1|req1", "dedupKey")
        } else {
            h.expect(false, "should parse assistant line")
        }
    }
    h.run("LogParser.fractionalTimestamp") {
        // 실제 로그는 밀리초 포함: 2026-06-30T06:21:14.686Z
        let l = #"{"type":"assistant","timestamp":"2026-06-30T06:21:14.686Z","requestId":"r","message":{"id":"m","model":"claude-opus-4","usage":{"input_tokens":10,"output_tokens":20}}}"#
        h.expectNotNil(LogParser.parseLine(l), "parses fractional-second timestamp")
    }
    h.run("LogParser.skipNonAssistant") {
        h.expectNil(LogParser.parseLine(#"{"type":"user","message":{}}"#), "user skipped")
    }
    h.run("LogParser.skipNoUsage") {
        h.expectNil(LogParser.parseLine(#"{"type":"assistant","message":{"id":"x"}}"#), "no usage skipped")
    }
    h.run("LogParser.cacheWriteFallback1h") {
        let l = #"{"type":"assistant","timestamp":"2026-07-02T09:00:00Z","requestId":"r","message":{"id":"m","model":"claude-sonnet-4","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":100}}}"#
        if let e = LogParser.parseLine(l) {
            // sonnet b=3e-6, 1h 2x → 100*2*3e-6 = 6e-4
            h.expectClose(e.cost, 6e-4, accuracy: 1e-9, "fallback 1h cost")
            h.expectEqual(e.cacheWrite, 100, "cacheWrite")
        } else { h.expect(false, "should parse") }
    }
}

func testCostRollup(_ h: Harness) {
    func mk(_ day: String, _ cat: ModelCategory, _ cost: Double, _ key: String) -> UsageEntry {
        UsageEntry(dayKey: day, category: cat, input: 10, output: 0,
                   cacheWrite: 0, cacheRead: 0, cost: cost, dedupKey: key)
    }
    h.run("CostRollup.buckets") {
        // now = 2026-07-15(수). 월시작 07-01, 주시작(월) 07-13, 오늘 07-15
        var dc = DateComponents(); dc.year = 2026; dc.month = 7; dc.day = 15; dc.hour = 12
        let now = Calendar(identifier: .gregorian).date(from: dc)!
        let entries = [
            mk("2026-07-15", .opus, 1.0, "a"),   // 오늘+주+월
            mk("2026-07-14", .opus, 2.0, "b"),   // 주+월
            mk("2026-07-03", .sonnet, 4.0, "c"), // 월만
            mk("2026-06-30", .opus, 8.0, "d"),   // 범위 밖
        ]
        let c = CostRollup.rollup(entries: entries, now: now)
        h.expectClose(c.day.cost, 1.0, accuracy: 1e-9, "day")
        h.expectClose(c.week.cost, 3.0, accuracy: 1e-9, "week 1+2")
        h.expectClose(c.month.cost, 7.0, accuracy: 1e-9, "month 1+2+4")
        h.expectClose(c.byModel[.opus]?.cost ?? 0, 3.0, accuracy: 1e-9, "opus month")
        h.expectClose(c.byModel[.sonnet]?.cost ?? 0, 4.0, accuracy: 1e-9, "sonnet month")
    }
    h.run("CostRollup.dedup") {
        var dc = DateComponents(); dc.year = 2026; dc.month = 7; dc.day = 15
        let now = Calendar(identifier: .gregorian).date(from: dc)!
        let entries = [
            mk("2026-07-15", .opus, 1.0, "dup"),
            mk("2026-07-15", .opus, 1.0, "dup"),  // 중복
        ]
        let c = CostRollup.rollup(entries: entries, now: now)
        h.expectClose(c.day.cost, 1.0, accuracy: 1e-9, "dedup once")
    }
}
