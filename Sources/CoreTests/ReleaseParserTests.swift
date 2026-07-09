import Foundation
import ClaudeUsageLive

func testReleaseParser(_ h: Harness) {
    let json = """
    {"tag_name":"v1.4","assets":[
      {"name":"notes.txt","browser_download_url":"https://x/notes.txt"},
      {"name":"claude-usage-mac.zip","browser_download_url":"https://x/app.zip"}]}
    """.data(using: .utf8)!
    h.run("ReleaseParser.ok") {
        let r = ReleaseParser.parseLatest(json)
        h.expectNotNil(r, "파싱 성공")
        h.expectEqual(r?.tag, "v1.4", "tag")
        h.expectEqual(r?.zipURL.absoluteString, "https://x/app.zip", "첫 zip 에셋")
    }
    h.run("ReleaseParser.fail") {
        h.expectNil(ReleaseParser.parseLatest(Data("garbage".utf8)), "쓰레기→nil")
        let noZip = #"{"tag_name":"v1.4","assets":[{"name":"a.txt","browser_download_url":"https://x/a"}]}"#
        h.expectNil(ReleaseParser.parseLatest(Data(noZip.utf8)), "zip 없음→nil")
    }
}
