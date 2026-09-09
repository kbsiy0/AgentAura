import AppKit
import Foundation
import AuraCore

/// 離屏繪製共用 harness（不是測試，是 `Tests/AgentAuraAppTests` 共用工具）。
///
/// spec §6：自建 sRGB `CGContext`——**不用** `bitmapImageRepForCachingDisplay`
/// （實測它回裝置色彩空間，數字不可跨機重現）。
enum OffscreenRender {

    enum SampleError: Error, CustomStringConvertible {
        case outOfBounds(point: CGPoint, pixel: (x: Int, y: Int), size: (w: Int, h: Int))
        case noData
        case contextCreationFailed
        /// 取樣到非不透明像素：本 harness 一律先鋪不透明背景，讀到 α<255 代表有人改疊 `.clear`、
        /// 或 buffer 是 premultiplied 而沒還原——兩種都會讓數字靜默錯，所以 throw（review Minor 1）。
        case translucentSample(point: CGPoint, alpha: Double)

        var description: String {
            switch self {
            case let .outOfBounds(point, pixel, size):
                return "取樣點越界：view 座標 \(point) → 像素 (\(pixel.x), \(pixel.y))，" +
                    "畫布 \(size.w)×\(size.h)（sRGB，@2x）"
            case .noData: return "CGContext 沒有可讀的 pixel buffer"
            case let .translucentSample(point, alpha): return "取樣點 \(point) 的 α=\(alpha) 不是 1.0 —— 背景沒鋪滿或 premultiplied 未還原"
            case .contextCreationFailed: return "建不出 sRGB CGContext"
            }
        }
    }

    /// 離屏繪製結果。`scale` 固定 2（@2x）。
    struct Bitmap {
        let context: CGContext
        let scale: CGFloat
        let viewSize: CGSize

        /// view 座標 → 像素（×scale、y 翻轉：CGBitmapContext 的 row 0 在畫面最上方）。
        /// **越界一律 throw**，不回一個看起來像顏色的值（spec §5）。
        func pixel(at point: CGPoint) throws -> RGBA {
            let width = context.width
            let height = context.height
            let px = Int((point.x * scale).rounded())
            let pyFromTop = Int(((viewSize.height - point.y) * scale).rounded())
            guard px >= 0, px < width, pyFromTop >= 0, pyFromTop < height else {
                throw SampleError.outOfBounds(point: point, pixel: (px, pyFromTop), size: (width, height))
            }
            guard let data = context.data else { throw SampleError.noData }
            let bytesPerRow = context.bytesPerRow
            let offset = pyFromTop * bytesPerRow + px * 4
            let buf = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
            guard buf[offset + 3] == 255 else {
                throw SampleError.translucentSample(point: point, alpha: Double(buf[offset + 3]) / 255)
            }
            return RGBA(r: Double(buf[offset]) / 255,
                       g: Double(buf[offset + 1]) / 255,
                       b: Double(buf[offset + 2]) / 255,
                       a: Double(buf[offset + 3]) / 255)
        }
    }

    /// 疊在 `background` 上離屏繪製一次。`view.frame` 必須先設好（決定 bounds）。
    @MainActor
    static func render(_ view: NSView, over background: NSColor) throws -> Bitmap {
        let scale: CGFloat = 2
        let size = view.bounds.size
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw SampleError.contextCreationFailed
        }
        ctx.scaleBy(x: scale, y: scale)

        let bg = background.usingColorSpace(.sRGB) ?? background
        ctx.setFillColor(red: bg.redComponent, green: bg.greenComponent,
                         blue: bg.blueComponent, alpha: bg.alphaComponent)
        ctx.fill(CGRect(origin: .zero, size: size))

        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        view.displayIgnoringOpacity(view.bounds, in: nsContext)

        return Bitmap(context: ctx, scale: scale, viewSize: size)
    }

    // MARK: - WCAG 對比

    private static func linearize(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func relativeLuminance(_ c: RGBA) -> Double {
        0.2126 * linearize(c.r) + 0.7152 * linearize(c.g) + 0.0722 * linearize(c.b)
    }

    /// WCAG 相對亮度對比。
    static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        let (hi, lo) = la >= lb ? (la, lb) : (lb, la)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// 對 phase 掃 `AnimationCurve.alpha` 的 argmax，不在測試寫死 0.5／0。
    static func peakPhase(of animation: IconAnimation, resolution: Int = 1000) -> Double {
        var best = 0.0
        var bestAlpha = -Double.infinity
        for i in 0...resolution {
            let phase = Double(i) / Double(resolution)
            let alpha = AnimationCurve.alpha(for: animation, phase: phase)
            if alpha > bestAlpha {
                bestAlpha = alpha
                best = phase
            }
        }
        return best
    }

    /// 對 phase 掃 `AnimationCurve.alpha` 的 argmin——`plateGuaranteesContrast` (d) 只印谷值，不設門檻。
    static func troughPhase(of animation: IconAnimation, resolution: Int = 1000) -> Double {
        var best = 0.0
        var bestAlpha = Double.infinity
        for i in 0...resolution {
            let phase = Double(i) / Double(resolution)
            let alpha = AnimationCurve.alpha(for: animation, phase: phase)
            if alpha < bestAlpha {
                bestAlpha = alpha
                best = phase
            }
        }
        return best
    }

    /// 像素 gate 的預期值：`c` 以 `c.a × curveAlpha` 疊在 `bg` 上——palette 的 `a` 因此也被驗到。
    static func expected(_ c: RGBA, curveAlpha: Double, over bg: RGBA) -> RGBA {
        let alpha = c.a * curveAlpha
        return RGBA(r: c.r * alpha + bg.r * (1 - alpha),
                   g: c.g * alpha + bg.g * (1 - alpha),
                   b: c.b * alpha + bg.b * (1 - alpha),
                   a: 1)
    }
}

extension NSRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension RGBA {
    /// 兩個 sRGB 顏色的最大分量差（0…1）——像素 gate 用它跟 `2/255` 之類的門檻比較。
    func maxComponentDelta(_ other: RGBA) -> Double {
        max(abs(r - other.r), abs(g - other.g), abs(b - other.b), abs(a - other.a))
    }
}
