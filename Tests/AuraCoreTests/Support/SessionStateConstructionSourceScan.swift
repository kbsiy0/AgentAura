import Foundation

/// T05d m1：找出 `Sources/` 底下每一個 `SessionState(` 建構呼叫的**完整區塊**
/// （用括號配對，不是只看命中那一行——生產呼叫點是多行寫法，`agent:` 可能出現在
/// 命中行之後好幾行），供呼叫端檢查「有沒有明傳 `agent:`」。
///
/// 沿用 `UserDefaultsSourceScan.scan(under:)` 的形狀：讀不到就 throw（不把
/// 「讀不到」當成乾淨），檔數由同一個 reader 回報供呼叫端做「防空跑」檢查。
enum SessionStateConstructionSourceScan {
    struct Occurrence { let file: URL; let block: String }

    static func scan(under directory: URL) throws -> (scanned: Int, occurrences: [Occurrence]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return (0, [])
        }
        let files = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var occurrences: [Occurrence] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是乾淨
            let marker = "SessionState("
            var searchStart = text.startIndex
            while let markerRange = text.range(of: marker, range: searchStart..<text.endIndex) {
                // 從 marker 已經消耗掉的那個 "(" 開始配對，depth 從 1 起算；
                // 一路數到配對的 ")" 收尾，正確處理呼叫區塊裡任何巢狀括號
                // （例如 `agent: Agent(stored: s.agent)`）。
                var depth = 1
                var idx = markerRange.upperBound
                var blockEnd = idx
                while idx < text.endIndex {
                    let ch = text[idx]
                    if ch == "(" { depth += 1 }
                    if ch == ")" {
                        depth -= 1
                        if depth == 0 { blockEnd = idx; break }
                    }
                    idx = text.index(after: idx)
                }
                let block = String(text[markerRange.lowerBound...blockEnd])
                occurrences.append(Occurrence(file: url, block: block))
                searchStart = text.index(after: blockEnd)
            }
        }
        return (files.count, occurrences)
    }
}
