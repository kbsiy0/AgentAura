import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// G6（spec §6.3）：`PanelFooterView` 真的用 `healthTone` 畫 chip 色、真的把版本字串印到畫面。
/// **一律以 `wildPalette` 渲**（N11：以 `.default` 渲時 chip 色與圖例點同色，mutation 抓不到——
/// `.default.done` 與 `healthTone.ok` 同色、`.default.waiting` 與 `.warn` 同色）。
/// G11（`healthTonesDontCollideWithPixelFixtures`）是這條 gate 的前提，放在同一檔。
@MainActor
@Suite("Footer 健康 chip 與版本（G6／G11）")
struct FooterPixelTests {

    func session(_ id: String, _ a: Activity) -> SessionState {
        SessionState(id: id, projectName: id,
                    permissionMode: nil, effort: nil, model: nil,
                    activity: a, mainActivity: a, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    func model(install: InstallState, version: String = "1.0") -> PanelModel {
        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)
        return PanelModel.make(icon: icon, sessions: [session("a", .working)], palette: PanelPixelTests.wildPalette,
                               install: install, version: version, optionsExpanded: false,
                               launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
    }

    func renderPanel(_ m: PanelModel) throws -> OffscreenRender.Bitmap {
        let hosting = NSHostingView(rootView: PanelView(model: m, onAction: { _ in }))
        let height = max(hosting.fittingSize.height, 44)
        return try RenderPinned.render(hosting, appearance: .aqua, canvas: NSSize(width: 380, height: height))
    }

    @Test("(a) connected → ok 色 chip ≥ 100 px；notConnected → warn 色 chip ≥ 100 px（wildPalette）")
    func chipColorReflectsHealthTone() throws {
        let connectedBitmap = try renderPanel(model(install: .connected(owner: .thisApp, verified: .verified)))
        let okHits = connectedBitmap.count(near: HealthTone.ok.color)
        #expect(okHits >= 100, "connected 狀態下 ok 色像素只有 \(okHits) —— chip 沒有真的用 healthTone 畫色")

        let notConnectedBitmap = try renderPanel(model(install: .notConnected))
        let warnHits = notConnectedBitmap.count(near: HealthTone.warn.color)
        #expect(warnHits >= 100, "notConnected 狀態下 warn 色像素只有 \(warnHits) —— chip 沒有真的用 healthTone 畫色")
    }

    @Test("(b) 版本差異渲染：v0.1.0 vs v9.9.9 差異 ≥ 300 px；同內容連渲差異 == 0")
    func versionTextReachesTheView() throws {
        let connected = InstallState.connected(owner: .thisApp, verified: .verified)
        let v1 = try renderPanel(model(install: connected, version: "0.1.0"))
        let v2 = try renderPanel(model(install: connected, version: "9.9.9"))
        let diff = try DifferingPixels.count(v1, v2)
        #expect(diff >= 300, "v0.1.0 與 v9.9.9 的渲染差異只有 \(diff) px —— 版本字串可能沒有真的印到畫面上")

        let v1Again = try renderPanel(model(install: connected, version: "0.1.0"))
        let sameDiff = try DifferingPixels.count(v1, v1Again)
        #expect(sameDiff == 0, "同內容連渲兩次應該完全一致，實際差異 \(sameDiff) px")
    }

    @Test("(c) 前提：離屏渲染非背景像素 > 2000（RenderPinned 內建，不另外斷言）")
    func renderPinnedPreconditionHolds() throws {
        _ = try renderPanel(model(install: .notConnected))   // 沒有 throw 就代表前提斷言通過
    }

    @Test("G11：healthTone.ok／.warn 與 wildPalette 五色的 maxComponentDelta > 0.063（8 × count(near:) tolerance 2/255）")
    func healthTonesDontCollideWithWildPalette() {
        let wild = PanelPixelTests.wildPalette
        let wildColors = [wild.idle, wild.working, wild.done, wild.waiting, wild.error]
        for tone in [HealthTone.ok, HealthTone.warn] {
            for color in wildColors {
                let delta = tone.color.maxComponentDelta(color)
                #expect(delta > 0.063, """
                    \(tone) 色（\(tone.color)）與 wildPalette 某色（\(color)）delta 只有 \(delta)——
                    低於門檻代表 G6 的顏色 mutation 可能被這個 wild 色蓋過去而測不出來
                    """)
            }
        }
    }
}
