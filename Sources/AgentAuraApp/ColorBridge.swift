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
    /// E13（/simplify 波次2，reuse#13）：`alpha` override——`LEDStripView` 需要把
    /// `rgba.a` 換成動畫曲線算出來的瞬時值（同 `Color.init(rgba:ignoringAlpha:)`
    /// 「要換掉 alpha」這個既有需求），原本繞過這裡自己手寫 `NSColor(srgbRed:...)`，
    /// 讓「RGBA → 色彩型別」的轉換多了第二份、sRGB 這個選擇要記兩處。
    convenience init(rgba: RGBA, alpha: Double? = nil) {
        self.init(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: alpha ?? rgba.a)
    }

    /// `IconDrawing` conformer 的 tint（`/simplify` icon-shapes 波次，reuse#3）。
    ///
    /// D-2：**顏色與 alpha 全部來自 `IconAppearance`**——App 層不自己 switch activity、
    /// 不自己算曲線。`LEDStripView` 與 `SFSymbolIconView` 原本各寫一份
    /// `c.a * AnimationCurve.alpha(...)`；`appLayerNeverSwitchesOnIconAnimation` 那條
    /// 來源掃描守的是「App 層不得自己 switch 動畫種類」，抓不到「兩份公式其中一份被改」。
    /// 每多一個造型 conformer 就多一份，所以收口在這裡。
    ///
    /// （該掃描比對原始碼字面且**不濾註解**，所以這段刻意不寫出它要抓的那個 case 字面。）
    convenience init(appearance: IconAppearance, phase: Double) {
        self.init(rgba: appearance.color, alpha: appearance.drawingAlpha(phase: phase))
    }
}
