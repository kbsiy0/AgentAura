import AppKit
import Foundation
import SwiftUI
import Testing
import AuraCore
@testable import AgentAuraApp

/// README 的圖片素材產生器——**離屏渲染真實的生產 view**，不是另外畫的示意圖
/// （同 `Phase2EvidenceRenderer` 的既有慣例與 env gate，平常的 `swift test` 不會跑）。
///
/// 為什麼不用真的螢幕截圖：(1) 這個 repo 要公開，真實截圖會把使用者的專案名稱、路徑、
/// session 標題一起印進去；(2) 選單列 app 的截圖無法在 CI／無頭環境重現；
/// (3) `screencapture` 需要螢幕錄製權限。離屏渲染三個問題都沒有，而且畫出來的
/// **就是使用者會看到的那些 view**。
///
/// 產生：`AURA_RENDER_README=1 swift test --filter ReadmeAssetRenderer`
@MainActor
@Suite("README 素材（env gate）",
      .enabled(if: ProcessInfo.processInfo.environment["AURA_RENDER_README"] == "1"))
struct ReadmeAssetRenderer {

    static let outputDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/readme")

    /// 真實的 app 版本——讀 `Resources/Info.plist`，不在這裡寫死。
    static let bundleVersion: String = {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = dict["CFBundleShortVersionString"] as? String
        else { return "?" }
        return version
    }()

    /// **示範用的假專案名**——公開 repo 的圖片裡不放任何真實專案／路徑／session 標題。
    static let demoProjects = ["api-gateway", "web-dashboard", "etl-pipeline", "mobile-app"]

    static func session(_ name: String, _ activity: Activity, tool: String?, ms: Int?) -> SessionState {
        SessionState(id: name, projectName: name,
                     permissionMode: nil, effort: nil, model: "claude-opus-5",
                     activity: activity, mainActivity: activity, subActivity: nil,
                     currentTool: tool, subagentTool: nil, toolDurationMs: ms,
                     turnStartedAt: nil, subagents: [:], toolFailures: 0,
                     lastMessage: nil, errorType: nil, toolError: nil,
                     liveness: .alive(pid: 1), updatedAt: Date())
    }

    static func model(optionsExpanded: Bool, language: Language) -> PanelModel {
        let sessions = [
            session(demoProjects[0], .waiting, tool: "Bash", ms: nil),
            session(demoProjects[1], .working, tool: "Edit", ms: 2400),
            session(demoProjects[2], .error, tool: "Bash", ms: nil),
            session(demoProjects[3], .done, tool: nil, ms: nil),
        ]
        let counts: [Activity: Int] = [.waiting: 1, .working: 1, .error: 1, .done: 1]
        return PanelModel.make(icon: IconState(activity: .error, counts: counts, liveCount: 4),
                               sessions: sessions, palette: .default,
                               install: .connected(owner: .thisApp, verified: .verified),
                               // 版本號從 bundle 的 Info.plist 讀，不寫死——README 的截圖
                               // 不該顯示一個 app 裡不存在的版本。
                               version: Self.bundleVersion, optionsExpanded: optionsExpanded,
                               launchAtLogin: true, externalTargetPath: nil, banner: nil,
                               systemReduceMotion: false, userReduceMotion: false,
                               iconPlate: true, iconShape: .ledStrip, language: language, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
    }

    static func renderPanel(_ m: PanelModel, over bg: NSColor, _ appearance: NSAppearance.Name) throws -> CGImage {
        let hosting = NSHostingView(rootView: PanelView(model: m, onAction: { _ in }))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 44))
        let bitmap = try OffscreenRender.render(hosting, over: bg)
        guard let image = bitmap.context.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    @Test("面板：亮／暗、收合／展開，英文與繁中各一組")
    func renderPanels() throws {
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        let dark = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        for (lang, suffix) in [(Language.english, ""), (.traditionalChinese, "-zh")] {
            for (expanded, name) in [(false, "panel"), (true, "panel-options")] {
                let m = Self.model(optionsExpanded: expanded, language: lang)
                try EvidenceRenderer.writePNG(try Self.renderPanel(m, over: .white, .aqua),
                                              to: Self.outputDir.appendingPathComponent("\(name)\(suffix)-light.png"))
                try EvidenceRenderer.writePNG(try Self.renderPanel(m, over: dark, .darkAqua),
                                              to: Self.outputDir.appendingPathComponent("\(name)\(suffix)-dark.png"))
            }
        }
    }

    // MARK: - 選單列 icon

    static let statesInOrder: [(Activity, String)] = [
        (.idle, "idle"), (.working, "working"), (.done, "done"), (.waiting, "waiting"), (.error, "error"),
    ]

    /// 動畫週期（秒）。時間 → phase 的換算要用**各自的週期**，不能全部共用一個
    /// ——`working` 是 4.0s 呼吸、`waiting`／`error` 是 1.1s，一起畫才看得出「誰在催你」。
    static func period(of animation: IconAnimation) -> Double {
        switch animation {
        case .none: return 1
        case let .breathe(period, _, _): return period
        case let .doubleBlink(period): return period
        }
    }

