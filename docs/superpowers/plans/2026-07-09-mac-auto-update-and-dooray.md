# Mac 자동 업데이트 + 문의하기(Dooray) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mac 앱에 GitHub 기반 자동 업데이트(확인→다운로드→교체→재실행)와 Dooray 방으로 가는 문의하기를 추가한다.

**Architecture:** 순수 로직(버전 비교·릴리즈 JSON 파싱·문의 페이로드)은 Core/Live에 두고 CoreTests 하니스로 TDD. 네트워크(`Updater`,`ContactSender`)는 Live 액터. 자가 교체(`Installer`)·UI는 App 타깃. 배포는 태그 push→GitHub Actions(macOS 러너)가 빌드+ad-hoc서명+릴리즈. Dooray hook URL은 Actions 시크릿→빌드 시 gitignore된 `Secrets.generated.swift`로 주입.

**Tech Stack:** Swift 5.9 / SwiftPM(무의존성), SwiftUI(MenuBarExtra), URLSession, GitHub Releases API, GitHub Actions, Dooray Incoming Hook. 테스트=커스텀 `CoreTests` 실행형 하니스(`swift run CoreTests`).

**참고 스펙:** `docs/superpowers/specs/2026-07-09-mac-auto-update-and-dooray-design.md`

**전제:** hook URL은 이미 Actions 시크릿 `DOORAY_HOOK_URL`에 저장됨. `.gitignore`에 `*.generated.swift`·`.secrets/`·`Secrets.local.*` 추가됨. 레포 public 전환은 Phase 3에서 수행.

---

## Phase 1 — 버전/업데이트 코어 + 파이프라인

### Task 1: Version 값 타입 (Core, 순수)

**Files:**
- Create: `Sources/ClaudeUsageCore/Version.swift`
- Test: `Sources/CoreTests/VersionTests.swift`
- Modify: `Sources/CoreTests/main.swift`

- [ ] **Step 1: 실패 테스트 작성** — `Sources/CoreTests/VersionTests.swift`

```swift
import Foundation
import ClaudeUsageCore

func testVersion(_ h: Harness) {
    h.run("Version.parse") {
        h.expectEqual(Version("v1.4")?.description, "1.4", "v 접두사 제거")
        h.expectEqual(Version("1.4.2")?.description, "1.4.2", "3요소")
        h.expectNil(Version("abc"), "숫자 아님→nil")
        h.expectNil(Version(""), "빈 문자열→nil")
    }
    h.run("Version.compare") {
        h.expect(Version("1.3")! < Version("1.4")!, "1.3 < 1.4")
        h.expect(Version("1.4")! < Version("1.10")!, "1.4 < 1.10 (숫자비교)")
        h.expect(Version("1.3")! < Version("1.3.1")!, "1.3 < 1.3.1")
        h.expect(Version("1.4")! == Version("1.4.0")!, "1.4 == 1.4.0")
        h.expect(!(Version("1.4")! < Version("1.4")!), "동일은 < 아님")
    }
}
```

- [ ] **Step 2: main.swift에 등록** — `Sources/CoreTests/main.swift`, `h.finish()` 바로 위에 추가:

```swift
// MARK: - Version
testVersion(h)
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `cd ~/projects/claude-usage-bar && swift run CoreTests 2>&1 | tail -3`
Expected: 컴파일 에러(`cannot find 'Version'`) 또는 FAIL.

- [ ] **Step 4: 최소 구현** — `Sources/ClaudeUsageCore/Version.swift`

```swift
import Foundation

