import SwiftUI
import AuraCore

/// spec §4.3（D-b）：面板內展開的 Options 區。**只從 `OptionsMenuModel.rows(...)` 取列**
/// （S1-Q6：不得自己列硬編的列——那會讓 G10 守的 model 與畫面漂移，model 改了畫面不會變）。
///
/// T15（V1 落地，team-lead 看 T14 渲圖抓到的毛病之三）：Options 與 session 卡片先前視覺重量
/// 相同，資料沒有壓過設定。這裡**降一級**——不用邊框，只留淡背景（`Color.primary.opacity(0.04)`）；
/// 對照 `PanelView.sessionsCard` 仍保留 1pt hairline 邊：內容區是主角，設定區是背景。
///
/// A10（T11 commit3）：每列垂直內距先前從 6pt 砍半到 3pt；T15 改用 V1 token 的 28pt 固定列高
/// （含左側 20pt 圖示欄），`OptionsPanelSizing` 的推導常數已重新量過（見該檔 doc comment）。
struct OptionsSectionView: View {
    let model: PanelModel
    /// 沒有預設值：忘了傳要是編譯錯（D-j）。
    let onAction: (PanelAction) -> Void

    private var rows: [OptionsRow] {
        OptionsMenuModel.rows(install: model.install, launchAtLogin: model.launchAtLogin,
                              isDefaultPalette: model.isDefaultPalette,
                              systemReduceMotion: model.systemReduceMotion, userReduceMotion: model.userReduceMotion,
                              iconPlate: model.iconPlate, palette: model.palette)
    }

    var body: some View {
        // E5（/simplify 波次2，eff#5）：`rows` 是 computed property——`ForEach` 迴圈裡原本
        // 每次比對 `rows[index - 1].group` 都會重新求值一整趟 `OptionsMenuModel.rows(...)`
        // （9–10 個 `OptionsRow` 配置＋字串插值＋`lightBarWarning` 對每個 activity 跑一次
        // WCAG `pow`），9 列等於 8 趟多餘的完整重建。綁一次區域變數就好，值不變。
        let rows = self.rows
        VStack(alignment: .leading, spacing: 0) {
            // C1（team-lead 收尾）：分隔線只畫在群組交界，不是每一列都畫——九列全隔開
            // 會變成一面「列牆」（Amphetamine 只在群組之間放分隔線）。第一列前面不用再畫。
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0, rows[index - 1].group != row.group { Divider().padding(.leading, 32) }
                OptionsRowContent(row: row, onAction: onAction)
            }
            // §3.1：connected(owner: .external, _) 時多一行灰字寫掛載目標——自己的群組，
            // 前面補一條分隔線（不再依賴舊版「每列後面都有」留下的那一條）。
            //
            // 波次2接線（reuse#3,4／altitude#5）：文字改讀 `PanelModel.mountTargetNote`
            // （B6，AuraCore）——這句話原本在這裡跟 `PanelModel.connectCTASubtitle`／
            // `notConnectedDetailText` 各組一份，且已經漂成「目前指向：」（跟另外兩處
            // 「現有掛載指向：」不同）。「要不要顯示」仍由 view 自己讀 `isConnected`
            // （不 switch `InstallState`，N9／S2-6）＋ note 是否非 nil 決定。
            if model.install.isConnected, let target = model.mountTargetNote {
                Divider().padding(.leading, 32)
                Text(target)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 4)
            }
        }
        .panelCard(filled: true)
    }
}

/// internal（不是 private）：`OptionsDividerGroupingTests` 要能用同一個列內容元件，
/// 組出「舊版每列都有分隔線」的對照組，才能像素驗證分組後線真的變少（不是只有型別層算對）。
struct OptionsRowContent: View {
    let row: OptionsRow
    let onAction: (PanelAction) -> Void

    var body: some View {
        if let toggleValue = row.toggleValue {
            HStack(alignment: row.subtitle == nil ? .center : .firstTextBaseline, spacing: 8) {
                OptionsRowIconView(kind: row.action.kind)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.system(size: 13))
                    // B5：系統已強制「減少動態」時，開關顯示開且 disabled——這行字說明為什麼
                    // 按不動，不然又是一次「畫面沒說清楚」（tooltip／CTA 說謊病族的同類）。
                    if let subtitle = row.subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // A9（T11 commit3）：team-lead 實測離屏渲染下 `Toggle` 的 on／off 兩張圖完全
                // 一樣（診斷量到 0 px 差異）——同 CLAUDE.md 的 gate 哲學：渲不出來的狀態
                // 指示，我們就沒有辦法驗證使用者看不看得到。`Toggle` 保留（真的觸發互動），
                // 但狀態另外自己畫一個字樣＋顏色，兩者都是渲染保證畫得出來的。
                Text(toggleValue ? "開" : "關")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(toggleValue ? Color(rgba: HealthTone.ok.color) : .secondary)
                Toggle("", isOn: Binding(get: { toggleValue }, set: { _ in onAction(row.action) }))
                    .labelsHidden()
                    .disabled(row.isDisabled)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 28)
        } else {
            Button {
                onAction(row.action)
            } label: {
                HStack(spacing: 8) {
                    OptionsRowIconView(kind: row.action.kind)
                    Text(row.title).font(.system(size: 13))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(row.isDisabled)
            .padding(.horizontal, 14)
            .frame(minHeight: 28)
        }
    }
}

/// T15：Options 每一列都要有圖示——team-lead 看 T14 渲圖抓到的毛病之一（開機自動啟動／
/// 減少動態兩列先前留空，看起來像壞掉）。`systemName(for:)` 對 `PanelActionKind` 全 case
/// 窮盡（回 `String` 不是 `String?`）：四個非選單 case（`OptionsMenuModel.nonMenuKinds`）
/// 不會真的出現在 Options 列裡，仍給實際值只是讓 switch 保持窮盡，不是留給某個真的會被
/// 畫出來的空白列。
private struct OptionsRowIconView: View {
    let kind: PanelActionKind

    var body: some View {
        Image(systemName: Self.systemName(for: kind))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 20)
    }

    private static func systemName(for kind: PanelActionKind) -> String {
        switch kind {
        case .openHelp: "questionmark.circle"
        case .setLaunchAtLogin: "power"
        case .setReduceMotion: "tortoise"
        case .setIconPlate: "rectangle.on.rectangle"
        case .resetColors: "arrow.counterclockwise"
        case .connect: "arrow.triangle.2.circlepath"
        case .recheckHook: "arrow.clockwise"
        case .disconnect: "trash"
        case .uninstall: "trash.fill"
        case .about: "info.circle"
        case .reportIssue: "exclamationmark.bubble"
        case .quit: "power.circle"
        case .pickColor: "paintpalette"
        case .toggleOptions: "ellipsis.circle"
        case .dismissBanner: "xmark"
        case .replaceExternalMount: "arrow.2.squarepath"
        }
    }
}
