import Testing
import AuraCore

/// spec `2026-09-09-m4-icon-form-design.md` §6：`paletteSubscriptIsTotal`、
/// `appearanceCarriesPaletteColor`。
@Suite("IconPalette")
struct IconPaletteTests {

    /// 五色彼此差異極大——不能用 `.default`：全零時任何欄位互換都恆等，
    /// 「接錯欄位」的 mutation 會被吃掉，等於 gate 沒有牙齒。
    static let distinctPalette = IconPalette(
        idle:    RGBA(r: 0.10, g: 0.20, b: 0.30, a: 0.40),
        working: RGBA(r: 0.90, g: 0.10, b: 0.10, a: 1.00),
        done:    RGBA(r: 0.10, g: 0.90, b: 0.10, a: 1.00),
        waiting: RGBA(r: 0.90, g: 0.60, b: 0.10, a: 1.00),
        error:   RGBA(r: 0.10, g: 0.10, b: 0.90, a: 1.00))

    @Test("subscript 對每個 activity 都轉發到對應欄位（主斷言）；欄位名與 Activity.allCases 一致（次要）")
    func paletteSubscriptIsTotal() throws {
        let p = Self.distinctPalette
        let byField: [Activity: RGBA] = [
            .idle: p.idle, .working: p.working, .done: p.done,
            .waiting: p.waiting, .error: p.error,
        ]
        for a in Activity.allCases {
            #expect(p[a] == byField[a], "palette[.\(a)] 沒有轉發到 \(a) 欄位，實際 \(p[a])")
        }

        // 次要斷言：型別已保證完整（5 個非 optional 欄位），這條只守欄位名。
        let names = Set(Mirror(reflecting: p).children.compactMap(\.label))
        #expect(names == Set(Activity.allCases.map(\.rawValue)), """
            IconPalette 的 stored property 名與 Activity.allCases 對不上：\(names)
            """)
    }

    @Test("AppearancePolicy 把 palette 的色解析進 IconAppearance.color")
    func appearanceCarriesPaletteColor() throws {
        let palette = Self.distinctPalette
        for a in Activity.allCases {
            let icon = IconState(activity: a, counts: [a: 1], liveCount: 1)
            let appearance = AppearancePolicy.appearance(for: icon, palette: palette)
            #expect(appearance.color == palette[a], """
                .\(a) 的 appearance.color 應為 palette[.\(a)]（\(palette[a])），實際 \(appearance.color)
                """)
        }
    }
}
