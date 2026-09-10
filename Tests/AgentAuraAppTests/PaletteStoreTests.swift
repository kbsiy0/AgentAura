import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// spec `2026-09-09-panel-legend-palette-design.md` §6：`storeLoadsDefaultWhenEmpty`、
/// `storeRoundTripsThroughRealDefaults`、`storeResetRemovesKeys`、`storeToleratesGarbageDefaults`、
/// `storeNotifiesBeforePersisting`、`storeKeyBudget`。
///
/// 固定 suite 名（spec §6）＋ `.serialized` ＋每測 `removePersistentDomain`：共用同一個
/// domain、序列化跑、每測前清空——不會互相汙染，也不會碰到生產 domain `io.agentaura.app`。
@Suite("PaletteStore", .serialized)
struct PaletteStoreTests {
    static let suiteName = "io.agentaura.tests.palette"

    func freshDefaults() throws -> UserDefaults {
        let d = try #require(UserDefaults(suiteName: Self.suiteName), "建不出 suite \(Self.suiteName)")
        d.removePersistentDomain(forName: Self.suiteName)
        return d
    }

    @MainActor
    @Test("空 defaults 載入應為預設 palette")
    func storeLoadsDefaultWhenEmpty() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = PaletteStore(defaults: defaults)
        #expect(store.palette == .default, "空 defaults 應載入預設 palette，實際 \(store.palette)")
    }

    @MainActor
    @Test("set 之後，新建第二個 store（同 suite）應讀到同色（round trip）")
    func storeRoundTripsThroughRealDefaults() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = PaletteStore(defaults: defaults)
        // 8-bit 精確的顏色（= #9c0de0）：round trip 經過 hex 量化，非 8-bit 值會在正確實作下也對不上（review-t01 B1）。
        let wild = RGBA(r: 156.0 / 255, g: 13.0 / 255, b: 224.0 / 255, a: 1)
        store.set(wild, for: .waiting)
        #expect(defaults.string(forKey: "AgentAuraColor.waiting") == "#9c0de0", """
            寫入端 key 名應為 AgentAuraColor.waiting、值為小寫 #rrggbb，實際 \(String(describing: defaults.string(forKey: "AgentAuraColor.waiting")))
            """)

        let secondStore = PaletteStore(defaults: defaults)
        #expect(secondStore.palette[.waiting] == wild, """
            set(.waiting) 之後新建的第二個 store（同 suite）應讀到同色 \(wild)，實際 \(secondStore.palette[.waiting])
            """)
    }

    @MainActor
    @Test("reset 移除四個 key")
    func storeResetRemovesKeys() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        // 前提：先塞四個 key，才測得出「reset 有沒有真的清掉」。
        for activity in Activity.allCases where activity != .idle {
            defaults.set("#123456", forKey: "AgentAuraColor.\(activity.rawValue)")
        }

        let store = PaletteStore(defaults: defaults)
        store.reset()

        for activity in Activity.allCases where activity != .idle {
            let key = "AgentAuraColor.\(activity.rawValue)"
            #expect(defaults.object(forKey: key) == nil, """
                reset 後 \(key) 應被移除，實際 \(String(describing: defaults.object(forKey: key)))
                """)
        }
        let hits = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("AgentAuraColor.") }.count
        #expect(hits == 0, "reset 後前綴命中應為 0，實際 \(hits)")
    }

    @MainActor
    @Test("垃圾 defaults（字串／Int／Data）不 crash，載入為預設（對抗式）")
    func storeToleratesGarbageDefaults() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        defaults.set("not-a-hex-at-all", forKey: "AgentAuraColor.error")
        defaults.set(42, forKey: "AgentAuraColor.waiting")
        defaults.set(Data([0x01, 0x02]), forKey: "AgentAuraColor.working")
        defaults.set("", forKey: "AgentAuraColor.done")

        let store = PaletteStore(defaults: defaults)
        #expect(store.palette == .default, "垃圾 defaults 應落回預設、不 crash，實際 \(store.palette)")
    }

    @MainActor
    @Test("onChange 在 persist 之前呼叫（defaults 仍是舊值）")
    func storeNotifiesBeforePersisting() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = PaletteStore(defaults: defaults)

        var observed: String??
        store.onChange = { observed = defaults.string(forKey: "AgentAuraColor.waiting") }
        store.set(RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1), for: .waiting)

        let captured = try #require(observed, "onChange 應該在 set() 之後被呼叫，目前完全沒被呼叫過")
        #expect(captured == nil, """
            onChange 觸發當下 defaults 應該還沒被寫入（先通知再落盤），實際已經是 \(String(describing: captured))
            """)
    }

    @MainActor
    @Test("改四色後 UserDefaults 前綴命中 ≤ 4（R9 key 預算）")
    func storeKeyBudget() throws {
        let defaults = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = PaletteStore(defaults: defaults)
        for activity in Activity.allCases where activity != .idle {
            store.set(RGBA(r: 0.1, g: 0.2, b: 0.3, a: 1), for: activity)
        }
        let hits = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("AgentAuraColor.") }.count
        #expect(hits <= 4, "前綴命中應 ≤ 4，實際 \(hits)")
    }
}
