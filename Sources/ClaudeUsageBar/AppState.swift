import SwiftUI
import ClaudeUsageCore
import ClaudeUsageLive

@MainActor
final class AppState: ObservableObject {
    @Published var usage: UsageData?
    @Published var cost: UsageCost?
    @Published var lastUpdated: Date?
    @Published var isStale = false
    @Published var statusText = ""   // 행동 필요한 상태(로그인/토큰만료)만 채움
    @Published var rotateShowSession = true
    @Published var displayMode: DisplayMode = .rotate   // 즉시 UI 반영용(설정과 동기화)
    @Published var sessionBurn: BurnState = .none       // 세션 소진 예측(측정중/안정/도달/ETA)
    @Published var sessionBurnImminent = false          // 리셋 전 도달 예상 → 메뉴바 🔥 표시

    let settings = SettingsStore()

    init() {
        displayMode = settings.displayMode   // 저장된 값 복원
    }

    /// 표시모드 변경: @Published 갱신(즉시 반영) + 영속화 + 순환 재시작.
    func setDisplayMode(_ m: DisplayMode) {
        displayMode = m
        settings.displayMode = m
        startRotation()
    }
    private let client = UsageClient()
    private let aggregator = LogAggregator()
    private let burnEstimator = BurnEstimator()
    private var timer: Timer?
    private var rotateTimer: Timer?
    private var burnTimer: Timer?
    private var backoffUntil: Date?   // 429 등으로 네트워크 호출을 잠시 멈추는 시각

    /// 배터리 + 절전 시 네트워크 갱신 최소 간격(초). 로직과 설정 표시가 이 값을 공유.
    static let batteryThrottleSeconds: TimeInterval = 300

    func start() {
        Task { await refresh() }
        restartPolling()
        startRotation()
        startBurnRefresh()
    }

    /// 설정 폴링 주기로 타이머 재설정. (.common 모드 = 메뉴/팝업 열려있어도 계속 갱신)
    func restartPolling() {
        timer?.invalidate()
        let interval = TimeInterval(settings.pollSeconds)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 소진 예측을 30초마다 재계산(경과시간이 흐르므로 eta 갱신). .common=메뉴 열려있어도 동작.
    /// 네트워크와 무관 — 현재 로드된 스냅샷(%, 리셋시각)만으로 계산하므로 기기 간 동일.
    func startBurnRefresh() {
        burnTimer?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recomputeBurn() }
        }
        RunLoop.main.add(t, forMode: .common)
        burnTimer = t
        recomputeBurn()
    }

    /// 순환 모드일 때만 4초마다 5h⇄1W 토글 (텍스트 스왑 — 값 없으면 재렌더 없음).
    func startRotation() {
        rotateTimer?.invalidate()
        guard displayMode == .rotate else { return }
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
            if !onAC, let last = lastUpdated,
               Date().timeIntervalSince(last) < Self.batteryThrottleSeconds { return }
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
            recomputeBurn()   // 새 스냅샷 반영(즉시)
        } catch UsageError.http(429) {
            // rate limit → 3분 백오프. 데이터 있으면 조용히 stale, 없으면(=로그아웃 오해 방지) 명시.
            self.isStale = true
            self.backoffUntil = Date().addingTimeInterval(180)
            if self.usage == nil {
                self.statusText = "요청 제한(429) — 사용량 API 호출이 많아 잠시 대기 중, 자동 재시도"
            }
        } catch UsageError.http(let code) where code == 401 || code == 403 {
            self.isStale = true
            self.statusText = creds.isExpired(now: Date())
                ? "토큰 만료 — Claude Code 한 번 실행하면 갱신"
                : "인증 오류(\(code)) — Claude Code 재로그인 필요할 수 있음"
        } catch {
            self.isStale = true   // 네트워크 등 일시 오류: 조용히 재시도
        }
    }

    /// 현재 세션 스냅샷(%, 리셋까지 남은 초)만으로 소진 예측 재계산 → 같은 계정이면 3대 동일.
    private func recomputeBurn() {
        let l = usage?.limit(kind: "session")
        let st = burnEstimator.estimate(
            percent: l?.percent,
            secondsUntilReset: l?.secondsRemaining(),
            windowSeconds: BurnEstimator.sessionWindow)
        sessionBurn = st
        // eta는 이미 "리셋 전 도달"만 의미 → reached/eta면 임박(메뉴바 🔥)
        switch st {
        case .reached, .eta:
            sessionBurnImminent = true
        default:
            sessionBurnImminent = false
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
