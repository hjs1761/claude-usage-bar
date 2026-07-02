import SwiftUI
import ClaudeUsageCore

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var mode: DisplayMode
    @State private var poll: Int
    @State private var throttle: Bool

    init(state: AppState) {
        self.state = state
        _mode = State(initialValue: state.settings.displayMode)
        _poll = State(initialValue: state.settings.pollSeconds)
        _throttle = State(initialValue: state.settings.chargingThrottle)
    }

    var body: some View {
        Form {
            Picker("메뉴바 표시", selection: $mode) {
                ForEach(DisplayMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .onChange(of: mode) { _, v in
                state.settings.displayMode = v
                state.startRotation()
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
        }
    }
}
