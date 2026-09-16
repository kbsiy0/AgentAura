import Testing
import AppKit
@testable import AgentAuraApp
import AuraCore

/// T32：`SFSymbolIconView`（`IconDrawing` 第二個 conformer）＋「符號名真的存在」的 gate——
/// 這條擋的是「打錯符號名 → 選單列空白，而型別層測試全綠」（`IconShapeTests` 只驗字串
/// 對不對，不驗那個字串真的建得出 `NSImage`）。
@Suite("SFSymbolIconView：SF Symbol 造型的繪製")
struct SFSymbolIconViewTests {

    /// `IconShape.allCases` 逐一走訪，非 nil 的 `systemSymbolName` 都要真的建得出 `NSImage`。
    @Test("每個非 nil 的 systemSymbolName 都真的建得出 NSImage")
    func everySystemSymbolNameBuildsAnNSImage() {
        let names = IconShape.allCases.compactMap(\.systemSymbolName)
        #expect(!names.isEmpty, "gate 不能空跑——至少要有一個造型帶 SF Symbol 名稱")
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, """
                IconShape 的 systemSymbolName「\(name)」建不出 NSImage —— 打錯字或這個系統版本沒有這個符號，
                選單列會空白
                """)
        }
    }

    @MainActor
    @Test("preferredWidth 等於 IconPlate.height（方形底板，符號置中）")
    func preferredWidthIsSquare() {
        let view = SFSymbolIconView()
        #expect(view.preferredWidth == IconPlate.height)
        #expect(SFSymbolIconView.preferredWidth == IconPlate.height)
    }

    /// review-t01-0203 I4 同款 tested≠wired 守門：真的呼叫 `update`，離屏渲染取樣符號
    /// 中心像素，斷言真的是 IconAppearance 算出來的 tinted 顏色（同 `applyReachesDrawing`
    /// 的手法）。用 `.dot`（`circle.fill`，實心圓）——中心點必定落在符號輪廓內。
    @MainActor
    @Test("update 之後，符號中心像素反映 IconAppearance.color（同 LEDStripView 的曲線，D-2）")
    func symbolCenterPixelReflectsAppearance() throws {
        let view = SFSymbolIconView()
        view.symbolName = try #require(IconShape.dot.systemSymbolName)
        view.frame = NSRect(x: 0, y: 0, width: SFSymbolIconView.preferredWidth, height: IconPlate.height)
        view.setShowsPlate(false)

        let error = IconState(activity: .error, counts: [.error: 1], liveCount: 1)
        view.update(AppearancePolicy.appearance(for: error, reduceMotion: true), phase: 0)

        let bitmap = try OffscreenRender.render(view, over: .black)
        let px = try bitmap.pixel(at: view.bounds.center)
        let expected = OffscreenRender.expected(IconPalette.default.error, curveAlpha: 1,
                                                over: RGBA(r: 0, g: 0, b: 0, a: 1))
        #expect(px.maxComponentDelta(expected) <= 2.0 / 255, """
            符號中心像素是 \(px)，不是 error 色 \(expected) —— view 沒把 appearance 用在畫符號上
            """)
    }

    /// `/simplify`（icon-shapes 波次，efficiency#C 的前置 gate）：上面那條只量
    /// `reduceMotion: true`（曲線恆 1）的情形，**動畫中的瞬時 alpha 完全沒被守住**。
    /// 這個 view 的 `draw` 之後要改成「快取不透明的上色圖、逐幀只用 `fraction:` 調暗」，
    /// 那個等價性正是在 alpha < 1 時才有可能出錯——沒有這條 gate，改壞了也全綠。
    ///
    /// 峰值／谷值的 phase 由 `OffscreenRender.peakPhase`／`troughPhase` 掃出來，不寫死。
    /// 單位：sRGB 分量（0…1），容差 2/255。
    @MainActor
    @Test("動畫中的每一格：符號中心像素 == 色 × AnimationCurve.alpha，疊在背景上")
    func symbolCenterPixelFollowsAnimationCurve() throws {
        let view = SFSymbolIconView()
        view.symbolName = try #require(IconShape.dot.systemSymbolName)
        view.frame = NSRect(x: 0, y: 0, width: SFSymbolIconView.preferredWidth, height: IconPlate.height)
        view.setShowsPlate(false)

        let state = IconState(activity: .waiting, counts: [.waiting: 1], liveCount: 1)
        let appearance = AppearancePolicy.appearance(for: state)
        let bg = RGBA(r: 0, g: 0, b: 0, a: 1)

        for phase in [OffscreenRender.peakPhase(of: appearance.animation),
                      OffscreenRender.troughPhase(of: appearance.animation)] {
            view.update(appearance, phase: phase)
            let bitmap = try OffscreenRender.render(view, over: .black)
            let px = try bitmap.pixel(at: view.bounds.center)
            let curve = AnimationCurve.alpha(for: appearance.animation, phase: phase)
            let expected = OffscreenRender.expected(appearance.color, curveAlpha: curve, over: bg)
            #expect(px.maxComponentDelta(expected) <= 2.0 / 255, """
                phase \(phase)（曲線 \(curve)）時中心像素是 \(px)，應為 \(expected)。
                """)
        }
    }

    /// efficiency#C 的第二條前置 gate：上面兩條都用**新建的 view**，快取因此從未跨顏色重用過，
    /// 所以「顏色換了要不要失效」在它們底下是看不見的。而生產裡這個 view 活得很久，
    /// `update(_:phase:)` 會隨 activity 變化餵進不同顏色——快取若只認 `symbolName`，
    /// **選單列的 icon 會永遠停在第一次畫出來的那個顏色**，狀態變化完全看不出來。
    /// 這是這個快取唯一真正危險的失效條件，必須有自己的 gate。
    @MainActor
    @Test("同一個 view 換狀態（換色）後要重畫成新色，不得沿用舊的快取圖")
    func colorChangeInvalidatesCachedSymbol() throws {
        let view = SFSymbolIconView()
        view.symbolName = try #require(IconShape.dot.systemSymbolName)
        view.frame = NSRect(x: 0, y: 0, width: SFSymbolIconView.preferredWidth, height: IconPlate.height)
        view.setShowsPlate(false)
        let bg = RGBA(r: 0, g: 0, b: 0, a: 1)

        func renderCenter(_ activity: Activity) throws -> RGBA {
            let state = IconState(activity: activity, counts: [activity: 1], liveCount: 1)
            view.update(AppearancePolicy.appearance(for: state, reduceMotion: true), phase: 0)
            return try OffscreenRender.render(view, over: .black).pixel(at: view.bounds.center)
        }

        _ = try renderCenter(.error)                      // 先讓快取填上 error 色
        let waitingPixel = try renderCenter(.waiting)     // 再換成 waiting

        let expected = OffscreenRender.expected(IconPalette.default.waiting, curveAlpha: 1, over: bg)
        #expect(waitingPixel.maxComponentDelta(expected) <= 2.0 / 255, """
            換成 waiting 之後中心像素還是 \(waitingPixel)，應為 \(expected)
            —— 上色後的符號圖被快取住了，顏色變了卻沒有重畫。
            """)
    }

    /// 底板開／關要能真的畫出差異（同 T16 對 `LEDStripView` 的既有驗證形狀）——
    /// 取樣底板角落（符號輪廓一定沒蓋到的地方），開時應為 `IconPlate.color`，關時應維持背景色。
    @MainActor
    @Test("setShowsPlate(true) 時角落像素是 IconPlate.color；false 時維持背景色")
    func plateTogglesCornerPixel() throws {
        let view = SFSymbolIconView()
        view.symbolName = try #require(IconShape.ring.systemSymbolName)
        view.frame = NSRect(x: 0, y: 0, width: SFSymbolIconView.preferredWidth, height: IconPlate.height)
        view.update(AppearancePolicy.appearance(for: .empty), phase: 0)

        // x=1／y=置中：左邊緣中點，避開圓角（半徑 5pt，貼在幾何角落的取樣點會被裁掉，
        // 誤判成背景色——同 LEDStripView 的圓角幾何，見 IconPlate.draw）與符號輪廓。
        let corner = CGPoint(x: 1, y: IconPlate.height / 2)

        view.setShowsPlate(true)
        let onBitmap = try OffscreenRender.render(view, over: .white)
        let onPixel = try onBitmap.pixel(at: corner)
        #expect(onPixel.maxComponentDelta(IconPlate.colorRGBA) <= 2.0 / 255, """
            底板開啟時角落像素應是 IconPlate.color，實際 \(onPixel)
            """)

        view.setShowsPlate(false)
        let offBitmap = try OffscreenRender.render(view, over: .white)
        let offPixel = try offBitmap.pixel(at: corner)
        #expect(offPixel.maxComponentDelta(RGBA(r: 1, g: 1, b: 1, a: 1)) <= 2.0 / 255, """
            底板關閉時角落像素應維持背景白，實際 \(offPixel)
            """)
    }
}
