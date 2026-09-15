import AppKit
import AuraCore

/// T08：composition-root 的其餘生產副作用縫——與 `makeRenderer`／`defaults` 同一個理由
/// （spec §6.4：測試裡絕不真的 `NSApp.terminate`／彈 `NSAlert`／開瀏覽器）。
///
/// `AppTerminating` 原是 `Tests/AgentAuraAppTests/Support/FakeTerminator.swift` 的 T01
/// 佔位宣告——現在是這裡的真型別，`FakeTerminator` 改對它 conform（同 `LoginItemControlling`／
/// `HookVerificationStoring` 的既有慣例）。
@MainActor
protocol AppTerminating {
    func terminate()
    /// T24：完整移除的最後一步——**不經過 `NSApp.terminate()`**。team-lead 真機實測
    /// 抓到：`NSApp.terminate()` 的 AppKit teardown 會把剛清空的 `io.agentaura.app`
    /// persistent domain 部分寫回去（觀察到 `NSToolbar Configuration com.apple.NSColorPanel`
    /// 這個鍵復活），即使 decoy domain 的對照實驗測不出這個效應（AppKit 沒有參與那個
    /// domain）——這正是「gates share one eye」：decoy 跟生產路徑不是同一件事。
    /// 直接結束行程，不給 AppKit 任何寫回的機會。
    func terminateImmediately()
}

/// `.quit`（D-j）：唯一真的呼叫 `NSApp.terminate` 的地方。
///
/// `nonisolated init()`：`AppDelegate.init(...)` 把 `RealTerminator()` 當一般參數的
/// 預設值（不是包在 `@MainActor` 閉包裡）——預設值表達式在呼叫端求值，實測若不宣告
/// `nonisolated init` 會被 Swift 6 擋成「call to main actor-isolated initializer in a
/// synchronous nonisolated context」。`init` 本身不碰任何 actor 隔離狀態，只有
/// `terminate()`（`NSApp`）需要留在 MainActor（protocol 本身宣告 `@MainActor`）。
struct RealTerminator: AppTerminating {
    nonisolated init() {}
    func terminate() { NSApp.terminate(nil) }
    func terminateImmediately() { exit(0) }
}

/// E11（/simplify 波次2，reuse#9）：`DisconnectConfirmation`／`ReplaceMountConfirmation`
/// 原本逐行平行——`NSAlert()` → `.alertStyle = .warning` → `messageText` →
/// `informativeText` → 兩顆按鈕 → `runModal() == .alertFirstButtonReturn` → `onConfirm()`。
/// 「第一顆按鈕＝確認」這個慣例被寫了兩遍，加第三個確認框就是第三遍——寫錯按鈕順序的
/// 後果是使用者按「取消」卻執行了破壞性動作。收成一個共用建構式，兩個既有 enum
/// 變成呼叫它的兩組常數：注入縫（`confirmDisconnect`／`confirmReplaceExternalMount`）
/// 完全不動，測試不受影響。
///
/// T29（i18n）：「取消」按鈕文案改讀 `L10nConfirmationAlerts.cancelButtonTitle`——三個
/// 呼叫端（disconnect／replaceMount／uninstall）共用同一顆取消鈕，`language` 因此在這裡
/// 收斂一次，不必三處各自傳一次「取消」的翻譯。
@MainActor
enum ConfirmationAlert {
    static func present(title: String, body: String, confirmTitle: String, language: Language,
                       onConfirm: () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: L10nConfirmationAlerts.cancelButtonTitle.text(language))
        if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        }
    }
}

/// `.disconnect`：呼叫端負責確認對話框（spec §4.1）——真的彈 `NSAlert`，
/// 寫清楚會刪什麼、不會刪什麼、AgentAura 會留在選單列（S1-S2 措辭要求）。
/// 只有使用者按下「移除掛載」（第一顆按鈕）才呼叫 `onConfirm`。
@MainActor
enum DisconnectConfirmation {
    static func present(language: Language, onConfirm: () -> Void) {
        ConfirmationAlert.present(
            title: L10nConfirmationAlerts.disconnectTitle.text(language),
            body: L10nConfirmationAlerts.disconnectBody.text(language),
            confirmTitle: L10nConfirmationAlerts.disconnectConfirmButton.text(language),
            language: language, onConfirm: onConfirm)
    }
}

