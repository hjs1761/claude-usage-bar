import Foundation

/// 세션 사용률 소진 예측 상태.
public enum BurnState: Equatable, Sendable {
    case none               // 데이터 없음 → 표시 안 함
    case measuring          // 표본 모으는 중
    case stable             // 사용률 평탄/감소 → 리셋 전 한도 도달 안 함
    case reached            // 이미 한도(100%)
    case eta(TimeInterval)  // 현재 속도로 한도 도달까지 남은 초
}

/// (시각, 사용률%) 표본들로 한도 도달 시각을 외삽.
/// 윈도우판(claude_usage_*.py의 burn_text)과 동일 로직 — 첫·끝 표본의 단순 기울기.
public struct BurnEstimator: Sendable {
    /// 표본 하나: 단조 시각(초) + 그 시점의 사용률%.
    public struct Sample: Equatable, Sendable {
        public let t: TimeInterval
        public let percent: Double
        public init(t: TimeInterval, percent: Double) {
            self.t = t
            self.percent = percent
        }
    }

    public let windowSeconds: TimeInterval   // 표본 보관 창(그 이전은 폐기)
    public let minSamples: Int               // 예측 시작 최소 표본 수
    public let minSpanSeconds: TimeInterval  // 예측 시작 최소 시간폭

    public init(windowSeconds: TimeInterval = 40 * 60,
                minSamples: Int = 3,
                minSpanSeconds: TimeInterval = 90) {
        self.windowSeconds = windowSeconds
        self.minSamples = minSamples
        self.minSpanSeconds = minSpanSeconds
    }

    /// 창(windowSeconds) 밖의 오래된 표본 제거. 시각 오름차순 가정.
    public func pruned(_ samples: [Sample], now: TimeInterval) -> [Sample] {
        let cutoff = now - windowSeconds
        return samples.filter { $0.t >= cutoff }
    }

    /// 표본 + 현재 % → 소진 상태.
    /// - p 없음: .none / p>=100: .reached / 표본·시간폭 부족: .measuring
    /// - 기울기<=0(평탄·감소): .stable / 그 외: .eta(도달까지 남은 초)
    public func estimate(samples: [Sample], currentPercent: Double?) -> BurnState {
        guard let p = currentPercent else { return .none }
        if p >= 100 { return .reached }
        guard samples.count >= minSamples,
              let first = samples.first, let last = samples.last else { return .measuring }
        let span = last.t - first.t
        if span < minSpanSeconds { return .measuring }
        let rate = (last.percent - first.percent) / (span / 3600.0)   // %/시간
        if rate <= 0 { return .stable }
        let hours = (100 - p) / rate
        if hours <= 0 { return .reached }
        return .eta(hours * 3600)
    }
}
