import AppKit
import Testing
@testable import AgentAuraApp
@testable import AuraCore

/// `/simplify`（icon-shapes 波次，reuse#1）：**底板幾何在所有造型之間必須一致**。
///
/// ## 這條 gate 補的洞
///
/// `IconPlate.draw(in:)` 當初的 doc comment 宣稱「只讀 `LEDStripView` 的常數，不重寫」，
/// 但實際重寫的是**繪製程序**：`LEDStripView` 畫進 `plateRect`（高度鎖 `plateHeight` = 18、
/// 在 bounds 裡垂直置中），`SFSymbolIconView` 畫進整個 `bounds`。生產路徑
/// （`StatusItemController.init`／`setIconShape`）把 view 高度設成
/// `NSStatusBar.system.thickness`（本機 22pt），於是選單列上：LED 造型底板 18pt、上下各留 2pt；
/// SF Symbol 造型底板 22pt、頂天立地。**同一個「底板」開關畫出兩種底板。**
///
/// 而在此之前**沒有任何測試會紅**——`SFSymbolIconViewTests`、`StatusItemControllerIconShapeTests`、
/// `IconShapePreview.rawImage` 三個觀測點全部把高度設成 `IconPlate.height`（18），
/// 剛好避開唯一的生產值。這正是 CLAUDE.md 記載的「vacuously green」家族：
/// 三道關卡共用同一個「方便的高度」，盲點被複製到每一道。
///
/// ## 為什麼量渲染而不是比對原始碼
///
/// gate 哲學第 4 條：守「宣告」不等於守「渲染結果」。這裡直接在**生產高度**下渲染、
/// 量底板的實際垂直範圍，任何造型只要底板畫得跟別人不一樣就會紅。
/// 單位：pt（`NSView.bounds`／`IconPlate.height` 都是 pt；取樣步長 0.5pt＝@2x 的 1 像素）。
@MainActor
@Suite("底板幾何跨造型一致（reuse#1）")
struct IconPlateGeometryTests {

    /// **生產高度**，不是測試方便的 `IconPlate.height`——這條 gate 存在的全部理由就是
    /// 既有三個觀測點都用了後者，剛好避開差異。
    static var productionHeight: CGFloat { NSStatusBar.system.thickness }

    static func mountedView(for shape: IconShape) -> NSView & IconDrawing {
        let view = StatusItemController.makeDrawingView(for: shape)
        view.setShowsPlate(true)
        view.update(AppearancePolicy.appearance(for: IconState.empty), phase: 0)
        view.frame = NSRect(x: 0, y: 0, width: view.preferredWidth, height: productionHeight)
        return view
    }

    /// 在 `x` 這一直行上，量「非背景」像素的垂直範圍（view 座標，pt）。
    /// 底板是畫得最外圈的東西（符號／LED 都在它裡面），所以這個範圍就是底板的上下緣。
    static func plateVerticalSpan(of view: NSView, at x: CGFloat) throws -> (min: CGFloat, max: CGFloat) {
        let bitmap = try OffscreenRender.render(view, over: .white)
        let white = RGBA(r: 1, g: 1, b: 1, a: 1)
        let step: CGFloat = 0.5          // @2x 的一個像素
        var lo = CGFloat.infinity
        var hi = -CGFloat.infinity
        // 從 `step` 起跳、到 `bounds.height` 為止：`pixel(at:)` 把 view 座標 y 換算成
        // `(height - y) * scale` 再四捨五入，y < 0.5 會捨進到畫布外（實測 y=0.25 → 越界 throw）。
        var y = step
        while y <= view.bounds.height {
            let px = try bitmap.pixel(at: CGPoint(x: x, y: y))
            if px.maxComponentDelta(white) > 0.05 {
                lo = min(lo, y)
                hi = max(hi, y)
            }
            y += step
        }
        try #require(hi >= lo, "整行都是背景色 —— 底板根本沒畫出來，量不出幾何")
        return (lo, hi)
    }

    @Test("每個造型的底板高度都是 IconPlate.height，且在生產高度下垂直置中")
    func everyShapeDrawsTheSamePlateGeometry() throws {
        let height = Self.productionHeight
        try #require(height > IconPlate.height, """
            選單列厚度 \(height)pt 沒有大於底板高度 \(IconPlate.height)pt —— 這條 gate 量不出差異，
            換一個能顯出差異的高度，不要讓它靜默空轉。
            """)

        for shape in IconShape.allCases {
            let view = Self.mountedView(for: shape)
            let span = try Self.plateVerticalSpan(of: view, at: view.bounds.midX)
            let drawn = span.max - span.min
            let topMargin = height - span.max
            let bottomMargin = span.min

            #expect(abs(drawn - IconPlate.height) <= 1.0, """
                \(shape) 的底板高 \(drawn)pt，應為 IconPlate.height = \(IconPlate.height)pt。
                差異來源多半是底板畫進了整個 `bounds` 而不是高度鎖定的底板矩形——
                在選單列上（高 \(height)pt）會變成頂天立地，跟其他造型不一樣。
                """)
            #expect(abs(topMargin - bottomMargin) <= 1.0, """
                \(shape) 的底板上邊距 \(topMargin)pt vs 下邊距 \(bottomMargin)pt —— 沒有垂直置中。
                """)
        }
    }

    @Test("縮圖用的高度就是底板高度，不會跟選單列上的底板說不同的話")
    func previewHeightMatchesPlateHeight() {
        #expect(IconShapePreview.height == IconPlate.height, """
            `IconShapePreview.height` 是縮圖畫布的高度。它一旦與 `IconPlate.height` 脫鉤，
            縮圖畫的底板就會跟選單列上的底板不同高，而縮圖的賣點正是「本尊自己畫的」。
            """)
    }
}
