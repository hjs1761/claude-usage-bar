import SwiftUI
import ClaudeUsageCore

@MainActor
final class AppState: ObservableObject {
    @Published var usage: UsageData?
    @Published var cost: UsageCost?
    @Published var lastUpdated: Date?
    @Published var isStale = false
    @Published var statusText = "—"

    private let client = UsageClient()
    private let aggregator = LogAggregator()
    private var timer: Timer?

    func start() {
        Task { await refresh() }
        // 우선 60초 폴링 (Task 11에서 설정 주기로 대체)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        // 로컬 비용 (네트워크 무관, 항상 갱신)
        self.cost = aggregator.compute()
        // 라이브 usage
        guard let creds = KeychainReader.readClaudeCodeToken() else {
            self.statusText = "로그인 필요"
            return
        }
        do {
            let d = try await client.fetch(token: creds.accessToken)
            self.usage = d
            self.lastUpdated = Date()
            self.isStale = false
            self.statusText = ""
        } catch {
            self.isStale = true   // 마지막 성공값 유지
        }
    }
}