/// "v1.4" / "1.4.2" 같은 버전 문자열을 파싱·비교. 부족한 자리는 0으로 취급(1.4 == 1.4.0).
public struct Version: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ s: String) {
        var str = s.trimmingCharacters(in: .whitespaces)
        if str.hasPrefix("v") || str.hasPrefix("V") { str.removeFirst() }
        guard !str.isEmpty else { return nil }
        var comps: [Int] = []
        for part in str.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(part), n >= 0 else { return nil }
            comps.append(n)
        }
        guard !comps.isEmpty else { return nil }
        self.components = comps
    }

    public static func < (a: Version, b: Version) -> Bool {
        let n = max(a.components.count, b.components.count)
        for i in 0..<n {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: Version, b: Version) -> Bool {
        let n = max(a.components.count, b.components.count)
        for i in 0..<n {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return false }
        }
        return true
    }

    public var description: String { components.map(String.init).joined(separator: ".") }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift run CoreTests 2>&1 | tail -3`
Expected: `... passed, 0 failed`.

- [ ] **Step 6: 커밋**

```bash
git add Sources/ClaudeUsageCore/Version.swift Sources/CoreTests/VersionTests.swift Sources/CoreTests/main.swift
git commit -m "feat(core): Version 파싱·비교 타입 + 테스트"
```

---

### Task 2: 릴리즈 JSON 파서 (Live, 순수)

**Files:**
- Create: `Sources/ClaudeUsageLive/ReleaseInfo.swift`
- Test: `Sources/CoreTests/ReleaseParserTests.swift`
- Modify: `Sources/CoreTests/main.swift`

- [ ] **Step 1: 실패 테스트 작성** — `Sources/CoreTests/ReleaseParserTests.swift`

```swift
import Foundation
import ClaudeUsageLive

func testReleaseParser(_ h: Harness) {
    let json = """
    {"tag_name":"v1.4","assets":[
      {"name":"notes.txt","browser_download_url":"https://x/notes.txt"},
      {"name":"claude-usage-mac.zip","browser_download_url":"https://x/app.zip"}]}
    """.data(using: .utf8)!
    h.run("ReleaseParser.ok") {
        let r = ReleaseParser.parseLatest(json)
        h.expectNotNil(r, "파싱 성공")
        h.expectEqual(r?.tag, "v1.4", "tag")
        h.expectEqual(r?.zipURL.absoluteString, "https://x/app.zip", "첫 zip 에셋")
    }
    h.run("ReleaseParser.fail") {
        h.expectNil(ReleaseParser.parseLatest(Data("garbage".utf8)), "쓰레기→nil")
        let noZip = #"{"tag_name":"v1.4","assets":[{"name":"a.txt","browser_download_url":"https://x/a"}]}"#
        h.expectNil(ReleaseParser.parseLatest(Data(noZip.utf8)), "zip 없음→nil")
    }
}
```

- [ ] **Step 2: main.swift 등록** — `h.finish()` 위:

```swift
// MARK: - ReleaseParser
testReleaseParser(h)
```

- [ ] **Step 3: 실패 확인**

Run: `swift run CoreTests 2>&1 | tail -3`
Expected: 컴파일 에러(`cannot find 'ReleaseParser'`).

- [ ] **Step 4: 구현** — `Sources/ClaudeUsageLive/ReleaseInfo.swift`

```swift
import Foundation

public struct ReleaseInfo: Equatable, Sendable {
    public let tag: String
    public let zipURL: URL
    public init(tag: String, zipURL: URL) { self.tag = tag; self.zipURL = zipURL }
}

