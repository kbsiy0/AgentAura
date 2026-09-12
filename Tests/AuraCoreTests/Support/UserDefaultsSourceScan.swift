import Foundation

/// T01 必辦⑤（後半）：`verificationStoreIsInjected` 的掃描形狀，供 T07 直接沿用去掃
/// `Sources/AuraHookFile/`。
///
/// **樣式帶標點**（`UserDefaults(` / `UserDefaults.`），不是掃「UserDefaults 字樣」——
/// 實測掃裸字樣會被中文註解裡提到 `UserDefaults` 這個詞的句子命中（grep 回 1、
/// 那一個命中全在註解裡），讓 gate born-red 或被誤刪註解繞過。帶標點鎖定的是
/// 「建構呼叫」或「member access」語法，不是任意提及。
///
/// 沿用 `AppLayerSourceScanTests.scanForAnimationSwitches` 的形狀：讀不到就 throw
/// （不把「讀不到」當成乾淨），檔數由同一個 reader 回報供呼叫端做「防空跑」檢查。
enum UserDefaultsSourceScan {
    static func scan(under directory: URL) throws -> (scanned: Int, hits: [URL]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return (0, [])
        }
        let files = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var hits: [URL] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是乾淨
            if text.contains("UserDefaults(") || text.contains("UserDefaults.") { hits.append(url) }
        }
        return (files.count, hits)
    }
}
