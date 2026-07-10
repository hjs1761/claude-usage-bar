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
