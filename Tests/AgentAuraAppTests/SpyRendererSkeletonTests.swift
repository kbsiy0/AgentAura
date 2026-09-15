import Testing
import AuraCore

/// T01 composition-root smoke 骨架的自我測試：`SpyRenderer` 新增的 `onAction`／
/// `showPanel()`／`callOrder` 真的記錄得到，供 T08 的 `firstRunOrdering`／
/// `panelActionsAreWired` 直接沿用。**這條合理地是 GREEN**：驗的是 spy 自己的
/// instrumentation，不是還沒接線的 `AppDelegate`（T08）。
@MainActor
@Suite("SpyRenderer 骨架自我驗證")
struct SpyRendererSkeletonTests {

    @Test("onAction 收到的 PanelAction 與送入的相等")
    func onActionReceivesTheDispatchedAction() {
        let spy = SpyRenderer()
        var received: [PanelAction] = []
        spy.onAction = { received.append($0) }

        spy.onAction?(.connect)
        spy.onAction?(.setLaunchAtLogin(true))

        #expect(received == [.connect, .setLaunchAtLogin(true)])
    }

    @Test("callOrder 依序記錄 attachPopover → setPanel → showPanel")
    func callOrderRecordsSequence() {
        let spy = SpyRenderer()
        spy.attachPopover()
        spy.setPanel(.make(icon: .empty, sessions: [], palette: .default,
                          install: .notConnected, version: "1.0", optionsExpanded: false,
                          launchAtLogin: nil, externalTargetPath: nil, banner: nil,
                          systemReduceMotion: false, userReduceMotion: false, iconPlate: true, language: .traditionalChinese))
        spy.showPanel()

        #expect(spy.callOrder == ["attachPopover", "setPanel", "showPanel"])
        #expect(spy.showPanelCallCount == 1)
    }

    @Test("showPanel 可以被呼叫零次——callOrder 與 showPanelCallCount 不會憑空出現")
    func showPanelNotCalledLeavesNoTrace() {
        let spy = SpyRenderer()
        spy.attachPopover()
        #expect(spy.showPanelCallCount == 0)
        #expect(!spy.callOrder.contains("showPanel"))
    }
}
