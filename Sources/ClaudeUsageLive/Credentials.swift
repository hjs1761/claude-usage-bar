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
