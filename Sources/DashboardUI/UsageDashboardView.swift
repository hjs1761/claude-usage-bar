import SwiftUI
import Charts
import ClaudeUsageCore

let kModelColors: [String: Color] = ["Opus": .purple, "Sonnet": .blue, "Haiku": .teal]

/// 공유 사용량 대시보드. `onChangeFolder`가 nil이면 폴더 변경 UI를 숨긴다(개인용 앱).
public struct UsageDashboardView: View {
    @ObservedObject var model: DashboardModel
    let onChangeFolder: (() -> Void)?
    @State private var hoverPoint: SeriesPoint?
    @State private var detailProject: ProjectRow?

    public init(model: DashboardModel, onChangeFolder: (() -> Void)? = nil) {
        self.model = model
        self.onChangeFolder = onChangeFolder
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.isEmpty && !model.isLoading {
                    emptyState
                } else {
                    summaryCards
                    insightLine
                    trendCard
                    HStack(alignment: .top, spacing: 16) { modelCard; projectCard }
                }
                footer
            }
            .padding(20)
        }
        .frame(minWidth: 760, minHeight: 680)
        .sheet(item: $detailProject) { row in ProjectDetailView(model: model, rawKey: row.raw) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code 사용량").font(.title2.bold())
                Text("로컬 로그 기반 · 비용은 추정치").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
            Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }.help("새로고침")
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            stat("이번 달", model.cost.month, .purple)
            stat("이번 주", model.cost.week, .blue)
            stat("오늘", model.cost.day, .teal)
        }
    }
    private func stat(_ title: String, _ b: ModelBucket, _ accent: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Text(Fmt.usd(b.cost)).font(.system(.title, design: .rounded).weight(.bold))
                Text("\(Fmt.tokens(b.tokens)) tokens").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var insightLine: some View {
        HStack(spacing: 14) {
            Label("\(model.periodShort) 캐시 토큰 \(Int((model.cacheRatio * 100).rounded()))%",
                  systemImage: "arrow.triangle.2.circlepath")
            if let oldest = model.oldestDayKey {
                Label("데이터 시작 \(Fmt.shortDay(oldest))", systemImage: "calendar")
            }
            Spacer()
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Trend (드릴다운)
    private var trendCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("비용 추이").font(.headline)
                    Spacer()
                    Text(model.canDrillDown ? "막대 클릭 → 상세" : "시간대별 (최하위)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                breadcrumbBar
                HStack(spacing: 10) {
                    Button { hoverPoint = nil; model.lateral(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless).disabled(!model.canLateralBack)
                    Text(model.rangeTitle).font(.subheadline.weight(.medium))
                        .frame(minWidth: 180).multilineTextAlignment(.center)
                    Button { hoverPoint = nil; model.lateral(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless).disabled(!model.canLateralForward)
                    Spacer()
                    Text("합계 \(Fmt.usd(model.seriesTotal)) · \(model.avgLabel) \(Fmt.usd(model.seriesAvg))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                chart
            }
        }
    }
    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.breadcrumbs.enumerated()), id: \.element.id) { idx, crumb in
                if idx > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                let isLast = idx == model.breadcrumbs.count - 1
                Button { hoverPoint = nil; model.popTo(depth: crumb.id) } label: {
                    Text(crumb.label).font(.caption)
                        .foregroundStyle(isLast ? Color.primary : Color.accentColor)
                }
                .buttonStyle(.plain).disabled(isLast)
            }
            Spacer()
        }
    }
    private var chart: some View {
        Chart {
            ForEach(model.series) { p in
                BarMark(x: .value("구간", p.label), y: .value("비용", p.cost))
                    .foregroundStyle(.tint)
                    .opacity(hoverPoint == nil || hoverPoint?.id == p.id ? 1 : 0.3)
            }
            if let hp = hoverPoint {
                RuleMark(x: .value("구간", hp.label))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) { tooltip(hp) }
            }
        }
        .chartXScale(domain: model.series.map(\.label))   // 균등 칸(카테고리) + 순서 유지
        .chartXAxis {
            AxisMarks(values: model.axisTickLabels) { value in
                AxisGridLine()
                AxisValueLabel { if let s = value.as(String.self) { Text(model.axisLabel(s)) } }
            }
        }
        .frame(height: 210)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt):
                            guard let plot = proxy.plotFrame else { hoverPoint = nil; return }
                            if let label: String = proxy.value(atX: pt.x - geo[plot].origin.x) {
                                hoverPoint = model.point(label: label)
                            }
                        case .ended: hoverPoint = nil
                        }
                    }
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard model.canDrillDown, let plot = proxy.plotFrame else { return }
                        if let label: String = proxy.value(atX: value.location.x - geo[plot].origin.x),
                           let p = model.point(label: label) {
                            hoverPoint = nil; model.drill(p)
                        }
                    })
            }
        }
    }
    private func tooltip(_ p: SeriesPoint) -> some View {
        VStack(spacing: 1) {
            Text(model.pointLabel(p)).font(.caption2).foregroundStyle(.secondary)
            Text(Fmt.usd(p.cost)).font(.caption.bold().monospacedDigit())
            Text("\(Fmt.tokens(p.tokens)) tok").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.25)))
    }

    private var modelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("모델별 (\(model.periodShort))").font(.headline)
                if model.modelSlices.isEmpty { placeholder } else {
                    ZStack {
                        Chart(model.modelSlices) { s in
                            SectorMark(angle: .value("비용", s.cost), innerRadius: .ratio(0.62), angularInset: 1.5)
                                .foregroundStyle(kModelColors[s.name] ?? .gray)
                        }
                        .frame(height: 180)
                        VStack(spacing: 0) {
                            Text(model.periodShort).font(.caption2).foregroundStyle(.secondary)
                            Text(Fmt.usd(model.focusedTotal.cost))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                        }
                    }
                    modelLegend
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private var modelLegend: some View {
        let total = max(model.focusedTotal.cost, 0.000001)
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(model.modelSlices) { s in
                HStack(spacing: 6) {
                    Circle().fill(kModelColors[s.name] ?? .gray).frame(width: 8, height: 8)
                    Text(s.name).font(.caption)
                    Spacer()
                    Text("\(Fmt.usd(s.cost)) · \(Int((s.cost / total * 100).rounded()))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var projectCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("프로젝트별 (\(model.periodShort))").font(.headline)
                    Spacer()
                    Text("클릭 → 상세").font(.caption2).foregroundStyle(.tertiary)
                }
                if model.projectRanking.isEmpty { placeholder } else {
                    let maxCost = model.projectRanking.map(\.cost).max() ?? 1
                    VStack(spacing: 8) {
                        ForEach(model.projectRanking) { row in
                            Button { detailProject = row } label: { projectRow(row, maxCost: maxCost) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private func projectRow(_ row: ProjectRow, maxCost: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(row.name).font(.callout).lineLimit(1)
                Spacer()
                Text(Fmt.usd(row.cost)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4).fill(Color.accentColor)
                        .frame(width: max(6, geo.size.width * CGFloat(row.cost / maxCost)))
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 3).contentShape(Rectangle())
    }

    private var placeholder: some View {
        Text("데이터 없음").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180)
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("표시할 사용량이 없습니다").font(.headline)
            Text("`~/.claude/projects` 에서 Claude Code 로그(*.jsonl)를 찾지 못했어요.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).font(.callout)
            if let change = onChangeFolder { Button("폴더 변경") { change() } }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    private var footer: some View {
        HStack(spacing: 6) {
            if let u = model.lastUpdated { Text("갱신 \(u.formatted(date: .omitted, time: .shortened))") }
            if let path = model.folderPath { Text("· \(path)").lineLimit(1).truncationMode(.middle) }
            Spacer()
            if let change = onChangeFolder { Button("폴더 변경") { change() }.buttonStyle(.link) }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - 프로젝트 상세 시트

struct ProjectDetailView: View {
    @ObservedObject var model: DashboardModel
    let rawKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let d = model.detail(for: rawKey)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).font(.title2.bold())
                    Text(rawKey).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 10) {
                miniStat("이번 달", d.cost.month); miniStat("이번 주", d.cost.week); miniStat("오늘", d.cost.day)
            }
            Text("일별 (최근 30일)").font(.headline)
            Chart(d.daily) { p in
                BarMark(x: .value("날짜", p.date, unit: .day), y: .value("비용", p.cost)).foregroundStyle(.tint)
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            .frame(height: 170)
            if !d.cost.byModel.isEmpty {
                Text("모델별").font(.headline)
                ForEach(d.cost.byModel.sorted { $0.value.cost > $1.value.cost }, id: \.key) { cat, b in
                    HStack(spacing: 6) {
                        Circle().fill(kModelColors[cat.displayName] ?? .gray).frame(width: 8, height: 8)
                        Text(cat.displayName).font(.callout)
                        Spacer()
                        Text("\(Fmt.usd(b.cost)) · \(Fmt.tokens(b.tokens)) tok")
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20).frame(width: 540, height: 580)
    }
    private func miniStat(_ t: String, _ b: ModelBucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(Fmt.usd(b.cost)).font(.system(.title3, design: .rounded).weight(.bold))
            Text("\(Fmt.tokens(b.tokens)) tok").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

/// 카드 컨테이너.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}
