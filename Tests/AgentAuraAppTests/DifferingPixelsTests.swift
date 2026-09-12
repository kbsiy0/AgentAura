import Testing
import AppKit
import AuraCore
@testable import AgentAuraApp

/// T01 項目 4 的自我測試：同內容 → 0（spec 明訂的自我測試）；不同內容 → > 0；
/// 尺寸不同 → throw。**這條合理地是 GREEN**：驗的是 helper 本身。
@MainActor
@Suite("DifferingPixels 自我驗證")
struct DifferingPixelsTests {

    func renderLED(_ activity: Activity) throws -> OffscreenRender.Bitmap {
        let view = LEDStripView()
        let icon = IconState(activity: activity, counts: [activity: 1], liveCount: 1)
        view.update(AppearancePolicy.appearance(for: icon), phase: 0)
        return try RenderPinned.render(view, appearance: .aqua,
                                       canvas: NSSize(width: LEDStripView.preferredWidth, height: 20))
    }

    @Test("同內容連渲兩次 → 0（spec §6.1 明訂的自我測試）")
    func sameContentYieldsZero() throws {
        let a = try renderLED(.working)
        let b = try renderLED(.working)
        #expect(try DifferingPixels.count(a, b) == 0)
    }

    @Test("不同內容 → 差異像素數 > 0")
    func differentContentYieldsPositiveCount() throws {
        let a = try renderLED(.working)
        let b = try renderLED(.error)
        #expect(try DifferingPixels.count(a, b) > 0)
    }

    @Test("尺寸不同 → throw SizeMismatch，不安靜回無意義的數字")
    func mismatchedSizeThrows() throws {
        let small = try RenderPinned.render(LEDStripView(), appearance: .aqua, canvas: NSSize(width: 42, height: 20),
                                            minimumForegroundPixels: 0)
        let big = try RenderPinned.render(LEDStripView(), appearance: .aqua, canvas: NSSize(width: 80, height: 40),
                                          minimumForegroundPixels: 0)
        #expect(throws: DifferingPixels.SizeMismatch.self) {
            _ = try DifferingPixels.count(small, big)
        }
    }
}
