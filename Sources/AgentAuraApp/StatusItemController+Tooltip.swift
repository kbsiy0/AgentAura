import AppKit
import AuraCore

/// tooltip 相關的成員住在這裡——理由同 `StatusItemController+Dismiss.swift`／
/// `+IconFrame.swift`：純粹為了不撞 200 行上限才拆檔，不是抽象邊界。
///
/// tooltip 有**三個**獨立輸入，各自從不同路徑進來，所以都存最後一次收到的值：
/// 動畫幀（`apply`）· 安裝狀態（`setInstallState`）· 語言（`setPanel` 帶著 `PanelModel` 來）。
extension StatusItemController {
    /// T16：轉發到 `drawing`（自己管 `needsDisplay`，同 `update(_:phase:)` 的模式）。
    /// T32：順便快取進 `showsPlate`——`setIconShape` 換掉 `drawing` 時要用它延續偏好。
    func setIconPlate(_ shows: Bool) {
        showsPlate = shows
        drawing.setShowsPlate(shows)
    }

    func updateTooltip() {
        item.button?.toolTip = TooltipText.text(appearance: lastAppearance, install: installState,
                                                language: language)
    }

    /// 測試觀測用：真的 `NSStatusItem.button.toolTip`，不是重算一份平行邏輯。
    var currentTooltip: String? { item.button?.toolTip }

    /// 舊窄簽章轉發（`PanelHostingTests.tooltipNeverNegative` 對齊，不必跟著改）。
    static func tooltip(for a: IconAppearance, language: Language) -> String {
        TooltipText.sessionSummary(a, language: language)
    }
}
