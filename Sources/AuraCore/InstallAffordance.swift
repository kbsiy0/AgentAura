extension InstallState {
    /// B4（/simplify 波次1，reuse#2）：從 app 層 `AppDelegate+Verification.owner(of:)` 搬過來——
    /// 那是 app 層唯一對 `InstallState` 的窮盡 switch，`InstallState` 的窮盡 gate
    /// （`affordanceMatchesTable` 等）只守 `AuraCore` 內的 switch，看不到它；一旦 `InstallState`
    /// 加一個 case 或 `connected` 的 payload 改形狀，那個 switch 可能漏改也不會有任何東西變紅。
    /// 搬進來後跟 `affordance`／`healthLabel` 同一層維護、同一批 gate 守著。
    public var owner: MountOwner? {
        switch self {
        case .claudeNotFound, .notConnected: return nil
        case .connected(let owner, _): return owner
        case .broken(_, let owner): return owner
        }
    }

    /// B5（/simplify 波次1，reuse#5）：`affordance == .none` 的具名版本——app 層有兩份
    /// 逐字相同的 IIFE（`{ if case .connected = installState { return true }; return false }()`）
    /// 判斷「是不是已接上」，都繞過了唯一的路由來源 `affordance`（N9／S2-6）。
    public var isConnected: Bool { affordance == .none }
}

/// spec §3.1.1：唯一的「這個狀態能做什麼」。任何呼叫端不得自己看 `owner`
/// 或 `switch InstallState` 做「可否安全替換」的判斷（N9／S2-6）——一律讀這個屬性。
public enum ConnectAffordance: Equatable, Sendable {
    case connect                    // 可以直接接上（含「目標不存在，沒有東西會被毀」）
    case replaceExternal            // 只能走 replaceExternalMount（需使用者明確選擇）
    case explainOnly(InstallState.Reason?)  // 只能解釋，沒有 app 能做的動作
    case none                       // 已接上
}

extension InstallState {
    /// **實作形式是強制的（S0-1(i)）**：`case .broken(let reason, let owner)` 之後，
    /// switch 的最外層必須是 `Reason`，`owner` 只准在**單一 Reason 分支內**被讀。
    /// **不得先對 `owner` 分派**——三種寫法實跑過 `swiftc -typecheck -swift-version 6`：
    /// 規定形式漏一個 `Reason` 是 error（好）；r3 表的列序（`broken(_, owner:)` 排在具體
    /// Reason 之前）與「owner 在最外層」兩種壞寫法**零 error、零 warning**，24 格中
    /// 分別錯 6 格／2 格——Swift 對「帶 payload 的 enum 互相覆蓋」完全不會報，
    /// 機械 gate `affordanceMatchesTable` 是唯一同時抓得到兩種壞寫法的東西。
    public var affordance: ConnectAffordance {
        switch self {
        case .claudeNotFound:
            return .explainOnly(nil)
        case .notConnected:
            return .connect
        case .connected:
            return .none
        case .broken(let reason, let owner):
            switch reason {
            case .occupiedByFile:
                return .explainOnly(.occupiedByFile)
            case .occupiedByDirectory:
                return .explainOnly(.occupiedByDirectory)
            case .targetMissing, .targetUnresolvable, .notAPlugin,
                 .hookMissing, .hookNotExecutable, .hookBlockedOrBroken, .hookUnconfirmed:
                return owner == .external ? .replaceExternal : .connect
            }
        }
    }
}

extension InstallState {
    /// A3（T11 commit3）＋ S1-1（T13 收尾）：`.explainOnly` 的三格說明維持不變；T13 把
    /// 同一個屬性放寬到 `.connect`／`.replaceExternal` 這 7 個 broken reason——這 7 個雖然
    /// 有 CTA 按鈕，但 persona 實測按下去之前使用者看不到任何處方，落地頁把同一句
    /// healthLabel 印三次卻不給行動指引。`.hookBlockedOrBroken`／`.hookUnconfirmed` 直接
    /// 沿用 `AppDelegate+Connect.swift` 的 `handleConnectFailure` 同一句錯誤文案
    /// （`hookBlockedPrescription`／`hookUnconfirmedPrescription`，單一 oracle，不重複維護）；
    /// 其餘 5 個 Reason 底下 `.connect` 真的會重建掛載修好（`Installer.performConnectSteps()`
    /// 一律原子替換成指向這個 App 的新掛載，不看是哪個 Reason 壞的），所以給同一句
    /// 「按鈕會怎樣」的事實陳述，不是新編的行銷文案。
    /// B1（/simplify 波次1，alt#3／struct E1）：改成單一 `switch self`——原本以
    /// `affordance` 為 key，內部要再寫一次「{occupiedByFile, occupiedByDirectory} vs
    /// 其餘 7 個」這個分割（`affordance` 自己已經寫過一次），還留下 4 個「防禦性保留」
    /// 的死分支（每個 reason 在兩個分支裡給的字串完全一樣，因為這個屬性本來就只是
    /// `Reason` 的函式）。逐格核對過對每一個可達輸入行為完全等價；`explainOnlyStates*`
    /// 與 `everyBrokenReasonHasNonEmptyDetail` 這兩條既有 gate 因此從「碰巧成立」
    /// （`affordance` 剛好把 9 個 reason 分成兩組，兩組都被填了字串）變成「結構上必然」
    /// （`Reason.allCases` 9 格在這裡被逐一窮盡，不會再漏）。
    public var explanationDetail: String? {
        switch self {
        case .claudeNotFound:
            return "看起來還沒用過 Claude Code，先跑一次（隨便問它一句話）再回來，通常就能一鍵接上。"
        case .notConnected, .connected:
            return nil
        case .broken(let reason, _):
            switch reason {
            case .occupiedByFile:
                return "~/.claude/skills/agentaura 目前是一個普通檔案，不是掛載用的位置。手動刪除或搬走這個檔案，再從 Options 選「重新接上 Claude Code」。"
            case .occupiedByDirectory:
                return "~/.claude/skills/agentaura 目前是別的安裝在用的目錄，AgentAura 不會動它。確認那個安裝不再需要之後手動移除該目錄，再從 Options 選「重新接上 Claude Code」。"
            case .hookBlockedOrBroken:
                return Self.hookBlockedPrescription
            case .hookUnconfirmed:
                return Self.hookUnconfirmedPrescription
            case .targetMissing, .targetUnresolvable, .notAPlugin, .hookMissing, .hookNotExecutable:
                return "按下面的按鈕會重新建立掛載，通常就能修好。"
            }
        }
    }

