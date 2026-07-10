# 프로젝트 귀속 비교 탭 (cwd vs 파일-터치) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 대시보드 "프로젝트별" 카드에 세그먼트 탭 `[①cwd][②파일-터치]`를 넣어 Claude Code 토큰을 두 방식으로 나눠 비교한다.

**Architecture:** ②는 순수 로직(`FileAttribution`)으로 assistant 턴의 tool_use 파일경로 → 프로젝트명(dominant) 추정. 파일-신호 없는 턴은 세션 내 직전값 승계(sticky, `LogAggregator`에서 순차 처리). `UsageEntry`에 `projectByFiles` 한 필드만 추가하고, 대시보드는 기존 범용 `CostRollup.totals(by:)`에 keyer만 바꿔 재집계.

**Tech Stack:** Swift 5.9 / SwiftPM, SwiftUI(MenuBarExtra), 커스텀 CoreTests 하네스(`swift run CoreTests`). 무의존성.

**참고 스펙:** `docs/superpowers/specs/2026-07-10-project-attribution-tabs-design.md`

**작업 브랜치:** `feat/project-attribution-tabs` (개인깃 base v1.17=bd0ccea). 커밋은 이 브랜치에.

---

## 파일 구조

- **신규** `Sources/ClaudeUsageCore/FileAttribution.swift` — ② 순수 로직(경로추출·taxonomy·dominant). 테스트 대상.
- **신규** `Sources/CoreTests/FileAttributionTests.swift` — 위 + sticky 검증.
- **수정** `Sources/ClaudeUsageCore/LogModels.swift` — `UsageEntry.projectByFiles` 필드.
- **수정** `Sources/ClaudeUsageCore/LogParser.swift` — 턴별 raw 파일-프로젝트 계산(`home` 주입).
- **수정** `Sources/ClaudeUsageCore/LogAggregator.swift` — sticky 패스 + 캐시 필드 + parseLine 호출부.
- **수정** `Sources/DashboardUI/DashboardModel.swift` — `projectMode` + 분기 집계.
- **수정** `Sources/DashboardUI/UsageDashboardView.swift` — projectCard 세그먼트 탭.
- **수정** `Sources/CoreTests/main.swift` — 테스트 등록.

---

## Task 1: FileAttribution — 순수 로직 + 테스트

**Files:**
- Create: `Sources/ClaudeUsageCore/FileAttribution.swift`
- Test: `Sources/CoreTests/FileAttributionTests.swift`
- Modify: `Sources/CoreTests/main.swift`

- [ ] **Step 1: 실패 테스트 작성** — `Sources/CoreTests/FileAttributionTests.swift`

```swift
import Foundation
import ClaudeUsageCore

func testFileAttribution(_ h: Harness) {
    let home = "/Users/hjs"

    h.run("FileAttribution.project (taxonomy)") {
        h.expectEqual(FileAttribution.project(forPath: "/Users/hjs/develop/네오팜운영/bo/x.php", home: home),
                      "네오팜운영", "develop 하위 파일 → 하위폴더명")
        h.expectEqual(FileAttribution.project(forPath: "~/projects/ledger/app/a.swift", home: home),
                      "ledger", "틸드 projects 하위")
        h.expectEqual(FileAttribution.project(forPath: "/Users/hjs/projects/ledger", home: home),
                      "ledger", "프로젝트 루트 디렉토리(확장자 없음) → 인정")
        h.expectNil(FileAttribution.project(forPath: "/Users/hjs/develop/readme.md", home: home),
                    "루트 직속 파일(확장자) → nil")
        h.expectNil(FileAttribution.project(forPath: "/tmp/x.php", home: home), "홈 밖 → nil")
    }

    h.run("FileAttribution.extractPaths") {
        let content: [Any] = [
            ["type": "text", "text": "hi"],
            ["type": "tool_use", "name": "Edit",
             "input": ["file_path": "/Users/hjs/develop/네오팜운영/a.php"]],
            ["type": "tool_use", "name": "Bash",
             "input": ["command": "grep -rn foo ~/projects/ledger/app | head"]],
        ]
        let paths = FileAttribution.extractPaths(fromContent: content)
        h.expect(paths.contains("/Users/hjs/develop/네오팜운영/a.php"), "Edit file_path 추출")
        h.expect(paths.contains { $0.hasPrefix("~/projects/ledger/app") }, "Bash 경로 추출")
    }

    h.run("FileAttribution.dominant") {
        let paths = ["/Users/hjs/develop/네오팜운영/a.php",
                     "/Users/hjs/develop/네오팜운영/b.php",
                     "/Users/hjs/projects/ledger/c.swift"]
        h.expectEqual(FileAttribution.dominant(paths: paths, home: home), "네오팜운영", "최다=네오팜운영")
        h.expectNil(FileAttribution.dominant(paths: ["/tmp/x"], home: home), "매칭 없음 → nil")
        // 동수 → 첫 등장 우선
        let tie = ["/Users/hjs/projects/ledger/a", "/Users/hjs/develop/네오팜운영/b"]
        h.expectEqual(FileAttribution.dominant(paths: tie, home: home), "ledger", "동수 → 첫 등장")
    }
}
```

