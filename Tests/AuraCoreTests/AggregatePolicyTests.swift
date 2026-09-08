import Testing
import Foundation
@testable import AuraCore

@Suite("AggregatePolicy 優先序（D1）")
struct AggregatePolicyTests {

    let policy = PriorityAggregatePolicy()

    func state(_ id: String, _ a: Activity, live: Bool = true) -> SessionState {
        SessionState(id: id, projectName: id, projectPath: nil,
                     permissionMode: nil, effort: nil, model: nil,
                     activity: a, mainActivity: a, subActivity: nil,
                     currentTool: nil, subagentTool: nil, toolDurationMs: nil,
                     turnStartedAt: nil, subagents: [:], toolFailures: 0,
                     lastMessage: nil, errorType: nil, toolError: nil,
                     liveness: live ? .alive(pid: 1) : .ended,
                     updatedAt: Date(timeIntervalSince1970: 1_788_628_000))
    }

    @Test("2 個 working + 1 個 error → error（使用者原始舉例）")
    func twoWorkingOneErrorIsError() {
        let r = policy.aggregate([state("a", .working), state("b", .working), state("c", .error)])
        #expect(r.activity == .error)
    }

    @Test("順序無關 —— 任何排列結果都相同")
    func orderIndependent() {
        let s = [state("a", .working), state("b", .error), state("c", .waiting), state("d", .done)]
        let expected = policy.aggregate(s).activity
        #expect(expected == .error)
        for _ in 0..<40 {
            #expect(policy.aggregate(s.shuffled()).activity == expected)
        }
    }

    @Test("error 勝過 waiting（D1：紅色絕對優先）")
    func errorBeatsWaiting() {
        #expect(policy.aggregate([state("a", .waiting), state("b", .error)]).activity == .error)
    }

    @Test("waiting 勝過 working")
    func waitingBeatsWorking() {
        #expect(policy.aggregate([state("a", .working), state("b", .waiting)]).activity == .waiting)
    }

    @Test("working 勝過 done")
    func workingBeatsDone() {
        #expect(policy.aggregate([state("a", .done), state("b", .working)]).activity == .working)
    }

    @Test("done 勝過 idle")
    func doneBeatsIdle() {
        #expect(policy.aggregate([state("a", .idle), state("b", .done)]).activity == .done)
    }

    @Test("空清單 → idle")
    func emptyIsIdle() {
        let r = policy.aggregate([])
        #expect(r.activity == .idle)
        #expect(r.liveCount == 0)
        #expect(r.attentionCount == 0)
    }

    @Test("counts 逐 activity 計數正確")
    func countsPerActivity() {
        let r = policy.aggregate([
            state("a", .working), state("b", .working), state("c", .working),
            state("d", .waiting), state("e", .error), state("f", .done),
        ])
        #expect(r.counts[.working] == 3)
        #expect(r.counts[.waiting] == 1)
        #expect(r.counts[.error] == 1)
        #expect(r.counts[.done] == 1)
        #expect(r.counts[.idle] == nil)
    }

    @Test("liveCount 只算活著的")
    func liveCountExcludesEnded() {
        let r = policy.aggregate([
            state("a", .working), state("b", .waiting),
            state("c", .error, live: false), state("d", .done, live: false),
        ])
        #expect(r.liveCount == 2)
        #expect(r.counts.values.reduce(0, +) == 4, "counts 涵蓋全部傳入的 session")
    }

    @Test("attentionCount = error + waiting，done 不計入")
    func attentionCountExcludesDone() {
        let r = policy.aggregate([
            state("a", .error), state("b", .waiting), state("c", .waiting),
            state("d", .done), state("e", .working),
        ])
        #expect(r.attentionCount == 3, "done 是「可以去看了」，不是「你被擋著」")
    }

    @Test("50 個 session 的聚合是 O(n) 且結果穩定")
    func fiftySessions() {
        var s = (0..<49).map { state("s\($0)", .working) }
        s.append(state("boom", .error))
        #expect(policy.aggregate(s).activity == .error)
        #expect(policy.aggregate(s).liveCount == 50)
    }
}
