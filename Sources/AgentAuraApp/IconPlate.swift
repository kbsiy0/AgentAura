import AppKit
import AuraCore

/// T32：底板繪製，`SFSymbolIconView` 與既有 `LEDStripView` 共用同一份幾何／顏色常數
/// （design doc `2026-09-15-icon-shapes-design.md` §4 known gap 3：第一版所有造型
/// 一律沿用同一個底板開關，不逐一調整）。
///
/// **這裡是兩個 conformer 共用的唯一一份底板繪製**（`/simplify` icon-shapes 波次，reuse#1）。
/// 初版只搬常數、繪製程序各寫一份，宣稱「不改已驗證的程式碼所以風險為零」——
/// 結果兩份當場就漂開了：`LEDStripView` 畫進高度鎖 18pt 的 `plateRect`，
/// `SFSymbolIconView` 畫滿整個 `bounds`，而生產路徑的 view 高度是
/// `NSStatusBar.system.thickness`（22pt），於是選單列上 SF Symbol 造型的底板頂天立地、
/// LED 造型上下各留 2pt。三個既有觀測點又剛好都把高度設成 18，沒有一條會紅。
/// **少改一行的風險不是零，只是換成了沒人看顧的那一種。**
/// 現在幾何（`rect(in:)`）與繪製（`draw(in:)`）都收在這裡，`LEDStripView.plateRect`
/// 轉呼叫，渲染結果由 `IconPlateGeometryTests` 在**生產高度**下逐造型量。
///
/// `@MainActor`：`LEDStripView` 是 `@MainActor final class`，它的 static 成員因此也是
/// main-actor-isolated——這裡讀取它們的 `static let` 初始值必須在同一個隔離域。
@MainActor
enum IconPlate {
    static let height: CGFloat = LEDStripView.plateHeight
    static let cornerRadius: CGFloat = LEDStripView.plateCornerRadius

    /// 底板色的**唯一**字面（`/simplify` icon-shapes 波次，simplify#B2）。
    ///
    /// 原本是反過來的：`NSColor` 那份是來源，這裡用 `usingColorSpace(.sRGB)` 轉回來，
    /// 轉換失敗時再 fallback 到一組手寫的 (20,20,22)——而那個 doc comment 正好寫著
    /// 「不重複 `LEDStripView.plateColor` 內部那組字面」，下一行就寫了第三份。
    /// 那條 `guard else` 還永遠不會執行（來源是 `NSColor(srgbRed:)` 建的，轉 sRGB 不會失敗），
    /// 也就是一段沒有人能觸發、卻要維護的程式碼。
    /// 現在 `RGBA` 是來源，`NSColor` 從它導出，字面只有這一處。
    static let colorRGBA = RGBA(r: 20 / 255, g: 20 / 255, b: 22 / 255, a: 1)
    static let color = NSColor(rgba: colorRGBA)

    /// 底板矩形：**寬度吃滿 `bounds`、高度鎖 `height` 並垂直置中**。
    /// 選單列給的 view 高度是 `NSStatusBar.system.thickness`（22pt）而底板是 18pt，
    /// 差額就是上下邊距；拿整個 `bounds` 當底板會讓它頂天立地（reuse#1 實測的差異）。
    static func rect(in bounds: NSRect) -> NSRect {
        NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
    }

    /// 疊在 `plate`（＝`rect(in:)` 算出來的底板矩形，**不是**整個 bounds）。
    static func draw(in plate: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: plate, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        // 描邊內縮 0.25pt，否則外側 0.25pt 會被 bounds 裁掉（spec §4.1）。
        let strokePath = NSBezierPath(roundedRect: plate.insetBy(dx: 0.25, dy: 0.25),
                                      xRadius: cornerRadius, yRadius: cornerRadius)
        strokePath.lineWidth = 0.5
        NSColor.white.withAlphaComponent(0.10).setStroke()
        strokePath.stroke()
    }
}
