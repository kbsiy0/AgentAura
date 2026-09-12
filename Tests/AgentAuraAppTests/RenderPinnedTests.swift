import Testing
import AppKit
import AuraCore
@testable import AgentAuraApp

/// T01 項目 3 的自我測試：正向對照（真內容成功）＋ 負對照（空白 view 觸發前提斷言）。
/// **這條合理地是 GREEN**：驗的是 helper 本身，不是還沒寫的 `Installer`／面板新欄位。
/// 用既有的 `LEDStripView`（已定案贏家）當正向對照，不另造 probe view。
@MainActor
@Suite("RenderPinned 自我驗證")
struct RenderPinnedTests {

    @Test("正向：LEDStripView 畫出真內容時，renderPinned 成功回傳點陣圖（.aqua）")
    func rendersRealContentSuccessfully() throws {
        let view = LEDStripView()
        let icon = IconState(activity: .error, counts: [.error: 1], liveCount: 1)
        view.update(AppearancePolicy.appearance(for: icon), phase: 0)
        let bitmap = try RenderPinned.render(view, appearance: .aqua,
                                             canvas: NSSize(width: LEDStripView.preferredWidth, height: 20))
        #expect(bitmap.context.width > 0 && bitmap.context.height > 0)
    }

    @Test("正向：深色 appearance 搭配深色背景也成功（S0-Q2 的兩態都要釘）")
    func rendersRealContentSuccessfullyInDarkAppearance() throws {
        let view = LEDStripView()
        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)
        view.update(AppearancePolicy.appearance(for: icon), phase: 0)
        // 背景刻意用純黑，不是 LEDStripView 自己的不透明底板色（#141416）——
        // 兩者太接近會讓底板本身併入「背景」，只剩 LED 反鋸齒邊緣算前景，
        // 門檻因此測不出「真的有畫東西」。
        let bitmap = try RenderPinned.render(
            view, appearance: .darkAqua, canvas: NSSize(width: LEDStripView.preferredWidth, height: 20),
            over: .black)
        #expect(bitmap.context.width > 0 && bitmap.context.height > 0)
    }

    @Test("負對照：空白 view（沒有任何內容）觸發前提斷言 throw，不是安靜回一張空白圖")
    func blankViewTripsPrecondition() throws {
        let blank = NSView()
        #expect(throws: RenderPinned.PreconditionFailure.self) {
            _ = try RenderPinned.render(blank, appearance: .aqua, canvas: NSSize(width: 100, height: 100))
        }
    }
}
