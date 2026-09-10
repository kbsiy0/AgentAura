import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// spec `2026-09-09-panel-legend-palette-design.md` §6：`legendDotsUsePalette`、`rowDotsUsePalette`。
///
/// **`NSHostingView(rootView:)` → `OffscreenRender.render`，不是 `ImageRenderer`**——reviewer
/// 實測 `ImageRenderer` 不渲 `ScrollView` 內容（spec §6 review B1）。fixture 一律經
/// `PanelViewModel.rows(from:)`／`PanelModel.make`（不加 public init、不 `@testable import AuraCore`）。
@MainActor
@Suite("面板像素（圖例／列色點吃 palette）")
struct PanelPixelTests {

    /// 五色彼此差異極大、五色 a 皆 1——本檔獨立定義（避免跨檔耦合到 `RendererPixelTests.honorPalette`）。
    static let wildPalette = IconPalette(
        idle:    RGBA(r: 0.05, g: 0.85, b: 0.35, a: 1),
        working: RGBA(r: 0.95, g: 0.05, b: 0.65, a: 1),
        done:    RGBA(r: 0.15, g: 0.25, b: 0.95, a: 1),
        waiting: RGBA(r: 0.85, g: 0.75, b: 0.05, a: 1),
        error:   RGBA(r: 0.05, g: 0.75, b: 0.85, a: 1))

    func session(_ id: String, _ a: Activity) -> SessionState {
        SessionState(id: id, projectName: id, projectPath: nil,
                    permissionMode: nil, effort: nil, model: nil,
                    activity: a, mainActivity: a, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    func renderPanel(_ model: PanelModel) throws -> OffscreenRender.Bitmap {
        let hosting = NSHostingView(rootView: PanelView(model: model))
        let height = max(hosting.fittingSize.height, 44)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: height)
        return try OffscreenRender.render(hosting, over: .white)
    }

    @Test("圖例色點吃 palette：rows 空與非空都畫；wild 四色各 ≥ 200 px；.default 渲時 wild 色 0 px（對抗式）")
    func legendDotsUsePalette() throws {
        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)

        for (label, sessions) in [("空 rows", [SessionState]()), ("非空 rows", [session("a", .working)])] {
            let wildModel = PanelModel.make(icon: icon, sessions: sessions, palette: Self.wildPalette)
            let wildBitmap = try renderPanel(wildModel)
            for activity in [Activity.error, .waiting, .working, .done] {
                let hits = wildBitmap.count(near: Self.wildPalette[activity])
                #expect(hits >= 200, """
                    \(label)／wild palette／.\(activity) 圖例點像素數 \(hits) < 200 —— 圖例沒有真的用 palette 畫色點
                    """)
            }

            let defaultModel = PanelModel.make(icon: icon, sessions: sessions, palette: .default)
            let defaultBitmap = try renderPanel(defaultModel)
            for activity in [Activity.error, .waiting, .working, .done] {
                let hits = defaultBitmap.count(near: Self.wildPalette[activity])
                #expect(hits == 0, """
                    \(label)／用 .default 渲染時，wild palette 的 .\(activity) 色不該出現，實際 \(hits) px
                    """)
            }
        }
    }

    @Test("單列色點吃 palette：wild 四色各 ≥ 120 px；.default 渲時 wild 色 0 px（對抗式）")
    func rowDotsUsePalette() throws {
        for activity in [Activity.error, .waiting, .working, .done] {
            let row = try #require(PanelViewModel.rows(from: [session("r", activity)]).first,
                "前提：至少要生得出一列")

            let wildHosting = NSHostingView(rootView: PanelRowView(row: row, palette: Self.wildPalette))
            wildHosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(wildHosting.fittingSize.height, 30))
            let wildBitmap = try OffscreenRender.render(wildHosting, over: .white)
            let wildHits = wildBitmap.count(near: Self.wildPalette[activity])
            #expect(wildHits >= 120, ".\(activity) 列色點像素數 \(wildHits) < 120 —— PanelRowView 沒有真的用 palette 畫色點")

            let defaultHosting = NSHostingView(rootView: PanelRowView(row: row, palette: .default))
            defaultHosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(defaultHosting.fittingSize.height, 30))
            let defaultBitmap = try OffscreenRender.render(defaultHosting, over: .white)
            let defaultHits = defaultBitmap.count(near: Self.wildPalette[activity])
            #expect(defaultHits == 0, ".\(activity) 用 .default 渲染時 wild 色不該出現，實際 \(defaultHits) px")
        }
    }

    /// review-t0406 I3 ＋ closure C4：列色點要忽略 palette 的 alpha（idle a=0.35 在白底面板只有 1.31:1）。
    /// 兩條主 gate 的 wild palette 五色 a 皆 1，看不出有沒有乘 alpha——這條專守 idle。
    @Test("idle 列色點忽略 alpha：以 .default 渲一列 idle，全不透明的 #48484a ≥ 120 px")
    func idleRowDotIgnoresAlpha() throws {
        let row = try #require(PanelViewModel.rows(from: [session("idle-row", .idle)]).first)
        let hosting = NSHostingView(rootView: PanelRowView(row: row, palette: .default))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 30))
        let bitmap = try OffscreenRender.render(hosting, over: .white)
        let opaqueIdle = RGBA(r: 72.0 / 255, g: 72.0 / 255, b: 74.0 / 255, a: 1)
        let hits = bitmap.count(near: opaqueIdle)
        #expect(hits >= 120, "idle 列色點應以不透明 #48484a 畫出（≥120 px），實際 \(hits) —— 0.35 alpha 疊白底會變成 #c0c0c0，面板上看不見")
    }
}
