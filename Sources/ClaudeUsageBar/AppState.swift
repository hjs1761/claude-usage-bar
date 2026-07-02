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
    private var backoffUntil: Date?   // 429 등으로 네트워크 호출을 잠시 멈추는 시각

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
        // 1) 로컬 비용: 무거운 로그 파싱은 백그라운드에서. 항상 갱신(네트워크 무관).
        let agg = aggregator
        self.cost = await Task.detached(priority: .utility) { agg.compute() }.value

        // 2) 429 백오프 중이면 네트워크 호출 스킵 (과도한 재호출 방지).
        if let until = backoffUntil, Date() < until { return }

        // 3) 충전 연동 절전: 배터리 + 최근 5분 내 갱신이면 네트워크 스킵.
        if settings.chargingThrottle {
            let onAC = await Task.detached(priority: .utility) { Self.isOnAC() }.value
            if !onAC, let last = lastUpdated, Date().timeIntervalSince(last) < 300 { return }
        }

        // 4) 키체인 읽기(Process, blocking) → 백그라운드.
        let creds = await Task.detached(priority: .utility) {
            KeychainReader.readClaudeCodeToken()
        }.value
        guard let creds else {
            self.statusText = "로그인 필요"
            return
        }

        // 5) usage 조회 (actor → 메인 밖 실행).
        do {
            let d = try await client.fetch(token: creds.accessToken)
            self.usage = d
            self.lastUpdated = Date()
            self.isStale = false
            self.statusText = ""
            self.backoffUntil = nil
        } catch UsageError.http(429) {
            // rate limit → 2분 백오프. 조용히 stale 유지.
            self.isStale = true
            self.backoffUntil = Date().addingTimeInterval(120)
        } catch UsageError.http(let code) where (code == 401 || code == 403) && creds.isExpired(now: Date()) {
            self.isStale = true
            self.statusText = "토큰 만료 — Claude Code 한 번 실행하면 갱신"
        } catch {
            self.isStale = true   // 네트워크 등 일시 오류: 조용히 재시도
        }
    }

    /// AC 전원(충전기) 연결 여부. 못 읽으면 true(안전: 갱신 유지).
    nonisolated static func isOnAC() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "ps"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return true }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.contains("AC Power")
    }
}
