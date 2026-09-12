import AppKit
import AuraCore

/// `LEDStripView` 遵守的介面。
///
/// 照 `IconRendering`（`StatusItemController.swift`）的寫法：protocol 存在是為了
/// 可測性，不是抽象癖——`StatusItemController` 的 `drawing: any IconDrawing` 讓
/// composition-root smoke（`statusItemBuildsTheWinner`）與像素 gate 測得到接線，
/// 讓 `StatusItemController` 不綁死 view 型別（未來第二個 conformer 的接線縫）；測試仍以 `@testable import` 讀 `drawing`。
///
/// M4 A/B 決策已定案選 A2（`docs/2026-09-09-m4-ab-decision.md`）：落選形態的 view 與
/// 開發期切換用的型別已隨 T09 一併刪除（spec §4.3 評後刪）。
@MainActor
protocol IconDrawing: AnyObject {
    func update(_ appearance: IconAppearance, phase: Double)
    var preferredWidth: CGFloat { get }
    /// T16：使用者控制的底板可見度（預設 true）——`false` 時只畫 LED，不畫底板填色／描邊。
    func setShowsPlate(_ shows: Bool)
}
