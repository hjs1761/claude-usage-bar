import Foundation

public enum ModelCategory: String, CaseIterable, Sendable {
    case opus, sonnet, haiku

    /// base 입력 단가 (USD/token). 출력 5x, 캐시읽기 0.1x, 캐시쓰기5m 1.25x / 1h 2x.
    public var basePrice: Double {
        switch self {
        case .opus:   return 5e-6
        case .sonnet: return 3e-6
        case .haiku:  return 1e-6
        }
    }

    public var displayName: String {
        switch self {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        }
    }

    /// 모델명 문자열 → 카테고리. opus/haiku 아니면 sonnet.
    public static func from(model: String?) -> ModelCategory {
        let m = (model ?? "").lowercased()
        if m.contains("opus") { return .opus }
        if m.contains("haiku") { return .haiku }
        return .sonnet
    }
}
