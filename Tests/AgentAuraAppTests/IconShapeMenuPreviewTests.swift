import Testing
import AppKit
import Foundation
@testable import AgentAuraApp
@testable import AuraCore

/// T35：造型選單開著時縮圖要動起來（使用者原話：「你做一個動畫觸發機制，讓我可以
/// 快速看到套用該圖示的效果」）。
///
/// **這組 gate 刻意不測「真的 timer 會不會準時觸發」**——那是這個 codebase 已經被咬過
/// 三次的絕對時間 flaky 類型（CLAUDE.md「這個 codebase 的 gate 哲學」第 5 條）。
/// `.common` mode 的 timer 在真的 `NSMenu.popUp` 期間會不會觸發，已經用真的
/// `NSApplication` + 真的 `NSMenu.popUp` 手動實測過（見 `IconShapeMenuPreview.swift`
/// 的 doc comment：5 次觸發、且成功用 timer 呼叫 `menu.cancelTracking()` 自己關掉選單；
/// 沒有真的 `NSApplication`／沒有真的 `NSMenu.popUp` 在跑的對照組量到 0 次）。
/// 這裡改測「機制本身有沒有牙齒」：`tick(step:)` 真的推進相位、真的重畫；
/// `targetFPS == 0`（含減少動態）真的不排程；`stop()` 真的收掉 timer。
@MainActor
@Suite("造型選單動畫預覽（T35）")
struct IconShapeMenuPreviewTests {

    static func appearance(_ activity: Activity, reduceMotion: Bool = false) -> IconAppearance {
        AppearancePolicy.appearance(for: IconState(activity: activity, counts: [activity: 1], liveCount: 1),
                                    reduceMotion: reduceMotion)
    }

