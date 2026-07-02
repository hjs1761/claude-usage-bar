import SwiftUI
import ClaudeUsageCore

/// 메뉴바 텍스트. 값이 바뀔 때만 SwiftUI가 갱신 → 불필요 재렌더 없음.
struct MenuBarLabel: View {
    let usage: UsageData?
    // Task 8: "둘 다 한 줄" 고정. 표시모드 선택은 Task 10에서 설정 연동.
    var body: some View {
        Text(text)
    }
    private var text: String {
        guard let u = usage else { return "◵" }
        let s = u.sessionPercent.map { "\(Int($0.rounded()))%" } ?? "—"
        let w = u.weeklyPercent.map { "\(Int($0.rounded()))%" } ?? "—"
        return "5h \(s) · 1W \(w)"
    }
}
