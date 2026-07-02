import SwiftUI
import ClaudeUsageCore

@MainActor
final class AppState: ObservableObject {
    @Published var usage: UsageData?
    @Published var cost: UsageCost?
    @Published var lastUpdated: Date?
    @Published var isStale = false
    @Published var statusText = ""   // 행동 필요한 상태(로그인/토큰만료)만 채움
    @Published var rotateShowSession = true

    let settings = SettingsStore()
    private let client = UsageClient()
    private let aggregator = LogAggregator()
    private var timer: Timer?
    private var rotateTimer: Timer?

    func start() {
        Task { await refresh() }
        restartPolling()
        startRotation()
    }

    /// 설정 폴링 주기로 타이머 재설정.
    func restartPolling() {
        timer?.invalidate()
        let interval = TimeInterval(settings.pollSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// 순환 모드일 때만 4초마다 5h⇄1W 토글 (텍스트 스왑 — 값 없으면 재렌더 없음).
    func startRotation() {
        rotateTimer?.invalidate()
        guard settings.displayMode == .rotate else { return }
        rotateTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rotateShowSession.toggle() }
        }
    }

    func refresh() async {
        // 로컬 비용: 로그 파싱은 무거우니(수초) 반드시 백그라운드에서. 결과만 메인에 반영.
        let agg = aggregator
        let computed = await Task.detached(priority: .utility) { agg.compute() }.value
        self.cost = computed

        // 키체인 읽기(Process)도 동기 blocking → 백그라운드에서.
        let creds = await Task.detached(priority: .utility) {
            KeychainReader.readClaudeCodeToken()
        }.value
        guard let creds else {
            self.statusText = "로그인 필요"
            return
        }
        // client는 actor라 네트워크 호출은 이미 메인 밖에서 실행됨.
        do {
            let d = try await client.fetch(token: creds.accessToken)
            self.usage = d
            self.lastUpdated = Date()
            self.isStale = false
            self.statusText = ""
        } catch UsageError.http(let code) where (code == 401 || code == 403) && creds.isExpired(now: Date()) {
            // 행동 필요: 토큰 만료 → 안내 표시
            self.isStale = true
            self.statusText = "토큰 만료 — Claude Code 한 번 실행하면 갱신"
        } catch {
            // 429·네트워크·일시 오류 등: 조용히 stale 유지(자동 재시도). 메시지 안 띄움.
            self.isStale = true
        }
    }
}
