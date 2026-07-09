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
