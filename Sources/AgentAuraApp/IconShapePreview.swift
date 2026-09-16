import AppKit
import AuraCore

/// 造型選單每一項左邊的縮圖。
///
/// **關鍵設計：預覽圖用的是真正的繪製器**（`StatusItemController.makeDrawingView(for:)`），
/// 不是另外畫一份「長得很像」的示意圖。理由是這個 codebase 反覆踩過的同一族問題——
/// 平行維護的第二份實作會跟本尊漂開，而且漂開時**沒有任何東西會紅**
/// （CLAUDE.md gate 哲學第 2 條「涵蓋每一個 X 必須從型別／磁碟推導」的同一個精神）。
/// 這裡連「涵蓋」都不必推導：預覽**就是**選單列上那個 view 自己畫出來的。
///
/// 使用者回報：「在選擇的頁面就先把 icon 秀出來，不要讓人選完才知道長什麼樣」——
/// 原本的選單只有文字，挑造型卻看不到造型。
///
/// T35：**每一項的畫布寬度統一**——各造型 `preferredWidth` 不同
/// （`SFSymbolIconView` 18pt／`LEDStripView` 44pt），
/// `NSMenuItem.image` 直接吃這些不等寬的圖，文字起點就跟著參差，看起來像跑版
/// （使用者回報：「文字與圖示的排版有點破」）。`image(for:...)` 因此拆成兩層：
/// `rawImage` 產出真正繪製器畫出來的原始寬度（沿用 T34 的既有邏輯，未改），
/// `image` 再把它疊在統一寬度的畫布上水平置中。單位皆為 pt（`preferredWidth`／
/// `NSImage.size` 都是 pt，不是 @2x 像素）。
@MainActor
enum IconShapePreview {

    /// 選單項圖片的高度（pt）。`NSMenuItem.image` 太高會把列撐開，
    /// 18pt 與 `IconPlate.height` 同源，剛好是選單列上那個底板的實際高度。
    static var height: CGFloat { IconPlate.height }

    /// T35：統一畫布寬度——`IconShape.allCases` 裡最寬造型實際佔的 `preferredWidth`，
    /// **從 allCases 推導，不寫死數字**（CLAUDE.md「這個 codebase 的 gate 哲學」第 2 條：
    /// 凍住的數字會凍住錯誤，`LEDStripView.preferredWidth` 曾經吃過這個虧）。
    ///
    /// `static let` 而非 `static var`（`/simplify` icon-shapes 波次，efficiency#A）：
    /// **推導式一字不改**，只是靠 `swift_once` 求值一次。原本是 computed property，
    /// 而每次讀取都會把全部造型的 view 各建一個——`image(for:)` 每張縮圖讀一次，
    /// 於是一張縮圖＝7 個 `NSView` 配置（1 個真的拿來畫 + 6 個只為了算一個寬度）。
    /// 選單開啟一次 42 個；選單開著時 `IconShapeMenuPreview` 每格再 42 個，
    /// 而幀率是活的 `targetFPS`（`waiting`／`error` 30fps）→ **1,260 個 view 配置/秒**，
    /// 全在主執行緒、而且選單正在 tracking。同檔 `IconPlate.colorRGBA` 是同樣的形狀。
    static let canvasWidth: CGFloat =
        IconShape.allCases.map { StatusItemController.makeDrawingView(for: $0).preferredWidth }.max() ?? height

    /// 造型本身真正畫出來的原始尺寸——**用的是真正的繪製器**
    /// （`StatusItemController.makeDrawingView(for:)`），不是另外畫一份「長得很像」的
    /// 示意圖（理由見上）。`image(for:...)` 疊置中畫布前的唯一輸入。
    ///
    /// `phase` 預設 0（靜態）；T35 加這個參數是為了選單開著時的動畫預覽
    /// （`IconShapeMenuPreview`）能拿同一份繪製邏輯畫不同相位，不必另外重寫一次。
    /// 兩個 conformer 的 `draw` 都吃 `AnimationCurve.alpha(for:phase:)`，所以 phase 真的
    /// 改變像素；`phase` 不推進時固定同一張，行為與 T34 相同。
    static func rawImage(for shape: IconShape, appearance: IconAppearance, showsPlate: Bool,
                         phase: Double = 0) -> NSImage? {
        let view = StatusItemController.makeDrawingView(for: shape)
        view.setShowsPlate(showsPlate)
        view.update(appearance, phase: phase)
        view.frame = NSRect(x: 0, y: 0, width: view.preferredWidth, height: height)

        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)

        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        // **不是 template**：各狀態色都靠真實顏色傳達，交給系統做單色化
        // 會把整排預覽變成同一個灰形狀，等於沒有預覽。
        image.isTemplate = false
        return image
    }

    /// 把某個造型畫成 `NSMenuItem` 用得上的 `NSImage`——`rawImage` 疊在 `canvasWidth`
    /// 寬的透明畫布上水平置中，讓每一項的圖片寬度一致，文字起點才會對齊（T35）。
    static func image(for shape: IconShape, appearance: IconAppearance, showsPlate: Bool,
                      phase: Double = 0) -> NSImage? {
        guard let inner = rawImage(for: shape, appearance: appearance, showsPlate: showsPlate, phase: phase)
        else { return nil }
        return centered(inner, in: NSSize(width: canvasWidth, height: height))
    }

    /// 把 `inner` 疊在 `canvasSize` 的透明畫布正中央——顯式用 `NSBitmapImageRep` 建畫布
    /// （不是 `NSImage.lockFocus()`），確保最終圖片的 `representations.first` 仍是
    /// `NSBitmapImageRep`（既有的 `previewIsNotBlank` 逐像素檢查依賴這個型別）。
    private static func centered(_ inner: NSImage, in canvasSize: NSSize) -> NSImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(canvasSize.width), pixelsHigh: Int(canvasSize.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // 顯式清成透明——`bitmapDataPlanes: nil` 配置出來的記憶體內容未定義，不能假設是 0。
        context.cgContext.clear(CGRect(origin: .zero, size: canvasSize))
        let x = (canvasSize.width - inner.size.width) / 2
        inner.draw(at: NSPoint(x: x, y: 0), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let canvas = NSImage(size: canvasSize)
        canvas.addRepresentation(rep)
        canvas.isTemplate = false
        return canvas
    }
}
