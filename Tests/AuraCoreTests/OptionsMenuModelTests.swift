import Testing
import AuraCore

/// `optionsRowsCoverEveryAction`（spec §6.3，r7，兩段）：
/// (a) `nonMenuKinds` 恰好等於 r7 表那四個；
/// (b) 代表狀態集合的 `rows` 聯集涵蓋全部選單 Kind（`PanelActionKind.allCases` 扣掉
///     `nonMenuKinds`，不寫數字），且任一單一狀態內同一 Kind 最多一次。
@Suite("OptionsMenuModel.rows 涵蓋每個選單 Kind（optionsRowsCoverEveryAction，G10）")
struct OptionsMenuModelTests {

    @Test("(a) nonMenuKinds 恰好等於 {pickColor, toggleOptions, dismissBanner, replaceExternalMount}")
    func nonMenuKindsIsExactlyThatLiteralSet() {
        #expect(OptionsMenuModel.nonMenuKinds == [.pickColor, .toggleOptions, .dismissBanner, .replaceExternalMount], """
            nonMenuKinds 目前是 \(OptionsMenuModel.nonMenuKinds)，
            必須恰好等於 r7 表那四個——多了／少了都代表某個動作的守衛被靜默換了頻道（R5）
            """)
    }

    /// 代表狀態集合，由型別推導（不寫數字）：`InstallState` 用與 G8a 相同的乘積（`InstallStateAllCases`）、
    /// `launchAtLogin` 覆蓋三值（含 nil，才踩得到 setLaunchAtLogin 的隱藏分支）、
    /// `isDefaultPalette` 覆蓋兩值。
    @Test("(b) 各狀態 rows 聯集涵蓋全部選單 Kind，且任一單一狀態內同一 Kind 最多一次")
    func rowsUnionCoversEveryMenuKindWithoutDuplicates() {
        var union: Set<PanelActionKind> = []
        for install in InstallStateAllCases.all() {
            for launchAtLogin: Bool? in [true, false, nil] {
                for isDefaultPalette in [true, false] {
                    let rows = OptionsMenuModel.rows(install: install, launchAtLogin: launchAtLogin,
                                                     isDefaultPalette: isDefaultPalette,
                                                     systemReduceMotion: false, userReduceMotion: false, iconPlate: true, palette: .default)
                    let kinds = rows.map(\.action.kind)
                    #expect(Set(kinds).count == kinds.count, """
                        install=\(install) launchAtLogin=\(String(describing: launchAtLogin)) \
                        isDefaultPalette=\(isDefaultPalette) 的 rows 同一 Kind 出現超過一次：\(kinds)
                        """)
                    union.formUnion(kinds)
                }
            }
        }
        let expectedMenuKinds = Set(PanelActionKind.allCases).subtracting(OptionsMenuModel.nonMenuKinds)
        #expect(union == expectedMenuKinds, """
            rows 聯集是 \(union.map(\.rawValue).sorted())，
            應恰好涵蓋 PanelActionKind.allCases 扣掉 nonMenuKinds 之後的 \(expectedMenuKinds.count) 個：\(expectedMenuKinds.map(\.rawValue).sorted())
            """)
    }

    @Test("setLaunchAtLogin 列在 launchAtLogin == nil 時整列隱藏")
    func launchAtLoginRowHiddenWhenUnsupported() {
        let rows = OptionsMenuModel.rows(install: .notConnected, launchAtLogin: nil, isDefaultPalette: true,
                                              systemReduceMotion: false, userReduceMotion: false, iconPlate: true, palette: .default)
        #expect(!rows.contains { $0.action.kind == .setLaunchAtLogin })
    }

    @Test("recheckHook 列只在 connected(_, verified: .unknown) 時出現")
    func recheckHookRowOnlyWhenVerificationUnknown() {
        let unknownRows = OptionsMenuModel.rows(install: .connected(owner: .thisApp, verified: .unknown),
                                                launchAtLogin: true, isDefaultPalette: true,
                                                systemReduceMotion: false, userReduceMotion: false, iconPlate: true, palette: .default)
        #expect(unknownRows.contains { $0.action.kind == .recheckHook })

        let verifiedRows = OptionsMenuModel.rows(install: .connected(owner: .thisApp, verified: .verified),
                                                 launchAtLogin: true, isDefaultPalette: true,
                                                 systemReduceMotion: false, userReduceMotion: false, iconPlate: true, palette: .default)
        #expect(!verifiedRows.contains { $0.action.kind == .recheckHook })

        let notConnectedRows = OptionsMenuModel.rows(install: .notConnected, launchAtLogin: true, isDefaultPalette: true,
                                                     systemReduceMotion: false, userReduceMotion: false, iconPlate: true, palette: .default)
        #expect(!notConnectedRows.contains { $0.action.kind == .recheckHook })
    }

    @Test("resetColors 列在 isDefaultPalette 時仍在，只是 disabled")
    func resetColorsRowDisabledNotHiddenWhenDefaultPalette() {
        let rows = OptionsMenuModel.rows(install: .notConnected, launchAtLogin: true, isDefaultPalette: true,
                                         systemReduceMotion: false, userReduceMotion: false, iconPlate: true, palette: .default)
        let resetRow = rows.first { $0.action.kind == .resetColors }
        #expect(resetRow != nil, "resetColors 列不該因為 isDefaultPalette 而消失——只准 disabled")
        #expect(resetRow?.isDisabled == true)

        let nonDefaultRows = OptionsMenuModel.rows(install: .notConnected, launchAtLogin: true, isDefaultPalette: false,
                                                   systemReduceMotion: false, userReduceMotion: false, iconPlate: true, palette: .default)
        #expect(nonDefaultRows.first { $0.action.kind == .resetColors }?.isDisabled == false)
    }

    /// A4（T11 commit3）：popover 從頂邊固定往下長，展開 accordion 會把第一列推到使用者
    /// 剛剛點下「Options ⌄」的螢幕座標——第一列若是開關，第二下誤點＝靜默切換系統設定。
    /// 型別層驗證（不必靠像素）：對代表狀態集合（含 `launchAtLogin` 非 nil，才踩得到
    /// 開關真的存在的分支），`rows.first` 恆不是 toggle 型（`toggleValue == nil`）。
    @Test("(A4) rows 第一列永遠不是 toggle 型，即使 setLaunchAtLogin 存在")
    func firstRowIsNeverToggle() {
        for install in InstallStateAllCases.all() {
            for launchAtLogin: Bool? in [true, false, nil] {
                for isDefaultPalette in [true, false] {
                    let rows = OptionsMenuModel.rows(install: install, launchAtLogin: launchAtLogin,
                                                     isDefaultPalette: isDefaultPalette,
                                                     systemReduceMotion: false, userReduceMotion: false, iconPlate: true, palette: .default)
                    guard let first = rows.first else { continue }
                    #expect(first.toggleValue == nil, """
                        install=\(install) launchAtLogin=\(String(describing: launchAtLogin)) 的第一列是
                        toggle 型（「\(first.title)」）—— 展開 accordion 的第二下誤點會靜默切換它
                        """)
                }
            }
        }
    }

    // MARK: - T12（B5）：減少動態列

    private static func reduceMotionRow(system: Bool, user: Bool) -> OptionsRow {
        let rows = OptionsMenuModel.rows(install: .notConnected, launchAtLogin: true, isDefaultPalette: true,
                                         systemReduceMotion: system, userReduceMotion: user, iconPlate: true, palette: .default)
        return rows.first { $0.action.kind == .setReduceMotion }!
    }

    @Test("(B5-a) 系統關、使用者開：toggleValue true、不 disabled、subtitle 是可及性提醒（T13 S1-4'）")
    func reduceMotionRowSystemOffUserOn() {
        let row = Self.reduceMotionRow(system: false, user: true)
        #expect(row.toggleValue == true)
        #expect(row.isDisabled == false, "系統沒強制時應該可以自由切換")
        #expect(row.subtitle == "動畫關閉後，「等你」與「錯誤」只靠顏色區分", """
            使用者自己打開時 subtitle 不該是 nil（T13 S1-4'）——這個開關會讓 waiting／error
            只剩色相差別，且系統沒有強制他開，他必須被主動告知，實際「\(String(describing: row.subtitle))」
            """)
        #expect(row.action == .setReduceMotion(false), "目前是開，觸發應該送出關閉（!reduceMotionOn）")
    }

    @Test("(B5-b) 系統開、使用者關：仍顯示 toggleValue true 且 disabled（系統值贏）")
    func reduceMotionRowSystemOnUserOff() {
        let row = Self.reduceMotionRow(system: true, user: false)
        #expect(row.toggleValue == true, "系統強制時開關應該顯示為開，即使使用者偏好是關")
        #expect(row.isDisabled == true, "系統強制時這一列必須 disabled——按了也沒用")
    }

    /// T13（S1-3／S1-4'）：三種非空 subtitle 各自對得上狀態——系統強制時固定講系統設定，
    /// 只有「完全沒開」才是唯一的 nil（gate 對應團隊指定的「該列開啟時 subtitle 非空」）。
    @Test("(B5-c) subtitle 與 isDisabled 對得上狀態：關掉時才是 nil，其餘三種組合都非空")
    func reduceMotionRowSubtitleMatchesDisabledState() {
        #expect(Self.reduceMotionRow(system: true, user: false).subtitle == "已在系統設定開啟")
        #expect(Self.reduceMotionRow(system: true, user: true).subtitle == "已在系統設定開啟")
        #expect(Self.reduceMotionRow(system: false, user: true).subtitle == "動畫關閉後，「等你」與「錯誤」只靠顏色區分")
        #expect(Self.reduceMotionRow(system: false, user: false).subtitle == nil, "完全沒開時沒什麼好提醒的，維持 nil")
    }

    /// T13：把「該列開啟時 subtitle 非空」寫成窮盡斷言，不只挑四個字面值對——
    /// `reduceMotionOn`（toggleValue）為 true 的每一種 system/user 組合都必須有 subtitle。
    @Test("(T13) reduceMotionOn 為 true 時 subtitle 必為非空")
    func reduceMotionSubtitleNonEmptyWheneverOn() {
        for system in [true, false] {
            for user in [true, false] {
                let row = Self.reduceMotionRow(system: system, user: user)
                if row.toggleValue == true {
                    #expect(row.subtitle?.isEmpty == false, """
                        system=\(system) user=\(user)：開關顯示為開時 subtitle 應非空，
                        實際「\(String(describing: row.subtitle))」
                        """)
                }
            }
        }
    }

    @Test("(B5-d) 系統關、使用者也關：toggleValue false、不 disabled")
    func reduceMotionRowBothOff() {
        let row = Self.reduceMotionRow(system: false, user: false)
        #expect(row.toggleValue == false)
        #expect(row.isDisabled == false)
        #expect(row.action == .setReduceMotion(true), "目前是關，觸發應該送出開啟")
    }

    // MARK: - T16：燈條底板列

    private static func iconPlateRow(_ iconPlate: Bool, palette: IconPalette = .default) -> OptionsRow {
        let rows = OptionsMenuModel.rows(install: .notConnected, launchAtLogin: true, isDefaultPalette: palette.isDefault,
                                         systemReduceMotion: false, userReduceMotion: false,
                                         iconPlate: iconPlate, palette: palette)
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

    // MARK: - C1（team-lead 收尾）：分隔線只在群組交界，rows 必須依 group 連續

    /// 代表狀態集合覆蓋 `launchAtLogin`／`recheckHook` 兩個隱藏分支 ＋ B5 的系統/使用者偏好，
    /// 逼出「群組成員數量最多／最少」兩端；不寫死哪個 group 出現幾次（型別推導）。
    @Test("rows 依 group 連續：同一個 group 不得被拆散在兩處（view 只在交界畫 Divider 的前提）")
    func rowsAreContiguousByGroup() {
        for install in InstallStateAllCases.all() {
            for launchAtLogin: Bool? in [true, false, nil] {
                for isDefaultPalette in [true, false] {
                    for systemReduceMotion in [true, false] {
                        let rows = OptionsMenuModel.rows(install: install, launchAtLogin: launchAtLogin,
                                                         isDefaultPalette: isDefaultPalette,
                                                         systemReduceMotion: systemReduceMotion, userReduceMotion: false, iconPlate: true, palette: .default)
                        var collapsed: [OptionsRowGroup] = []
                        for row in rows where collapsed.last != row.group { collapsed.append(row.group) }
                        #expect(Set(collapsed).count == collapsed.count, """
                            install=\(install) launchAtLogin=\(String(describing: launchAtLogin)) \
                            systemReduceMotion=\(systemReduceMotion) 的 group 序列 \(collapsed) 有重複——
                            同一個 group 被拆散在兩處，view 會在中間多畫一條不該有的分隔線
                            """)
                    }
                }
            }
        }
    }

    @Test("五個 group 都至少在某個代表狀態出現過（allCases 沒有用不到的 case）")
    func everyGroupIsReachable() {
        var seen: Set<OptionsRowGroup> = []
        for install in InstallStateAllCases.all() {
            for launchAtLogin: Bool? in [true, false, nil] {
                let rows = OptionsMenuModel.rows(install: install, launchAtLogin: launchAtLogin,
                                                 isDefaultPalette: true, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, palette: .default)
                seen.formUnion(rows.map(\.group))
            }
        }
        #expect(seen == Set(OptionsRowGroup.allCases), """
            代表狀態集合只踩到 \(seen)，缺 \(Set(OptionsRowGroup.allCases).subtracting(seen))——
            有 group 用不到，可能是 rows(...) 漏了某個 case
            """)
    }
}
