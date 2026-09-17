import Foundation

/// T10b（team-lead 診斷）：全套件唯一的 spawn 序列化點——理由與
/// `Tests/AuraCoreTests/Support/SpawnGate.swift` 完全一致（AgentAuraAppTests 不依賴
/// AuraCoreTests target，不能直接沿用，本檔是同一個手法的獨立小型複製）。
///
/// **`@MainActor` 而不是普通 `actor`**：這裡的呼叫端全是 `@MainActor @Suite`（`AppDelegate`
/// 系列測試），真正的 spawn 又藏在 `AppDelegate` 內部（`applicationDidFinishLaunching` 的
/// 背景驗證、`onAction(.connect)` 等）——那些呼叫本身就要求在 MainActor 上下文執行。
/// 若改用一般 `actor`，`body` 內呼叫這些 MainActor API 會需要額外跳轉隔離域，徒增複雜度
/// 又沒有實際好處（呼叫端與這個閘門本來就同一個執行緒序列化）。鎖本身仍是手刻的
/// 顯式 acquire／release（理由同 AuraCoreTests 那份文件——`body` 內的 `await` 會讓
/// MainActor 在懸掛點變成可重入，只靠隔離域本身序列化不住跨 `await` 的臨界區）。
@MainActor
final class SpawnGate {
    static let shared = SpawnGate()

    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        guard !waiters.isEmpty else {
            locked = false
            return
        }
        waiters.removeFirst().resume()
    }

    /// 序列化任意一段（可能內含 `await` 的）工作——同一時間全套件只有一個 body 在跑。
    ///
    /// `T: Sendable`：`run` 是 actor 方法，回傳值要跨 actor 邊界送回呼叫端。
    /// **Swift 6.1.2 要求它是 Sendable，6.3 的 region-based isolation 推得出來所以不要求**
    /// ——本機（6.3.3）編得過，CI runner（6.1.2）編不過。所有呼叫點回傳的都是 `Void`
    /// 或簡單值，加上這個約束不影響任何一處，卻讓程式碼在兩個版本上都成立。
    func run<T: Sendable>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }
}
