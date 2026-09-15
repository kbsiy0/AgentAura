/// D-1 字串表機制的共用骨架——每個「領域」字串表是一個獨立的 `CaseIterable` enum，
/// 帶一個 `text(_:)`，內部對 `Language` 做窮盡 `switch`、**無 `default` 分支**：
/// 少翻一個語言＝那個 switch 編不過（`Language` 新增一個 case 時，所有 domain enum
/// 一次全部編不過）；少翻一個字串＝忘了在 domain enum 加 case，呼叫端就找不到那個鍵，
/// 一樣是編譯錯誤。這兩件事合起來就是 D-1 承諾的「少翻一個字串＝編譯錯誤」。
///
/// **為什麼不做成單一個大 enum 裝全部 ~107 個鍵**：Swift 的 enum case 不能用 extension
/// 補（不像 protocol conformance 可以分檔案），硬要塞單一 enum 會讓那個檔案隨 T27／T28
/// 一路長到撞 `Sources/` 200 行上限、且到頂之後無法再拆。改成「每個領域一個小 enum、
/// 各自一個檔案」，T27／T28 加新領域時新增檔案即可，既有檔案不必變動；單一 domain
/// 太肥時就再拆成更小的 domain（例如 `OptionsMenuModel` 的 mount 群組獨立一份），
/// case 集合本身還是留在單一宣告裡，只是「領域」切得更細。
///
/// `L10nRegistry`（同目錄）手動列出所有 domain enum，供 D-5(2)(3) 兩條 gate 走訪；
/// `L10nRegistrySourceScanTests` 反過來驗證這份清單沒有漏掉磁碟上的 domain 檔。
public protocol L10nCatalog: CaseIterable {
    func text(_ language: Language) -> String
}
