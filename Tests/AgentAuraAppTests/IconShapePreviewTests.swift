import Testing
import AppKit
@testable import AgentAuraApp
@testable import AuraCore

/// T34：造型選單每一項左邊要有縮圖——使用者回報「在選擇的頁面就先把 icon 秀出來，
/// 不要讓人選完才知道長什麼樣」。原本的選單只有文字，挑造型卻看不到造型。
///
/// **這組 gate 真正守的是「縮圖不會跟本尊漂開」**：縮圖由
/// `StatusItemController.makeDrawingView(for:)` 產生，也就是選單列上那個 view 自己畫的，
/// 不是另外維護一份「長得很像」的示意圖。平行維護的第二份實作會漂，而且漂的時候
/// 沒有任何東西會紅——這個 codebase 已經被同一族咬過兩次（`LEDStripView.preferredWidth`
/// 的凍結數字、`SessionsCardSizing.rowHeight` 用錯的列量出來的高度）。
@MainActor
@Suite("造型選單縮圖（T34）")
struct IconShapePreviewTests {

    static func appearance(_ activity: Activity, alpha: Double) -> IconAppearance {
        AppearancePolicy.appearance(for: IconState(activity: activity,
                                                  counts: [activity: 1], liveCount: 1))
    }

    @Test("每一個造型都畫得出縮圖（涵蓋從 allCases 推導，新增造型不會漏）")
    func everyShapeProducesAPreview() {
        let base = Self.appearance(.working, alpha: 1).staticFullyOpaque
        for shape in IconShape.allCases {
            let image = IconShapePreview.image(for: shape, appearance: base, showsPlate: true)
            let img = try? #require(image, "\(shape) 畫不出縮圖 —— 選單那一項會是空白")
            #expect((img?.size.width ?? 0) > 0 && (img?.size.height ?? 0) > 0,
                    "\(shape) 的縮圖尺寸是 0，等於沒有縮圖")
        }
    }

    /// **T34 原始斷言，T35 改指向 `rawImage`（疊置中畫布前那一層）**——這是「用同一個
    /// 繪製器」最直接的可觀察後果，若哪天有人改成另外畫一份示意圖，寬度就會對不上。
    /// 這條是**改寫，不是弱化**：T35 之前 `image(...)` 本身就是這層，寬度必然等於
    /// `preferredWidth`；T35 讓 `image(...)` 多疊一層置中畫布後，公開 API 的寬度統一變成
    /// `canvasWidth`（見下面 `allPreviewsShareTheSameCanvasWidth`），「縮圖用真正的繪製器」
    /// 這件事本身沒有變，只是量測點從 `image` 移到它現在呼叫的 `rawImage`——同一份邏輯、
    /// 同一個斷言內容，只是換了層。單位：pt。
    @Test("rawImage 寬度 == 該造型的 preferredWidth（證明用的是同一個繪製器）")
    func rawImageWidthMatchesRealRendererWidth() {
        let base = Self.appearance(.working, alpha: 1).staticFullyOpaque
        for shape in IconShape.allCases {
            let expected = StatusItemController.makeDrawingView(for: shape).preferredWidth
            let image = IconShapePreview.rawImage(for: shape, appearance: base, showsPlate: true)
            #expect(image?.size.width == expected, """
                \(shape) 的 rawImage 寬 \(String(describing: image?.size.width))pt，
                但它在選單列上實際佔 \(expected)pt —— 縮圖已經不是用真正的繪製器畫的了。
                """)
        }
    }

    /// T35：使用者回報「文字與圖示的排版有點破」——根因是各造型 `preferredWidth` 不同，
    /// `NSMenuItem.image` 直接吃這些不等寬的圖，文字起點就跟著參差。這裡要求每一項
    /// **最終**縮圖（`image(...)`，含置中畫布）寬度一致，且等於獨立推導出的最大
    /// `preferredWidth`（不是照抄 `IconShapePreview.canvasWidth` 本身，避免「跟自己比對」
    /// 這種凍不住錯誤的假 gate——同 CLAUDE.md 對 `statusItemWidthFollowsRenderer` 的提醒）。
    @Test("每個造型的最終縮圖共用同一個畫布寬度，且等於從 allCases 推導出的最大 preferredWidth")
    func allPreviewsShareTheSameCanvasWidth() {
        let base = Self.appearance(.working, alpha: 1).staticFullyOpaque
        let expectedCanvas = IconShape.allCases
            .map { StatusItemController.makeDrawingView(for: $0).preferredWidth }
            .max()
        for shape in IconShape.allCases {
            let image = IconShapePreview.image(for: shape, appearance: base, showsPlate: true)
            #expect(image?.size.width == expectedCanvas, """
                \(shape) 的最終縮圖寬 \(String(describing: image?.size.width))pt，
                但統一畫布應該是 \(String(describing: expectedCanvas))pt —— 各項文字起點會參差。
                """)
        }
    }

    /// T35：畫布加寬只是手段，內容真的置中才是目的——否則「跑版」只是從左邊挪到別的地方，
    /// 不是修好。量比畫布窄的造型左右留白的像素數，兩邊應該相等（±1px 容忍反鋸齒）。
    @Test("畫布內比較窄的造型水平置中，不是靠左貼齊")
    func previewContentIsHorizontallyCentered() throws {
        let base = Self.appearance(.working, alpha: 1).staticFullyOpaque
        let canvasWidth = IconShapePreview.canvasWidth
        let narrowerShapes = IconShape.allCases.filter {
            StatusItemController.makeDrawingView(for: $0).preferredWidth < canvasWidth
        }
        try #require(!narrowerShapes.isEmpty, "沒有造型比畫布窄，量不出置中效果——換一個能顯出差異的基準造型")
        for shape in narrowerShapes {
            let image = try #require(IconShapePreview.image(for: shape, appearance: base, showsPlate: true))
            let rep = try #require(image.representations.first as? NSBitmapImageRep)
            var minX = rep.pixelsWide
            var maxX = -1
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    break
                }
            }
            try #require(maxX >= minX, "\(shape) 整張透明，量不出置中效果")
            let leftGap = minX
            let rightGap = rep.pixelsWide - 1 - maxX
            #expect(abs(leftGap - rightGap) <= 1,
                    "\(shape) 左右留白 \(leftGap)px vs \(rightGap)px，內容沒有置中，只是換個位置跑版")
        }
    }

    /// 縮圖不是空白。`.ledStrip` 在 `showsPlate: false`、顏色又剛好接近背景時仍應畫得出東西，
    /// 所以這裡用有底板的版本確保一定有像素——這條擋的是「畫布建了但根本沒 draw」。
    @Test("縮圖真的有畫東西，不是空白畫布")
    func previewIsNotBlank() throws {
        let base = Self.appearance(.waiting, alpha: 1).staticFullyOpaque
        for shape in IconShape.allCases {
            let image = try #require(IconShapePreview.image(for: shape, appearance: base, showsPlate: true))
            let rep = try #require(image.representations.first as? NSBitmapImageRep)
            var nonTransparent = 0
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                for y in stride(from: 0, to: rep.pixelsHigh, by: 2) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                    nonTransparent += 1
                }
            }
            #expect(nonTransparent > 0, "\(shape) 的縮圖整張透明 —— 畫布建了但沒畫東西")
        }
    }

    /// altitude#5：**新增造型路徑上唯一沒有編譯器守住的接縫。**
    ///
    /// `IconShape` 的三個 `switch`（`systemSymbolName`／`displayName`／`L10nIconShape.text`）
    /// 都沒有 `default:`，少一個 case 就編不過——那是刻意且有效的編譯器 gate。
    /// 但 `StatusItemController.makeDrawingView(for:)` 是 `if let symbolName … else { LEDStripView() }`，
    /// **新增一個非 SF Symbol 的造型不會有任何東西變紅，它會安靜地畫成 LED 燈條**。
    /// 那個 `else` 在 T32→T33 是刻意佔位（當時彩虹貓還沒畫），造型移除後佔位語意消失、
    /// 形狀留著。
    ///
    /// 既有的三條 `allCases` 推導 gate（畫得出來／寬度對／不是空白）對「兩個造型畫出
    /// 同一張圖」全部是綠的。這條補上：**任兩個造型的縮圖不得逐像素相同**。
    /// 從 `allCases` 兩兩配對推導，新增造型不必再補斷言。
    @Test("任兩個造型畫出來的縮圖不得完全相同（新增造型忘了接線會安靜畫成 LED）")
    func everyShapeRendersDistinctly() throws {
        let base = Self.appearance(.working, alpha: 1).staticFullyOpaque
        var bytes: [IconShape: Data] = [:]
        for shape in IconShape.allCases {
            let image = try #require(IconShapePreview.image(for: shape, appearance: base, showsPlate: true))
            let rep = try #require(image.representations.first as? NSBitmapImageRep)
            let raw = try #require(rep.bitmapData)
            bytes[shape] = Data(bytes: raw, count: rep.bytesPerRow * rep.pixelsHigh)
        }
        let shapes = IconShape.allCases
        for i in shapes.indices {
            for j in shapes.indices where j > i {
                #expect(bytes[shapes[i]] != bytes[shapes[j]], """
                    \(shapes[i]) 與 \(shapes[j]) 畫出來逐像素相同 —— 多半是
                    `makeDrawingView(for:)` 沒有為其中一個接上繪製器，它落到了 `else`
                    那條「沿用 LEDStripView」的佔位分支。使用者選了造型卻看不到變化。
                    """)
            }
        }
    }

    /// `staticFullyOpaque` 的契約：**只動 alpha 與動畫，狀態語意原封不動**。
    /// 這條擋的是「有人為了讓縮圖好看，順手在這裡改了 activity 或計數」——
    /// 那會讓縮圖與實際狀態說不同的話。
    @Test("staticFullyOpaque 只拉滿 alpha 與停掉動畫，不動狀態語意")
    func staticFullyOpaquePreservesStateSemantics() {
        for activity in Activity.allCases {
            let original = Self.appearance(activity, alpha: 1)
            let preview = original.staticFullyOpaque
            #expect(preview.activity == original.activity)
            #expect(preview.attentionCount == original.attentionCount)
            #expect(preview.liveCount == original.liveCount)
            #expect(preview.color.r == original.color.r && preview.color.g == original.color.g
                    && preview.color.b == original.color.b, "色相不得被改動，只有 alpha")
            #expect(preview.color.a == 1, "alpha 要拉滿，否則 idle 的縮圖整排灰掉難以比較")
            #expect(preview.animation == .none && preview.targetFPS == 0, "縮圖是靜態的，不該排程重繪")
        }
    }
}
