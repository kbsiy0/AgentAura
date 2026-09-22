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
        SessionState(id: id, projectName: id,
                    permissionMode: nil, effort: nil, model: nil,
                    activity: a, mainActivity: a, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    func renderPanel(_ model: PanelModel) throws -> OffscreenRender.Bitmap {
        let hosting = NSHostingView(rootView: PanelView(model: model, onAction: { _ in }))
        let height = max(hosting.fittingSize.height, 44)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: height)
        return try OffscreenRender.render(hosting, over: .white)
    }

    /// T19（對齊新契約，非弱化）：門檻從 200 降到 150——`DotRing`（配套 B）給每個色點加了
    /// 一圈 1pt 邊線，邊線本身吃掉一圈原本算「純色」的像素（實測純色區從 200+ 降到 172，
    /// 邊線越粗吃越多，這是加邊線的必然代價，不是實作退步）。150 對實測 172 仍留 ~13% margin，
    /// 而且離「palette 完全沒接上」（0 px，下面那條負向斷言在守）差了一個數量級，mutation
    /// 力道沒被削弱。
    @Test("圖例色點吃 palette：rows 空與非空都畫；wild 四色各 ≥ 150 px；.default 渲時 wild 色 0 px（對抗式）")
    func legendDotsUsePalette() throws {
        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)

        for (label, sessions) in [("空 rows", [SessionState]()), ("非空 rows", [session("a", .working)])] {
            let wildModel = PanelModel.make(icon: icon, sessions: sessions, palette: Self.wildPalette,
                                            install: .notConnected, version: "1.0", optionsExpanded: false,
                                            launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
            let wildBitmap = try renderPanel(wildModel)
            for activity in [Activity.error, .waiting, .working, .done] {
                let hits = wildBitmap.count(near: Self.wildPalette[activity])
                #expect(hits >= 150, """
                    \(label)／wild palette／.\(activity) 圖例點像素數 \(hits) < 150 —— 圖例沒有真的用 palette 畫色點
                    """)
            }

            let defaultModel = PanelModel.make(icon: icon, sessions: sessions, palette: .default,
                                               install: .notConnected, version: "1.0", optionsExpanded: false,
                                               launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
            let defaultBitmap = try renderPanel(defaultModel)
            for activity in [Activity.error, .waiting, .working, .done] {
                let hits = defaultBitmap.count(near: Self.wildPalette[activity])
                #expect(hits == 0, """
                    \(label)／用 .default 渲染時，wild palette 的 .\(activity) 色不該出現，實際 \(hits) px
                    """)
            }
        }
    }

    /// T19：門檻從 120 降到 70，理由同 `legendDotsUsePalette`（`DotRing` 邊線吃掉一圈純色像素，
    /// 8pt 列色點比 10pt 圖例色點小，被吃掉的比例更高——實測純色區從 120+ 降到 88，70 對實測 88
    /// 仍留 ~20% margin）。
    @Test("單列色點吃 palette：wild 四色各 ≥ 70 px；.default 渲時 wild 色 0 px（對抗式）")
    func rowDotsUsePalette() throws {
        for activity in [Activity.error, .waiting, .working, .done] {
            let row = try #require(PanelViewModel.rows(from: [session("r", activity)], language: .traditionalChinese).first,
                "前提：至少要生得出一列")

            let wildHosting = NSHostingView(rootView: PanelRowView(row: row, palette: Self.wildPalette))
            wildHosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(wildHosting.fittingSize.height, 30))
            let wildBitmap = try OffscreenRender.render(wildHosting, over: .white)
            let wildHits = wildBitmap.count(near: Self.wildPalette[activity])
            #expect(wildHits >= 70, ".\(activity) 列色點像素數 \(wildHits) < 70 —— PanelRowView 沒有真的用 palette 畫色點")

            let defaultHosting = NSHostingView(rootView: PanelRowView(row: row, palette: .default))
            defaultHosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(defaultHosting.fittingSize.height, 30))
            let defaultBitmap = try OffscreenRender.render(defaultHosting, over: .white)
            let defaultHits = defaultBitmap.count(near: Self.wildPalette[activity])
            #expect(defaultHits == 0, ".\(activity) 用 .default 渲染時 wild 色不該出現，實際 \(defaultHits) px")
        }
    }

    /// review-t0406 I3 ＋ closure C4：列色點要忽略 palette 的 alpha（idle a=0.35 在白底面板只有 1.31:1）。
    /// 兩條主 gate 的 wild palette 五色 a 皆 1，看不出有沒有乘 alpha——這條專守 idle。
    /// T19：門檻從 120 降到 70，理由同 `rowDotsUsePalette`（`DotRing` 邊線吃掉一圈純色像素，
    /// 實測純色區從 120+ 降到 88，70 對實測 88 仍留 ~20% margin）。
    @Test("idle 列色點忽略 alpha：以 .default 渲一列 idle，全不透明的 #48484a ≥ 70 px")
    func idleRowDotIgnoresAlpha() throws {
        let row = try #require(PanelViewModel.rows(from: [session("idle-row", .idle)], language: .traditionalChinese).first)
        let hosting = NSHostingView(rootView: PanelRowView(row: row, palette: .default))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 30))
        let bitmap = try OffscreenRender.render(hosting, over: .white)
        let opaqueIdle = RGBA(r: 72.0 / 255, g: 72.0 / 255, b: 74.0 / 255, a: 1)
        let hits = bitmap.count(near: opaqueIdle)
        #expect(hits >= 70, "idle 列色點應以不透明 #48484a 畫出（≥70 px），實際 \(hits) —— 0.35 alpha 疊白底會變成 #c0c0c0，面板上看不見")
    }

    /// T19 配套 B（對抗式）：`.default` 的 working 改成白色之後，圖例色點／列色點在淺色卡片背景上
    /// 沒有邊線會直接跟背景同色、視覺上消失。
    ///
    /// **不是「數某個灰色像素數」**——第一版這樣寫過，mutation 沒紅：整張 `PanelView` 渲染本身
    /// 就有大量 `.secondary`／`.tertiary` 文字反鋸齒與 `.quaternary` 卡片邊框，掃到的灰階雜訊
    /// 底噪高達數百 px，跟拿掉 `DotRing` 之後「消失的那圈」量級相當，色彩比對法測不出差異
    /// （已用 `count(near:)` 逐灰階實測驗證）。改用 `DifferingPixels` 比較兩張**單獨渲染、
    /// 只有色點邊線這一處不同**的圖：真的 `PanelRowView`／`LegendRowView`（production，含
    /// `DotRing`）vs 同一份佈局但色點是純 `Circle().fill(...)`（沒有 `DotRing`）的對照組——
    /// 逐字複製自 production body，唯一差異就是那個 `.overlay`（同
    /// `OptionsDividerGroupingPixelTests.AllDividersLayout` 的手法）。**單獨渲染**（不嵌進整個
    /// `PanelView`）才能讓兩張圖除了色點以外逐像素相同，不會被 title／footer／banner 這些跟色點
    /// 無關的內容稀釋掉。appearance 一定要釘住（`.aqua`）——`DotRing` 用 `Color.primary`，
    /// 深色機器上跑不釘會把它解成白色，邊線變白疊白，等於沒測到。
    /// mutation：拿掉正式碼的 `.overlay(DotRing())`，這條必須紅（已手動驗證，見 commit message）。
    @Test("T19：淺色外觀下，.default 白色 working 的圖例色點與列色點都跟「沒有邊線」的對照組不同")
    func dotRingKeepsWhiteWorkingDotVisibleOnLightCard() throws {
        func pinned(_ view: some View, size: NSSize) throws -> OffscreenRender.Bitmap {
            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: .aqua)
            hosting.frame = NSRect(origin: .zero, size: size)
            return try OffscreenRender.render(hosting, over: .white)
        }

        // (a) 列色點：真的 PanelRowView vs 同佈局但無邊線的對照組。
        let row = try #require(PanelViewModel.rows(from: [session("a", .working)], language: .traditionalChinese).first)
        let rowSize = NSSize(width: 380, height: 30)
        let rowWithRing = try pinned(PanelRowView(row: row, palette: .default), size: rowSize)
        let rowNoRing = try pinned(PanelPixelTests.NoRingRow(row: row, palette: .default), size: rowSize)
        let rowDiff = try DifferingPixels.count(rowWithRing, rowNoRing)
        #expect(rowDiff >= 20, """
            列色點有邊線／無邊線兩張渲染只差 \(rowDiff) px（門檻 20）—— 白色 working 列色點的邊線
            可能沒有真的畫出來，在淺色卡片背景上會直接消失
            """)

        // (b) 圖例色點：真的 LegendRowView vs 同佈局但無邊線的對照組。
        let legend = LegendModel.items(for: .default, language: .traditionalChinese)
        let legendSize = NSSize(width: 380, height: 24)
        let legendWithRing = try pinned(LegendRowView(legend: legend, onAction: { _ in }, language: .traditionalChinese), size: legendSize)
        let legendNoRing = try pinned(PanelPixelTests.NoRingLegend(legend: legend), size: legendSize)
        let legendDiff = try DifferingPixels.count(legendWithRing, legendNoRing)
        #expect(legendDiff >= 20, """
            圖例色點有邊線／無邊線兩張渲染只差 \(legendDiff) px（門檻 20）—— 白色 working 圖例色點的
            邊線可能沒有真的畫出來，在淺色卡片背景上會直接消失
            """)
    }

    /// 上面那條對抗式 gate 的對照組——結構逐字比照 `PanelRowView.body`，唯一差異是色點沒有
    /// `.overlay(DotRing())`（同 `OptionsDividerGroupingPixelTests.AllDividersLayout` 的手法：
    /// 不是重寫一套新邏輯，是拿掉正式碼那一處，其餘逐字複製）。
    struct NoRingRow: View {
        let row: PanelRow
        let palette: IconPalette

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Color(rgba: palette[row.activity], ignoringAlpha: true))
                    .frame(width: 8, height: 8).padding(.top, 6).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.projectName).font(.system(size: 13, weight: .semibold))
                        Text(row.meta).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(row.headline).font(.system(size: 12))
                        .foregroundStyle(row.activity == .error ? .red : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    if !row.footer.isEmpty {
                        Text(row.footer).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
        }
    }

    /// 同上，對照 `LegendRowView.body`（拿掉 `Button`／`.help`／`.onHover`——那些不影響
    /// 靜態像素外觀，只影響互動，逐字複製反而引入跟色點無關的差異來源）。
    struct NoRingLegend: View {
        let legend: [LegendItem]

        var body: some View {
            HStack(spacing: 10) {
                ForEach(legend) { item in
                    HStack(spacing: 4) {
                        Circle().fill(Color(rgba: item.color)).frame(width: 10, height: 10).frame(width: 20, height: 20)
                        Text(item.label).font(.system(size: 11))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 24)
        }
    }

    /// T04 新增 gate：`onPickColor`／`onResetColors` 併入 `onAction` 之後，
    /// view→controller 這一跳原本沒有任何 gate（只有 controller→delegate 那半有，
    /// `PaletteWiringSmokeTests.controllerForwardsPanelCallbacks`）。
    ///
    /// 建真的 `PanelView`、離屏渲染強迫 AppKit 橋接（`.buttonStyle(.borderless)` 橋接成真的
    /// `NSButton`——`.onTapGesture` 不會，實測改用 `Button` 是這條 gate 能存在的前提），
    /// 對每個真的 `NSButton` 呼叫 `performClick(nil)`（不是呼叫閉包本身），斷言 `onAction`
    /// 收到對應的 `PanelAction`。
    /// E16（/simplify 波次2，alt#8）：不數總數、不用位置索引——舊版 `buttons.count == 5`
    /// ＋ `buttons[index]` 已經反過來塑造生產碼（`LegendRowView` 的 ⓘ 因此被寫成不可點的
    /// `Image`，明文標「包成 Button 會變成第 6 顆，讓這條 gate 紅」，CLAUDE.md「八族空轉
    /// 的守衛」同一族）。改成點遍每一顆真的橋接出來的 `NSButton`，收集每次點擊各自觸發的
    /// `PanelAction`，跟從型別推導的期望集合（`Activity.customizable` 的圖例動作 ∪
    /// `.toggleOptions`）比對兩個方向——不再因為按鈕數量或排列順序改變就跟著紅，
    /// 而是清楚指出哪個動作缺了、哪個是意外多出來的，設計上不再需要先繞過這條測試
    /// 才能改 view（例如真的把 ⓘ 做成 `Button`；新按鈕仍需要把新動作補進期望集合，
    /// 這是正確的訊號，不是舊版「數字對不上」那種不知所以然的紅）。
    @Test("真的 PanelView：點遍每個按鈕，收到的 PanelAction 集合恰為型別推導的期望集合")
    func panelViewForwardsAction() throws {
        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)
        // T08（對齊新契約，非弱化）：`.connected` 讓 `showsConnectCTA` 為 false，避免
        // `ConnectCTABannerView` 的「接上」按鈕混進來——這條測的是圖例／footer 按鈕的
        // 轉發，與安裝狀態無關，只是需要一個不多不少的按鈕組合。
        let model = PanelModel.make(icon: icon, sessions: [session("a", .working)], palette: Self.wildPalette,
                                    install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                                    optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
        var received: [PanelAction] = []
        let hosting = NSHostingView(rootView: PanelView(model: model, onAction: { received.append($0) }))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 44))
        _ = try OffscreenRender.render(hosting, over: .white)   // 強迫 layout，AppKit 橋接的按鈕才真的存在

        let buttons = Self.allButtons(in: hosting)
        #expect(!buttons.isEmpty, "至少該有圖例色點與 footer「Options ⌄」橋接成真的 NSButton")

        var receivedByButton: [PanelAction] = []
        for button in buttons {
            received.removeAll()
            button.performClick(nil)
            #expect(received.count == 1, "每顆按鈕應該恰好觸發一個 PanelAction，實際 \(received)")
            receivedByButton.append(contentsOf: received)
        }

        // 期望集合完全從型別推導：`Activity.customizable`（圖例列的定義域，見 `LegendModel`）
        // 的每一個 activity 各一顆 `.pickColor`，加上 footer 唯一的 `.toggleOptions`——
        // 不是寫死「5」或猜按鈕排列順序。
        let expected = Activity.customizable.map { PanelAction.pickColor($0) } + [.toggleOptions]
        #expect(receivedByButton.count == expected.count, """
            點遍所有按鈕收到的動作數應該恰為 \(expected.count)（\(Activity.customizable.count) 個圖例 \
            ＋ 1 個 Options 切換），實際 \(receivedByButton.count)：\(receivedByButton)
            """)
        for action in expected {
            #expect(receivedByButton.contains(action), "期望的動作 \(action) 沒有被任何按鈕觸發到")
        }
        for action in receivedByButton {
            #expect(expected.contains(action), "收到了未預期的動作 \(action)")
        }
    }

    private static func allButtons(in view: NSView) -> [NSButton] {
        var found: [NSButton] = []
        if let button = view as? NSButton { found.append(button) }
        for sub in view.subviews { found.append(contentsOf: allButtons(in: sub)) }
        return found
    }
}
