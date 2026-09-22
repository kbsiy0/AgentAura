/// T13i（S1-4，D-ab）：`CodexSectionView` 的 snippet 區塊固定高度——**上限住在這裡**
/// （AuraCore，純算術，形狀照抄 `SessionsCardSizing`：常數從真實量測而來）。**下限（6 個
/// 視覺列）的基準不寫在這裡**——`minVisibleLines` 只是「多少行」這個純算術規則，真正的
/// pt 下限由 `CodexSnippetHeightTests`（App 層）用真實渲染量出來再比對，AuraCore 只准
/// import Foundation、量不了文字（同 `LEDStripView.preferredWidth` 把算術錯誤凍成常數的
/// 教訓，CLAUDE.md gate 哲學第 2 條）。
///
/// **上下限共用同一個量到的行高**（r16／n6）：`lineHeight` 這個常數同時是下限「6 個視覺列」
/// 與上限「12 個視覺列」換算 pt 的單位——`CodexSnippetSizingDerivationTests` 離屏渲染真實
/// `Text`（10pt 等寬字型、`.padding(8)`，逐字照抄 `CodexSectionView.snippetBlock` 的樣式）
/// 驗證這裡的常數等於真的量到的值（±0.5pt），改壞字型／padding 這條測試會紅。**為什麼不能
/// 只照抄 `SessionsCardSizing` 的形狀而不照抄它的 gate**：那個先例的第一版把 `rowHeight`
/// 寫死成 33（量測時用的是沒有副行的列）被 review 退回，真實有副行是 49pt——沒有推導 gate，
/// 改壞版面不會有任何測試變紅（`SessionsCardSizing.swift:15`）。
///
/// **實測分解**（2026-09-21，`CodexSnippetHeightMeasurement.step6IsolatedLineHeight`，
/// 孤立渲染 `Text(...).font(.system(size: 10, design: .monospaced)).padding(8)`，餵已知行數
/// 的顯式換行字串——明確換行不依賴自動換行，離屏環境下不需要真的 layout pass 就準確）：
/// 1 行＝29pt、6 行＝94pt、12 行＝172pt。兩段斜率完全一致：`(94-29)/5 = (172-94)/6 = 13.0`pt／行，
/// 截距（`.padding(8)` 上下共）16pt。
///
/// **上限數字怎麼選**（`CodexSnippetHeightMeasurement` STEP8，2026-09-21）：整個五維域
/// （14 個 `CodexState` 代表值 × 兩語言 × {rows 空,3 列} × `install ∈ {.connected,
/// .replaceExternal 代表值}` × `banner ∈ {nil,.codexConnected}`）裡，把 `.occupiedByOther`
/// 的 `codexSnippet` 清空後量到的**結構性最壞組合**是 538pt（語言 English、rows 空、
/// install=replaceExternal、banner=codexConnected）；扣掉空字串本身佔的單行高度
/// （29pt，與孤立量測的 h1 完全一致，交叉驗證過）＝ **結構高度 509pt**。780pt 天花板扣掉
/// 結構高度，上限預算是 **271pt**；選 **12 行 ＝ 172pt**，預算內留 99pt 餘裕（給鏈 A 的
/// T13f 標題換行等本 worktree 還沒落地的增量），也遠高於 6 行下限（94pt）。
/// **780pt 天花板在這個預算下可達，不必調整**。
public enum CodexSnippetSizing {
    /// 每一個視覺列的高度（pt）——`CodexSnippetSizingDerivationTests` 用離屏渲染驗證（±0.5pt）。
    public static let lineHeight: Double = 13
    /// `Text(...).padding(8)` 上下共 16pt，是唯一跟行數無關的固定量（截距）。
    public static let verticalPadding: Double = 16
    /// D-ab 下限：至少同時顯示這麼多視覺列（pt 下限由 `CodexSnippetHeightTests` 在 App 層
    /// 用真實渲染量出來，這裡只放「幾行」這個純算術規則）。
    public static let minVisibleLines = 6
    /// D-ab 上限：snippet 區塊固定高度——12 個視覺列（見上方 doc comment 的先量後定）。
    public static let height: Double = verticalPadding + lineHeight * 12
}
