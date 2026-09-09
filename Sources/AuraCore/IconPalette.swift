/// 五個 activity 各自的顏色 + 基礎 alpha。純資料，不含任何繪製。
/// spec `2026-09-09-m4-icon-form-design.md` §3、§6 `paletteSubscriptIsTotal`。

/// sRGB 0…1 色彩分量 + 基礎 alpha。`a` 是該狀態的**基礎 alpha**，繪製時再乘上
/// `AnimationCurve.alpha`——idle 之外的四色 `a` 恆為 1。Codable 為 Change 2
/// 持久化預留，本 change 無消費者、不測 Codable 行為。
public struct RGBA: Equatable, Sendable, Codable {
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
    public static let `default` = IconPalette(
        idle:    RGBA(r:  72/255, g:  72/255, b:  74/255, a: 0.35), // #48484a 極暗灰 × 0.35
        working: RGBA(r:  10/255, g: 132/255, b: 255/255, a: 1),    // #0a84ff systemBlue(dark)
        done:    RGBA(r:  48/255, g: 209/255, b:  88/255, a: 1),    // #30d158 systemGreen(dark)
        waiting: RGBA(r: 255/255, g: 159/255, b:  10/255, a: 1),    // #ff9f0a systemOrange(dark)
        error:   RGBA(r: 255/255, g:  69/255, b:  58/255, a: 1))    // #ff453a systemRed(dark)
}
