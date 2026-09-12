/// C1（team-lead 收尾）：分隔線只准畫在群組交界，不是每一列都畫（九列變成一面「列牆」）。
/// 五個群組對應 Amphetamine 式的視覺分段；**`.help` 與 `.about` 都是「資訊」性質但刻意
/// 分成兩個 case**——它們在列表裡不相鄰（中間隔著 `.settings`／`.mount`），若共用同一個
/// group 值，`rowsAreContiguousByGroup` 這條 gate（見 `OptionsMenuModelTests`）必須紅
/// （同一個 group 被拆散在兩處）。`CaseIterable` 供 gate 推導、不必手寫「5 個」。
public enum OptionsRowGroup: Sendable, Equatable, CaseIterable {
    case help, settings, mount, about, quit
}

/// spec §4.3／§6.3（r7）：Options 展開列表的資料化——view 只從 `rows(...)` 取列
/// （S1-Q6：這是 gate 的推導來源），不得自己組裝標題／action。
public struct OptionsRow: Equatable, Sendable, Identifiable {
    public var id: PanelActionKind { action.kind }
    public let title: String
    /// B5：狀態說明（目前只有「減少動態」在用）。兩種情況都非空：系統已強制時說明為什麼
    /// 開關按不動（否則顯示為開但 disabled，卻沒有任何文字解釋，又是一次「畫面沒說清楚」）；
    /// T13（S1-4'）：使用者**自己**打開時，改說明開了之後會失去什麼（見 `rows(...)` 的
    /// `reduceMotionSubtitle` 推導）——spec §R4 承諾 error／waiting「不必辨色也能區分」，
    /// 這個開關恰好會拿掉那個保證，這裡必須讓打開它的人知道。
    public let subtitle: String?
    public let action: PanelAction
    public let isDisabled: Bool
    /// 開關列（`setLaunchAtLogin`／`setReduceMotion`）目前值；其餘列固定 `nil`。
    public let toggleValue: Bool?
    /// C1：view 只在**群組交界**畫 `Divider`，不得自己重算分組（同 `action`／`title` 的理由）。
    public let group: OptionsRowGroup

    public init(title: String, subtitle: String? = nil, action: PanelAction, isDisabled: Bool,
               toggleValue: Bool?, group: OptionsRowGroup) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.isDisabled = isDisabled
        self.toggleValue = toggleValue
        self.group = group
    }
}

/// r7 的裁決（派 T06 前自查發現 r5 的 `nonMenuKinds` 與 §4.3 Options 列表互相矛盾）：
/// `PanelActionKind` = 4 個非選單（`nonMenuKinds`，字面集合恰為這四個）＋其餘皆選單列
/// （`rows(...)` 的聯集，由 `optionsRowsCoverEveryAction` 型別推導，不寫數字）。
/// T12（B2／B5）：新增 `reportIssue`／`setReduceMotion` 都是選單列，不進 `nonMenuKinds`——
/// 兩者都刻意需要在 Options 區被看見，不像 `replaceExternalMount` 需要 CTA 的脈絡。
public enum OptionsMenuModel {
    /// **字面集合，恰為這四個**（G10(a)：往裡面加東西就是紅）。這四個動作各自的觸發處在
    /// 圖例色點／footer 的「Options ⌄」／banner 的關閉／CTA 副標，不住在 Options 選單列表裡——
    /// `replaceExternalMount` 尤其刻意：要顯示「現有掛載指向 X」的脈絡，不適合當一列裸選單項。
    public static let nonMenuKinds: Set<PanelActionKind> = [
        .pickColor, .toggleOptions, .dismissBanner, .replaceExternalMount,
    ]

