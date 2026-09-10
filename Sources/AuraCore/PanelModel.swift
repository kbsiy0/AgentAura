import Foundation

/// 傳給 `PanelView` 的值——`PanelViewModel` 純函式集合的產出打包（spec §2）。
///
/// 跟 `PanelRow` 一樣**不加 public init**：合成的 memberwise init 只到 internal，
/// 跨模組只能經 `make(icon:sessions:palette:now:)` 建構，測試 fixture 因此一律
/// 走真的資料流，不會有跟生產路徑對不上的手搓值。
public struct PanelModel: Equatable, Sendable {
    public let title: String
    public let rows: [PanelRow]
    public let palette: IconPalette
    public let legend: [LegendItem]
    public let isDefaultPalette: Bool

    /// `rows`／`title` 借用既有的 `PanelViewModel`（已測過的純函式）；`palette` 直接帶入、
    /// `legend` 經 `LegendModel.items(for:)` 組裝、`isDefaultPalette` = `palette.isDefault`。
    public static func make(icon: IconState, sessions: [SessionState], palette: IconPalette,
                            now: Date = Date()) -> PanelModel {
        PanelModel(title: PanelViewModel.title(for: icon),
                  rows: PanelViewModel.rows(from: sessions, now: now),
                  palette: palette,
                  legend: LegendModel.items(for: palette),
                  isDefaultPalette: palette.isDefault)
    }
}
