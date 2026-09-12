import Foundation
import AuraCore

/// spec `2026-09-10-app-shell-design.md` §4.1：一鍵接上／斷開。
///
/// **`Sendable`**——欄位只有 `URL`／`URL?`，背景執行緒只做 exec 並回傳結果；
/// **不得**持有或碰 `UserDefaults`（R1：`Sendable` conformance 在 Swift 6 下
/// unavailable，且憑證 I/O 本就該留在 app 層的 `HookVerificationStore`）。
public struct Installer: Sendable {
    /// `~/.claude`（生產）或注入的 temp 根（測試）。**只准碰這裡的 `skills[/agentaura]`**
    /// （D-h），其餘 `~/.claude/` 唯讀。
    public let claudeHome: URL
    /// app bundle 內的 `plugin` 目錄（生產）或注入的 fixture 目錄（測試，含
    /// `hooks/hooks.json`／`bin/aura-hook`——G4(b) 用的是真的 SwiftPM 產物）。
    public let bundlePluginURL: URL
    /// 測試注入點，見 `verifyByExecuting(stamp:)` 的文件。
    public let verificationRootOverride: URL?
    /// exec 驗證的有界等待上限（秒）。生產 2 秒；**測試必須注入**（T06b）：
    /// 全套件並行時真的 spawn 會與其他測試搶行程資源，2 秒偶發不夠 → 正常路徑被誤判成
    /// `.unconfirmed`（實測 4 次全量跑有 2 次紅）。而逾時那條 gate 反過來注入一個很小的值，
    /// 就不必真的等 2 秒、也不再依賴「機器夠慢」這種不可控前提。
    public let verificationTimeout: Double

    public init(claudeHome: URL, bundlePluginURL: URL, verificationRootOverride: URL? = nil,
                verificationTimeout: Double = 2) {
        let skills = claudeHome.appendingPathComponent("skills")
        let link = skills.appendingPathComponent("agentaura")
        self.skillsURL = skills
        self.linkURL = link
        self.linkPath = link.path
        self.claudeHome = claudeHome
        self.bundlePluginURL = bundlePluginURL
        self.bundlePluginPath = bundlePluginURL.path
        self.verificationRootOverride = verificationRootOverride
        self.verificationTimeout = verificationTimeout
    }

    /// 生產組裝：真的 `~/.claude` ＋ app bundle 內的 `plugin`。
    public static func production() -> Installer {
        Installer(
            claudeHome: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
            bundlePluginURL: (Bundle.main.resourceURL ?? URL(fileURLWithPath: "/nonexistent"))
                .appendingPathComponent("plugin"))
    }

    /// 這兩個 URL 與它們的 `path` 是 `claudeHome` 的純函式、行程內不會變，所以在 `init`
    /// 算一次就好——**不是為了漂亮，是量出來的**：`linkURL` 每次重新 `appendingPathComponent`
    /// 兩層要 ~16 µs，而 `probe()` 用到它三次（`lstat`／`readlink`／`realpath`），
    /// 光這一項就佔掉整個 probe 128 µs 裡的 ~48 µs（T10a 實測分解）。
    let skillsURL: URL
    let linkURL: URL
    /// `URL.path` 本身也要成本，`probe()`／`connect()` 全部改用這個。
    let linkPath: String
    /// D2（/simplify 波次1，eff#8）：`linkPath` 的雙生子——`thisAppIdentity()` 每次 probe
    /// 都重算 `bundlePluginURL.path`，同一個理由在 `init` 算一次。
    let bundlePluginPath: String

