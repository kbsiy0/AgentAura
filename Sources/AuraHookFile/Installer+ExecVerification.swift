import Foundation
import AuraCore

extension Installer {
    /// §4.1：獨立的「再驗證」入口，**不做 mkdir／atomicReplace**（那是 `connect()` 的工作，
    /// 這裡只重新 exec 驗證*目前已經在*的掛載）——供 app 層的兩個非 `connect()` 呼叫點使用：
    /// 啟動時的背景驗證（N1，僅當 `verification != .verified`）與 `recheckHook`（R2 的退化
    /// 出口）。`connect()` 對 `.none` affordance 早退不會重新 exec（T08 實測：`.connected(_,
    /// verified: .unknown)` 的 affordance 仍是 `.none`），這兩個呼叫點正是唯一能把 `.unknown`
    /// 撥回 `.verified`／`.blocked`／`.unconfirmed` 的路徑（R2：`unknown` 不得為終態）。
    /// E9（/simplify 波次2，alt#7）：回傳值帶著**這次真的驗證用的** `observation`——
    /// 呼叫端（`AppDelegate.beginBackgroundVerification`）原本自己另外 probe 一次拿
    /// `obs` 只為了決定「有沒有東西可驗」，驗證完卻拿那份**更早**的 obs 去 apply，
    /// 跟真正被 exec 驗過的（這裡內部的 `probe()`）不是同一份觀測。回傳兩者綁在一起，
    /// 讓「被驗的那一份」與「被 apply 的那一份」在型別上就是同一個值。
    public func reverifyCurrentMount() throws -> (observation: LinkObservation, stamp: String) {
        let obs = probe()
        guard let stamp = obs.hookBinaryStamp else {
            throw InstallerFailure.verificationFailed
        }
        // **只驗自己的掛載。**（公開前稽核，攻擊面 #1）
        //
        // 這條路徑會 `removexattr` 拆掉目標的 quarantine 再 exec 它，而且由
        // `AppDelegate.launchVerificationIfNeeded` 在**啟動時自動跑、零確認**。
        // 原本只檢查「有東西在那裡」，不檢查那是不是這個 app 自己 bundle 裡的那一份——
        // 於是使用者若手動 `ln -sfn` 把掛載指到別人給的目錄，我們會主動替那份程式碼
        // 拆掉 Gatekeeper 的保護再執行它。
        //
        // 不是遠端可利用（掛過去之後 Claude Code 每個 hook 事件本來就會執行它），
        // 但「自動、無聲、替不是自己的二進位拆保護」這件事不該由背景驗證來做。
        // 外部掛載要驗，走使用者明確按下、且有確認框的 `replaceExternalMount`。
        guard let target = obs.targetIdentity, let mine = obs.thisAppPluginIdentity,
              target == mine else {
            throw InstallerFailure.verificationFailed
        }
        return (obs, try verifyByExecuting(stamp: stamp))
    }

    /// §4.1 步驟 6（S0-A2 本步是重點）：**看產物，不是看 x 位或 exit code**——本專案自己的
    /// invariant「`aura-hook` exit code 無法用來驗收」對這裡同樣成立，quarantine 下的 exec
    /// 是 SIGKILL，`access(X_OK)` 照樣說可執行。
    ///
    /// 三種結果都不寫 `UserDefaults`（R1）：回傳值／拋出的 error 帶著 `stamp`，
    /// 由呼叫端（app 層的 `HookVerificationStore`）決定寫哪個鍵。
    ///
    /// **`verificationRootOverride`**：`nil`（正式路徑）時自建全新 UUID 暫存目錄並在結束後
    /// 清掉；測試注入非 nil 值時清理責任交還呼叫端——這是唯一能讓「整段拿掉這個函式」這個
    /// mutation 變成可觀察紅燈的方法（G4(b)：單看 `connect()` 回傳的 stamp 字串，「真的
    /// exec 過」與「壓根沒 exec 就回傳」分不出來；獨立檢查注入的暫存目錄底下真的出現了
    /// 狀態檔，兩者才分得開）。
    func verifyByExecuting(stamp: String) throws -> String {
        let hookBinary = linkURL.appendingPathComponent("bin/aura-hook")

        // 只對這一顆檔案 removexattr，不遞迴（實測：只清 binary 就夠，目錄仍帶隔離也能跑；
        // bundle 唯讀時這裡會 EPERM，失敗不致命——`.hookBlockedOrBroken` 那條路徑必須保留）。
        _ = removexattr(hookBinary.path, "com.apple.quarantine", 0)

        let ownsRoot = verificationRootOverride == nil
        let root = verificationRootOverride ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-verify-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { if ownsRoot { try? FileManager.default.removeItem(at: root) } }

        let sessionID = UUID().uuidString
        let payload = #"{"hook_event_name":"SessionStart","session_id":"\#(sessionID)"}"#
        // A1（/simplify 波次1，reuse#1）：檔名規則只有一個來源——`SnapshotIO.url(for:root:)`，
        // 跟 `aura-hook` 真正寫入時走的是同一個函式。先前這裡自己拼 `"\(sessionID).json"`，
        // `SnapshotIO` 的命名規則一改（加子目錄、換副檔名）寫入端會跟著改、這裡不會，
        // 正常掛載會被誤判成 `.hookBlockedOrBroken`（S2-11：不得誤指控 macOS）。
        // `sessionID` 是這裡自己產生的 UUID，必過 `isSafeSessionID`，`try?` 只是防禦性的。
        guard let artifactURL = try? SnapshotIO.url(for: sessionID, root: root) else {
            throw InstallerFailure.hookBlockedOrBroken(stamp: stamp)
        }

        let process = Process()
        process.executableURL = hookBinary
        process.environment = ProcessInfo.processInfo.environment
            .merging(["AGENTAURA_ROOT": root.path]) { _, new in new }
        let inPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            // spawn 本身丟錯（fork 失敗／沙箱）——不准讓狀態留在 unknown（R2）。
            throw InstallerFailure.hookUnconfirmed(stamp: stamp)
        }
        inPipe.fileHandleForWriting.write(Data(payload.utf8))
        try? inPipe.fileHandleForWriting.close()

        // 有界等待，**單調時鐘**（`DispatchTime` 基於 `mach_absolute_time`，不受牆上時鐘調整影響）。
        let deadline = DispatchTime.now() + .milliseconds(Int(verificationTimeout * 1000))
        while process.isRunning && DispatchTime.now() < deadline {
            usleep(10_000)
        }
        guard !process.isRunning else {
            // 逾時（機器睡眠等）：行程還在跑，無法確認——不得反過來誤指控 macOS（S2-11）。
            throw InstallerFailure.hookUnconfirmed(stamp: stamp)
        }

        guard FileManager.default.fileExists(atPath: artifactURL.path) else {
            // 真的跑完了但沒有產物：quarantine SIGKILL／arch 不符／複製損壞。
            throw InstallerFailure.hookBlockedOrBroken(stamp: stamp)
        }
        return stamp
    }
}
