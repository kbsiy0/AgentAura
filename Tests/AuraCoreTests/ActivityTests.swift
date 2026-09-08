import Testing
@testable import AuraCore

@Suite("Activity 優先序（D1）")
struct ActivityTests {

    @Test("優先序為 error > waiting > working > done > idle")
    func priorityOrder() {
        #expect(Activity.error > Activity.waiting)
        #expect(Activity.waiting > Activity.working)
        #expect(Activity.working > Activity.done)
        #expect(Activity.done > Activity.idle)
    }

    @Test("max 保住 waiting 不被 working 蓋掉（§2.5 的基石）")
    func maxPreservesWaiting() {
        #expect(max(Activity.waiting, Activity.working) == .waiting)
        #expect(max(Activity.working, Activity.waiting) == .waiting)
        #expect(max(Activity.error, Activity.waiting) == .error)
    }

    @Test("rawValue 是可讀字串，供狀態檔 JSON 使用")
    func rawValuesAreStrings() {
        #expect(Activity.waiting.rawValue == "waiting")
        #expect(Activity(rawValue: "error") == .error)
        #expect(Activity(rawValue: "bogus") == nil)
    }

    @Test("priority 值兩兩不同且涵蓋全部 case")
    func prioritiesAreDistinct() {
        let ps = Activity.allCases.map(\.priority)
        #expect(Set(ps).count == Activity.allCases.count)
        #expect(ps.sorted() == [0, 1, 2, 3, 4])
    }

    @Test("isQuiescent 僅 waiting / done / error 為真")
    func quiescence() {
        #expect(Activity.waiting.isQuiescent)
        #expect(Activity.done.isQuiescent)
        #expect(Activity.error.isQuiescent)
        #expect(!Activity.working.isQuiescent)
        #expect(!Activity.idle.isQuiescent)
    }
}