    /// §3.1／§4.1：觀測目前的掛載狀態，零判定邏輯——判定住在 `InstallState.from(_:verification:)`。
    /// **只 stat 一次目標 hook 二進位**（T01 必辦④：`hookBinaryStamp` 與 exists／executable
    /// 共用同一次 `stat`／`access`，不讓後續任何人再對同一顆檔案 stat 第二次）。
    public func probe() -> LinkObservation {
        let claudeHomeExists = isDirectory(claudeHome)
        var linkStat = stat()
        guard lstat(linkPath, &linkStat) == 0 else {
            return observation(claudeHomeExists: claudeHomeExists, entryType: .absent)
        }
        let entryType = Self.entryType(of: linkStat.st_mode)
        guard entryType == .symlink else {
            return observation(claudeHomeExists: claudeHomeExists, entryType: entryType)
        }

        let rawTarget = readRawLinkTarget(linkURL)
        guard let resolvedPath = resolveRealPath(linkURL) else {
            return observation(claudeHomeExists: claudeHomeExists, entryType: .symlink,
                                resolveFailure: Self.resolveFailure(errno: errno), rawLinkTarget: rawTarget)
        }
        var targetStat = stat()
        guard stat(resolvedPath, &targetStat) == 0 else {
            // TOCTOU：realpath 成功後目標消失，視同解析失敗（目標不存在）。
            return observation(claudeHomeExists: claudeHomeExists, entryType: .symlink,
                                resolveFailure: .notFound, rawLinkTarget: rawTarget)
        }
        let isDir = (targetStat.st_mode & S_IFMT) == S_IFDIR
        let identity = FileIdentity(dev: targetStat.st_dev, ino: targetStat.st_ino)
        // D2（/simplify 波次1，eff#8）：字串串接組子路徑，不是 URL——`init` 已經為了
        // 這個理由把 `linkPath`／`bundlePluginPath` 算好一次，probe() 的後半段這裡曾經
        // 「長回」用 URL（實測 5.82 µs vs 字串 0.113 µs）。不動 stat／access 的次數與時機，
        // 只換組路徑的方式。
        let hooksJSONExists = FileManager.default.fileExists(atPath: resolvedPath + "/hooks/hooks.json")
        let (hookExists, hookExecutable, stamp) = hookBinaryStatus(at: resolvedPath + "/bin/aura-hook")

        return LinkObservation(
            claudeHomeExists: claudeHomeExists, entryType: .symlink, resolveFailure: nil,
            targetIsDirectory: isDir, targetIdentity: identity, thisAppPluginIdentity: thisAppIdentity(),
            hooksJSONExists: hooksJSONExists, hookBinaryExists: hookExists, hookBinaryExecutable: hookExecutable,
            hookBinaryStamp: stamp, rawLinkTarget: rawTarget, displayTargetPath: resolvedPath)
    }

    private func observation(claudeHomeExists: Bool, entryType: LinkObservation.EntryType,
                             resolveFailure: LinkObservation.ResolveFailure? = nil,
                             rawLinkTarget: String? = nil) -> LinkObservation {
        LinkObservation(claudeHomeExists: claudeHomeExists, entryType: entryType, resolveFailure: resolveFailure,
                        targetIsDirectory: false, targetIdentity: nil, thisAppPluginIdentity: thisAppIdentity(),
                        hooksJSONExists: false, hookBinaryExists: false, hookBinaryExecutable: false,
                        hookBinaryStamp: nil, rawLinkTarget: rawLinkTarget, displayTargetPath: nil)
    }

    private func thisAppIdentity() -> FileIdentity? {
        var st = stat()
        guard stat(bundlePluginPath, &st) == 0 else { return nil }
        return FileIdentity(dev: st.st_dev, ino: st.st_ino)
    }

    /// 一次 `stat` 拿存在性與 mtime 戳、一次 `access` 拿 x 位——不對同一顆檔案重複 stat。
    private func hookBinaryStatus(at path: String) -> (exists: Bool, executable: Bool, stamp: String?) {
        var st = stat()
        guard stat(path, &st) == 0 else { return (false, false, nil) }
        let executable = access(path, X_OK) == 0
        // st_mtimespec：秒＋奈秒（S2-9，同一秒內重建的 hook 不會讓憑證失效）。
        let stamp = "\(st.st_dev):\(st.st_ino):\(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec)"
        return (true, executable, stamp)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func readRawLinkTarget(_ url: URL) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }

    private func resolveRealPath(_ url: URL) -> String? {
        guard let cstr = realpath(url.path, nil) else { return nil }
        defer { free(cstr) }
        return String(cString: cstr)
    }

    static func entryType(of mode: mode_t) -> LinkObservation.EntryType {
        switch mode & S_IFMT {
        case S_IFLNK: return .symlink
        case S_IFDIR: return .directory
        default: return .otherFile
        }
    }

    static func resolveFailure(errno errorCode: Int32) -> LinkObservation.ResolveFailure {
        switch errorCode {
        case ENOENT: return .notFound
        case ELOOP: return .loop
        case EACCES: return .permissionDenied
        default: return .other(errorCode)
        }
    }
}

// `InstallerFailure` 搬進 `AuraCore`（B2，/simplify 波次1）——見 `AuraCore/InstallerFailure.swift`。
