import Foundation
import AuraHookFile

/// T24：D-1「完整移除」的五個動作，依序執行、冪等（D-6）——讓機器回到「從未安裝過」的
/// 狀態。每一步各自 best-effort（`try?`／guard 早退），沒有一步的失敗該卡住後面的步驟
/// （同 Lessons #8「收尾動作與保本動作分離」——這裡全部都是保本動作，彼此不互相依賴）。
///
/// D-3：登入項目要在清 defaults **之前**處理（`SMAppService` 可能寫入），清完
/// persistent domain 後立刻進最後一步，不再讓任何程式碼有機會寫回偏好設定。
///
/// `bundleIdentifier`／`bundleURL` 為 `nil`：呼叫端判斷「現在不是真的 app bundle 執行」
/// （`swift test`／`swift run`，同 `LoginItem.runningFromBundle` 既有的判斷依據
/// `Bundle.main.bundleIdentifier != nil`）——composition root 因此不必為這兩步另開一條
/// 測試專用的注入縫：`swift test` 下它們天生是 nil，這兩步自然跳過。
@MainActor
struct Uninstaller {
    let installer: Installer
    let loginItem: any LoginItemControlling
    let defaults: UserDefaults
    let bundleIdentifier: String?
    /// `~/.agentaura`（生產）或注入的 temp 目錄（測試）——同 `Installer.claudeHome` 的
    /// 注入模式，不直接讀 `SnapshotIO.defaultRoot`。
    let stateDirectory: URL
    let homeDirectory: URL
    let recycler: any BundleRecycling
    let bundleURL: URL?
    /// 存整個 `any AppTerminating`（同 `AppDelegate.terminator` 的既有型別），不是抽出
    /// `.terminate` 當成一個裸閉包欄位——結構型別的閉包欄位會被 Swift 6 要求 `@Sendable`，
    /// 而由 protocol existential 取出的 bound method 不是，兩者對不上（實測撞過一次）。
    let terminator: any AppTerminating

    func run() {
        try? loginItem.set(false)
        try? installer.disconnect()
        StateDirectoryEraser.erase(stateDirectory, home: homeDirectory)
        erasePersistentDomain()
        recycleBundleAndTerminate()
    }

    private func erasePersistentDomain() {
        guard let bundleIdentifier else { return }
        defaults.removePersistentDomain(forName: bundleIdentifier)
        defaults.synchronize()
    }

    /// **`terminateImmediately()` 只在垃圾桶操作的 completion 裡呼叫，不是發出去就馬上
    /// 終止**——`NSWorkspace.recycle` 是非同步的，行程若在完成前就結束，垃圾桶操作有沒有
    /// 真的落地是未定義的。`bundleURL == nil` 時沒有東西可移，直接終止。**用
    /// `terminateImmediately()` 不是 `terminate()`**——team-lead 真機實測：`NSApp.terminate()`
    /// 的 AppKit teardown 會把 `erasePersistentDomain()` 剛清空的 domain 部分寫回去
    /// （`NSToolbar Configuration com.apple.NSColorPanel` 這個鍵），跳過那段 teardown
    /// 才是「完整移除」名副其實的必要條件。
    ///
    /// T25：completion 帶的 `Error?` 以前被 `_` 整個吞掉——真機事故裡 app 從
    /// `/Applications` 消失，卻沒有進垃圾桶，而且無法從程式裡知道發生了什麼，因為根本
    /// 沒有接住結果。失敗時交給 `UninstallFailureLog` 留下線索；成功時什麼都不寫
    /// （見 `UninstallFailureLog` 的 doc comment）。
    private func recycleBundleAndTerminate() {
        guard let bundleURL else { terminator.terminateImmediately(); return }
        recycler.recycle(bundleURL) { [terminator, homeDirectory] error in
            if let error {
                UninstallFailureLog.record(error: error, source: bundleURL, home: homeDirectory)
            }
            Task { @MainActor in terminator.terminateImmediately() }
        }
    }
}

/// T25：垃圾桶動作失敗時唯一留下線索的地方——只在失敗時才寫檔，成功時完整移除
/// 不該留下任何殘留（`recycleSuccessLeavesNoFailureLog` 是這個決定的迴歸守衛）。
/// 寫到 `homeDirectory` 底下（同 `stateDirectory` 的既有注入縫，測試從不碰真實家目錄），
/// 不是 `UserDefaults`——這一步發生在 `erasePersistentDomain()` 之後，寫 defaults 會把
/// 剛清空的 domain 又建回來；也不用 `NSLog`——本專案實測它不進統一日誌，`log show`
/// 撈不到。內容覆蓋而非累加：同一台機器只在乎「上一次」有沒有失敗。
/// `scripts/verify-uninstall.sh` 第 6 項會檢查這個檔案存不存在，看到就大聲說出來，
/// 留給人判斷要不要刪。
enum UninstallFailureLog {
    static let filename = ".agentaura-uninstall.log"

    static func record(error: Error, source: URL, home: URL) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] 垃圾桶動作失敗：來源 \(source.path)，錯誤：\(error.localizedDescription)\n"
        try? line.write(to: home.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }
}
