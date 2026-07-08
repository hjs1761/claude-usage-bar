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
