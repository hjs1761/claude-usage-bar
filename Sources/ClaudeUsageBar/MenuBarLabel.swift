import SwiftUI
import ClaudeUsageCore

/// 메뉴바 텍스트. 값이 바뀔 때만 SwiftUI가 갱신 → 불필요 재렌더 없음.
struct MenuBarLabel: View {
    let usage: UsageData?
    let mode: DisplayMode
    let rotateShowSession: Bool   // 순환 모드에서 지금 5h를 보여줄 차례인지
    var body: some View { Text(text) }

    private var text: String {
        guard let u = usage else { return "◵" }
        switch mode {
        case .both:
            // 한 줄에 둘 다 → 너무 길어지지 않게 %만
            return "\(seg(u, "session", "5h", time: false)) · \(seg(u, "weekly_all", "1W", time: false))"
        case .sessionOnly:
            return seg(u, "session", "5h", time: true)
        case .weeklyOnly:
            return seg(u, "weekly_all", "1W", time: true)
        case .rotate:
            return rotateShowSession
                ? seg(u, "session", "5h", time: true)
                : seg(u, "weekly_all", "1W", time: true)
        }
    }

    /// "5h 34% · 12m" (time=true) 또는 "5h 34%" (time=false)
    private func seg(_ u: UsageData, _ kind: String, _ prefix: String, time: Bool) -> String {
        let l = u.limit(kind: kind)
        let p = l?.percent.map { "\(Int($0.rounded()))%" } ?? "—"
        if time, let rem = l?.remaining() {
            return "\(prefix) \(p) · \(rem)"
        }
        return "\(prefix) \(p)"
    }
}
