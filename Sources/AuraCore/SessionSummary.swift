/// B3（/simplify 波次1，alt#1／reuse#12）：「session 摘要」句的單一來源。
///
/// `PanelViewModel.title(for:)` 與 `TooltipText.sessionSummary(_:)` 曾各自實作同一套
/// 三元式（attention>0 → 有無 running → liveCount>0 → 兜底），用詞與分支數已經漂移
/// （「個在等你」vs「個需要你」；只有 `title` 有 done 分支）——收成一個純函式，
/// 兩邊只傳各自的 `attentionWord`，用詞差異因此是一個參數，不是兩份複製的控制流。
///
/// T27（i18n）：句子內容搬進 `L10nSessionSummary`（D-5(3) 要求字面只能住在 `L10n*.swift`），
/// 這裡只剩四路分支要走哪一句的判斷邏輯。**帶預設值 `.traditionalChinese`**（同 `Jargon`
/// 的 T27 理由）：既有呼叫端只有 `PanelViewModel.title(for:)`／`TooltipText.sessionSummary(_:)`
/// 兩個，都在 `AuraCore` 內部、都會改成明確傳 `language`，預設值只是保底、不藏任何生產風險。
public enum SessionSummary {
    public typealias AttentionWord = L10nSessionSummary.AttentionWord

    /// - Parameters:
    ///   - done: tooltip 目前刻意不講已完成數（`IconAppearance` 沒帶這個計數）——
    ///     傳 `nil` 讓「不講 done」是呼叫端的一次明確決定，不是「另一個檔案剛好少寫
    ///     一個分支」。
    public static func text(attention: Int, live: Int, done: Int?, attentionWord: AttentionWord,
                            language: Language) -> String {
        if attention > 0 {
            let running = live - attention
            return L10nSessionSummary.attentionSummary(count: attention, running: running,
                                                        word: attentionWord, language: language)
        }
        if live > 0 { return L10nSessionSummary.liveCount(live, language: language) }
        if let done, done > 0 { return L10nSessionSummary.doneCount(done, language: language) }
        return L10nSessionSummary.noActiveSessions.text(language)
    }
}
