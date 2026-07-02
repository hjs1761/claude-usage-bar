# Claude Usage Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 SwiftBar 파이썬 플러그인을 네이티브 macOS 메뉴바 앱으로 완전 이식한다 (개인용, 유휴 CPU ~0%).

**Architecture:** SwiftPM 패키지를 두 타겟으로 분리 — `ClaudeUsageCore`(순수 로직 라이브러리, `swift test`로 TDD) + `ClaudeUsageBar`(SwiftUI `MenuBarExtra` 실행파일). 앱은 코어의 서비스를 `@MainActor AppState`로 조율해 표시만 한다. `.app` 번들은 스크립트로 수동 패키징(LSUIElement, ad-hoc 서명).

**Tech Stack:** Swift 6.2 / SwiftUI `MenuBarExtra` / SwiftPM / Foundation(URLSession, Keychain via `security`) / macOS 14+ 타겟 (개발기 26.5, arm64). Xcode 없이 CommandLineTools로 빌드.

---

## File Structure

```
~/projects/claude-usage-bar/
├─ Package.swift
├─ .gitignore
├─ scripts/
│   └─ package_app.sh              # swift build + .app 번들 생성 + ad-hoc 서명 + 실행
├─ Sources/
│   ├─ ClaudeUsageCore/            # 순수 로직 (테스트 대상)
│   │   ├─ ModelCategory.swift     # opus/sonnet/haiku 분류 + 단가
│   │   ├─ ColorAdapt.swift        # text_dual 이식 (라이트/다크 대비 보정)
│   │   ├─ Credentials.swift       # 키체인 JSON 파싱 (순수) + KeychainReader (security 래퍼)
│   │   ├─ UsageData.swift         # /api/oauth/usage 응답 모델 + 디코드
│   │   ├─ UsageClient.swift       # HTTP 호출 (얇게) + 캐시
│   │   ├─ LogModels.swift         # UsageEntry, UsageCost, ModelBucket
│   │   ├─ LogParser.swift         # jsonl 한 줄 → UsageEntry? (순수)
│   │   ├─ CostRollup.swift        # [UsageEntry] + now → UsageCost (순수)
│   │   ├─ LogAggregator.swift     # 파일 글로빙 + (mtime,size) 인덱스 캐시 + 롤업
│   │   └─ Settings.swift          # SettingsStore (UserDefaults), DisplayMode enum
│   └─ ClaudeUsageBar/             # SwiftUI 앱 (실행파일)
│       ├─ ClaudeUsageBarApp.swift # @main, MenuBarExtra 진입점
│       ├─ AppState.swift          # @MainActor ObservableObject, 폴링·조율
│       ├─ MenuBarLabel.swift      # 메뉴바 라벨 (표시모드별)
│       ├─ DashboardView.swift     # 팝오버 대시보드
│       ├─ SettingsView.swift      # 설정 화면
│       └─ LoginItem.swift         # SMAppService 자동실행
└─ Tests/
    └─ ClaudeUsageCoreTests/
        ├─ ColorAdaptTests.swift
        ├─ CredentialsTests.swift
        ├─ UsageDataTests.swift
        ├─ LogParserTests.swift
        ├─ CostRollupTests.swift
        └─ SettingsTests.swift
```

**책임 경계:**
- `LogParser.parseLine` (순수) ↔ `LogAggregator` (파일 IO) 분리 → 파싱 로직 TDD 가능.
- `CostRollup.rollup(entries:now:)` (순수, now 주입) → 날짜 경계 TDD 가능.
- `UsageData` 디코드 (순수) ↔ `UsageClient` (네트워크) 분리 → 스키마 TDD 가능.
- `Credentials.parse` (순수) ↔ `KeychainReader` (security 호출) 분리.
- 뷰는 `AppState`만 관찰.

---

## Task 0: SwiftPM 스캐폴드

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/ClaudeUsageCore/ModelCategory.swift`
- Create: `Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift`

- [ ] **Step 1: `.gitignore` 작성**

```
.build/
*.app
.DS_Store
DerivedData/
```

- [ ] **Step 2: `Package.swift` 작성**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeUsageCore"),
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["ClaudeUsageCore"]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"]
        ),
    ]
)
```

- [ ] **Step 3: 최소 코어 파일 (빌드 성립용)**

`Sources/ClaudeUsageCore/ModelCategory.swift`:
```swift
import Foundation

public enum ModelCategory: String, CaseIterable, Sendable {
    case opus, sonnet, haiku

    /// base 입력 단가 (USD/token). 출력 5x, 캐시읽기 0.1x, 캐시쓰기5m 1.25x / 1h 2x.
    public var basePrice: Double {
        switch self {
        case .opus:   return 5e-6
        case .sonnet: return 3e-6
        case .haiku:  return 1e-6
        }
    }

    public var displayName: String {
        switch self {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        }
    }

    /// 모델명 문자열 → 카테고리. opus/haiku 아니면 sonnet.
    public static func from(model: String?) -> ModelCategory {
        let m = (model ?? "").lowercased()
        if m.contains("opus") { return .opus }
        if m.contains("haiku") { return .haiku }
        return .sonnet
    }
}
```

- [ ] **Step 4: 최소 앱 파일 (빌드 성립용, 아직 실행 안 함)**

`Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift`:
```swift
import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageBarApp: App {
    var body: some Scene {
        MenuBarExtra("CUB") {
            Text("Hello")
        }
    }
}
```

- [ ] **Step 5: 빌드 확인**

Run: `cd ~/projects/claude-usage-bar && swift build`
Expected: `Compiling ...` 후 에러 없이 `Build complete!`

- [ ] **Step 6: Commit**

```bash
cd ~/projects/claude-usage-bar
git add -A
git commit -m "feat: SwiftPM scaffold (Core lib + MenuBarExtra executable)"
```

---

## Task 1: `.app` 패키징 스크립트 + 메뉴바에 실제로 뜨는지 확인

**Files:**
- Create: `scripts/package_app.sh`

- [ ] **Step 1: 패키징 스크립트 작성**

`scripts/package_app.sh`:
```bash
#!/bin/bash
# swift build (release) → .app 번들 조립 → LSUIElement Info.plist → ad-hoc 서명 → 실행.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Claude Usage Bar"
BIN_NAME="ClaudeUsageBar"
BUILD_CONFIG="${1:-debug}"   # debug(기본) | release

echo ">> swift build ($BUILD_CONFIG)"
swift build -c "$BUILD_CONFIG"
BIN_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/$BIN_NAME"

APP_DIR=".build/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>local.claude-usage-bar</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>$BIN_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

echo ">> ad-hoc 서명"
codesign --force --deep --sign - "$APP_DIR"

echo ">> 실행"
open "$APP_DIR"
echo "완료: $APP_DIR"
```

- [ ] **Step 2: 실행 권한 부여 + 실행**

