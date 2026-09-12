import Foundation
import AuraCore

/// §3.1.1／§4.1 步驟 1：`connect()` 的路由決定，抽成純函式（T08，`affordanceRoutesConnect`）
/// ——純粹是 `state.affordance` 的函式，不碰檔案系統，讓 gate 可以對 `InstallState` 的
/// **全部** 27+3 格（`Reason.allCases × MountOwner.allCases` ＋三個頂層 case）窮盡驗證
/// 「N9 的兩個 switch（這裡與 `InstallAffordance.swift`）不再漂移」，不必為每一格都真的
/// 建一份磁碟 fixture。
public enum ConnectRoute: Equatable, Sendable {
    case alreadyConnected
    case cannotConnect(InstallState.Reason?)
    case needsExternalChoice
    case proceed
}

extension Installer {
    /// 純函式：**唯一輸入是 `affordance`**（§3.1.1 已經是唯一的路由來源，N9／S2-6）——
    /// 不重新看 `owner` 或 `InstallState` 本身，否則又是「兩個獨立寫的窮盡 switch」那個坑。
    public static func route(for affordance: ConnectAffordance, force: Bool) -> ConnectRoute {
        switch affordance {
        case .none: return .alreadyConnected
        case .explainOnly(let reason): return .cannotConnect(reason)
        case .replaceExternal: return force ? .proceed : .needsExternalChoice
        case .connect: return .proceed
        }
    }

    /// §4.1 全流程。**唯一的路由來源是 `InstallState.affordance`**（§3.1.1）——不再自己
    /// switch 狀態或看 `owner` 判斷可否安全替換（N9／S2-6）。實際路由決定委派給
    /// `Installer.route(for:force:)`，這裡只負責把每個 `ConnectRoute` case 接到對應的
    /// 早退／繼續動作。
    ///
    /// routing 用 `verification: .unknown`：`.hookBlockedOrBroken`／`.hookUnconfirmed` 與
    /// 其餘 broken Reason 的 affordance 完全相同（都是「再試一次接上」），差別只在最終是否
    /// 落到 `.connected`——routing 階段用不到那個分支，也不該讓這一層去讀持久憑證（R1）。
    ///
    /// 成功回傳**驗證過的 `hookBinaryStamp`**，供上層寫 `AgentAuraHookVerified`；已經接上時
    /// 直接回傳現有 stamp（冪等成功，不 throw——D-i／步驟1「`.none` → return .alreadyConnected」；
    /// 呼叫端據此顯示「已經接上了」banner，而不是把它當成錯誤處理）。
    @discardableResult
    public func connect(force: Bool, translocated: Bool, inDownloads: Bool) throws -> String {
        guard !translocated, !inDownloads else { throw InstallerFailure.mustMoveToApplications }

        let initial = probe()
        let state = InstallState.from(initial, verification: .unknown)
        switch Installer.route(for: state.affordance, force: force) {
        case .alreadyConnected:
            guard let stamp = initial.hookBinaryStamp else {
                throw InstallerFailure.verificationFailed
            }
            return stamp
        case .cannotConnect(let reason):
            throw InstallerFailure.cannotConnect(reason)
        case .needsExternalChoice:
            throw InstallerFailure.externalMountNeedsChoice
        case .proceed:
            break
        }
        return try performConnectSteps()
    }

    /// `replaceExternalMount` 就是 `connect(force: true, …)`（N6）——同一段實作，guard 0、
    /// 原子替換、exec 驗證全部共用；只有第 1 步的 `.replaceExternal` 早退被跳過。
    @discardableResult
    public func replaceExternalMount(translocated: Bool, inDownloads: Bool) throws -> String {
        try connect(force: true, translocated: translocated, inDownloads: inDownloads)
    }

    /// §4.1 步驟 2–6。**`internal`，不是 `private`**：`installerRefusesToClobber`（G3a）要能
    /// 繞過步驟 0–1 直接測第 4 步的寫入點型別檢查——那道護欄擋的是 probe（步驟1）到
    /// rename（步驟4）之間的 TOCTOU 窗，一般情境下 affordance 早已先擋住同樣的違規，
    /// 只從 `connect()` 整體外部測不出「拿掉第 4 步會不會出事」（S0-1(ii)）。
    func performConnectSteps() throws -> String {
        guard FileManager.default.fileExists(atPath: bundlePluginURL.path) else {
            throw InstallerFailure.bundleIncomplete
        }
        if !FileManager.default.fileExists(atPath: skillsURL.path) {
            // 只這一層——`~/.claude` 不存在時 affordance 已在上一步擋下（.claudeNotFound）。
            try FileManager.default.createDirectory(at: skillsURL, withIntermediateDirectories: false)
        }
        try guardWriteTarget()
        try atomicReplace()

        let after = probe()
        let afterState = InstallState.from(after, verification: .unknown)
        guard case .connected = afterState, let stamp = after.hookBinaryStamp else {
            throw InstallerFailure.verificationFailed
        }
        return try verifyByExecuting(stamp: stamp)
    }

    /// S0-1(ii)：保本動作要在執行層驗，不能只信路由層。**只有 absent 或 `S_IFLNK` 才准繼續**
    /// ——普通檔案被 `rename` 蓋掉是 rc=0、內容直接消失（實測）；實體目錄是 EISDIR。
    func guardWriteTarget() throws {
        var st = stat()
        guard lstat(linkPath, &st) == 0 else { return }   // absent：可以繼續
        guard (st.st_mode & S_IFMT) == S_IFLNK else {
            throw InstallerFailure.writeTargetOccupied
        }
    }

    /// `symlink(bundledPlugin → tmp)` → `rename(tmp → linkURL)`：**永不先 unlink**，
    /// 舊的 symlink（若有）被 `rename` 直接蓋掉（實測可行）。
    func atomicReplace() throws {
        let tmp = skillsURL.appendingPathComponent("agentaura.tmp-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: tmp, withDestinationURL: bundlePluginURL)
        guard rename(tmp.path, linkPath) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: tmp)
            throw InstallerFailure.renameFailed(code)
        }
    }

    /// **只有 `lstat` 回 `S_IFLNK` 才 unlink**（S1-S2：唯一會刪到使用者資料的路徑）；其餘
    /// 一律拒絕。**不刪 `~/.agentaura/`、不刪 app、不呼叫 `acknowledgeAll()`**（S1-A9——
    /// 那些屬於 app 層，這裡連引用都不該有）。absent 視為已斷開，冪等成功。
    public func disconnect() throws {
        var st = stat()
        guard lstat(linkPath, &st) == 0 else { return }
        guard (st.st_mode & S_IFMT) == S_IFLNK else {
            throw InstallerFailure.writeTargetOccupied
        }
        try FileManager.default.removeItem(at: linkURL)
    }
}
