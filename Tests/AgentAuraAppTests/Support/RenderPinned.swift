import AppKit
import Foundation
import AuraCore

/// T01 helper（項目 3，S0-Q2）：所有新離屏渲染共用的前提。釘 `NSAppearance`、
/// 固定畫布、回 `Bitmap`，並內建**前提斷言**（非背景色像素 > 門檻，預設 2000）。
/// G6／G8 一律經它，不准各測試自己決定 appearance。
///
/// 實測依據：不釘 appearance 在 Dark 機器渲淺底，文字 0 px、非白像素只有 224——
/// 一個 harness 設定同時廢掉 G6／G8。
enum RenderPinned {
    struct PreconditionFailure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor
    static func render(_ view: NSView, appearance: NSAppearance.Name, canvas: NSSize,
                       over background: NSColor = .white,
                       minimumForegroundPixels: Int = 2000) throws -> OffscreenRender.Bitmap {
        view.appearance = NSAppearance(named: appearance)
        view.frame = NSRect(origin: .zero, size: canvas)
        let bitmap = try OffscreenRender.render(view, over: background)

        let bg = background.usingColorSpace(.sRGB) ?? background
        let bgColor = RGBA(r: bg.redComponent, g: bg.greenComponent, b: bg.blueComponent, a: 1)
        let backgroundPixels = bitmap.count(near: bgColor)
        let total = bitmap.context.width * bitmap.context.height
        let foreground = total - backgroundPixels
        guard foreground > minimumForegroundPixels else {
            throw PreconditionFailure(description: """
                離屏渲染前提斷言失敗：非背景色像素只有 \(foreground)（門檻 > \(minimumForegroundPixels)，
                appearance=\(appearance.rawValue)，canvas=\(canvas)）。
                harness 可能空轉——appearance 沒釘住／view 沒真的畫出內容，這必須大聲紅，不能安靜綠。
                """)
        }
        return bitmap
    }
}
