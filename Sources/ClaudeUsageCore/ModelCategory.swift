import Foundation

/// 모델 1개의 단가. 출력 5x, 캐시쓰기 5m 1.25x / 1h 2x는 전 모델 공통이라 base만 둔다.
public struct ModelPrice: Sendable, Equatable {
    public let base: Double       // 입력 USD/token
    public let cacheRead: Double  // 캐시읽기 배수 (base 대비)
    public init(base: Double, cacheRead: Double) { self.base = base; self.cacheRead = cacheRead }
}

public enum ModelCategory: String, CaseIterable, Sendable {
    case fable, opus, sonnet, haiku

    /// 카테고리 기본 base 입력 단가 (USD/token). 모델별 예외는 `price(model:)`.
    public var basePrice: Double {
        switch self {
        case .fable:  return 10e-6
        case .opus:   return 5e-6
        case .sonnet: return 3e-6
        case .haiku:  return 1e-6
        }
    }

    public var displayName: String {
        switch self {
        case .fable: return "Fable"
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        }
    }

    /// 모델명 → 단가. 카테고리 기본값(캐시읽기 0.1x)에서 벗어나는 모델만 예외.
    /// Fable 5.1 캐시읽기 0.025x($0.25/MTok) · Opus 5.5 $4, 캐시읽기 0.05x($0.20) · Sonnet 5 $2.
    public static func price(model: String?) -> ModelPrice {
        let m = (model ?? "").lowercased()
        if m.contains("fable-5-1") { return ModelPrice(base: 10e-6, cacheRead: 0.025) }
        if m.contains("opus-5-5") { return ModelPrice(base: 4e-6, cacheRead: 0.05) }
        if m.contains("sonnet-5") { return ModelPrice(base: 2e-6, cacheRead: 0.1) }
        return ModelPrice(base: from(model: m).basePrice, cacheRead: 0.1)
    }

    /// 모델명 문자열 → 카테고리. fable/opus/haiku 아니면 sonnet.
    public static func from(model: String?) -> ModelCategory {
        let m = (model ?? "").lowercased()
        if m.contains("fable") { return .fable }
        if m.contains("opus") { return .opus }
        if m.contains("haiku") { return .haiku }
        return .sonnet
    }
}
