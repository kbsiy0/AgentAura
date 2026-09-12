import Foundation
@testable import AgentAuraApp

// T07：`LoginItemControlling`／`LoginItemError` 現在是 `Sources/AgentAuraApp/LoginItem.swift`
// 的真型別，T01 的本地重製已刪除——`FakeLoginItem` 直接對生產 protocol 實作，才能在
// composition-root gate（T08 的 `productionUsesRealLoginItem`）裡與真 `LoginItem` 互換。

/// `isSupported == false`、`set` 丟 `.requiresApproval`、`isEnabled` 與剛設定的值
/// **不一致**（模擬需核准時系統沒有真的打開）——spec §6.1 明訂的刁鑽組合。
@MainActor
final class FakeLoginItem: LoginItemControlling {
    enum SetBehavior { case succeeds, requiresApprovalAndDoesNotActuallyEnable }

    var isSupported: Bool
    private(set) var isEnabled: Bool
    var setBehavior: SetBehavior
    private(set) var setCallCount = 0

    init(isSupported: Bool = true, initiallyEnabled: Bool = false, setBehavior: SetBehavior = .succeeds) {
        self.isSupported = isSupported
        self.isEnabled = initiallyEnabled
        self.setBehavior = setBehavior
    }

    func set(_ on: Bool) throws {
        setCallCount += 1
        switch setBehavior {
        case .succeeds:
            isEnabled = on
        case .requiresApprovalAndDoesNotActuallyEnable:
            // isEnabled 刻意不變——呼叫端若不檢查 throw 就假設成功，會顯示
            // 與系統實際狀態不一致的開關（spec §4.2：「開關彈回實際值」要靠這個測出來）。
            throw LoginItemError.requiresApproval
        }
    }
}
