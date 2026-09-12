/// B3（/simplify 波次1，alt#1／reuse#12）：「session 摘要」句的單一來源。
///
/// `PanelViewModel.title(for:)` 與 `TooltipText.sessionSummary(_:)` 曾各自實作同一套
/// 三元式（attention>0 → 有無 running → liveCount>0 → 兜底），用詞與分支數已經漂移
/// （「個在等你」vs「個需要你」；只有 `title` 有 done 分支）——收成一個純函式，
/// 兩邊只傳各自的 `attentionWord`，用詞差異因此是一個參數，不是兩份複製的控制流。
public enum SessionSummary {

    /// - Parameters:
    ///   - done: tooltip 目前刻意不講已完成數（`IconAppearance` 沒帶這個計數）——
    ///     傳 `nil` 讓「不講 done」是呼叫端的一次明確決定，不是「另一個檔案剛好少寫
    ///     一個分支」。
    public static func text(attention: Int, live: Int, done: Int?, attentionWord: String) -> String {
        if attention > 0 {
            let running = live - attention
            return running > 0
                ? "\(attention) 個\(attentionWord) · \(running) 個在跑"
                : "\(attention) 個\(attentionWord)"
        }
        if live > 0 { return "\(live) 個 session 在跑" }
        if let done, done > 0 { return "\(done) 個已完成" }
        return "沒有活著的 session"
    }
}