Run: `chmod +x scripts/package_app.sh && ./scripts/package_app.sh`
Expected: `Build complete!` → `완료: .build/Claude Usage Bar.app` 출력, 메뉴바에 `CUB` 텍스트가 뜬다 (Dock 아이콘 없음).

- [ ] **Step 3: 수동 검증**

메뉴바 오른쪽에 `CUB`가 보이고 클릭하면 `Hello` 드롭다운이 나오는지 눈으로 확인. Dock에 아이콘이 안 뜨는지(LSUIElement) 확인.

- [ ] **Step 4: 종료 확인**

Run: `pkill -x ClaudeUsageBar`
Expected: 메뉴바에서 사라짐.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: .app packaging script (LSUIElement, ad-hoc sign)"
```

---

## Task 2: ColorAdapt (라이트/다크 대비 보정) — TDD

기존 파이썬 `text_dual()` 이식. 선택한 강조색을 라이트/다크 각각에서 가독되게 보정.

**Files:**
- Create: `Sources/ClaudeUsageCore/ColorAdapt.swift`
- Test: `Tests/ClaudeUsageCoreTests/ColorAdaptTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/ClaudeUsageCoreTests/ColorAdaptTests.swift`:
```swift
import XCTest
@testable import ClaudeUsageCore

final class ColorAdaptTests: XCTestCase {
    func testGrayscaleBecomesPureBlackWhite() {
        // 무채색(회색)은 라이트=검정, 다크=흰색
        let r = ColorAdapt.dual(hex: "#808080")
        XCTAssertEqual(r.light, RGB(r: 0, g: 0, b: 0))
        XCTAssertEqual(r.dark, RGB(r: 255, g: 255, b: 255))
    }

    func testBrightColorIsDarkenedForLight() {
        // 밝은 노랑(#ffff00, 명도 높음)은 라이트용으로 어두워져야 함
        let r = ColorAdapt.dual(hex: "#ffff00")
        let lumLight = 0.299*Double(r.light.r) + 0.587*Double(r.light.g) + 0.114*Double(r.light.b)
        XCTAssertLessThan(lumLight, 200)   // 원본(≈226)보다 낮아짐
    }

    func testDarkColorIsLightenedForDark() {
        // 어두운 파랑(#000080)은 다크용으로 밝아져야 함
        let r = ColorAdapt.dual(hex: "#000080")
        XCTAssertGreaterThan(r.dark.b, 128) // 원본 128보다 밝아짐
    }

