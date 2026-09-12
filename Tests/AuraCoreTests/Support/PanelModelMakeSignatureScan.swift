import Foundation

/// `panelModelMakeHasNoDefaults`（G13，來源推導）的掃描形狀：抓出 `static func make(` 的
/// 括號配對範圍（`now: Date = Date()` 自己就帶一層巢狀括號，不能用字面 `find ")"` 找結尾），
/// 依「頂層逗號」（深度 0）切成各參數，對每個參數檢查是否含 `=`（有就是預設值）——
/// 標籤是 `now` 的例外。沿用 `AppLayerSourceScanTests`／`UserDefaultsSourceScan` 的精神：
/// 讀不到、抓不到簽章一律 throw，不把「掃不到」讀成「乾淨」。
enum PanelModelMakeSignatureScan {
    struct ScanFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// `make(` 括號內的完整文字（不含最外層那對括號本身）。
    static func parameterListText(in text: String) throws -> String {
        guard let marker = text.range(of: "static func make(") else {
            throw ScanFailure("找不到 static func make( —— gate 無法作答")
        }
        var depth = 1   // 已經吃掉開頭的 "("
        var i = marker.upperBound
        let start = i
        while i < text.endIndex {
            let ch = text[i]
            if ch == "(" { depth += 1 }
            if ch == ")" {
                depth -= 1
                if depth == 0 { return String(text[start..<i]) }
            }
            i = text.index(after: i)
        }
        throw ScanFailure("make( 的括號沒有配對到 —— 檔案可能截斷或語法壞了")
    }

    /// 依「深度 0 的逗號」切開參數列表——巢狀括號／中括號內的逗號不算分隔點。
    static func splitTopLevelParameters(_ list: String) -> [String] {
        var depth = 0
        var current = ""
        var params: [String] = []
        for ch in list {
            switch ch {
            case "(", "[":
                depth += 1
                current.append(ch)
            case ")", "]":
                depth -= 1
                current.append(ch)
            case "," where depth == 0:
                params.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            default:
                current.append(ch)
            }
        }
        let last = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { params.append(last) }
        return params
    }

    /// 回傳「帶預設值、但標籤不是 `now`」的參數原文清單——空陣列＝乾淨。
    static func defaultedParameters(in text: String) throws -> [String] {
        let params = splitTopLevelParameters(try parameterListText(in: text))
        return params.filter { param in
            guard param.contains("=") else { return false }
            let label = param.split(separator: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""
            return label != "now"
        }
    }
}
