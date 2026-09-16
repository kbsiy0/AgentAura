import Testing
import AuraCore

/// A3（T11 commit3）：spec §3.1.1 承諾 `.explainOnly` 三格「無按鈕，只有 chip ＋ 說明文字」，
/// 但面板本體先前只印「沒有活著的 session」——`explanationDetail` 補上這半，
/// `showsExplanationPanel` 是 `PanelView` 用來決定要不要走大版說明的 derived property。
///
/// 定義域**由 `affordance` 過濾推導，不手寫清單**（R6）：第一版曾手寫
/// `[.claudeNotFound, .broken(.occupiedByFile, owner: .unknown), .broken(.occupiedByDirectory, owner: .unknown)]`，
/// 實跑 `InstallStateAllCases.all()` 立刻證明是錯的——`InstallAffordance.affordance` 對
/// `occupiedByFile`／`occupiedByDirectory` 完全不看 `owner`（見該檔），所以
/// `owner: .thisApp`／`.external` 兩種組合（雖然 `InstallState.from` 實務上不會產生，
/// 但型別上可直接建構）一樣是 `.explainOnly`，手寫清單漏了它們。
@Suite("`.explainOnly` 三格有非空、互不相同的說明文字（A3，T11 commit3）")
struct ExplainOnlyDetailTests {

    static var explainOnlyStates: [InstallState] {
        InstallStateAllCases.all().filter {
            if case .explainOnly = $0.affordance { return true }
            return false
        }
    }

    @Test("定義域非空（gate 不能空跑——至少涵蓋 claudeNotFound ＋ occupiedByFile／occupiedByDirectory 各 3 個 owner）")
    func explainOnlyStatesIsNotEmpty() {
        #expect(Self.explainOnlyStates.count >= 7, "實際只有 \(Self.explainOnlyStates.count) 個，定義域可能被過度過濾")
    }

    @Test("每一種 .explainOnly 狀態的 explanationDetail 非空")
    func explainOnlyStatesHaveNonEmptyDetail() {
        // i18n：**兩種語言都要驗**。這條測的是結構性質（非空），與語言無關，
        // 所以跑遍 `Language.allCases` 比只釘一種語言更強——它會抓到「某個狀態只翻了一半」。
        for language in Language.allCases {
            for state in Self.explainOnlyStates {
                let detail = state.explanationDetail(language)
                #expect(detail?.isEmpty == false, "\(state) 在 \(language) 的 explanationDetail 是 nil 或空字串 —— .explainOnly 沒有按鈕，說明文字是使用者唯一能看到的行動指引")
            }
        }
    }

    @Test("三種 Reason（claudeNotFound／occupiedByFile／occupiedByDirectory）的說明文字互不相同")
    func explainOnlyDetailsAreAllDistinctByReason() {
        // owner 不影響文案（affordance 本就不看 owner），這裡只需驗證「三種原因」本身分得開，
        // 不必逐 owner 組合都各自算一次 distinct（那樣只是同一句文字重複 3 次，Set 會誤判成通過）。
        let byReason: [InstallState] = [.claudeNotFound, .broken(.occupiedByFile, owner: .unknown),
                                        .broken(.occupiedByDirectory, owner: .unknown)]
        // i18n：互異性在每一種語言裡都必須成立（翻譯時把兩句翻成同一句也要抓到）。
        for language in Language.allCases {
            let details = byReason.compactMap { $0.explanationDetail(language) }
            #expect(details.count == byReason.count, "三種原因在 \(language) 應該都有非空文案")
            #expect(Set(details).count == details.count, "三種原因的 explanationDetail 在 \(language) 有重複：\(details)")
        }
    }

