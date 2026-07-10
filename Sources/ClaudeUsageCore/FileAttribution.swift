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