    /// 依序、分五群（C1）：`.help`（說明）／`.settings`（開機自動啟動／減少動態／重設顏色）／
    /// `.mount`（重新接上／再檢查一次／移除掛載）／`.about`（關於／回報問題）／`.quit`。
    /// 兩列狀態相依：`setLaunchAtLogin` 在 `launchAtLogin == nil`（這個環境不支援）時整列
    /// 隱藏；`recheckHook` 只在 `install` 是 `connected(_, verified: .unknown)` 時出現
    /// （R2 的退化出口，不讓畫面停在未驗證）。`resetColors` 在 `isDefaultPalette` 時整列
    /// 仍在，只是 disabled（不是隱藏）。
    ///
    /// A4（T11 commit3）：「說明與快速上手…」**恆為第一列**（`setLaunchAtLogin` 這顆開關
    /// 排第二，不是第一）——persona 實測 popover 從頂邊固定往下長，展開 accordion 會把
    /// 第一列推到使用者剛剛點下「Options ⌄」的那個螢幕座標，第二下誤點會落在第一列上。
    /// 開關類控制項排第一就等於「第二下點擊＝靜默切換一個持久系統設定」；非開關列排第一，
    /// 誤點的後果最多是多開一次說明頁，不會動到任何狀態（`optionsRowsFirstIsNeverToggle`）。
    /// T12（B5）：`systemReduceMotion`／`userReduceMotion` 各自是系統值與使用者偏好——
    /// 「減少動態」列的 disabled／subtitle 只看系統值，toggleValue 看兩者的 OR（與
    /// `AnimationDriver.setUserReduceMotion` 同一個 oracle，不在這裡重算一份平行邏輯）。
    public static func rows(install: InstallState, launchAtLogin: Bool?, isDefaultPalette: Bool,
                            systemReduceMotion: Bool, userReduceMotion: Bool, iconPlate: Bool,
                            palette: IconPalette) -> [OptionsRow] {
        var rows: [OptionsRow] = []

        rows.append(OptionsRow(title: "說明與快速上手…", action: .openHelp, isDisabled: false,
                               toggleValue: nil, group: .help))
        if let launchAtLogin {
            // 觸發時把值反過來（按下＝切換），toggleValue 帶目前值供 view 畫開關位置。
            rows.append(OptionsRow(title: "開機自動啟動", action: .setLaunchAtLogin(!launchAtLogin),
                                   isDisabled: false, toggleValue: launchAtLogin, group: .settings))
        }
        // B5：系統已強制時開關顯示為開且 disabled（按了也沒用——系統值贏），
        // 旁邊灰字說明為什麼；系統沒開時可自由切換，開＝使用者要求減少動態。
        // T13（S1-3）：「系統設定已開啟」中文語序會被讀成「系統設定（那個 App）已經被打開」，
        // 改成「已在系統設定開啟」。
        // T13（S1-4'）：使用者自己打開（系統沒強制）時不再是 nil——persona 實測這個開關會讓
        // waiting／error 只剩色相差別（亮度差 1.66:1），且這件事在這一列完全沒有任何提示；
        // `subtitle` 這個欄位已經存在（B5 自己在用），只是換一句話，不是新機制。
        let reduceMotionOn = systemReduceMotion || userReduceMotion
        let reduceMotionSubtitle: String?
        if systemReduceMotion {
            reduceMotionSubtitle = "已在系統設定開啟"
        } else if userReduceMotion {
            reduceMotionSubtitle = "動畫關閉後，「等你」與「錯誤」只靠顏色區分"
        } else {
            reduceMotionSubtitle = nil
        }
        rows.append(OptionsRow(title: "減少動態", subtitle: reduceMotionSubtitle,
                               action: .setReduceMotion(!reduceMotionOn),
                               isDisabled: systemReduceMotion, toggleValue: reduceMotionOn, group: .settings))
        // T16：底板讓 LED 對比在深淺模式／任何桌布下恆定（M4 選 A2 的理由）；關掉後
        // 燈直接疊在選單列上，一般取捨說明放在 help.html（`HelpDocOptionsRowCoverageTests` 強制）。
        // T19：但「一般取捨」與「目前這個 palette 底板關了會不會真的看不見」是兩回事——
        // 使用者把 working 改成白色之後，底板關掉會讓它在淺色選單列上幾乎消失（1.12:1），
        // 這件事跟「使用者現在正在看的這個開關」直接相關，help.html 的靜態文字不會主動跳出來，
        // 所以借用既有的 `subtitle` 欄位（跟「減少動態」那條可及性提醒同一套機制，B5）。
        rows.append(OptionsRow(title: "燈條底板", subtitle: lightBarWarning(iconPlate: iconPlate, palette: palette),
                               action: .setIconPlate(!iconPlate), isDisabled: false,
                               toggleValue: iconPlate, group: .settings))
        rows.append(OptionsRow(title: "重設顏色", action: .resetColors, isDisabled: isDefaultPalette,
                               toggleValue: nil, group: .settings))
        rows.append(OptionsRow(title: "重新接上 Claude Code", action: .connect, isDisabled: false,
                               toggleValue: nil, group: .mount))
        if case .connected(_, .unknown) = install {
            rows.append(OptionsRow(title: "再檢查一次", action: .recheckHook, isDisabled: false,
                                   toggleValue: nil, group: .mount))
        }
        rows.append(OptionsRow(title: "移除掛載…", action: .disconnect, isDisabled: false,
                               toggleValue: nil, group: .mount))
        rows.append(OptionsRow(title: "關於 AgentAura", action: .about, isDisabled: false,
                               toggleValue: nil, group: .about))
        // B2：Amphetamine 的 Feedback & Support 對應——開 GitHub issues（見 `ProjectLinks.newIssue`）。
        rows.append(OptionsRow(title: "回報問題…", action: .reportIssue, isDisabled: false,
                               toggleValue: nil, group: .about))
        rows.append(OptionsRow(title: "離開 AgentAura ⌘Q", action: .quit, isDisabled: false,
                               toggleValue: nil, group: .quit))

        return rows
    }

    /// T19：底板關＋目前 palette 有任一可改色狀態在淺色選單列上「幾乎看不見」
    /// （`ContrastCheck.lowOnLightBar`）時給提醒；底板開時恆 nil（有底板就沒有這個問題，
    /// 白色 18.40:1）。命名具體出問題的狀態（而不是籠統講「顏色」或猜色名）——
    /// 使用者可能改的不是 working，點出「哪一個」比講「白色」更準也更泛用。
    private static func lightBarWarning(iconPlate: Bool, palette: IconPalette) -> String? {
        guard !iconPlate else { return nil }
        let dim = Activity.customizable.filter { ContrastCheck.lowOnLightBar(palette[$0]) }
        guard !dim.isEmpty else { return nil }
        let names = dim.map { "「\(LegendModel.label($0))」" }.joined(separator: "、")
        return "底板關閉時，\(names)的顏色在淺色選單列上幾乎看不見"
    }
}