    /// 逐像素加總 alpha——用來比較「同一個造型在不同相位下畫出來的像素」是不是真的不同，
    /// 不挑單一座標（置中畫布疊過一層，各造型的內容偏移不同，挑固定座標容易撲空）。
    static func totalAlpha(of image: NSImage) throws -> Double {
        let rep = try #require(image.representations.first as? NSBitmapImageRep)
        var total = 0.0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                total += Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            }
        }
        return total
    }

    /// 沿用 `RightClickSendActionGuardTests.repoRoot()` 的既有慣例：往上找 `Package.swift`，
    /// 讀不到就大聲 throw，不讓 gate 空跑（不用 `fatalError`）。
    static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        throw GateFailure("從 \(#filePath) 往上找不到 Package.swift")
    }

    struct GateFailure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    @Test("targetFPS == 0（含使用者開了「減少動態」）不排程 timer，縮圖不會動——可及性承諾")
    func startDoesNotScheduleWhenTargetFPSIsZero() {
        let reduced = Self.appearance(.error, reduceMotion: true)
        #expect(reduced.targetFPS == 0, "這條 gate 的前提是 reduceMotion 真的把 fps 壓成 0")
        let item = NSMenuItem(title: "probe", action: nil, keyEquivalent: "")
        let preview = IconShapeMenuPreview(items: [(.ledStrip, item)], appearance: reduced, showsPlate: true)
        preview.start()
        #expect(preview.timer == nil, "targetFPS == 0 時 start() 不該排程任何 timer")
    }

    @Test("targetFPS > 0 時 start() 真的排程，stop() 真的收掉——不留下背景計時器")
    func startSchedulesAndStopInvalidates() {
        let appearance = Self.appearance(.error)
        #expect(appearance.targetFPS > 0, "這條 gate 的前提是 .error 本來就會動")
        let item = NSMenuItem(title: "probe", action: nil, keyEquivalent: "")
        let preview = IconShapeMenuPreview(items: [(.ledStrip, item)], appearance: appearance, showsPlate: true)
        preview.start()
        #expect(preview.timer != nil, "targetFPS > 0 應該排程了一顆 timer，才量得出 stop() 有沒有收")
        preview.stop()
        #expect(preview.timer == nil, "stop() 之後 timer 必須是 nil，否則選單關了背景還在重畫")
    }

    @Test("tick(step:) 推進相位、真的重畫——同一個造型在不同相位下像素明顯不同（動畫真的推進）")
    func tickAdvancesPhaseAndChangesRenderedPixels() throws {
        // .error 是 doubleBlink(period: 1.1)：phase 0 落在「亮」（alpha 1.0），
        // phase 0.5 落在兩段亮區間之外的「暗」（alpha 0.08）——12 倍的落差，
        // 用來跟反鋸齒的雜訊量級（±1px 邊緣）拉開，不會誤判成量測雜訊。
        //
        // **`showsPlate: false`（刻意）**：底板是不透明填色，LED 用 sourceOver 疊上去時，
        // Porter-Duff over 疊在「已經不透明」的底上，結果 alpha 恆為 1（不透明＋任何 alpha
        // 的來源＝還是不透明）——活動色的暗只會反映在 RGB 混色上，alpha 通道量不出來。
        // 關掉底板讓 LED 直接畫在透明畫布上，alpha 通道才會等於真正的
        // `c.a * AnimationCurve.alpha(...)`，這裡才量得出「有沒有變暗」。
        let appearance = Self.appearance(.error)
        let shape = IconShape.ledStrip
        let item = NSMenuItem(title: "probe", action: nil, keyEquivalent: "")
        item.image = IconShapePreview.image(for: shape, appearance: appearance.staticFullyOpaque, showsPlate: false)
        let before = try Self.totalAlpha(of: try #require(item.image))

        let preview = IconShapeMenuPreview(items: [(shape, item)], appearance: appearance, showsPlate: false)
        preview.tick(step: 0.5)
        #expect(preview.phase == 0.5)
        let after = try Self.totalAlpha(of: try #require(item.image))

        #expect(after < before * 0.5, """
            phase 從 0 推進到 0.5 之後像素總 alpha 從 \(before) 只變成 \(after)，
            沒有明顯變暗——doubleBlink 在 phase 0.5 應該落在暗區間（0.08），
            tick(step:) 可能沒有真的重畫，或沒有把新 phase 傳給 IconShapePreview.image。
            """)
    }

    @Test("tick(step:) 涵蓋 items 陣列裡每一項——不是只重畫第一個")
    func tickUpdatesEveryItem() throws {
        // 同上一條：關掉底板讓 alpha 通道能反映動畫（見上面 doc comment）。
        let appearance = Self.appearance(.error)
        let itemA = NSMenuItem(title: "a", action: nil, keyEquivalent: "")
        let itemB = NSMenuItem(title: "b", action: nil, keyEquivalent: "")
        itemA.image = IconShapePreview.image(for: .ledStrip, appearance: appearance.staticFullyOpaque, showsPlate: false)
        itemB.image = IconShapePreview.image(for: .dot, appearance: appearance.staticFullyOpaque, showsPlate: false)
        let beforeA = try Self.totalAlpha(of: try #require(itemA.image))
        let beforeB = try Self.totalAlpha(of: try #require(itemB.image))

        let preview = IconShapeMenuPreview(items: [(.ledStrip, itemA), (.dot, itemB)],
                                           appearance: appearance, showsPlate: false)
        preview.tick(step: 0.5)

        let afterA = try Self.totalAlpha(of: try #require(itemA.image))
        let afterB = try Self.totalAlpha(of: try #require(itemB.image))
        #expect(afterA < beforeA * 0.5, "第一項沒有跟著 tick 變暗")
        #expect(afterB < beforeB * 0.5, "第二項沒有跟著 tick 變暗——tick 可能只更新了陣列的第一個元素")
    }

    /// `IconShapeMenu.present` 真的呼叫 `menu.popUp(...)`，是阻塞呼叫，測試裡不能真的觸發
    /// （會卡住整個測試行程）。這裡改用 source scan 驗證接線順序：`start()` 在 `popUp` 之前、
    /// `stop()` 在 `popUp` 之後——同 `RightClickSendActionGuardTests` 的既有慣例（平台不肯
    /// 讓我們安全地驗證阻塞呼叫，就問原始碼）。
    ///
    /// 掃描對象**從磁碟找出 `IconShapeMenu` 實際住在哪一個檔**，不寫死路徑
    /// （`/simplify` icon-shapes 波次）：原本寫死 `AppEnvironment.swift`，型別搬家時
    /// 這條就紅了——而它守的是「接線順序」，不是「住在哪個檔」。寫死的路徑讓一次無害的
    /// 搬檔看起來像壞了接線，同 CLAUDE.md gate 哲學第 2 條（從磁碟推導，不寫死）。
    @Test("IconShapeMenu.present 接線：start() 在 popUp 之前、stop() 在 popUp 之後")
    func presentWiresPreviewAroundPopUp() throws {
        let root = try Self.repoRoot().appendingPathComponent("Sources/AgentAuraApp")
        let urls = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        let sources = try urls.map { try String(contentsOf: $0, encoding: .utf8) }
        let source = try #require(sources.first { $0.contains("enum IconShapeMenu") }, """
            `Sources/AgentAuraApp/` 底下找不到宣告 `enum IconShapeMenu` 的檔案 ——
            造型選單的型別不見了，或改名了。
            """)

        guard let startRange = source.range(of: "preview.start()"),
              let popUpRange = source.range(of: "menu.popUp("),
              let stopRange = source.range(of: "preview.stop()") else {
            Issue.record("`AppEnvironment.swift` 裡找不到 `preview.start()` / `menu.popUp(` / `preview.stop()` 三者之一——動畫預覽可能沒有接上 present(...)")
            return
        }
        #expect(startRange.lowerBound < popUpRange.lowerBound,
                "start() 必須在 popUp 之前呼叫，否則選單一開始是靜態的，動畫要等第一次 tick 才會出現")
        #expect(popUpRange.lowerBound < stopRange.lowerBound,
                "stop() 必須在 popUp 回傳之後才呼叫，否則動畫在選單還開著的時候就被關掉")
    }
}
