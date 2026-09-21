import Foundation
@testable import AgentAuraApp

/// review M3：`AppDelegate.init` 的 `codexDependencies` 拿掉了預設值（漏傳即編譯錯誤，
/// 同本專案 `PanelBanner` 的 `language` 與 T08 三個新參數的既有先例）——這個已經害過一次
/// （測試意外寫入使用者真實 `~/.codex/hooks.json`，見 `d75bd06`）。這裡提供**一個**共用
/// helper，讓不特別關心 Codex 的既有測試只需要多一個參數，不必各自重寫一份
/// `FakeCodexInstaller` 建構。
///
/// **安全預設值**：`FakeCodexInstaller(mode: .normal)`（全記憶體、零 spawn）＋
/// `translocated`／`inDownloads` 都 false（`pathRejection == nil`，不會被 R-9 guard 擋住）
/// ＋ `writeToPasteboard` 不做任何事。**不叫 `.production()`**——那個名字留給真的生產
/// 預設值（`CodexDependencies.production()`），避免兩個語意混淆。
extension CodexDependencies {
    static func inert() -> CodexDependencies {
        CodexDependencies(installer: FakeCodexInstaller(mode: .normal), translocated: false,
                          inDownloads: false, writeToPasteboard: { _ in })
    }
}
