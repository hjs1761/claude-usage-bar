import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(state: state)
        } label: {
            MenuBarLabel(usage: state.usage,
                         mode: state.settings.displayMode,
                         rotateShowSession: state.rotateShowSession)
                .onAppear { state.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
