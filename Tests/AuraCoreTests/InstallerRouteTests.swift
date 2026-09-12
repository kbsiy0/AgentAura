import Testing
import AuraCore
import AuraHookFile

/// `affordanceRoutesConnect`（spec §6.2／§6.3，T08）：`Installer.connect(...)` 的路由決定
/// 委派給純函式 `Installer.route(for:force:)`（§3.1.1 唯一路由來源）——這條對**每一種**
/// `InstallState`（`Reason.allCases × MountOwner.allCases` ＋三個頂層 case，格數由型別推導，
/// 不寫數字，同 `InstallAffordanceTests` 的定義域）窮盡驗證 `route` 對得上 `.affordance`，
/// 不必為每一格建一份磁碟 fixture（那是 `InstallerClobberTests`／`InstallerTests` 少數幾個
/// 代表格已經在做的事，這裡補的是「N9 的兩個 switch 不再漂移」的全格覆蓋）。
@Suite("Installer.route 對照 affordance（affordanceRoutesConnect）")
struct InstallerRouteTests {

    @Test(".connect 的都不得走路由型早退——force 為 true／false 皆回 .proceed")
    func connectAffordanceAlwaysProceeds() {
        #expect(Installer.route(for: .connect, force: false) == .proceed)
        #expect(Installer.route(for: .connect, force: true) == .proceed)
    }

    @Test(".explainOnly 一律回 .cannotConnect(reason)，force 不影響（沒有 app 能做的動作）")
    func explainOnlyAlwaysCannotConnect() {
        for reason: InstallState.Reason? in [nil] + InstallState.Reason.allCases.map({ Optional($0) }) {
            #expect(Installer.route(for: .explainOnly(reason), force: false) == .cannotConnect(reason))
            #expect(Installer.route(for: .explainOnly(reason), force: true) == .cannotConnect(reason))
        }
    }

    @Test(".replaceExternal：force=false 回 .needsExternalChoice（需使用者明確選擇），force=true 回 .proceed")
    func replaceExternalNeedsForce() {
        #expect(Installer.route(for: .replaceExternal, force: false) == .needsExternalChoice)
        #expect(Installer.route(for: .replaceExternal, force: true) == .proceed)
    }

    @Test(".none（已接上）一律回 .alreadyConnected，force 不影響——`connect()` 對有效掛載的保護是完全不觸碰")
    func noneAlwaysAlreadyConnected() {
        #expect(Installer.route(for: .none, force: false) == .alreadyConnected)
        #expect(Installer.route(for: .none, force: true) == .alreadyConnected)
    }

    /// 全格覆蓋：對 `InstallAffordanceTests` 同一個定義域（27 格 broken ＋ 3 個頂層 case），
    /// 先算出 `affordance`，再驗 `route(for:force: false)` 與 `.affordance` 的對應關係——
    /// 三種 `ConnectAffordance` case 分別對回哪個 `ConnectRoute`，逐格比對，不漏一格。
    @Test("全格覆蓋：每一種 InstallState 算出的 affordance，route(for:force:) 都對得上表")
    func everyInstallStateRoutesAccordingToItsAffordance() {
        var states: [InstallState] = [.claudeNotFound, .notConnected,
                                       .connected(owner: .thisApp, verified: .verified)]
        for reason in InstallState.Reason.allCases {
            for owner in MountOwner.allCases {
                states.append(.broken(reason, owner: owner))
            }
        }
        for state in states {
            let affordance = state.affordance
            let routeNoForce = Installer.route(for: affordance, force: false)
            let routeForce = Installer.route(for: affordance, force: true)
            switch affordance {
            case .connect:
                #expect(routeNoForce == .proceed, "\(state)：.connect 應 force=false 也 .proceed，實際 \(routeNoForce)")
                #expect(routeForce == .proceed, "\(state)：.connect 應 force=true 也 .proceed，實際 \(routeForce)")
            case .explainOnly(let reason):
                #expect(routeNoForce == .cannotConnect(reason), "\(state) 的 route 對不上 .explainOnly")
                #expect(routeForce == .cannotConnect(reason), "\(state) 的 route（force=true）對不上 .explainOnly")
            case .replaceExternal:
                #expect(routeNoForce == .needsExternalChoice, "\(state)：force=false 應 .needsExternalChoice，實際 \(routeNoForce)")
                #expect(routeForce == .proceed, "\(state)：force=true 應 .proceed，實際 \(routeForce)")
            case .none:
                #expect(routeNoForce == .alreadyConnected, "\(state) 的 route 對不上 .none")
                #expect(routeForce == .alreadyConnected, "\(state) 的 route（force=true）對不上 .none")
            }
        }
    }
}
