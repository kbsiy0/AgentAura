/// 五個 activity 各自的顏色 + 基礎 alpha。純資料，不含任何繪製。
/// spec `2026-09-09-m4-icon-form-design.md` §3、§6 `paletteSubscriptIsTotal`。

/// sRGB 0…1 色彩分量 + 基礎 alpha。`a` 是該狀態的**基礎 alpha**，繪製時再乘上
/// `AnimationCurve.alpha`——idle 之外的四色 `a` 恆為 1。持久化不走 `Codable`——
/// `PaletteStore` 用 `PaletteCodec` 的 hex 字串（`"#rrggbb"`）寫 `UserDefaults`。
public struct RGBA: Equatable, Sendable {
    public let r, g, b, a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

/// 5 個**非 optional** 具名欄位——型別層保證「不可能缺值」，見 spec §2 選擇 3。
/// `subscript` 只是純轉發；`Mirror` gate 另外守欄位名與 `Activity.allCases` 一致。
public struct IconPalette: Equatable, Sendable {
    public let idle, working, done, waiting, error: RGBA

    public init(idle: RGBA, working: RGBA, done: RGBA, waiting: RGBA, error: RGBA) {
        self.idle = idle
        self.working = working
        self.done = done
        self.waiting = waiting
        self.error = error
    }

    public subscript(_ activity: Activity) -> RGBA {
        switch activity {
        case .idle:    return idle
        case .working: return working
        case .done:    return done
        case .waiting: return waiting
        case .error:   return error
        }
    }

    /// spec §3 釘死的數字（WCAG 對比、working 可用窗口見同節）。
    /// **不得為了讓對比 gate 轉綠而調這五組數字**——要調就回 spec §3 改並在
    /// commit message 記錄理由。
    ///
    /// T19：`working` 從 systemBlue 改成白 `#ffffff`——使用者自己把它改成白色後回報「這才是對的」：
    /// 「白色……它等於是正在工作、不搶眼，但是我特意去看它的話，其實看得出來它就是安靜的、沒有事」，
    /// 實測數字支持這個判斷（sRGB WCAG 對比，含底板時 LED vs 底板 `#141416`）：
    /// - 有底板 18.40:1（原藍 5.04:1）；深色選單列（底板關）17.01:1（原藍 4.66:1）——這兩格是本 app
    ///   有史以來最高，且白色不像四個狀態色那樣搶注意力（R4 注意力預算）。
    /// - 代價：淺色選單列（底板關）只剩 1.12:1、面板白卡片色點僅 1.00:1——兩格都「幾乎看不見」，
    ///   不能只改這一個常數了事，見下面兩件配套：`ContrastCheck.lowOnLightBar`（Options「燈條底板」
    ///   列在底板關＋對比過低時給 subtitle 提醒）與面板色點加邊線（`LegendRowView`／`PanelRowView`，
    ///   否則白點在白卡片上直接消失）。
    /// - 這取代了 M4 §3「保留 systemBlue」的決定——那次的前提是「只有底板、沒有可關底板選項、
    ///   面板也還沒有色點」，三個前提現在都不成立（T16 加了底板開關、Change 2 加了面板色點）。
    public static let `default` = IconPalette(
        idle:    RGBA(r:  72/255, g:  72/255, b:  74/255, a: 0.35), // #48484a 極暗灰 × 0.35
        working: RGBA(r:   1,     g:   1,     b:   1,     a: 1),    // #ffffff 白（T19，原 #0a84ff systemBlue）
        done:    RGBA(r:  48/255, g: 209/255, b:  88/255, a: 1),    // #30d158 systemGreen(dark)
        waiting: RGBA(r: 255/255, g: 159/255, b:  10/255, a: 1),    // #ff9f0a systemOrange(dark)
        error:   RGBA(r: 255/255, g:  69/255, b:  58/255, a: 1))    // #ff453a systemRed(dark)
}