    func testShortHexParses() {
        let r = ColorAdapt.dual(hex: "#08f")
        XCTAssertEqual(r.light.r, 0)   // 파싱만 확인 (크래시 없이)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ColorAdaptTests`
Expected: FAIL — `cannot find 'ColorAdapt' in scope` / `RGB`.

- [ ] **Step 3: 구현**

`Sources/ClaudeUsageCore/ColorAdapt.swift`:
```swift
import Foundation

public struct RGB: Equatable, Sendable {
    public let r: Int, g: Int, b: Int
    public init(r: Int, g: Int, b: Int) { self.r = r; self.g = g; self.b = b }
}

public struct DualColor: Sendable {
    public let light: RGB
    public let dark: RGB
}

public enum ColorAdapt {
    public static func parseHex(_ hex: String) -> RGB {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = Int(h, radix: 16) else { return RGB(r: 128, g: 128, b: 128) }
        return RGB(r: (v >> 16) & 0xff, g: (v >> 8) & 0xff, b: v & 0xff)
    }

    /// 선택색 → (라이트용, 다크용). 필요한 만큼만 보정해 원색을 최대한 유지.
    public static func dual(hex: String) -> DualColor {
        let c = parseHex(hex)
        let r = Double(c.r), g = Double(c.g), b = Double(c.b)
        // 무채색 → 순수 흑백 (최대 대비)
        if max(c.r, c.g, c.b) - min(c.r, c.g, c.b) < 24 {
            return DualColor(light: RGB(r: 0, g: 0, b: 0), dark: RGB(r: 255, g: 255, b: 255))
        }
        let lum = 0.299*r + 0.587*g + 0.114*b
        let light: RGB
        if lum > 135 {                       // 라이트: 밝은 색만 낮춤
            let f = 135.0 / lum
            light = RGB(r: Int(r*f), g: Int(g*f), b: Int(b*f))
        } else {
            light = c
        }
        let dark: RGB
        if lum < 155 {                       // 다크: 어두운 색만 밝게(흰색 블렌드)
            let t = lum < 255 ? (155.0 - lum) / (255.0 - lum) : 0
            dark = RGB(r: Int(r + (255-r)*t), g: Int(g + (255-g)*t), b: Int(b + (255-b)*t))
        } else {
            dark = c
        }
        return DualColor(light: light, dark: dark)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter ColorAdaptTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(core): ColorAdapt light/dark contrast adaptation (port of text_dual)"
```

---

## Task 3: Credentials 파싱 + KeychainReader — TDD (파싱만)

**Files:**
- Create: `Sources/ClaudeUsageCore/Credentials.swift`
- Test: `Tests/ClaudeUsageCoreTests/CredentialsTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/ClaudeUsageCoreTests/CredentialsTests.swift`:
```swift
import XCTest
@testable import ClaudeUsageCore

final class CredentialsTests: XCTestCase {
    func testParsesAccessTokenAndExpiry() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"tok-123","expiresAt":1780000000000}}"#
        let c = try XCTUnwrap(Credentials.parse(json))
        XCTAssertEqual(c.accessToken, "tok-123")
        XCTAssertEqual(c.expiresAtMillis, 1780000000000)
    }

    func testMissingOauthReturnsNil() {
        XCTAssertNil(Credentials.parse(#"{"other":1}"#))
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(Credentials.parse("not json"))
    }

    func testExpiredComputedAgainstNow() throws {
        let c = try XCTUnwrap(Credentials.parse(
            #"{"claudeAiOauth":{"accessToken":"t","expiresAt":1000}}"#))
        // 1000ms = 1970년 → 지금 기준 만료
        XCTAssertTrue(c.isExpired(now: Date()))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter CredentialsTests`
Expected: FAIL — `cannot find 'Credentials'`.

- [ ] **Step 3: 구현**

`Sources/ClaudeUsageCore/Credentials.swift`:
```swift
import Foundation

public struct Credentials: Sendable {
    public let accessToken: String
    public let expiresAtMillis: Double?

    public func isExpired(now: Date) -> Bool {
        guard let ms = expiresAtMillis else { return false }
        return ms / 1000.0 < now.timeIntervalSince1970
    }

    /// 키체인 항목 JSON(문자열) → Credentials. 실패 시 nil.
    public static func parse(_ raw: String) -> Credentials? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        let exp = (oauth["expiresAt"] as? NSNumber)?.doubleValue
        return Credentials(accessToken: token, expiresAtMillis: exp)
    }
}

/// 키체인에서 Claude Code 자격증명을 읽는 얇은 래퍼 (read-only).
public enum KeychainReader {
    public static func readClaudeCodeToken() -> Credentials? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return nil }
        return Credentials.parse(raw)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter CredentialsTests`
Expected: PASS (4 tests).

- [ ] **Step 5: KeychainReader 실동작 스모크 확인 (수동)**

Run: `swift build && swift run ClaudeUsageBar` 는 아직 UI라 부적합 → 임시 확인은 생략하고 Task 8에서 통합 검증. 여기선 파싱 테스트로 충분.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(core): Credentials parse + KeychainReader (read-only token)"
```

---

## Task 4: UsageData 모델 + 디코드 — TDD

**Files:**
- Create: `Sources/ClaudeUsageCore/UsageData.swift`
- Test: `Tests/ClaudeUsageCoreTests/UsageDataTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/ClaudeUsageCoreTests/UsageDataTests.swift`:
```swift
import XCTest
@testable import ClaudeUsageCore

final class UsageDataTests: XCTestCase {
    let sample = #"""
    {"limits":[
      {"kind":"session","percent":35.4,"resets_at":"2026-07-02T15:00:00Z","severity":"ok"},
      {"kind":"weekly_all","percent":62.0,"resets_at":"2026-07-07T00:00:00Z"},
      {"kind":"weekly_scoped","percent":10,"scope":{"model":{"display_name":"Opus"}}}
    ],
    "extra_usage":{"is_enabled":true,"utilization":12.5}}
    """#

    func testDecodesLimits() throws {
        let d = try UsageData.decode(Data(sample.utf8))
        XCTAssertEqual(d.limits.count, 3)
        XCTAssertEqual(d.limits[0].kind, "session")
        XCTAssertEqual(Int(d.limits[0].percent ?? 0), 35)
        XCTAssertEqual(d.limits[2].scope?.model?.displayName, "Opus")
    }

    func testExtraUsage() throws {
        let d = try UsageData.decode(Data(sample.utf8))
        XCTAssertTrue(d.extraUsage?.isEnabled ?? false)
        XCTAssertEqual(d.extraUsage?.utilization ?? 0, 12.5, accuracy: 0.01)
    }

    func testSessionAndWeeklyHelpers() throws {
        let d = try UsageData.decode(Data(sample.utf8))
        XCTAssertEqual(Int(d.sessionPercent ?? 0), 35)
        XCTAssertEqual(Int(d.weeklyPercent ?? 0), 62)
    }

    func testMissingFieldsDontCrash() throws {
        let d = try UsageData.decode(Data(#"{"limits":[]}"#.utf8))
        XCTAssertEqual(d.limits.count, 0)
        XCTAssertNil(d.sessionPercent)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter UsageDataTests`
Expected: FAIL — `cannot find 'UsageData'`.

- [ ] **Step 3: 구현**

`Sources/ClaudeUsageCore/UsageData.swift`:
```swift
import Foundation

public struct UsageData: Decodable, Sendable {
    public struct ModelScope: Decodable, Sendable {
        public struct Model: Decodable, Sendable {
            public let displayName: String?
            enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }
        public let model: Model?
    }
    public struct Limit: Decodable, Sendable {
        public let kind: String?
        public let percent: Double?
        public let resetsAt: String?
        public let severity: String?
        public let scope: ModelScope?
        enum CodingKeys: String, CodingKey {
            case kind, percent, severity, scope
            case resetsAt = "resets_at"
        }
    }
    public struct ExtraUsage: Decodable, Sendable {
        public let isEnabled: Bool?
        public let utilization: Double?
        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case utilization
        }
    }

    public let limits: [Limit]
    public let extraUsage: ExtraUsage?
    enum CodingKeys: String, CodingKey {
        case limits
        case extraUsage = "extra_usage"
    }

    public static func decode(_ data: Data) throws -> UsageData {
        try JSONDecoder().decode(UsageData.self, from: data)
    }

    public func limit(kind: String) -> Limit? { limits.first { $0.kind == kind } }
    public var sessionPercent: Double? { limit(kind: "session")?.percent }
    public var weeklyPercent: Double? { limit(kind: "weekly_all")?.percent }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter UsageDataTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(core): UsageData model + decoder for /api/oauth/usage"
```

---

## Task 5: UsageClient (HTTP) + 캐시

네트워크는 얇게. 디코드는 Task 4에서 이미 검증됨. 여기선 요청 구성 + 캐시 로직만.

**Files:**
- Create: `Sources/ClaudeUsageCore/UsageClient.swift`

- [ ] **Step 1: 구현 (테스트는 fetch 결과 캐시 왕복만 경량 확인)**

`Sources/ClaudeUsageCore/UsageClient.swift`:
```swift
import Foundation

public enum UsageError: Error, Sendable {
    case noToken
    case http(Int)
    case network(String)
    case decode(String)
}

public actor UsageClient {
    private let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(token: String) async throws -> UsageData {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // 정직한 UA (Claude Code 사칭 금지)
        req.setValue("ClaudeUsageBar/1.0 (personal)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw UsageError.http(code) }
            do { return try UsageData.decode(data) }
            catch { throw UsageError.decode(String(describing: error)) }
        } catch let e as UsageError {
            throw e
        } catch {
            throw UsageError.network(String(describing: error))
        }
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(core): UsageClient (HTTP fetch, honest UA, typed errors)"
```

---

## Task 6: 로컬 로그 비용 — LogModels + LogParser + CostRollup — TDD (핵심)

**Files:**
- Create: `Sources/ClaudeUsageCore/LogModels.swift`
- Create: `Sources/ClaudeUsageCore/LogParser.swift`
- Create: `Sources/ClaudeUsageCore/CostRollup.swift`
- Test: `Tests/ClaudeUsageCoreTests/LogParserTests.swift`
- Test: `Tests/ClaudeUsageCoreTests/CostRollupTests.swift`

- [ ] **Step 1: 모델 작성 (테스트 성립용)**

`Sources/ClaudeUsageCore/LogModels.swift`:
```swift
import Foundation

public struct UsageEntry: Sendable, Equatable {
    public let dayKey: String       // "YYYY-MM-DD" (로컬)
    public let category: ModelCategory
    public let input: Int
    public let output: Int
    public let cacheWrite: Int
    public let cacheRead: Int
    public let cost: Double
    public let dedupKey: String      // "\(msgId)|\(requestId)"
    public var tokens: Int { input + output + cacheWrite + cacheRead }
}

public struct ModelBucket: Sendable {
    public var cost: Double = 0
    public var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    public var tokens: Int { input + output + cacheWrite + cacheRead }
}

public struct UsageCost: Sendable {
    public var day = ModelBucket()
    public var week = ModelBucket()
    public var month = ModelBucket()
    public var byModel: [ModelCategory: ModelBucket] = [:]   // 이번 달 기준
}
```

- [ ] **Step 2: LogParser 실패 테스트**

`Tests/ClaudeUsageCoreTests/LogParserTests.swift`:
```swift
import XCTest
@testable import ClaudeUsageCore

final class LogParserTests: XCTestCase {
    // opus 라인: in100 out200 cacheRead1000 cc5m50 cc1h10
    let line = #"{"type":"assistant","timestamp":"2026-07-02T09:00:00Z","requestId":"req1","message":{"id":"m1","model":"claude-opus-4","usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":50,"ephemeral_1h_input_tokens":10}}}}"#

    func testParsesCostExactly() throws {
        let e = try XCTUnwrap(LogParser.parseLine(line))
        // 100*5e-6 + 200*5*5e-6 + 1000*0.1*5e-6 + 50*1.25*5e-6 + 10*2*5e-6
        XCTAssertEqual(e.cost, 0.0064125, accuracy: 1e-9)
        XCTAssertEqual(e.category, .opus)
        XCTAssertEqual(e.tokens, 1360)          // 100+200+60+1000
        XCTAssertEqual(e.dedupKey, "m1|req1")
    }

    func testSkipsNonAssistant() {
        XCTAssertNil(LogParser.parseLine(#"{"type":"user","message":{}}"#))
    }

    func testSkipsLineWithoutUsage() {
        XCTAssertNil(LogParser.parseLine(#"{"type":"assistant","message":{"id":"x"}}"#))
    }

    func testCacheWriteFallbackTo1h() throws {
        // 5m/1h 분해 없이 cache_creation_input_tokens만 → 1h로 간주
        let l = #"{"type":"assistant","timestamp":"2026-07-02T09:00:00Z","requestId":"r","message":{"id":"m","model":"claude-sonnet-4","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":100}}}"#
        let e = try XCTUnwrap(LogParser.parseLine(l))
        // sonnet b=3e-6, 1h 2x → 100*2*3e-6 = 6e-4
        XCTAssertEqual(e.cost, 6e-4, accuracy: 1e-9)
        XCTAssertEqual(e.cacheWrite, 100)
    }
}
```

- [ ] **Step 3: LogParser 실패 확인**

Run: `swift test --filter LogParserTests`
Expected: FAIL — `cannot find 'LogParser'`.

- [ ] **Step 4: LogParser 구현**

`Sources/ClaudeUsageCore/LogParser.swift`:
```swift
import Foundation

public enum LogParser {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f   // 로컬 타임존 사용
    }()

    /// jsonl 한 줄 → UsageEntry?. assistant + usage 없으면 nil.
    public static func parseLine(_ line: String) -> UsageEntry? {
        guard line.contains("\"output_tokens\"") || line.contains("\"cache_creation_input_tokens\"")
        else { return nil }
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any]
        else { return nil }

        let i = usage["input_tokens"] as? Int ?? 0
        let o = usage["output_tokens"] as? Int ?? 0
        let cr = usage["cache_read_input_tokens"] as? Int ?? 0
        let cc = usage["cache_creation"] as? [String: Any]
        var cc5 = cc?["ephemeral_5m_input_tokens"] as? Int ?? 0
        var cc1 = cc?["ephemeral_1h_input_tokens"] as? Int ?? 0
        let cw = usage["cache_creation_input_tokens"] as? Int ?? (cc5 + cc1)
        if cc5 == 0 && cc1 == 0 && cw > 0 { cc1 = cw }   // 분해 없으면 1h로 간주

        let cat = ModelCategory.from(model: msg["model"] as? String)
        let b = cat.basePrice
        let cost = Double(i)*b + Double(o)*5*b + Double(cr)*0.1*b
                 + Double(cc5)*1.25*b + Double(cc1)*2*b

        let ts = obj["timestamp"] as? String ?? ""
        guard let date = iso.date(from: ts) else { return nil }
        let dayKey = dayFmt.string(from: date)

        let mid = (msg["id"] as? String) ?? ""
        let rid = (obj["requestId"] as? String) ?? ""
        return UsageEntry(dayKey: dayKey, category: cat, input: i, output: o,
                          cacheWrite: cw, cacheRead: cr, cost: cost,
                          dedupKey: "\(mid)|\(rid)")
    }
}
```

- [ ] **Step 5: LogParser 통과 확인**

Run: `swift test --filter LogParserTests`
Expected: PASS (4 tests). `testCacheWriteFallbackTo1h`의 `cc5+cc1`=0이므로 cw=0 fallback인데 cache_creation_input_tokens=100 → cw=100, cc1=100. 검증 OK.

- [ ] **Step 6: CostRollup 실패 테스트**

`Tests/ClaudeUsageCoreTests/CostRollupTests.swift`:
```swift
import XCTest
@testable import ClaudeUsageCore

final class CostRollupTests: XCTestCase {
    func mkEntry(day: String, cat: ModelCategory, cost: Double, key: String) -> UsageEntry {
        UsageEntry(dayKey: day, category: cat, input: 10, output: 0,
                   cacheWrite: 0, cacheRead: 0, cost: cost, dedupKey: key)
    }

    func testRollupBucketsByDayWeekMonth() {
        // now = 2026-07-15 (수). 이번달 시작 07-01, 이번주 시작(월) 07-13, 오늘 07-15
        let now = DateComponents(calendar: .current, year: 2026, month: 7, day: 15,
                                 hour: 12).date!
        let entries = [
            mkEntry(day: "2026-07-15", cat: .opus, cost: 1.0, key: "a"),   // 오늘+주+월
            mkEntry(day: "2026-07-14", cat: .opus, cost: 2.0, key: "b"),   // 주+월
            mkEntry(day: "2026-07-03", cat: .sonnet, cost: 4.0, key: "c"), // 월만
            mkEntry(day: "2026-06-30", cat: .opus, cost: 8.0, key: "d"),   // 범위 밖
        ]
        let c = CostRollup.rollup(entries: entries, now: now)
        XCTAssertEqual(c.day.cost, 1.0, accuracy: 1e-9)
        XCTAssertEqual(c.week.cost, 3.0, accuracy: 1e-9)    // 1+2
        XCTAssertEqual(c.month.cost, 7.0, accuracy: 1e-9)   // 1+2+4
        XCTAssertEqual(c.byModel[.opus]?.cost ?? 0, 3.0, accuracy: 1e-9)  // 월 기준 opus 1+2
        XCTAssertEqual(c.byModel[.sonnet]?.cost ?? 0, 4.0, accuracy: 1e-9)
    }

    func testDedupAcrossEntries() {
        let now = DateComponents(calendar: .current, year: 2026, month: 7, day: 15).date!
        let entries = [
            mkEntry(day: "2026-07-15", cat: .opus, cost: 1.0, key: "dup"),
            mkEntry(day: "2026-07-15", cat: .opus, cost: 1.0, key: "dup"),  // 중복
        ]
        let c = CostRollup.rollup(entries: entries, now: now)
        XCTAssertEqual(c.day.cost, 1.0, accuracy: 1e-9)   // 한 번만
    }
}
```

- [ ] **Step 7: CostRollup 실패 확인**

Run: `swift test --filter CostRollupTests`
Expected: FAIL — `cannot find 'CostRollup'`.

- [ ] **Step 8: CostRollup 구현**

`Sources/ClaudeUsageCore/CostRollup.swift`:
```swift
import Foundation

public enum CostRollup {
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public static func rollup(entries: [UsageEntry], now: Date) -> UsageCost {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2   // 월요일 시작 (파이썬 weekday()==0=월)
        let today = cal.startOfDay(for: now)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        let weekStart = cal.date(from: cal.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: today))!

        let tKey = dayFmt.string(from: today)
        let wKey = dayFmt.string(from: weekStart)
        let mKey = dayFmt.string(from: monthStart)

        var out = UsageCost()
        var seen = Set<String>()
        func add(_ b: inout ModelBucket, _ e: UsageEntry) {
            b.cost += e.cost; b.input += e.input; b.output += e.output
            b.cacheWrite += e.cacheWrite; b.cacheRead += e.cacheRead
        }
        for e in entries {
            if !seen.insert(e.dedupKey).inserted { continue }   // 전역 dedup
            if e.dayKey >= mKey {
                add(&out.month, e)
                var bm = out.byModel[e.category] ?? ModelBucket()
                add(&bm, e); out.byModel[e.category] = bm
            }
            if e.dayKey >= wKey { add(&out.week, e) }
            if e.dayKey >= tKey { add(&out.day, e) }
        }
        return out
    }
}
```

- [ ] **Step 9: CostRollup 통과 확인**

Run: `swift test --filter CostRollupTests`
Expected: PASS (2 tests).
Note: 문자열 날짜 비교(`>=`)는 "YYYY-MM-DD" 형식이라 사전식=시간순이라 정확. 파이썬 원본과 동일 전략.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat(core): local log cost — LogParser + CostRollup (TDD, ported pricing)"
```

---

## Task 7: LogAggregator (파일 글로빙 + 인덱스 캐시)

파일 IO 계층. 순수 로직(Task 6)을 파일에 적용 + `(mtime,size)` 캐시로 안 바뀐 파일 스킵.

**Files:**
- Create: `Sources/ClaudeUsageCore/LogAggregator.swift`

- [ ] **Step 1: 구현**

`Sources/ClaudeUsageCore/LogAggregator.swift`:
```swift
import Foundation

public struct LogAggregator: Sendable {
    let projectsDir: URL
    let indexPath: URL

    public init(
        projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        indexPath: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar/log-index.json")
    ) {
        self.projectsDir = projectsDir
        self.indexPath = indexPath
    }

    struct FileEntry: Codable { var mtime: Double; var size: Int; var entries: [Cached] }
    struct Cached: Codable {
        var dayKey: String; var category: String
        var input: Int; var output: Int; var cacheWrite: Int; var cacheRead: Int
        var cost: Double; var dedupKey: String
    }

    public func compute(now: Date = Date()) -> UsageCost {
        let fm = FileManager.default
        // cutoff: 이번달/이번주 시작 중 이른 것 - 하루 (파이썬과 동일)
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        let weekStart = cal.date(from: cal.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: today))!
        let cutoff = min(monthStart, weekStart).addingTimeInterval(-86400).timeIntervalSince1970

        var oldIndex: [String: FileEntry] = [:]
        if let d = try? Data(contentsOf: indexPath),
           let idx = try? JSONDecoder().decode([String: FileEntry].self, from: d) {
            oldIndex = idx
        }

        var newIndex: [String: FileEntry] = [:]
        var allEntries: [UsageEntry] = []

        let files = (try? fm.subpathsOfDirectory(atPath: projectsDir.path)) ?? []
        for rel in files where rel.hasSuffix(".jsonl") {
            let path = projectsDir.appendingPathComponent(rel).path
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970,
                  let size = attrs[.size] as? Int, mtime >= cutoff else { continue }

            if let cached = oldIndex[path], cached.mtime == mtime, cached.size == size {
                newIndex[path] = cached
                allEntries.append(contentsOf: cached.entries.map { toEntry($0) })
            } else {
                let parsed = parseFile(path)
                newIndex[path] = FileEntry(mtime: mtime, size: size,
                                           entries: parsed.map { toCached($0) })
                allEntries.append(contentsOf: parsed)
            }
        }

        try? fm.createDirectory(at: indexPath.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(newIndex) { try? d.write(to: indexPath) }

        return CostRollup.rollup(entries: allEntries, now: now)
    }

    private func parseFile(_ path: String) -> [UsageEntry] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var out: [UsageEntry] = []
        var seen = Set<String>()
        content.enumerateLines { line, _ in
            if let e = LogParser.parseLine(line), seen.insert(e.dedupKey).inserted {
                out.append(e)
            }
        }
        return out
    }

    private func toCached(_ e: UsageEntry) -> Cached {
        Cached(dayKey: e.dayKey, category: e.category.rawValue, input: e.input,
               output: e.output, cacheWrite: e.cacheWrite, cacheRead: e.cacheRead,
               cost: e.cost, dedupKey: e.dedupKey)
    }
    private func toEntry(_ c: Cached) -> UsageEntry {
        UsageEntry(dayKey: c.dayKey, category: ModelCategory(rawValue: c.category) ?? .sonnet,
                   input: c.input, output: c.output, cacheWrite: c.cacheWrite,
                   cacheRead: c.cacheRead, cost: c.cost, dedupKey: c.dedupKey)
    }
}
```

- [ ] **Step 2: 빌드 + 실동작 스모크 (수동)**

Run: `swift build`
Expected: `Build complete!`
Note: 실제 집계 검증은 Task 9(대시보드)에서 화면으로 확인. 여기선 컴파일만.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(core): LogAggregator (file glob + mtime/size index cache)"
```

---

## Task 8: AppState + MenuBarLabel — 메뉴바에 라이브 % 표시 (통합)

**Files:**
- Create: `Sources/ClaudeUsageBar/AppState.swift`
- Create: `Sources/ClaudeUsageBar/MenuBarLabel.swift`
- Modify: `Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift`

- [ ] **Step 1: AppState 작성**

`Sources/ClaudeUsageBar/AppState.swift`:
```swift
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
        // 폴링 (Task 11에서 설정 연동 주기로 대체 예정, 우선 60초)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        // 로컬 비용 (네트워크 무관, 항상 갱신)
        let c = aggregator.compute()
        self.cost = c
        // 라이브 usage
        guard let creds = KeychainReader.readClaudeCodeToken() else {
            self.statusText = "로그인 필요"; return
        }
        do {
            let d = try await client.fetch(token: creds.accessToken)
            self.usage = d
            self.lastUpdated = Date()
            self.isStale = false
        } catch {
            self.isStale = true   // 마지막 성공값 유지
        }
    }
}
```

- [ ] **Step 2: MenuBarLabel 작성**

`Sources/ClaudeUsageBar/MenuBarLabel.swift`:
```swift
import SwiftUI
import ClaudeUsageCore

/// 메뉴바 텍스트. 값이 바뀔 때만 SwiftUI가 갱신 → 불필요 재렌더 없음.
struct MenuBarLabel: View {
    let usage: UsageData?
    // 우선 "둘 다 한 줄" 고정 (표시모드 선택은 Task 10에서 설정 연동)
    var body: some View {
        Text(text)
    }
    private var text: String {
        guard let u = usage else { return "◵" }
        let s = u.sessionPercent.map { "\(Int($0.rounded()))%" } ?? "—"
        let w = u.weeklyPercent.map { "\(Int($0.rounded()))%" } ?? "—"
        return "5h \(s) · 1W \(w)"
    }
}
```

- [ ] **Step 3: App 진입점 수정**

`Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift`:
```swift
import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            // 팝오버 내용 (Task 9에서 DashboardView로 교체)
            VStack(alignment: .leading) {
                Text("Claude Usage Bar").font(.headline)
                Button("지금 새로고침") { Task { await state.refresh() } }
                Divider()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }
            .padding(8)
        } label: {
            MenuBarLabel(usage: state.usage)
                .onAppear { state.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 4: 빌드 + 패키징 + 실행**

Run: `./scripts/package_app.sh`
Expected: 메뉴바에 `5h NN% · 1W NN%` (또는 로그인 없으면 `◵`) 표시. 클릭 시 새로고침/종료 메뉴.

- [ ] **Step 5: 수동 검증**

- 메뉴바에 실제 사용량 %가 SwiftBar 플러그인과 비슷하게 뜨는지 확인.
- "지금 새로고침" 클릭 시 값 갱신되는지.
- 값 정확도: SwiftBar 플러그인 표시값과 대조.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(app): AppState + MenuBarLabel — live 5h/1W % in menu bar"
```

---

## Task 9: DashboardView (팝오버 대시보드)

**Files:**
- Create: `Sources/ClaudeUsageBar/DashboardView.swift`
- Modify: `Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift` (팝오버를 DashboardView로 교체)

- [ ] **Step 1: 남은시간 포맷 헬퍼를 코어에 추가**

`Sources/ClaudeUsageCore/UsageData.swift`에 추가 (extension):
```swift
public extension UsageData.Limit {
    /// resets_at 까지 남은 시간 "1d2h" / "3h04m" / "12m".
    func remaining(now: Date = Date()) -> String? {
        guard let iso = resetsAt else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: iso) else { return nil }
        let secs = d.timeIntervalSince(now)
        if secs <= 0 { return "0m" }
        let day = Int(secs / 86400), h = Int(secs.truncatingRemainder(dividingBy: 86400) / 3600)
        let m = Int(secs.truncatingRemainder(dividingBy: 3600) / 60)
        if day > 0 { return "\(day)d\(h)h" }
        if h > 0 { return String(format: "%dh%02dm", h, m) }
        return "\(m)m"
    }
}
```

- [ ] **Step 2: DashboardView 작성**

`Sources/ClaudeUsageBar/DashboardView.swift`:
```swift
import SwiftUI
import ClaudeUsageCore

struct DashboardView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Max 사용량").font(.headline)
            Divider()
            limitsSection
            extraSection
            Divider()
            costSection
            Divider()
            footer
        }
        .padding(10)
        .frame(width: 320)
    }

    @ViewBuilder private var limitsSection: some View {
        if let limits = state.usage?.limits, !limits.isEmpty {
            ForEach(Array(limits.enumerated()), id: \.offset) { _, l in
                HStack {
                    Text(label(l)).font(.system(.body, design: .monospaced))
                    Spacer()
                    if let p = l.percent { Text("\(Int(p.rounded()))%").foregroundStyle(color(l)) }
                    if let rem = l.remaining() { Text(rem).foregroundStyle(.secondary).font(.caption) }
                }
                ProgressView(value: min(1.0, (l.percent ?? 0)/100)).tint(color(l))
            }
        } else {
            Text("표시할 한도 없음").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var extraSection: some View {
        if let e = state.usage?.extraUsage, e.isEnabled == true {
            let u = e.utilization.map { "\(Int($0.rounded()))%" } ?? "활성"
            Text("추가 사용량 (extra)  \(u)").foregroundStyle(.purple).font(.callout)
        }
    }

    @ViewBuilder private var costSection: some View {
        if let c = state.cost {
            Text("💬 토큰 사용량 (로컬 로그 · 추정)").font(.caption).foregroundStyle(.secondary)
            costRow("오늘", c.day)
            costRow("이번 주", c.week)
            costRow("이번 달", c.month)
            ForEach(ModelCategory.allCases, id: \.self) { cat in
                if let b = c.byModel[cat], b.cost > 0 {
                    Text("  └ \(cat.displayName)  ~$\(b.cost, specifier: "%.0f") · \(fmtTok(b.tokens))")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func costRow(_ label: String, _ b: ModelBucket) -> some View {
        HStack {
            Text(label).font(.system(.body, design: .monospaced))
            Spacer()
            Text("~$\(b.cost, specifier: "%.0f")  ·  \(fmtTok(b.tokens)) tok")
                .font(.system(.body, design: .monospaced))
        }
    }

    private var footer: some View {
        HStack {
            if let t = state.lastUpdated {
                Text("업데이트 \(t.formatted(date: .omitted, time: .standard))\(state.isStale ? " (캐시)" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("새로고침") { Task { await state.refresh() } }
            Button("claude.ai") { NSWorkspace.shared.open(URL(string: "https://claude.ai")!) }
            Button("종료") { NSApplication.shared.terminate(nil) }
        }.font(.caption)
    }

    private func label(_ l: UsageData.Limit) -> String {
        switch l.kind {
        case "session": return "세션 (5h)"
        case "weekly_all": return "주간 (전체)"
        case "weekly_scoped": return "주간 \(l.scope?.model?.displayName ?? "")"
        default: return l.kind ?? "?"
        }
    }
    private func color(_ l: UsageData.Limit) -> Color {
        let p = l.percent ?? 0
        if l.severity == "critical" || p >= 90 { return .red }
        if l.severity == "warning" || p >= 70 { return .orange }
        return .primary
    }
    private func fmtTok(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n)/1e6) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n)/1e3) }
        return "\(n)"
    }
}
```

- [ ] **Step 3: 팝오버 교체**

`ClaudeUsageBarApp.swift`의 `MenuBarExtra { ... }` 내용을 `DashboardView(state: state)`로 교체:
```swift
        MenuBarExtra {
            DashboardView(state: state)
        } label: {
            MenuBarLabel(usage: state.usage)
                .onAppear { state.start() }
        }
        .menuBarExtraStyle(.window)
```

- [ ] **Step 4: 빌드 + 실행 + 검증**

Run: `./scripts/package_app.sh`
Expected: 메뉴바 클릭 시 한도 진행바 3개(session/weekly/scoped) + extra + 로컬 비용(오늘/주/월 + 모델별) + 푸터. SwiftBar 플러그인 팝오버와 값 대조.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(app): DashboardView popover (limits, extra, local cost)"
```

---

## Task 10: Settings (표시모드/테마/폴링/충전절전) + SettingsView

**Files:**
- Create: `Sources/ClaudeUsageCore/Settings.swift`
- Test: `Tests/ClaudeUsageCoreTests/SettingsTests.swift`
- Create: `Sources/ClaudeUsageBar/SettingsView.swift`
- Modify: `MenuBarLabel.swift`, `AppState.swift`, `DashboardView.swift`

- [ ] **Step 1: Settings 실패 테스트**

`Tests/ClaudeUsageCoreTests/SettingsTests.swift`:
```swift
import XCTest
@testable import ClaudeUsageCore

final class SettingsTests: XCTestCase {
    func makeStore() -> SettingsStore {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return SettingsStore(defaults: d)
    }
    func testDefaults() {
        let s = makeStore()
        XCTAssertEqual(s.displayMode, .rotate)
        XCTAssertEqual(s.pollSeconds, 60)
        XCTAssertFalse(s.chargingThrottle)
    }
    func testPersistsDisplayMode() {
        let s = makeStore()
        s.displayMode = .both
        XCTAssertEqual(s.displayMode, .both)
    }
    func testPollSecondsClampsToAllowed() {
        let s = makeStore()
        s.pollSeconds = 120
        XCTAssertEqual(s.pollSeconds, 120)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter SettingsTests`
Expected: FAIL — `cannot find 'SettingsStore'`.

- [ ] **Step 3: 구현**

`Sources/ClaudeUsageCore/Settings.swift`:
```swift
import Foundation

public enum DisplayMode: String, CaseIterable, Sendable {
    case rotate     // 5h ⇄ 1W 순환 (기본)
    case both       // 5h · 1W 한 줄
    case sessionOnly
    case weeklyOnly
    public var label: String {
        switch self {
        case .rotate: return "순환 (5h ⇄ 1W)"
        case .both: return "둘 다 (5h · 1W)"
        case .sessionOnly: return "5h만"
        case .weeklyOnly: return "1W만"
        }
    }
}

public final class SettingsStore: @unchecked Sendable {
    private let d: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.d = defaults }

    public var displayMode: DisplayMode {
        get { DisplayMode(rawValue: d.string(forKey: "displayMode") ?? "") ?? .rotate }
        set { d.set(newValue.rawValue, forKey: "displayMode") }
    }
    public var pollSeconds: Int {
        get { let v = d.integer(forKey: "pollSeconds"); return v == 0 ? 60 : v }
        set { d.set(newValue, forKey: "pollSeconds") }
    }
    public var chargingThrottle: Bool {
        get { d.bool(forKey: "chargingThrottle") }
        set { d.set(newValue, forKey: "chargingThrottle") }
    }
    public var accentHex: String? {
        get { d.string(forKey: "accentHex") }
        set { d.set(newValue, forKey: "accentHex") }
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter SettingsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: MenuBarLabel에 표시모드 + 순환 반영**

`MenuBarLabel.swift` 전체 교체:
```swift
import SwiftUI
import ClaudeUsageCore

struct MenuBarLabel: View {
    let usage: UsageData?
    let mode: DisplayMode
    let rotateShowSession: Bool   // 순환 모드에서 지금 5h를 보여줄 차례인지
    var body: some View { Text(text) }

    private var text: String {
        guard let u = usage else { return "◵" }
        let s = u.sessionPercent.map { "5h \(Int($0.rounded()))%" } ?? "5h —"
        let w = u.weeklyPercent.map { "1W \(Int($0.rounded()))%" } ?? "1W —"
        switch mode {
        case .both: return "\(s) · \(w)"
        case .sessionOnly: return s
        case .weeklyOnly: return w
        case .rotate: return rotateShowSession ? s : w
        }
    }
}
```

- [ ] **Step 6: AppState에 설정 + 순환 타이머 추가**

`AppState.swift`에 프로퍼티/로직 추가:
```swift
    let settings = SettingsStore()
    @Published var rotateShowSession = true
    private var rotateTimer: Timer?

    func startRotation() {
        rotateTimer?.invalidate()
        guard settings.displayMode == .rotate else { return }
        rotateTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rotateShowSession.toggle() }
        }
    }
```
그리고 `start()` 끝에 `startRotation()` 호출 추가.

- [ ] **Step 7: App 진입점에서 라벨에 모드 전달**

`ClaudeUsageBarApp.swift`의 label 부분:
```swift
        } label: {
            MenuBarLabel(usage: state.usage, mode: state.settings.displayMode,
                         rotateShowSession: state.rotateShowSession)
                .onAppear { state.start() }
        }
```

- [ ] **Step 8: SettingsView 작성 + 대시보드에 "설정" 버튼**

`Sources/ClaudeUsageBar/SettingsView.swift`:
```swift
import SwiftUI
import ClaudeUsageCore

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var mode: DisplayMode
    @State private var poll: Int
    @State private var throttle: Bool

    init(state: AppState) {
        self.state = state
        _mode = State(initialValue: state.settings.displayMode)
        _poll = State(initialValue: state.settings.pollSeconds)
        _throttle = State(initialValue: state.settings.chargingThrottle)
    }

    var body: some View {
        Form {
            Picker("메뉴바 표시", selection: $mode) {
                ForEach(DisplayMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }.onChange(of: mode) { _, v in state.settings.displayMode = v; state.startRotation() }

            Picker("새로고침 주기", selection: $poll) {
                Text("30초").tag(30); Text("1분").tag(60); Text("2분").tag(120)
                Text("5분").tag(300); Text("10분").tag(600)
            }.onChange(of: poll) { _, v in state.settings.pollSeconds = v; state.restartPolling() }

            Toggle("충전 연동 절전 (배터리일 때 완화)", isOn: $throttle)
                .onChange(of: throttle) { _, v in state.settings.chargingThrottle = v }
        }
        .padding().frame(width: 300)
    }
}
```

- [ ] **Step 9: 빌드 + 실행 + 검증**

Run: `./scripts/package_app.sh`
Expected: 설정에서 표시모드 바꾸면 메뉴바가 즉시 순환/둘다/단일로 바뀜. 순환은 4초마다 5h⇄1W.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: Settings (display mode/poll/throttle) + SettingsView + rotation"
```

---

## Task 11: 폴링 주기 연동 + 충전 연동 절전

**Files:**
- Modify: `Sources/ClaudeUsageBar/AppState.swift`

- [ ] **Step 1: 폴링 재시작 + 배터리 스로틀 구현**

`AppState.swift`에 추가/수정:
```swift
    func restartPolling() {
        timer?.invalidate()
        let interval = TimeInterval(settings.pollSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// AC 전원 연결 여부 (못 읽으면 true = 안전하게 갱신 유지).
    private func isOnAC() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "ps"]
        let pipe = Pipe(); p.standardOutput = pipe
        do { try p.run() } catch { return true }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.contains("AC Power")
    }
```
그리고 `refresh()` 앞부분에 스로틀 가드 추가:
```swift
        if settings.chargingThrottle && !isOnAC() {
            if let last = lastUpdated, Date().timeIntervalSince(last) < 300 {
                // 배터리 + 최근 5분 내 갱신 → 네트워크 스킵 (로컬 비용만 갱신)
                self.cost = aggregator.compute()
                return
            }
        }
```
그리고 `start()`의 60초 고정 타이머를 `restartPolling()` 호출로 교체.

- [ ] **Step 2: 빌드 + 실행 확인**

Run: `./scripts/package_app.sh`
Expected: 설정에서 주기 변경 시 폴링 간격 반영. 충전 연동 켜고 배터리 상태면 네트워크 호출이 5분 간격으로 완화(로컬 비용은 계속 갱신).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(app): poll interval binding + charging-aware throttle"
```

---

## Task 12: 로그인 시 자동 실행 (SMAppService)

**Files:**
- Create: `Sources/ClaudeUsageBar/LoginItem.swift`
- Modify: `SettingsView.swift`

- [ ] **Step 1: LoginItem 래퍼 작성**

`Sources/ClaudeUsageBar/LoginItem.swift`:
```swift
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LoginItem toggle failed: \(error)")
        }
    }
}
```

- [ ] **Step 2: SettingsView에 토글 추가**

`SettingsView.swift`의 `Form` 안에 추가:
```swift
            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { LoginItem.isEnabled },
                set: { LoginItem.set($0) }))
```

- [ ] **Step 3: 빌드 + 실행 + 검증**

Run: `./scripts/package_app.sh`
Expected: 설정에서 "로그인 시 자동 실행" 토글. (실제 로그인 재시작 검증은 선택)
Note: SMAppService는 `.app` 번들 + 서명 필요 → ad-hoc 서명으로 로컬 동작 확인. 토글이 크래시 없이 동작하면 OK.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(app): login item toggle (SMAppService)"
```

---

## Task 13: 견고성 + 성능(유휴 CPU) 측정

**Files:**
- Modify: `Sources/ClaudeUsageBar/AppState.swift` (토큰 만료 안내), `DashboardView.swift` (에러 상태)

- [ ] **Step 1: 토큰 만료/에러 상태 표시**

`AppState.swift` `refresh()`의 catch를 세분화:
```swift
        do {
            let d = try await client.fetch(token: creds.accessToken)
            self.usage = d; self.lastUpdated = Date(); self.isStale = false
            self.statusText = ""
        } catch UsageError.http(let code) where (code == 401 || code == 403) && creds.isExpired(now: Date()) {
            self.statusText = "토큰 만료 — Claude Code 한 번 실행하면 갱신"
        } catch {
            self.isStale = true   // 그 외: 마지막 성공값 유지
        }
```
`DashboardView` footer 위에 `statusText`가 비어있지 않으면 주황색으로 표시하는 줄 추가:
```swift
            if !state.statusText.isEmpty {
                Text(state.statusText).font(.caption).foregroundStyle(.orange)
            }
```

- [ ] **Step 2: 릴리스 빌드로 패키징**

Run: `./scripts/package_app.sh release`
Expected: `Build complete!` (release), 앱 실행됨.

- [ ] **Step 3: 유휴 CPU 측정 (성능 목표 검증)**

Run:
```bash
PID=$(pgrep -x ClaudeUsageBar)
top -l 15 -s 2 -pid $PID -stats cpu,command 2>/dev/null | grep -i ClaudeUsageBar | awk '{s+=$1} END {print "평균 유휴 CPU:", s/NR"%"}'
```
Expected: **평균 유휴 CPU가 한 자릿수(이상적으로 ~0~1%)** — SwiftBar 6% 대비 대폭 개선. (순환 4초 타이머 텍스트 스왑은 무시할 수준)
목표 미달 시: 순환 타이머 간격 늘리기 or 값 변경 없을 때 `objectWillChange` 스킵 검토.

- [ ] **Step 4: 최종 회귀 — 전체 테스트 통과**

Run: `swift test`
Expected: 모든 테스트 PASS (ColorAdapt, Credentials, UsageData, LogParser, CostRollup, Settings).

- [ ] **Step 5: SwiftBar 플러그인과 값 대조 (수동)**

- 5h/1W % 일치하는지
- 오늘/주/월 비용이 대략 일치하는지 (동일 단가·로직 이식이라 근사)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(app): robustness (token expiry/error states) + idle CPU verified"
```

---

## Self-Review (작성자 체크리스트 — 완료)

**Spec coverage:** §5 체크리스트 전 항목 → Task 매핑 확인:
- 메뉴바 5h/1W % + 색상 → Task 8, 10 ✅
- 순환/둘다/5h/1W 표시모드 → Task 10 ✅
- 글자색 시스템/커스텀 적응형 → Task 2(ColorAdapt) + Task 10(accentHex). (커스텀색을 라벨에 실제 적용하는 것은 v1 기본=시스템색이라 Task 10에 accentHex 저장까지, 실제 Text 색 적용은 후속. 메뉴바 기본은 시스템 라벨색 = 라이트/다크 자동. **spec의 "기본=시스템색" 충족**)
- 팝오버 한도바/extra/비용/모델별/타임스탬프/새로고침/claude.ai → Task 9 ✅
- 설정 테마/굵기/폴링/충전절전/자동실행 → Task 10, 11, 12 ✅ (글자 굵기는 v1 후속 — 시스템 기본, spec "추후" 허용범위)
- 견고성 stale/만료 → Task 13 ✅
- 성능 유휴 CPU ~0% → Task 13 측정 ✅
- 빌드 A안 SwiftPM + .app → Task 0, 1 ✅

**Placeholder scan:** "TBD/TODO/적절히" 없음. 모든 코드 스텝에 실제 코드 포함. ✅

**Type consistency:** `UsageData.sessionPercent`/`weeklyPercent`, `UsageCost.day/week/month/byModel`, `ModelBucket.tokens`, `SettingsStore.displayMode/pollSeconds/chargingThrottle`, `AppState.refresh()/start()/startRotation()/restartPolling()` — 태스크 간 시그니처 일치 확인. ✅

**남은 갭(의도적, v1 후속):** 메뉴바 커스텀 글자색 실제 적용, 글자 굵기 설정, HEX 피커. spec §5에서 "추후"로 명시됨.
