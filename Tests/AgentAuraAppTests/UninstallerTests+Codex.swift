import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// review m4：搬出 `UninstallerTests.swift`（撞到 300 行 Tests 上限）——沿用同一份
/// `makeRig`／`cleanup`／`wait`（同一個 test target，internal 可見）。
extension UninstallerTests {
    /// codex disconnect 用 `try?`（D-n 正確），但交付時沒有任何測試讓它真的拋錯——而拋錯
    /// 是 **P2 使用者的常態路徑**（他自己的 `hooks.json`，跟我們記錄的憑證對不上）。這裡
    /// 讓 fake 磁碟上有內容、`codexStore` 留空，`disconnect(ifContentsEqual: nil)` 對非 nil
    /// 磁碟內容必定拋 `.contentsMismatch`；斷言 recycler／terminator 仍各自跑一次，證明
    /// `try?` 真的擋住了那個錯誤，不是靠巧合才沒炸開整個 `run()`。
    @Test("m4：codex disconnect 拋錯（P2 常態路徑）不阻斷後續步驟——recycler／terminator 仍各跑一次")
    func codexDisconnectThrowingDoesNotBlockRemainingSteps() async throws {
        let rig = try makeRig()
        defer { cleanup(rig) }
        _ = try rig.codexInstaller.connect(json: Data("someone-elses-hooks-json".utf8),
                                           translocated: false, inDownloads: false)
        #expect(rig.codexStore.contents == nil, "前提：store 沒有寫入過任何內容，disconnect 的比對必定不符")

        let bundleURL = URL(fileURLWithPath: "/tmp/fake.app")
        Uninstaller(installer: rig.installer, loginItem: rig.loginItem, defaults: rig.defaults,
                   bundleIdentifier: rig.suite, stateDirectory: rig.stateDirectory, homeDirectory: rig.stateHome,
                   recycler: rig.recycler, bundleURL: bundleURL, terminator: rig.terminator, language: .traditionalChinese,
                   codexInstaller: rig.codexInstaller, codexStore: rig.codexStore).run()

        await wait(upTo: 2) { rig.terminator.terminateImmediatelyCallCount == 1 }
        #expect(rig.codexInstaller.diskContents != nil, "disconnect 拋錯，磁碟內容應該還在（沒被清掉）")
        #expect(rig.recycler.recycledURLs == [bundleURL], "codex disconnect 拋錯不該阻斷 recycler 這一步")
        #expect(rig.terminator.terminateImmediatelyCallCount == 1, "codex disconnect 拋錯不該阻斷最後的 terminate")
    }
}
