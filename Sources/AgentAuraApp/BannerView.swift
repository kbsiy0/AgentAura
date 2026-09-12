import SwiftUI
import AuraCore

/// spec §3.3（S1-P3/P4）：接上成功／已接上／已移除掛載／錯誤的可關閉窄條。
/// 只讀 `banner.text`／`banner.kind`——文案本身只准經 `PanelBanner` 的 static 建構式產生
/// （見 `PanelBanner` 的文件），這裡不手搓字串。
struct BannerView: View {
    let banner: PanelBanner
    /// 沒有預設值：忘了傳要是編譯錯（D-j）。
    let onAction: (PanelAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(banner.text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            // A7(b)（T11 commit3）：視覺仍是 9pt 小叉，可點區放大到 20×20pt——同
            // `LegendRowView.LegendDot` 既有的「10pt 視覺／20pt 命中」做法（persona 量到
            // 舊版只有 10×10pt，低於 macOS 舒適門檻）。`.contentShape(Rectangle())` 讓整個
            // 20×20 的 frame 都可點，不是只有畫出線條的那幾個像素。
            Button {
                onAction(.dismissBanner)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .bannerChrome(background: background)
    }

    private var background: Color {
        banner.kind == .error ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.12)
    }
}
