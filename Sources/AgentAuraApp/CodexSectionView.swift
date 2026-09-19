import SwiftUI
import AuraCore

/// T09（spec §4.6，R-9／R-10／D-s）：Codex 掛載卡片。依 `model.codex.kind` ＋
/// `model.codexPathRejection`／`model.codexSnippet` 分支——`PanelModel` 已經把
/// `codexPathRejection`／`codexSnippet` 兩個「橫跨 case 的外部輸入」算好（見該檔
/// doc comment），這裡只讀，不重新判定。位置在 `PanelView.body` 裡緊接在 Claude 側內容
/// 之後、`LegendRowView` 之前（P1：兩張卡片疊在同一張畫面時，Codex 的提示永遠在下面）。
///
/// `.unavailable`／`.connected` 回 `EmptyView()`——**零像素差異**（D-j）；`.connected` 的
/// 「已接上」說明留給 Options 選單的「移除 Codex 掛載…」一列，不重畫第二份卡片
/// （同 Claude 側 `NotConnectedView` 只在未接上時出現的既有理由）。其餘四態各自對應
/// §4.6 表一格，`.connectedStalePath`／`.occupiedByOther` 還要再吃 `pathRejection`／
/// `codexSnippet` 才能決定按鈕與 snippet 區塊有沒有。
///
/// 按鈕一律 `.borderless` 配自訂 `CTAButtonLabel`（同 `NotConnectedView`／`CTAButtonStyle`
/// 既有理由：離屏渲染下 `.bordered` 會把真 `NSButton` 包進 `_FocusRingView`，沒有真
/// `NSWindow` 時 `allButtons` 遞迴走訪找不到）。
struct CodexSectionView: View {
    let model: PanelModel
    /// 沒有預設值：忘了傳要是編譯錯（D-j，同 `NotConnectedView`／`OptionsSectionView`）。
    let onAction: (PanelAction) -> Void

    var body: some View {
        switch model.codex {
        case .unavailable, .connected:
            EmptyView()
        case .notConnected:
            card {
                explanation(L10nCodex.notConnectedPrompt.text(model.language))
                actionButton(.connectCodex, title: L10nCodex.connectRow.text(model.language))
            }
        case .connectedStalePath:
            // R-9：`pathRejection != nil` 時**不給按鈕**——按下去會先 disconnect 掉一份
            // 還在運作的檔（見 `CodexHookPathCheck` 的既有理由）。文案不預設成因（r4 m2）。
            if model.codexPathRejection != nil {
                card {
                    explanation(L10nCodex.staleOtherCopyMessage.text(model.language))
                }
            } else {
                card {
                    explanation(L10nCodex.staleMovedPrompt.text(model.language))
                    actionButton(.connectCodex, title: L10nCodex.reconnectRow.text(model.language))
                }
            }
        case .occupiedByOther:
            card {
                explanation(L10nCodex.occupiedIntro.text(model.language))
                if let snippet = model.codexSnippet {
                    snippetBlock(snippet)
                } else {
                    // R-10：路徑會在下次開機消失，寧可不給也不給一份會過期的設定。
                    explanation(L10nCodex.occupiedSnippetWithheldReason.text(model.language))
                }
            }
        case .blockedByBundlePath(let rejection):
            card {
                switch rejection {
                case .mustMoveToApplications:
                    // D-s：**不給 snippet**——那個路徑下次開機就消失。
                    explanation(L10nCodex.blockedPathExplanation.text(model.language))
                    explanation(InstallerFailure.mustMoveToApplicationsMessage(model.language))
                case .unsupportedCharacter(let character):
                    explanation(L10nCodex.unsupportedCharacterExplanation(character, language: model.language))
                    if let snippet = model.codexSnippet {
                        snippetBlock(snippet)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func explanation(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private func actionButton(_ action: PanelAction, title: String) -> some View {
        Button { onAction(action) } label: { CTAButtonLabel(text: title) }
            .buttonStyle(.borderless)
    }

    /// 可選取、等寬——使用者是真的會照著貼進 `~/.codex/hooks.json` 的那個人（P2）。
    /// **文字直接讀 `snippet` 參數，不手搓第二份字面**——`snippet` 的唯一來源是
    /// `PanelModel.codexSnippet`（`CodexHooksJSON.snippet(...)` 的產出，R-10 之後穿過
    /// 路徑判定），這裡只負責畫出來，同源見 `CodexSectionViewTests`
    /// 的 `occupiedWithSnippetShowsSnippetAndCopyButton`／`blockedUnsupportedCharacterNamesTheCharacterAndKeepsSnippet`
    /// 兩條（mutation③：改成手寫字串，兩條都會紅）。
    @ViewBuilder
    private func snippetBlock(_ snippet: String) -> some View {
        Text(snippet)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        actionButton(.copyCodexSnippet, title: L10nCodex.copyButtonLabel.text(model.language))
    }

    /// 每個非空狀態共用的卡片外框——固定加一個「Codex」小標頭（產品名，D-b：**不進
    /// L10n**），避免只有「複製」這種不提 agent 名字的按鈕時，使用者分不出這張卡片在講哪個
    /// agent（`.occupiedByOther`／`.blockedByBundlePath` 兩態的按鈕都不提 Codex 三個字）。
    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Agent.codex.label ?? "Codex").font(.system(size: 12, weight: .semibold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(filled: false)
    }
}
