import AppKit

/// T08：composition-root 的其餘生產副作用縫——與 `makeRenderer`／`defaults` 同一個理由
/// （spec §6.4：測試裡絕不真的 `NSApp.terminate`／彈 `NSAlert`／開瀏覽器）。
///
/// `AppTerminating` 原是 `Tests/AgentAuraAppTests/Support/FakeTerminator.swift` 的 T01
/// 佔位宣告——現在是這裡的真型別，`FakeTerminator` 改對它 conform（同 `LoginItemControlling`／
/// `HookVerificationStoring` 的既有慣例）。
@MainActor
protocol AppTerminating {
    func terminate()
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
}

/// E11（/simplify 波次2，reuse#9）：`DisconnectConfirmation`／`ReplaceMountConfirmation`
/// 原本逐行平行——`NSAlert()` → `.alertStyle = .warning` → `messageText` →
/// `informativeText` → 兩顆按鈕 → `runModal() == .alertFirstButtonReturn` → `onConfirm()`。
/// 「第一顆按鈕＝確認」這個慣例被寫了兩遍，加第三個確認框就是第三遍——寫錯按鈕順序的
/// 後果是使用者按「取消」卻執行了破壞性動作。收成一個共用建構式，兩個既有 enum
/// 變成呼叫它的兩組常數：注入縫（`confirmDisconnect`／`confirmReplaceExternalMount`）
/// 完全不動，測試不受影響。
@MainActor
enum ConfirmationAlert {
    static func present(title: String, body: String, confirmTitle: String, onConfirm: () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")
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
    static func present(onConfirm: () -> Void) {
        ConfirmationAlert.present(
            title: "移除 Claude Code 掛載？",
            body: """
                這會移除 ~/.claude/skills/agentaura 這個掛載，讓 Claude Code 的 hook 停止回報執行狀態。

                不會刪除 AgentAura 本身、不會刪除任何 session 紀錄或你的顏色設定——AgentAura 會留在選單列，\
                要再用的話隨時可以按「接上」。
                """,
            confirmTitle: "移除掛載", onConfirm: onConfirm)
    }
}

/// A5（T11 commit3）：`.replaceExternalMount`（D-i：明確選擇「改指向這個 App」）先前
/// 直接執行、沒有確認框——不對稱得很明顯，「移除掛載」（破壞性較低）有一個寫得很好的
/// `NSAlert`，比較讓人意外的「把你的開發掛載換成凍結版」卻一顆按鈕直接生效。
/// 同 `DisconnectConfirmation` 的注入縫（測試不真的彈 `NSAlert`，spec §6.4）。
@MainActor
enum ReplaceMountConfirmation {
    static func present(onConfirm: () -> Void) {
        ConfirmationAlert.present(
            title: "改指向這個 App？",
            body: """
                目前的掛載指向別的地方（例如你自己的開發用 repo）。改指向這個 App 之後，
                那份掛載會被換成 App 內建的版本，原本的掛載不會再生效。

                不會刪除原本掛載指向的任何檔案——只是換了 ~/.claude/skills/agentaura 指向哪裡，
                要換回去的話可以到原本的位置重新接上一次。
                """,
            confirmTitle: "改指向這個 App", onConfirm: onConfirm)
    }
}