- [ ] **Step 2: main.swift에 등록** — `Sources/CoreTests/main.swift`, `h.finish()` 바로 위에 추가:

```swift
// MARK: - FileAttribution
testFileAttribution(h)
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `cd ~/projects/claude-usage-bar && swift run CoreTests 2>&1 | tail -5`
Expected: 컴파일 에러 `cannot find 'FileAttribution' in scope`.

- [ ] **Step 4: 구현** — `Sources/ClaudeUsageCore/FileAttribution.swift`

```swift
import Foundation

/// ② 파일-터치 기준 프로젝트 귀속의 순수 로직.
/// assistant 턴의 tool_use에서 파일/디렉토리 경로를 뽑아 프로젝트명(dominant)을 추정한다.
public enum FileAttribution {
    /// 작업영역 루트 — 이 하위 첫 세그먼트가 프로젝트명. (개인 환경 기준)
    static let roots = ["develop", "projects"]

    /// assistant 메시지 `content[]`의 tool_use 블록에서 경로 추출.
    ///   Read/Edit/Write/MultiEdit/NotebookEdit → input.file_path
    ///   Grep/Glob → input.path
    ///   Bash → input.command 안의 `~/…`·`/Users/…` 경로 토큰
    public static func extractPaths(fromContent content: [Any]) -> [String] {
        var out: [String] = []
        for block in content {
            guard let b = block as? [String: Any],
                  (b["type"] as? String) == "tool_use",
                  let input = b["input"] as? [String: Any] else { continue }
            switch (b["name"] as? String) ?? "" {
            case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit":
                if let p = input["file_path"] as? String { out.append(p) }
            case "Grep", "Glob":
                if let p = input["path"] as? String { out.append(p) }
            case "Bash":
                if let cmd = input["command"] as? String { out.append(contentsOf: pathsInCommand(cmd)) }
            default:
                break
            }
        }
        return out
    }

