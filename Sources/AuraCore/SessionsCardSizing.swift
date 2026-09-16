/// T22（panel-interaction-fixes）：`PanelView.sessionsCard` 原本用 `ScrollView { … }
/// .frame(maxHeight: 420)` 承載 session 列表——`ScrollView` 在垂直方向天生貪婪，
/// `maxHeight` 只設了「不超過 420」的上限、沒有設下限，SwiftUI 對它的高度提案只要小於
/// 420，它都會盡量吃滿被提案的高度，不會回到自己內容的自然高度。
///
/// 這在 popover 外層真的被壓縮時（resize 動畫的中繼畫格、或 `NSHostingController`
/// 被提案一個跟理想高度不同的畫布——`OptionsExpandTests`〔A4〕量的是**沒有外部壓力**的
/// `preferredContentSize`，那個情境下這個洞量不到，diff 剛好是 0）會讓 footer／圖例列
/// 跟著外層壓力上下亂跳：`FooterPositionStabilityTests` 實測（3 個 session、外層畫布
/// 高度被提案 600pt）collapsed 與 expanded 的 footer Y 差到 `257`pt。
///
/// 修法：**不讓 `ScrollView` 自己決定高度**——改用從真實列內容推導出來、夾到 420 的固定
/// `.frame(height:)`，`ScrollView` 因此永遠拿到一個跟外層畫布高度無關的值，不再貪婪。
///
/// **review 退回（T16 同族——凍住的數字）**：第一版把 `rowHeight` 寫死成 33（量測時用的
/// 是「沒有 `footer` 副行」的列），沒有任何 gate 從真實 view 推導它，改壞 `PanelRowView`
/// 也不會有測試變紅；而使用者機器上常見的單一 session **有** `footer` 副行（`PanelRow.footer`
/// 非空——例如「3s · 剛剛」），真實高度是 49pt，若整卡只用 33pt 的假設去分配空間，
/// 唯一那一列會被裁掉一截。修法：**per-row 依 `footer.isEmpty` 分別套用兩種高度**，
/// 不再假設所有列等高；兩個常數各自配一條 `RowHeightDerivationTests` 的 gate，離屏渲染
/// 真實 `PanelRowView`（分別餵「沒有 footer」與「有 footer」的 fixture）驗證常數等於
/// 量到的值（±0.5pt），改 `PanelRowView` 的 padding／字級／行數就會紅。
///
/// **執行期自我量測（`GeometryReader`＋`PreferenceKey`）已嘗試但放棄**：離屏渲染下
/// `.onPreferenceChange` 的第一次回呼只收到 `defaultValue`（真正量到的值那一次回呼
/// 沒有發生，即使多次 `layoutSubtreeIfNeeded()` 加 `RunLoop.current.run(until:)`
/// 也一樣——`@State` 因為 preference 改變而該觸發的第二次 render pass，在沒有真的
/// `NSWindow`／應用程式事件迴圈的離屏環境下不會發生）。這代表這個技巧在我們的測試環境
/// 裡**無法驗證**，即使它在真的跑起來的 app 裡可能沒事，我們也沒有任何 gate 能守住它、
/// 抓到迴歸——與其塞一個測不到的機制，改用能被 gate 守住的推導常數。
///
/// **實測分解**（`NSHostingView(rootView: PanelRowView(...)).fittingSize`）：
/// 沒有 `footer` 副行的列＝43pt；有 `footer` 副行（如 `toolDurationMs` 非 nil）的列＝59pt
/// （基底 33／49pt 加上 `PanelRowView` 的 `.padding(.vertical, 5)` 上下共 10pt）；
/// 分隔線（`Divider().padding(.leading, 40)`，1→5 列純無 footer 列連續量測）每條＋1pt。
public enum SessionsCardSizing {
    /// 沒有 `footer` 副行的列高（見上方實測分解；`RowHeightDerivationTests` 守）。
    public static let compactRowHeight: Double = 43
    /// 有 `footer` 副行的列高（見上方實測分解；`RowHeightDerivationTests` 守）。
    public static let tallRowHeight: Double = 59
    /// 相鄰兩列之間 `Divider().padding(.leading, 40)` 的自然高度。
    public static let dividerHeight: Double = 1
    /// `PanelView.sessionsCard` 原本 `.frame(maxHeight: 420)` 的上限語意，維持不變。
    public static let maxHeight: Double = 420

    /// 逐列依 `footer.isEmpty` 套用對應高度——不假設所有列等高，避免有副行的列被裁切
    /// （review 指出的迴歸），也避免全部套用保守上界造成短列留下多餘空白。
    /// `rows.count - 1` 條分隔線（`PanelView.sessionsCard` 只在列與列之間畫，不含頭尾）。
    public static func contentHeight(for rows: [PanelRow]) -> Double {
        guard !rows.isEmpty else { return 0 }
        let rowsHeight = rows.reduce(0.0) { $0 + ($1.footer.isEmpty ? compactRowHeight : tallRowHeight) }
        return rowsHeight + Double(rows.count - 1) * dividerHeight
    }

    /// `sessionsCard` 真正要用的高度：自然內容高度夾到 `maxHeight`。
    public static func cardHeight(for rows: [PanelRow]) -> Double {
        min(contentHeight(for: rows), maxHeight)
    }
}
