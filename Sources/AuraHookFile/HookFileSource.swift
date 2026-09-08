import Foundation
import AuraCore

/// 用 FSEvents 監看 `~/.agentaura/sessions`，把變動的檔案讀成 `SessionSnapshot`。
public final class HookFileSource: EventSource, @unchecked Sendable {

    private let root: URL
    private let latency: TimeInterval
    private let queue = DispatchQueue(label: "io.agentaura.fsevents")
    private var stream: FSEventStreamRef?
    private var continuation: AsyncStream<SessionSnapshot>.Continuation?
    private let lock = NSLock()

    public let snapshots: AsyncStream<SessionSnapshot>

    public init(root: URL = SnapshotIO.defaultRoot, latency: TimeInterval = 0.1) {
        self.root = root
        self.latency = latency
        var cont: AsyncStream<SessionSnapshot>.Continuation!
        self.snapshots = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    deinit { stop() }

    public func bootstrap() -> [SessionSnapshot] {
        SnapshotIO.allSessionIDs(root: root)
            .compactMap { SnapshotIO.read(sessionID: $0, root: root) }
    }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard stream == nil else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let source = Unmanaged<HookFileSource>.fromOpaque(info).takeUnretainedValue()
            // 未設 kFSEventStreamCreateFlagUseCFTypes，故 eventPaths 是 char **。
            // 用 assumingMemoryBound 而非 unsafeBitCast —— 後者從 raw pointer 硬轉型別，
            // 編譯器會警告可能造成 undefined behavior（實測 Swift 6.3.3 確實會警告）。
            let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            var changed: Set<String> = []
            for i in 0..<count {
                let name = (String(cString: paths[i]) as NSString).lastPathComponent
                guard name.hasSuffix(".json") else { continue }
                changed.insert(String(name.dropLast(5)))
            }
            source.emit(sessionIDs: changed)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

        guard let s = FSEventStreamCreate(
            nil, callback, &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, flags)
        else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    /// **stop() 是終局。** `snapshots` 是 `init` 建立的單一 AsyncStream，
    /// 這裡 `finish()` 之後再 `start()` 也不會有任何事件 —— source 已經聾了。
    /// 生產上只在 `applicationWillTerminate` 呼叫一次，故這是刻意的契約；
    /// `stopIsTerminal` 測試把它釘死，未來若有人加「休眠後重啟」會立刻紅。
    public func stop() {
        lock.lock(); defer { lock.unlock() }
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        continuation?.finish()
        continuation = nil
    }

    /// 讀不到（半截 JSON、剛被刪）就跳過 —— 呼叫端保留上次已知狀態。
    private func emit(sessionIDs: Set<String>) {
        for id in sessionIDs {
            guard SnapshotIO.isSafeSessionID(id),
                  let snap = SnapshotIO.read(sessionID: id, root: root) else { continue }
            continuation?.yield(snap)
        }
    }
}
