import Testing
import Foundation

/// **吃 `language` 的使用者可見字串工廠，一律不得給 `language` 預設值。**
/// 沒有預設值，漏傳就是**編譯錯誤**——由編譯器當 gate，不是由測試近似它。
///
/// ## 為什麼是這個形狀（兩次修正之後的結論）
///
/// 第一版：手寫一個函式名（`OptionsMenuModel.rows(`）去掃呼叫點。T27 開工立刻證明不夠——
/// 搬遷時 `InstallState.healthLabel`／`TooltipText.text`／`LegendModel.items`／
/// `PanelBanner.connected()` 一整批都要開始吃 `language`，手寫清單當場漏掉一批。
///
/// 第二版：改成從原始碼推導函式清單再掃呼叫點。**實跑之後發現這條路不可靠**：
/// - `FSEventStreamContext(` 含有 `text(` 這個子字串 → 假陽性。
/// - 字串表協定自己是 `func text(_ language:)`（無標籤），呼叫端位置傳遞 → 假陽性。
/// - 更根本的：`text` 這個名字同時屬於 `L10nCatalog.text(_:)` 與
///   `TooltipText.text(appearance:install:)` 兩個不同函式。**靠裸函式名比對無法分辨它們**，
///   而要分辨就得真的解析 Swift 型別——那是在編譯器外面再包一層自己的近似，
///   正是 CLAUDE.md gate 哲學第 1 條禁止的事。
///
/// 第三版（本檔）：**不要近似編譯器，直接用它。** 只要這些參數沒有預設值，
/// 任何漏傳的呼叫點都編不過，一個都跑不掉，也不需要任何字串比對。
/// 這條測試因此只守一件很小、很明確、掃得準的事：**沒有人偷偷加回預設值。**
///
/// ## 它擋的具體災難
///
/// `PanelFooterView`／`PanelView`／`StatusItemController` 這三個檔**自己沒有任何中文字面**，
/// 所以 `L10nStrayLiteralSourceScanTests` 的允許清單裡沒有它們、那條掃描也永遠掃不到它們。
/// 但它們直接呼叫上面那些工廠。只要工廠帶了 `language` 預設值而這裡沒傳，
/// **使用者切成英文之後，footer、面板、tooltip 會繼續顯示中文，而所有測試照樣全綠**。
/// 那不是邊角案例，那是這個功能本身失效。
///
/// ## 例外
///
/// 字串表內部的 `func text(_ language: Language)` 這類**無標籤**參數不在此限——
/// 它們是表自己的查詢介面，呼叫端位置傳遞，不存在「忘記傳」這種事（漏傳一樣編不過）。
/// 本 gate 只針對**有標籤**的 `language:` 參數。
@Suite("吃 language 的字串工廠不得給預設值（讓編譯器當 gate）")
struct L10nProductionCallSitesPassLanguageTests {

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        throw Failure("從 \(#filePath) 往上找不到 Package.swift")
    }

    /// 掃 `Sources/` 底下每一個 `.swift`（從磁碟推導，新增檔案不會漏網——
    /// 同 `IsolationTests.swiftFiles(under:)` 的既有慣例）。
    static func sourceFiles() throws -> [(name: String, lines: [String])] {
        let root = try repoRoot().appendingPathComponent("Sources")
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw Failure("列舉不到 \(root.path) —— gate 不能空跑")
        }
        let urls = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        return try urls.map { url in
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅
            return (url.lastPathComponent,
                    text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        }
    }

    @Test("Sources/ 裡沒有任何 language 參數帶預設值")
    func noLanguageParameterHasADefaultValue() throws {
        let files = try Self.sourceFiles()
        #expect(!files.isEmpty, "掃不到任何 Sources/*.swift —— gate 不能空跑")

        var offenders: [String] = []
        var declarationsSeen = 0

        for file in files {
            for (i, line) in file.lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.hasPrefix("//"), !t.hasPrefix("*") else { continue }   // 註解不算
                // 儲存屬性的初始值（`var language: Language = .english`）不是參數預設值——
                // composition root 本來就要有一個持有語言偏好的欄位，那是正確的形狀。
                guard !t.hasPrefix("var "), !t.hasPrefix("let "),
                      !t.hasPrefix("private var "), !t.hasPrefix("private let ") else { continue }
                guard line.contains("language:") else { continue }
                declarationsSeen += 1
                // `language: Language = .xxx` ——等號代表預設值。
                // 呼叫端寫的是 `language: model.language`，不會有 `Language = `。
                if line.contains("language: Language = ") {
                    offenders.append("\(file.name):\(i + 1)  \(t)")
                }
            }
        }

        #expect(declarationsSeen > 0, """
            `Sources/` 裡一個 `language:` 都掃不到 —— 要嘛參數名改了、要嘛這條 gate 已經空轉。
            兩種情況都要有人來看，不能靜默通過。
            """)
        #expect(offenders.isEmpty, """
            這些 `language` 參數帶了預設值，於是「呼叫時忘記傳」不再是編譯錯誤而是**靜默**
            吃到預設值（D-2 要求預設英文，而預設值多半寫成中文）——**使用者切成英文之後
            那些地方會繼續顯示中文，而所有測試照樣全綠**。

            拿掉預設值，讓編譯器逼每一個呼叫點表態。遷移期間想少改幾個呼叫點不是理由：
            那些呼叫點正是需要被接線的東西，用預設值跳過它們等於把缺口藏起來。

            \(offenders.joined(separator: "\n"))
            """)
    }
}
