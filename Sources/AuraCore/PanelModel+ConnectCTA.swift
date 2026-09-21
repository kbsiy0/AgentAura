/// T26：搬出 `PanelModel.swift`本體，純粹為了在 200 行上限內騰出空間給 `language`
/// 欄位（D-3：`PanelModel.make` 多吃一個 `language`）——這裡的內容是**原封不動搬移**，
/// 不是重寫，`connectCTAText`／`connectCTASubtitle`／`connectCTAAction`／`connectCTAStyle`／
/// `showsConnectCTA`／`effectiveBanner`／`showsExplanationPanel` 這批本來就是 computed
/// property，可以住在 extension 裡（跟 `PanelModel+NotConnectedDetail.swift` 同一個手法）。
extension PanelModel {
    /// D-v（T13b，S0-1）：面板上有沒有任何一列是 Codex 的——`.codexConnected` banner 的
    /// 退場條件。用 `agentLabel == Agent.codex.label`（**不是** `agentLabel != nil`）：
    /// 目前只有兩種 agent，兩種寫法今天等價，但第三種 agent 進來時 `!= nil` 會把它的列
    /// 也當成「Codex 出現了」而靜默誤退場；`Agent.codex.label` 恆非 nil，已由既有
    /// `CodexRowLabelTests.codexLabelIsPinnedToLiteralCodex` 釘住字面。
    public var hasCodexRow: Bool {
        rows.contains { $0.agentLabel == Agent.codex.label }
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
    /// T27（i18n）：讀 `self.language`（`PanelModel` 既有欄位，D-3），零簽章變動。
    public var connectCTAText: String? {
        switch install.affordance {
        case .connect: return L10nPanel.connectCTAConnect.text(language)
        case .replaceExternal: return L10nPanel.connectCTAReplaceExternal.text(language)
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
    /// `.connected`／`.codexConnected` 兩個 kind 各自有自己的退場條件（它們是僅有的兩個
    /// 「宣稱某件事將會發生」的 banner）；其餘（`disconnected`／`error`／`alreadyConnected`）
    /// 沒有對應的「條件被滿足」可判斷，維持既有生命週期（使用者按 ✕，或被下一個 banner 蓋掉）。
    /// **不改寫 `banner` 這個原始欄位本身**——`AppDelegate` 存的狀態不受影響，這只是顯示層的推導。
    ///
    /// D-v（T13b，S0-1）：`.connected`（Claude）退場條件是「出現任何一列」——那裡「出現一個
    /// session」確實兌現了「下一個 session 起生效」。**`.codexConnected` 不能沿用同一條**：
    /// 出現一列 **Claude** 的 session 對「Codex 會問你一次是否信任」這句話什麼都沒兌現，
    /// 只在出現 **Codex 的列**（`hasCodexRow`）時才退場——這正是 persona r1 抓到的縫：
    /// 面板上有任何一列（哪怕是 Claude 的）就把 banner 抹掉，D-m 強制的兩句補償話因此
    /// 被靜默抑制。**禁止**把這條退場條件整個拿掉讓 `.connected` banner 也永遠留著——
    /// 那是弱化既有行為（A7 修掉的正是「banner 在條件兌現後還佔著頂端 40pt」），不是修 bug。
    public var effectiveBanner: PanelBanner? {
        switch banner?.kind {
        case .connected: if !rows.isEmpty { return nil }
        case .codexConnected: if hasCodexRow { return nil }
        default: break
        }
        return banner
    }

    /// A3（T11 commit3）：`.explainOnly` 沒有按鈕，但一樣要走大版說明（chip 當標題、
    /// 有副標可行動）——不是 `.fullPanel`（那個判斷專屬「有 CTA 按鈕」），是第三種內容樣式。
    /// `rows.isEmpty` 這個前提在實務上恆真（這三格代表 hook 從未真的接上過，不會有 session）。
    public var showsExplanationPanel: Bool {
        if case .explainOnly = install.affordance, rows.isEmpty { return true }
        return false
    }
}