/// GitHub `releases/latest` 응답 → tag + 첫 .zip 에셋 URL. 순수 함수(테스트 가능).
public enum ReleaseParser {
    public static func parseLatest(_ data: Data) -> ReleaseInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let assets = obj["assets"] as? [[String: Any]] else { return nil }
        for a in assets {
            if let name = a["name"] as? String, name.hasSuffix(".zip"),
               let s = a["browser_download_url"] as? String, let url = URL(string: s) {
                return ReleaseInfo(tag: tag, zipURL: url)
            }
        }
        return nil
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `swift run CoreTests 2>&1 | tail -3`
Expected: `... passed, 0 failed`.

- [ ] **Step 6: 커밋**

```bash
git add Sources/ClaudeUsageLive/ReleaseInfo.swift Sources/CoreTests/ReleaseParserTests.swift Sources/CoreTests/main.swift
git commit -m "feat(live): GitHub 릴리즈 JSON 파서 + 테스트"
```

---

### Task 3: Updater 액터 (Live, 네트워크)

**Files:**
- Create: `Sources/ClaudeUsageLive/Updater.swift`

- [ ] **Step 1: 구현** — `Sources/ClaudeUsageLive/Updater.swift`

```swift
import Foundation

public enum UpdaterError: Error, Sendable { case http(Int), network(String) }

/// GitHub Releases 최신 조회 + 에셋 다운로드. (public 레포라 비인증)
public actor Updater {
    private let repo: String
    private let session: URLSession
    public init(repo: String = "hjs1761/claude-usage-bar", session: URLSession = .shared) {
        self.repo = repo; self.session = session
    }

    /// 최신 릴리즈. 실패/부재 시 nil(조용히).
    public func fetchLatest() async -> ReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ClaudeUsageBar", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await session.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return nil }
        return ReleaseParser.parseLatest(data)
    }

    /// zip을 dest 경로로 다운로드(기존 파일 덮어씀).
    public func download(_ url: URL, to dest: URL) async throws {
        let (tmp, resp) = try await session.download(from: url)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            throw UpdaterError.http(code)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }
}
```

- [ ] **Step 2: 컴파일 확인**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!` (앱 타깃은 아직 Secrets 없어 실패할 수 있음 → `swift build --target ClaudeUsageLive` 로 Live만 확인)
Run: `swift build --target ClaudeUsageLive 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: 커밋**

```bash
git add Sources/ClaudeUsageLive/Updater.swift
git commit -m "feat(live): Updater — 릴리즈 조회 + 다운로드"
```

---

### Task 4: 시크릿 주입 스크립트 + gitignore 확인

**Files:**
- Create: `scripts/gen-secrets.sh`
- Verify: `.gitignore` (이미 `*.generated.swift` 포함)

- [ ] **Step 1: 스크립트 작성** — `scripts/gen-secrets.sh`

```bash
#!/bin/bash
# DOORAY_HOOK_URL(env)로 gitignore된 Secrets.generated.swift 생성. 없으면 빈 값(문의 비활성).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="Sources/ClaudeUsageBar/Secrets.generated.swift"
URL="${DOORAY_HOOK_URL:-}"
cat > "$OUT" <<EOF
// 자동 생성 — 커밋 금지(.gitignore: *.generated.swift). scripts/gen-secrets.sh 산출물.
enum Secrets { static let doorayHookURL = "$URL" }
EOF
echo ">> generated $OUT (hook: ${URL:+set}${URL:+ }${URL:-empty})"
```

- [ ] **Step 2: 실행 권한 + 생성 확인**

Run: `chmod +x scripts/gen-secrets.sh && scripts/gen-secrets.sh && cat Sources/ClaudeUsageBar/Secrets.generated.swift`
Expected: `enum Secrets { static let doorayHookURL = "" }` (env 없으면 빈 값)

- [ ] **Step 3: gitignore로 생성 파일이 무시되는지 확인**

Run: `git status --porcelain Sources/ClaudeUsageBar/Secrets.generated.swift`
Expected: **아무 출력 없음** (무시됨). 출력되면 `.gitignore`에 `*.generated.swift` 없음 → 추가.

- [ ] **Step 4: 커밋** (스크립트만)

```bash
git add scripts/gen-secrets.sh
git commit -m "build: gen-secrets.sh — DOORAY_HOOK_URL을 gitignore된 Secrets로 주입"
```

---

### Task 5: package_app.sh — 시크릿 생성 + CI 모드

**Files:**
- Modify: `scripts/package_app.sh`

- [ ] **Step 1: 시크릿 생성 호출 추가** — `swift build` 줄 바로 위(현재 11번 줄 앞)에 삽입:

```bash
echo ">> gen-secrets"
scripts/gen-secrets.sh
```

- [ ] **Step 2: CI 모드 가드 추가** — 파일 끝의 설치/실행 블록(현재 42~58번 줄)을 아래로 교체:

```bash
# CI=1 이면 번들만 만들고 설치/실행 안 함(GitHub Actions용).
if [ "${CI:-}" = "1" ]; then
  echo "완료(CI): $APP_DIR"
  exit 0
fi

# release는 /Applications에 설치해 거기서 실행(안정 위치). debug는 .build에서.
RUN_APP="$APP_DIR"
if [ "$BUILD_CONFIG" = "release" ]; then
  DEST="/Applications/$APP_NAME.app"
  echo ">> /Applications 설치"
  rm -rf "$DEST"; ditto "$APP_DIR" "$DEST"; RUN_APP="$DEST"
fi
echo ">> 실행 ($RUN_APP)"
pkill -x "$BIN_NAME" 2>/dev/null || true
sleep 0.3
open "$RUN_APP"
echo "완료: $RUN_APP"
```

- [ ] **Step 3: 로컬 빌드 검증**

Run: `bash scripts/package_app.sh release 1.3 2>&1 | tail -5`
Expected: gen-secrets 출력 후 빌드·서명·설치·실행 완료. 앱이 뜸.

- [ ] **Step 4: 커밋**

```bash
git add scripts/package_app.sh
git commit -m "build(package): gen-secrets 호출 + CI=1 번들전용 모드"
```

---

### Task 6: GitHub Actions 릴리즈 워크플로

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: 워크플로 작성** — `.github/workflows/release.yml`

```yaml
name: release
on:
  push:
    tags: ['v*']
permissions:
  contents: write
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Version from tag
        id: ver
        run: echo "v=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"
      - name: Build + package (CI, no install)
        env:
          DOORAY_HOOK_URL: ${{ secrets.DOORAY_HOOK_URL }}
          CI: "1"
        run: bash scripts/package_app.sh release "${{ steps.ver.outputs.v }}"
      - name: Zip app
        run: ditto -c -k --keepParent ".build/Claude Usage Bar.app" "claude-usage-mac-${GITHUB_REF_NAME}.zip"
      - name: Create release
        env:
          GH_TOKEN: ${{ github.token }}
        run: gh release create "${GITHUB_REF_NAME}" "claude-usage-mac-${GITHUB_REF_NAME}.zip" --generate-notes --repo "${{ github.repository }}"
```

- [ ] **Step 2: 커밋(푸시는 Phase 3 public 전환 후 태그와 함께)**

```bash
git add .github/workflows/release.yml
git commit -m "ci: 태그 push 시 빌드+ad-hoc서명+릴리즈 워크플로"
```

> 검증은 Phase 3에서 실제 태그 push로 수행(로컬 검증 불가).

---

### Task 7: Installer — 자가 교체 + 재실행 (App)

**Files:**
- Create: `Sources/ClaudeUsageBar/Installer.swift`

- [ ] **Step 1: 구현** — `Sources/ClaudeUsageBar/Installer.swift`

```swift
import Foundation
import AppKit

enum InstallerError: Error { case badBundle, unzipFailed }

/// 다운로드된 zip을 풀어 /Applications 번들을 교체하고 재실행한다.
/// 실행 중 앱은 자기 자신을 덮어쓸 수 없으므로, 헬퍼 셸을 detached로 띄우고 스스로 종료한다.
enum Installer {
    static let appName = "Claude Usage Bar"

    /// zip → 임시 해제 → 격리제거 → 검증 → 헬퍼로 교체+재실행(앱 종료).
    static func applyUpdate(fromZip zip: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("cub-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        // 1) 해제 (ditto -x -k)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, work.path]
        try unzip.run(); unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw InstallerError.unzipFailed }

        // 2) 새 .app 찾기 + 검증
        let newApp = work.appendingPathComponent("\(appName).app")
        let exe = newApp.appendingPathComponent("Contents/MacOS/ClaudeUsageBar")
        guard fm.fileExists(atPath: exe.path) else { throw InstallerError.badBundle }

        // 3) 격리 제거(Gatekeeper 통과)
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        // 4) 헬퍼 스크립트: 현재 PID 종료 대기 → 교체 → 재실행
        let dest = "/Applications/\(appName).app"
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        rm -rf "\(dest)"
        /usr/bin/ditto "\(newApp.path)" "\(dest)"
        /usr/bin/xattr -dr com.apple.quarantine "\(dest)" 2>/dev/null || true
        /usr/bin/open "\(dest)"
        """
        let sh = work.appendingPathComponent("swap.sh")
        try script.write(to: sh, atomically: true, encoding: .utf8)

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [sh.path]
        try helper.run()   // detached (부모 종료돼도 계속)

        NSApplication.shared.terminate(nil)
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run(); p.waitUntilExit()
    }
}
```

- [ ] **Step 2: (컴파일은 Task 8 이후 앱 전체 빌드 때 확인) 커밋**

```bash
git add Sources/ClaudeUsageBar/Installer.swift
git commit -m "feat(app): Installer — 다운로드 zip으로 /Applications 교체+재실행"
```

---

### Task 8: AppState — 업데이트 확인 상태 배선

**Files:**
- Modify: `Sources/ClaudeUsageBar/AppState.swift`

- [ ] **Step 1: 상태/의존성 추가** — `AppState`의 `@Published` 블록 아래, `sessionBurnImminent` 다음 줄에 추가:

```swift
    @Published var updateStatus: UpdateStatus = .idle
    var currentVersionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }
```

그리고 파일 하단(클래스 밖)에 열거형 추가:

```swift
enum UpdateStatus: Equatable {
    case idle                    // 확인 전/최신
    case checking
    case available(tag: String)  // 새 버전 있음
    case downloading
    case error(String)
}
```

- [ ] **Step 2: Updater 인스턴스 + 다운로드 대상 프로퍼티 추가** — `private let burnEstimator = BurnEstimator()` 아래:

```swift
    private let updater = Updater()
    private var pendingZipURL: URL?   // available 상태에서 다운로드할 에셋 URL
```

- [ ] **Step 3: 확인/설치 메서드 추가** — `recomputeBurn()` 아래에 삽입:

```swift
    /// 최신 릴리즈 확인 → 현재 버전보다 높으면 available.
    func checkForUpdate() async {
        if case .downloading = updateStatus { return }
        updateStatus = .checking
        guard let info = await updater.fetchLatest(),
              let latest = Version(info.tag), let cur = Version(currentVersionString) else {
            updateStatus = .idle; return
        }
        if latest > cur {
            pendingZipURL = info.zipURL
            updateStatus = .available(tag: info.tag)
        } else {
            updateStatus = .idle
        }
    }

    /// available일 때 호출: 다운로드 후 Installer로 교체+재실행(앱 종료).
    func installUpdate() async {
        guard let url = pendingZipURL else { return }
        updateStatus = .downloading
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("cub-update-\(UUID().uuidString).zip")
        do {
            try await updater.download(url, to: dest)
            try Installer.applyUpdate(fromZip: dest)   // 성공 시 앱 종료됨
        } catch {
            updateStatus = .error("업데이트 실패: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 4: 시작 시 1회 확인** — `start()` 안, `startBurnRefresh()` 다음 줄에 추가:

```swift
        Task { await checkForUpdate() }
```

- [ ] **Step 5: 앱 전체 빌드 확인**

Run: `scripts/gen-secrets.sh && swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 6: 커밋**

```bash
git add Sources/ClaudeUsageBar/AppState.swift
git commit -m "feat(app): AppState 업데이트 확인/설치 상태 배선"
```

---

### Task 9: 설정 UI — 업데이트 섹션

**Files:**
- Modify: `Sources/ClaudeUsageBar/SettingsView.swift`

- [ ] **Step 1: 업데이트 섹션 추가** — `SettingsView` `Form` 맨 아래(로그인 토글 다음)에 삽입:

```swift
            Divider()
            HStack {
                Text("버전 \(state.currentVersionString)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                switch state.updateStatus {
                case .idle:
                    Button("업데이트 확인") { Task { await state.checkForUpdate() } }.font(.callout)
                case .checking:
                    Text("확인 중…").font(.caption).foregroundStyle(.secondary)
                case .available(let tag):
                    Button("\(tag) 설치") { Task { await state.installUpdate() } }
                        .font(.callout).buttonStyle(.borderedProminent)
                case .downloading:
                    Text("다운로드 중…").font(.caption).foregroundStyle(.secondary)
                case .error(let m):
                    Text(m).font(.caption).foregroundStyle(.red)
                }
            }
```

- [ ] **Step 2: 앱 빌드 + 실행 육안 확인**

Run: `bash scripts/package_app.sh release 1.3 2>&1 | tail -3`
Expected: 앱 실행 → 설정 열면 "버전 1.3" + [업데이트 확인] 버튼. 클릭 시 최신이면 "확인 중…"→사라짐(현재 배포 전이라 idle 복귀 정상).

- [ ] **Step 3: 커밋**

```bash
git add Sources/ClaudeUsageBar/SettingsView.swift
git commit -m "feat(app): 설정에 업데이트 확인/설치 섹션"
```

---

## Phase 2 — 문의하기(Dooray)

### Task 10: 문의 페이로드 (Live, 순수) + 테스트

**Files:**
- Create: `Sources/ClaudeUsageLive/Contact.swift`
- Test: `Sources/CoreTests/ContactTests.swift`
- Modify: `Sources/CoreTests/main.swift`

- [ ] **Step 1: 실패 테스트** — `Sources/CoreTests/ContactTests.swift`

```swift
import Foundation
import ClaudeUsageLive

func testContact(_ h: Harness) {
    h.run("Contact.payload") {
        let data = Contact.payload(message: "버그 있어요", from: "황준석",
                                   appVersion: "1.3", os: "26.5", timestamp: "2026-07-09T12:00")
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = (obj?["text"] as? String) ?? ""
        h.expectEqual(obj?["botName"] as? String, "사용량앱 문의", "botName")
        h.expect(text.contains("버그 있어요"), "내용 포함")
        h.expect(text.contains("v1.3"), "버전 포함")
        h.expect(text.contains("황준석"), "보낸사람 포함")
    }
    h.run("Contact.payload.익명") {
        let data = Contact.payload(message: "hi", from: "", appVersion: "1.3", os: "26", timestamp: "t")
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        h.expect(((obj?["text"] as? String) ?? "").contains("익명"), "빈 보낸사람→익명")
    }
}
```

- [ ] **Step 2: main.swift 등록** — `h.finish()` 위:

```swift
// MARK: - Contact
testContact(h)
```

- [ ] **Step 3: 실패 확인**

Run: `swift run CoreTests 2>&1 | tail -3`
Expected: 컴파일 에러(`cannot find 'Contact'`).

- [ ] **Step 4: 구현** — `Sources/ClaudeUsageLive/Contact.swift`

```swift
import Foundation

public enum ContactError: Error, Sendable { case notConfigured, http(Int), network }

/// Dooray Incoming Hook 문의 전송.
public enum Contact {
    /// 방에 올릴 JSON 바디 생성(순수·테스트 가능).
    public static func payload(message: String, from sender: String,
                               appVersion: String, os: String, timestamp: String) -> Data {
        let who = sender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "익명" : sender
        let text = "\(message)\n\n---\n앱 v\(appVersion) · macOS \(os) · 보낸사람: \(who) · \(timestamp)"
        let obj: [String: Any] = ["botName": "사용량앱 문의", "text": text]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    /// hook URL로 POST. 빈 URL이면 notConfigured.
    public static func send(hookURL: String, body: Data,
                            session: URLSession = .shared) async throws {
        guard !hookURL.isEmpty, let url = URL(string: hookURL) else { throw ContactError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 15
        guard let (_, resp) = try? await session.data(for: req) else { throw ContactError.network }
        guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            throw ContactError.http((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `swift run CoreTests 2>&1 | tail -3`
Expected: `... passed, 0 failed`.

- [ ] **Step 6: 커밋**

```bash
git add Sources/ClaudeUsageLive/Contact.swift Sources/CoreTests/ContactTests.swift Sources/CoreTests/main.swift
git commit -m "feat(live): Dooray 문의 페이로드/전송 + 테스트"
```

---

### Task 11: AppState 문의 전송 + 문의 시트 UI

**Files:**
- Modify: `Sources/ClaudeUsageBar/AppState.swift`
- Create: `Sources/ClaudeUsageBar/ContactSheet.swift`
- Modify: `Sources/ClaudeUsageBar/SettingsView.swift`

- [ ] **Step 1: AppState에 전송 메서드 + hook 설정 여부** — `installUpdate()` 아래 삽입:

```swift
    var contactConfigured: Bool { !Secrets.doorayHookURL.isEmpty }

