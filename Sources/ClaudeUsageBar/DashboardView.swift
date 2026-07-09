import SwiftUI
import ClaudeUsageCore
import ClaudeUsageLive

struct DashboardView: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme

    // 심각도 색 — 다크는 선명색 유지, 라이트는 같은 계열의 어두운 톤(형광 방지·투명글래스 가독성)
    private var cNormal: Color { scheme == .dark ? .green  : Color(red: 0.16, green: 0.44, blue: 0.20) }
    private var cWarn:   Color { scheme == .dark ? .orange : Color(red: 0.80, green: 0.42, blue: 0.00) }
    private var cDanger: Color { scheme == .dark ? .red    : Color(red: 0.72, green: 0.12, blue: 0.12) }

    /// 색이 확실히 먹는 커스텀 진행바(ProgressView.tint가 시스템 강조색에 먹히는 문제 회피).
    private func bar(_ value: Double, _ color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Max 사용량").font(.headline)
            if !state.statusText.isEmpty {
                Text(state.statusText).font(.caption).foregroundStyle(.orange)
            }
            Divider()
            limitsSection
            extraSection
            Divider()
            costSection
            Divider()
            footer
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
                            Text("\(Int(p.rounded()))%")
                                .font(.system(.callout, design: .monospaced).weight(.semibold))
                                .foregroundStyle(color(l))
                                .monospacedDigit()
                        }
                        if let rem = l.remaining() {
                            Text(rem).foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    bar((l.percent ?? 0) / 100, color(l))
                    if l.kind == "session" { burnLine }   // 소진 예측(🔥) — 별도 작은 줄
                }
            }
        } else {
            Text("표시할 한도 없음").foregroundStyle(.secondary).font(.callout)
        }
    }

    /// 세션 소진 예측 한 줄. 🔥=한도 도달 예상(강조), 그 외는 회색 보조 안내.
    @ViewBuilder private var burnLine: some View {
        switch state.sessionBurn {
        case .eta(let secs):
            Text("🔥 이 속도면 ~\(Self.hm(secs)) 후 한도 도달")
                .font(.caption.weight(.semibold)).foregroundStyle(cDanger)   // 한도 도달 경고 → 빨강 계열
        case .reached:
            Text("🔥 한도 도달").font(.caption.weight(.semibold)).foregroundStyle(cDanger)
        case .stable:
            Text("소진 속도 안정 — 리셋 전 도달 안 함")
                .font(.caption).foregroundStyle(.primary)   // .secondary는 투명 글래스서 안 보임
        case .measuring:
            Text("소진 예측 측정 중…").font(.caption).foregroundStyle(.primary)
        case .none:
            EmptyView()
        }
    }

    /// 초 → "1h20m" / "20m".
    private static func hm(_ secs: TimeInterval) -> String {
        let s = max(0, Int(secs))
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))m" : "\(m)m"
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
            Button {
                openWindow(id: "usage-dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("상세 대시보드 열기", systemImage: "chart.bar.xaxis").frame(maxWidth: .infinity)
            }
            if let t = state.lastUpdated {
                Text("업데이트 \(t.formatted(date: .omitted, time: .standard))\(state.isStale ? " (캐시)" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("새로고침") { Task { await state.refresh() } }
                Button("설정") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "settings") }
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
        if l.severity == "critical" || p >= 90 { return cDanger }
        if l.severity == "warning" || p >= 70 { return cWarn }
        return cNormal   // 정상(<70%): 초록(다크=선명/라이트=어두운 톤)
    }
    private func fmtCost(_ v: Double) -> String { String(format: "%.0f", v) }
    private func fmtTok(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1e6) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1e3) }
        return "\(n)"
    }
}
