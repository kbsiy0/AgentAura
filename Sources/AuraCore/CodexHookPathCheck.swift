import Foundation

/// 「這個 bundle 路徑能不能寫進 `~/.codex/hooks.json`」的單一純函式判定（spec §4.4／R-5）。
///
/// **三個消費者，一個判定**：路由層（`CodexState.from` 的 `pathRejection`）、
/// `performConnectCodex()` 的前置 guard（R-9）、執行層 `CodexInstaller.connect` 的第一行
/// guard——全部呼叫同一個 `rejection(...)`，不各自近似一份。**零 I/O、零平台 API**：
/// 只做字串／布林運算，`translocated`／`inDownloads` 由呼叫端量好再傳進來
/// （`RunningBundle` 的職責，不是這裡）。
///
/// **注意**：既有 `Installer.connect` 的 `mustMoveToApplications` 擋的**只有** translocated
/// 與 `~/Downloads`，**沒有**「必須在 `/Applications`」這個條件。所以 `~/Applications/`、
/// `~/My Apps/` 這類合法位置**可以含空白**——「幾乎永遠不觸發」不成立，`unsupportedCharacters`
/// 那一段判定不是聊備一格。
public enum CodexHookPathCheck {

    /// `Rejection` 帶 associated value 不能 `CaseIterable`（D-r，同 `PanelActionKind`／
    /// `CodexStateKind` 的既有理由），配這個平行型別供窮盡定義域推導。
    public enum RejectionKind: String, Sendable, CaseIterable {
        case mustMoveToApplications
        case unsupportedCharacter
    }

    /// bundle 路徑為什麼不能寫進 hooks.json（R-5）。
    public enum Rejection: Equatable, Sendable {
        /// App 是 translocated（Gatekeeper 隔離）或跑在 `~/Downloads`——路徑下次啟動就消失。
        case mustMoveToApplications
        /// 路徑含 shell／JSON 都會出問題的字元；帶的是**第一個**命中的那一個。
        case unsupportedCharacter(Character)

        /// 窮盡 switch，**不得有 `default`**——那正是 `RejectionKind` 這個平行型別存在的
        /// 唯一理由：新增一個 `Rejection` case 時，這裡與 `samples(_:)` 會編不過，逼你同時
        /// 補齊；加一個 `default` 看起來像防禦性寫法，實際是讓整條定義域推導鏈靜默失效。
        public var kind: RejectionKind {
            switch self {
            case .mustMoveToApplications: .mustMoveToApplications
            case .unsupportedCharacter: .unsupportedCharacter
            }
        }

        /// 每個 `RejectionKind` 的**全部**代表值。`.unsupportedCharacter` 這一格從
        /// `unsupportedCharacters` 推導、逐字元各給一個代表值，不是單一代表值
        /// （同 `PanelAction.samples` 的既有理由：單一代表值時「六個字元裡漏了一個」照樣全綠）。
        /// 窮盡 switch，**不得有 `default`**——理由與 `kind` 逐字相同：新 case 忘了補這裡，
        /// 编譯器擋下來；`default: []` 會讓這條定義域推導鏈靜默失效。
        public static func samples(_ kind: RejectionKind) -> [Rejection] {
            switch kind {
            case .mustMoveToApplications: [.mustMoveToApplications]
            case .unsupportedCharacter: unsupportedCharacters.map(Rejection.unsupportedCharacter)
            }
        }
    }

    /// 會讓寫進 hooks.json 的 `command` 字串出問題的字元（spec §4.4）：空白（拆開 shell
    /// 參數）、`'`／`"`（提前結束引號）、`$`（shell 變數展開）、`` ` ``（shell 指令替換）、
    /// `\`（跳脫序列）。
    public static let unsupportedCharacters: Set<Character> = [" ", "'", "\"", "$", "`", "\\"]

    /// 判定 `hookBinaryPath` 能不能寫進 hooks.json。
    ///
    /// 順序即優先序：① `translocated || inDownloads` 一律先判——那個路徑下次啟動就消失，
    /// 比字元問題更急迫；② 否則由左至右掃字元，回傳**第一個**命中 `unsupportedCharacters`
    /// 的字元；③ 都沒中回 `nil`（可以寫）。
    public static func rejection(translocated: Bool, inDownloads: Bool,
                                 hookBinaryPath: String) -> Rejection? {
        if translocated || inDownloads {
            return .mustMoveToApplications
        }
        for character in hookBinaryPath where unsupportedCharacters.contains(character) {
            return .unsupportedCharacter(character)
        }
        return nil
    }
}
