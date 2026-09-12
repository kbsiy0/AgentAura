import SwiftUI
import AuraCore

/// T11 commit1（S0-1）：主要動作（「接上」／「改指向這個 App」）的填色底樣式。
///
/// **仍是 `.borderless`，不是 `.bordered`／`.borderedProminent`**——理由不變（見
/// `LegendRowView` 的既有結論）：後兩者在離屏渲染下把真正的 `NSButton` 包進
/// `_FocusRingView`，沒有真 `NSWindow`／首次 layout pass 時該容器 `subviews` 是空的，
/// `allButtons` 遞迴走訪找不到，G8(b) 的按鈕計數測試會少算一顆。
///
/// **零 gate 風險的修法**：`.borderless` 配上**自訂 `label:`**（不是 `Button(String)`
/// 這種標題式建構）——persona 實測量到兩者離屏渲染結果天差地遠：標題式在沒有真
/// `NSWindow`／key state 時只拿系統次要前景色（渲成 #7f7f7f，4.00:1，跟旁邊的說明句
/// 同色），自訂 `label:` 則是 SwiftUI 自己把 view 樹畫上去——同 `LegendRowView`／
/// `PanelFooterView` 的「Options ⌄」既有寫法，兩者都被 `allButtons` 遞迴找到並可
/// `performClick(nil)`。
///
/// **色值寫死，不吃 `Color.accentColor`**（同 `HealthTone` 的理由）：使用者可在系統設定
/// 自選 accent color（黃／綠等淺色對白字對比可能 < 3:1），寫死才能保證「深淺兩種
/// appearance 各自量」都過 4.5:1——這兩個常數本身不隨 `NSAppearance` 變化，兩種
/// appearance 下的對比數字因此恆等。`#0060df` 對純白字：WCAG 相對亮度對比 ≈ 5.61:1
/// （`CTAAffordanceRenderTests.ctaFillTextContrastMeetsWCAG_AA` 釘住這個數字，
/// 门檻抓 4.5 留邊際）。
enum CTAButtonStyle {
    static let fill = RGBA(r: 0x00 / 255, g: 0x60 / 255, b: 0xdf / 255, a: 1)
    static let text = RGBA(r: 1, g: 1, b: 1, a: 1)
}

/// CTA 按鈕的填色標籤。`compact` 給 `.banner` 那種窄條用（`ConnectCTABannerView`）——
/// 同一組色值、字級與內距縮小，避免把只有 6pt 垂直內距的窄條撐爆。
struct CTAButtonLabel: View {
    let text: String
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 11 : 12, weight: .bold))
            .foregroundStyle(Color(rgba: CTAButtonStyle.text))
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.vertical, compact ? 4 : 8)
            .background(Color(rgba: CTAButtonStyle.fill),
                       in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
