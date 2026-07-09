import SwiftUI
import AppKit
import ClaudeUsageCore

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var poll: Int
    @State private var throttle: Bool
    @State private var onAC = true
    @Environment(\.openWindow) private var openWindow

    init(state: AppState) {
        self.state = state
        _poll = State(initialValue: state.settings.pollSeconds)
        _throttle = State(initialValue: state.settings.chargingThrottle)
    }

    var body: some View {
        Form {
            Picker("메뉴바 표시", selection: Binding(
                get: { state.displayMode },
                set: { state.setDisplayMode($0) })) {
                ForEach(DisplayMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }

            Picker("새로고침 주기", selection: $poll) {
                Text("30초").tag(30); Text("1분").tag(60); Text("2분").tag(120)
                Text("5분").tag(300); Text("10분").tag(600)
            }
            .onChange(of: poll) { _, v in
                state.settings.pollSeconds = v
                state.restartPolling()
            }

            Toggle("충전 연동 절전 (배터리일 때 완화)", isOn: $throttle)
                .onChange(of: throttle) { _, v in state.settings.chargingThrottle = v }
            if throttle {
                Text(onAC
                     ? "현재: 충전 중 · \(intervalLabel(poll))마다 갱신"
                     : "현재: 배터리 · 약 \(Int(AppState.batteryThrottleSeconds / 60))분마다 갱신 (절전 · 로컬 비용은 계속)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { LoginItem.isEnabled },
                set: { LoginItem.set($0) }))
            Divider()
            HStack {
                Text("버전 \(state.currentVersionString)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                switch state.updateStatus {
                case .idle:
                    Button("업데이트 확인") { Task { await state.checkForUpdate() } }.font(.callout)
                case .checking:
                    Text("확인 중…").font(.caption).foregroundStyle(.secondary)
                case .available(let tag):
                    Button("\(tag) 설치") { Task { await state.installUpdate() } }
                        .font(.callout).buttonStyle(.borderedProminent)
                case .downloading:
                    Text("다운로드 중…").font(.caption).foregroundStyle(.secondary)
                case .error(let m):
                    Text(m).font(.caption).foregroundStyle(.red)
                }
            }
            Button("문의하기") {
                NSApp.activate(ignoringOtherApps: true)   // 액세서리 앱 → 새 창을 앞으로
                openWindow(id: "contact")
            }
                .font(.callout)
                .disabled(!state.contactConfigured)
        }
        .task {
            // 설정 열려있는 동안 2초마다 전원 상태 재확인 → 충전기 꽂/뺌 거의 실시간 반영.
            while !Task.isCancelled {
                onAC = await Task.detached(priority: .utility) { AppState.isOnAC() }.value
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func intervalLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)초" : "\(seconds / 60)분"
    }
}
