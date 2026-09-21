import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// review M5：`FakeCodexInstaller` 的三個對抗式 mode
/// （`connectSucceedsButProbeStaysNotConnected`／`disconnectClaimsSuccessButLeavesFile`／
/// `probeReturnsUnavailable`）在 T10 交付時只被 double 的自我測試消費，沒有任何一條接線
/// 測試用到——T10 是最後一個會用到它們的 task，不用就等於這組 double 是裝飾。搬出主檔
/// （`CodexWiringSmokeTests.swift`）只是為了不撞 300 行 Tests 上限，沿用同一份
/// `makeDelegate`（同一個 test target，internal 可見，見那邊的 doc comment）。
extension CodexWiringSmokeTests {

    /// review M5①：對抗式 mode `connectSucceedsButProbeStaysNotConnected`——`connect()`
    /// 回報成功，但磁碟上其實沒有真的落地（fake 模擬「installer 自己說謊」）。**設計裁決**
    /// （spec 沒有明講，這裡選最不會騙人的那個，理由寫在這裡）：`codexState` 永遠是
    /// `reprobeCodex()` 重新算出來的、不是 `connect()` 回傳值直接決定的——即使
    /// `performConnectCodexUnblocked()` 已經先把 banner 設成「已接上」，緊接著的
    /// `reprobeCodex()` 仍然照 probe() 的真相把 `codexState` 訂成 `.notConnected`，
    /// 下一次面板重畫就會照實顯示，不會被那句 banner 卡住太久。
    @Test("對抗式 mode①：connect 回報成功但 probe 說沒接上時，codexState 以 probe 為準（不因 banner 已顯示成功而卡住）")
    func connectSuccessButProbeDisagreesTrustsProbe() throws {
        let fakeInstaller = FakeCodexInstaller(mode: .connectSucceedsButProbeStaysNotConnected)
        let (delegate, spy, cleanup) = try makeDelegate(translocated: false, fakeInstaller: fakeInstaller)
        defer { cleanup() }

        let onAction = try #require(spy.onAction, "AppDelegate 沒有接 status.onAction")
        onAction(.connectCodex)

        #expect(delegate.banner?.kind == .connected, """
            connect() 沒有 throw，banner 仍應顯示「已接上」（這是設計裁決的前半——banner 只反映
            connect() 呼叫本身的結果，不是 probe 的結果），實際 \(String(describing: delegate.banner?.kind))
            """)
        #expect(delegate.codexRuntime.codexState == .notConnected, """
            但緊接著的 reprobeCodex() 必須照 probe() 的真相走，codexState 應該是 .notConnected，\
            不能因為 connect() 回報成功就顯示 .connected，實際 \(delegate.codexRuntime.codexState)
            """)
    }

    /// review M5②：對抗式 mode `disconnectClaimsSuccessButLeavesFile`——`disconnect()`
    /// 沒有 throw（宣稱成功），但磁碟上的檔案其實還在。`performDisconnectCodex()` 在沒有
    /// throw 時會呼叫 `store.clear()`，之後 `reprobeCodex()` 重新 probe：磁碟非 nil、
    /// `recordedContents`（剛清空的 store）是 nil，`CodexState.from` 第 4 列判定成
    /// `.occupiedByOther`——不是 `.notConnected`，因為磁碟上真的還有一個我們認不得的檔案，
    /// 不是真的乾淨。
    @Test("對抗式 mode②：disconnect 宣稱成功但檔案還在時，下一次 reprobeCodex() 必須判成 .occupiedByOther（不是 .notConnected）")
    func disconnectClaimsSuccessButFileRemainsBecomesOccupied() throws {
        let seeded = Data("still-here-after-disconnect".utf8)
        let fakeInstaller = FakeCodexInstaller(mode: .disconnectClaimsSuccessButLeavesFile, seededDiskContents: seeded)
        let (delegate, spy, cleanup) = try makeDelegate(translocated: false, fakeInstaller: fakeInstaller)
        defer { cleanup() }
        // 前提：store 裡先有跟磁碟一致的憑證（同「已接上」狀態），才有東西可拆。
        delegate.codexRuntime.store.write(seeded)

        let onAction = try #require(spy.onAction, "AppDelegate 沒有接 status.onAction")
        onAction(.disconnectCodex)

        #expect(fakeInstaller.diskContents == seeded, "前提：fake 這個 mode 底下磁碟內容真的沒被清掉")
        #expect(delegate.codexRuntime.codexState == .occupiedByOther, """
            disconnect 宣稱成功但磁碟上的檔案其實還在時，reprobeCodex() 必須誠實回報
            .occupiedByOther，不能因為 disconnect 沒有 throw 就顯示成 .notConnected，\
            實際 \(delegate.codexRuntime.codexState)
            """)
    }

    /// review M5③：對抗式 mode `probeReturnsUnavailable`——`~/.codex` 本身探測失敗（吞成
    /// absent 形狀）。斷言分兩層：① `reprobeCodex()` 真的呼叫過 `probe()`（`probeCallCount
    /// > 0`）——這條防的是「codexState 剛好等於初始預設值 `.unavailable`、但其實從沒被
    /// reprobe 過」這種恰好綠的假象；② 把這個真實狀態餵回 `OptionsMenuModel.rows(...)`
    /// （拿 `spy.panels.last` 其餘欄位原封不動帶入，只換 `codex`／`codexPathRejection`），
    /// 三個 Codex action kind 一個都不該出現。
    @Test("對抗式 mode③：probe 說不可用時，codexState 是 .unavailable 且真的被 reprobe 過，Options 沒有任何 Codex 列")
    func probeUnavailableYieldsNoCodexOptionsRows() throws {
        let fakeInstaller = FakeCodexInstaller(mode: .probeReturnsUnavailable)
        let (delegate, spy, cleanup) = try makeDelegate(translocated: false, fakeInstaller: fakeInstaller)
        defer { cleanup() }

        #expect(fakeInstaller.probeCallCount > 0, """
            前提：reprobeCodex() 必須真的呼叫過 probe()，不能只是恰好停在初始值 .unavailable
            """)
        #expect(delegate.codexRuntime.codexState == .unavailable, """
            probe 說不可用時 codexState 應該是 .unavailable，實際 \(delegate.codexRuntime.codexState)
            """)

        let lastPanel = try #require(spy.panels.last, "launch 之後應該至少畫過一次面板")
        let rows = OptionsMenuModel.rows(install: lastPanel.install, launchAtLogin: lastPanel.launchAtLogin,
                                         isDefaultPalette: lastPanel.isDefaultPalette,
                                         systemReduceMotion: lastPanel.systemReduceMotion,
                                         userReduceMotion: lastPanel.userReduceMotion, iconPlate: lastPanel.iconPlate,
                                         iconShape: lastPanel.iconShape, palette: lastPanel.palette,
                                         language: lastPanel.language, codex: delegate.codexRuntime.codexState,
                                         codexPathRejection: delegate.codexRuntime.pathRejection)
        let codexKinds: Set<PanelActionKind> = [.connectCodex, .disconnectCodex, .copyCodexSnippet]
        #expect(rows.allSatisfy { !codexKinds.contains($0.action.kind) }, """
            .unavailable 時 Options 列不該包含任何 Codex action，實際列出的 kinds \
            \(rows.map(\.action.kind))
            """)
    }
}
