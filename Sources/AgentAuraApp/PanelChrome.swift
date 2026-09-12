import SwiftUI

/// E11（/simplify 波次2，reuse#7,#8）：V1 卡片外框與窄條 chrome 的共用樣式——原本各自
/// 散在三個檔案（`PanelView.sessionsCard`／`NotConnectedView`／`OptionsSectionView`），
/// 一個是兩個（`BannerView`／`ConnectCTABannerView`），調一個數字（圓角、邊色、線寬、
/// 內距、窄條節奏）要記得同步改；漏一處就是只有真渲圖才看得出來的漂移。
extension View {
    /// V1 token：圓角 10pt 卡片。`filled == true` 用淡背景填色（Options 這種「設定區」
    /// 降一級視覺重量，見 `OptionsSectionView` 的 doc comment）；`false` 用 1pt hairline
    /// 邊（`sessionsCard`／`NotConnectedView` 這種「內容區主角」）。
    func panelCard(filled: Bool) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            if filled {
                shape.fill(Color.primary.opacity(0.04))
            } else {
                shape.strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .padding(.horizontal, 12)
    }

    /// V1 token：窄條 chrome（`BannerView`／`ConnectCTABannerView` 同一個形狀——一行字 ＋
    /// 一顆按鈕，高度節奏與內距相同，差別只有底色）。
    func bannerChrome(background: Color) -> some View {
        self.padding(.horizontal, 12).padding(.vertical, 6).background(background)
    }
}
