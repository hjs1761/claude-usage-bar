import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            // 팝오버 내용 (Task 9에서 DashboardView로 교체)
            VStack(alignment: .leading, spacing: 6) {
                Text("Claude Usage Bar").font(.headline)
                if !state.statusText.isEmpty {
                    Text(state.statusText).font(.caption).foregroundStyle(.orange)
                }
                Button("지금 새로고침") { Task { await state.refresh() } }
                Divider()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }
            .padding(8)
        } label: {
            MenuBarLabel(usage: state.usage)
                .onAppear { state.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