/// A5（T11 commit3）：`.replaceExternalMount`（D-i：明確選擇「改指向這個 App」）先前
/// 直接執行、沒有確認框——不對稱得很明顯，「移除掛載」（破壞性較低）有一個寫得很好的
/// `NSAlert`，比較讓人意外的「把你的開發掛載換成凍結版」卻一顆按鈕直接生效。
/// 同 `DisconnectConfirmation` 的注入縫（測試不真的彈 `NSAlert`，spec §6.4）。
@MainActor
enum ReplaceMountConfirmation {
    static func present(language: Language, onConfirm: () -> Void) {
        ConfirmationAlert.present(
            title: L10nConfirmationAlerts.replaceMountTitle.text(language),
            body: L10nConfirmationAlerts.replaceMountBody.text(language),
            confirmTitle: L10nConfirmationAlerts.replaceMountConfirmButton.text(language),
            language: language, onConfirm: onConfirm)
    }
}

/// T24（D-1）：`.uninstall`——比 `.disconnect` 更進一步。文案是使用者原話要求改過的
/// 第二版：條列、短句、講**使用者感受得到的後果**，不寫技術名詞（不提 symlink／
/// persistent domain／`~/.claude/skills/agentaura` 這類字面）。`title`／`body` 拆成
/// 獨立函式（不是內嵌在 `present()` 裡）：`UninstallConfirmationCopyTests` 需要在
/// 不彈真 `NSAlert` 的前提下驗文案語意，這是唯一的讀取點。
///
/// T25（真機事故）：結尾原本寫「都可以救回來」，是無條件保證——垃圾桶動作曾經在無法
/// 解釋的情況下沒有真的落地，那句話對那次的使用者是假話。這個對話框在動作**之前**
/// 顯示，沒辦法等垃圾桶動作真的回報成功才講這句話，所以改成不做絕對承諾，
/// 而不是把承諾綁在事實上（`recoveryClaimIsHedgedNotAbsolute` 驗證這個決定）。
///
/// T29（i18n）：`title`／`body`／`confirmButtonTitle` 從 `static let`／字面改成吃
/// `language:` 的函式（無預設值）——內容搬進 `L10nUninstallConfirmation`（AuraCore），
/// 這裡只留「哪句話對應哪個角色」的組裝。
@MainActor
enum UninstallConfirmation {
    static func title(_ language: Language) -> String { L10nUninstallConfirmation.title.text(language) }
    static func body(_ language: Language) -> String { L10nUninstallConfirmation.body.text(language) }
    static func confirmButtonTitle(_ language: Language) -> String {
        L10nUninstallConfirmation.confirmButtonTitle.text(language)
    }

    static func present(language: Language, onConfirm: () -> Void) {
        ConfirmationAlert.present(title: title(language), body: body(language),
                                  confirmTitle: confirmButtonTitle(language),
                                  language: language, onConfirm: onConfirm)
    }
}

/// T24（D-1 步驟5）：`NSWorkspace.recycle`（可還原，不是 `FileManager.removeItem`）。
/// 注入縫同 `AppServiceRegistering`（`LoginItem.swift`）——**測試不得真的呼叫它**，
/// 走 fake（spec §6.4 的既有慣例，這裡是同一個形狀）。
@MainActor
protocol BundleRecycling {
    func recycle(_ url: URL, completion: @escaping (Error?) -> Void)
}

@MainActor
struct WorkspaceRecycler: BundleRecycling {
    func recycle(_ url: URL, completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.recycle([url]) { _, error in completion(error) }
    }
}
