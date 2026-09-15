import Testing
import AuraCore

/// G1（spec §6.3）：`InstallState.from(_:verification:)` 對 §6.1 fixture 逐一驗判定順序，
/// 外加 `healthLabel`／`healthTone`（§3.3）窮盡推導——狀態集合由型別推導
/// （`Reason.allCases × MountOwner.allCases` ＋ connected 的 `MountOwner × Verification`
/// ＋ 兩個頂層 case），不寫數字（R6）。`affordanceMatchesTable`（24 格 ＋ 3 頂層 case）
/// 另在 `InstallAffordanceTests.swift`，兩者互補、不重複。
@Suite("InstallState.from 判定與 healthLabel（G1）")
struct InstallStateTests {

    // MARK: - 頂層：claudeHomeExists / entryType 四值

    @Test("claudeHomeExists == false → .claudeNotFound（先於其他判定）")
    func claudeHomeMissingWins() {
        #expect(InstallState.from(LinkObservationFixtures.claudeHomeMissing, verification: .unknown) == .claudeNotFound)
    }

    @Test("entryType == .absent → .notConnected")
    func absentIsNotConnected() {
        #expect(InstallState.from(LinkObservationFixtures.notConnected, verification: .unknown) == .notConnected)
    }

    @Test("entryType == .otherFile → .broken(.occupiedByFile, owner: .unknown)（路徑上根本不是掛載）")
    func otherFileIsOccupiedByFile() {
        #expect(InstallState.from(LinkObservationFixtures.occupiedByFile, verification: .unknown)
                == .broken(.occupiedByFile, owner: .unknown))
    }

    @Test("entryType == .directory → .broken(.occupiedByDirectory, owner: .unknown)")
    func directoryIsOccupiedByDirectory() {
        #expect(InstallState.from(LinkObservationFixtures.occupiedByDirectory, verification: .unknown)
                == .broken(.occupiedByDirectory, owner: .unknown))
    }

    // MARK: - symlink：resolveFailure（N3：斷鏈 ≠ 迴圈 ≠ 權限 ≠ 其他）

    @Test("resolveFailure == .notFound → .targetMissing（app 被搬走，最常見）")
    func notFoundIsTargetMissing() {
        #expect(InstallState.from(LinkObservationFixtures.brokenTargetMissing, verification: .unknown)
                == .broken(.targetMissing, owner: .unknown))
    }

    /// r6①：`.loop`／`.permissionDenied`／`.other` 且無法用 `rawLinkTarget` 正向命中
    /// bundle 前綴時，owner 是 `.external`（不是 `.unknown`）——目標可能還在，只是解不開，
    /// 不得被靜默替換，要使用者明確選擇（S1-A7 家族）。
    ///
    /// **改前**（r5 態）：owner 恆 `.unknown`。**改後**（r6①）：`.notFound` 仍是 `.unknown`
    /// （目標真的不存在，沒有東西會被毀），其餘三種 errno 變 `.external`。測的仍是同一件事
    /// （resolveFailure 與 targetUnresolvable 的對應），只是 owner 的期望值依 r6① 更正。
    @Test("resolveFailure ∈ {.loop, .permissionDenied, .other} 且無正向命中 → owner .external（目標可能還在，只是解不開，r6①）")
    func loopPermissionDeniedAndOtherAreTargetUnresolvableWithExternalOwner() {
        for fixture in [LinkObservationFixtures.brokenLoop, LinkObservationFixtures.brokenPermissionDenied,
                        LinkObservationFixtures.brokenOtherErrno] {
            #expect(InstallState.from(fixture, verification: .unknown) == .broken(.targetUnresolvable, owner: .external))
        }
    }

    // MARK: - symlink：解析成功，owner 依 targetIdentity 比對

    @Test("targetIdentity 與 thisAppPluginIdentity 相符 → owner .thisApp，一切完好 → .connected")
    func matchingIdentityIsThisAppConnected() {
        #expect(InstallState.from(LinkObservationFixtures.symlinkToThisAppComplete, verification: .verified)
                == .connected(owner: .thisApp, verified: .verified))
    }

    @Test("targetIdentity 與 thisAppPluginIdentity 不符 → owner .external，一切完好 → .connected(external)")
    func mismatchingIdentityIsExternalConnected() {
        #expect(InstallState.from(LinkObservationFixtures.symlinkToExternalComplete, verification: .verified)
                == .connected(owner: .external, verified: .verified))
    }

    @Test("解析成功但目標不是目錄 → .notAPlugin（與『是目錄但缺 hooks.json』刻意落同一格，N3 追加）")
    func targetNotDirectoryIsNotAPlugin() {
        #expect(InstallState.from(LinkObservationFixtures.symlinkToRegularFile, verification: .unknown)
                == .broken(.notAPlugin, owner: .external))
    }

    @Test("目錄但缺 hooks.json → .notAPlugin（與上一格同一個 Reason，不准補第 9 個）")
    func missingHooksJSONIsNotAPlugin() {
        #expect(InstallState.from(LinkObservationFixtures.symlinkMissingHooksJSON, verification: .unknown)
                == .broken(.notAPlugin, owner: .external))
    }

    @Test("有 hooks.json 但沒有 bin/aura-hook → .hookMissing")
    func missingHookBinaryIsHookMissing() {
        #expect(InstallState.from(LinkObservationFixtures.symlinkMissingHookBinary, verification: .unknown)
                == .broken(.hookMissing, owner: .external))
    }

    /// **G1 主 mutation 標的**：把 `hookNotExecutable` 併進 `connected`（拿掉第 7 步的
    /// `hookBinaryExecutable` guard）會讓這條紅——二進位存在但沒有 x 位絕不能算已接上。
    @Test("二進位存在但沒有 x 位 → .hookNotExecutable（不得被判成已接上）")
    func notExecutableIsHookNotExecutable() {
        #expect(InstallState.from(LinkObservationFixtures.symlinkHookNotExecutable, verification: .verified)
                == .broken(.hookNotExecutable, owner: .external))
    }

    @Test("看起來完好但 verification == .blocked → .hookBlockedOrBroken（只有 exec 驗證抓得到，S0-A2）")
    func executableButBlockedVerificationIsHookBlockedOrBroken() {
        let obs = LinkObservationFixtures.symlinkHookExecutableButQuarantined
        #expect(InstallState.from(obs, verification: .blocked) == .broken(.hookBlockedOrBroken, owner: .external))
        // 同一顆 LinkObservation，verification 換成 .verified 就是 .connected——
        // 證明「看起來完好」與「connected」是兩件事，差別只在注入的 verification（T01 必辦④）。
        #expect(InstallState.from(obs, verification: .verified) == .connected(owner: .external, verified: .verified))
    }

    /// r6②：`verification == .unconfirmed`（逾時／spawn 丟錯）與 `.blocked`（確實沒有產物）
    /// 必須落到不同的 Reason，不得混在一起——否則「無法確認」與「macOS 擋住了」共用同一句
    /// 文案，使用者會被誤導去系統設定允許一個其實只是機器睡眠造成的逾時。
    @Test("看起來完好但 verification == .unconfirmed → .hookUnconfirmed（與 .blocked 不同格，r6②）")
    func executableButUnconfirmedVerificationIsHookUnconfirmed() {
        let obs = LinkObservationFixtures.symlinkHookExecutableButQuarantined
        #expect(InstallState.from(obs, verification: .unconfirmed) == .broken(.hookUnconfirmed, owner: .external))
        #expect(InstallState.from(obs, verification: .unconfirmed) != InstallState.from(obs, verification: .blocked),
                ".unconfirmed 與 .blocked 必須是不同的 InstallState——文案不同，不得共用一格")
    }

    // MARK: - owner 的 fallback 分支（targetIdentity == nil，R4）

    @Test("thisAppPluginIdentity == nil（bundle 不完整／swift test）且無法用 rawLinkTarget 判斷 → owner .unknown")
    func bundleIncompleteFallsBackToUnknownOwner() {
        // rawLinkTarget 是假路徑，swift test 環境的 Bundle.main.resourceURL 必不吻合前綴，
        // 因此退回 .unknown——目標不存在時沒有東西會被毀（R4）。
        #expect(InstallState.from(LinkObservationFixtures.bundleIncompleteWithRawLinkTarget, verification: .verified)
                == .connected(owner: .unknown, verified: .verified))
    }

    @Test("targetIdentity 與 rawLinkTarget 都不可用 → owner .unknown，resolveFailure 仍照 §3.1 第 6 步分派")
    func bundleIncompleteWithoutRawLinkTargetIsUnknownOwner() {
        #expect(InstallState.from(LinkObservationFixtures.bundleIncompleteWithoutRawLinkTarget, verification: .unknown)
                == .broken(.targetMissing, owner: .unknown))
    }

    @Test("hookBinaryStamp 缺席不影響狀態判定（那是 Installer／store 的憑證欄位，不是 from() 的輸入）")
    func missingStampDoesNotAffectDerivation() {
        #expect(InstallState.from(LinkObservationFixtures.stampAbsent, verification: .verified)
                == .connected(owner: .thisApp, verified: .verified))
    }

    // MARK: - healthLabel／healthTone（§3.3，窮盡推導，集合由型別推導不寫數字）

    private static let brokenLabels: [InstallState.Reason: String] = [
        .targetMissing: "接不上：App 被搬走了",
        .targetUnresolvable: "接不上：掛載解不開",
        .notAPlugin: "接不上：掛載內容不對",
        .hookMissing: "接不上：少了 hook 程式",
        .hookNotExecutable: "接不上：hook 沒有執行權限",
        .hookBlockedOrBroken: "接不上：macOS 擋住了 hook",
        .hookUnconfirmed: "接不上：無法確認 hook 能不能跑",
        .occupiedByDirectory: "已被其他安裝佔用",
        .occupiedByFile: "路徑被一個檔案佔住",
    ]

    /// T27（i18n）：D-4 對齊——明確指定 `.traditionalChinese`，內容不變。
    @Test("broken 的 chip 文字只依 Reason（owner 不影響文字），tone 恆 .warn")
    func brokenHealthLabelAndToneCoverEveryReasonAndOwner() {
        for reason in InstallState.Reason.allCases {
            for owner in MountOwner.allCases {
                let state = InstallState.broken(reason, owner: owner)
                #expect(state.healthLabel(.traditionalChinese) == Self.brokenLabels[reason], "\(reason)／\(owner) 的 chip 文字對不上 §3.3 的表")
                #expect(state.healthTone == .warn, "\(reason)／\(owner) 的 tone 應為 .warn")
            }
        }
    }

    /// D-4：補英文版——每個 Reason 的英文都非空、且跟中文不同（不是漏翻）。
    @Test("broken 的 chip 文字（英文）每個 Reason 都非空且與中文不同")
    func brokenHealthLabelEnglishDiffersFromChinese() {
        for reason in InstallState.Reason.allCases {
            let state = InstallState.broken(reason, owner: .unknown)
            let en = state.healthLabel(.english)
            #expect(!en.isEmpty, "\(reason) 的英文 chip 文字是空的")
            #expect(en != state.healthLabel(.traditionalChinese), "\(reason) 的英文跟中文一樣，像是漏翻")
        }
    }

    @Test("claudeNotFound／notConnected 的 chip 文字與 tone")
    func topLevelHealthLabelAndTone() {
        #expect(InstallState.claudeNotFound.healthLabel(.traditionalChinese) == "找不到 Claude Code")
        #expect(InstallState.claudeNotFound.healthTone == .warn)
        #expect(InstallState.notConnected.healthLabel(.traditionalChinese) == "還沒接上")
        #expect(InstallState.notConnected.healthTone == .warn)
    }

    @Test("claudeNotFound／notConnected 的 chip 文字（英文）")
    func topLevelHealthLabelEnglish() {
        #expect(InstallState.claudeNotFound.healthLabel(.english) == "Claude Code not found")
        #expect(InstallState.notConnected.healthLabel(.english) == "Not connected yet")
    }

    /// S2（T11 A9–A11 批次）：三個子句用「 · 」串接（不再是兩層括號疊字），
    /// `owner==.external` 的子句排在 verified 子句之前——見 `InstallAffordance.healthLabel`。
    /// T27（i18n）：D-4 對齊——明確指定 `.traditionalChinese`，內容不變。
    @Test("connected 的 chip 對 (owner, verified) 逐格：owner 決定要不要插入掛載子句、verified 決定要不要加驗證狀態；tone 恆 .ok")
    func connectedHealthLabelAndToneCoverEveryOwnerAndVerification() {
        for owner in MountOwner.allCases {
            let ownerClause = owner == .external ? " · 你的 repo 掛載" : ""
            let state = { (v: Verification) in InstallState.connected(owner: owner, verified: v) }
            #expect(state(.verified).healthLabel(.traditionalChinese) == "已接上" + ownerClause)
            #expect(state(.inFlight).healthLabel(.traditionalChinese) == "已接上" + ownerClause + " · 檢查中…",
                    ".inFlight 與 .unknown 必須不同文案（R2：檢查中是關於進行中的宣稱）")
            #expect(state(.unknown).healthLabel(.traditionalChinese) == "已接上" + ownerClause + " · 未驗證")
            for verified in Verification.allCases {
                #expect(state(verified).healthTone == .ok, "connected 恆 .ok，\(owner)／\(verified) 不應例外")
            }
        }
    }

    /// D-4：補英文版——`owner`／`verified` 每一格都非空、跟中文不同。
    @Test("connected 的 chip 對 (owner, verified) 逐格（英文）：每格都非空且與中文不同")
    func connectedHealthLabelEnglishDiffersFromChinese() {
        for owner in MountOwner.allCases {
            for verified in Verification.allCases {
                let state = InstallState.connected(owner: owner, verified: verified)
                let en = state.healthLabel(.english)
                #expect(!en.isEmpty, "\(owner)／\(verified) 的英文 chip 文字是空的")
                #expect(en != state.healthLabel(.traditionalChinese), "\(owner)／\(verified) 的英文跟中文一樣，像是漏翻")
            }
        }
    }
}
