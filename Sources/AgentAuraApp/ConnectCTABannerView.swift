import SwiftUI
import AuraCore

/// spec §3.3（S1-P4 的一半，`connectCTAStyle == .banner`）：有活著的列時，CTA 不吃掉整個
/// 面板——縮成列上方一條窄條。與 `BannerView` 同一個形狀（一行字 ＋ 一顆按鈕），差別是
/// 這條不會被關掉（沒有 `dismissBanner`，狀態變了它自己會消失）。
///
/// 只讀 `PanelModel` 已經窮盡推導好的 `connectCTAText`／`connectCTAAction`（§3.1.1）——
/// 不自己 switch `InstallState` 或 `affordance`（N9／S2-6）。呼叫端（`PanelView`）保證
/// 只在兩者皆非 nil 時才建這個 view（`connectCTAStyle == .banner` ⟺ `showsConnectCTA`）。
struct ConnectCTABannerView: View {
    let label: String
    /// A5（T11 commit3）：`.fullPanel` 版（`NotConnectedView`）一直都有「現有掛載指向：X」，
    /// 這個窄條先前沒有——P3（整夜跑 pipeline、有活著的列）看的正是這一版，看不到自己的
    /// 掛載指向哪裡。`nil` 時不畫（`.connect` affordance 沒有副標可顯示）。
    let subtitle: String?
    let ctaText: String
    let action: PanelAction
    /// 沒有預設值：忘了傳要是編譯錯（D-j，同本檔其餘 view 的理由）。
    let onAction: (PanelAction) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            // T11 commit1（S0-1）：自訂 `label:` 的 `.borderless`（`compact: true`）——
            // 見 `CTAButtonStyle` 的文件。理由不變（T07 平台實測，見 CLAUDE.md「這個
            // codebase 的 gate 哲學」）：`.bordered`／`.borderedProminent` 在離屏渲染下
            // 把真正的 NSButton 包進 `_FocusRingView`，沒有真 NSWindow 時該容器
            // `subviews` 是空的，遞迴走訪找不到。持證標題式 `Button(ctaText)` 換成自訂
            // label：persona 實測這個窄條左邊的狀態文字與右邊的按鈕最深像素**都是
            // 112**——看不出哪一半可以按，填色底才能一眼分開。
            Button {
                onAction(action)
            } label: {
                CTAButtonLabel(text: ctaText, compact: true)
            }
            .buttonStyle(.borderless)
        }
        .bannerChrome(background: Color.accentColor.opacity(0.12))
    }
}
