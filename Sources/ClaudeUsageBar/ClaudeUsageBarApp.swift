import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(state: state)
        } label: {
            MenuBarLabel(usage: state.usage)
                .onAppear { state.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
