import Foundation

/// 現存 session 與「已結束但未確認」的尾巴。
///
/// 尾巴的存在理由：整夜跑 pipeline、terminal 自己收掉的情境下，若 session 一結束就消失，
/// 使用者早上回來看到的是暗燈，產品最大價值被抵銷。
public struct SessionRegistry: Sendable {
    public private(set) var states: [String: SessionState] = [:]
    public private(set) var acknowledged: Set<String> = []

    public init() {}

    public func isAcknowledged(_ id: String) -> Bool { acknowledged.contains(id) }

    public mutating func upsert(_ s: SessionState) {
        // 新活動代表有新結果要被看過 —— 撤銷先前的確認。
        if let old = states[s.id], old.activity != s.activity || old.updatedAt < s.updatedAt {
            acknowledged.remove(s.id)
        }
        states[s.id] = s
        if s.liveness == .ended, acknowledged.contains(s.id) {
            // 已看過又已結束 → 直接清掉。**兩個表都要清。**
            //
            // 只清 `states` 會讓 id 永遠留在 `acknowledged` 裡：`refreshLiveness`
            // 只走訪 `states.keys`，所以它再也不會被 `remove(_:)` 掃到。之後同一個
            // id（`claude --resume` 會沿用）若第一個被觀察到的 snapshot 已是
            // `.ended`，這一行會**再次**把它刪掉 —— 而且救不回來，因為上面撤銷
            // 確認的分支需要 `states[s.id]` 非 nil。使用者永遠看不到那個結果。
            remove(s.id)
        }
    }

    /// 移除一個 session。
    ///
    /// 用於「狀態檔已不存在」的情況：檔案是狀態的唯一真實來源，沒有檔案就沒有 session。
    /// 若該 session 其實還活著，下一個 hook 事件會把它重建回來。
    public mutating func remove(_ id: String) {
        states[id] = nil
        acknowledged.remove(id)
    }

    /// 面板開啟：所有未確認一律標為已確認（不論是否捲動到、是否可見）。
    /// 回傳「已結束且已確認」的 id —— 呼叫端據此刪除狀態檔。
    public mutating func acknowledgeAll() -> [String] {
        acknowledged.formUnion(states.keys)
        let removable = states.values.filter { $0.liveness == .ended }.map(\.id)
        for id in removable { remove(id) }      // 兩個表都清 —— 呼叫端接著會刪檔
        return removable
    }

    /// 參與 icon 聚合的 session：活著的，加上已結束但仍有未確認**結果**的。
    ///
    /// `waiting` 刻意不算結果（§2.4.1）。實測：使用者按 Deny 不產生任何 hook 事件，
    /// session 的最後事件停在 `PermissionRequest`，之後直接 `SessionEnd`。
    /// 若 `waiting` 也能進尾巴，一個已結束、使用者早就回答過的 session 會讓 icon
    /// 一直亮橘燈說「有人在等你」—— 本產品最不該犯的錯。
    public var visible: [SessionState] {
        states.values.filter { s in
            if s.liveness != .ended { return true }
            let isResult = s.activity == .done || s.activity == .error
            return isResult && !acknowledged.contains(s.id)
        }
    }
}
