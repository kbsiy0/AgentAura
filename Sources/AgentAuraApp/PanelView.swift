import SwiftUI
import AuraCore

struct PanelView: View {
    let model: PanelModel
    var onPick: (Activity) -> Void = { _ in }
    var onReset: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4))

            if model.rows.isEmpty {
                Text("沒有活著的 session")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.rows) { row in
                            PanelRowView(row: row, palette: model.palette)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            LegendRowView(legend: model.legend, isDefaultPalette: model.isDefaultPalette,
                        onPick: onPick, onReset: onReset)
        }
        .frame(width: 380)
    }
}

struct PanelRowView: View {
    let row: PanelRow
    let palette: IconPalette

    /// 沒有預設值：`PanelView` 忘了傳 palette 要是編譯錯，不是靜默畫預設色（review-t0406 I1）。
    init(row: PanelRow, palette: IconPalette) {
        self.row = row
        self.palette = palette
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            // 列色點只借色相，不借 alpha——idle 的 a=0.35 在面板上只是「看不見」（review-t0406 I3：白底 1.31:1）
            Circle().fill(Color(rgba: palette[row.activity], ignoringAlpha: true))
                .frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.projectName).font(.system(size: 12, weight: .semibold))
                    Text(row.meta).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(row.headline)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(row.activity == .error ? .red : .primary)
                    .lineLimit(1).truncationMode(.middle)
                if !row.detail.isEmpty || row.isEnded {
                    Text([row.detail, row.isEnded ? "已結束 · \(row.relativeTime)" : row.relativeTime]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }
}