    /// 문의 전송. 성공/실패를 bool로 반환(UI 토스트용).
    func sendContact(message: String, from sender: String) async -> Bool {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osStr = "\(os.majorVersion).\(os.minorVersion)"
        let ts = ISO8601DateFormatter().string(from: Date())
        let body = Contact.payload(message: message, from: sender,
                                   appVersion: currentVersionString, os: osStr, timestamp: ts)
        do { try await Contact.send(hookURL: Secrets.doorayHookURL, body: body); return true }
        catch { return false }
    }
```

> `ClaudeUsageLive`는 이미 `import` 되어 있음(파일 상단). `Secrets`는 같은 앱 타깃(생성 파일).

- [ ] **Step 2: 문의 시트** — `Sources/ClaudeUsageBar/ContactSheet.swift`

```swift
import SwiftUI

struct ContactSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var sender = ""
    @State private var sending = false
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("문의하기").font(.headline)
            Text("내용이 담당 Dooray 방으로 전송됩니다. (앱 버전·OS 자동 첨부)")
                .font(.caption).foregroundStyle(.secondary)
            TextField("보내는 사람 (선택)", text: $sender).textFieldStyle(.roundedBorder)
            TextEditor(text: $message)
                .frame(height: 120).border(.secondary.opacity(0.3))
            if let r = result { Text(r).font(.caption).foregroundStyle(r.contains("완료") ? .green : .red) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button(sending ? "전송 중…" : "보내기") {
                    sending = true; result = nil
                    Task {
                        let ok = await state.sendContact(message: message, from: sender)
                        sending = false
                        result = ok ? "전송 완료" : "전송 실패 — 잠시 후 다시 시도"
                        if ok { try? await Task.sleep(for: .seconds(1)); dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16).frame(width: 340)
    }
}
```

- [ ] **Step 3: 설정에 문의하기 버튼** — `SettingsView`의 업데이트 섹션(Task 9) 아래에 삽입:

```swift
            Button("문의하기") { showContact = true }
                .font(.callout)
                .disabled(!state.contactConfigured)
```

그리고 `SettingsView`의 상태 변수(맨 위 `@State private var onAC` 아래)에 추가:

```swift
    @State private var showContact = false
```

`Form` 닫힌 직후(`.task { ... }` 위)에 `.sheet` 추가:

```swift
        .sheet(isPresented: $showContact) { ContactSheet(state: state) }
```

- [ ] **Step 4: 빌드 + 육안 확인**

Run: `DOORAY_HOOK_URL=$(gh secret list >/dev/null 2>&1; echo '') scripts/gen-secrets.sh; bash scripts/package_app.sh release 1.3 2>&1 | tail -3`
> 로컬엔 hook env가 없으니 "문의하기"는 비활성(정상). 활성 테스트는 Phase 3 릴리즈 빌드에서.
Expected: 설정에 [문의하기] 버튼 보임(비활성 회색).

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeUsageBar/AppState.swift Sources/ClaudeUsageBar/ContactSheet.swift Sources/ClaudeUsageBar/SettingsView.swift
git commit -m "feat(app): 문의하기 시트 + Dooray 전송 배선"
```

---

## Phase 3 — public 전환 · 첫 릴리즈 · E2E 검증

### Task 12: public 전환 + 첫 릴리즈

**Files:** (코드 없음 — 운영 작업)

- [ ] **Step 1: 커밋 전부 push (main)**

```bash
git fetch origin && git rebase origin/main
git push origin main
```

- [ ] **Step 2: 레포 public 전환**

Run: `gh repo edit hjs1761/claude-usage-bar --visibility public --accept-visibility-change-consequences`
Expected: 성공. (히스토리 감사 통과 확인됨)

- [ ] **Step 3: 첫 릴리즈 태그 push → Actions 확인**

```bash
git tag v1.4 && git push origin v1.4
gh run watch --repo hjs1761/claude-usage-bar   # 워크플로 완료 대기
gh release view v1.4 --repo hjs1761/claude-usage-bar   # zip 에셋 확인
```
Expected: `release` 워크플로 성공 + `claude-usage-mac-v1.4.zip` 에셋 존재.

- [ ] **Step 4: E2E — 업데이트 흐름**

1. 로컬에 **구버전(v1.3)** 설치 상태에서 앱 실행.
2. 설정 → "업데이트 확인" → **[v1.4 설치]** 활성 확인.
3. 클릭 → 다운로드 → 앱 종료 후 자동 재실행 → 설정 "버전 1.4" 확인.
Expected: 크래시 없이 v1.4로 교체·재실행.

- [ ] **Step 5: E2E — 문의하기**

1. v1.4(릴리즈 빌드, hook 주입됨) 실행 → 설정 → [문의하기] 활성.
2. 내용 입력 → 보내기 → "전송 완료".
3. Dooray 방에 메시지(내용 + 버전·OS·시각) 도착 확인.
Expected: 방에 게시됨.

- [ ] **Step 6: 배포 안내**

동료에게: 릴리즈 페이지 zip 다운로드 → 압축해제 → `/Applications`로 이동 → 최초 1회 `xattr -cr "/Applications/Claude Usage Bar.app"` 후 실행. 이후는 앱 내 업데이트 버튼으로 갱신.

---

## 자기검토 메모 (작성자)
- 스펙 커버리지: 배포(Actions)=Task6/12, 앱 확인/적용=Task3/7/8/9, 버전비교=Task1, 시크릿주입=Task4/5/6, 문의=Task10/11, public전환/감사=Task12(감사는 스펙에서 완료). ✅
- 타입 일관성: `Version`, `ReleaseInfo`(tag/zipURL), `UpdateStatus`(idle/checking/available/downloading/error), `Updater.fetchLatest()/download(_:to:)`, `Installer.applyUpdate(fromZip:)`, `Contact.payload(...)/send(hookURL:body:)`, `Secrets.doorayHookURL` — 태스크 간 시그니처 일치 확인. ✅
- 플레이스홀더: 없음(모든 코드 블록 실체). ✅
- 주의: 앱 타깃은 `Secrets.generated.swift`가 있어야 컴파일 → 앱 빌드 전 항상 `gen-secrets.sh`(package_app.sh가 호출). `CoreTests`는 Secrets 미참조 → 무관.
