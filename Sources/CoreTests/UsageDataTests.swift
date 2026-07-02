import Foundation
import ClaudeUsageCore

func testUsageData(_ h: Harness) {
    let sample = #"""
    {"limits":[
      {"kind":"session","percent":35.4,"resets_at":"2026-07-02T15:00:00Z","severity":"ok"},
      {"kind":"weekly_all","percent":62.0,"resets_at":"2026-07-07T00:00:00Z"},
      {"kind":"weekly_scoped","percent":10,"scope":{"model":{"display_name":"Opus"}}}
    ],
    "extra_usage":{"is_enabled":true,"utilization":12.5}}
    """#

    h.run("UsageData.decodeLimits") {
        if let d = try? UsageData.decode(Data(sample.utf8)) {
            h.expectEqual(d.limits.count, 3, "limit count")
            h.expectEqual(d.limits[0].kind ?? "", "session", "first kind")
            h.expectEqual(Int(d.limits[0].percent ?? 0), 35, "session pct")
            h.expectEqual(d.limits[2].scope?.model?.displayName ?? "", "Opus", "scoped model")
        } else {
            h.expect(false, "decode sample")
        }
    }
    h.run("UsageData.extraUsage") {
        if let d = try? UsageData.decode(Data(sample.utf8)) {
            h.expect(d.extraUsage?.isEnabled ?? false, "extra enabled")
            h.expectClose(d.extraUsage?.utilization ?? 0, 12.5, accuracy: 0.01, "extra util")
        } else { h.expect(false, "decode") }
    }
    h.run("UsageData.helpers") {
        if let d = try? UsageData.decode(Data(sample.utf8)) {
            h.expectEqual(Int(d.sessionPercent ?? 0), 35, "sessionPercent")
            h.expectEqual(Int(d.weeklyPercent ?? 0), 62, "weeklyPercent")
        } else { h.expect(false, "decode") }
    }
    h.run("ISODate.realFormats") {
        // 로그: 밀리초+Z / usage: 마이크로초+오프셋 / 소수부 없음
        h.expectNotNil(ISODate.parse("2026-06-30T06:21:14.686Z"), "millis+Z")
        h.expectNotNil(ISODate.parse("2026-07-02T11:30:00.174256+00:00"), "micros+offset")
        h.expectNotNil(ISODate.parse("2026-07-02T15:00:00Z"), "no-fraction")
    }
    h.run("UsageData.remainingWithRealFormat") {
        // resets_at가 마이크로초+오프셋이어도 남은시간이 계산돼야 함
        let json = #"{"limits":[{"kind":"session","percent":34,"resets_at":"2026-07-02T11:30:00.174256+00:00"}]}"#
        if let d = try? UsageData.decode(Data(json.utf8)) {
            // 기준 시각을 리셋 12분 전으로 → "12m"
            let now = ISODate.parse("2026-07-02T11:18:00.000000+00:00")!
            h.expectEqual(d.limits[0].remaining(now: now) ?? "", "12m", "remaining 12m")
        } else { h.expect(false, "decode") }
    }
    h.run("UsageData.missingFields") {
        if let d = try? UsageData.decode(Data(#"{"limits":[]}"#.utf8)) {
            h.expectEqual(d.limits.count, 0, "empty limits")
            h.expectNil(d.sessionPercent, "no session")
        } else { h.expect(false, "decode empty") }
    }
}
