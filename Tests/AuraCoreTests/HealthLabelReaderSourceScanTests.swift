import Testing
import Foundation

/// T13f（S1-1，D-y，CX52，r14 改名＋補 AuraCore root）：`healthLabelReadersAreTheNamedSet`——
/// `install.healthLabel` 的來源推導半，**兩個 root**：
///
/// ① `Sources/AgentAuraApp/` 底下 `.healthLabel(`（**有前導點**，抓的是讀取點——
/// `x.healthLabel(...)` 這種呼叫式，宣告不在這一層）命中數**恰為 0**——三處狀態字串
/// 全部改讀 `PanelModel.statusLabel(_:)` 之後，App 層不該再有任何直接讀取點。
///
/// ② `Sources/AuraCore/` 底下含有 `healthLabel(`（**無前導點**，才涵蓋宣告處
/// `public func healthLabel(`）的**檔案集合恰等於一個具名清單**：`InstallAffordance.swift`
/// （宣告處）、`TooltipText.swift`、`PanelBanner+InstallerFailure.swift`、
/// `PanelModel+ConnectCTA.swift`（`statusLabel` 唯一讀取點）。**兩格的 pattern 刻意不同**
/// （r15／r14 review n2，2026-09-21 實跑確認）：有點的版本抓不到宣告處本身（`public func
/// healthLabel(` 前面沒有點），若拿它掃 AuraCore 會在集合裡永遠少一個檔而跟具名清單自相矛盾。
///
/// **用具名檔案集合、不用命中數**（review m1）：數字會被無關的增刪推著走，集合不會。
/// `PanelModel.swift` 在 T13f 落地後退出這個集合（`title` 改讀 `statusLabel`，不再直接
/// 呼叫 `healthLabel`），`PanelModel+ConnectCTA.swift` 進來（`statusLabel` 的唯一讀取點）——
/// 集合仍是 4 檔，不是 5 檔。
///
/// **已知假陰性**（同 CX46）：跨行寫法與 block comment 形式的 `healthLabel(` 不會被
/// 這個單行字面掃描抓到——这是本 gate 承認的邊界，不是宣稱涵蓋一切寫法。
///
/// **已知假陽性**（r1 review m1，實測咬過一次）：doc comment／行內註解裡**提到**
/// `healthLabel(` 這個字面（例如用反引號說明「這個函式叫 healthLabel(...)」）也會被
/// 這個單行字面掃描算成命中——寫這份文件時，`L10nCodex+Failures.swift` 的一句 doc comment
/// 提到 `` `install.healthLabel(l)` `` 就讓②格的集合多算了一個檔，逼著把那句話改寫措辭
/// 避開字面。與上面的假陰性是同一枚硬幣的兩面：**這個 gate 掃的是文字，不是語意**。
///
/// **`TooltipText` 刻意不在這條 gate 想「收斂」的三處狀態字串範圍內**（T13f 量測任務的
/// 邊界）：tooltip 是選單列的 hover 文字，不是面板的三處狀態字串，它繼續讀
/// `install.healthLabel` 是刻意的，不是漏掉——它仍然要出現在具名集合裡（它真的呼叫
/// `healthLabel(`），只是「該不該雙 agent 感知」不是這條 gate 要回答的問題。
///
/// **與既有 `NotConnectedViewNoDuplicateHealthLabelSourceScanTests` 的關係**（r1 review m8）：
/// 那條是 app-shell（PR #7）就有的既有 gate，掃的是單一檔案（`NotConnectedView.swift`）
/// 不得直接讀 `model.install.healthLabel`；①格落地後它是①格（App 層命中恰 0）的**真子集**
/// ——不是重複或錯誤，只是兩條 gate 現在守同一件事的不同粒度，日後改①格記得它。
@Suite("healthLabel 讀取點的來源集合（CX52）")
struct HealthLabelReaderSourceScanTests {

    static func swiftFiles(under directory: URL) throws -> [URL] {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(directory.path)")
        }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// r1 review M1：函式名依 spec §6.3 慣例改成 `healthLabelReadersAreTheNamedSet_<條目>`。
    @Test("① Sources/AgentAuraApp/ 內 .healthLabel( 命中數恰為 0")
    func healthLabelReadersAreTheNamedSet_1() throws {
        let root = Gate.repoRoot().appendingPathComponent("Sources/AgentAuraApp")
        let files = try Self.swiftFiles(under: root)
        #expect(files.count >= 15, "Sources/AgentAuraApp 只讀到 \(files.count) 個 .swift —— gate 不能空跑")

        var hits: [(String, Int)] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            let count = text.components(separatedBy: ".healthLabel(").count - 1
            if count > 0 { hits.append((url.lastPathComponent, count)) }
        }
        #expect(hits.isEmpty, """
            Sources/AgentAuraApp/ 內不該再有任何 .healthLabel( 直接讀取點（三處狀態字串
            都該改讀 PanelModel.statusLabel(_:)），實際命中：\(hits)
            """)
    }

    static let expectedAuraCoreReaders: Set<String> = [
        "InstallAffordance.swift", "TooltipText.swift",
        "PanelBanner+InstallerFailure.swift", "PanelModel+ConnectCTA.swift",
    ]

    @Test("② Sources/AuraCore/ 內含 healthLabel( 的檔案集合恰等於具名清單")
    func healthLabelReadersAreTheNamedSet_2() throws {
        let root = Gate.repoRoot().appendingPathComponent("Sources/AuraCore")
        let files = try Self.swiftFiles(under: root)
        #expect(files.count >= 15, "Sources/AuraCore 只讀到 \(files.count) 個 .swift —— gate 不能空跑")

        var actual: Set<String> = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("healthLabel(") { actual.insert(url.lastPathComponent) }
        }
        #expect(actual == Self.expectedAuraCoreReaders, """
            Sources/AuraCore/ 內含 healthLabel( 的檔案集合應該恰等於具名清單，
            實際 \(actual.sorted())，預期 \(Self.expectedAuraCoreReaders.sorted())——
            多出來的檔案代表出現了第四個讀取點而沒人記得改，少掉的代表清單本身過時了
            """)
    }
}
