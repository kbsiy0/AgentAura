import Foundation
@testable import AgentAuraApp

// T24：`BundleRecycling` 現在是 `Sources/AgentAuraApp/AppEnvironment.swift` 的真型別
// （同 `AppTerminating`／`LoginItemControlling` 的既有慣例）——`FakeRecycler` 直接對生產
// protocol 實作，才能在 `Uninstaller` 的測試裡與真 `WorkspaceRecycler` 互換。
// **不得真的呼叫 `NSWorkspace.recycle`**——這個 fake 完全不持有 `NSWorkspace`，
// 結構上就不可能碰到它。

@MainActor
final class FakeRecycler: BundleRecycling {
    private(set) var recycledURLs: [URL] = []
    var completionError: Error?
    /// 預設同步呼叫 completion（多數測試不關心非同步時序）；設成 `false` 時
    /// completion 要靠測試自己呼叫 `fireCompletion()`——`recycleWaitsForCompletionBeforeTerminating`
    /// 用它證明 `terminate()` 真的等 completion，不是發出去就跑。
    var callsCompletionSynchronously = true
    private var pendingCompletion: ((Error?) -> Void)?

    func recycle(_ url: URL, completion: @escaping (Error?) -> Void) {
        recycledURLs.append(url)
        if callsCompletionSynchronously {
            completion(completionError)
        } else {
            pendingCompletion = completion
        }
    }

    func fireCompletion() {
        pendingCompletion?(completionError)
        pendingCompletion = nil
    }
}
