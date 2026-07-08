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
    h.run("LogParser.dedupFallbackNoIds") {
        // id·requestId 둘 다 없는 서로 다른 두 라인 → dedupKey 달라야 (과잉 dedup=비용누락 방지)
        let l1 = #"{"type":"assistant","timestamp":"2026-07-02T09:00:00Z","message":{"model":"claude-opus-4","usage":{"input_tokens":10,"output_tokens":20}}}"#
        let l2 = #"{"type":"assistant","timestamp":"2026-07-02T09:00:00Z","message":{"model":"claude-opus-4","usage":{"input_tokens":30,"output_tokens":40}}}"#
        let e1 = LogParser.parseLine(l1), e2 = LogParser.parseLine(l2)
        h.expectNotNil(e1, "l1 parses"); h.expectNotNil(e2, "l2 parses")
        h.expect((e1?.dedupKey ?? "x") != (e2?.dedupKey ?? "y"), "다른 내용 → 다른 dedupKey")
        h.expect((e1?.dedupKey ?? "|") != "|", "both-empty이어도 \"|\" 아님")
        // 동일 라인 반복 → 같은 키 (진짜 중복은 여전히 dedup, 결정론적)
        h.expectEqual(LogParser.parseLine(l1)?.dedupKey, LogParser.parseLine(l1)?.dedupKey, "동일라인 동일키")
    }
    h.run("StableHash.deterministic") {
        h.expectEqual(StableHash.fnv1a("hello"), StableHash.fnv1a("hello"), "동일입력 동일해시")
        h.expect(StableHash.fnv1a("a") != StableHash.fnv1a("b"), "다른입력 다른해시")
    }
}

func testProjectTagging(_ h: Harness) {
    h.run("ProjectPath.name") {
        // ~/.claude/projects 아래 상대경로의 첫 요소 = 프로젝트 폴더
        h.expectEqual(ProjectPath.name(fromRelative: "myproj/uuid.jsonl"), "myproj", "first component")
        h.expectEqual(ProjectPath.name(fromRelative: "myproj/sub/x.jsonl"), "myproj", "nested→first")
        h.expectEqual(ProjectPath.name(fromRelative: "x.jsonl"), "", "폴더 없으면 빈문자")
        h.expectEqual(ProjectPath.name(fromRelative: ""), "", "빈 경로→빈문자")
    }
    h.run("LogParser.project") {
        let line = #"{"type":"assistant","timestamp":"2026-07-02T09:00:00Z","requestId":"r","message":{"id":"m","model":"claude-opus-4","usage":{"input_tokens":10,"output_tokens":20}}}"#
        h.expectEqual(LogParser.parseLine(line, project: "acme")?.project, "acme", "project 주입")
        h.expectEqual(LogParser.parseLine(line)?.project, "", "기본값 빈문자")
    }
}

