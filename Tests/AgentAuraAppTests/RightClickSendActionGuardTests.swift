import Testing
import Foundation

/// 實機清單 ⑥「右鍵開 Options」回報不通過之後的追查產物（2026-09-12）。
///
/// **追查結論：重現不出來。** 用一個帶診斷輸出、輸出直接寫檔的建置（NSLog 沒有進統一日誌，
/// 那一段自己也繞了一圈）在真機上量了三輪，每一輪都正常：
/// - 真實右鍵的 `NSApp.currentEvent?.type` 原始值恆為 **4**（`.rightMouseUp`），
///   獨立的最小 status-item 探針也量到同一個值。
/// - 滑鼠命中的 view 是 `LEDStripView`（LED 自訂 view **不會**把右鍵吃掉），
///   點在按鈕文字上與點在燈點正上方，兩者結果一致。
/// - `onRightClick` 每次都觸發、`optionsExpanded` 每次都被設為 `true`，使用者確認面板展開。
/// - 另外順手推翻一個假設：換 `rootView` 之後 `preferredContentSize` **立刻**反映新高度
///   （250 → 542pt，不需要額外的 layout pass），所以「面板用舊尺寸顯示、把展開區裁掉」不成立。
///
/// **但追查暴露了一個真的缺口，就是這條 gate 存在的理由。**
/// `RightClickOpensOptionsTests` 注入假的 `currentEventType`，證明的是「**如果**事件是右鍵，
/// 分流會正確」；它完全沒有碰「按鈕有沒有被設定成右鍵也送 action」這件事。那件事只有
/// `attachPopover()` 裡的 `sendAction(on:)` 在做，而 AppKit **沒有讀回該遮罩的 API**
/// （`NSCell.sendAction(on:)` 回傳舊遮罩，沒有 getter），所以離屏斷言不到。
///
/// 拿掉那一行的後果：右鍵會**安靜地**停止抵達 action，面板照常用左鍵開，
/// 而現有全部測試照樣全綠——典型的 tested ≠ wired。既然平台不肯回答，就問原始碼。
/// 這是 CLAUDE.md gate 哲學第 1 條（平台契約要問平台）在平台無法作答時的退路，
/// 不是偷懶：它守的是一行不可觀測但必要的設定。
@Suite("右鍵送 action 的設定不得消失（⑥ 追查的副產品）")
struct RightClickSendActionGuardTests {

    /// 沿用 `AboutContentTests.repoRoot()` 的既有慣例（同一個 target 看不到 `AuraCoreTests`
    /// 的 `Gate`）。這裡不用 `fatalError`——讀不到就大聲 throw，不讓 gate 空跑。
    static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        throw GateFailure("從 \(#filePath) 往上找不到 Package.swift")
    }

    struct GateFailure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    @Test("StatusItemController 必須把 status item 按鈕設定成右鍵也送 action")
    func buttonSendsActionOnRightMouseUp() throws {
        let url = try Self.repoRoot()
            .appendingPathComponent("Sources/AgentAuraApp/StatusItemController.swift")
        let source = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }   // 註解不算數

        let sendActionLines = lines.filter { $0.contains("sendAction(on:") }
        #expect(!sendActionLines.isEmpty, """
            `StatusItemController.swift` 裡找不到 `sendAction(on:` —— status item 的按鈕
            預設只在左鍵放開時送 action，右鍵會安靜地完全不抵達 `togglePopover`，
            B1 的右鍵快速路徑因此變成死碼。AppKit 沒有讀回這個遮罩的 API，這條只能問原始碼。
            """)
        #expect(sendActionLines.contains { $0.contains(".rightMouseUp") }, """
            有 `sendAction(on:` 但沒有 `.rightMouseUp` —— 實測（2026-09-12 真機）右鍵送到
            action 時 `NSApp.currentEvent?.type` 的原始值是 4（`.rightMouseUp`），
            `togglePopover` 正是拿它分流。遮罩裡少了它，右鍵就不會送 action。
            實際找到的行：\(sendActionLines)
            """)
        #expect(sendActionLines.contains { $0.contains(".leftMouseUp") }, """
            遮罩覆寫掉預設值，所以 `.leftMouseUp` 必須明寫 —— 少了它會把左鍵
            （面板的主要開啟方式）一起關掉。
            """)
    }
}
