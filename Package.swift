// swift-tools-version:5.9
import PackageDescription

// XCTest는 Xcode.app에만 포함됨(CommandLineTools엔 없음).
// 그래서 테스트는 별도 실행형 타겟 CoreTests + 경량 Harness로 구동한다.
//   실행: swift run CoreTests   (실패 시 exit 1)
let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeUsageCore"),
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["ClaudeUsageCore"]
        ),
        .executableTarget(
            name: "CoreTests",
            dependencies: ["ClaudeUsageCore"]
        ),
    ]
)
