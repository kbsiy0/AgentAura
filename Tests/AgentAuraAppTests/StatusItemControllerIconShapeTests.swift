import Testing
import AppKit
@testable import AgentAuraApp
import AuraCore

/// T32：`StatusItemController.setIconShape` 真的換掉 `drawing`、`preferredWidth` 跟著造型變
/// （CLAUDE.md gate 哲學：`statusItemWidthFollowsRenderer` 只守預設 `.ledStrip` 這一個造型，
/// 這裡補「換造型之後」的觀測性——不必動那條既有 gate）。
@MainActor
@Suite("StatusItemController.setIconShape：造型可換")
struct StatusItemControllerIconShapeTests {

    @Test("預設建構仍是 LEDStripView（不驚動既有使用者，D-3）——既有 statusItemWidthFollowsRenderer 前提不變")
    func defaultConstructionIsStillLEDStripView() {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }
        #expect(controller.drawing is LEDStripView)
    }

    @Test("setIconShape(.dot) 換成 SFSymbolIconView，preferredWidth／item.length 跟著變成 IconPlate.height + 8")
    func setIconShapeSwapsDrawingAndWidth() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }

        controller.setIconShape(.dot)

        let view = try #require(controller.drawing as? SFSymbolIconView, """
            .setIconShape(.dot) 之後 drawing 應該是 SFSymbolIconView，實際 \(type(of: controller.drawing))
            """)
        #expect(view.symbolName == IconShape.dot.systemSymbolName)
        #expect(controller.drawing.preferredWidth == IconPlate.height)
        #expect(controller.statusItemLength == IconPlate.height + 8, """
            statusItemLength 應跟著新 renderer 的 preferredWidth 變，實際 \(controller.statusItemLength)
            """)
    }

    /// 換造型之前用 `apply` 設過的 appearance／底板偏好必須延續到新 view——否則換造型的
    /// 瞬間會有一顆看不出任何狀態的空白 icon（同 T16 `showsPlate` 偏好延續的既有精神）。
    @Test("setIconShape 之後，之前的 appearance 與底板偏好延續到新 view")
    func setIconShapePreservesAppearanceAndPlatePreference() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }

        controller.setIconPlate(false)
        let error = IconState(activity: .error, counts: [.error: 1], liveCount: 1)
        controller.apply(AppearancePolicy.appearance(for: error, reduceMotion: true), phase: 0)

        controller.setIconShape(.dot)

        let bitmap = try OffscreenRender.render(try #require(controller.drawing as? NSView), over: .white)
        // x=1／置中高度：左邊緣中點，避開圓角與符號輪廓——同 SFSymbolIconViewTests 的既有理由。
        let corner = try bitmap.pixel(at: CGPoint(x: 1, y: IconPlate.height / 2))
        #expect(corner.maxComponentDelta(RGBA(r: 1, g: 1, b: 1, a: 1)) <= 2.0 / 255, """
            setIconPlate(false) 之後換造型，新 view 的底板應該仍是關的，實際角落像素 \(corner)
            """)

        let px = try bitmap.pixel(at: try #require(controller.drawing as? NSView).bounds.center)
        let expected = OffscreenRender.expected(IconPalette.default.error, curveAlpha: 1, over: RGBA(r: 1, g: 1, b: 1, a: 1))
        #expect(px.maxComponentDelta(expected) <= 2.0 / 255, """
            換造型前 apply 過的 error 色應該延續到新 view，實際中心像素 \(px)
            """)
    }
}