    static let cellWidth: CGFloat = 78
    static let barHeight: CGFloat = 26
    static let labelHeight: CGFloat = 15

    /// 一張「選單列橫條」：5 個狀態並排，各自畫在自己的動畫相位上。
    /// `time` 是真實秒數，每個狀態用自己的週期換算 phase。
    static func iconStrip(at time: Double, shape: IconShape = .ledStrip,
                          states: [(Activity, String)]? = nil, scale: CGFloat = 4) throws -> CGImage {
        let cells = states ?? statesInOrder
        let size = NSSize(width: cellWidth * CGFloat(cells.count), height: barHeight + labelHeight)
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw OffscreenRender.SampleError.contextCreationFailed }
        ctx.scaleBy(x: scale, y: scale)
        // 選單列般的深色底——GitHub 的亮／暗主題下都看得清楚。
        ctx.setFillColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        for (i, cell) in cells.enumerated() {
            let appearance = AppearancePolicy.appearance(
                for: IconState(activity: cell.0, counts: [cell.0: 1], liveCount: 1))
            let phase = (time / period(of: appearance.animation)).truncatingRemainder(dividingBy: 1)
            let view = StatusItemController.makeDrawingView(for: shape)
            view.setShowsPlate(true)
            view.update(appearance, phase: phase)
            view.frame = NSRect(x: 0, y: 0, width: view.preferredWidth, height: barHeight)
            let originX = CGFloat(i) * cellWidth + (cellWidth - view.preferredWidth) / 2
            nsCtx.saveGraphicsState()
            ctx.translateBy(x: originX, y: labelHeight)
            view.displayIgnoringOpacity(view.bounds, in: nsCtx)
            nsCtx.restoreGraphicsState()

            let label = NSAttributedString(string: cell.1, attributes: [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
                .foregroundColor: NSColor(srgbRed: 0.62, green: 0.62, blue: 0.65, alpha: 1)])
            let w = label.size().width
            label.draw(at: NSPoint(x: CGFloat(i) * cellWidth + (cellWidth - w) / 2, y: 3))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    @Test("五個狀態的靜態橫條 ＋ 動畫逐格（給 ffmpeg 組 GIF）")
    func renderIconStates() throws {
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        // 靜態圖取 waiting 呼吸的峰值，最能代表「它在叫你」。
        let peak = 1.1 * OffscreenRender.peakPhase(of: .breathe(period: 1.1, min: 0.20, max: 1.00))
        try EvidenceRenderer.writePNG(try Self.iconStrip(at: peak),
                                      to: Self.outputDir.appendingPathComponent("icon-states.png"))

        // 逐格：4.4s＝1.1s 的整數倍，waiting／error 完美循環（working 的 4.0s 呼吸極慢，
        // 接縫處的 alpha 落差小於 0.05，肉眼看不出來）。20fps。
        let frameDir = Self.outputDir.appendingPathComponent("frames")
        try? FileManager.default.removeItem(at: frameDir)
        try FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)
        let fps = 20.0, duration = 4.4
        for i in 0..<Int(fps * duration) {
            let image = try Self.iconStrip(at: Double(i) / fps)
            try EvidenceRenderer.writePNG(image,
                to: frameDir.appendingPathComponent(String(format: "f%03d.png", i)))
        }
    }

    @Test("六種造型並排（每一種都畫在同一個狀態下，差異只來自造型本身）")
    func renderIconShapes() throws {
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        let cells = IconShape.allCases.map { (Activity.waiting, $0.displayName(.english)) }
        let size = NSSize(width: Self.cellWidth * CGFloat(cells.count), height: Self.barHeight + Self.labelHeight)
        let scale: CGFloat = 4
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw OffscreenRender.SampleError.contextCreationFailed }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        let appearance = AppearancePolicy.appearance(
            for: IconState(activity: .waiting, counts: [.waiting: 1], liveCount: 1)).staticFullyOpaque
        for (i, shape) in IconShape.allCases.enumerated() {
            let view = StatusItemController.makeDrawingView(for: shape)
            view.setShowsPlate(true)
            view.update(appearance, phase: 0)
            view.frame = NSRect(x: 0, y: 0, width: view.preferredWidth, height: Self.barHeight)
            nsCtx.saveGraphicsState()
            ctx.translateBy(x: CGFloat(i) * Self.cellWidth + (Self.cellWidth - view.preferredWidth) / 2,
                            y: Self.labelHeight)
            view.displayIgnoringOpacity(view.bounds, in: nsCtx)
            nsCtx.restoreGraphicsState()

            let label = NSAttributedString(string: cells[i].1, attributes: [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
                .foregroundColor: NSColor(srgbRed: 0.62, green: 0.62, blue: 0.65, alpha: 1)])
            let w = min(label.size().width, Self.cellWidth - 4)
            label.draw(at: NSPoint(x: CGFloat(i) * Self.cellWidth + (Self.cellWidth - w) / 2, y: 3))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { throw OffscreenRender.SampleError.noData }
        try EvidenceRenderer.writePNG(image, to: Self.outputDir.appendingPathComponent("icon-shapes.png"))
    }
}
