import Foundation

/// T10b（team-lead 診斷）：全套件唯一的 spawn 序列化點。
///
/// **背景**：swift-testing 預設跨 suite 並行；一旦套件裡會真的 fork/exec `aura-hook` 的測試
/// 變多（T08／T10b 之後），機器會被自己的測試灌滿，量到的是機器負載不是產品——實測
/// `AuraHookCLITests` 的「單次呼叫中位數 < 50ms」量到 204ms，`InstallerPathScopeTests`
/// 等測試偶發把正常路徑誤判成 `.hookUnconfirmed`（`.serialized` 只序列化同一個 suite
/// 內部，擋不住跨 suite 並行）。任何直接 `Process()` 或透過 `Installer.connect()`／
/// `replaceExternalMount()` 真的會 spawn 一個行程的測試碼，都必須經過
/// `SpawnGate.shared.run { … }`。
///
/// **不是單靠 actor 隱式序列化，是手刻的非重入鎖**：`body` 內部若有 `await`
/// （例如某些測試在觸發動作後還要 `await wait(upTo:...)` 輪詢結果），Swift actor 在那個
/// 懸掛點是可重入的——另一個呼叫端這時呼叫 `SpawnGate.shared.run` 一樣會被排進同一個
/// actor 的佇列去執行，並不會真的排隊等待。只靠「呼叫 actor 方法」本身序列化不住跨
/// `await` 的臨界區。這裡改成顯式 acquire／release，鎖的存活跨越 `body` 內任何數量的
/// `await`，正確性不依賴 actor reentrancy 的細節。
actor SpawnGate {
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
        // 鎖直接轉交給佇列裡下一個等待者，locked 全程維持 true——不留「已釋放但還沒有人
        // 拿到」的空窗，否則兩個同時被喚醒的等待者可能都以為自己拿到了鎖。
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
