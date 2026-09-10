import SwiftUI
import AppKit
import AuraCore

/// 面板底部常駐圖例列（R7）：四個色點＋標籤＋提示行＋「重設」。spec §4.1。
struct LegendRowView: View {
    let legend: [LegendItem]
    let isDefaultPalette: Bool
    let onPick: (Activity) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 12) {
                ForEach(legend) { item in
                    // 整組（色點＋標籤）都可點、都換游標——persona S2-5：只有 20pt 色點可點時，
                    // 每項只有 36–45% 的面積有反應，而較大較好讀的那一半是死的。
                    HStack(spacing: 4) {
                        LegendDot(item: item)
                        Text(item.label).font(.system(size: 11))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(item.activity) }
                    // set() 而非 push/pop：popover 可能在游標停在上面時整個消失（點外面／鎖屏），SwiftUI 不保證補
                    // onHover(false)，push 沒配對的 pop 會讓指標全 app 卡在手形（review-t0406 I4）。
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    }
                    .onDisappear { NSCursor.arrow.set() }
                    .help("改「\(item.label)」的顏色")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("改「\(item.label)」的顏色")
                    .accessibilityAddTraits(.isButton)
                }
            }
            HStack {
                // persona S2-6：關鍵那半句是「與 session 數無關」；S2-4：10pt 在淺色只有 3.95:1，改 11pt
                Text("燈固定 8 顆，與 session 數無關 · 點色點可改顏色")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("重設") { onReset() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .disabled(isDefaultPalette)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

/// 單個圖例色點：10pt 視覺圓佔 20pt（D-k）；互動掛在外層「色點＋標籤」整組上。
private struct LegendDot: View {
    let item: LegendItem

    var body: some View {
        Circle()
            .fill(Color(rgba: item.color))
            .frame(width: 10, height: 10)
            .frame(width: 20, height: 20)
    }
}
