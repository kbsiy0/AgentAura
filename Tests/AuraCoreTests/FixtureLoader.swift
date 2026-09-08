import Foundation
import Testing

enum Fixtures {
    /// 讀取探針 ndjson，回傳剝開 `_payload` 後的原始 hook JSON 字典陣列。
    static func rawEvents(named name: String) throws -> [[String: Any]] {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "ndjson"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").compactMap { line -> [String: Any]? in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return obj["_payload"] as? [String: Any] ?? obj
        }
    }

    /// 只回傳指定 hook_event_name 的事件。
    static func events(named name: String, kind: String) throws -> [[String: Any]] {
        try rawEvents(named: name).filter { $0["hook_event_name"] as? String == kind }
    }

    /// 把字典重新序列化成 hook 會從 stdin 送進來的 JSON bytes。
    static func jsonData(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }
}
