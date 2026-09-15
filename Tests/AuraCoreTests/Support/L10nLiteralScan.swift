import Foundation

/// D-5(3) 的掃描形狀：「這個檔案裡有沒有『字串字面』含中日韓統一表意文字」——
/// 不是「這個檔案裡有沒有中文」（**全部** `Sources/` 的 doc comment 幾乎都是中文，
/// 那樣掃只會讓允許清單等於整個 `Sources/`，gate 沒有意義）。
///
/// 簡化（同 `AppLayerSourceScanTests` 一路的作法，掃文字不做完整 lexer）：
/// 1. 這個 codebase 的 `Sources/` 底下沒有 `/* */` 區塊註解（已用 `grep` 驗過 0 命中），
///    只需要逐行砍掉 `//`（含 `///`）之後的內容。
/// 2. 字串字面用雙引號配對抓，反斜線跳脫一律跳過（不解析插值運算式內部，這個
///    codebase 目前沒有巢狀字串插值案例）；`"""` 三引號字串按這個演算法會被拆成
///    「空字串＋一個沒配對到的引號」，偵測不到裡面的內容——可接受，因為唯一用到
///    `"""` 的檔案（`AppEnvironment.swift`）整檔都在 `pendingMigrationFiles` 允許清單裡，
///    不靠這個掃描器抓內容。
enum L10nLiteralScan {
    static func stripLineComment(_ line: Substring) -> Substring {
        guard let range = line.range(of: "//") else { return line }
        return line[line.startIndex..<range.lowerBound]
    }

    static func stringLiteralContents(in code: Substring) -> [String] {
        let chars = Array(code)
        var i = 0
        var contents: [String] = []
        while i < chars.count {
            guard chars[i] == "\"" else { i += 1; continue }
            var j = i + 1
            var content = ""
            var closed = false
            while j < chars.count {
                if chars[j] == "\\", j + 1 < chars.count { j += 2; continue }
                if chars[j] == "\"" { closed = true; break }
                content.append(chars[j])
                j += 1
            }
            if closed { contents.append(content) }
            i = j + 1
        }
        return contents
    }

    /// CJK Unified Ideographs（U+4E00–U+9FFF）＋ CJK 標點（U+3000–U+303F）——
    /// 足以涵蓋這個 codebase 目前用到的繁體中文字元與全形標點。
    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) || (0x3000...0x303F).contains($0.value)
        }
    }

    static func fileHasCJKStringLiteral(_ text: String) -> Bool {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let code = stripLineComment(line)
            for literal in stringLiteralContents(in: code) where containsCJK(literal) {
                return true
            }
        }
        return false
    }
}
