# 업데이트 알림 표시 (팝오버 배너 + 메뉴바 점) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** 새 버전이 있으면(자동확인으로 `updateStatus=.available`) 메뉴바 팝오버에 설치 배너를, 메뉴바 라벨엔 점(•)을 표시한다. 설정을 열지 않아도 인지 가능하게.

**Architecture:** 업데이트 확인 로직(AppState의 시작 시+하루1회 자동 `checkForUpdate`)은 그대로. `updateStatus`를 팝오버(DashboardView)와 메뉴바(MenuBarLabel)에서 **읽어 표시만** 추가. 순수 UI + 트리비얼 헬퍼.

**Tech Stack:** SwiftUI(MenuBarExtra), 무의존성. 작업 브랜치 `feat/update-available-indicator`(base v1.18=c6a2d66).

**설계(합의됨):** A안 — 팝오버 배너(.available→설치 / .downloading→진행 / .error→재시도) + 메뉴바 라벨 끝 `•`. [설치] 클릭=`installUpdate()`(다운로드→교체→앱 재실행, 기존 설정창 설치와 동일).

> ⚠ `UpdateStatus`는 앱 타깃(ClaudeUsageBar)에 있어 CoreTests(ClaudeUsageCore 전용)로 단위테스트 불가 → 검증=빌드 성공 + `swift run CoreTests` 회귀무 + 육안.

---

## Task 1: UpdateStatus.isUpdateAvailable 헬퍼

**Files:** Modify `Sources/ClaudeUsageBar/AppState.swift` (enum `UpdateStatus`, 현재 213-219줄)

- [ ] **Step 1: enum에 계산 프로퍼티 추가** — `UpdateStatus` 정의를 아래로 교체:

```swift
enum UpdateStatus: Equatable {
    case idle                    // 확인 전/최신
    case checking
    case available(tag: String)  // 새 버전 있음
    case downloading
    case error(String)

    /// 메뉴바 점·배너 표시용.
    var isUpdateAvailable: Bool { if case .available = self { return true } else { return false } }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `cd ~/projects/claude-usage-bar && swift build 2>&1 | tail -3`
Expected: 빌드 성공.

- [ ] **Step 3: 커밋**

```bash
git add Sources/ClaudeUsageBar/AppState.swift
git commit -m "feat(app): UpdateStatus.isUpdateAvailable 헬퍼"
```

---

## Task 2: 메뉴바 라벨에 점(•) 표시

**Files:** Modify `Sources/ClaudeUsageBar/MenuBarLabel.swift` (프로퍼티 10-14줄, `text` 60-78줄)

- [ ] **Step 1: 파라미터 추가** — `sessionBurnImminent` 선언 아래에 추가:

```swift
    var sessionBurnImminent = false   // 세션 소진 임박 → 세션 % 옆에 🔥
    var updateAvailable = false       // 새 버전 있음 → 라벨 끝에 • 표시
```

- [ ] **Step 2: `text`에 마커 추가** — `text`의 `return` 줄(현재 77줄)을 교체:

```swift
        // 세션 소진 임박 시 🔥를 맨 앞에, 새 버전 있으면 끝에 •
        return (sessionBurnImminent ? "🔥 " : "") + base + (updateAvailable ? " •" : "")
