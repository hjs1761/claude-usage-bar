import Foundation

public struct ReleaseInfo: Equatable, Sendable {
    public let tag: String
    public let zipURL: URL
    public init(tag: String, zipURL: URL) { self.tag = tag; self.zipURL = zipURL }
}

/// GitHub `releases/latest` 응답 → tag + 첫 .zip 에셋 URL. 순수 함수(테스트 가능).
public enum ReleaseParser {
    public static func parseLatest(_ data: Data) -> ReleaseInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let assets = obj["assets"] as? [[String: Any]] else { return nil }
        for a in assets {
            if let name = a["name"] as? String, name.hasSuffix(".zip"),
               let s = a["browser_download_url"] as? String, let url = URL(string: s) {
                return ReleaseInfo(tag: tag, zipURL: url)
            }
        }
        return nil
    }
}
