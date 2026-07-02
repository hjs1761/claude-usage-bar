import Foundation
import ClaudeUsageCore

func testColorAdapt(_ h: Harness) {
    h.run("ColorAdapt.grayscale→blackWhite") {
        // 무채색은 라이트=검정, 다크=흰색
        let r = ColorAdapt.dual(hex: "#808080")
        h.expectEqual(r.light, RGB(r: 0, g: 0, b: 0), "gray light=black")
        h.expectEqual(r.dark, RGB(r: 255, g: 255, b: 255), "gray dark=white")
    }
    h.run("ColorAdapt.brightDarkenedForLight") {
        // 밝은 노랑은 라이트용으로 어두워져야 함
        let r = ColorAdapt.dual(hex: "#ffff00")
        let lum = 0.299*Double(r.light.r) + 0.587*Double(r.light.g) + 0.114*Double(r.light.b)
        h.expect(lum < 200, "bright yellow darkened for light (lum=\(lum))")
    }
    h.run("ColorAdapt.darkLightenedForDark") {
        // 어두운 파랑은 다크용으로 밝아져야 함
        let r = ColorAdapt.dual(hex: "#000080")
        h.expect(r.dark.b > 128, "dark blue lightened for dark (b=\(r.dark.b))")
    }
    h.run("ColorAdapt.shortHex") {
        let r = ColorAdapt.dual(hex: "#08f")
        h.expectEqual(r.light.r, 0, "short hex parses r")
    }
}