    /// S1-1：與 `AppDelegate+Connect.swift` 的 `handleConnectFailure` 共用同一句——按下「接上」
    /// 真的失敗之後的錯誤 banner，與按下之前 `explanationDetail` 顯示的處方是同一句話，
    /// 只維護一份，不允許兩處各自抄一份而之後各自漂移。
    public static let hookBlockedPrescription =
        "macOS 擋住了 hook。把 App 拖進「應用程式」再開一次；或到系統設定 → 隱私與安全性允許。"
    public static let hookUnconfirmedPrescription = "無法確認 hook 能不能跑，稍後再試一次。"
}

/// §3.3：`healthTone` 的實際色值寫死——`ok` 與 done 同色、`warn` 與 waiting 同色，
/// 語意一致是刻意的，配色不改。
public enum HealthTone: Equatable, Sendable {
    case ok
    case warn

    public var color: RGBA {
        switch self {
        case .ok:   return RGBA(r:  48/255, g: 209/255, b:  88/255, a: 1) // #30d158
        case .warn: return RGBA(r: 255/255, g: 159/255, b:  10/255, a: 1) // #ff9f0a
        }
    }
}

extension InstallState {
    /// §3.3：健康 chip 文字，由 `InstallState` 窮盡推導。`connected` 對 `(owner, verified)`
    /// 逐格——`owner` 決定要不要插入「你的 repo 掛載」子句、`verified` 決定要不要加驗證狀態；
    /// `.inFlight` 與 `.unknown` 必須不同文案（R2：「檢查中…」是關於進行中的宣稱，
    /// 沒東西在進行時就是說謊）。
    ///
    /// S2（T11 A9–A11 批次，team-lead 自查）：三個子句一律用「 · 」串接，不再用兩層括號
    /// 疊字（舊版 `owner==.external ＋ unknown` 會印出「已接上（未驗證）（你的 repo 掛載）」，
    /// 兩個括號子句疊在一起）——改成「已接上 · 你的 repo 掛載 · 未驗證」，唸起來是一句話。
    public var healthLabel: String {
        switch self {
        case .claudeNotFound:
            return "找不到 Claude Code"
        case .notConnected:
            return "還沒接上"
        case .connected(let owner, let verified):
            var parts = ["已接上"]
            if owner == .external { parts.append("你的 repo 掛載") }
            switch verified {
            case .verified:
                break
            case .inFlight:
                parts.append("檢查中…")
            case .unknown, .blocked, .unconfirmed:
                // `InstallState.from` 永遠不會產出 `.blocked`／`.unconfirmed` 這兩個組合
                // （分別導向 `broken(.hookBlockedOrBroken, _)`／`broken(.hookUnconfirmed, _)`，
                // r6②），但 `connected` 的 case 型別上仍可被直接建構，窮盡 switch 必須列出；
                // 回傳與 `.unknown` 一致的保守文案，不得 crash。
                parts.append("未驗證")
            }
            return parts.joined(separator: " · ")
        case .broken(let reason, _):
            switch reason {
            case .targetMissing:       return "接不上：App 被搬走了"
            case .targetUnresolvable:  return "接不上：掛載解不開"
            case .notAPlugin:          return "接不上：掛載內容不對"
            case .hookMissing:         return "接不上：少了 hook 程式"
            case .hookNotExecutable:   return "接不上：hook 沒有執行權限"
            case .hookBlockedOrBroken: return "接不上：macOS 擋住了 hook"
            case .hookUnconfirmed:     return "接不上：無法確認 hook 能不能跑"
            case .occupiedByDirectory: return "已被其他安裝佔用"
            case .occupiedByFile:      return "路徑被一個檔案佔住"
            }
        }
    }

    /// `connected` 恆 `.ok`，其餘（`claudeNotFound`／`notConnected`／`broken`）恆 `.warn`。
    public var healthTone: HealthTone {
        switch self {
        case .connected: return .ok
        case .claudeNotFound, .notConnected, .broken: return .warn
        }
    }
}
