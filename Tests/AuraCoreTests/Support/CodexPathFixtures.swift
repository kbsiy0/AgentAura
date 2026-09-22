import Foundation

/// codex-support T01 必辦④（R-5）：`CodexHookPathCheck.rejection(...)` 的路徑對抗式輸入，
/// 供 T04 的 `CodexHookPathCheckTests`（CX33）與 T06 的 `CodexInstallerClobberTests`
/// （CX32）、T10 的 `codexReconnectNeverDisconnectsWhenPathIsRejected`（CX39）共用。
///
/// **期望值寫死在這裡**（T01b，review M1）：比照 `AgentArgvFixtures` 的做法，用字串
/// 描述期望的 `Rejection`（`nil`／`"mustMoveToApplications"`／
/// `"unsupportedCharacter(<那個字元>)"`）而不是 `CodexHookPathCheck.Rejection` 本身
/// ——這樣在 T04 落地前就能先寫死、先編譯，**不是從 `CodexHookPathCheck.rejection(...)`
/// 的實作反推**。各 gate 把真正算出來的 `Rejection` 轉成同樣的字串描述再比對。
/// `translocatedAndContainsSpace` 填 `"mustMoveToApplications"`——這就是「translocated
/// 優先於字元檢查」這個優先序的資料化表達，不再只活在 case 的名字裡。
enum CodexPathFixtures {
    struct Case {
        let name: String
        let translocated: Bool
        let inDownloads: Bool
        let hookBinaryPath: String
        let expectedRejection: String?
    }

    /// spec §4.4／CX33：六個不支援字元，逐一測試「第一個命中者」。
    static let unsupportedCharacterSamples: [Character] = [" ", "'", "\"", "$", "`", "\\"]

    static let cases: [Case] = {
        var result: [Case] = [
            Case(name: "translocated",
                 translocated: true, inDownloads: false,
                 hookBinaryPath: "/private/var/folders/xx/T/AppTranslocation/ABCDEF12-3456-7890"
                    + "-ABCD-EF1234567890/d/AgentAura.app/Contents/MacOS/aura-hook",
                 expectedRejection: "mustMoveToApplications"),
            Case(name: "inDownloads",
                 translocated: false, inDownloads: true,
                 hookBinaryPath: "/Users/demo/Downloads/AgentAura.app/Contents/MacOS/aura-hook",
                 expectedRejection: "mustMoveToApplications"),
            Case(name: "translocatedAndContainsSpace（驗優先序：translocated 先於字元檢查）",
                 translocated: true, inDownloads: false,
                 hookBinaryPath: "/private/var/folders/xx/T/AppTranslocation/ABCDEF12-3456-7890"
                    + "-ABCD-EF1234567890/d/Agent Aura.app/Contents/MacOS/aura-hook",
                 expectedRejection: "mustMoveToApplications"),
            Case(name: "clean（負對照）",
                 translocated: false, inDownloads: false,
                 hookBinaryPath: "/Applications/AgentAura.app/Contents/MacOS/aura-hook",
                 expectedRejection: nil),
        ]
        for c in unsupportedCharacterSamples {
            result.append(Case(
                name: "unsupportedCharacter(\(c))",
                translocated: false, inDownloads: false,
                hookBinaryPath: "/Applications/Agent\(c)Aura.app/Contents/MacOS/aura-hook",
                expectedRejection: "unsupportedCharacter(\(c))"))
        }
        return result
    }()
}
