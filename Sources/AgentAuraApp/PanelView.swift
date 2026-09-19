import SwiftUI
import AuraCore

/// T15（app-shell）：V1「macOS 原生感」落地——`docs/superpowers/specs/2026-09-11-panel-visual-ab.md`
/// §2 V1，使用者真渲圖 A/B 選定，§6 有決策紀錄。分組卡片＋字型層級＋原生材質，取代舊版
/// 「不透明底、無層級、無間距節奏」。
///
/// **背景交回 popover**（`.background(Color.clear)`）：離屏渲染沒有真 `NSWindow`，
/// 無法證明真 vibrancy 有沒有透出來——這條靠真 app 上肉眼確認（commit message 已標記）。
/// 就算材質沒生效退回不透明底，文字全走 `.primary`／`.secondary`／`.tertiary` 這類語意色，
/// 不靠這行本身撐對比，所以有讀得清楚的 fallback。
struct PanelView: View {
    let model: PanelModel
    /// 沒有預設值：忘了傳 `onAction` 要是編譯錯，不是靜默沒反應（T04，D-j，
    /// 同 `PanelRowView.palette` 的理由）。
    let onAction: (PanelAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14).padding(.top, 12)

            // banner 依 §3.3 的優先序放在上方（`model.connectCTAStyle` 已經把 `.banner` 在
            // `effectiveBanner != nil` 時降級為 `.none`，兩者不會同時要求這塊空間）。
            // A7：讀 `effectiveBanner`（不是原始 `banner`）——`.connected` banner 在真的出現
            // 第一個 session 之後自動退場，這裡只是顯示層，不改寫 `AppDelegate` 存的原始狀態。
            if let banner = model.effectiveBanner {
                BannerView(banner: banner, onAction: onAction)
            }

