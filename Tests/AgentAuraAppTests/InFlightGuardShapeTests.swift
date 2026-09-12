import Testing
import Foundation

/// T01 必辦⑤（前半）的自我測試：同時只有一個背景工作在跑，第二次呼叫被跳過，
/// 完成後 `inFlight` 變回 `nil`。**這條合理地是 GREEN**：驗的是 guard 形狀本身，
/// 不是還沒寫的 `HookVerificationStore`（T07）。
@MainActor
@Suite("InFlightGuardShape 自我驗證")
struct InFlightGuardShapeTests {

    /// 有界輪詢——直接 `while` 在 mutation 下會變掛住而不是變紅（沿用
    /// `CompositionSmokeTests.wait(upTo:until:)` 的形狀）。
    func wait(upTo seconds: TimeInterval, until cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test("已經有一個在跑時，第二次 begin 被跳過；完成後 inFlight 變 nil")
    func onlyOneInFlightAtATime() async throws {
        let guardShape = InFlightGuardShape()
        let gate = AsyncGate()

        let started1 = guardShape.begin { await gate.wait() }
        #expect(started1 == true)
        #expect(guardShape.inFlight != nil, "inFlight 應非 nil —— 這正好就是 Verification.inFlight 的訊號（R2）")

        let started2 = guardShape.begin { /* 不應該真的跑到這裡 */ }
        #expect(started2 == false, "已經有一個在跑，第二次呼叫必須被跳過")
        #expect(guardShape.skippedCount == 1)
        #expect(guardShape.startedCount == 1, "跳過的那次不算啟動")

        await gate.release()
        await wait(upTo: 5) { guardShape.inFlight == nil }
        #expect(guardShape.inFlight == nil, "背景工作完成後，inFlight 必須變回 nil")
    }

    @Test("第一段工作完成後，可以再啟動下一段（不是一次性用完的 guard）")
    func canStartAgainAfterPreviousCompletes() async throws {
        let guardShape = InFlightGuardShape()
        let firstGate = AsyncGate()
        _ = guardShape.begin { await firstGate.wait() }
        await firstGate.release()
        await wait(upTo: 5) { guardShape.inFlight == nil }

        let secondGate = AsyncGate()
        let started = guardShape.begin { await secondGate.wait() }
        #expect(started == true, "前一段已完成，應能重新啟動下一段")
        #expect(guardShape.startedCount == 2)
        await secondGate.release()
        await wait(upTo: 5) { guardShape.inFlight == nil }
    }
}