    /// T13（S1-1 收尾）：`explanationDetail` 從 `.explainOnly` 專屬放寬到「7 個 broken reason
    /// 各給一句」（見 `InstallAffordance.swift` 新版 switch）——這條把舊的「非 explainOnly
    /// 恆 nil」改窄成只管真正沒有 Reason 可講的兩種狀態（`.connected`／`.notConnected`），
    /// 不是弱化：新契約下「非 explainOnly」不再等於「恆 nil」，`everyBrokenReasonHasNonEmptyDetail`
    /// 補上另一半（explainOnly 之外的 7 個 broken reason 現在恆非空）。
    @Test(".connected／.notConnected 沒有 Reason 可講，explanationDetail 恆 nil")
    func connectedAndNotConnectedHaveNilDetail() {
        // i18n：「恆 nil」在每一種語言裡都必須成立——某個語言不小心回了空字串而不是 nil，
        // 這裡就要抓到（`.explainOnly` 的判斷讀的正是 nil／非 nil）。
        for language in Language.allCases {
            #expect(InstallState.notConnected.explanationDetail(language) == nil, "\(language)")
        }
        for owner in MountOwner.allCases {
            for verified in Verification.allCases {
                let state = InstallState.connected(owner: owner, verified: verified)
                #expect(Language.allCases.allSatisfy { state.explanationDetail($0) == nil }, """
                    \(state) 的 explanationDetail 應為 nil，實際「\(String(describing: state.explanationDetail(.english)))」
                    """)
            }
        }
    }

    /// T13：team-lead 指定的 gate——「每個 broken reason 的 explanationDetail 非空」，
    /// 窮盡全部 9 個 Reason（不只 explainOnly 的 occupiedByFile／occupiedByDirectory 兩個）
    /// × 全部 owner，不手寫清單（`InstallState.Reason.allCases`／`MountOwner.allCases` 推導）。
    @Test("每一個 broken reason（含 explainOnly 之外的 7 個）explanationDetail 皆非空")
    func everyBrokenReasonHasNonEmptyDetail() {
        for reason in InstallState.Reason.allCases {
            for owner in MountOwner.allCases {
                let state = InstallState.broken(reason, owner: owner)
                #expect(Language.allCases.allSatisfy { state.explanationDetail($0)?.isEmpty == false }, """
                    \(state) 的 explanationDetail 是 nil 或空字串 —— T13（S1-1）要求全部 9 個
                    Reason 在按下 CTA **之前**都要有可行動的說明，不是只有 explainOnly 的兩個
                    """)
            }
        }
    }

    /// B1（/simplify 波次1）：`everyBrokenReasonHasNonEmptyDetail` 只驗非空，
    /// `explainOnlyDetailsAreAllDistinctByReason` 只驗 3 個 explainOnly reason 互不相同——
    /// 兩條都抓不到「`.hookBlockedOrBroken`／`.hookUnconfirmed` 這兩句字面被寫顛倒」這種
    /// mutation（單一 switch 化之後兩句改成相鄰的兩個 case，寫顛倒的風險比分兩段時更高）。
    /// 這裡直接釘住它們就是 S1-1 那兩個共用常數（`InstallState.hookBlockedPrescription`／
    /// `hookUnconfirmedPrescription`）本身，不因 owner 而不同。
    @Test("hookBlockedOrBroken／hookUnconfirmed 的 explanationDetail 恰為對應的共用 prescription 常數")
    func hookFailureReasonsUseSharedPrescriptionConstants() {
        for owner in MountOwner.allCases {
            // i18n：兩種語言都要對上各自的 prescription 常數，不是只有中文那半。
            for language in Language.allCases {
                #expect(InstallState.broken(.hookBlockedOrBroken, owner: owner).explanationDetail(language)
                        == InstallState.hookBlockedPrescription(language), "owner: .\(owner) / \(language)")
                #expect(InstallState.broken(.hookUnconfirmed, owner: owner).explanationDetail(language)
                        == InstallState.hookUnconfirmedPrescription(language), "owner: .\(owner) / \(language)")
            }
        }
    }

    @Test("showsExplanationPanel：.explainOnly 且 rows 空 → true；其餘 → false")
    func showsExplanationPanelReflectsAffordance() {
        for state in Self.explainOnlyStates {
            let model = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                        install: state, version: "1.0", optionsExpanded: false,
                                        launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
            #expect(model.showsExplanationPanel, "\(state) 的 showsExplanationPanel 應為 true")
        }
        let connected = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                        install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                                        optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
        #expect(!connected.showsExplanationPanel, "已接上不該走說明樣式")
        let notConnected = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                           install: .notConnected, version: "1.0", optionsExpanded: false,
                                           launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
        #expect(!notConnected.showsExplanationPanel, "notConnected 走的是有 CTA 按鈕的 .fullPanel，不是純說明樣式")
    }
}
