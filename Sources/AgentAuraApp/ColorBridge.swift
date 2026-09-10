import SwiftUI
import AppKit
import AuraCore

/// `RGBA` ⇄ SwiftUI／AppKit 顏色型別的小橋接。純轉換，不是本 change 的受測邏輯——
/// 兩個型別的正確性各自由消費端的像素／色板 gate 間接驗證。
extension Color {
    /// `ignoringAlpha`：面板上的色點只借色相（idle 的 0.35 是給 LED 的「該暗」，在面板圓點只是看不見）。
    init(rgba: RGBA, ignoringAlpha: Bool = false) {
        self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: ignoringAlpha ? 1 : rgba.a)
    }
}

extension NSColor {
    convenience init(rgba: RGBA) {
        self.init(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }
}
