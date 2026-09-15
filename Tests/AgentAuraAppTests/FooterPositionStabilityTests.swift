import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// T22（panel-interaction-fixes）：`OptionsExpandTests`（A4）只守「整體
/// `preferredContentSize` 隨展開變高」，不守「footer（含「Options ⌄」自己）的螢幕位置
/// 不隨之改變」——這正是使用者實機踩到的洞（⑩：展開後滑鼠不動再點一下，落點在圖例列，
/// 不在「Options ⌃」）。
///
/// **驗證過、且推翻了 team-lead 原本的假設**：直接量 `NSHostingController.preferredContentSize`
/// （沒有外部壓力的「理想」尺寸，`OptionsExpandTests` 也量這個）時，footer 位置在
/// collapsed／expanded 之間 diff 恆為 0（session 數 3／10/15/20/30 都測過，改動前就是 0）——
/// `sessionsCard` 的 `ScrollView` 在**理想提案**下其實會乖乖 hug 自己的內容，不會貪婪吃滿；
/// 那個情境本來就沒有洞，不是這條新 gate 的主檔（`footerTopUnchangedAtIdealSize` 留著當
/// 基本回歸網）。
///
/// 真正的洞在**外層畫布被提案一個比兩邊自然高度都大的高度**（`surplusHeight`，見下方
/// `footerTopUnchangedUnderSurplusCanvas`）——這是完全寫實的情境：`NSHostingController`
/// 的實際 `view.frame` 不保證跟 `preferredContentSize` 一路同步（`NSPopover` resize
/// 動畫途中、或單純螢幕空間比內容需要的還寬裕時，都會出現「提案高度 > 內容自然高度」），
/// 這時 `ScrollView` 沒有下限，只要提案的高度小於 420，它都會盡量把提案的高度吃滿，不會
/// 退回自己內容的自然高度——於是 footer／圖例列的位置變成「依外層畫布高度而定」，不再是
/// 「列數固定時的常數」。
///
/// **修之前實測**（3 個 session、外層畫布固定 600pt——超過 collapsed 自然高度 211pt 與
/// expanded 自然高度 503pt 兩者）：collapsed footerTop=536pt，expanded footerTop=279pt，
/// 差 `-257`pt。修法有兩處：(1) `SessionsCardSizing.cardHeight(for:)` 從真實列內容推導
/// 固定高度（夾到既有的 420pt 上限）取代 `.frame(maxHeight: 420)`，讓 `ScrollView` 的高度
/// 永遠跟外層畫布提案無關；(2) `PanelView.body` 加 `.frame(maxHeight: .infinity, alignment:
/// .top)`——沒有它，多出來的畫布高度會被整個 `VStack` 置中吸收（內容上下各分到一半空白），
/// 同樣讓 footer 的位置跟著外層畫布高度漂移。
///
/// **已知、且承認做不到的部分**：外層畫布被提案一個**比兩邊自然高度都小**的值（例如
/// `NSHostingController.view.frame` 被直接設成 300pt，介於 211 與 503 之間，模擬 resize
/// 動畫「還沒長到最終高度」的中繼畫格）時，`NSHostingView` 會把「大於目前 frame」的內容
/// 整個置中塞進這個偏小的 frame——這個行為在拿掉 `.frame(maxHeight: .infinity, alignment:
/// .top)` 之後也一模一樣（用最小 SwiftUI+AppKit 範例單獨驗證過，見 commit message），
/// 代表這是 `NSHostingView` 自己在「SwiftUI 內容的理想高度」與「外部強制設定的 view.frame」
/// 不一致時的預設收斂方式，不是 `PanelView` 這層的佈局邏輯能覆寫的。這個情境是否會在真的
/// `NSPopover` resize 動畫中出現、又出現多久，離屏測試量不到（沒有真 `NSWindow`），需要
/// 使用者在真 app 上，展開/收合 Options 的當下（不是等動畫結束後）點擊確認。
///
/// **量測手法必須用點擊辨識按鈕身份，不能用位置索引**（這裡不是理論上的保守寫法，是
/// 實測踩到的坑）：`NSView.subviews` 的走訪順序**不等於** SwiftUI body 的宣告順序——
/// collapsed 時 5 顆按鈕依序是「4 顆圖例＋footer」，footer 在索引 4；但 expanded 時
/// 15 顆按鈕的順序是「10 顆 Options 列＋4 顆圖例＋footer」，footer 仍是**最後一顆**但
/// 位置變成索引 14，不是 4。若照索引 4 去讀，expanded 那次讀到的其實是 Options 某一列
/// 的按鈕，量出來的差會是量錯按鈕的假象。這裡改成離屏渲染真的 `PanelView`、強迫 AppKit
/// 橋接後點遍每一顆 `NSButton`（同 `PanelPixelTests.panelViewForwardsAction` 的既有手法），
/// 找出**觸發 `.toggleOptions` 的那一顆**——不論它排在陣列的第幾個位置。用
/// `button.convert(_:to: hosting)` 換成 hosting 自己的座標系——已用獨立腳本驗證
/// `NSHostingView.isFlipped == true`，換算後的 `frame.minY` 直接就是「距離 hosting
/// 頂端幾 pt」。
@MainActor
@Suite("Options 展開時 footer 的螢幕位置不變（T22）")
struct FooterPositionStabilityTests {

