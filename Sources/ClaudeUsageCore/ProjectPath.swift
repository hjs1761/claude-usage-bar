import Foundation

/// `~/.claude/projects` 아래 파일의 상대경로에서 프로젝트를 식별한다.
/// Claude Code는 cwd 경로를 `-Users-me-develop` 처럼 폴더명으로 인코딩해 저장한다.
public enum ProjectPath {
    /// 상대경로의 첫 경로요소(= 프로젝트 폴더명). 폴더 없이 파일만이면 "".
    ///   "myproj/uuid.jsonl"      → "myproj"
    ///   "myproj/sub/x.jsonl"     → "myproj"
    ///   "x.jsonl" / ""           → ""
    public static func name(fromRelative rel: String) -> String {
        let parts = rel.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count >= 2 ? String(parts[0]) : ""
    }

    /// 인코딩된 폴더명을 사람이 읽기 좋은 이름으로. (마지막 세그먼트 휴리스틱)
    ///   "-Users-me-develop"      → "develop"
    ///   "myproj"                 → "myproj"
    ///   ""                       → "(unknown)"
    public static func friendly(_ folder: String) -> String {
        if folder.isEmpty { return "(unknown)" }
        let segs = folder.split(separator: "-", omittingEmptySubsequences: true)
        return segs.last.map(String.init) ?? folder
    }
}
