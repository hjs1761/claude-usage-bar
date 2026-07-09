import Foundation
import ClaudeUsageLive

func testContact(_ h: Harness) {
    h.run("Contact.payload") {
        let data = Contact.payload(message: "버그 있어요", from: "황준석",
                                   appVersion: "1.3", os: "26.5", timestamp: "2026-07-09T12:00")
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = (obj?["text"] as? String) ?? ""
        h.expectEqual(obj?["botName"] as? String, "사용량앱 문의", "botName")
        h.expect(text.contains("버그 있어요"), "내용 포함")
        h.expect(text.contains("v1.3"), "버전 포함")
        h.expect(text.contains("황준석"), "보낸사람 포함")
    }
    h.run("Contact.payload.익명") {
        let data = Contact.payload(message: "hi", from: "", appVersion: "1.3", os: "26", timestamp: "t")
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        h.expect(((obj?["text"] as? String) ?? "").contains("익명"), "빈 보낸사람→익명")
    }
}
