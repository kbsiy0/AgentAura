import Foundation

/// 接上成功／已接上／已移除掛載／錯誤的可關閉窄條（S1-P3/P4，spec §3.3）。
///
/// 只准經下列 public static 建構——與 `PanelModel.make` 同一個理由：任何呼叫端
/// 想顯示 banner 就只能挑這幾句，不能手搓文案（避免下一個人寫出「立即生效」那種謊，D-m）。
public struct PanelBanner: Equatable, Sendable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case connected, alreadyConnected, disconnected, error
        /// D-v（T13b，S0-1）：`.codexConnected(language:)` 的專屬 kind——`.connected` 的
        /// 退場條件（出現任何一列就退場）是為 Claude banner 推導的，出現一列 Claude 的
        /// session 對「Codex 會問你一次是否信任」這句話什麼都沒兌現。獨立 kind 讓
        /// `effectiveBanner`（`PanelModel+ConnectCTA.swift`）能依 kind 各自判斷退場條件，
        /// 不用共用 `.connected` 那組退場邏輯。
        case codexConnected
    }
    public let kind: Kind
    public let text: String

    /// D-m：接上成功的固定文案——**不得**寫成「立即生效」，那是 S0-A1 修掉的謊
    /// （新掛載要下一個 Claude Code session 起才載入）。
    ///
    /// `language` **沒有預設值**（T27 review 裁決）：漏傳就是編譯錯誤，由編譯器當 gate。
    /// 遷移期間一度給過預設值以免逼著下游同步跟進，但那讓「忘記傳」變成靜默吃到中文——
    /// `AppDelegate+Connect.swift` 就這樣漏接過，直到移除預設值才被編譯器抓出來。
    /// 見 `L10nProductionCallSitesPassLanguageTests`。
    public static func connected(language: Language) -> PanelBanner {
        PanelBanner(kind: .connected, text: L10nPanelBanner.connected.text(language))
    }

    /// §4.1：`connect()` 對有效掛載的冪等回應（S2-5）——不是錯誤，是「本來就好了」。
    public static func alreadyConnected(target: String?, language: Language) -> PanelBanner {
        PanelBanner(kind: .alreadyConnected, text: L10nPanelBanner.alreadyConnected(target: target, language: language))
    }

    /// S1-P4：措辭必須與「壞掉」明顯不同，否則使用者以為自己弄壞了。
    public static func disconnected(language: Language) -> PanelBanner {
        PanelBanner(kind: .disconnected, text: L10nPanelBanner.disconnected.text(language))
    }

    /// A5（T11 commit3）：`replaceExternalMount` 成功的專屬文案——與一般 `connected()`
    /// 不對稱的地方正是這裡：這顆按鈕做的事是「把開發者的掛載換成 App 內建的凍結版」，
    /// 不明說換了什麼，使用者只會覺得「畫面變了但不知道為什麼」。沿用 `.connected` kind
    /// （視覺樣式相同，仍是成功色），只有文案不同。
    public static func mountReplaced(from target: String?, language: Language) -> PanelBanner {
        PanelBanner(kind: .connected, text: L10nPanelBanner.mountReplaced(from: target, language: language))
    }

    public static func error(_ message: String) -> PanelBanner {
        PanelBanner(kind: .error, text: message)
    }

    /// T09（D-m）：Codex 接上成功的固定文案——同 `.connected(language:)` 對 Claude 側的既有
    /// 理由（忘了傳 `language` 要是編譯錯，不是靜默吃到中文），但兩者**不是同一句**：
    /// Codex 額外要求「Codex 會問你一次是否信任」（F5，P4 硬下限），Claude 側沒有這件事。
    /// `AppDelegate+Codex.swift`（T10）是唯一預期呼叫點。
    public static func codexConnected(language: Language) -> PanelBanner {
        PanelBanner(kind: .codexConnected, text: L10nCodex.connectedBanner.text(language))
    }

    /// T10：`performDisconnectCodex()` 成功時的固定文案——同 `.codexConnected(language:)`
    /// 的既有理由，`.disconnected` kind（視覺上是「已移除」樣式，同 Claude 側 `.disconnect`）。
    public static func codexDisconnected(language: Language) -> PanelBanner {
        PanelBanner(kind: .disconnected, text: L10nCodex.disconnectedBanner.text(language))
    }

    private init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// §3.3／N10：CTA 的呈現形狀。`.fullPanel` = 沒有活著的列時整版顯示；
/// `.banner` = 有列時縮成上方一條窄條；`.none` = 不顯示（已接上，或被 banner 蓋過）。
public enum CTAStyle: Equatable, Sendable { case fullPanel, banner, none }

