import Foundation
import AuraCore

public enum SnapshotIOError: Error, Equatable {
    case unsafeSessionID(String)
}

/// 狀態檔的讀寫。所有寫入在 `flock(LOCK_EX)` 下完成 read-merge-write；
/// 讀取取 `LOCK_SH`。
///
/// 檔案是 per-session，故跨 session 零競爭；同一 session 內事件近乎循序，
/// 但 `async: true` 理論上可能重疊 —— 鎖是必要的，不是可選的。
public enum SnapshotIO {

    public static let defaultRoot = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".agentaura/sessions")

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// D1（/simplify 波次1，eff#7）：`CharacterSet` 建構一次共用，不是每次呼叫重建
    /// （實測 3.44 µs → 0.42 µs／次）。純搬位置，字元集合與語意不變。
    private static let allowedSessionIDCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")

    /// 只接受單一路徑片段的安全字元，長度 1...128。
    public static func isSafeSessionID(_ id: String) -> Bool {
        guard (1...128).contains(id.count), id != ".", id != ".." else { return false }
        return id.unicodeScalars.allSatisfy { allowedSessionIDCharacters.contains($0) }
    }

    public static func url(for sessionID: String, root: URL = defaultRoot) throws -> URL {
        guard isSafeSessionID(sessionID) else { throw SnapshotIOError.unsafeSessionID(sessionID) }
        return root.appendingPathComponent("\(sessionID).json")
    }

    public static func read(sessionID: String, root: URL = defaultRoot) -> SessionSnapshot? {
        guard let url = try? url(for: sessionID, root: root),
              let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        flock(fh.fileDescriptor, LOCK_SH)
        defer { flock(fh.fileDescriptor, LOCK_UN) }
        guard let data = try? fh.readToEnd(), !data.isEmpty else { return nil }
        return try? decoder.decode(SessionSnapshot.self, from: data)
    }

    public static func update(sessionID: String,
                              root: URL = defaultRoot,
                              _ transform: (SessionSnapshot?) -> SessionSnapshot) throws {
        let url = try url(for: sessionID, root: root)
        // **0700 / 0600。** 這些檔含 `cwd`、tool 參數與助理輸出的開頭 ——
        // 是使用者的工作內容，沒有理由讓同機其他帳號讀得到。
        //
        // `createDirectory` 的 `attributes` 只在**真的建立**時生效，目錄已存在時
        // 是 no-op —— 而舊版建出來的目錄是 0755。所以建完再無條件設一次。
        // 設不成不該讓 hook 失敗（契約是「絕不干擾 agent」），故用 `try?`。
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // **只收緊真的是狀態目錄的路徑。** `root` 可被 `AGENTAURA_ROOT` 覆寫，而這一行
        // 原本是無條件的——`AGENTAURA_ROOT=$HOME` 會把家目錄靜默改成 0700（契約是靜默，
        // 所以連訊息都不會有）。只有使用者自己設得了那個環境變數，所以不是外部可利用，
        // 但「觀測工具靜默改別人目錄的權限位元」本身就不該發生。
        // 用末段是不是 `sessions` 當閘門：預設路徑與所有正當覆寫都符合，`$HOME` 不符合。
        if root.lastPathComponent == "sessions" {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: root.path)
        }

        // `O_NOFOLLOW`：狀態檔若被換成 symlink，寫入**拒絕跟出去**（失敗成 ELOOP），
        // 而不是把 JSON 寫進別人指定的位置。目錄是 0700，所以要植入 symlink 得先是同一個
        // 帳號或 root——不跨權限邊界，但零成本，而且與這個 codebase「只信 lstat、
        // 不信會 follow 的 API」的既有哲學一致（`Installer.disconnect`／`StateDirectoryEraser`）。
        let fd = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        // `O_CREAT` 的 mode 只在**建立時**套用 —— 舊版建出來的 0644 檔案
        // 就算被重寫一百次也還是 0644。所以每次都無條件收緊一次。
        // 失敗不該讓 hook 失敗（契約是「絕不干擾 agent」），故不檢查回傳值。
        if fd >= 0 { _ = fchmod(fd, 0o600) }
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EWOULDBLOCK) }
        defer { flock(fd, LOCK_UN) }

        let fh = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let existing = (try? fh.readToEnd()).flatMap { $0.isEmpty ? nil : $0 }
            .flatMap { try? decoder.decode(SessionSnapshot.self, from: $0) }

        let data = try encoder.encode(transform(existing))
        try fh.seek(toOffset: 0)
        try fh.truncate(atOffset: 0)
        try fh.write(contentsOf: data)
        try fh.synchronize()
    }

    public static func delete(sessionID: String, root: URL = defaultRoot) throws {
        let url = try url(for: sessionID, root: root)
        // `lstat` 而非 `fileExists`：後者會 follow symlink，所以懸空的 symlink 會被判定成
        // 「不存在」而留在原地。這裡要刪的是那個路徑本身（`removeItem` 對 symlink 是刪連結、
        // 不會跟出去），所以用只看路徑本身的 `lstat` 判斷。
        var st = stat()
        if lstat(url.path, &st) == 0 {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func allSessionIDs(root: URL = defaultRoot) -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        return items
            .filter { $0.pathExtension == "json"
                   && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter(isSafeSessionID)
            .sorted()
    }
}
