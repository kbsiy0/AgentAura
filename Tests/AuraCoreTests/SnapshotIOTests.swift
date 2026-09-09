// Tests/AuraCoreTests/SnapshotIOTests.swift
import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

@Suite("SnapshotIO 鎖與檔名安全")
struct SnapshotIOTests {

    /// 每個測試各自一個暫存 root，避免互相干擾。
    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-test-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func snap(_ id: String, _ a: Activity) -> SessionSnapshot {
        var s = SessionSnapshot(sessionID: id)
        s.mainActivity = a; s.writtenAt = Date(timeIntervalSince1970: 1_788_628_000)
        s.hookEventName = "PreToolUse"
        return s
    }

    // ---- round-trip ----

    @Test("寫入後讀回完全相同")
    func roundTrip() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .waiting) }
        let back = try #require(SnapshotIO.read(sessionID: "s1", root: root))
        #expect(back == snap("s1", .waiting))
    }

    @Test("update 的 transform 收到既有值，可做累積")
    func updateSeesExisting() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .working) }
        try SnapshotIO.update(sessionID: "s1", root: root) { old in
            #expect(old?.mainActivity == .working, "第二次 update 必須看到第一次的結果")
            var s = old!; s.toolFailures = 7; return s
        }
        #expect(SnapshotIO.read(sessionID: "s1", root: root)?.toolFailures == 7)
    }

    @Test("讀取不存在的 session 回 nil")
    func readMissing() throws {
        // try 要在 #expect 之外求值：巨集展開後會把引數包進 autoclosure，
        // 裡面的 try 變成「call can throw, but it is not marked with 'try'」。
        let root = try makeRoot()
        #expect(SnapshotIO.read(sessionID: "nope", root: root) == nil)
    }

    // ---- 對抗式：畸形檔案 ----

    @Test("截斷的 JSON 檔回 nil，不得 crash")
    func truncatedFileReturnsNil() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .waiting) }
        let url = try SnapshotIO.url(for: "s1", root: root)
        let full = try Data(contentsOf: url)
        for cut in [0, 1, full.count / 3, full.count / 2, full.count - 1] {
            try full.prefix(cut).write(to: url)
            #expect(SnapshotIO.read(sessionID: "s1", root: root) == nil,
                    "截斷 \(cut) bytes 應回 nil —— 呼叫端須保留上次已知狀態，不得當成 session 不存在")
        }
    }

    @Test("垃圾內容回 nil")
    func garbageFileReturnsNil() throws {
        let root = try makeRoot()
        let url = try SnapshotIO.url(for: "s1", root: root)
        for junk in ["", "   ", "not json", "{}", "[]", "null", "{\"schema\":1}"] {
            try Data(junk.utf8).write(to: url)
            #expect(SnapshotIO.read(sessionID: "s1", root: root) == nil)
        }
    }

    // ---- 檔名安全（path traversal）----

    @Test("合法 session_id 通過")
    func safeIDsAccepted() {
        for id in ["abc123", "e69dc6d9-7364-4619-a438-159b48151b02", "a.b_c-d", "A1"] {
            #expect(SnapshotIO.isSafeSessionID(id), "\(id) 應合法")
        }
    }

    @Test("path traversal 與控制字元一律拒絕")
    func unsafeIDsRejected() {
        for id in ["..", ".", "../etc/passwd", "a/b", "a\\b", "", " ", "a b",
                   "a\u{0}b", "a\nb", "~/x", "/abs", String(repeating: "x", count: 200)] {
            #expect(!SnapshotIO.isSafeSessionID(id), "\(id.debugDescription) 應被拒絕")
        }
    }

    /// `HookFileSource.emit` 依賴這個契約 —— 它不再自己重驗 `isSafeSessionID`，
    /// 因為那份重複的守衛永遠不會觸發（實測移除後零測試變紅）。
    /// 這條測試就是那份依賴的釘子：檔案**真的存在**時 `read` 仍必須拒絕。
    @Test("不安全的 session_id 即使檔案真的存在，read 仍回 nil")
    func readRejectsUnsafeIDEvenIfFileExists() throws {
        let root = try makeRoot()
        // 直接寫一個合法檔名、但 stem 不是合法 session id 的檔
        let payload = try SnapshotIO.encoder.encode(snap("bad name", .error))
        try payload.write(to: root.appendingPathComponent("bad name.json"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("bad name.json").path))

        #expect(SnapshotIO.read(sessionID: "bad name", root: root) == nil,
                "檔案存在也不能讀 —— 這是 HookFileSource.emit 依賴的那一層防護")
        #expect(SnapshotIO.read(sessionID: "../escaped", root: root) == nil)
    }

    @Test("不安全的 session_id 讓 url(for:) 丟錯，不得寫到目錄外")
    func unsafeIDThrows() throws {
        let root = try makeRoot()
        #expect(throws: SnapshotIOError.self) {
            _ = try SnapshotIO.url(for: "../escaped", root: root)
        }
    }

    // ---- 併發（flock 的存在理由）----

    @Test("同一 session 的 8 條併發 update 不遺失任何一次累加")
    func concurrentUpdatesDoNotLoseCounts() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .working) }

        let iterations = 40, workers = 8
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            for _ in 0..<iterations {
                try? SnapshotIO.update(sessionID: "s1", root: root) { old in
                    var s = old ?? self.snap("s1", .working)
                    s.toolFailures += 1
                    return s
                }
            }
        }
        let final = try #require(SnapshotIO.read(sessionID: "s1", root: root))
        #expect(final.toolFailures == iterations * workers,
                "flock 必須讓 read-merge-write 成為原子操作")
    }

    @Test("50 個不同 session 併發寫入互不干擾")
    func concurrentDistinctSessions() throws {
        let root = try makeRoot()
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            try? SnapshotIO.update(sessionID: "s\(i)", root: root) { _ in
                self.snap("s\(i)", i.isMultiple(of: 3) ? .waiting : .working)
            }
        }
        #expect(SnapshotIO.allSessionIDs(root: root).count == 50)
        for i in 0..<50 {
            #expect(SnapshotIO.read(sessionID: "s\(i)", root: root)?.sessionID == "s\(i)")
        }
    }

    @Test("併發讀寫時讀取端不會拿到半截檔（讀到 nil 可接受，crash 不可）")
    func concurrentReadWhileWriting() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .working) }
        DispatchQueue.concurrentPerform(iterations: 4) { w in
            for i in 0..<200 {
                if w == 0 {
                    try? SnapshotIO.update(sessionID: "s1", root: root) { old in
                        var s = old ?? self.snap("s1", .working); s.toolFailures = i; return s
                    }
                } else {
                    _ = SnapshotIO.read(sessionID: "s1", root: root)
                }
            }
        }
        #expect(SnapshotIO.read(sessionID: "s1", root: root) != nil)
    }

    // ---- 其他 ----

    @Test("delete 移除檔案，allSessionIDs 隨之更新")
    func deleteRemoves() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .done) }
        #expect(SnapshotIO.allSessionIDs(root: root) == ["s1"])
        try SnapshotIO.delete(sessionID: "s1", root: root)
        #expect(SnapshotIO.allSessionIDs(root: root).isEmpty)
        try SnapshotIO.delete(sessionID: "s1", root: root)   // 重複刪不得丟錯
    }

    /// 三個過濾條件各有一個**只有它能擋**的樣本 —— 否則某個條件移除了測試還是綠的。
    /// 實測過：原本只放一個叫 `sub` 的目錄，光靠副檔名就擋掉了，
    /// `isRegularFile` 與 `isSafeSessionID` 兩個過濾都是空轉。
    @Test("allSessionIDs 的三個過濾條件各自都有牙齒")
    func allSessionIDsFilters() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .done) }

        // 只有副檔名過濾擋得住
        try Data("x".utf8).write(to: root.appendingPathComponent("README.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        // 只有 isRegularFile 擋得住：一個**目錄**叫 dir.json
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dir.json"),
                                                withIntermediateDirectories: true)
        // 只有 isSafeSessionID 擋得住：檔名 stem 含空白，是合法檔名但不是合法 session id
        try Data("{}".utf8).write(to: root.appendingPathComponent("bad name.json"))

        #expect(SnapshotIO.allSessionIDs(root: root) == ["s1"],
                "多出來的是：\(SnapshotIO.allSessionIDs(root: root))")
    }

    @Test("root 不存在時 update 會自動建立")
    func createsRootDirectory() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-test-\(UUID().uuidString)/deep/sessions")
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .idle) }
        #expect(SnapshotIO.read(sessionID: "s1", root: root) != nil)
    }

    /// **狀態檔含使用者的工作內容**（`cwd`、tool 參數、助理輸出的開頭），
    /// 沒有理由讓同機其他帳號讀得到。
    @Test("狀態檔 0600、目錄 0700")
    func filePermissionsArePrivate() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "p1", root: root) { _ in self.snap("p1", .working) }
        let fm = FileManager.default
        let file = try SnapshotIO.url(for: "p1", root: root)
        let fileMode = try #require(fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
        #expect(fileMode.int16Value == 0o600, "狀態檔權限是 \(String(fileMode.int16Value, radix: 8))")
        let dirMode = try #require(fm.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)
        #expect(dirMode.int16Value == 0o700, "狀態目錄權限是 \(String(dirMode.int16Value, radix: 8))")
    }
}
