import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

@Suite("HookFileSource FSEvents 監看", .serialized)
struct HookFileSourceTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-fse-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ id: String, _ a: Activity, to root: URL) throws {
        try SnapshotIO.update(sessionID: id, root: root) { old in
            var s = old ?? SessionSnapshot(sessionID: id)
            s.mainActivity = a
            s.hookEventName = "PreToolUse"
            s.writtenAt = Date()
            return s
        }
    }

    /// 收集到的事件。用 actor 是為了讓逾時分支也能報出「收到了哪些」。
    actor Collected {
        private var items: [SessionSnapshot] = []
        func add(_ s: SessionSnapshot) -> [SessionSnapshot] { items.append(s); return items }
        func all() -> [SessionSnapshot] { items }
    }

    /// 從 AsyncStream 收集事件，直到滿足條件或**真的**逾時。
    ///
    /// 前一版寫成 `for await { got.append(); if predicate || Date() > deadline { break } }`,
    /// deadline 只在收到元素之後才檢查 —— 零元素時 `for await` 永久 block，
    /// `timeout` 參數形同虛設。實測：把 `FSEventStreamStart` 移除後，這個 suite
    /// 不是變紅而是**掛住**（90s 強殺、零輸出），CI 上會變成 hung job 而非失敗。
    /// 逾時必須由一條獨立的 task 計時並取消收集端。
    func collect(_ source: HookFileSource,
                 until predicate: @escaping @Sendable ([SessionSnapshot]) -> Bool,
                 timeout: TimeInterval = 5) async -> [SessionSnapshot] {
        let box = Collected()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await snap in source.snapshots {
                    if predicate(await box.add(snap)) { break }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            }
            await group.next()      // 誰先完成就結束
            group.cancelAll()
        }
        return await box.all()
    }

    // ---- bootstrap ----

    @Test("bootstrap 掃出目錄裡既有的全部 session")
    func bootstrapReadsExisting() throws {
        let root = try makeRoot()
        try write("b1", .waiting, to: root)
        try write("b2", .working, to: root)
        try write("b3", .error,   to: root)

        let source = HookFileSource(root: root)
        let got = source.bootstrap()
        #expect(Set(got.map(\.sessionID)) == ["b1", "b2", "b3"],
                "app 沒開時累積的事件，啟動即還原（spec §1 失效模式 2）")
        #expect(got.first { $0.sessionID == "b1" }?.mainActivity == .waiting)
    }

    @Test("bootstrap 對空目錄回空陣列，不丟錯")
    func bootstrapEmpty() throws {
        let root = try makeRoot()
        #expect(HookFileSource(root: root).bootstrap().isEmpty)
    }

    @Test("bootstrap 對不存在的目錄回空陣列，不丟錯")
    func bootstrapMissingDirectory() {
        let root = URL(fileURLWithPath: "/tmp/aura-definitely-missing-\(UUID().uuidString)")
        #expect(HookFileSource(root: root).bootstrap().isEmpty)
    }

    @Test("bootstrap 跳過畸形檔案但保留其餘（部分損壞不得拖垮全部）")
    func bootstrapSkipsCorrupt() throws {
        let root = try makeRoot()
        try write("good1", .waiting, to: root)
        try write("good2", .working, to: root)
        try Data("{ truncated".utf8).write(to: root.appendingPathComponent("bad.json"))

        let got = HookFileSource(root: root).bootstrap()
        #expect(Set(got.map(\.sessionID)) == ["good1", "good2"])
    }

    // ---- 即時監看 ----

    @Test("新檔案出現時吐出 snapshot")
    func detectsNewFile() async throws {
        let root = try makeRoot()
        let source = HookFileSource(root: root)
        source.start()
        defer { source.stop() }

        Task { try? self.write("live1", .waiting, to: root) }
        let got = await collect(source) { $0.contains { $0.sessionID == "live1" } }
        #expect(got.contains { $0.sessionID == "live1" && $0.mainActivity == .waiting })
    }

    @Test("既有檔案被覆寫時吐出新 snapshot")
    func detectsModification() async throws {
        let root = try makeRoot()
        try write("live2", .working, to: root)
        let source = HookFileSource(root: root)
        source.start()
        defer { source.stop() }

        Task { try? self.write("live2", .error, to: root) }
        let got = await collect(source) { $0.contains { $0.mainActivity == .error } }
        #expect(got.contains { $0.sessionID == "live2" && $0.mainActivity == .error })
    }

    @Test("多個 session 併發寫入全部都收到")
    func detectsManySessions() async throws {
        let root = try makeRoot()
        let source = HookFileSource(root: root)
        source.start()
        defer { source.stop() }

        Task {
            for i in 0..<10 { try? self.write("many\(i)", .working, to: root) }
        }
        let got = await collect(source, until: { Set($0.map(\.sessionID)).count >= 10 }, timeout: 10)
        #expect(Set(got.map(\.sessionID)).count >= 10)
    }

    @Test("stop 之後不再吐事件")
    func stopEndsStream() async throws {
        let root = try makeRoot()
        let source = HookFileSource(root: root)
        source.start()
        source.stop()
        try write("after-stop", .working, to: root)

        // 用有界的 `collect`，不要直接 `for await`。
        //
        // 前一版是 `for await s in source.snapshots { got.append(s) }`，靠
        // 「stop() 會 finish() continuation，所以迭代立刻結束」來終止 ——
        // 但那正是這條測試的**被測物**。實測：把 stop() 裡的 finish() 拿掉，
        // 這條測試不是變紅而是掛住（120s 強殺）。
        // 拿被測物當迴圈終止條件，等於測試在假設結論成立。
        let got = await collect(source, until: { !$0.isEmpty }, timeout: 1)
        #expect(!got.contains { $0.sessionID == "after-stop" })
    }

    @Test("stop 是終局：再 start 也不會復活（釘死契約，不是缺陷）")
    func stopIsTerminal() async throws {
        let root = try makeRoot()
        let source = HookFileSource(root: root)
        source.start()
        source.stop()
        source.start()                      // 嘗試復活
        defer { source.stop() }

        Task { try? self.write("revived", .working, to: root) }
        let got = await collect(source, until: { !$0.isEmpty }, timeout: 1)
        #expect(got.isEmpty, """
            契約：`snapshots` 是 init 建立的單一 AsyncStream，stop() 會 finish() 它，
            之後 start() 不會有任何事件。生產上只在 applicationWillTerminate 呼叫一次，
            所以這是刻意的契約。若這條變紅，表示有人讓 start() 可以復活 —— 那是好事，
            但 AppDelegate 的生命週期假設要一起改，別讓它靜默地變成兩套語意。
            """)
    }

    @Test("重複 start / stop 不 crash")
    func repeatedStartStop() throws {
        let source = HookFileSource(root: try makeRoot())
        source.start(); source.start()
        source.stop();  source.stop()
    }

    @Test("root 不存在時 start 會自動建立目錄")
    func startCreatesRoot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-fse-\(UUID().uuidString)/deep/sessions")
        let source = HookFileSource(root: root)
        source.start()
        defer { source.stop() }
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
