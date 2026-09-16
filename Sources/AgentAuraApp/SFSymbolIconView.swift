import AppKit
import AuraCore

/// T32：SF Symbol 造型的 `IconDrawing` conformer（design doc D-1）——`LEDStripView` 之外
/// 第二個 conformer。
///
/// `symbolName` 是可設定的 `var`，不是 init 參數：`NSView` 一旦新增自訂 designated init，
/// `required init?(coder:)` 也要一起補——那通常寫成 `fatalError(...)`，CLAUDE.md 禁用。
/// 沿用 `LEDStripView`「零自訂 init、全部欄位有預設值」的既有形狀，兩個 conformer 因此
/// 一致，`makeDrawingView(for:)`（`StatusItemController+IconShape.swift`）建完就立刻設值。
@MainActor
final class SFSymbolIconView: NSView, IconDrawing {
    private var iconAppearance = AppearancePolicy.appearance(for: IconState.empty)
    private var phase: Double = 0
    var symbolName: String = "circle.fill" { didSet { needsDisplay = true } }

    /// design doc §4 known gap 3：底板沿用 `IconPlate`（跟 `LEDStripView` 同一份幾何／顏色）。
    /// 方形——寬＝高，符號置中；不像 LED 燈條需要 8 顆燈的橫向跨距。
    static var preferredWidth: CGFloat { IconPlate.height }
    var preferredWidth: CGFloat { Self.preferredWidth }

    private(set) var showsPlate = true

    /// 全部 5 個 SF Symbol 造型共用同一份字重／尺寸，不逐一調整。
    static let symbolPointSize: CGFloat = 13

    func update(_ appearance: IconAppearance, phase: Double) {
        self.iconAppearance = appearance
        self.phase = phase
        needsDisplay = true
    }

    func setShowsPlate(_ shows: Bool) {
        showsPlate = shows
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsPlate { IconPlate.draw(in: IconPlate.rect(in: bounds)) }

        // D-2：顏色全部來自 IconAppearance，動畫的瞬時不透明度由
        // `IconAppearance.drawingAlpha(phase:)` 算——App 層不自己判斷動畫種類、不自己算曲線。
        guard let tinted = opaqueTintedSymbol() else { return }
        let rect = NSRect(x: (bounds.width - tinted.size.width) / 2, y: (bounds.height - tinted.size.height) / 2,
                          width: tinted.size.width, height: tinted.size.height)
        tinted.draw(in: rect, from: .zero, operation: .sourceOver,
                    fraction: iconAppearance.drawingAlpha(phase: phase))
    }

    /// 上色後的**不透明**符號圖，依 `symbolName` ＋ 顏色快取。
    ///
    /// `/simplify`（icon-shapes 波次，efficiency#C）：原本每一幀都重跑
    /// 「`NSImage(systemSymbolName:)` → `withSymbolConfiguration` → `tinted()`」，
    /// 也就是 3 個 `NSImage` 配置 ＋ 一次 `lockFocus` 離屏光柵化。這是**常駐 icon 的熱路徑**
    /// （`AnimationDriver` 每幀觸發，`working` 10fps／`waiting`·`error` 30fps，只要有 session
    /// 在那個狀態就一直跑），而 6 個造型裡有 5 個走它。逐幀真正改變的只有一個純量 alpha。
    ///
    /// 等價性：「填 alpha=a 的色 → `.destinationIn` 遮罩」與「不透明圖 × `fraction: a`」
    /// 在 premultiplied 合成下結果相同。**這不是靠推論相信的**——
    /// `symbolCenterPixelFollowsAnimationCurve` 在曲線峰值與谷值兩個相位逐像素驗過。
    ///
    /// 失效條件只有兩個：`symbolName` 換了（`didSet`）、或 appearance 的顏色換了
    /// （這裡比對，不必靠呼叫端記得清）。phase **不是**失效條件，那正是重點。
    private var cachedSymbol: (name: String, color: RGBA, image: NSImage)?

    private func opaqueTintedSymbol() -> NSImage? {
        let color = iconAppearance.color
        if let cached = cachedSymbol, cached.name == symbolName, cached.color == color {
            return cached.image
        }
        let config = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .regular)
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let image = Self.tinted(base, with: NSColor(rgba: color, alpha: 1))
        cachedSymbol = (symbolName, color, image)
        return image
    }

    /// template image 在畫的當下換成任意顏色（含動畫算出來的瞬時 alpha）的標準手法：
    /// 先鋪滿 `color`，再用符號本身當 alpha 遮罩（`.destinationIn`）裁掉輪廓外的部分。
    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        rect.fill()
        image.draw(in: rect, from: rect, operation: .destinationIn, fraction: 1.0)
        result.unlockFocus()
        return result
    }
}
