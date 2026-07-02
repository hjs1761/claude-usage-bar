import Foundation
import ClaudeUsageCore

func testCredentials(_ h: Harness) {
    h.run("Credentials.parseTokenAndExpiry") {
        let json = #"{"claudeAiOauth":{"accessToken":"tok-123","expiresAt":1780000000000}}"#
        if let c = Credentials.parse(json) {
            h.expectEqual(c.accessToken, "tok-123", "accessToken")
            h.expectEqual(c.expiresAtMillis ?? 0, 1780000000000, "expiresAt")
        } else {
            h.expect(false, "should parse valid json")
        }
    }
    h.run("Credentials.missingOauth→nil") {
        h.expectNil(Credentials.parse(#"{"other":1}"#), "missing claudeAiOauth")
    }
    h.run("Credentials.garbage→nil") {
        h.expectNil(Credentials.parse("not json"), "garbage")
    }
    h.run("Credentials.expiredAgainstNow") {
        // 1000ms = 1970년 → 지금 기준 만료
        if let c = Credentials.parse(#"{"claudeAiOauth":{"accessToken":"t","expiresAt":1000}}"#) {
            h.expect(c.isExpired(now: Date()), "epoch token is expired")
        } else {
            h.expect(false, "should parse")
        }
    }
}
