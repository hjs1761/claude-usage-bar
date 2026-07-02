import Foundation

/// 견고한 ISO8601 파서. 실제 API/로그는 형식이 섞여 있음:
///   - 로그:  2026-06-30T06:21:14.686Z            (밀리초 + Z)
///   - usage: 2026-07-02T11:30:00.174256+00:00    (마이크로초 + 오프셋)
///   - 소수부 없음: 2026-07-02T15:00:00Z
/// 세 경우 모두 파싱. 실패 시 소수부를 제거하고 재시도.
public enum ISODate {
    private static let withFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parse(_ s: String) -> Date? {
        if let d = withFrac.date(from: s) { return d }
        if let d = plain.date(from: s) { return d }
        // 폴백: 소수부(.174256)를 제거하고 재시도 (마이크로초 등 자릿수 이슈 대비)
        if let range = s.range(of: #"\.\d+"#, options: .regularExpression) {
            var stripped = s
            stripped.removeSubrange(range)
            if let d = plain.date(from: stripped) { return d }
            if let d = withFrac.date(from: stripped) { return d }
        }
        return nil
    }
}
