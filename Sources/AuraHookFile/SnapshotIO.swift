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

    /// 只接受單一路徑片段的安全字元，長度 1...128。
    public static func isSafeSessionID(_ id: String) -> Bool {
        guard (1...128).contains(id.count), id != ".", id != ".." else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
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
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let fd = open(url.path, O_RDWR | O_CREAT, 0o644)
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
        if FileManager.default.fileExists(atPath: url.path) {
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
