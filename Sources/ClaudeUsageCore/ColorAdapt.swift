import Foundation

public struct RGB: Equatable, Sendable {
    public let r: Int, g: Int, b: Int
    public init(r: Int, g: Int, b: Int) { self.r = r; self.g = g; self.b = b }
}

public struct DualColor: Sendable {
    public let light: RGB
    public let dark: RGB
}

public enum ColorAdapt {
    public static func parseHex(_ hex: String) -> RGB {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = Int(h, radix: 16) else { return RGB(r: 128, g: 128, b: 128) }
        return RGB(r: (v >> 16) & 0xff, g: (v >> 8) & 0xff, b: v & 0xff)
    }

    /// 선택색 → (라이트용, 다크용). 필요한 만큼만 보정해 원색을 최대한 유지.
    public static func dual(hex: String) -> DualColor {
        let c = parseHex(hex)
        let r = Double(c.r), g = Double(c.g), b = Double(c.b)
        // 무채색 → 순수 흑백 (최대 대비)
        if max(c.r, c.g, c.b) - min(c.r, c.g, c.b) < 24 {
            return DualColor(light: RGB(r: 0, g: 0, b: 0), dark: RGB(r: 255, g: 255, b: 255))
        }
        let lum = 0.299*r + 0.587*g + 0.114*b
        let light: RGB
        if lum > 135 {                       // 라이트: 밝은 색만 낮춤
            let f = 135.0 / lum
            light = RGB(r: Int(r*f), g: Int(g*f), b: Int(b*f))
        } else {
            light = c
        }
        let dark: RGB
        if lum < 155 {                       // 다크: 어두운 색만 밝게(흰색 블렌드)
            let t = lum < 255 ? (155.0 - lum) / (255.0 - lum) : 0
            dark = RGB(r: Int(r + (255-r)*t), g: Int(g + (255-g)*t), b: Int(b + (255-b)*t))
        } else {
            dark = c
        }
        return DualColor(light: light, dark: dark)
    }
}
