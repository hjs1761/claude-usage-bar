import Foundation

/// "v1.4" / "1.4.2" 같은 버전 문자열을 파싱·비교. 부족한 자리는 0으로 취급(1.4 == 1.4.0).
public struct Version: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ s: String) {
        var str = s.trimmingCharacters(in: .whitespaces)
        if str.hasPrefix("v") || str.hasPrefix("V") { str.removeFirst() }
        guard !str.isEmpty else { return nil }
        var comps: [Int] = []
        for part in str.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(part), n >= 0 else { return nil }
            comps.append(n)
        }
        guard !comps.isEmpty else { return nil }
        self.components = comps
    }

    public static func < (a: Version, b: Version) -> Bool {
        let n = max(a.components.count, b.components.count)
        for i in 0..<n {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: Version, b: Version) -> Bool {
        let n = max(a.components.count, b.components.count)
        for i in 0..<n {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return false }
        }
        return true
    }

    public var description: String { components.map(String.init).joined(separator: ".") }
}