    /// Bash 명령어 문자열에서 `~/…` 및 `/Users/<user>/…` 경로 토큰을 정규식으로 추출.
    static func pathsInCommand(_ cmd: String) -> [String] {
        let pattern = #"(~|/Users/[^/\s]+)(/[^\s'"|;&)>]+)+"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = cmd as NSString
        return re.matches(in: cmd, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    /// 절대/틸드 경로 → 프로젝트명. roots 하위 폴더명. 매칭 안 되면 nil(→호출측 폴백).
    ///   ~/develop/네오팜운영/x.php → 네오팜운영
    ///   ~/projects/ledger         → ledger (확장자 없는 프로젝트 루트 디렉토리)
    ///   ~/develop/readme.md       → nil   (루트 직속 파일)
    public static func project(forPath path: String, home: String) -> String? {
        var p = path
        if p == "~" { p = home }
        else if p.hasPrefix("~/") { p = home + "/" + p.dropFirst(2) }
        let homeSlash = home.hasSuffix("/") ? home : home + "/"
        guard p.hasPrefix(homeSlash) else { return nil }
        let segs = p.dropFirst(homeSlash.count)
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard segs.count >= 2, roots.contains(segs[0]) else { return nil }
        // 루트 직속 파일(develop/readme.md)은 프로젝트 아님. 하위폴더가 있거나(≥3)
        // segs[1]이 확장자 없는 폴더명이면 프로젝트로 인정.
        if segs.count == 2 && segs[1].contains(".") { return nil }
        return segs[1]
    }

    /// 경로들 → 프로젝트들 → 최다(dominant). 동수면 첫 등장 우선. 없으면 nil.
    public static func dominant(paths: [String], home: String) -> String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for path in paths {
            guard let proj = project(forPath: path, home: home) else { continue }
            if counts[proj] == nil { order.append(proj) }
            counts[proj, default: 0] += 1
        }
        guard let maxCount = counts.values.max() else { return nil }
        return order.first { counts[$0] == maxCount }
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift run CoreTests 2>&1 | tail -5`
Expected: 전체 PASS (FileAttribution 그룹 포함).

- [ ] **Step 6: 커밋**

```bash
git add Sources/ClaudeUsageCore/FileAttribution.swift Sources/CoreTests/FileAttributionTests.swift Sources/CoreTests/main.swift
git commit -m "feat(core): FileAttribution — 파일-터치 기준 프로젝트 귀속 순수 로직 + 테스트"
```

---

## Task 2: UsageEntry에 projectByFiles 필드 추가

**Files:**
- Modify: `Sources/ClaudeUsageCore/LogModels.swift:3-24`

- [ ] **Step 1: 필드 + 이니셜라이저 기본값 추가** — `UsageEntry`에 `projectByFiles` 추가. 기본값 `""`로 기존 호출부 호환.

기존 (`LogModels.swift:11`, `18-24`) 를 아래로 교체:

```swift
    public let dedupKey: String      // "\(msgId)|\(requestId)"
    public let project: String       // ① cwd 기준. ~/.claude/projects/{folder}, 미상이면 ""
    public var projectByFiles: String // ② 파일-터치 기준. sticky 적용 후 값, 미상이면 ""
    public let hour: Int             // 0~23 (로컬) — 시간대별 드릴다운용
    public var tokens: Int { input + output + cacheWrite + cacheRead }

    public init(dayKey: String, category: ModelCategory, input: Int, output: Int,
                cacheWrite: Int, cacheRead: Int, cost: Double, dedupKey: String,
                project: String = "", projectByFiles: String = "", hour: Int = 0) {
        self.dayKey = dayKey; self.category = category
        self.input = input; self.output = output
        self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
        self.cost = cost; self.dedupKey = dedupKey
        self.project = project; self.projectByFiles = projectByFiles; self.hour = hour
    }
```

- [ ] **Step 2: 컴파일 확인** (기본값 덕에 기존 호출부 무변경)

Run: `swift build 2>&1 | tail -5`
Expected: 빌드 성공(경고 무관).

- [ ] **Step 3: 커밋**

```bash
git add Sources/ClaudeUsageCore/LogModels.swift
git commit -m "feat(core): UsageEntry.projectByFiles 필드(② 파일-터치 기준) 추가"
```

---

## Task 3: LogParser — 턴별 raw 파일-프로젝트 계산

**Files:**
- Modify: `Sources/ClaudeUsageCore/LogParser.swift:14-50`

- [ ] **Step 1: 실패 테스트 작성** — `Sources/CoreTests/FileAttributionTests.swift`의 `testFileAttribution` 안에 그룹 추가:

```swift
    h.run("LogParser.projectByFiles (raw, 턴단위)") {
        let home = "/Users/hjs"
        // usage + Edit(네오팜운영) 있는 assistant 라인
        let line = #"""
        {"type":"assistant","timestamp":"2026-07-10T01:00:00.000Z","message":{"model":"claude-sonnet-4","id":"m1","usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/hjs/develop/네오팜운영/a.php"}}]}}
        """#.replacingOccurrences(of: "\n", with: "")
        let e = LogParser.parseLine(line, project: "develop", home: home)
        h.expectEqual(e?.projectByFiles, "네오팜운영", "턴 내 Edit → 네오팜운영")
        // 파일 신호 없는 턴 → raw ""
        let line2 = #"{"type":"assistant","timestamp":"2026-07-10T01:00:00.000Z","message":{"model":"claude-sonnet-4","id":"m2","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"hi"}]}}"#
        h.expectEqual(LogParser.parseLine(line2, project: "develop", home: home)?.projectByFiles, "", "파일 없음 → raw \"\"")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `swift run CoreTests 2>&1 | tail -5`
Expected: 컴파일 에러(`parseLine`에 `home:` 인자 없음) 또는 FAIL.

- [ ] **Step 3: parseLine 시그니처·본문 수정** — `LogParser.swift`

`parseLine` 선언(`:14`)을 교체:

```swift
    public static func parseLine(_ line: String, project: String = "", home: String = "") -> UsageEntry? {
```

그리고 `return UsageEntry(...)`(현재 `:47-49`) 직전에 파일-프로젝트 계산 추가하고 반환에 필드 추가:

```swift
        let content = (msg["content"] as? [Any]) ?? []
        let rawFileProj = FileAttribution.dominant(paths: FileAttribution.extractPaths(fromContent: content),
                                                   home: home) ?? ""
        return UsageEntry(dayKey: dayKey, category: cat, input: i, output: o,
                          cacheWrite: cw, cacheRead: cr, cost: cost,
                          dedupKey: dedup, project: project, projectByFiles: rawFileProj, hour: hour)
```

- [ ] **Step 4: 통과 확인**

Run: `swift run CoreTests 2>&1 | tail -5`
Expected: 전체 PASS.

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeUsageCore/LogParser.swift Sources/CoreTests/FileAttributionTests.swift
git commit -m "feat(core): LogParser가 턴별 파일-프로젝트(raw) 계산"
```

---

## Task 4: LogAggregator — sticky 승계 + 캐시 + 호출부

**Files:**
- Modify: `Sources/ClaudeUsageCore/LogAggregator.swift` (Cached `:31-35`, loadEntries `:84-95`, parseFile `:119-129`, toCached `:131-135`, toEntry `:136-142`)

- [ ] **Step 1: 실패 테스트 작성(applySticky)** — `FileAttributionTests.swift`의 `testFileAttribution` 안에 추가:

```swift
    h.run("LogAggregator.applySticky") {
        func mk(_ pf: String, _ id: String) -> UsageEntry {
            UsageEntry(dayKey: "2026-07-10", category: .sonnet, input: 1, output: 1,
                       cacheWrite: 0, cacheRead: 0, cost: 0, dedupKey: id,
                       project: "develop", projectByFiles: pf, hour: 0)
        }
        let input = [mk("", "a"), mk("ledger", "b"), mk("", "c"), mk("네오팜운영", "d"), mk("", "e")]
        let out = LogAggregator.applySticky(input, fallback: "develop")
        h.expect(out.map { $0.projectByFiles } == ["develop", "ledger", "ledger", "네오팜운영", "네오팜운영"],
                 "앞부분 무신호→fallback, 이후 무신호→직전 승계")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `swift run CoreTests 2>&1 | tail -5`
Expected: 컴파일 에러(`applySticky` 없음).

- [ ] **Step 3: applySticky 구현** — `LogAggregator.swift` 안(예: `cwdName` 아래)에 추가:

```swift
    /// ② 파일신호 없는 턴은 세션(파일) 내 직전 확정값 승계, 세션 앞부분은 cwd로 폴백.
    /// 입력은 파일 내 등장 순서. 순수 함수(테스트 대상).
    public static func applySticky(_ entries: [UsageEntry], fallback: String) -> [UsageEntry] {
        var last = ""
        return entries.map { entry in
            var e = entry
            if e.projectByFiles.isEmpty {
                e.projectByFiles = last.isEmpty ? fallback : last
            } else {
                last = e.projectByFiles
            }
            return e
        }
    }
```

- [ ] **Step 4: parseFile에서 sticky 적용 + home 주입** — `parseFile`(`:119-129`) 전체 교체:

```swift
    private func parseFile(_ path: String, project: String) -> [UsageEntry] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var out: [UsageEntry] = []
        var seen = Set<String>()
        content.enumerateLines { line, _ in
            if let e = LogParser.parseLine(line, project: project, home: home),
               seen.insert(e.dedupKey).inserted {
                out.append(e)
            }
        }
        // 파일(=세션) 단위 순차 sticky. fallback = ① cwd 프로젝트.
        return Self.applySticky(out, fallback: project)
    }
```

- [ ] **Step 5: 캐시에 projectByFiles 저장/복원** — `Cached`(`:31-35`)에 필드 추가:

```swift
    struct Cached: Codable {
        var dayKey: String; var category: String
        var input: Int; var output: Int; var cacheWrite: Int; var cacheRead: Int
        var cost: Double; var dedupKey: String; var hour: Int
        var projectByFiles: String = ""   // ② 값(내용기반이라 캐시 가능). ①은 위치서 재도출.
    }
```

`toCached`(`:131-135`) 교체:

```swift
    private func toCached(_ e: UsageEntry) -> Cached {
        Cached(dayKey: e.dayKey, category: e.category.rawValue, input: e.input,
               output: e.output, cacheWrite: e.cacheWrite, cacheRead: e.cacheRead,
               cost: e.cost, dedupKey: e.dedupKey, hour: e.hour, projectByFiles: e.projectByFiles)
    }
```

`toEntry`(`:136-142`) 교체(② 는 캐시값, ① project는 인자로 받은 현재 위치값):

```swift
    private func toEntry(_ c: Cached, project: String) -> UsageEntry {
        UsageEntry(dayKey: c.dayKey, category: ModelCategory(rawValue: c.category) ?? .sonnet,
                   input: c.input, output: c.output, cacheWrite: c.cacheWrite,
                   cacheRead: c.cacheRead, cost: c.cost, dedupKey: c.dedupKey,
                   project: project, projectByFiles: c.projectByFiles, hour: c.hour)
    }
```

> 참고: loadEntries(`:84-95`)는 무변경 — 이미 캐시 히트 시 `toEntry($0, project: project)`, 미스 시 `parseFile(path, project:)`를 호출한다. project(①)는 위치서 재도출, projectByFiles(②)는 캐시본 사용/재계산.

- [ ] **Step 6: 통과 확인 (기존 통합테스트 회귀 없나)**

Run: `swift run CoreTests 2>&1 | tail -8`
Expected: 전체 PASS (기존 `testAggregatorIntegration` 포함).

- [ ] **Step 7: 캐시 무효화 (구 스키마 인덱스 제거)**

기존 인덱스에는 `projectByFiles`가 없어 디코딩은 기본값 `""`로 되지만, ② 값이 비게 되므로 1회 재빌드 필요:
Run: `rm -f ~/.config/claude-usage-bar/log-index.json`
Expected: 다음 실행 시 전체 재파싱(②값 채워짐). (운영 배포본에도 동일 — 캐시는 자동 재생성)

- [ ] **Step 8: 커밋**

```bash
git add Sources/ClaudeUsageCore/LogAggregator.swift Sources/CoreTests/FileAttributionTests.swift
git commit -m "feat(core): LogAggregator sticky 승계 + projectByFiles 캐시"
```

---

## Task 5: DashboardModel — projectMode + 분기 집계

**Files:**
- Modify: `Sources/DashboardUI/DashboardModel.swift` (프로퍼티 `:12-21`, refreshSeries `:91-93`, detail `:225-233`)

- [ ] **Step 1: ProjectMode + @Published 추가** — `DashboardModel` 클래스 상단(`@Published var focus` 아래, `:21` 근처)에 추가:

```swift
    /// 프로젝트 귀속 방식(대시보드 프로젝트 카드 탭). .cwd=세션 cwd, .files=파일-터치.
    enum ProjectMode: String, CaseIterable { case cwd, files }
    @Published var projectMode: ProjectMode = .cwd { didSet { refreshSeries() } }
```

- [ ] **Step 2: projectRanking을 모드별 keyer로 집계** — `refreshSeries()`의 projectRanking 블록(`:91-93`)을 교체:

```swift
        // 기존 totalsByProject와 동일하게 트레일링 클로저 리터럴로 전달(String→String? 자동 승격).
        // 명시적 (UsageEntry)->String 함수값을 by:에 넘기면 K? 파라미터와 타입 불일치로 컴파일 실패.
        projectRanking = CostRollup.totals(fe) { self.projectMode == .cwd ? $0.project : $0.projectByFiles }
            .map { ProjectRow(raw: $0.key, name: ProjectPath.friendly($0.key), cost: $0.value.cost) }
            .filter { $0.cost > 0 }.sorted { $0.cost > $1.cost }.prefix(12).map { $0 }
```

- [ ] **Step 3: detail(for:)도 모드 반영** — `detail(for:)`(`:225-233`)의 `sub` 필터 교체:

```swift
    func detail(for rawKey: String) -> ProjectDetail {
        let sub = entries.filter {
            (projectMode == .cwd ? $0.project : $0.projectByFiles) == rawKey
        }
        let now = Date()
        return ProjectDetail(
            raw: rawKey, name: ProjectPath.friendly(rawKey),
            cost: CostRollup.rollup(entries: sub, now: now),
            daily: CostRollup.dailySeries(entries: sub, days: 30, endingAt: now)
        )
    }
```

- [ ] **Step 4: 빌드 확인**

Run: `swift build 2>&1 | tail -5`
Expected: 빌드 성공.

- [ ] **Step 5: 커밋**

```bash
git add Sources/DashboardUI/DashboardModel.swift
git commit -m "feat(dashboard): projectMode(cwd/files) + 모드별 프로젝트 집계"
```

---

## Task 6: UsageDashboardView — projectCard 세그먼트 탭

**Files:**
- Modify: `Sources/DashboardUI/UsageDashboardView.swift:228-248` (projectCard)

- [ ] **Step 1: projectCard 헤더에 세그먼트 Picker 추가** — `projectCard`(`:228-248`) 전체 교체:

```swift
    private var projectCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("프로젝트별 (\(model.periodShort))").font(.headline)
                    Spacer()
                    Text("클릭 → 상세").font(.caption2).foregroundStyle(.tertiary)
                }
                Picker("", selection: $model.projectMode) {
                    Text("cwd 기준").tag(DashboardModel.ProjectMode.cwd)
                    Text("파일 기준").tag(DashboardModel.ProjectMode.files)
                }
                .pickerStyle(.segmented).labelsHidden()
                if model.projectRanking.isEmpty { placeholder } else {
                    let maxCost = model.projectRanking.map(\.cost).max() ?? 1
                    VStack(spacing: 8) {
                        ForEach(model.projectRanking) { row in
                            Button { detailProject = row } label: { projectRow(row, maxCost: maxCost) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
```

> 참고: `$model.projectMode`는 `@ObservedObject var model`의 `@Published var projectMode`에 대한 바인딩. 탭 전환 → didSet → refreshSeries → 랭킹 갱신. 상세 시트는 `ProjectDetailView`가 `model.detail(for:)`을 쓰므로 자동으로 모드 반영.

- [ ] **Step 2: 빌드 확인**

Run: `swift build 2>&1 | tail -5`
Expected: 빌드 성공.

- [ ] **Step 3: 커밋**

```bash
git add Sources/DashboardUI/UsageDashboardView.swift
git commit -m "feat(dashboard): 프로젝트 카드에 cwd/파일 기준 세그먼트 탭"
```

---

## Task 7: 전체 검증 (테스트 + 로컬 빌드/실행) + 육안 확인

**Files:** (없음 — 검증)

- [ ] **Step 1: 전체 유닛테스트**

Run: `cd ~/projects/claude-usage-bar && swift run CoreTests 2>&1 | tail -8`
Expected: 전체 PASS, 실패 0.

- [ ] **Step 2: 릴리스 빌드 + 로컬 설치·실행** (기존 Dooray 훅 보존)

```bash
export DOORAY_HOOK_URL="$(sed -n 's/.*doorayHookURL = "\([^"]*\)".*/\1/p' Sources/ClaudeUsageBar/Secrets.generated.swift)"
rm -f ~/.config/claude-usage-bar/log-index.json   # ② 값 채우기 위해 캐시 재생성
bash scripts/package_app.sh release 1.18-dev 2>&1 | tail -6
```
Expected: 빌드·서명·설치·실행 완료.

- [ ] **Step 3: 육안 확인 (사용자)** — 대시보드 열기 → "프로젝트별" 카드 상단 `[cwd 기준][파일 기준]` 탭. 전환 시:
  - cwd 기준: 대부분 `develop`로 뭉침(현행).
  - 파일 기준: `claude-usage-bar`·`ledger`·`네오팜운영` 등으로 분산(재귀속).
  - 프로젝트 클릭 → 상세 시트가 선택된 방식 기준으로 뜨는지.

- [ ] **Step 4: (문제 없으면) 브랜치 최종 상태 push (개인깃)**

```bash
git -c credential.helper='!gh auth git-credential' push personal feat/project-attribution-tabs
```

---

## 배포 (검증 후, 별도 진행 — 스펙 §배포)

> ⚠ **CI(macos-14)는 로컬보다 동시성 엄격.** 로컬 통과만 믿지 말 것. 타이머/클로저 격리 필요 시 `MainActor.assumeIsolated`. 이번 변경은 UI/순수로직 위주라 위험 낮으나, 릴리즈 태그 push 후 Actions 빌드 로그 확인.

1. 사용자 검증 OK → `git checkout main && git merge --no-ff feat/project-attribution-tabs`
2. `git push origin main` (팀+개인 dual-push)
3. `git tag v1.18 && git push origin v1.18` → 두 레포 Actions 자동 빌드·릴리즈
4. 앱 [업데이트 확인] → v1.18 설치. 되돌릴 경우 브랜치 미머지 유지 → 정식본 영향 없음.

---

## Self-Review (작성자 점검 결과)

- **스펙 커버리지**: UI 탭(Task 6), projectByFiles 데이터(Task 2), ② 알고리즘=경로추출/taxonomy/Bash/dominant(Task 1)+sticky(Task 4), 집계 분기(Task 5), 테스트(Task 1·3·4), 배포(하단) — 스펙 각 절 대응됨.
- **타입 일관성**: `FileAttribution.project(forPath:home:)`·`extractPaths(fromContent:)`·`dominant(paths:home:)`·`applySticky(_:fallback:)`·`UsageEntry.projectByFiles`·`DashboardModel.ProjectMode`·`CostRollup.totals(_:by:)` — 전 태스크에서 시그니처 동일 사용.
- **플레이스홀더 없음**: 모든 코드 스텝에 실제 코드/명령/기대값 포함.
- **주의**: ② 값 채우려면 Task 4 Step 7 / Task 7 Step 2에서 `log-index.json` 1회 삭제 필요(구 캐시엔 필드 없음). 명시함.
