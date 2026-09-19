import Foundation

/// T08b（T07 review 回頭補的裂縫）：找出 `Sources/` 底下每一個 `OptionsMenuModel.rows(`
/// 呼叫的**完整區塊**（括號配對，不是只看命中那一行——生產呼叫點是多行寫法）。
///
/// 沿用 `SessionStateConstructionSourceScan.scan(under:)` 的形狀：讀不到就 throw
/// （不把「讀不到」當成乾淨），檔數由同一個 reader 回報供呼叫端做「防空跑」檢查。
enum OptionsMenuModelRowsCallSiteScan {
    struct Occurrence { let file: URL; let block: String }

    static func scan(under directory: URL) throws -> (scanned: Int, occurrences: [Occurrence]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return (0, [])
        }
        let files = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var occurrences: [Occurrence] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是乾淨
            let marker = "OptionsMenuModel.rows("
            var searchStart = text.startIndex
            while let markerRange = text.range(of: marker, range: searchStart..<text.endIndex) {
                // doc comment 裡提到函式名字面（例如「OptionsMenuModel.rows(codex:)」的說明句）
                // 不是真的呼叫——這個型別（連同 `SessionStateConstructionSourceScan` 抄的
                // `SessionState(` 找不到這個問題）第一版沒過濾，`PanelModel.swift`／
                // `L10nOptionsMenuRows.swift`／`OptionsMenuModel+Codex.swift`／
                // `OptionsPanelSizing.swift` 的 doc comment 全部假陽性中獎（實測 8 處變 1 處）。
                // 判準：marker 所在那一行，往行首 trim 掉空白後是不是以 `//` 開頭。
                let lineStart = text.lineRange(for: markerRange).lowerBound
                let linePrefix = text[lineStart..<markerRange.lowerBound].trimmingCharacters(in: .whitespaces)
                guard !linePrefix.hasPrefix("//") else {
                    searchStart = markerRange.upperBound
                    continue
                }
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
