import Foundation

/// Codex 側 `~/.codex/hooks.json` 的產生器（AuraCore 純函式、只 import Foundation，
/// spec §4.3／R-1／R-4）。
///
/// 逐字複製 F14 探針量到的**已驗證**形狀（`docs/2026-09-18-codex-hook-probe.md` F14）：
/// 每個事件一個 group，`matcher` 為空字串、`hooks` 陣列僅一個 `type: "command"` entry，
/// `command` 是**裸路徑**（不加引號）加上 `--agent codex`。**唯一的數值偏離是 `timeout`**
/// （F14 量到的是 5，這裡固定寫 3，見 `hookTimeoutSeconds`）。**不加 `async`**——那是
/// Claude 側 hooks.json 的欄位，F14 的「未測」欄第二項就是它，Codex 是否接受或拒絕沒量過。
///
/// 12 個事件鍵**從 `EventMapping.codexEvents` 推導**，不維護第二份清單；輸出用
/// `JSONSerialization` 的 `.sortedKeys` 讓鍵序決定性，供 round-trip／逐字比對使用。
public enum CodexHooksJSON {

    /// `command` 字串裡附加在 hook 二進位絕對路徑後面的參數（F8：`command` 可以帶參數）。
    public static let agentFlag = "--agent codex"

    /// 全部 12 個事件共用同一個 `timeout`（秒）——**對 F14 唯一的數值偏離**（F14 量到 5）。
    ///
    /// 理由三件事（不准為任何單一事件覆寫這個值——12 個事件從單一常數推導，逐事件各自
    /// 一個值等於重新養一份要手動維護、會 drift 的清單，同 `handledEvents` 的既有教訓）：
    /// 1. 這是產生器與 F14 之間**唯一**不逐字相同的欄位，其餘每個位元組都照抄已驗證的形狀。
    /// 2. 目的是避開 F13 量到的行為——Codex 會把 `SessionEnd`／`Interrupt` 的 timeout
    ///    **強制壓到 3 秒**並在 stderr 印一則 clamping 警告；把值本身就設成 3，
    ///    讓那則警告不會落進使用者的終端機（`aura-hook` 單次執行 ~7 ms，3 秒仍是充裕上限）。
    /// 3. **「3 不會觸發警告」是從 F13「壓到 3」反推出來的推論，不是量到的事實**——探針
    ///    從未直接測過 `timeout: 3`（或任何 ≤ 3 的值）本身還會不會有別的警告。三種可能結果
    ///    （不警告／仍警告但無害／有未知副作用）都在可承受範圍內；代價是失去 F1 賴以斷言
    ///    「Codex 讀到了 hooks.json」的那個便宜訊號（clamping 警告本身），已寫進 INSTALL
    ///    troubleshooting 當替代驗證步驟（暫時改回 5、下個 session 看 stderr、再改回 3）。
    public static let hookTimeoutSeconds = 3

    /// 產生完整 `~/.codex/hooks.json` 的內容（UTF-8 JSON `Data`）。
    ///
    /// - Parameter hookBinaryPath: bundle 內 `aura-hook` 的**絕對路徑**（F9：Codex 沒有
    ///   `CLAUDE_PLUGIN_ROOT` 這類環境變數可用，`command` 必須是完整路徑）。
    public static func json(hookBinaryPath: String) -> Data {
        let entry: [String: Any] = [
            "type": "command",
            "command": "\(hookBinaryPath) \(agentFlag)",
            "timeout": hookTimeoutSeconds,
        ]
        // `matcher: ""` 不可省：F14「未測」欄第一項就是「省略 matcher 是否可行」——沒量過
        // 的東西不能省。**不能拿 Claude 側當佐證**：Claude 的 19 個 entry 裡只有
        // `Notification` 帶 `matcher`，而且 Codex 與 Claude 是兩個獨立解析器、寬容度相反
        // （F7：Codex 對不認得的事件名寬容、Claude 全有全無），一邊的省略習慣推不到另一邊。
        let group: [String: Any] = ["matcher": "", "hooks": [entry]]
        var hooks: [String: Any] = [:]
        for event in EventMapping.codexEvents { hooks[event] = [group] }
        let root: [String: Any] = ["hooks": hooks]

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else {
            // 不可達：`root` 只由 String／Int／Array／Dictionary（key 皆為 String）組成，
            // `JSONSerialization` 對這個形狀保證不丟錯。保留這個分支只是為了讓函式簽章維持
            // 非 throwing，不代表這條路徑真的會被打到。
            return Data()
        }
        return data
    }

    /// `json(hookBinaryPath:)` 的文字形式——**同一個產生器**，供 UI 顯示可複製的 snippet
    /// （§4.6 的 `.occupiedByOther`／`.blockedByBundlePath(.unsupportedCharacter)`）。
    public static func snippet(hookBinaryPath: String) -> String {
        String(decoding: json(hookBinaryPath: hookBinaryPath), as: UTF8.self)
    }

    /// R-10／**r13（D-w）：有 rejection 就扣住，不分哪一種**——`.mustMoveToApplications`
    /// 那個路徑下次開機就消失，給出來等於發一張明天就過期的票；`.unsupportedCharacter` 那個
    /// 路徑雖然不會消失，但 `command` 是裸路徑不加引號（`CodexHookPathCheck` doc comment的
    /// 既有理由），遞出去的是一份**我們自己剛在同一張卡片說可能會壞**的設定檔，而 Codex 對
    /// 壞掉的 hook 是完全靜默跳過——兩種 rejection 的共同點不是「路徑會消失」，是「我們不敢
    /// 替他寫這一份」（persona r1 S0-2：P2 是最會真的照著貼的那個 persona）。
    /// ~~r12：只扣 `.mustMoveToApplications`，`.unsupportedCharacter` 照給~~。
    /// **這條規則不看 `CodexState`**——CX40 的乘積表故意跨每個 `CodexStateKind` 驗證同一個
    /// 結論，確保沒有人不小心把扣住的條件寫成「只在 `.blockedByBundlePath` 時」（那會漏掉
    /// `.occupiedByOther`，正是 r3 M1 指出的那扇側門）。`AppDelegate+Codex.swift` 的
    /// `CodexRuntime` 是唯一生產呼叫點，不在那裡另外重算一次同樣的判斷。
    public static func withheldSnippet(hookBinaryPath: String,
                                       pathRejection: CodexHookPathCheck.Rejection?) -> String? {
        pathRejection != nil ? nil : snippet(hookBinaryPath: hookBinaryPath)
    }
}
