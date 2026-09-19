import Testing
import Foundation
@testable import AuraCore   // E15（/simplify 波次2）：StubLiveness 收成 internal 之後需要 @testable

/// spec `2026-09-09-panel-legend-palette-design.md` §6：`customizableOrder`、
/// `legendItemsFollowOrderAndLabelsTotal`、`withChangesOnlyThatField`、`panelModelCarriesPalette`。
@Suite("LegendModel／PanelModel")
struct LegendModelTests {

    /// 五色彼此差異極大——不能用 `.default`，否則「接錯欄位」的 mutation 會被吃掉。
    static let distinctPalette = IconPalette(
        idle:    RGBA(r: 0.12, g: 0.34, b: 0.56, a: 0.5),
        working: RGBA(r: 0.91, g: 0.11, b: 0.22, a: 1),
        done:    RGBA(r: 0.05, g: 0.88, b: 0.15, a: 1),
        waiting: RGBA(r: 0.95, g: 0.65, b: 0.05, a: 1),
        error:   RGBA(r: 0.10, g: 0.20, b: 0.95, a: 1))

    @Test("customizable 順序釘死為 [.error, .waiting, .working, .done]，且不含 idle")
    func customizableOrder() throws {
        #expect(Activity.customizable == [.error, .waiting, .working, .done], """
            Activity.customizable 應為 [.error, .waiting, .working, .done]，實際 \(Activity.customizable)
            """)
        #expect(!Activity.customizable.contains(.idle), "customizable 不得含 idle")
    }

    @Test("items(for:) 順序與 customizable 一致；四項、label 非空互異；色取自 palette")
    func legendItemsFollowOrderAndLabelsTotal() throws {
        let palette = Self.distinctPalette
        let items = LegendModel.items(for: palette, language: .traditionalChinese)

        #expect(items.count == 4, "圖例應恆為四項（D-a：四態可改色），實際 \(items.count)")
        #expect(items.map(\.activity) == [.error, .waiting, .working, .done], """
            圖例順序應為 [.error, .waiting, .working, .done]，實際 \(items.map(\.activity))
            """)
        let labels = items.map(\.label)
        #expect(Set(labels).count == labels.count, "四個標籤應互異，實際 \(labels)")
        #expect(labels.allSatisfy { !$0.isEmpty }, "標籤不得為空，實際 \(labels)")
        for item in items {
            #expect(item.color == palette[item.activity], ".\(item.activity) 圖例色應取自 palette，實際 \(item.color)")
        }
        // D-c 的四個字面（review-t0203 Minor 4：經 public 的 items(for:) 可直接釘死，不必 @testable）
        #expect(items.map(\.label) == ["錯誤", "等你", "執行中", "已完成"], """
            圖例標籤字面應為 錯誤／等你／執行中／已完成（D-c），實際 \(items.map(\.label))
            """)
    }

    @Test("with(_:color:) 用 Mirror 逐欄位比對，只有目標欄位變動")
    func withChangesOnlyThatField() throws {
        let original = Self.distinctPalette
        let newColor = RGBA(r: 0.03, g: 0.77, b: 0.41, a: 1)
        let updated = original.with(.waiting, color: newColor)

        func fields(_ p: IconPalette) -> [String: RGBA] {
            Dictionary(uniqueKeysWithValues: Mirror(reflecting: p).children.compactMap { child -> (String, RGBA)? in
                guard let label = child.label, let value = child.value as? RGBA else { return nil }
                return (label, value)
            })
        }
        let before = fields(original)
        let after = fields(updated)

        for (label, originalValue) in before {
            if label == Activity.waiting.rawValue {
                #expect(after[label] == newColor, """
                    with(.waiting, color:) 之後 .waiting 欄位應為新色 \(newColor)，實際 \(String(describing: after[label]))
                    """)
            } else {
                #expect(after[label] == originalValue, """
                    with(.waiting, color:) 不該動到 .\(label)，實際從 \(originalValue) 變成 \(String(describing: after[label]))
                    """)
            }
        }
    }

    @Test("PanelModel.make 攜帶 palette：model.palette、legend 色、isDefaultPalette、rows/title 與 PanelViewModel 相同")
    func panelModelCarriesPalette() throws {
        let palette = Self.distinctPalette
        let icon = IconState(activity: .waiting, counts: [.waiting: 1], liveCount: 1)
        // 真的一筆 session（review-t01 I2：空陣列會讓 rows 半句變成 0 == 0 的空轉）
        var snap = SessionSnapshot(sessionID: "pm1"); snap.mainActivity = .waiting; snap.cwd = "/tmp/proj"; snap.writtenAt = Date()
        let sessions = [SessionReducer.state(from: snap, liveness: StubLiveness(table: [:]))]
        let now = Date()

        // T11（S0-2，對齊新契約非弱化）：`install` 從 `.notConnected` 改成 `.connected`——
        // `PanelModel.title` 現在非 connected 時改走 `install.healthLabel`（見
        // `TooltipAndTitleConsistencyTests`），`title == PanelViewModel.title(for: icon, language: .traditionalChinese)`
        // 這個斷言的原意「title 委派給 PanelViewModel」只在 connected 時仍然成立，
        // 這裡改 install 讓斷言測的還是同一件事；palette／legend／isDefaultPalette／rows
        // 四個斷言與 install 無關，不受影響。
        let model = PanelModel.make(icon: icon, sessions: sessions, palette: palette,
                                    install: .connected(owner: .thisApp, verified: .verified),
                                    version: "1.0", optionsExpanded: false,
                                    launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, now: now)

        #expect(model.palette == palette, "model.palette 應等於傳入的 palette，實際 \(model.palette)")
        #expect(model.legend.count == 4, "圖例應恆為四項，實際 \(model.legend.count)")
        for item in model.legend {
            #expect(item.color == palette[item.activity], "圖例 .\(item.activity) 應取自傳入的 palette，實際 \(item.color)")
        }
        #expect(model.isDefaultPalette == palette.isDefault, """
            isDefaultPalette 應等於 palette.isDefault，實際 model=\(model.isDefaultPalette) palette.isDefault=\(palette.isDefault)
            """)
        #expect(model.rows == PanelViewModel.rows(from: sessions, now: now, language: .traditionalChinese), "rows 應與 PanelViewModel.rows 相同")
        #expect(model.title == PanelViewModel.title(for: icon, language: .traditionalChinese), "connected 時 title 應與 PanelViewModel.title 相同")
    }
}