func testAggregatorIntegration(_ h: Harness) {
    let fm = FileManager.default
    func mkLine(_ ts: String, _ model: String, _ inTok: Int, _ id: String) -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","requestId":"\#(id)","message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(inTok),"output_tokens":0}}}"#
    }
    h.run("LogAggregator.computeDashboard") {
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("tt-agg-" + ProcessInfo.processInfo.globallyUniqueString)
        let projA = tmp.appendingPathComponent("projA")
        let projB = tmp.appendingPathComponent("projB")
        try? fm.createDirectory(at: projA, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projB, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // opus base 5e-6: 1000*5e-6 = 0.005 / sonnet 3e-6: 1000*3e-6 = 0.003
        let a = [
            mkLine("2026-07-15T09:00:00Z", "claude-opus-4", 1000, "a1"),  // 오늘
            mkLine("2026-07-10T09:00:00Z", "claude-opus-4", 1000, "a2"),  // 이번달·30일창 안
            mkLine("2026-05-01T09:00:00Z", "claude-opus-4", 1000, "a3"),  // 창 밖(제외)
        ].joined(separator: "\n")
        try? a.write(to: projA.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        try? mkLine("2026-07-14T09:00:00Z", "claude-sonnet-4", 1000, "b1")
            .write(to: projB.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)

        let agg = LogAggregator(projectsDir: tmp, indexPath: tmp.appendingPathComponent("index.json"))
        var dc = DateComponents(); dc.year = 2026; dc.month = 7; dc.day = 15; dc.hour = 12
        let now = Calendar(identifier: .gregorian).date(from: dc)!
        let data = agg.computeDashboard(now: now)

        // 이번달 합계: 07-15 + 07-10 + 07-14 = 0.005+0.005+0.003 (05-01 제외)
        h.expectClose(data.cost.month.cost, 0.013, accuracy: 1e-9, "월 합(05-01 제외)")
        h.expectClose(data.cost.byProject["projA"]?.cost ?? 0, 0.010, accuracy: 1e-9, "projA=두 opus")
        h.expectClose(data.cost.byProject["projB"]?.cost ?? 0, 0.003, accuracy: 1e-9, "projB=sonnet")
        let daily = CostRollup.dailySeries(entries: data.entries, days: 30, endingAt: now)
        h.expectEqual(daily.count, 30, "일별 30포인트")
        h.expectEqual(daily.last?.label, "2026-07-15", "마지막=오늘")
        h.expectClose(daily.last?.cost ?? 0, 0.005, accuracy: 1e-9, "오늘 0.005")
        let dailySum = daily.reduce(0) { $0 + $1.cost }
        h.expectClose(dailySum, 0.013, accuracy: 1e-9, "30일 합=0.013 (월초 잘림 없음)")

        // 2회차 = 캐시 히트. project가 캐시된 경로에서도 재도출돼 유지돼야 함.
        let data2 = agg.computeDashboard(now: now)
        h.expectClose(data2.cost.byProject["projA"]?.cost ?? 0, 0.010, accuracy: 1e-9, "캐시히트도 projA 유지")
        h.expect(data2.cost.byProject[""] == nil, "캐시히트여도 빈 프로젝트 없어야")
    }
    h.run("LogAggregator.baseFolderFallback") {
        // 사용자가 projects 루트가 아닌 특정 프로젝트 폴더를 고른 경우(파일이 바로 아래)
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("proj-solo-" + ProcessInfo.processInfo.globallyUniqueString)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        try? mkLine("2026-07-15T09:00:00Z", "claude-opus-4", 1000, "s1")
            .write(to: tmp.appendingPathComponent("x.jsonl"), atomically: true, encoding: .utf8)

        let agg = LogAggregator(projectsDir: tmp, indexPath: tmp.appendingPathComponent("i.json"))
        var dc = DateComponents(); dc.year = 2026; dc.month = 7; dc.day = 15; dc.hour = 12
        let now = Calendar(identifier: .gregorian).date(from: dc)!
        let data = agg.computeDashboard(now: now)
        h.expect(data.cost.byProject[""] == nil, "빈 프로젝트 키 없어야")
        h.expect(data.cost.byProject[tmp.lastPathComponent] != nil, "고른 폴더명으로 태깅")
    }
}

func testDailyAndProject(_ h: Harness) {
    func mk(_ day: String, _ cost: Double, _ key: String, _ proj: String = "") -> UsageEntry {
        UsageEntry(dayKey: day, category: .opus, input: 10, output: 0,
                   cacheWrite: 0, cacheRead: 0, cost: cost, dedupKey: key, project: proj)
    }
    var dc = DateComponents(); dc.year = 2026; dc.month = 7; dc.day = 15; dc.hour = 12
    let now = Calendar(identifier: .gregorian).date(from: dc)!

    h.run("CostRollup.byProject") {
        let entries = [
            mk("2026-07-15", 1.0, "a", "projX"),
            mk("2026-07-10", 2.0, "b", "projX"),
            mk("2026-07-05", 4.0, "c", "projY"),
            mk("2026-06-30", 8.0, "d", "projX"),   // 지난달 → 제외
        ]
        let c = CostRollup.rollup(entries: entries, now: now)
        h.expectClose(c.byProject["projX"]?.cost ?? 0, 3.0, accuracy: 1e-9, "projX 이번달 1+2")
        h.expectClose(c.byProject["projY"]?.cost ?? 0, 4.0, accuracy: 1e-9, "projY 이번달 4")
    }
    h.run("CostRollup.dailySeries") {
        let entries = [
            mk("2026-07-15", 1.0, "a"),
            mk("2026-07-15", 2.0, "b"),
            mk("2026-07-15", 2.0, "b"),   // dedup 중복 → 무시
            mk("2026-07-13", 5.0, "c"),
            mk("2026-07-01", 9.0, "z"),   // 7일 창 밖
        ]
        let s = CostRollup.dailySeries(entries: entries, days: 7, endingAt: now)
        h.expectEqual(s.count, 7, "정확히 7일")
        h.expectEqual(s.first?.label, "2026-07-09", "시작 = end-6")
        h.expectEqual(s.last?.label, "2026-07-15", "종료 = end")
        h.expectClose(s.last?.cost ?? -1, 3.0, accuracy: 1e-9, "오늘 1+2 (dup 제외)")
        h.expectClose(s[4].cost, 5.0, accuracy: 1e-9, "7-13 (index4)")
        h.expectClose(s[0].cost, 0.0, accuracy: 1e-9, "빈 날 0으로 채움")
    }
    h.run("CostRollup.dailySeries.paging") {
        // endingAt을 과거로 → 창이 뒤로 이동 (좌우 페이징)
        let entries = [mk("2026-07-05", 3.0, "p1"), mk("2026-07-15", 9.0, "p2")]
        var pc = DateComponents(); pc.year = 2026; pc.month = 7; pc.day = 8; pc.hour = 12
        let past = Calendar(identifier: .gregorian).date(from: pc)!
        let s = CostRollup.dailySeries(entries: entries, days: 7, endingAt: past)   // 07-02..07-08
        h.expectEqual(s.first?.label, "2026-07-02", "창 시작 이동")
        h.expectEqual(s.last?.label, "2026-07-08", "창 끝 이동")
        h.expectClose(s[3].cost, 3.0, accuracy: 1e-9, "07-05 포함")
        let sum = s.reduce(0) { $0 + $1.cost }
        h.expectClose(sum, 3.0, accuracy: 1e-9, "07-15는 창 밖")
    }
    h.run("CostRollup.monthlySeries") {
        let entries = [
            mk("2026-01-10", 1.0, "m1"), mk("2026-01-20", 2.0, "m2"),
            mk("2026-07-05", 4.0, "m3"), mk("2025-12-31", 8.0, "m4"),  // 다른 해 제외
        ]
        let s = CostRollup.monthlySeries(entries: entries, year: 2026)
        h.expectEqual(s.count, 12, "12개월")
        h.expectEqual(s.first?.label, "2026-01", "1월 라벨")
        h.expectClose(s[0].cost, 3.0, accuracy: 1e-9, "1월 1+2")
        h.expectClose(s[6].cost, 4.0, accuracy: 1e-9, "7월 4")
        h.expectClose(s[11].cost, 0.0, accuracy: 1e-9, "12월 0")
    }
    h.run("CostRollup.yearlySeries") {
        let entries = [mk("2024-05-01", 1.0, "y1"), mk("2026-05-01", 4.0, "y2")]  // 2025 빈해
        let s = CostRollup.yearlySeries(entries: entries)
        h.expectEqual(s.map(\.label), ["2024", "2025", "2026"], "연속 연도 채움")
        h.expectClose(s[0].cost, 1.0, accuracy: 1e-9, "2024")
        h.expectClose(s[1].cost, 0.0, accuracy: 1e-9, "2025 빈해")
        h.expectClose(s[2].cost, 4.0, accuracy: 1e-9, "2026")
    }
    h.run("CostRollup.dailySeriesOfMonth") {
        let e = [
            mk("2026-07-01", 1.0, "d1"), mk("2026-07-15", 2.0, "d2"),
            mk("2026-06-15", 9.0, "d3"),   // 다른 달 제외
        ]
        let s = CostRollup.dailySeriesOfMonth(entries: e, year: 2026, month: 7)
        h.expectEqual(s.count, 31, "7월=31일")
        h.expectEqual(s.first?.label, "2026-07-01", "1일 라벨")
        h.expectClose(s[0].cost, 1.0, accuracy: 1e-9, "1일")
        h.expectClose(s[14].cost, 2.0, accuracy: 1e-9, "15일")
        h.expectClose(s[30].cost, 0.0, accuracy: 1e-9, "31일 0")
    }
    h.run("CostRollup.totals") {
        let e = [
            mk("2026-07-15", 1.0, "t1", "projA"), mk("2026-07-15", 2.0, "t2", "projB"),
            mk("2026-07-15", 2.0, "t2", "projB"),   // dedup
        ]
        h.expectClose(CostRollup.total(e).cost, 3.0, accuracy: 1e-9, "합계 1+2 (dup 제외)")
        h.expectClose(CostRollup.totalsByModel(e)[.opus]?.cost ?? 0, 3.0, accuracy: 1e-9, "opus 3")
        h.expectClose(CostRollup.totalsByProject(e)["projA"]?.cost ?? 0, 1.0, accuracy: 1e-9, "projA 1")
        h.expectClose(CostRollup.totalsByProject(e)["projB"]?.cost ?? 0, 2.0, accuracy: 1e-9, "projB 2")
    }
    h.run("CostRollup.hourlySeries") {
        func mkh(_ day: String, _ hour: Int, _ cost: Double, _ key: String) -> UsageEntry {
            UsageEntry(dayKey: day, category: .opus, input: 0, output: 0, cacheWrite: 0,
                       cacheRead: 0, cost: cost, dedupKey: key, project: "", hour: hour)
        }
        let e = [
            mkh("2026-07-15", 9, 1.0, "h1"), mkh("2026-07-15", 9, 2.0, "h2"),
            mkh("2026-07-15", 22, 4.0, "h3"), mkh("2026-07-14", 9, 8.0, "h4"),  // 다른 날 제외
        ]
        let s = CostRollup.hourlySeries(entries: e, year: 2026, month: 7, day: 15)
        h.expectEqual(s.count, 24, "24시간")
        h.expectEqual(s.first?.label, "00", "0시 라벨")
        h.expectClose(s[9].cost, 3.0, accuracy: 1e-9, "09시 1+2")
        h.expectClose(s[22].cost, 4.0, accuracy: 1e-9, "22시 4")
        h.expectClose(s[0].cost, 0.0, accuracy: 1e-9, "00시 0")
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