/// 傳給 `PanelView` 的值——`PanelViewModel` 純函式集合的產出打包（spec §2），
/// app-shell（T06）擴充帶上安裝狀態、版本、Options 展開狀態與 banner（spec §3.3）。
///
/// 跟 `PanelRow` 一樣**不加 public init**：合成的 memberwise init 只到 internal，
/// 跨模組只能經 `make(...)` 建構，測試 fixture 因此一律走真的資料流，不會有跟生產路徑
/// 對不上的手搓值。
public struct PanelModel: Equatable, Sendable {
    public let title: String
    public let rows: [PanelRow]
    public let palette: IconPalette
    public let legend: [LegendItem]
    public let isDefaultPalette: Bool
    public let install: InstallState
    /// `CFBundleShortVersionString`，app 層讀好傳進來（不在這裡碰 `Bundle`——AuraCore 零 AppKit
    /// 依賴以外，`Bundle.main` 在 `swift test` 環境裡也讀不到 app bundle 的版本）。
    public let version: String
    /// Options 區展開狀態，家在 `AppDelegate`（§4.3：`setPanel` 每次 FSEvents 都換 `rootView`，
    /// SwiftUI `@State` 會與 model 失步）。
    public let optionsExpanded: Bool
    /// nil = 這個環境不支援開機自動啟動（`LoginItem.isSupported == false`）。
    public let launchAtLogin: Bool?
    /// `connected(owner: .external, _)` 時的掛載目標，只給 UI 顯示。
    public let externalTargetPath: String?
    public let banner: PanelBanner?
    /// T12（B5）：系統值（`NSWorkspace.accessibilityDisplayShouldReduceMotion`）與使用者偏好
    /// 各自帶進來——`OptionsSectionView` 只從這兩個欄位算「減少動態」列，不自己問 `NSWorkspace`
    /// （AuraCore 零 AppKit 依賴，`AppDelegate.refreshPanel()` 讀好傳進來，同 `version` 的理由）。
    public let systemReduceMotion: Bool
    public let userReduceMotion: Bool
    /// T16：燈條底板開關目前值——`OptionsSectionView` 只從這個欄位算「燈條底板」列，
    /// 不自己問 `UserDefaults`（同 `userReduceMotion` 的理由，唯一寫入點是 `AppDelegate.performSetIconPlate`）。
    public let iconPlate: Bool
    /// T32：選單列 icon 造型目前值——`OptionsSectionView` 只從這個欄位算「icon 造型」列，
    /// 不自己問 `UserDefaults`（同 `iconPlate` 的理由，唯一寫入點是 `AppDelegate.performSetIconShape`）。
    public let iconShape: IconShape
    /// D-3（i18n）：顯示層參數，不是全域狀態——唯一來源是 `AppDelegate.language`
    /// （落盤預設英文，見 `LanguagePreference`），往下傳給 `OptionsSectionView` 等消費端。
    public let language: Language
    /// T08（spec §3／§4.6）：Codex 掛載六態，唯一來源是 `AppDelegate+Codex.reprobeCodex()`
    /// 的行程常數（D-t）——`PanelModel` 只是原封不動帶著走，不在這裡重新判定。
    /// `CodexSectionView`（T09）依這個欄位分支；`OptionsMenuModel.rows(codex:)`
    /// 走的是同一個值（`AppDelegate.refreshPanel` 只算一次、兩處都傳）。
    public let codex: CodexState
    /// T08（R-10／D-s）：`(pathRejection == .mustMoveToApplications) ? nil : CodexHooksJSON.snippet(...)`
    /// 的產出——**穿過路徑判定**才拿到，不是 `CodexHooksJSON.snippet` 的直接輸出，
    /// `PanelModel` 一樣只是帶著走。`nil` 時面板卡片改顯示「先把 App 移到『應用程式』」
    /// 那句（見 `CodexSectionView`），不是省略整塊。
    public let codexSnippet: String?
    /// T08b（T07 review 回頭補的裂縫，R-9）：`CodexHookPathCheck.rejection(...)` 的行程常數
    /// （D-t），橫跨 `.connectedStalePath`（要不要給「重新接上」按鈕）與 `.occupiedByOther`
    /// （snippet 要不要被扣住，見 `codexSnippet`）兩個 case，不是任何一個 `CodexState`
    /// case 自己的欄位——`CodexState.swift` 的 doc comment 已經寫明這件事，這裡只是把
    /// 那個外部輸入原封不動帶到 `OptionsMenuModel.rows(codex:codexPathRejection:)`。
    /// `OptionsSectionView.rows` 是唯一生產消費點——忘了從這裡讀（改用字面 `nil`），
    /// 就是「重新接上」按鈕永遠不出現的那個 tested≠wired 坑，見
    /// `OptionsMenuModelRowsCallSiteSourceScanTests`。
    public let codexPathRejection: CodexHookPathCheck.Rejection?

