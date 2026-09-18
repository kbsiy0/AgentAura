import Foundation
import AuraCore

/// spec `2026-09-18-codex-support-design.md` §4.4：Codex 側 `~/.codex/hooks.json` 的
/// 一鍵接上／斷開。**只碰 `<codexHome>/hooks.json`**，絕不碰 `config.toml`（D-j／R-8）。
///
/// **`Sendable`**——欄位只有兩個 `URL`，同 `Installer` 的既有理由：背景執行緒安全，
/// 也不持有 `UserDefaults`（憑證 I/O 留在 app 層的 `CodexHookStore`，同 R1）。
public struct CodexInstaller: Sendable {
    /// `~/.codex`（生產）或注入的 temp 根（測試）。**可以自己是 symlink**（D-p）——
    /// 不拒絕，但寫入落在哪裡由 POSIX 路徑解析自然決定：`hooksJSONURL` 只是字面上
    /// `codexHome` 底下的 `hooks.json`，若 `codexHome` 本身是指到目錄的 symlink，
    /// `open`／`lstat` 對中間路徑段照樣會 follow（只有**最後一段**受 `O_NOFOLLOW`
    /// 影響）——不必額外呼叫 `realpath` 才能落在正確位置，只有 `displayPath`
    /// （純 UI 用途）才需要。
    public let codexHome: URL
    /// `codexHome.appendingPathComponent("hooks.json")`，在 `init` 算一次
    /// （同 `Installer.linkURL` 的既有理由：`connect`／`disconnect`／`probe` 都要用到）。
    public let hooksJSONURL: URL

    public init(codexHome: URL) {
        self.codexHome = codexHome
        self.hooksJSONURL = codexHome.appendingPathComponent("hooks.json")
    }

    /// 生產組裝：真的 `~/.codex`。
    public static func production() -> CodexInstaller {
        CodexInstaller(codexHome: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex"))
    }

    /// §4.4：路徑 guard → `O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC`（D-i）→ 寫 → close →
    /// 回傳寫出去的位元組。`codexHome` 不是目錄先 throw `.codexHomeMissing`（**不建立它**）。
    /// **`EEXIST` 一律 → `.alreadyExists`**（四種佔用形狀實測全部 `EEXIST`，沒有 `EISDIR`，
    /// 見 `CodexInstallerClobberTests`）。
    ///
    /// **第一行是保本 guard，不准只信路由層**（S0-1(ii)／R-5）：`connect(json:...)` 沒有
    /// 獨立的 `hookBinaryPath` 參數——呼叫端已經把它烤進 `json`（`CodexHooksJSON.json(
    /// hookBinaryPath:)` 的輸出），所以這裡從 `json` 反推同一個字串再送進
    /// `CodexHookPathCheck.rejection(...)`。反推失敗（呼叫端傳了非產生器輸出的畸形
    /// `json`）時**只放棄字元檢查**，`translocated`／`inDownloads` 兩個布林旗標本身
    /// 不靠反推、永遠照樣檢查——那是 R-9 最在意的一種（會在錯的時機刪檔），這裡不能
    /// 因為 json 解不開就跟著失效。
    @discardableResult
    public func connect(json: Data, translocated: Bool, inDownloads: Bool) throws -> Data {
        let hookBinaryPath = Self.extractHookBinaryPath(from: json) ?? ""
        if let rejection = CodexHookPathCheck.rejection(
            translocated: translocated, inDownloads: inDownloads, hookBinaryPath: hookBinaryPath) {
            throw CodexFailure(rejection: rejection)
        }

        var homeStat = stat()
        guard stat(codexHome.path, &homeStat) == 0, (homeStat.st_mode & S_IFMT) == S_IFDIR else {
            throw CodexFailure.codexHomeMissing
        }

        let fd = open(hooksJSONURL.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            let code = errno
            throw code == EEXIST ? CodexFailure.alreadyExists : CodexFailure.writeFailed(code)
        }
        defer { close(fd) }
        do {
            try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: json)
        } catch {
            throw CodexFailure.writeFailed(errno)
        }
        return json
    }

    /// §4.4：`O_RDONLY|O_NOFOLLOW` → `fstat` 確認 `S_IFREG` → 讀 → **逐位元組比對**
    /// → 不符 throw `.notOurs`（不刪）→ 相符 → 交給 `unlinkIfIdentityUnchanged(_:)`
    /// 做最後一道複查再刪。`expected == nil`（憑證遺失）**一律**當作不符——`absent`
    /// 除外：檔案本來就不在時，不論 `expected` 是什麼都算「已經斷開」，冪等成功。
    public func disconnect(ifContentsEqual expected: Data?) throws {
        let fd = open(hooksJSONURL.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else {
            let code = errno
            if code == ENOENT { return }              // absent：冪等成功
            if code == ELOOP { throw CodexFailure.notOurs }   // 自己是 symlink：不刪
            throw CodexFailure.unreadable(code)
        }
        defer { close(fd) }

        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else {
            throw CodexFailure.notOurs   // 目錄或其他型別：不刪
        }

        let actual = try? FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd()
        guard let expected, actual == expected else {
            throw CodexFailure.notOurs
        }

        try unlinkIfIdentityUnchanged(FileIdentity(dev: st.st_dev, ino: st.st_ino))
    }

    /// POSIX 沒有「內容相符才 unlink」的原子原語——`disconnect` 已經用同一個 fd 完成
    /// 讀取與內容比對，這裡是最後一道複查：unlink **前**再 `lstat` 一次路徑，比對
    /// 是不是還是剛剛那個 `(dev, ino)`，不同就放棄。**`internal`，不是 `private`**：
    /// 一般情境下沒有東西會在 `disconnect()` 兩次呼叫之間真的把檔案換掉，從
    /// `disconnect()` 整體外部測不出「拿掉這道複查會不會出事」——`CodexInstallerTests`
    /// 直接餵一個刻意不符的 `identity` 測這一步（同 `Installer.guardWriteTarget()`／
    /// `performConnectStepsGuardsWriteTargetDirectly` 的既有先例）。
    func unlinkIfIdentityUnchanged(_ identity: FileIdentity) throws {
        var recheck = stat()
        guard lstat(hooksJSONURL.path, &recheck) == 0,
              recheck.st_dev == identity.dev, recheck.st_ino == identity.ino else {
            throw CodexFailure.notOurs
        }
        guard unlink(hooksJSONURL.path) == 0 else {
            throw CodexFailure.writeFailed(errno)
        }
    }

    /// `CodexHooksJSON.json(hookBinaryPath:)` 的逆運算：每個事件的 `command` 都是
    /// `"\(hookBinaryPath) \(agentFlag)"`（同一個值，任取一個即可）。零 I/O、零平台 API，
    /// 解析失敗回 nil（呼叫端只用來做 2 層保本檢查，不是唯一防線）。
    static func extractHookBinaryPath(from json: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let hooksByEvent = root["hooks"] as? [String: Any],
              let anyGroupList = hooksByEvent.values.first as? [[String: Any]],
              let group = anyGroupList.first,
              let entries = group["hooks"] as? [[String: Any]],
              let command = entries.first?["command"] as? String
        else { return nil }
        let suffix = " \(CodexHooksJSON.agentFlag)"
        return command.hasSuffix(suffix) ? String(command.dropLast(suffix.count)) : command
    }
}
