import Foundation

/// S1-1（T13 收尾）：`NotConnectedView` 原本自己內嵌一段 `if/else`（`externalTargetPath` →
/// `explanationDetail` → 通用句）——搬成 `PanelModel` 的 derived property，理由與
/// `connectCTAText`／`showsExplanationPanel` 那一批相同（N9）：view 只准讀，不准自己判斷，
/// 這裡也才能被 `PanelBodyTitleChipDistinctTests` 這種窮盡 gate 直接測，不必真的渲染 SwiftUI。
extension PanelModel {
    /// `NotConnectedView` 在標題（大版說明的那顆語意標題，不是頂端 `PanelView.title`）之下
    /// 顯示的說明句：有 `externalTargetPath` 時優先顯示目前指向哪裡；否則讀
    /// `install.explanationDetail`（S1-1 已放寬到 7 個 broken reason，見
    /// `InstallAffordance.swift`）；兩者都沒有時退回最原始的通用句（`.notConnected`，
    /// 從未壞過的第一次使用）。
    public var notConnectedDetailText: String {
        if let note = mountTargetNote { return note }
        if let detail = install.explanationDetail { return detail }
        return "接上之後，Claude Code 的執行狀態會顯示在選單列。"
    }

    /// B6（/simplify 波次1，altitude#5／reuse#3,4）：「現有掛載指向哪裡」的單一措辭——
    /// 這句話原本在這裡跟 `PanelModel.connectCTASubtitle` 各組一份，app 層的
    /// `OptionsSectionView` 還有第三份且已經漂成「目前指向：」（跟這裡的
    /// 「現有掛載指向：」不一樣）。收成一個 derived property，AuraCore 內的兩個呼叫點
    /// 先改用它；app 層那一份留給下一波接手（B6 的第三個消費者）。
    public var mountTargetNote: String? {
        externalTargetPath.map { "現有掛載指向：\($0)" }
    }
}
