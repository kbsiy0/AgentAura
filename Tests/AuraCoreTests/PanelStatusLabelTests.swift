import Testing
import AuraCore
import Foundation

/// T13f（S1-1，D-y，CX50）：`PanelModel.statusLabel(_:)` 是三處狀態字串（標題／footer
/// chip／CTA 窄條 label）的唯一 oracle——這裡守它的**純函式層**（AuraCore）。渲染那一半
/// （footer chip／CTA 窄條真的讀到它）由 App 層的 CX51 守，標題那一處**住在 AuraCore**，
/// 直接在這裡由斷言④守（不必等 App 層 view 才能判斷對不對）。
///
/// 定義域**逐字寫 `InstallStateAllCases.all()`**（test target 既有符號，由
/// `Reason.allCases × MountOwner.allCases` 推導，`Tests/AuraCoreTests/` 已有六處在用）——
/// 不手列「代表值」：手列會漏掉 `broken(reason, owner:)` 的變體，而斷言②正是為那些
/// 變體存在的（r13 review m4）。
@Suite("PanelModel.statusLabel：三處狀態字串的唯一 oracle（CX50）")
struct PanelStatusLabelTests {

    static let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)

    static func model(install: InstallState, codex: CodexState, language: Language) -> PanelModel {
        PanelModel.make(icon: icon, sessions: [], palette: .default,
                        install: install, version: "1.0", optionsExpanded: false,
                        launchAtLogin: nil, externalTargetPath: nil, banner: nil,
                        systemReduceMotion: false, userReduceMotion: false, iconPlate: true,
                        iconShape: .ledStrip, language: language,
                        codex: codex, codexSnippet: nil, codexPathRejection: nil)
    }

    /// `@Test(arguments:)` 最多吃兩個集合做交叉積——三維的域（`install × codexKind ×
    /// language`）先把前兩維程式推導壓成一個 tuple 陣列，再跟 `Language.allCases` 交叉。
    static func installCrossCodexKind(excluding excludedKind: CodexStateKind? = nil) -> [(InstallState, CodexStateKind)] {
        var pairs: [(InstallState, CodexStateKind)] = []
        for install in InstallStateAllCases.all() {
            for kind in CodexStateKind.allCases where kind != excludedKind {
                pairs.append((install, kind))
            }
        }
        return pairs
    }

    /// ①（D-j 零 diff）：`codex != .connected` 時，`statusLabel` 逐位元組等於
    /// `install.healthLabel`——沒裝 Codex／Codex 還沒接上的人，這句話一個位元組都不變。
    @Test("① codex != .connected → statusLabel 逐位元組等於 install.healthLabel",
          arguments: Self.installCrossCodexKind(excluding: .connected), Language.allCases)
    func zeroDiffWhenCodexNotConnected(pair: (InstallState, CodexStateKind), language: Language) {
        let (install, codexKind) = pair
        let codex = CodexState.samples(codexKind).first!
        let model = Self.model(install: install, codex: codex, language: language)
        #expect(model.statusLabel(language) == install.healthLabel(language), """
            codex=\(codexKind) 未接上時，statusLabel 應該逐位元組等於 install.healthLabel，
            實際 statusLabel="\(model.statusLabel(language))"，healthLabel="\(install.healthLabel(language))"
            """)
    }

    /// ②：`codex == .connected` 時，statusLabel 必須含 `Agent.codex.label!`，**且**
    /// `install.healthLabel(l)` 必須是它的逐字子字串——不得弄丟 `broken` 狀態的診斷資訊
    /// （這正是「組合既有 healthLabel」而不是「另寫一套雙 agent 文案」的理由）。
    @Test("② codex == .connected → 含 Agent.codex.label！且 install.healthLabel 是逐字子字串",
          arguments: InstallStateAllCases.all(), Language.allCases)
    func includesCodexLabelAndClaudeHalfWhenConnected(install: InstallState, language: Language) {
        let model = Self.model(install: install, codex: .connected, language: language)
        let label = model.statusLabel(language)
        #expect(label.contains(Agent.codex.label!), "statusLabel 應含 \(Agent.codex.label!)，實際 \(label)")
        #expect(label.contains(install.healthLabel(language)), """
            statusLabel 應該把 install.healthLabel 原封不動當子字串包進去（不得弄丟 broken 的診斷字），
            實際 statusLabel="\(label)"，healthLabel="\(install.healthLabel(language))"
            """)
    }

    /// ③：Codex 子句在最前面——footer chip 是 `lineLimit(1)`／`truncationMode(.tail)`，
    /// 截斷時先犧牲尾巴的版本號，不會犧牲「Codex 已接上」這件剛被 persona 判為 S0 的事。
    @Test("③ codex == .connected 時，Codex 子句在最前面",
          arguments: InstallStateAllCases.all(), Language.allCases)
    func codexClauseComesFirst(install: InstallState, language: Language) {
        let model = Self.model(install: install, codex: .connected, language: language)
        #expect(model.statusLabel(language).hasPrefix(Agent.codex.label!), """
            statusLabel 應該以 \(Agent.codex.label!) 開頭，實際 \(model.statusLabel(language))
            """)
    }

    /// ④（r14 解 M2③／m1）：把三處裡**住在 AuraCore 的標題那一處**下推到純函式層守——
    /// `install` 非 connected 時，`PanelModel.make(...)` 產出的 `title` 必須逐位元組等於
    /// `statusLabel(l)`。view 層的 CX51 因此只需要分辨另外兩處（footer chip／CTA 窄條）。
    static func notConnectedInstallCrossCodexKind() -> [(InstallState, CodexStateKind)] {
        var pairs: [(InstallState, CodexStateKind)] = []
        for install in InstallStateAllCases.all() where !install.isConnected {
            for kind in CodexStateKind.allCases {
                pairs.append((install, kind))
            }
        }
        return pairs
    }

    @Test("④ PanelModel.make 產出的 title 在 install 非 connected 時逐位元組等於 statusLabel",
          arguments: Self.notConnectedInstallCrossCodexKind(), Language.allCases)
    func titleMatchesStatusLabelWhenNotConnected(pair: (InstallState, CodexStateKind), language: Language) {
        let (install, codexKind) = pair
        let codex = CodexState.samples(codexKind).first!
        let model = Self.model(install: install, codex: codex, language: language)
        #expect(model.title == model.statusLabel(language), """
            install 非 connected 時，title 應該逐位元組等於 statusLabel——這是把住在 AuraCore
            的標題那一處下推到純函式層守（CX50④），實際 title="\(model.title)"，
            statusLabel="\(model.statusLabel(language))"
            """)
    }
}
