import Testing
import AuraCore

/// T01 必辦①：`affordanceMatchesTable`（spec §3.1.1、§6.2、§6.3）。
///
/// 定義域是 **`Reason.allCases × MountOwner.allCases` ＋ 三個頂層 case**，
/// 不是「狀態機目前可達的那些」——`occupiedByFile`／`occupiedByDirectory` 配
/// `owner: .external` 目前不可達是狀態機的運氣，不是 `affordance` 這個屬性的定義域。
/// **格數不寫死**（R6）：`Reason` 從 8 個變 9 個（r6②新增 `hookUnconfirmed`）之後，
/// 這條 gate 自動從 24 格變 27 格，不必改這個檔案一個字。
@Suite("InstallState.affordance 對照表（affordanceMatchesTable）")
struct InstallAffordanceTests {

    /// §3.1.1 的表，逐格搬過來——這是唯一的 oracle。
    static func oracle(_ reason: InstallState.Reason, _ owner: MountOwner) -> ConnectAffordance {
        switch reason {
        case .occupiedByFile: return .explainOnly(.occupiedByFile)
        case .occupiedByDirectory: return .explainOnly(.occupiedByDirectory)
        default: return owner == .external ? .replaceExternal : .connect
        }
    }

    @Test("broken(Reason, owner:) 逐格比對 §3.1.1（格數由 Reason.allCases × MountOwner.allCases 推導）")
    func brokenGridMatchesTable() {
        for reason in InstallState.Reason.allCases {
            for owner in MountOwner.allCases {
                let state = InstallState.broken(reason, owner: owner)
                let expected = Self.oracle(reason, owner)
                #expect(state.affordance == expected, """
                    broken(.\(reason), owner: .\(owner)) 的 affordance 是 \(state.affordance)，
                    §3.1.1 的表要求 \(expected)
                    """)
            }
        }
    }

    @Test("三個頂層 case：claudeNotFound / notConnected / connected 代表值")
    func topLevelCasesMatchTable() {
        #expect(InstallState.claudeNotFound.affordance == .explainOnly(nil),
                "claudeNotFound 的 affordance 應為 .explainOnly(nil)")
        #expect(InstallState.notConnected.affordance == .connect,
                "notConnected 的 affordance 應為 .connect")
        #expect(InstallState.connected(owner: .thisApp, verified: .verified).affordance == .none,
                "connected(_, _) 的 affordance 應為 .none")
    }

    /// B4（/simplify 波次1，reuse#2）：`InstallState.owner` 對頂層 case 回 nil，
    /// `connected`／`broken` 直接回它們各自帶的 `MountOwner` payload——這是唯一的
    /// 「取 owner」推導，窮盡到跟 `affordanceMatchesTable` 同一組定義域。
    @Test("owner：claudeNotFound／notConnected 為 nil，connected／broken 回各自的 owner payload")
    func ownerReflectsPayloadOrNilForTopLevelCases() {
        #expect(InstallState.claudeNotFound.owner == nil)
        #expect(InstallState.notConnected.owner == nil)
        for reason in InstallState.Reason.allCases {
            for owner in MountOwner.allCases {
                #expect(InstallState.broken(reason, owner: owner).owner == owner, "\(reason)／\(owner)")
            }
        }
        for owner in MountOwner.allCases {
            for verified in Verification.allCases {
                #expect(InstallState.connected(owner: owner, verified: verified).owner == owner, "\(owner)／\(verified)")
            }
        }
    }

    /// B5（/simplify 波次1，reuse#5）：`isConnected` 就是 `affordance == .none` 的具名版本——
    /// app 層曾有兩份逐字相同的 IIFE 各自判斷，都繞過了唯一的路由來源。
    @Test("isConnected 恰等於 affordance == .none，窮盡全部狀態")
    func isConnectedMatchesNoneAffordanceExhaustively() {
        for state in InstallStateAllCases.all() {
            #expect(state.isConnected == (state.affordance == .none), "\(state)")
        }
    }

    /// 補強：§3.1.1 表把 `connected(_, _)` 寫成單一列——**不分 owner／verified**。
    /// 上面的核心比對只挑了一個代表值，這條把 `MountOwner × Verification`
    /// 12 種組合全掃過，鎖住「connected 永遠 .none，不因 owner／verified 而不同」。
    @Test("connected 對任何 (owner, verified) 組合都是 .none")
    func connectedIsAlwaysNoneRegardlessOfOwnerOrVerification() {
        for owner in MountOwner.allCases {
            for verified in Verification.allCases {
                let state = InstallState.connected(owner: owner, verified: verified)
                #expect(state.affordance == .none, """
                    connected(owner: .\(owner), verified: .\(verified)) 的 affordance 是 \(state.affordance)，
                    應恆為 .none
                    """)
            }
        }
    }
}
