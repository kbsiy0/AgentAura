import Foundation
@testable import AgentAuraApp
import AuraCore

// T07：`Verification`／`HookVerificationStoring` 現在是 `Sources/AgentAuraApp/HookVerificationStore.swift`
// 的真型別（`Verification` 來自 `AuraCore`，5 個 case），T01 的本地重製已刪除——
// `FakeVerificationStore` 直接對生產 protocol 實作，才能在 T08 的 composition-root
// gate（`productionUsesRealVerificationStore` 之類）裡與真 store 互換。

/// 可設定憑證相符／不符／讀取失敗（spec §6.1：「憑證相符／不符／讀取丟錯」）。
/// 「不符」與「讀取失敗」都退化成非 `.verified` 的值——R2 的規則是 `unknown` 不得為
/// 終態，但這裡先給呼叫端足夠的區分度（`mismatched` 用 `.blocked`、`unreadable` 用
/// `.unknown`），T07 可依真實 store 的語意調整。
@MainActor
final class FakeVerificationStore: HookVerificationStoring {
    enum Behavior { case matches, mismatched, unreadable }

    var behavior: Behavior
    private(set) var verificationCallCount = 0
    private(set) var requestedStamps: [String?] = []

    init(behavior: Behavior) { self.behavior = behavior }

    func verification(for stamp: String?) -> Verification {
        verificationCallCount += 1
        requestedStamps.append(stamp)
        switch behavior {
        case .matches: return .verified
        case .mismatched: return .blocked
        case .unreadable: return .unknown
        }
    }
}
