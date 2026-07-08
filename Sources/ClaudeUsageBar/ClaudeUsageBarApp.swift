import SwiftUI
import ClaudeUsageCore
import DashboardUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(state: state)
        } label: {
            MenuBarLabel(usage: state.usage,
                         mode: state.displayMode,
                         rotateShowSession: state.rotateShowSession,
                         sessionBurnImminent: state.sessionBurnImminent)
                .onAppear { state.start() }
        }
        .menuBarExtraStyle(.window)

        // 메뉴바 버튼으로 여는 상세 사용량 대시보드 (로컬 로그, 비샌드박스=직접 읽기)
        Window("Claude Code 사용량", id: "usage-dashboard") {
            UsageDashboardWindow()
        }
        .windowResizability(.contentSize)
    }
}

/// 대시보드 창 컨텐츠. 개인용 앱은 샌드박스가 아니라 ~/.claude/projects를 직접 읽는다
/// (온보딩/북마크 불필요). compute()와 인덱스 충돌 피하려 별도 index 파일 사용.
struct UsageDashboardWindow: View {
    @StateObject private var model = DashboardModel(
        folderPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects").path
    ) {
        let idx = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar/dashboard-index.json")
        return LogAggregator(indexPath: idx).computeDashboard()
    }

    var body: some View {
        UsageDashboardView(model: model)
            .onAppear { model.reload() }
    }
}