```

- [ ] **Step 3: 빌드 확인**

Run: `swift build 2>&1 | tail -3`
Expected: 성공. (호출부 인자 누락으로 실패하면 Task 3에서 해결 — 이 단계에선 `updateAvailable` 기본값 `false`라 기존 호출 그대로 컴파일됨)

- [ ] **Step 4: 커밋**

```bash
git add Sources/ClaudeUsageBar/MenuBarLabel.swift
git commit -m "feat(app): 메뉴바 라벨에 업데이트 점(•) — updateAvailable 파라미터"
```

---

## Task 3: App에서 updateAvailable 전달

**Files:** Modify `Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift` (MenuBarLabel 호출, 현재 13-16줄)

- [ ] **Step 1: 호출에 인자 추가** — `MenuBarLabel(...)` 호출을 교체:

```swift
            MenuBarLabel(usage: state.usage,
                         mode: state.displayMode,
                         rotateShowSession: state.rotateShowSession,
                         sessionBurnImminent: state.sessionBurnImminent,
                         updateAvailable: state.updateStatus.isUpdateAvailable)
                .onAppear { state.start() }
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build 2>&1 | tail -3`
Expected: 성공.

- [ ] **Step 3: 커밋**

```bash
git add Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift
git commit -m "feat(app): 메뉴바 라벨에 updateAvailable 전달"
```

---

## Task 4: 팝오버 업데이트 배너

**Files:** Modify `Sources/ClaudeUsageBar/DashboardView.swift` (body 26-42줄)

- [ ] **Step 1: body에 배너 삽입** — `body`의 statusText if-블록과 `Divider()` 사이에 `updateBanner` 추가:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Usage Monitor").font(.headline)
            if !state.statusText.isEmpty {
                Text(state.statusText).font(.caption).foregroundStyle(.orange)
            }
            updateBanner
            Divider()
            limitsSection
            extraSection
            Divider()
            costSection
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 340)
    }
```

- [ ] **Step 2: updateBanner 뷰 정의** — `body` 바로 아래에 추가:

```swift
    /// 새 버전 상태 배너: available=설치버튼 / downloading=진행 / error=재시도. 그 외 숨김.
    @ViewBuilder private var updateBanner: some View {
        switch state.updateStatus {
        case .available(let tag):
            HStack(spacing: 8) {
                Text("🆙 새 버전 \(tag)").font(.callout.weight(.semibold))
                Spacer()
                Button("설치") { Task { await state.installUpdate() } }
                    .controlSize(.small).buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("업데이트 설치 중… (완료 후 재실행)").font(.caption).foregroundStyle(.secondary)
            }
        case .error(let msg):
            HStack(spacing: 8) {
                Text("업데이트 실패").font(.caption).foregroundStyle(.red)
                    .help(msg)
                Spacer()
                Button("다시 시도") { Task { await state.installUpdate() } }.controlSize(.small)
            }
        case .idle, .checking:
            EmptyView()
        }
    }
```

- [ ] **Step 3: 빌드 확인**

Run: `swift build 2>&1 | tail -3`
Expected: 성공.

- [ ] **Step 4: 커밋**

```bash
git add Sources/ClaudeUsageBar/DashboardView.swift
git commit -m "feat(dashboard): 팝오버 업데이트 배너(설치/진행/재시도)"
```

---

## Task 5: 검증

- [ ] **Step 1: 전체 빌드 + 회귀 테스트**

Run: `swift build 2>&1 | tail -3 && swift run CoreTests 2>&1 | tail -3`
Expected: 빌드 성공 + CoreTests 전부 PASS(회귀 없음).

- [ ] **Step 2: 육안 확인(사용자)** — 설치 후: 새 버전이 있을 때(=현재 릴리즈보다 낮은 버전으로 빌드하면 재현) 팝오버 상단 `🆙 새 버전` 배너 + 메뉴바 라벨 끝 `•`. `.available`이 아니면 배너/점 없음.

---

## 배포 (검증 후)
1. main 머지: `git checkout main && git merge --no-ff feat/update-available-indicator`
2. 듀얼푸쉬: `git push origin main` (팀+개인)
3. 릴리즈: `git tag v1.19 && git push origin v1.19` → 두 레포 Actions 자동 빌드/릴리즈
4. 앱 [업데이트 확인] 또는 배너 [설치]로 반영.

## Self-Review
- 스펙 커버리지: 배너(Task 4)·메뉴바 점(Task 2·3)·헬퍼(Task 1)·검증(Task 5) — 설계 대응.
- 타입 일관성: `UpdateStatus.isUpdateAvailable`·`MenuBarLabel.updateAvailable`·`state.installUpdate()`(기존)·`state.updateStatus`(@Published) 일치.
- 기본값 `updateAvailable = false`로 Task 2→3 사이 컴파일 유지.
- 플레이스홀더 없음.
