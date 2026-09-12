import Testing
import Foundation

/// `panelModelMakeHasNoDefaults`（G13，spec §3.3／§6.3，來源推導）：`PanelModel.swift` 的
/// `make(` 簽章除 `now:` 外不得出現預設值——忘了傳要是編譯錯，不是靜默畫「已接上」
/// （`install` 沒有一個安全的預設狀態，S1-Q10.3c）。
@Suite("panelModelMakeHasNoDefaults（G13）")
struct PanelModelMakeDefaultsTests {

    @Test("PanelModel.swift 的 make( 簽章除 now: 外沒有任何參數帶預設值")
    func productionSignatureHasNoDefaultsExceptNow() throws {
        let url = Gate.repoRoot().appendingPathComponent("Sources/AuraCore/PanelModel.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let violations = try PanelModelMakeSignatureScan.defaultedParameters(in: text)
        #expect(violations.isEmpty, "以下參數不該有預設值（只有 now: 例外）：\(violations)")
    }

    @Test("正向對照：probe 裡 install 帶預設值會被抓到，且 now: 不會被誤判")
    func scanCatchesRealDefaultValue() throws {
        let probe = """
            public struct PanelModel {
                public static func make(icon: IconState, install: InstallState = .notConnected,
                                        now: Date = Date()) -> PanelModel { fatalError() }
            }
            """
        let violations = try PanelModelMakeSignatureScan.defaultedParameters(in: probe)
        #expect(violations.contains { $0.hasPrefix("install") }, "掃描沒抓到 probe 裡 install 的預設值，實際 \(violations)")
        #expect(!violations.contains { $0.hasPrefix("now") }, "now: 是允許的例外，不該被列為違規")
    }

    @Test("負對照：probe 裡除 now 外都沒有預設值時掃描回空")
    func scanIsCleanWhenNoDefaultsExceptNow() throws {
        let probe = """
            public struct PanelModel {
                public static func make(icon: IconState, install: InstallState,
                                        now: Date = Date()) -> PanelModel { fatalError() }
            }
            """
        let violations = try PanelModelMakeSignatureScan.defaultedParameters(in: probe)
        #expect(violations.isEmpty, "沒有違規的簽章卻被掃出違規：\(violations)")
    }
}