            // A3：`.explainOnly` 沒有 CTA 按鈕，但一樣要走大版說明（`NotConnectedView` 在
            // `connectCTAText == nil` 時自然不畫按鈕，只印 chip 標題 ＋ `explanationDetail`）。
            if model.connectCTAStyle == .fullPanel || model.showsExplanationPanel {
                NotConnectedView(model: model, onAction: onAction)
            } else {
                // S1-P4 的一半：有活著的列時 CTA 不吃掉整個面板，縮成列上方一條窄條
                // （`connectCTAStyle == .banner` 依 `PanelModel` 的定義恆搭配非空 rows）。
                if model.connectCTAStyle == .banner,
                   let cta = model.connectCTAText, let action = model.connectCTAAction {
                    ConnectCTABannerView(label: model.install.healthLabel(model.language), subtitle: model.connectCTASubtitle,
                                        ctaText: cta, action: action, onAction: onAction)
                }
                if model.rows.isEmpty {
                    // A11（T11 A9–A11 批次）：讀 `model.emptyRowsMessage`，不再手搓
                    // 「沒有活著的 session」——那句字面跟頂端 `model.title`（connected 時走
                    // session 計數句子，空 session 也剛好是這句）一字不差，同一張畫面說了
                    // 兩次同一句話。
                    Text(model.emptyRowsMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    sessionsCard
                }
            }

            // T09（P1）：Codex 的提示永遠在 Claude 側內容**下面**——同一張畫面兩個 agent
            // 疊在一起時，使用者第一次看得懂哪個按鈕對應哪個 agent。`.unavailable`／
            // `.connected` 回 `EmptyView()`，這裡零版面代價（CX36）。
            CodexSectionView(model: model, onAction: onAction)

            LegendRowView(legend: model.legend, onAction: onAction, language: model.language)

            PanelFooterView(model: model, onAction: onAction)

            // A4：Options 展開插在 footer **下方**，不是上方——footer（含「Options ⌄」
            // 自己）的螢幕位置因此不隨展開狀態改變。persona 實測舊版把 Options 插在 footer
            // 上方，展開時 footer 被推下去 198pt，使用者第二下點擊（滑鼠沒動）會落在
            // accordion 第一列上，若那列是開關（`setLaunchAtLogin`）就是靜默誤觸。
            if model.optionsExpanded {
                OptionsSectionView(model: model, onAction: onAction)
            }
        }
        .padding(.bottom, 10)
        .frame(width: 380)
        // T22：`alignment: .top`——外層畫布（`NSHostingController.view.frame`）被提案一個
        // 跟這份內容理想高度不同的值時（resize 動畫的中繼畫格、螢幕空間不足），SwiftUI
        // 預設把內容**置中**塞進被提案的畫布，不是釘在頂端；置中會讓 footer 的螢幕 Y
        // 跟著「理想高度 vs 被提案高度」的差值漂移。`.frame(maxHeight: .infinity)` 接受
        // 任何被提案的高度、把實際內容釘在頂端，`preferredContentSize`（`ideal` 提案）
        // 不受影響——量過 `OptionsExpandTests`／`FooterPositionStabilityTests` 兩條都吃到
        // 這行才全綠。
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }

    /// T15（team-lead 看 T14 渲圖抓到的毛病之二）：分組卡片（圓角 10pt／1pt hairline）承載
    /// session 列表，取代先前「三列擠成一團」的裸列表——卡片內用細分隔線把 session 隔開，
    /// 縮進到與文字左緣對齊（`.padding(.leading, 40)`：圖示欄 20pt＋`HStack` 間距 8pt 再加
    /// 文字內距，數字沿用已經真渲圖評過的 V1 原型，不重新湊）。
    /// `ScrollView` 保留（V1 的 12 張渲圖只涵蓋 3 個 session，沒驗過超量情境，生產仍需要
    /// 捲動避免 session 數一多就把 footer／Options 推出視窗）。
    ///
    /// T22（panel-interaction-fixes）：高度**不用** `.frame(maxHeight: 420)`——`ScrollView`
    /// 垂直方向天生貪婪，只設上限沒設下限的話，外層畫布提案的高度只要跟內容自然高度不同，
    /// 它都會盡量吃滿被提案的高度，不會退回自己內容的自然高度。這在外層畫布被提案一個跟
    /// 理想高度不同的值時（`NSPopover` resize 動畫途中、或畫布比內容寬裕）會讓 footer／
    /// 圖例列的位置變成「依外層畫布高度而定」，不再是「列數固定時的常數」——
    /// `FooterPositionStabilityTests` 實測：3 個 session、外層畫布提案 600pt 時，Options
    /// 展開／收合兩者的 footer 位置差到 257pt。改用 `SessionsCardSizing.cardHeight(for:)`
    /// 從**真實列內容**（逐列依 `footer.isEmpty` 分別套用高度，不是列數乘一個假設常數，
    /// 見該型別 doc comment 的 review 退回紀錄）推導的固定高度（一樣夾到 420pt 上限），
    /// `ScrollView` 因此永遠拿到一個跟外層畫布提案無關的值。
    private var sessionsCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    PanelRowView(row: row, palette: model.palette)
                    if index < model.rows.count - 1 {
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
        .frame(height: SessionsCardSizing.cardHeight(for: model.rows))
        .panelCard(filled: false)
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
        HStack(alignment: .top, spacing: 8) {
            // 列色點只借色相，不借 alpha——idle 的 a=0.35 在面板上只是「看不見」（review-t0406 I3：白底 1.31:1）
            // T19 配套 B：與 `LegendDot` 共用同一份 `DotRing`（見該檔理由）——白色 working 列在
            // 白色卡片背景上沒有這圈邊線會直接消失。
            Circle().fill(Color(rgba: palette[row.activity], ignoringAlpha: true))
                .overlay(DotRing())
                .frame(width: 8, height: 8).padding(.top, 6).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                // D-l／CX23：標籤放在**既有第一行**，不另起一行——另起一行會撐高列高，
                // `RowHeightDerivationTests`（43／59pt）會紅。`.claude` 的 `agentLabel`
                // 是 nil（D-b），這裡不畫任何東西，維持既有面板長相。
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.projectName).font(.system(size: 13, weight: .semibold))
                    if let agentLabel = row.agentLabel {
                        // 實測（CodexRowLabelRenderTests）：加 padding／背景圓角會讓這個
                        // view 自己的 frame 高度多出 ~1pt，即使仍在同一個 `.firstTextBaseline`
                        // HStack 裡也會把整列量到的高度從 43/59pt 撐成 44/60pt——CX23 的
                        // ±0.5pt 容差抓得到。改成跟 `row.meta` 一樣的裸 `Text`（無 padding／
                        // 無背景），量到的高度才不變。
                        Text(agentLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Text(row.meta).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                // T15：headline 拿掉等寬（V1 token「headline 12 非等寬」——六個現況問題之一
                // 「等寬字太多」的來源，D-c 只保了 tool 名這句口吻，字型設計本身沒理由等寬）。
                Text(row.headline)
                    .font(.system(size: 12))
                    .foregroundStyle(row.activity == .error ? .red : .primary)
                    .lineLimit(1).truncationMode(.middle)
                // 副行字串由 model 拼（`PanelRow.footer`，「已結束」在行首）；view 不得自己拼——
                // `AppLayerSourceScanTests.panelFooterComesFromModel` 守這條。
                if !row.footer.isEmpty {
                    Text(row.footer).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        // T37：使用者回報「正在執行中的 session 上下邊區有一點點太小」——原本只有水平
        // 留白，列與列之間靠 `minHeight` 撐，文字幾乎貼著分隔線。垂直留白讓每一列有呼吸。
        //
        // 這個值一度只給到 2pt，因為 5pt／3pt 會讓 `FooterPositionStabilityTests` 紅，
        // 而我把那個紅讀成「版面到極限了」。**那是誤讀**（altitude#1）：那條 gate 的畫布
        // 高度當時寫死 600pt，而面板的 expanded 自然高度已經長到 599pt——加大留白讓它
        // 越過 600，畫布反而變得比內容小，掉進 gate 自己註解裡寫明「已知且承認做不到」
        // 的那一側。畫布常數改成從自然高度推導之後，這裡不再被它綁住。
        .padding(.vertical, 5)
        // 這裡原本還有 `.frame(minHeight: 28)`。**它已經恆不生效**：列本身的自然高度是
        // 43pt（無副行）／59pt（有副行），28pt 的下限永遠碰不到。實測撤掉它之後
        // `SessionsCardSizingDerivation`／`RowHeight`／`FooterPositionStability`／
        // `PanelPixel`／`OptionsExpand` 全綠、量到的列高一個像素都沒變，所以刪掉——
        // 留著會讓下一個人以為列高有個 28pt 的地板在管事（`OptionsSectionView` 裡的
        // 同名下限是真的在管事，別跟這裡搞混）。
    }
}
