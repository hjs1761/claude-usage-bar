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
                         sessionBurnImminent: state.sessionBurnImminent,
                         updateAvailable: state.updateStatus.isUpdateAvailable)
                .onAppear { state.start() }
        }
        .menuBarExtraStyle(.window)

        // 메뉴바 버튼으로 여는 상세 사용량 대시보드 (로컬 로그, 비샌드박스=직접 읽기)
        Window("Claude Code 사용량", id: "usage-dashboard") {
            UsageDashboardWindow()
        }
        .windowResizability(.contentSize)

        // 설정 — 별도 Window(MenuBarExtra 한 창에서 대시보드↔설정 토글 시 창이 안 줄어들어 뜨는 문제 회피)
        Window("설정", id: "settings") {
            SettingsView(state: state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // 문의하기 — 별도 Window(MenuBarExtra sheet은 텍스트 포커스 시 닫힘)
        Window("문의하기", id: "contact") {
            ContactWindowView(state: state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
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
