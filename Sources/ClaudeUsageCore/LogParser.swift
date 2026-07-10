import Foundation

public enum LogParser {
    // 실제 로그는 밀리초 포함(2026-06-30T06:21:14.686Z), 없는 경우도 대비해 둘 다 시도.
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f   // 로컬 타임존 사용
    }()
    private static let cal = Calendar(identifier: .gregorian)   // hour 추출 (로컬)

    /// jsonl 한 줄 → UsageEntry?. assistant + usage 없으면 nil.
    public static func parseLine(_ line: String, project: String = "", home: String = "") -> UsageEntry? {
        guard line.contains("\"output_tokens\"") || line.contains("\"cache_creation_input_tokens\"")
        else { return nil }
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any]
        else { return nil }

        let i = usage["input_tokens"] as? Int ?? 0
        let o = usage["output_tokens"] as? Int ?? 0
        let cr = usage["cache_read_input_tokens"] as? Int ?? 0
        let cc = usage["cache_creation"] as? [String: Any]
        let cc5 = cc?["ephemeral_5m_input_tokens"] as? Int ?? 0
        var cc1 = cc?["ephemeral_1h_input_tokens"] as? Int ?? 0
        let cw = usage["cache_creation_input_tokens"] as? Int ?? (cc5 + cc1)
        if cc5 == 0 && cc1 == 0 && cw > 0 { cc1 = cw }   // 분해 없으면 1h로 간주

        let cat = ModelCategory.from(model: msg["model"] as? String)
        let b = cat.basePrice
        let cost = Double(i)*b + Double(o)*5*b + Double(cr)*0.1*b
                 + Double(cc5)*1.25*b + Double(cc1)*2*b

        let ts = obj["timestamp"] as? String ?? ""
        guard let date = ISODate.parse(ts) else { return nil }
        let dayKey = dayFmt.string(from: date)
        let hour = cal.component(.hour, from: date)   // 로컬 시 (dayKey와 동일 타임존)

        let mid = (msg["id"] as? String) ?? ""
        let rid = (obj["requestId"] as? String) ?? ""
        // id·requestId 둘 다 없으면 라인내용 해시로 유니크화 (없으면 "|"로 뭉개져 과잉 dedup=비용누락)
        let dedup = (mid.isEmpty && rid.isEmpty) ? "anon:\(StableHash.fnv1a(line))" : "\(mid)|\(rid)"
        let content = (msg["content"] as? [Any]) ?? []
        let rawFileProj = FileAttribution.dominant(paths: FileAttribution.extractPaths(fromContent: content),
                                                   home: home) ?? ""
        return UsageEntry(dayKey: dayKey, category: cat, input: i, output: o,
                          cacheWrite: cw, cacheRead: cr, cost: cost,
                          dedupKey: dedup, project: project, projectByFiles: rawFileProj, hour: hour)
    }
}
