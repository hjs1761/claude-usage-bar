import Foundation

/// 세션 사용률 소진 예측 상태.
public enum BurnState: Equatable, Sendable {
    case none               // 예측 불가(퍼센트/리셋시각 없음)
    case measuring          // 창 시작 직후 등 아직 추정하기 이름
    case stable             // 이번 창엔 한도 도달 안 할 페이스
    case reached            // 이미 한도(100%)
    case eta(TimeInterval)  // 이번 창 내 한도 도달까지 남은 초
}

/// 계정 스냅샷 기반 소진 예측.
/// 현재 % 와 리셋시각만으로 "창 평균 페이스"를 계산 → 로컬 히스토리 불필요.
/// 같은 계정이면 어느 기기에서 계산해도 동일한 값이 나온다(3대 일관).
///   창 시작 = resets_at − windowSeconds,  경과 = windowSeconds − (리셋까지 남은 초)
///   평균속도 = % / 경과,  도달까지 = (100 − %) / 평균속도
public struct BurnEstimator: Sendable {
    /// 세션 한도 창 길이(초). 세션 = 5시간.
    public static let sessionWindow: TimeInterval = 5 * 3600

    /// 추정 시작에 필요한 최소 경과(초). 창 시작 직후엔 노이즈가 커서 대기.
    public let minElapsedSeconds: TimeInterval

    public init(minElapsedSeconds: TimeInterval = 5 * 60) {
        self.minElapsedSeconds = minElapsedSeconds
    }

    /// - percent: 현재 사용률(%)
    /// - secondsUntilReset: 리셋까지 남은 초 (resets_at − now)
    /// - windowSeconds: 이 한도의 창 길이(세션=5h)
    public func estimate(percent: Double?,
                         secondsUntilReset: TimeInterval?,
                         windowSeconds: TimeInterval) -> BurnState {
        guard let p = percent else { return .none }
        if p >= 100 { return .reached }
        guard let r = secondsUntilReset, r > 0 else { return .none }
        let elapsed = windowSeconds - r            // 창 시작 이후 경과
        if elapsed < minElapsedSeconds { return .measuring }
        if p <= 0 { return .stable }
        let ratePerSec = p / elapsed               // %/초 (창 평균 페이스)
        if ratePerSec <= 0 { return .stable }
        let eta = (100 - p) / ratePerSec           // 한도 도달까지 남은 초
        if eta <= 0 { return .reached }
        if eta >= r { return .stable }             // 리셋 전에 도달 안 함 → 안정
        return .eta(eta)
    }
}
