/// T11 commit2（S0-2）：選單列 tooltip 的唯一 oracle。
///
/// persona 實測：`StatusItemController.tooltip(for:)` 原本只吃 `IconAppearance`，
/// 完全看不到 `InstallState`——沒裝 hook 時一律印「沒有活著的 session」，
/// D-e 指定的「還沒接上 Claude Code」整個 repo 0 命中。同一顆根因也讓面板標題
/// （見 `PanelModel`）在同一張畫面同時出現「沒有活著的 session」與 `NotConnectedView`
/// 的「還沒接上」——唯一不需要開面板的表面（tooltip）與面板本體互相矛盾。
///
/// 修法：**窮盡 `InstallState`**——非 `connected` 時一律用 `install.healthLabel`
/// （與 footer chip／面板標題同一個 oracle，不手搓第二份文案，也不會漏掉任何一種
/// 「接不上」的原因）；`connected` 時維持既有以 session 計數為主的句子。
public enum TooltipText {
    public static func text(appearance: IconAppearance, install: InstallState) -> String {
        switch install {
        case .claudeNotFound, .notConnected, .broken:
            return install.healthLabel
        case .connected:
            return sessionSummary(appearance)
        }
    }

    /// 既有邏輯（原 `StatusItemController.tooltip(for:)`）：第二個數字定義
    /// `live − attention`，與 `PanelViewModel.title` 共用同一個 `SessionSummary.text`
    /// （review-t0406 B2：已結束未確認的 error 進尾巴、不算 live，沒有 guard 會印
    /// 「-1 個在跑」；B3：兩邊曾各自實作這套三元式，用詞已經漂移，收成單一來源）。
    public static func sessionSummary(_ a: IconAppearance) -> String {
        SessionSummary.text(attention: a.attentionCount, live: a.liveCount, done: nil, attentionWord: "需要你")
    }
}
