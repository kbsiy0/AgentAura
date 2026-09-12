import Foundation

/// 接上成功／已接上／已移除掛載／錯誤的可關閉窄條（S1-P3/P4，spec §3.3）。
///
/// 只准經下列 public static 建構——與 `PanelModel.make` 同一個理由：任何呼叫端
/// 想顯示 banner 就只能挑這幾句，不能手搓文案（避免下一個人寫出「立即生效」那種謊，D-m）。
public struct PanelBanner: Equatable, Sendable {
    public enum Kind: String, Sendable, Equatable, CaseIterable { case connected, alreadyConnected, disconnected, error }
    public let kind: Kind
    public let text: String

    /// D-m：接上成功的固定文案——**不得**寫成「立即生效」，那是 S0-A1 修掉的謊
    /// （新掛載要下一個 Claude Code session 起才載入）。
    public static func connected() -> PanelBanner {
        PanelBanner(kind: .connected, text: "已接上 · 下一個 Claude Code session 起生效（現在開著的視窗不受影響）")
    }

    /// §4.1：`connect()` 對有效掛載的冪等回應（S2-5）——不是錯誤，是「本來就好了」。
    public static func alreadyConnected(target: String?) -> PanelBanner {
        PanelBanner(kind: .alreadyConnected, text: "已經接上了" + (target.map { "（指向 \($0)）" } ?? ""))
    }

    /// S1-P4：措辭必須與「壞掉」明顯不同，否則使用者以為自己弄壞了。
    public static func disconnected() -> PanelBanner {
        PanelBanner(kind: .disconnected, text: "已移除掛載。要再用的話按［接上］。")
    }

    /// A5（T11 commit3）：`replaceExternalMount` 成功的專屬文案——與一般 `connected()`
    /// 不對稱的地方正是這裡：這顆按鈕做的事是「把開發者的掛載換成 App 內建的凍結版」，
    /// 不明說換了什麼，使用者只會覺得「畫面變了但不知道為什麼」。沿用 `.connected` kind
    /// （視覺樣式相同，仍是成功色），只有文案不同。
    public static func mountReplaced(from target: String?) -> PanelBanner {
        let suffix = target.map { "（原掛載：\($0)）" } ?? ""
        return PanelBanner(kind: .connected,
                           text: "已接上 · 掛載已換成這個 App\(suffix) · 下一個 Claude Code session 起生效")
    }

