import Foundation
@testable import AgentAuraApp

// T08：`AppTerminating` 現在是 `Sources/AgentAuraApp/AppEnvironment.swift` 的真型別
// （T01 的本地宣告已刪除）——`FakeTerminator` 直接對生產 protocol 實作，才能在
// composition-root gate（G5 的 `.quit`）裡與真 `RealTerminator` 互換。
// **不得真的呼叫 `NSApp.terminate`**——這個 fake 完全不持有 `NSApplication`，
// 結構上就不可能碰到它。

@MainActor
final class FakeTerminator: AppTerminating {
    private(set) var terminateCallCount = 0
    /// T24：`.uninstall` 的最後一步呼叫這個，不是 `terminate()`（見 `Uninstaller`）。
    private(set) var terminateImmediatelyCallCount = 0
    func terminate() { terminateCallCount += 1 }
    func terminateImmediately() { terminateImmediatelyCallCount += 1 }
}
