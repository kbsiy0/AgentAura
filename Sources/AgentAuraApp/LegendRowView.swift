import SwiftUI
import AppKit
import AuraCore

/// 面板底部常駐圖例列（R7）：四個色點＋標籤。spec §4.1／`2026-09-11-panel-visual-ab.md` §2 V1。
///
/// T15（V1 落地）：舊版的提示行（「八顆燈一起代表全部 session · 點色點改顏色」）拿掉，
/// 改成 ⓘ 的 `.help()` tooltip——**四個標籤本身（錯誤／等你／執行中／已完成）不受影響，
/// 一律保留**：`.help` tooltip 在離屏渲染下驗不到，不能只靠它傳遞語意，被拿掉的只是額外
/// 那句解釋句。
///
/// A8（T11 commit3）：**不畫「重設」**——D-a 把它搬進 Options（「重設顏色」列）的理由是
/// 「一年按一次卻永遠佔一格且多半是灰的」，但舊的這顆一直沒拿掉，兩處重複存在。
/// `LegendRowNoResetSourceScanTests` 守著：這個檔不得再送出重設顏色那個 `PanelAction`。
struct LegendRowView: View {
    let legend: [LegendItem]
    /// 沒有預設值：忘了傳要是編譯錯，不是靜默沒反應（T04，D-j）。
    let onAction: (PanelAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(legend) { item in
                // 整組（色點＋標籤）都可點、都換游標——persona S2-5：只有 20pt 色點可點時，
                // 每項只有 36–45% 的面積有反應，而較大較好讀的那一半是死的。
                // 改用真的 `Button`（`.borderless`，視覺與舊版 tapGesture 等價、無系統
                // chrome）：T04 的 `panelViewForwardsAction` 要建真的
                // PanelView 真的觸發——`.onTapGesture` 實測不會橋接成任何可從測試找到並觸發的
                // AppKit 控制項（`.buttonStyle(.plain)` 也不會，只有 `.bordered`／`.borderless`
                // 這類走原生 control 繪製的 style 才會），`Button(.borderless)` 會
                // （`performClick(nil)`）。
                Button {
                    onAction(.pickColor(item.activity))
                } label: {
                    HStack(spacing: 4) {
                        LegendDot(item: item)
                        Text(item.label).font(.system(size: 11))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                // set() 而非 push/pop：popover 可能在游標停在上面時整個消失（點外面／鎖屏），SwiftUI 不保證補
                // onHover(false)，push 沒配對的 pop 會讓指標全 app 卡在手形（review-t0406 I4）。
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
                .onDisappear { NSCursor.arrow.set() }
                .help("改「\(item.label)」的顏色")
                .accessibilityLabel("改「\(item.label)」的顏色")
            }
            Spacer(minLength: 0)
            // T15：提示行拿掉，改 ⓘ 的 tooltip——**不是** `Button`：純資訊、沒有對應的
            // `PanelAction` 可送，包成 Button 只會有一顆按鈕點下去什麼都不會發生。
            // E16（/simplify 波次2）：這是設計決定，不再是為了配合
            // `panelViewForwardsAction` 的按鈕總數斷言（該測試已改成點遍按鈕比對動作
            // 集合，不再數總數）——如果之後 ⓘ 真的需要可點的行為，加 `Button` 不會讓
            // 那條測試無故變紅。
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help(Text("八顆燈一起代表全部 session · 點色點改顏色"))
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
    }
}

/// 單個圖例色點：10pt 視覺圓佔 20pt（D-k）；互動掛在外層「色點＋標籤」整組上。
///
/// T19 配套 B（`DotRing`）：色點加一圈細邊——改完預設色為白之後，淺色卡片背景上的白色
/// 色點沒有邊線會直接消失（跟背景同色）。見 `DotRing` 的理由。只加邊線，不改 `.frame`
/// 的兩層尺寸——視覺大小與既有 20pt 命中區都不受影響。
private struct LegendDot: View {
    let item: LegendItem

    var body: some View {
        Circle()
            .fill(Color(rgba: item.color))
            .overlay(DotRing())
            .frame(width: 10, height: 10)
            .frame(width: 20, height: 20)
    }
}

/// T19 配套 B：色點統一加的細邊，`LegendDot`／`PanelRowView` 共用同一份定義
/// （避免兩處各挑一個透明度，日後對不上）。
///
/// `Color.primary.opacity(0.35)`——不是 `.separator`：這個 view 被
/// `RenderPinned`／`OffscreenRender` 這種不建真 `NSVisualEffectView` 的離屏 harness
/// 渲染，`.separatorColor` 那類靠 vibrancy 混色的語意色在沒有真材質層時解析結果不保證
/// 可預期（review：像素 gate 需要能手算的期望值）；`.primary` 在這個 harness 下已經被
/// 其他像素 gate 驗證過會解析成具體不透明色（labelColor：淺色近黑、深色近白），
/// 可以手算期望的疊色。淺色下 0.35 透明黑疊白＝約 `#a6a6a6`，邊線本身對白底有感的對比
/// （不是 1:1）；深色下 0.35 透明白疊在已經是白色的色點邊緣＝幾乎融進色點本身，
/// 不會變成一圈刺眼白框（team-lead 的兩個限制都滿足）。
struct DotRing: View {
    var body: some View {
        Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
    }
}
