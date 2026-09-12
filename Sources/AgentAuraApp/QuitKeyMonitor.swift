import AppKit

/// B3：面板顯示期間監聽 ⌘Q。`LSUIElement` app 的 popover 收不到選單列的 key equivalent——
/// Options 列上印著「離開 AgentAura ⌘Q」，但改之前按下去什麼都不會發生，是一句不接線的
/// 假字樣（誠實性問題，同 tooltip／CTA 說謊那個病族，不是加分項）。
///
/// install／remove 走注入的閉包（測試不得裝真的全域 event monitor，spec §6.4）；
/// 生產預設呼叫真的 `NSEvent.addLocalMonitorForEvents`。
///
/// **不宣告 `@MainActor`**（雖然實務上只會被 `StatusItemController`——本身 `@MainActor`——
/// 呼叫）：`StatusItemController.init` 把 `QuitKeyMonitor()` 當預設參數值，而預設值表達式
/// 在呼叫端求值，若這裡是 `@MainActor` 會被 Swift 6 擋成「call to main actor-isolated
/// initializer in a synchronous nonisolated context」（同 `RealTerminator` 踩過的理由）；
/// 但 `RealTerminator` 的解法（`nonisolated init` ＋ 零 stored property）在這裡不夠，因為
/// 這個類別的 init 真的要寫入 `install`／`remove`——`nonisolated init` 寫 `@MainActor` 的
/// stored property 一樣過不了型別檢查。乾脆整個類別不隔離：`NSEvent.addLocalMonitorForEvents`／
/// `removeMonitor` 本身不是 actor-isolated API（只有 `NSApp` 是），零風險。
final class QuitKeyMonitor {
    private let install: (@escaping (NSEvent) -> NSEvent?) -> Any
    private let remove: (Any) -> Void
    private var token: Any?

    init(install: @escaping (@escaping (NSEvent) -> NSEvent?) -> Any = { handler in
             NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler) as Any
         },
         remove: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }) {
        self.install = install
        self.remove = remove
    }

    /// 面板顯示時呼叫；已經裝過就不重複裝（面板開著時多次呼叫必須是 no-op）。
    func startIfNeeded(onQuit: @escaping () -> Void) {
        guard token == nil else { return }
        token = install { event in
            guard Self.isCommandQ(event) else { return event }
            onQuit()
            return nil   // 吞掉這個按鍵，不再往下傳給別的 responder
        }
    }

    /// 面板關閉時務必呼叫——不移除的話全 app 的鍵盤事件會一直被攔，是會咬人的那種洩漏。
    func stopIfNeeded() {
        guard let token else { return }
        remove(token)
        self.token = nil
    }

    static func isCommandQ(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "q"
    }
}
