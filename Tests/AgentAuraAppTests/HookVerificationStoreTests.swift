import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// spec §3.1／§6.3：`HookVerificationStore`（@MainActor ＋ 注入 `UserDefaults`，比照 `PaletteStore`）。
/// 三個互斥鍵、`inFlight` 合流 guard（T01 必辦⑤）。固定 suite 名 ＋ `.serialized` ＋
/// 每測 `removePersistentDomain`（同 `PaletteStoreTests` 的隔離手法）。
@Suite("HookVerificationStore", .serialized)
struct HookVerificationStoreTests {
    static let suiteName = "io.agentaura.tests.hookverification"

    func freshDefaults() throws -> UserDefaults {
        let d = try #require(UserDefaults(suiteName: Self.suiteName), "建不出 suite \(Self.suiteName)")
        d.removePersistentDomain(forName: Self.suiteName)
        return d
    }

    /// 有界輪詢（沿用 `CompositionSmokeTests.wait`／`InFlightGuardShapeTests.wait` 的形狀）：
    /// 直接 `while` 在 mutation 下會變掛住而不是變紅。
    @MainActor
    func wait(upTo seconds: TimeInterval, until cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @MainActor
    @Test("stamp 為 nil → .unknown；空 defaults 對任何 stamp 都 .unknown")
    func unknownWhenNoStampOrNoRecord() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = HookVerificationStore(defaults: defaults)
        #expect(store.verification(for: nil) == .unknown)
        #expect(store.verification(for: "1:1:1.0") == .unknown)
    }

    @MainActor
    @Test("writeVerified 之後，同一顆 stamp → .verified；不同 stamp 仍 .unknown")
    func verifiedMatchesExactStamp() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = HookVerificationStore(defaults: defaults)
        store.writeVerified("1:1:1000.0")
        #expect(store.verification(for: "1:1:1000.0") == .verified)
        #expect(store.verification(for: "1:1:1000.1") == .unknown, "mtime 奈秒不同的 stamp 不該被當成同一份，實際回報 .verified 會是「.verified 但從沒驗過這一份」（T01 必辦④防的正是這件事）")
    }

    @MainActor
    @Test("writeBlocked／writeUnconfirmed 各自對應正確的 Verification")
    func blockedAndUnconfirmedMatchTheirStamp() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = HookVerificationStore(defaults: defaults)
        store.writeBlocked("2:2:2000.0")
        #expect(store.verification(for: "2:2:2000.0") == .blocked)
        store.writeUnconfirmed("3:3:3000.0")
        #expect(store.verification(for: "3:3:3000.0") == .unconfirmed)
    }

    @MainActor
    @Test("三個鍵互斥：寫一個要清掉另兩個")
    func writingOneKeyClearsTheOtherTwo() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = HookVerificationStore(defaults: defaults)
        store.writeBlocked("x:x:1.0")
        #expect(store.verification(for: "x:x:1.0") == .blocked)

        store.writeVerified("x:x:1.0")
        #expect(store.verification(for: "x:x:1.0") == .verified, "寫 verified 之後同一顆 stamp 應變成 .verified")

        store.writeUnconfirmed("y:y:2.0")
        #expect(store.verification(for: "x:x:1.0") == .unknown, "寫 unconfirmed 應清掉先前的 verified 鍵——三鍵互斥")
        #expect(store.verification(for: "y:y:2.0") == .unconfirmed)
    }

    @MainActor
    @Test("inFlight 優先於任何鍵比對：即使 stamp 精準吻合 verified 鍵，還在跑時仍回 .inFlight")
    func inFlightTakesPriorityOverStoredKeys() async throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = HookVerificationStore(defaults: defaults)
        store.writeVerified("z:z:9.0")
        #expect(store.verification(for: "z:z:9.0") == .verified, "前提：沒有背景工作在跑時應照鍵值回報")

        let gate = AsyncGate()
        let started = store.beginVerification { await gate.wait() }
        #expect(started == true)
        #expect(store.verification(for: "z:z:9.0") == .inFlight, """
            inFlight != nil 時「檢查中…」必須是真話——即使 stamp 精準吻合已驗證的鍵，也不能搶答，
            否則序列化與文案誠實性這兩件事就不再是同一個機制（R2）
            """)

        await gate.release()
        await wait(upTo: 5) { store.inFlight == nil }
        #expect(store.verification(for: "z:z:9.0") == .verified, "背景工作結束後應恢復照鍵值回報")
    }

    @MainActor
    @Test("合流 guard：已經有一個在跑時，第二次 beginVerification 被跳過")
    func onlyOneVerificationInFlightAtATime() async throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = HookVerificationStore(defaults: defaults)
        let gate = AsyncGate()

        var secondRan = false
        let started1 = store.beginVerification { await gate.wait() }
        #expect(started1 == true)
        let started2 = store.beginVerification { secondRan = true }
        #expect(started2 == false, "已經有一個在跑，第二次呼叫必須被跳過——否則兩個 exec 併發、兩邊都寫憑證")

        await gate.release()
        await wait(upTo: 5) { store.inFlight == nil }
        #expect(!secondRan, "被跳過的那次工作不該真的執行")

        let started3 = store.beginVerification { }
        #expect(started3 == true, "前一段已完成，應能重新啟動下一段——不是一次性用完的 guard")
        await wait(upTo: 5) { store.inFlight == nil }
    }

    @MainActor
    @Test("注入的 UserDefaults 是真的持久化：同 suite 第二個 store 讀到同一份憑證（round trip）")
    func roundTripsThroughRealDefaults() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store1 = HookVerificationStore(defaults: defaults)
        store1.writeVerified("r:r:1.0")

        let store2 = HookVerificationStore(defaults: defaults)
        #expect(store2.verification(for: "r:r:1.0") == .verified, "第二個 store（同 suite）應讀到第一個寫入的憑證")
    }
}
