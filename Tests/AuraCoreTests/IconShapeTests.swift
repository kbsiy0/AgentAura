import Testing
import AuraCore

/// T32：`IconShape` 的模型層（design doc `2026-09-15-icon-shapes-design.md` §2／§3）。
/// D-2：這裡刻意不含任何顏色／動畫欄位——造型只決定畫什麼形狀，`IconAppearance`／
/// `AppearancePolicy` 完全不受影響（見 `IconAppearanceUnchangedByIconShapeTests`）。
@Suite("IconShape：六個造型的模型層")
struct IconShapeTests {

    @Test("六個 case，rawValue 對應設計文件表格（落盤用，字面釘死——同 Language.rawValuesArePinned 的理由）")
    func rawValuesArePinned() {
        #expect(IconShape.allCases.count == 6, "T37 移除彩虹貓後恰好 6 列，實際 \(IconShape.allCases.count)")
        #expect(IconShape.ledStrip.rawValue == "ledStrip")
        #expect(IconShape.dot.rawValue == "dot")
        #expect(IconShape.ring.rawValue == "ring")
        #expect(IconShape.capsule.rawValue == "capsule")
        #expect(IconShape.sparkle.rawValue == "sparkle")
        #expect(IconShape.halfCircle.rawValue == "halfCircle")
    }

    /// spec §3 表格：`ledStrip` 不是靠 SF Symbol 畫，它沿用既有 `LEDStripView`，
    /// 不透過 `NSImage(systemSymbolName:)` 建圖；`AgentAuraApp` 端的 `makeDrawingView(for:)`
    /// 靠這個 `nil` 判斷該不該走 SF Symbol 分支。
    @Test("systemSymbolName 對應 spec §3 表格")
    func systemSymbolNameMatchesSpecTable() {
        #expect(IconShape.ledStrip.systemSymbolName == nil)
        #expect(IconShape.dot.systemSymbolName == "circle.fill")
        #expect(IconShape.ring.systemSymbolName == "circle")
        #expect(IconShape.capsule.systemSymbolName == "capsule.fill")
        #expect(IconShape.sparkle.systemSymbolName == "sparkle")
        #expect(IconShape.halfCircle.systemSymbolName == "circle.lefthalf.filled")
    }

    @Test("displayName 對每個 case、每個語言都非空（走 L10nIconShape，窮盡覆蓋）")
    func displayNameIsExhaustive() {
        for shape in IconShape.allCases {
            for language in Language.allCases {
                #expect(!shape.displayName(language).isEmpty, "\(shape) 在 \(language) 底下不該是空字串")
            }
        }
    }
}
