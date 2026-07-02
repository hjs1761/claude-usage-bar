import SwiftUI
import ClaudeUsageCore

struct DashboardView: View {
    @ObservedObject var state: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(showSettings ? "설정" : "Claude Max 사용량").font(.headline)
                Spacer()
                if showSettings {
                    Button("← 뒤로") { showSettings = false }.font(.callout)
                }
            }
            if !state.statusText.isEmpty && !showSettings {
                Text(state.statusText).font(.caption).foregroundStyle(.orange)
            }
            Divider()
            if showSettings {
                SettingsView(state: state)
            } else {
                limitsSection
                extraSection
                Divider()
                costSection
                Divider()
                footer
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    @ViewBuilder private var limitsSection: some View {
        if let limits = state.usage?.limits, !limits.isEmpty {
            ForEach(Array(limits.enumerated()), id: \.offset) { _, l in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(label(l)).font(.system(.callout, design: .monospaced))
                        Spacer()
                        if let p = l.percent {
                            Text("\(Int(p.rounded()))%").foregroundStyle(color(l)).monospacedDigit()
                        }
                        if let rem = l.remaining() {
                            Text(rem).foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    ProgressView(value: min(1.0, max(0, (l.percent ?? 0) / 100))).tint(color(l))
                }
            }
        } else {
            Text("표시할 한도 없음").foregroundStyle(.secondary).font(.callout)
        }
    }

    @ViewBuilder private var extraSection: some View {
        if let e = state.usage?.extraUsage, e.isEnabled == true {
            let u = e.utilization.map { "\(Int($0.rounded()))%" } ?? "활성"
            Text("추가 사용량 (extra)  \(u)").foregroundStyle(.purple).font(.callout)
        }
    }

    @ViewBuilder private var costSection: some View {
        if let c = state.cost {
            Text("💬 토큰 사용량 (로컬 로그 · API환산 추정)")
                .font(.caption).foregroundStyle(.secondary)
            costRow("오늘", c.day)
            costRow("이번 주", c.week)
            costRow("이번 달", c.month)
            ForEach(ModelCategory.allCases, id: \.self) { cat in
                if let b = c.byModel[cat], b.cost > 0 {
                    Text("  └ \(cat.displayName)  ~$\(fmtCost(b.cost)) · \(fmtTok(b.tokens))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func costRow(_ label: String, _ b: ModelBucket) -> some View {
        HStack {
            Text(label).font(.system(.callout, design: .monospaced))
            Spacer()
            Text("~$\(fmtCost(b.cost))  ·  \(fmtTok(b.tokens)) tok")
                .font(.system(.callout, design: .monospaced)).monospacedDigit()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = state.lastUpdated {
                Text("업데이트 \(t.formatted(date: .omitted, time: .standard))\(state.isStale ? " (캐시)" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("새로고침") { Task { await state.refresh() } }
                Button("설정") { showSettings = true }
                Button("claude.ai") { NSWorkspace.shared.open(URL(string: "https://claude.ai")!) }
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }.font(.callout)
        }
    }

    private func label(_ l: UsageData.Limit) -> String {
        switch l.kind {
        case "session": return "세션 (5h)"
        case "weekly_all": return "주간 (전체)"
        case "weekly_scoped": return "주간 \(l.scope?.model?.displayName ?? "")"
        default: return l.kind ?? "?"
        }
    }
    private func color(_ l: UsageData.Limit) -> Color {
        let p = l.percent ?? 0
        if l.severity == "critical" || p >= 90 { return .red }
        if l.severity == "warning" || p >= 70 { return .orange }
        return .primary
    }
    private func fmtCost(_ v: Double) -> String { String(format: "%.0f", v) }
    private func fmtTok(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1e6) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1e3) }
        return "\(n)"
    }
}
