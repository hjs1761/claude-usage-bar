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