    /// `rows`／`title` 借用既有的 `PanelViewModel`（已測過的純函式）；`palette` 直接帶入、
    /// `legend` 經 `LegendModel.items(for:)` 組裝、`isDefaultPalette` = `palette.isDefault`。
    ///
    /// **新參數一律不給預設值（只有 `now:` 例外，G13）**：忘了傳要是編譯錯，不是靜默畫
    /// 「已接上」——`install` 沒有一個「安全的預設狀態」，猜錯的後果是畫出使用者從未同意過
    /// 的畫面（S1-Q10.3c）。
    public static func make(icon: IconState, sessions: [SessionState], palette: IconPalette,
                            install: InstallState, version: String, optionsExpanded: Bool,
                            launchAtLogin: Bool?, externalTargetPath: String?, banner: PanelBanner?,
                            systemReduceMotion: Bool, userReduceMotion: Bool, iconPlate: Bool, iconShape: IconShape,
                            language: Language, codex: CodexState, codexSnippet: String?,
                            codexPathRejection: CodexHookPathCheck.Rejection?, now: Date = Date()) -> PanelModel {
        PanelModel(title: title(for: icon, install: install, codex: codex, language: language),
                  rows: PanelViewModel.rows(from: sessions, now: now, language: language),
                  palette: palette,
                  legend: LegendModel.items(for: palette, language: language),
                  isDefaultPalette: palette.isDefault,
                  install: install, version: version, optionsExpanded: optionsExpanded,
                  launchAtLogin: launchAtLogin, externalTargetPath: externalTargetPath, banner: banner,
                  systemReduceMotion: systemReduceMotion, userReduceMotion: userReduceMotion, iconPlate: iconPlate,
                  iconShape: iconShape, language: language, codex: codex, codexSnippet: codexSnippet,
                  codexPathRejection: codexPathRejection)
    }

    /// T11 commit2（S0-2）：非 `connected` 時面板標題改用 `install.healthLabel`——與
    /// footer chip／`NotConnectedView` 的說明句同一個 oracle。舊行為（`PanelViewModel.title`，
    /// 純算 session 計數）留給 `connected` 用，否則標題會在還沒接上時說「沒有活著的
    /// session」，跟面板本體的「還沒接上」自相矛盾（persona S0-2：同一張畫面兩句互相打架）。
    ///
    /// T13f（D-y，S1-1）：非 `connected` 分支改讀 `PanelModel.statusLabel(install:codex:language:)`
    /// 這個共用 static 核心（`PanelModel+ConnectCTA.swift`）——**修的是同一族毛病的下一個
    /// 實例**：標題只反映 Claude 時，Codex 已接上且正在跑會全部寫「Not connected yet」，
    /// 跟面板本體另外兩處（footer chip／CTA 窄條）矛盾。`title` 在這裡（`make(...)` 建構
    /// `PanelModel` 實例之前）就要算好，還沒有 `self` 能呼叫 instance 版的
    /// `statusLabel(_:)`，因此吃 `codex` 參數、直接呼叫共用核心——這保證了 CX50④
    /// 「`title` 在 `install` 非 connected 時逐位元組等於 `statusLabel(l)`」是結構性的，
    /// 不是兩處各自抄一份湊出來的巧合。`connected` 分支維持既有語意不變（session 計數句，
    /// 本來就不分 agent，見 §3.1「標題那一欄的不對稱是刻意的」）。
    private static func title(for icon: IconState, install: InstallState, codex: CodexState, language: Language) -> String {
        if case .connected = install { return PanelViewModel.title(for: icon, language: language) }
        return statusLabel(install: install, codex: codex, language: language)
    }

    /// A11（T11 A9–A11 批次）：`connected` ＋ rows 空時的本體訊息——**不得跟 `title` 撞字**。
    /// 撞字的根因：`title` 走 session 計數句子（`PanelViewModel.title`），空 session 剛好
    /// 也是「沒有活著的 session」；`PanelView` 先前對這個分支手搓了同一句字面常數，
    /// 於是同一張畫面標題與本體一字不差——S0-2 那族「同一張畫面說兩次同一句話」的殘留。
    /// 只在這一種組合（`connected` 且 `rows.isEmpty`）會被顯示到，見 `PanelView` 的路由：
    /// 其餘狀態不是走 `.fullPanel`／`.explainOnly` 大版說明，就是 `rows` 非空直接列出。
    ///
    /// T26（i18n）：D-1 示範 3/3（純靜態、非 Options 列標題）——搬進 `L10nPanel` 字串表，
    /// 隨 `language` 換語言（同一個 oracle：`L10nPanel.emptyRowsMessage.text(_:)`）。
    ///
    /// T13g（S1-2，D-z）：`codex == .connected` 時改讀 `emptyRowsMessageWithCodex`——
    /// 同時點名兩個 agent。其餘 codex 狀態（含 `.unavailable`）逐位元組維持原句，
    /// 這是 CX53 的第一條斷言（D-j：沒裝 Codex 的人零 diff）。
    public var emptyRowsMessage: String {
        codex == .connected ? L10nPanel.emptyRowsMessageWithCodex.text(language) : L10nPanel.emptyRowsMessage.text(language)
    }
}