    func session(_ id: String, _ a: Activity) -> SessionState {
        SessionState(id: id, projectName: id,
                    permissionMode: nil, effort: nil, model: nil,
                    activity: a, mainActivity: a, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    func model(optionsExpanded: Bool, sessionCount: Int = 3) -> PanelModel {
        let icon = IconState(activity: .working, counts: [.working: sessionCount], liveCount: sessionCount)
        let sessions = (0..<sessionCount).map { session("s\($0)", .working) }
        return PanelModel.make(icon: icon, sessions: sessions, palette: .default,
                               install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                               optionsExpanded: optionsExpanded, launchAtLogin: true, externalTargetPath: nil,
                               banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, language: .traditionalChinese)
    }

    /// footer 的「Options」按鈕在真的 `NSHostingController.view` 座標系裡的 `minY`
    /// （距頂端幾 pt）——走真的 `StatusItemController.setPanel`（生產路徑），`height`
    /// 直接指定 `hostingController.view.frame`（`nil` 則用 `preferredContentSize` 本身，
    /// 即無外部壓力的理想尺寸）。`layoutSubtreeIfNeeded()` 是必要的——`height` 與自然內容
    /// 高度不同時，`OffscreenRender.render` 內建的 `displayIgnoringOpacity` 沒有先逼出
    /// 一次完整 layout pass，量到的按鈕位置會是還沒吃到新 frame 的舊值。用點擊辨識按鈕
    /// 身份（見檔案開頭 doc comment），不用位置索引。
    func footerButtonTop(_ controller: StatusItemController, _ m: PanelModel, height: CGFloat?) throws -> CGFloat {
        var lastReceived: [PanelAction] = []
        // `controller.onAction`（不是 `panelOnAction`）——`panelOnAction` 在 `init()` 已經
        // 接成「動態轉發到 `self.onAction`」，`setPanel` 建 `PanelView` 時是把 `panelOnAction`
        // 的當下值複製進去，事後才設 `panelOnAction` 對已經蓋好的 view 沒有效果。
        controller.onAction = { lastReceived.append($0) }
        controller.setPanel(m)
        let hc = try #require(controller.hostingController)
        let resolvedHeight = height ?? hc.preferredContentSize.height
        hc.view.frame = NSRect(x: 0, y: 0, width: 380, height: resolvedHeight)
        hc.view.layoutSubtreeIfNeeded()
        _ = try OffscreenRender.render(hc.view, over: .white)   // 強迫 layout，按鈕才真的存在

        for button in Self.allButtons(in: hc.view) {
            lastReceived.removeAll()
            button.performClick(nil)
            if lastReceived == [.toggleOptions] {
                return button.convert(button.bounds, to: hc.view).minY
            }
        }
        Issue.record("點遍所有按鈕都沒有觸發 .toggleOptions —— footer 的「Options」按鈕不見了")
        return -1
    }

    @Test("外層畫布被提案 600pt（超過 collapsed／expanded 兩邊自然高度）時，footer 位置差 0pt")
    func footerTopUnchangedUnderSurplusCanvas() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }
        let surplusHeight: CGFloat = 600   // > 兩邊自然高度（211／503），見檔案開頭 doc comment
        let collapsedTop = try footerButtonTop(controller, model(optionsExpanded: false), height: surplusHeight)
        let expandedTop = try footerButtonTop(controller, model(optionsExpanded: true), height: surplusHeight)

        #expect(collapsedTop == expandedTop, """
            外層畫布固定 600pt（超過兩邊自然高度）時，footer 按鈕的位置不該隨 Options 展開改變，\
            實際 collapsed=\(collapsedTop)pt expanded=\(expandedTop)pt（差 \(expandedTop - collapsedTop)pt，\
            修之前實測 -257pt）—— 外層畫布比內容需要的還寬裕時（真的 popover 也可能發生），\
            使用者若滑鼠沒動再點一次，會誤觸到被推移的圖例列，而不是收合 Options。
            """)
    }

    /// 次要保險：`preferredContentSize`（無外部壓力的理想尺寸，`OptionsExpandTests` 也測這個）
    /// 下 footer 位置本來就是 0 diff（連修之前都是），不是這條 T22 新增 gate 的主檔——留著
    /// 當基本回歸網，不重複宣稱它是「修之前 RED」的那一條。
    @Test("preferredContentSize（無外部壓力）下 footer 位置差 0pt")
    func footerTopUnchangedAtIdealSize() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }
        let collapsedTop = try footerButtonTop(controller, model(optionsExpanded: false), height: nil)
        let expandedTop = try footerButtonTop(controller, model(optionsExpanded: true), height: nil)

        #expect(collapsedTop == expandedTop, """
            理想尺寸下 footer 位置也不該變，實際 collapsed=\(collapsedTop)pt expanded=\(expandedTop)pt
            """)
    }

    private static func allButtons(in view: NSView) -> [NSButton] {
        var found: [NSButton] = []
        if let button = view as? NSButton { found.append(button) }
        for sub in view.subviews { found.append(contentsOf: allButtons(in: sub)) }
        return found
    }
}
