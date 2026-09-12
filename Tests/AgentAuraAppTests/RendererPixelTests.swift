import AppKit
import Testing
import AuraCore
@testable import AgentAuraApp

/// spec `2026-09-09-m4-icon-form-design.md` §6：`renderersDrawEveryActivityWithoutCrash`、
/// `renderersHonorPalette`、`plateGuaranteesContrast`、`workingIsQuietestColor`。
/// 落選形態的 view 與其專屬 gate（環繞動畫可分性）已隨 T09 一併刪除
/// （A/B 決定選 A2，`docs/2026-09-09-m4-ab-decision.md`）。
@MainActor
@Suite("Renderer 像素 gate")
struct RendererPixelTests {

    static let barHeight: CGFloat = 22
    static let plateSample = CGPoint(x: 2, y: barHeight / 2)

    /// 五色彼此差異極大、五色 a 皆 1——`renderersHonorPalette` 專用非預設 palette。
    static let honorPalette = IconPalette(
        idle:    RGBA(r: 0.90, g: 0.10, b: 0.50, a: 1),
        working: RGBA(r: 0.10, g: 0.90, b: 0.20, a: 1),
        done:    RGBA(r: 0.20, g: 0.20, b: 0.90, a: 1),
        waiting: RGBA(r: 0.90, g: 0.80, b: 0.10, a: 1),
        error:   RGBA(r: 0.10, g: 0.80, b: 0.80, a: 1))

    func makeLED() -> LEDStripView {
        let v = LEDStripView()
        v.frame = NSRect(x: 0, y: 0, width: LEDStripView.preferredWidth, height: Self.barHeight)
        return v
    }

    func icon(_ a: Activity) -> IconState { IconState(activity: a, counts: [a: 1], liveCount: 1) }

