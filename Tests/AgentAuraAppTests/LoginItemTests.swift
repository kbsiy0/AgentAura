import Testing
import Foundation
import ServiceManagement
@testable import AgentAuraApp

/// spec §4.2：`LoginItem`（`SMAppService.mainApp` 包一層）。三種失敗都要處理：
/// `register()` throw（開關彈回實際值）、`.requiresApproval`（指引系統設定）、
/// translocated／`~/Downloads`（拒絕註冊，D-f／S1-S3）。**不真的呼叫 `SMAppService.register()`**
/// （spec §6.4）——`AppServiceRegistering` 是唯一让 `LoginItem` 可測的縫，`FakeAppService`
/// 全程留在記憶體，型別上不可能碰到真的系統登入項目。
@MainActor
final class FakeAppService: AppServiceRegistering {
    var status: SMAppService.Status
    var registerBehavior: RegisterBehavior
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    enum RegisterBehavior {
        case succeeds(resultingStatus: SMAppService.Status)
        case throwsError
    }

    init(status: SMAppService.Status = .notRegistered, registerBehavior: RegisterBehavior = .succeeds(resultingStatus: .enabled)) {
        self.status = status
        self.registerBehavior = registerBehavior
    }

    func register() throws {
        registerCallCount += 1
        switch registerBehavior {
        case .succeeds(let resultingStatus):
            status = resultingStatus
        case .throwsError:
            throw NSError(domain: "FakeAppServiceError", code: 1)
        }
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}

@Suite("LoginItem")
struct LoginItemTests {

    @MainActor
    @Test("非 bundle 執行（runningFromBundle=false）→ isSupported=false")
    func notSupportedWhenNotRunningFromBundle() {
        let item = LoginItem(service: FakeAppService(), translocated: false, inDownloads: false, runningFromBundle: false)
        #expect(item.isSupported == false, "swift test／swift run 下應不支援——UI 隱藏該列")
    }

    @MainActor
    @Test("translocated → isSupported=false")
    func notSupportedWhenTranslocated() {
        let item = LoginItem(service: FakeAppService(), translocated: true, inDownloads: false, runningFromBundle: true)
        #expect(item.isSupported == false)
    }

    @MainActor
    @Test("bundle 執行、非 translocated → isSupported=true")
    func supportedWhenRunningFromBundleAndNotTranslocated() {
        let item = LoginItem(service: FakeAppService(), translocated: false, inDownloads: false, runningFromBundle: true)
        #expect(item.isSupported == true)
    }

    @MainActor
    @Test("isEnabled 每次都讀 service.status 的即時值，不自己記")
    func isEnabledAlwaysReflectsLiveStatus() {
        let service = FakeAppService(status: .notRegistered)
        let item = LoginItem(service: service, translocated: false, inDownloads: false, runningFromBundle: true)
        #expect(item.isEnabled == false)
        service.status = .enabled
        #expect(item.isEnabled == true, "isEnabled 應每次重讀 service.status，而不是快取建構時的值")
    }

    @MainActor
    @Test("set(true) 成功 → 呼叫 register()，不 throw")
    func setTrueCallsRegister() throws {
        let service = FakeAppService(registerBehavior: .succeeds(resultingStatus: .enabled))
        let item = LoginItem(service: service, translocated: false, inDownloads: false, runningFromBundle: true)
        try item.set(true)
        #expect(service.registerCallCount == 1)
        #expect(item.isEnabled == true)
    }

    @MainActor
    @Test("set(false) → 呼叫 unregister()")
    func setFalseCallsUnregister() throws {
        let service = FakeAppService(status: .enabled)
        let item = LoginItem(service: service, translocated: false, inDownloads: false, runningFromBundle: true)
        try item.set(false)
        #expect(service.unregisterCallCount == 1)
        #expect(item.isEnabled == false)
    }

    @MainActor
    @Test("register() 丟錯 → 原樣往外丟，isEnabled 維持系統實際值（開關彈回）")
    func registerThrowPropagatesAndStatusReflectsReality() {
        let service = FakeAppService(status: .notRegistered, registerBehavior: .throwsError)
        let item = LoginItem(service: service, translocated: false, inDownloads: false, runningFromBundle: true)
        #expect(throws: (any Error).self) {
            try item.set(true)
        }
        #expect(item.isEnabled == false, "register 丟錯，開關應彈回實際值（未啟用），不能靜默顯示已開")
    }

    @MainActor
    @Test(".requiresApproval：register 成功但狀態變成需核准 → set 丟 LoginItemError.requiresApproval")
    func requiresApprovalThrowsDedicatedError() {
        let service = FakeAppService(registerBehavior: .succeeds(resultingStatus: .requiresApproval))
        let item = LoginItem(service: service, translocated: false, inDownloads: false, runningFromBundle: true)
        #expect(throws: LoginItemError.requiresApproval) {
            try item.set(true)
        }
        #expect(service.registerCallCount == 1, "即使之後要丟 .requiresApproval，register() 仍應真的被呼叫過一次")
    }

    @MainActor
    @Test("inDownloads=true → set(true) 拒絕註冊，且 register() 完全不被呼叫（D-f／S1-S3）")
    func inDownloadsRejectsWithoutCallingRegister() {
        let service = FakeAppService()
        let item = LoginItem(service: service, translocated: false, inDownloads: true, runningFromBundle: true)
        #expect(throws: LoginItemError.mustMoveToApplications) {
            try item.set(true)
        }
        #expect(service.registerCallCount == 0, """
            人在 ~/Downloads 時必須在呼叫 SMAppService 之前就拒絕——否則會註冊一個必壞的登入項目，
            臨時掛載消失後登入項目跟著壞（S1-S3）
            """)
    }

    @MainActor
    @Test("inDownloads=true 但 set(false)（取消登入項目）不受影響，仍呼叫 unregister")
    func inDownloadsDoesNotBlockUnregistering() throws {
        let service = FakeAppService(status: .enabled)
        let item = LoginItem(service: service, translocated: false, inDownloads: true, runningFromBundle: true)
        try item.set(false)
        #expect(service.unregisterCallCount == 1, "取消登入項目不該被 Downloads 的保護卡住——那條保護只防止建立新的必壞項目")
    }

    @MainActor
    @Test("isSupported=false 時 set 一律拒絕，且不呼叫 service（防禦第二層——UI 已隱藏該列）")
    func setRejectsWhenNotSupported() {
        let service = FakeAppService()
        let item = LoginItem(service: service, translocated: true, inDownloads: false, runningFromBundle: true)
        #expect(throws: LoginItemError.mustMoveToApplications) {
            try item.set(true)
        }
        #expect(service.registerCallCount == 0)
        #expect(service.unregisterCallCount == 0)
    }
}
