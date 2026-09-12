import SwiftUI
import AuraCore

/// spec §3.3／§4.3（D-a）：底部常駐 utility bar——左健康 chip ＋版本、右「Options ⌄」。
///
/// **不得自己 switch `InstallState`**（N9）：chip 顏色／文字讀 `model.install.healthTone`／
/// `.healthLabel`——這兩個是 `AuraCore` 已經窮盡推導好的 derived property，這裡只是顯示，
/// 不是再判一次「哪一種狀態該顯示什麼」。
struct PanelFooterView: View {
    let model: PanelModel
    /// 沒有預設值：忘了傳要是編譯錯，不是靜默沒反應（同 `PanelView.onAction` 的理由，D-j）。
    let onAction: (PanelAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(rgba: model.install.healthTone.color))
                .frame(width: 8, height: 8)
            Text("\(model.install.healthLabel) · v\(model.version)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button {
                onAction(.toggleOptions)
            } label: {
                Text(model.optionsExpanded ? "Options ⌃" : "Options ⌄")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
        }
        // T15（V1 token「footer 24pt」）：固定高度，跟其餘常駐列（圖例 24pt）對齊節奏。
        .padding(.horizontal, 14)
        .frame(height: 24)
    }
}
