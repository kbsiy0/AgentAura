import Foundation
import ServiceManagement

/// spec §4.2：`SMAppService` 只暴露這三個成員給 `LoginItem`——讓測試能注入 fake，
/// 不必真的碰 `SMAppService.mainApp`（spec §6.4：「不真的呼叫 `SMAppService.register()`」）。
/// `@MainActor`：`LoginItem` 本身是 `@MainActor`，fake 實作若不隔離到同一個 actor 會撞
/// conformance isolation（`SMAppService` 的成員本就 nonisolated，加了不影響生產路徑）。
@MainActor
protocol AppServiceRegistering {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}
extension SMAppService: AppServiceRegistering {}

@MainActor
protocol LoginItemControlling {
    var isSupported: Bool { get }   // 非 bundle 執行／translocated → false，UI 隱藏該列
    var isEnabled: Bool { get }     // 每次展開 Options 重讀，不自己記
    func set(_ on: Bool) throws
}

enum LoginItemError: Error, Equatable {
    case requiresApproval
    /// D-f／S1-S3：translocated 或位於 `~/Downloads` 時拒絕註冊——否則登入項目指向一個
    /// 會消失的臨時掛載，形成「壞掉→重新接上→再壞」的迴圈。
    case mustMoveToApplications
}

/// 生產實作：包一層 `SMAppService.mainApp`（macOS 13+）。三種失敗都要處理——
/// `register()` throw（開關彈回實際值，`isEnabled` 本就不快取，天然滿足）、
/// `.requiresApproval`（指引到系統設定 → 一般 → 登入項目）、translocated／`~/Downloads`
/// （拒絕註冊）。`translocated` 併入 `isSupported`（整列隱藏）；`~/Downloads` 只在 `set(true)`
/// 時拒絕——單純待在 Downloads（未 translocate）時開關仍看得見，按下去才擋。
@MainActor
final class LoginItem: LoginItemControlling {
    private let service: any AppServiceRegistering
    private let translocated: Bool
    private let inDownloads: Bool
    private let runningFromBundle: Bool

    init(service: any AppServiceRegistering = SMAppService.mainApp,
         translocated: Bool, inDownloads: Bool,
         runningFromBundle: Bool = Bundle.main.bundleIdentifier != nil) {
        self.service = service
        self.translocated = translocated
        self.inDownloads = inDownloads
        self.runningFromBundle = runningFromBundle
    }

    var isSupported: Bool { runningFromBundle && !translocated }

    var isEnabled: Bool { service.status == .enabled }

    func set(_ on: Bool) throws {
        guard isSupported else { throw LoginItemError.mustMoveToApplications }
        guard on else {
            try service.unregister()
            return
        }
        guard !inDownloads else { throw LoginItemError.mustMoveToApplications }
        try service.register()
        if service.status == .requiresApproval {
            throw LoginItemError.requiresApproval
        }
    }
}
