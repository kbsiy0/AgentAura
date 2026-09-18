import Foundation

/// codex-support T01 必辦④（R-5）：`CodexHookPathCheck.rejection(...)` 的路徑對抗式輸入，
/// 供 T04 的 `CodexHookPathCheckTests`（CX33）與 T06 的 `CodexInstallerClobberTests`
/// （CX32）、T10 的 `codexReconnectNeverDisconnectsWhenPathIsRejected`（CX39）共用。
///
/// **期望值不放在這裡**——這裡只固定「輸入」；各 gate 自己對
/// `CodexHookPathCheck.rejection(...)`（T04 才存在）斷言期望的 `Rejection`。
enum CodexPathFixtures {
    struct Case {
        let name: String
        let translocated: Bool
        let inDownloads: Bool
        let hookBinaryPath: String
    }

    /// spec §4.4／CX33：六個不支援字元，逐一測試「第一個命中者」。
    static let unsupportedCharacterSamples: [Character] = [" ", "'", "\"", "$", "`", "\\"]

    static let cases: [Case] = {
        var result: [Case] = [
            Case(name: "translocated",
                 translocated: true, inDownloads: false,
                 hookBinaryPath: "/private/var/folders/xx/T/AppTranslocation/ABCDEF12-3456-7890"
                    + "-ABCD-EF1234567890/d/AgentAura.app/Contents/MacOS/aura-hook"),
            Case(name: "inDownloads",
                 translocated: false, inDownloads: true,
                 hookBinaryPath: "/Users/demo/Downloads/AgentAura.app/Contents/MacOS/aura-hook"),
            Case(name: "translocatedAndContainsSpace（驗優先序：translocated 先於字元檢查）",
                 translocated: true, inDownloads: false,
                 hookBinaryPath: "/private/var/folders/xx/T/AppTranslocation/ABCDEF12-3456-7890"
                    + "-ABCD-EF1234567890/d/Agent Aura.app/Contents/MacOS/aura-hook"),
            Case(name: "clean（負對照）",
                 translocated: false, inDownloads: false,
                 hookBinaryPath: "/Applications/AgentAura.app/Contents/MacOS/aura-hook"),
        ]
        for c in unsupportedCharacterSamples {
            result.append(Case(
                name: "unsupportedCharacter(\(c))",
                translocated: false, inDownloads: false,
                hookBinaryPath: "/Applications/Agent\(c)Aura.app/Contents/MacOS/aura-hook"))
        }
        return result
    }()
}
