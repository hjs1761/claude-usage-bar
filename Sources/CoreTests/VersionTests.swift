import Foundation
import ClaudeUsageCore

func testVersion(_ h: Harness) {
    h.run("Version.parse") {
        h.expectEqual(Version("v1.4")?.description, "1.4", "v 접두사 제거")
        h.expectEqual(Version("1.4.2")?.description, "1.4.2", "3요소")
        h.expectNil(Version("abc"), "숫자 아님→nil")
        h.expectNil(Version(""), "빈 문자열→nil")
    }
    h.run("Version.compare") {
        h.expect(Version("1.3")! < Version("1.4")!, "1.3 < 1.4")
        h.expect(Version("1.4")! < Version("1.10")!, "1.4 < 1.10 (숫자비교)")
        h.expect(Version("1.3")! < Version("1.3.1")!, "1.3 < 1.3.1")
        h.expect(Version("1.4")! == Version("1.4.0")!, "1.4 == 1.4.0")
        h.expect(!(Version("1.4")! < Version("1.4")!), "동일은 < 아님")
    }
}
