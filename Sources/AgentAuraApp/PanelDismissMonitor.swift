import AppKit

/// T20：`QuitKeyMonitor` 的同形手足——面板釘住（改色）期間額外裝兩個 `NSEvent` monitor，
/// 讓「點擊真正的外部」能主動關面板（`.semitransient` 本身不會，見 `PanelDismissPolicy`）。
/// 全域 monitor 抓「點到別的 app」（那必然是外部，不需要再判斷）；本地 monitor 抓
/// 「點到自己 app 內的某個視窗」，交給注入的 `shouldClose` 判斷（popover／色板／錨點例外）。
///
/// install／remove 走注入的閉包（測試不得裝真的全域 monitor，spec §6.4）；生產預設呼叫
/// 真的 `NSEvent.addGlobalMonitorForEvents`／`addLocalMonitorForEvents`。不宣告 `@MainActor`
/// ——理由同 `QuitKeyMonitor`（呼叫端把它當預設參數值，求值在呼叫端；這兩個 API本身也
/// 不是 actor-isolated）。
final class PanelDismissMonitor {
    private let installGlobal: (@escaping (NSEvent) -> Void) -> Any
    private let installLocal: (@escaping (NSEvent) -> NSEvent?) -> Any
    private let remove: (Any) -> Void
    private var globalToken: Any?
    private var localToken: Any?

    init(installGlobal: @escaping (@escaping (NSEvent) -> Void) -> Any = { handler in
             NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: handler) as Any
         },
         installLocal: @escaping (@escaping (NSEvent) -> NSEvent?) -> Any = { handler in
             NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: handler) as Any
         },
         remove: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }) {
        self.installGlobal = installGlobal
        self.installLocal = installLocal
        self.remove = remove
    }

    /// 面板釘住時呼叫；已經裝過就不重複裝（同 `QuitKeyMonitor.startIfNeeded`）。`shouldClose`
    /// 只用在本地 monitor——全域 monitor 收到的事件必然來自別的 app，不需要再判斷。
    func startIfNeeded(shouldClose: @escaping (NSEvent) -> Bool, onDismiss: @escaping () -> Void) {
        guard globalToken == nil, localToken == nil else { return }
        globalToken = installGlobal { _ in onDismiss() }
        localToken = installLocal { event in
            if shouldClose(event) { onDismiss() }
            return event   // 不吞事件——不論關不關，都讓它照常送達原本的 responder。
        }
    }

    /// 面板解除釘住／關閉（不論誰關的）務必呼叫——同 `QuitKeyMonitor.stopIfNeeded` 的洩漏理由。
    func stopIfNeeded() {
        if let globalToken { remove(globalToken); self.globalToken = nil }
        if let localToken { remove(localToken); self.localToken = nil }
    }
}
