import Foundation

/// 狀態來源的抽象。
///
/// 目前唯一實作是 `HookFileSource`（方案 1）。方案 3（zero-config 觀測
/// `~/.claude/projects/**/*.jsonl`）未來接在這個縫上，不需改動核心邏輯。
public protocol EventSource: AnyObject, Sendable {
    /// app 啟動時掃出現況。靜止態（waiting/done/error）天生就在檔案裡。
    func bootstrap() -> [SessionSnapshot]
    /// 來源有變動時吐出**一批**受影響的 snapshot——同一次底層事件回呼裡的所有變動
    /// 合成一批（絕不吐空陣列），讓消費端可以「整批 ingest 完才通知一次」（A3，
    /// /simplify 波次1，eff#1）：一個 FSEvents 批次有 K 個檔案變動，過去是跑 K 次
    /// 完整下游管線，只有最後一次有意義。
    var snapshots: AsyncStream<[SessionSnapshot]> { get }
    func start()
    func stop()
}
