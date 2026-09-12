import SwiftUI
import AuraCore

/// spec §3.3／§3.1.1：`connectCTAStyle == .fullPanel`（沒有活著的列、且 `showsConnectCTA`）
/// 時的整版 CTA。標題已經由 `PanelView` 頂端的 `Text(model.title)` 顯示過（S1-1：兩者
/// 對這個 view 涵蓋的每一種狀態恆相等），這裡只印說明句／按鈕——說明句
/// （`model.notConnectedDetailText`）與按鈕文案／action（`model.connectCTAText`／
/// `model.connectCTAAction`）都是 AuraCore 已經窮盡推導好的 derived property
/// （§3.1.1 的 affordance→CTA 表），這裡不再自己 switch `InstallState`（N9／S2-6）。
struct NotConnectedView: View {
    let model: PanelModel
    /// 沒有預設值：忘了傳要是編譯錯（D-j）。
    let onAction: (PanelAction) -> Void

    var body: some View {
        VStack(spacing: 10) {
            // S1-1（T13 收尾）：這裡先前無條件印一次 install 的健康標籤——但 `PanelView`
            // 頂端的 `Text(model.title)` 對這個 view 會渲染的**每一種**狀態都已經等於
            // 同一句（非 connected 時 `PanelModel.title(for:install:)` 直接回傳它，
            // `TooltipAndTitleConsistencyTests` 窮盡證明過），所以這裡再印一次是同一張畫面
            // 說了第二次同一句話；連同 footer chip 是第三次
            // （persona r2 S1-1：「A2-broken-title-light.png」六行裡三行同句）。
            // 標題已經在頂端，這裡不重畫，直接進說明文字（`notConnectedDetailText`，
            // 單一 oracle，見 `PanelModel+NotConnectedDetail.swift`——**不得**改回直接讀
            // `install` 的健康標籤，`NotConnectedViewNoDuplicateHealthLabelSourceScanTests`
            // 這條 gate 會紅）。
            Text(model.notConnectedDetailText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let cta = model.connectCTAText, let action = model.connectCTAAction {
                // T11 commit1（S0-1）：自訂 `label:` 的 `.borderless`——見 `CTAButtonStyle`
                // 的文件。理由不變：`.bordered`／`.borderedProminent` 在離屏渲染下把真正的
                // NSButton 包進 `_FocusRingView`，沒有真 NSWindow 時該容器 `subviews` 是空的
                // （`allButtons` 遞迴走訪找不到），G8(b) 的按鈕計數測試會少算一顆。
                // 差別是**標題式 `Button(cta)` 换成自訂 label**：persona 實測標題式在離屏
                // 渲染下只拿系統次要前景色（#7f7f7f，4.00:1，跟上面的說明句同色，看不出
                // 哪裡可按），自訂 label 才能真的畫出填色底＋足夠對比的文字。
                Button {
                    onAction(action)
                } label: {
                    CTAButtonLabel(text: cta)
                }
                .buttonStyle(.borderless)
            }
            Button("這是什麼？") { onAction(.openHelp) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
        // T15（V1 落地）：跟 `PanelView.sessionsCard` 同一種分組卡片——圓角 10pt／1pt hairline
        // 邊、內距 20pt、`minHeight` 從 160 調成 V1 token 的 140（真渲圖已評過的數字）。
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 140)
        .panelCard(filled: false)
    }
}
