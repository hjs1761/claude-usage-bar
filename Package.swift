// swift-tools-version:5.9
import PackageDescription

// XCTest는 Xcode.app에만 포함됨(CommandLineTools엔 없음).
// 그래서 테스트는 별도 실행형 타겟 CoreTests + 경량 Harness로 구동한다.
//   실행: swift run CoreTests   (실패 시 exit 1)
let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    products: [
        // 외부 앱(TokenTally)이 로컬 경로로 의존해 공유하는 순수 코어 + 대시보드 UI
        .library(name: "ClaudeUsageCore", targets: ["ClaudeUsageCore"]),
        .library(name: "DashboardUI", targets: ["DashboardUI"]),
    ],
    targets: [
        // 순수 로직 (네트워크/키체인 0) — App Store 앱(TokenTally)이 공유하는 코어
        .target(name: "ClaudeUsageCore"),
        // 네트워크/키체인 (개인용 Bar 앱 전용, App Store 앱엔 미포함)
        .target(name: "ClaudeUsageLive", dependencies: ["ClaudeUsageCore"]),
        // 사용량 대시보드 UI (SwiftUI+Charts) — 개인용 앱과 TokenTally가 공유. 데이터원은 loader 주입.
        .target(name: "DashboardUI", dependencies: ["ClaudeUsageCore"]),
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["ClaudeUsageCore", "ClaudeUsageLive", "DashboardUI"]
        ),
        .executableTarget(
            name: "CoreTests",
            dependencies: ["ClaudeUsageCore", "ClaudeUsageLive"]
        ),
    ]
)
