import Foundation

/// 狀態來源的抽象。
///
/// 目前唯一實作是 `HookFileSource`（方案 1）。方案 3（zero-config 觀測
/// `~/.claude/projects/**/*.jsonl`）未來接在這個縫上，不需改動核心邏輯。
public protocol EventSource: AnyObject, Sendable {
    /// app 啟動時掃出現況。靜止態（waiting/done/error）天生就在檔案裡。
    func bootstrap() -> [SessionSnapshot]
    /// 來源有變動時吐出受影響的 snapshot。
    var snapshots: AsyncStream<SessionSnapshot> { get }
    func start()
    func stop()
}