    public static func error(_ message: String) -> PanelBanner {
        PanelBanner(kind: .error, text: message)
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

    /// `rows`／`title` 借用既有的 `PanelViewModel`（已測過的純函式）；`palette` 直接帶入、
    /// `legend` 經 `LegendModel.items(for:)` 組裝、`isDefaultPalette` = `palette.isDefault`。
    ///
    /// **新參數一律不給預設值（只有 `now:` 例外，G13）**：忘了傳要是編譯錯，不是靜默畫
    /// 「已接上」——`install` 沒有一個「安全的預設狀態」，猜錯的後果是畫出使用者從未同意過
    /// 的畫面（S1-Q10.3c）。
    public static func make(icon: IconState, sessions: [SessionState], palette: IconPalette,
                            install: InstallState, version: String, optionsExpanded: Bool,
                            launchAtLogin: Bool?, externalTargetPath: String?, banner: PanelBanner?,
                            systemReduceMotion: Bool, userReduceMotion: Bool, iconPlate: Bool,
                            now: Date = Date()) -> PanelModel {
        PanelModel(title: title(for: icon, install: install),
                  rows: PanelViewModel.rows(from: sessions, now: now),
                  palette: palette,
                  legend: LegendModel.items(for: palette),
                  isDefaultPalette: palette.isDefault,
                  install: install, version: version, optionsExpanded: optionsExpanded,
                  launchAtLogin: launchAtLogin, externalTargetPath: externalTargetPath, banner: banner,
                  systemReduceMotion: systemReduceMotion, userReduceMotion: userReduceMotion, iconPlate: iconPlate)
    }

    /// T11 commit2（S0-2）：非 `connected` 時面板標題改用 `install.healthLabel`——與
    /// footer chip／`NotConnectedView` 的說明句同一個 oracle。舊行為（`PanelViewModel.title`，
    /// 純算 session 計數）留給 `connected` 用，否則標題會在還沒接上時說「沒有活著的
    /// session」，跟面板本體的「還沒接上」自相矛盾（persona S0-2：同一張畫面兩句互相打架）。
    private static func title(for icon: IconState, install: InstallState) -> String {
        if case .connected = install { return PanelViewModel.title(for: icon) }
        return install.healthLabel
    }

    /// §3.1.1：只讀 `install.affordance`，不得自己 switch `InstallState` 或看 `owner`（N9／S2-6）——
    /// 那正是 r3 讓 4 格顯示「按了只會出錯的按鈕」的原因。
    ///
    /// E10（/simplify 波次2，struct#D1）：與 `connectCTAAction` 是同一張 `affordance→CTA` 表的
    /// 兩欄——`.connect`／`.replaceExternal` 恆非 nil，`.explainOnly`／`.none` 恆 nil，
    /// 直接由後者推導，不再自己重寫第三份 switch（新增第五種 affordance 只要改一處）。
    public var showsConnectCTA: Bool { connectCTAAction != nil }

    /// CTA 按鈕文案，與 `showsConnectCTA` 共用同一個 oracle（§3.1.1 的 affordance→CTA 表）。
    /// spec 沒有指名承載它的符號，放在這裡與 `showsConnectCTA`／`connectCTAStyle` 相鄰，
    /// 理由相同：呼叫端只准讀 `affordance`，不准自己 switch（`.replaceExternal` 的副標
    /// 「現有掛載指向何處」另由 `externalTargetPath` 提供，不併進這個字串）。
    public var connectCTAText: String? {
        switch install.affordance {
        case .connect: return "接上"
        case .replaceExternal: return "改指向這個 App"
        case .explainOnly, .none: return nil
        }
    }

    /// A5（T11 commit3）：`.banner` 版 CTA 的副標——`.fullPanel` 版（`NotConnectedView`）
    /// 一直都有這行（讀 `externalTargetPath`），`.banner` 版先前沒有，P3（整夜跑 pipeline、
    /// 有活著的列）看不到自己的掛載指向哪裡。與 `connectCTAText` 共用同一個 oracle
    /// （只讀 `affordance`，不自己 switch `InstallState`，N9）。
    public var connectCTASubtitle: String? {
        switch install.affordance {
        case .replaceExternal: return mountTargetNote
        case .connect, .explainOnly, .none: return nil
        }
    }

    /// CTA 按鈕要送出的動作，與 `showsConnectCTA`／`connectCTAText` 共用同一個 oracle
    /// （§3.1.1）——view 不得自己 switch `affordance` 決定要送 `.connect` 還是
    /// `.replaceExternalMount`（否則又是 N9／S2-6 那個錯：呼叫端自己判斷路由）。
    /// `.replaceExternal` 送 `.replaceExternalMount`（D-i：明確選擇改指向 App 內建，
    /// r7：`replaceExternalMount` 的唯一觸發處就是 CTA）；`.connect` 送 `.connect`
    /// （與「重新接上」選單列送同一個 action，r7）。
    public var connectCTAAction: PanelAction? {
        switch install.affordance {
        case .connect: return .connect
        case .replaceExternal: return .replaceExternalMount
        case .explainOnly, .none: return nil
        }
    }

    /// §3.3／N10：banner 與 CTA 的優先序——同一時間畫面上方最多一條窄條。
    /// `effectiveBanner != nil` 時把 `.banner` 樣式降級為 `.none`（banner 贏）；
    /// `.fullPanel`（rows 空的整版 CTA）與 banner 可以並存，banner 在上。
    public var connectCTAStyle: CTAStyle {
        guard showsConnectCTA else { return .none }
        let base: CTAStyle = rows.isEmpty ? .fullPanel : .banner
        if effectiveBanner != nil, base == .banner { return .none }
        return base
    }

    /// A7（T11 commit3）：banner 沒有生命週期——「下一個 session 起生效」在它宣稱的條件
    /// 被滿足之後（真的出現第一個 session）還一直留著，佔掉面板頂端 40pt。
    /// 只有 `.connected` kind 有這個自動退場條件（它是唯一「宣稱某件事將會發生」的 banner）；
    /// 其餘（`disconnected`／`error`／`alreadyConnected`）沒有對應的「條件被滿足」可判斷，
    /// 維持既有生命週期（使用者按 ✕，或被下一個 banner 蓋掉）。**不改寫 `banner` 這個
    /// 原始欄位本身**——`AppDelegate` 存的狀態不受影響，這只是顯示層的推導。
    public var effectiveBanner: PanelBanner? {
        if banner?.kind == .connected, !rows.isEmpty { return nil }
        return banner
    }

    /// A3（T11 commit3）：`.explainOnly` 沒有按鈕，但一樣要走大版說明（chip 當標題、
    /// 有副標可行動）——不是 `.fullPanel`（那個判斷專屬「有 CTA 按鈕」），是第三種內容樣式。
    /// `rows.isEmpty` 這個前提在實務上恆真（這三格代表 hook 從未真的接上過，不會有 session）。
    public var showsExplanationPanel: Bool {
        if case .explainOnly = install.affordance, rows.isEmpty { return true }
        return false
    }

    /// A11（T11 A9–A11 批次）：`connected` ＋ rows 空時的本體訊息——**不得跟 `title` 撞字**。
    /// 撞字的根因：`title` 走 session 計數句子（`PanelViewModel.title`），空 session 剛好
    /// 也是「沒有活著的 session」；`PanelView` 先前對這個分支手搓了同一句字面常數，
    /// 於是同一張畫面標題與本體一字不差——S0-2 那族「同一張畫面說兩次同一句話」的殘留。
    /// 只在這一種組合（`connected` 且 `rows.isEmpty`）會被顯示到，見 `PanelView` 的路由：
    /// 其餘狀態不是走 `.fullPanel`／`.explainOnly` 大版說明，就是 `rows` 非空直接列出。
    public var emptyRowsMessage: String {
        "Claude Code 開起來、開始跑之後，這裡會列出每個 session。"
    }
}
