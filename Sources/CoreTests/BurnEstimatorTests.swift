import Foundation
import ClaudeUsageCore

func testBurnEstimator(_ h: Harness) {
    let e = BurnEstimator()   // 40m 창, 최소 3표본·90초

    h.run("Burn.none/reached") {
        h.expectEqual(e.estimate(samples: [], currentPercent: nil), .none, "퍼센트 없음→none")
        h.expectEqual(e.estimate(samples: [], currentPercent: 100), .reached, "100%→reached")
        h.expectEqual(e.estimate(samples: [], currentPercent: 105), .reached, ">100%→reached")
    }

    h.run("Burn.measuring") {
        // 표본 2개 → 부족
        let two = [BurnEstimator.Sample(t: 0, percent: 10),
                   BurnEstimator.Sample(t: 200, percent: 20)]
        h.expectEqual(e.estimate(samples: two, currentPercent: 20), .measuring, "표본<3→measuring")
        // 표본 3개지만 시간폭 60초(<90) → 부족
        let tooShort = [BurnEstimator.Sample(t: 0, percent: 10),
                        BurnEstimator.Sample(t: 30, percent: 12),
                        BurnEstimator.Sample(t: 60, percent: 14)]
        h.expectEqual(e.estimate(samples: tooShort, currentPercent: 14), .measuring, "시간폭<90→measuring")
    }

    h.run("Burn.stable") {
        // 평탄(기울기 0)
        let flat = [BurnEstimator.Sample(t: 0, percent: 40),
                    BurnEstimator.Sample(t: 120, percent: 40),
                    BurnEstimator.Sample(t: 240, percent: 40)]
        h.expectEqual(e.estimate(samples: flat, currentPercent: 40), .stable, "평탄→stable")
        // 감소(리셋 등)
        let down = [BurnEstimator.Sample(t: 0, percent: 80),
                    BurnEstimator.Sample(t: 120, percent: 50),
                    BurnEstimator.Sample(t: 240, percent: 20)]
        h.expectEqual(e.estimate(samples: down, currentPercent: 20), .stable, "감소→stable")
    }

    h.run("Burn.eta") {
        // t=0 50% → t=3600(1h) 60% ⇒ rate=10%/h, 현재 60% ⇒ (100-60)/10 = 4h = 14400s
        let ordered = [BurnEstimator.Sample(t: 0, percent: 50),
                       BurnEstimator.Sample(t: 1800, percent: 55),
                       BurnEstimator.Sample(t: 3600, percent: 60)]
        if case let .eta(secs) = e.estimate(samples: ordered, currentPercent: 60) {
            h.expectClose(secs, 14400, accuracy: 1, "rate 10%/h, 60%→4h")
        } else {
            h.expect(false, "증가 추세면 eta 나와야 함")
        }
    }

    h.run("Burn.pruned") {
        let now: TimeInterval = 5000
        let s = [BurnEstimator.Sample(t: 100, percent: 10),    // now-4900 → 창(2400) 밖
                 BurnEstimator.Sample(t: 3000, percent: 30),   // now-2000 → 창 안
                 BurnEstimator.Sample(t: 4800, percent: 40)]
        let p = e.pruned(s, now: now)
        h.expectEqual(p.count, 2, "40분 창 밖 표본 1개 제거")
        h.expectEqual(p.first?.percent ?? -1, 30, "남은 첫 표본=30%")
    }
}