    /// 分工（spec §6）：這條取樣的是 LED（`ledRect(at: 3).center`），不是底板——「有沒有畫」由它守，
    /// 「只少畫 LED」由 `plateGuaranteesContrast` 交叉補（review-t04-06 Minor 6）。這個交叉覆蓋
    /// 是 A2 唯一勝因（「LED 真的疊在不透明底板上」）的證人，T09 刪 B2 時保留、不得一起帶走。
    @Test("LED × 5 activity × phase {0,.5} 離屏繪製無 crash、且與純黑背景可分")
    func renderersDrawEveryActivityWithoutCrash() throws {
        let led = makeLED()
        for activity in Activity.allCases {
            for phase in [0.0, 0.5] {
                led.update(AppearancePolicy.appearance(for: icon(activity)), phase: phase)
                let bmp = try OffscreenRender.render(led, over: .black)
                let px = try bmp.pixel(at: led.ledRect(at: 3).center)
                #expect(px != RGBA(r: 0, g: 0, b: 0, a: 1), """
                    LED／.\(activity)／phase \(phase)：取樣點與純黑背景無法區分 —— 沒有畫出任何東西。
                    """)
            }
        }
    }

    private func checkHonorsPalette(_ view: NSView & IconDrawing, sample: CGPoint,
                                    palette: IconPalette, label: String) throws {
        let bg = RGBA(r: 0, g: 0, b: 0, a: 1)
        for activity in Activity.allCases {
            let appearance = AppearancePolicy.appearance(for: icon(activity), palette: palette, reduceMotion: true)
            view.update(appearance, phase: 0)
            let bmp = try OffscreenRender.render(view, over: .black)
            let px = try bmp.pixel(at: sample)
            let expected = OffscreenRender.expected(palette[activity], curveAlpha: 1, over: bg)
            #expect(px.maxComponentDelta(expected) <= 2.0 / 255, """
                \(label)／.\(activity)：取樣 \(px) 與預期 \(expected) 差超過 2/255 —— palette 沒被真的畫出來。
                """)
        }
    }

    @Test("LED 是否真的畫出注入的 palette 顏色（對抗式）")
    func renderersHonorPalette() throws {
        let palette = Self.honorPalette
        let led = makeLED()
        try checkHonorsPalette(led, sample: led.ledRect(at: 3).center, palette: palette, label: "LED")

        // 子斷言：idle a=0.5 → 取樣 ≈ 0.5 × idle 色 + 0.5 × **LED 實際的襯底**（證 view 真的乘了 color.a）。
        // A2 的 LED 疊在不透明底板上，不是疊在背景上——所以襯底是 spec §4.1 的底板色 #141416（字面值 pin，
        // 刻意不從 view 讀：從 view 讀會讓「底板色被改」與「預期值」一起變動）。T01 寫成純黑是無底板時的假設，
        // T05 底板落地後對齊（RendererPixelTests 這條在 T05 報告裡被實測證明對任何實作都紅，不是實作錯）。
        let halfAlpha = IconPalette(idle: RGBA(r: palette.idle.r, g: palette.idle.g, b: palette.idle.b, a: 0.5),
                                    working: palette.working, done: palette.done,
                                    waiting: palette.waiting, error: palette.error)
        let appearance = AppearancePolicy.appearance(for: icon(.idle), palette: halfAlpha, reduceMotion: true)
        led.update(appearance, phase: 0)
        let bmp = try OffscreenRender.render(led, over: .black)
        let px = try bmp.pixel(at: led.ledRect(at: 3).center)
        let plate = RGBA(r: 20.0 / 255, g: 20.0 / 255, b: 22.0 / 255, a: 1)   // spec §4.1 底板色，字面值 pin
        let expected = OffscreenRender.expected(halfAlpha.idle, curveAlpha: 1, over: plate)
        #expect(px.maxComponentDelta(expected) <= 2.0 / 255, """
            idle a=0.5 子斷言：取樣 \(px) 與預期 \(expected)（0.5×idle 疊底板 #141416）差超過 2/255 —— view 是否真的乘了 color.a？
            """)
    }

    @Test("A2 底板背景無關；四色靜態與動畫峰值對比達標（對抗式）")
    func plateGuaranteesContrast() throws {
        let led = makeLED()

        led.update(AppearancePolicy.appearance(for: icon(.idle), reduceMotion: true), phase: 0)
        let plateOnWhite = try (try OffscreenRender.render(led, over: .white)).pixel(at: Self.plateSample)
        let plateOnBlack = try (try OffscreenRender.render(led, over: .black)).pixel(at: Self.plateSample)
        #expect(plateOnWhite.maxComponentDelta(plateOnBlack) <= 1.0 / 255, """
            (a) 底板取樣在白／黑背景下差 \(plateOnWhite.maxComponentDelta(plateOnBlack)) > 1/255 —— 底板還不是背景無關的不透明層。
            """)

        for activity: Activity in [.working, .done, .waiting, .error] {
            let staticAppearance = AppearancePolicy.appearance(for: icon(activity), reduceMotion: true)
            led.update(staticAppearance, phase: 0)
            let staticBmp = try OffscreenRender.render(led, over: .black)
            let staticLED = try staticBmp.pixel(at: led.ledRect(at: 3).center)
            let staticContrast = OffscreenRender.contrast(staticLED, try staticBmp.pixel(at: Self.plateSample))
            #expect(staticContrast >= 3.0, "(b) .\(activity) 靜態對比 \(staticContrast) < 3:1")
            // review I3 / review-t04-06 I-B：(a) 只證底板那一個像素背景無關；對比數字的來源像素（LED）也要證——
            // 否則一塊沒鋪到 LED 底下的「底板」能讓 (a) 過關，而 LED 其實疊在背景上（round-1 的根因）。
            // 靜態分支的 LED 全不透明（四色 a=1、curve 1.0）→ 白黑必然相同、恆真；證人必須是**半透明**的格：
            // 谷值（working 0.35、waiting 0.20、error 0.08）與 (c′) 的 working 峰值 0.60。
            if activity != .done {
                let troughApp = AppearancePolicy.appearance(for: icon(activity), reduceMotion: false)
                led.update(troughApp, phase: OffscreenRender.troughPhase(of: troughApp.animation))
                let troughOnBlack = try (try OffscreenRender.render(led, over: .black)).pixel(at: led.ledRect(at: 3).center)
                let troughOnWhite = try (try OffscreenRender.render(led, over: .white)).pixel(at: led.ledRect(at: 3).center)
                #expect(troughOnWhite.maxComponentDelta(troughOnBlack) <= 1.0 / 255,
                        "(b′) .\(activity) 谷值（半透明 LED）在白／黑背景下不同 —— LED 底下不是不透明底板")
            }

            let dynamicAppearance = AppearancePolicy.appearance(for: icon(activity), reduceMotion: false)
            let peak = OffscreenRender.peakPhase(of: dynamicAppearance.animation)
            led.update(dynamicAppearance, phase: peak)
            let peakBmp = try OffscreenRender.render(led, over: .black)
            let peakLED = try peakBmp.pixel(at: led.ledRect(at: 3).center)
            let peakContrast = OffscreenRender.contrast(peakLED, try peakBmp.pixel(at: Self.plateSample))
            let peakLEDOnWhite = try (try OffscreenRender.render(led, over: .white)).pixel(at: led.ledRect(at: 3).center)
            #expect(peakLEDOnWhite.maxComponentDelta(peakLED) <= 1.0 / 255,
                    "(c′) .\(activity) 峰值 LED 取樣在白／黑背景下不同 —— 半透明 LED 底下不是底板")
            if activity == .working {
                // T19：working 從 systemBlue 改成白色（`IconPalette.default` 的 doc comment）——
                // 白色對底板的峰值對比從 2.54 變成 7.13（新常數，不是抄團隊那張表，是這個
                // harness 自己量出來的，見同檔 `workingIsQuietestByMotionNotColor` 的完整說明）。
                #expect(abs(peakContrast - 7.13) <= 0.10, "(c) working 峰值對比 \(peakContrast) 不在 7.13±0.10 內")
            } else {
                #expect(peakContrast >= 3.0, "(c) .\(activity) 峰值對比 \(peakContrast) < 3:1")
            }

            // (d) 谷值只印出，不設門檻。
            let trough = OffscreenRender.troughPhase(of: dynamicAppearance.animation)
            led.update(dynamicAppearance, phase: trough)
            let troughBmp = try OffscreenRender.render(led, over: .black)
            let troughContrast = OffscreenRender.contrast(
                try troughBmp.pixel(at: led.ledRect(at: 3).center), try troughBmp.pixel(at: Self.plateSample))
            print("(d) .\(activity) 谷值對比 = \(troughContrast)（僅記錄，不設門檻）")
        }
    }

    private func contrastAgainstPlate(_ led: LEDStripView, _ activity: Activity, static isStatic: Bool) throws -> Double {
        let appearance: IconAppearance
        let phase: Double
        if isStatic {
            appearance = AppearancePolicy.appearance(for: icon(activity), reduceMotion: true)
            phase = 0
        } else {
            appearance = AppearancePolicy.appearance(for: icon(activity), reduceMotion: false)
            phase = OffscreenRender.peakPhase(of: appearance.animation)
        }
        led.update(appearance, phase: phase)
        let bmp = try OffscreenRender.render(led, over: .black)
        return OffscreenRender.contrast(try bmp.pixel(at: led.ledRect(at: 3).center), try bmp.pixel(at: Self.plateSample))
    }

    /// T19（team-lead 裁決，2026-09-11）：working 從 systemBlue 改成白色之後，原本這條的
    /// 舊斷言（`workingStatic < errorStatic`，亮度對比）數學上不可能再成立（白色對任何深色
    /// 底板必然是最大亮度、必然是最大對比——實測 working 靜態 18.40:1、peak 7.13，皆高於
    /// error 的 5.40:1）。**這不是把 R4「working 不搶眼」的承諾放棄，是原本那條 gate 的
    /// 量法本身就錯了**：R4 要守的是「搶不搶眼」，`亮度對比` 衡量的是「看不看得清」——
    /// 兩件事不是同一件事。在一個用顏色當警示的系統裡，搶眼來自**色度**（飽和度／色相），
    /// 不是亮度：紅／橘會跳出來是因為它們是**有色**的警示，白是**無彩**的。使用者自己的
    /// 說法正好對上這個模型——「不搶眼，但是我特意去看它的話，其實看得出來」＝
    /// **高亮度對比（好認）＋ 零色度（不警示）**——白色不是違反 R4，是把 R4 的兩個半邊
    /// （「看得清」與「不搶眼」）第一次分乾淨：以前用同一支 systemBlue 兩者混著量，
    /// 恰好兩個方向都低，掩蓋了「亮度對比」從來就不是「搶不搶眼」的正確代理指標。
    /// 量錯的東西守了很久（M4 起）也還是量錯，2026-09-11 被這次實機推翻。
    ///
    /// 這條因此改守兩個半邊，各用各自正確的量：
    /// (1) **動態半邊**（未變）：working 的 alpha 振幅／重繪幀率在非 idle 狀態中最低——
    ///     完全不受顏色選擇影響，白色前後量出來都一樣。
    /// (2) **顏色半邊（色度，不是亮度對比）**：`.default` palette 下，working 的色度必須是
    ///     四個可改色狀態中最低——色度算法用 `max(r,g,b) − min(r,g,b)`（HSV 的 chroma，
    ///     不算亮度，只算「離灰階多遠」）。四色實測：working（白）0.0000（理論最小值，
    ///     S=0）、done 0.6314、error 0.7725、waiting 0.9608——白色恰好是 0，這條不但現在
    ///     會過，且語意正確：以後誰把 working 設成飽和色，這裡就會紅。只針對 `.default`
    ///     ——使用者自訂色不受限，那是他的自由（同 `OptionsMenuModelTests` 的 safePalette
    ///     不強制四色都過關同一個道理）。
    @Test("R4 動態＋色度半邊：working 的 alpha 振幅／重繪幀率最低（動態）、色度在 .default 四色中最低（顏色，T19 改用色度取代亮度對比）")
    func workingIsQuietestByMotionAndChroma() throws {
        let led = makeLED()
        let workingStatic = try contrastAgainstPlate(led, .working, static: true)
        let errorStatic = try contrastAgainstPlate(led, .error, static: true)
        print("""
            (參考，不設門檻) T19 後 working 靜態亮度對比 \(workingStatic) 高於 error \(errorStatic)——\
            亮度對比不是本測試守的量，見上面 doc comment：搶不搶眼要看色度，不是亮度
            """)

        // (1) 動態半邊。
        let workingAppearance = AppearancePolicy.appearance(for: icon(.working), reduceMotion: false)
        let waitingAppearance = AppearancePolicy.appearance(for: icon(.waiting), reduceMotion: false)
        let errorAppearance = AppearancePolicy.appearance(for: icon(.error), reduceMotion: false)

        func swing(_ animation: IconAnimation) -> Double {
            let peak = OffscreenRender.peakPhase(of: animation)
            let trough = OffscreenRender.troughPhase(of: animation)
            return AnimationCurve.alpha(for: animation, phase: peak) - AnimationCurve.alpha(for: animation, phase: trough)
        }

        let workingSwing = swing(workingAppearance.animation)
        let waitingSwing = swing(waitingAppearance.animation)
        let errorSwing = swing(errorAppearance.animation)
        #expect(workingSwing < waitingSwing, "working 的 alpha 振幅 \(workingSwing) 應 < waiting \(waitingSwing)")
        #expect(workingSwing < errorSwing, "working 的 alpha 振幅 \(workingSwing) 應 < error \(errorSwing)")

        #expect(workingAppearance.targetFPS < waitingAppearance.targetFPS, """
            working 的重繪幀率 \(workingAppearance.targetFPS) 應 < waiting \(waitingAppearance.targetFPS)
            """)
        #expect(workingAppearance.targetFPS < errorAppearance.targetFPS, """
            working 的重繪幀率 \(workingAppearance.targetFPS) 應 < error \(errorAppearance.targetFPS)
            """)

        // (2) 顏色半邊（色度，不是亮度對比）。
        func chroma(_ c: RGBA) -> Double {
            max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
        }
        let palette = IconPalette.default
        let workingChroma = chroma(palette.working)
        for (label, other) in [("done", palette.done), ("waiting", palette.waiting), ("error", palette.error)] {
            let otherChroma = chroma(other)
            #expect(workingChroma < otherChroma, """
                working 色度 \(workingChroma) 應 < \(label) 色度 \(otherChroma) —— \
                working 應是 .default 四色中色度最低（最不搶眼）的那個
                """)
        }
    }

    /// review-t04-06 I-A：`update` 裡的 `needsDisplay = true` 零 gate——刪掉它全套件仍綠，而 `AnimationDriver`
    /// 每格 `apply → update` 之後沒有人要求重繪，icon 會停在上一格。離屏 harness 走 `displayIgnoringOpacity`
    /// **不看** `needsDisplay`，所以像素 gate 抓不到。reviewer 實測：只有掛在**普通 NSWindow** 底下 `needsDisplay`
    /// 才可觀測（裸 view 與 status-item-hosted view 都恆 false），所以這條自己造一個 window。
    @Test("update 必須要求重繪（needsDisplay）")
    func updateRequestsRedraw() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let v: NSView & IconDrawing = LEDStripView()
        v.frame = NSRect(x: 0, y: 0, width: v.preferredWidth, height: Self.barHeight)
        window.contentView?.addSubview(v)
        v.displayIfNeeded()
        v.needsDisplay = false
        v.update(AppearancePolicy.appearance(for: icon(.waiting), reduceMotion: true), phase: 0)
        #expect(v.needsDisplay, "\(type(of: v)).update 沒有要求重繪 —— driver 推 phase 之後畫面會停在上一格")
    }
}
