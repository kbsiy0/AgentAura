import SwiftUI
import AuraCore

struct PanelView: View {
    let title: String
    let rows: [PanelRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4))

            if rows.isEmpty {
                Text("沒有活著的 session")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            PanelRowView(row: row)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(width: 380)
    }
}

struct PanelRowView: View {
    let row: PanelRow

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(Self.color(row.activity))
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

    static func color(_ a: Activity) -> Color {
        switch a {
        case .idle:    return .secondary
        case .working: return .blue
        case .waiting: return .orange
        case .done:    return .green
        case .error:   return .red
        }
    }
}
