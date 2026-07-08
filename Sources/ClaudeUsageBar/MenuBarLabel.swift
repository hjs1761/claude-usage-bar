import SwiftUI
import AppKit
import ClaudeUsageCore
import ClaudeUsageLive

/// 메뉴바 라벨. 값이 바뀔 때만 SwiftUI가 갱신 → 불필요 재렌더 없음.
/// ⚠ macOS 메뉴바의 Text 라벨은 시스템이 '단색'으로 강제 렌더 → foregroundStyle 색이 무시됨.
/// 그래서 경고(주황)/위험(빨강)은 색을 입힌 '비템플릿 이미지'로 렌더하고,
/// 정상 상태만 시스템 단색 Text로 둬서 라이트/다크에 자동 대응한다.
struct MenuBarLabel: View {
    let usage: UsageData?
    let mode: DisplayMode
    let rotateShowSession: Bool   // 순환 모드에서 지금 5h를 보여줄 차례인지
    var sessionBurnImminent = false   // 세션 소진 임박 → 세션 % 옆에 🔥

    var body: some View {
        switch severityLevel {
        case 2:
            Image(nsImage: Self.rendered(text, color: .systemRed)).renderingMode(.original)
        case 1:
            Image(nsImage: Self.rendered(text, color: .systemOrange)).renderingMode(.original)
        default:
            Text(text)   // 정상: 시스템 단색(라이트=검정/다크=흰색 자동)
        }
    }

    /// 텍스트를 색 입힌 비템플릿 이미지로 렌더 (해상도 독립 → retina 선명). 값 변할 때만 호출 → 비용 미미.
    /// SwiftUI가 메뉴바에서 이미지를 살짝 축소 표시 → 기본 Text(13pt)와 크기를 맞추려 15pt로 렌더.
    private static func rendered(_ s: String, color: NSColor) -> NSImage {
        let font = NSFont.systemFont(ofSize: 15)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let sz = (s as NSString).size(withAttributes: attrs)
        let img = NSImage(size: NSSize(width: ceil(sz.width), height: ceil(sz.height)),
                          flipped: false) { _ in
            (s as NSString).draw(at: .zero, withAttributes: attrs)
            return true
        }
        img.isTemplate = false   // 템플릿이면 단색 틴트됨 → false 로 색 유지
        return img
    }

    /// 현재 표시 중인 지표 기준 심각도. both 모드는 둘 중 더 위험한 쪽.
    private var severityLevel: Int {
        guard let u = usage else { return 0 }
        switch mode {
        case .sessionOnly: return level(u, "session")
        case .weeklyOnly:  return level(u, "weekly_all")
        case .rotate:      return level(u, rotateShowSession ? "session" : "weekly_all")
        case .both:        return max(level(u, "session"), level(u, "weekly_all"))
        }
    }
    private func level(_ u: UsageData, _ kind: String) -> Int {
        let l = u.limit(kind: kind)
        let p = l?.percent ?? 0
        if l?.severity == "critical" || p >= 90 { return 2 }
        if l?.severity == "warning"  || p >= 70 { return 1 }
        return 0
    }

    private var text: String {
        guard let u = usage else { return "◵" }
        let base: String
        switch mode {
        case .both:
            // 한 줄에 둘 다 → 너무 길어지지 않게 %만
            base = "\(seg(u, "session", "5h", time: false)) · \(seg(u, "weekly_all", "1W", time: false))"
        case .sessionOnly:
            base = seg(u, "session", "5h", time: true)
        case .weeklyOnly:
            base = seg(u, "weekly_all", "1W", time: true)
        case .rotate:
            base = rotateShowSession
                ? seg(u, "session", "5h", time: true)
                : seg(u, "weekly_all", "1W", time: true)
        }
        // 세션 소진 임박 시 🔥를 맨 앞에
        return (sessionBurnImminent ? "🔥 " : "") + base
    }

    /// "5h 34% · 12m" (time=true) 또는 "5h 34%" (time=false).
    private func seg(_ u: UsageData, _ kind: String, _ prefix: String, time: Bool) -> String {
        let l = u.limit(kind: kind)
        let p = l?.percent.map { "\(Int($0.rounded()))%" } ?? "—"
        if time, let rem = l?.remaining() {
            return "\(prefix) \(p) · \(rem)"
        }
        return "\(prefix) \(p)"
    }
}
