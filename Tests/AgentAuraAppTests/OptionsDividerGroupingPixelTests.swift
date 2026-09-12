import AppKit
import SwiftUI
import Testing
import AuraCore
@testable import AgentAuraApp

/// C1（team-lead 收尾）：分隔線只准畫在群組交界，不是每一列都畫。`OptionsMenuModelTests`
/// 已經型別層驗過 `rows` 依 group 連續——這裡補「畫面真的少畫了幾條線」的像素證據
/// （Lessons #5：model 算對 group 不等於 `OptionsSectionView.body` 真的用了它）。
///
/// `AllDividersLayout` 重現退場前的舊行為（每列後面一條 `Divider`）——用**同一個**
/// `OptionsRowContent`（生產型別，只是改成 internal 供這裡重用），差異只在分隔線放置規則，
/// 不是另外重寫一套列內容邏輯，才不會變成「比較自己 vs 自己」。
@MainActor
@Suite("C1：Options 分隔線只在群組交界（像素驗證）", .serialized)
struct OptionsDividerGroupingPixelTests {

    struct AllDividersLayout: View {
        let rows: [OptionsRow]
        let onAction: (PanelAction) -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                ForEach(rows) { row in
                    OptionsRowContent(row: row, onAction: onAction)
                    Divider()
                }
            }
        }
    }

    static let canvas = NSRect(x: 0, y: 0, width: 380, height: 520)

    func render(_ view: some View, appearance: NSAppearance.Name) throws -> OffscreenRender.Bitmap {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = Self.canvas
        return try OffscreenRender.render(hosting, over: .white)
    }

    static func worstCaseModel() -> PanelModel {
        PanelModel.make(icon: .empty, sessions: [], palette: .default,
                        install: .connected(owner: .external, verified: .unknown), version: "1.0",
                        optionsExpanded: true, launchAtLogin: true, externalTargetPath: nil, banner: nil,
                        systemReduceMotion: true, userReduceMotion: false, iconPlate: true)
    }

    @Test("worst-case：production OptionsSectionView（分組）vs 每列都隔開的對照組，像素明顯不同")
    func groupedDiffersFromAllDividers() throws {
        let model = Self.worstCaseModel()
        let rows = OptionsMenuModel.rows(install: model.install, launchAtLogin: model.launchAtLogin,
                                         isDefaultPalette: model.isDefaultPalette,
                                         systemReduceMotion: model.systemReduceMotion,
                                         userReduceMotion: model.userReduceMotion, iconPlate: model.iconPlate, palette: model.palette)
        #expect(rows.count >= 9, "worst-case 應該有夠多列（含 launchAtLogin／recheckHook）才有代表性，實際 \(rows.count)")

        let grouped = try render(OptionsSectionView(model: model, onAction: { _ in }), appearance: .aqua)
        let allDividers = try render(AllDividersLayout(rows: rows, onAction: { _ in }), appearance: .aqua)
        let diff = try DifferingPixels.count(grouped, allDividers)
        #expect(diff > 500, """
            分組後應該少畫好幾條分隔線，兩張圖的像素差異應該遠大於反鋸齒雜訊，
            實際只有 \(diff) 個像素不同 —— OptionsSectionView.body 可能沒有真的用 group 判斷
            """)
    }

    /// 正向對照：同一個 grouped 渲染跟自己再渲一次必須是 0 差異（前提斷言，harness 空轉要大聲紅）。
    @Test("正向對照：grouped 渲染跟自己再渲一次是 0 差異")
    func groupedRenderIsDeterministic() throws {
        let model = Self.worstCaseModel()
        let a = try render(OptionsSectionView(model: model, onAction: { _ in }), appearance: .aqua)
        let b = try render(OptionsSectionView(model: model, onAction: { _ in }), appearance: .aqua)
        #expect(try DifferingPixels.count(a, b) == 0, "同內容重渲兩次應該逐像素相同，harness 本身若不穩定，上面那條 gate 就不可信")
    }
}
