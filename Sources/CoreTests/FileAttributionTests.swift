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
            ["type": "tool_use", "name": "Grep",
             "input": ["pattern": "TODO", "path": "/Users/hjs/projects/ledger"]],
        ]
        let paths = FileAttribution.extractPaths(fromContent: content)
        h.expect(paths.contains("/Users/hjs/develop/네오팜운영/a.php"), "Edit file_path 추출")
        h.expect(paths.contains { $0.hasPrefix("~/projects/ledger/app") }, "Bash 경로 추출")
        h.expect(paths.contains("/Users/hjs/projects/ledger"), "Grep path 추출")
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

    h.run("LogParser.projectByFiles (raw, 턴단위)") {
        let home2 = "/Users/hjs"
        // usage + Edit(네오팜운영) 있는 assistant 라인
        let line = #"{"type":"assistant","timestamp":"2026-07-10T01:00:00.000Z","message":{"model":"claude-sonnet-4","id":"m1","usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/hjs/develop/네오팜운영/a.php"}}]}}"#
        let e = LogParser.parseLine(line, project: "develop", home: home2)
        h.expectEqual(e?.projectByFiles, "네오팜운영", "턴 내 Edit → 네오팜운영")
        // 파일 신호 없는 턴 → raw ""
        let line2 = #"{"type":"assistant","timestamp":"2026-07-10T01:00:00.000Z","message":{"model":"claude-sonnet-4","id":"m2","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"hi"}]}}"#
        h.expectEqual(LogParser.parseLine(line2, project: "develop", home: home2)?.projectByFiles, "", "파일 없음 → raw \"\"")
    }

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
}
