import Testing
import AuraCore

/// T07 第一步（純搬移，零行為變更）：`OptionsMenuModelTests.swift` 撞到 `Tests/` 300 行上限
/// （spec plan §T07），把 T16／T19／T32 這三批既有測試搬過來騰空間——被搬動的測試函式名
/// 一字不改、斷言總數不變，只是換了一個承接的 `struct`。
///
/// T07 第二步之後，這個檔案會**追加**（不是取代）CX20 `codexRowsAppearOnlyWhenAvailable` 的
/// 斷言：`OptionsMenuModel.rows(...)` 多吃的 `codex: CodexState` 參數如何影響 `.mount` 群組的
/// 列數與 action——名字「CodexOptionsRowTests」對得上檔案最終的主要用途。
@Suite("OptionsMenuModel.rows：燈條底板／造型列（T16／T19／T32，自 OptionsMenuModelTests 搬遷）")
struct CodexOptionsRowTests {

    // MARK: - T16：燈條底板列

    private static func iconPlateRow(_ iconPlate: Bool, palette: IconPalette = .default) -> OptionsRow {
        let rows = OptionsMenuModel.rows(install: .notConnected, launchAtLogin: true, isDefaultPalette: palette.isDefault,
                                         systemReduceMotion: false, userReduceMotion: false,
                                         iconPlate: iconPlate, iconShape: .ledStrip, palette: palette, language: .traditionalChinese)
        return rows.first { $0.action.kind == .setIconPlate }!
    }

    @Test("(T16-a) 燈條底板列一律存在、屬 .settings 群、永不 disabled")
    func iconPlateRowAlwaysPresentInSettingsGroup() {
        for iconPlate in [true, false] {
            let row = Self.iconPlateRow(iconPlate)
            #expect(row.group == .settings, "燈條底板列應屬 .settings 群，實際 \(row.group)")
            #expect(row.isDisabled == false, "燈條底板沒有系統強制值這種前提，不該 disabled")
        }
    }

    @Test("(T16-b) toggleValue 反映目前值，action 送出相反值")
    func iconPlateRowReflectsCurrentValueAndTogglesAction() {
        let on = Self.iconPlateRow(true)
        #expect(on.toggleValue == true)
        #expect(on.action == .setIconPlate(false), "目前是開，觸發應該送出關閉")

        let off = Self.iconPlateRow(false)
        #expect(off.toggleValue == false)
        #expect(off.action == .setIconPlate(true), "目前是關，觸發應該送出開啟")
    }

    // MARK: - T19：燈條底板列的淺色選單列低對比提醒

    /// working 換回舊的 systemBlue，其餘沿用 `.default`——`ContrastCheck.lowOnLightBar` 對
    /// 四色都應該是 false（見該檔 doc comment 的驗證），拿來當「不該有提醒」的對照組。
    private static let safePalette = IconPalette(
        idle: IconPalette.default.idle,
        working: RGBA(r: 10.0 / 255, g: 132.0 / 255, b: 255.0 / 255, a: 1),
        done: IconPalette.default.done, waiting: IconPalette.default.waiting, error: IconPalette.default.error)

    @Test("(T19-a) 底板關＋.default palette（白色 working）：燈條底板列 subtitle 非空、提到「執行中」")
    func iconPlateRowWarnsWhenOffAndDefaultPaletteLowContrast() {
        let row = Self.iconPlateRow(false, palette: .default)
        #expect(row.subtitle?.contains("執行中") == true, """
            .default 的 working 現在是白色（T19），底板關閉時應該提醒淺色選單列幾乎看不見，
            實際 subtitle=\(String(describing: row.subtitle))
            """)
    }

    @Test("(T19-b) 底板開：即使 palette 對比過低，subtitle 仍為 nil（有底板就沒有這個問題）")
    func iconPlateRowSilentWhenPlateOnRegardlessOfPalette() {
        let row = Self.iconPlateRow(true, palette: .default)
        #expect(row.subtitle == nil, "底板開啟時不該有淺色選單列提醒，實際 \(String(describing: row.subtitle))")
    }

    @Test("(T19-c) 底板關＋四色都過關的 palette：subtitle 仍為 nil（不是逢底板關必警告）")
    func iconPlateRowSilentWhenOffButPaletteIsFine() {
        let row = Self.iconPlateRow(false, palette: Self.safePalette)
        #expect(row.subtitle == nil, """
            safePalette 四色對淺色選單列都不該低於門檻，底板關也不該有提醒，
            實際 \(String(describing: row.subtitle))
            """)
    }

    @Test("(T19-d) 底板關＋只有 waiting 過低：subtitle 只提到「等你」，不誤指其他狀態")
    func iconPlateRowNamesOnlyTheOffendingState() {
        let waitingWhite = Self.safePalette.with(.waiting, color: RGBA(r: 1, g: 1, b: 1, a: 1))
        let row = Self.iconPlateRow(false, palette: waitingWhite)
        #expect(row.subtitle?.contains("等你") == true, "應該提到「等你」，實際 \(String(describing: row.subtitle))")
        #expect(row.subtitle?.contains("執行中") == false, "working 沒問題，不該被提到，實際 \(String(describing: row.subtitle))")
    }

    // MARK: - T32：icon 造型列

    private static func iconShapeRow(_ iconShape: IconShape) -> OptionsRow {
        OptionsMenuModel.rows(install: .notConnected, launchAtLogin: true, isDefaultPalette: true, systemReduceMotion: false,
                              userReduceMotion: false, iconPlate: true, iconShape: iconShape, palette: .default,
                              language: .traditionalChinese).first { $0.action.kind == .pickIconShape }!
    }

    /// 七個造型都要走一遍（N7 同款精神）：一律 `.settings` 群、不 disabled、非 toggle
    /// （七選一），subtitle 是目前造型雙語名稱，action 帶目前造型當開啟選單的脈絡。
    @Test("(T32) 造型列：屬 .settings 群、不 disabled、非 toggle、subtitle／action 反映目前造型")
    func iconShapeRowReflectsCurrentShape() {
        for shape in IconShape.allCases {
            let row = Self.iconShapeRow(shape)
            #expect(row.group == .settings && !row.isDisabled && row.toggleValue == nil,
                   "造型列應屬 .settings、不 disabled、非 toggle，實際 \(row)")
            #expect(row.subtitle == shape.displayName(.traditionalChinese), "subtitle 應是目前造型的雙語名稱")
            #expect(row.action == .pickIconShape(shape), "action 應該帶目前造型，實際 \(row.action)")
        }
    }
}
