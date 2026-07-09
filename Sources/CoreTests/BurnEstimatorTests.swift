import Foundation
import ClaudeUsageCore

func testBurnEstimator(_ h: Harness) {
    let e = BurnEstimator()              // minElapsed 5분
    let W = BurnEstimator.sessionWindow  // 18000초(5h)

    h.run("Burn.none/reached") {
        h.expectEqual(e.estimate(percent: nil, secondsUntilReset: 8000, windowSeconds: W), .none, "퍼센트 없음→none")
        h.expectEqual(e.estimate(percent: 100, secondsUntilReset: 8000, windowSeconds: W), .reached, "100%→reached")
        h.expectEqual(e.estimate(percent: 105, secondsUntilReset: 8000, windowSeconds: W), .reached, ">100%→reached")
        h.expectEqual(e.estimate(percent: 50, secondsUntilReset: nil, windowSeconds: W), .none, "리셋시각 없음→none")
        h.expectEqual(e.estimate(percent: 50, secondsUntilReset: 0, windowSeconds: W), .none, "리셋 남은시간 0→none")
    }

    h.run("Burn.measuring") {
        // 경과 = 18000 - 17800 = 200초(<300) → 이름
        h.expectEqual(e.estimate(percent: 5, secondsUntilReset: 17800, windowSeconds: W), .measuring, "창 시작 직후→measuring")
    }

    h.run("Burn.stable") {
        // 경과 9000, p=20 → eta=(80/20)*9000=36000 ≥ r(9000) → 리셋 전 도달 안 함
        h.expectEqual(e.estimate(percent: 20, secondsUntilReset: 9000, windowSeconds: W), .stable, "느린 페이스→stable")
        // p<=0
        h.expectEqual(e.estimate(percent: 0, secondsUntilReset: 9000, windowSeconds: W), .stable, "0%→stable")
    }

    h.run("Burn.eta") {
        // 경과 9000, p=60 → rate=60/9000, eta=(40)/(60/9000)=6000초. r=9000 → eta<r → eta(6000)
        if case let .eta(secs) = e.estimate(percent: 60, secondsUntilReset: 9000, windowSeconds: W) {
            h.expectClose(secs, 6000, accuracy: 1, "p60·경과9000 → 6000초")
        } else {
            h.expect(false, "리셋 전 도달 페이스면 eta 나와야 함")
        }
        // 실사례: p=78, r=8160(2h16m) → 경과 9840, eta≈2775초(약 46분)
        if case let .eta(secs) = e.estimate(percent: 78, secondsUntilReset: 8160, windowSeconds: W) {
            h.expectClose(secs, 2775.4, accuracy: 1, "p78·리셋2h16m → ~46분")
        } else {
            h.expect(false, "eta 기대")
        }
    }

    h.run("Burn.동일성(계정기반)") {
        // 같은 스냅샷이면 어느 기기서 계산해도(=같은 입력) 동일한 결과 — 로컬 히스토리 무관
        let a = e.estimate(percent: 73.4, secondsUntilReset: 7200, windowSeconds: W)
        let b = e.estimate(percent: 73.4, secondsUntilReset: 7200, windowSeconds: W)
        h.expectEqual(a, b, "같은 스냅샷 → 항상 동일")
    }
}
