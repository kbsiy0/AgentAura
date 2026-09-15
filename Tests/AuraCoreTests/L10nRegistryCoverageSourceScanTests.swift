import Testing
import Foundation

/// D-5(2)(3) 兩條 gate 都是從 `L10nRegistry.allEntries` 推導——如果 T27／T28 加了一個新
/// domain enum（例如 `L10nOptionsMenu` 之外再加一個 `L10nAbout`）卻忘了登記進
/// `L10nRegistry`，那兩條 gate 會對新 key 視而不見（registry 沒有它、entries 裡也就
/// 不會出現它），等於悄悄失效。這條 gate 反過來驗證：磁碟上每一個 domain enum 檔案
/// 宣告的型別名，都必須出現在 `L10nRegistry.swift` 的原始碼裡。
@Suite("D-5：L10nRegistry 沒有漏掉磁碟上的 domain 字串表")
struct L10nRegistryCoverageSourceScanTests {

    /// 找 `public enum L10n\w+` 宣告——排除 `L10nCatalog`（protocol，不是 domain enum）與
    /// `L10nRegistry` 自己。
    static func declaredDomainEnumNames(in text: String) -> [String] {
        var names: [String] = []
        let lines = text.split(separator: "\n")
        for line in lines {
            guard let range = line.range(of: "public enum L10n") else { continue }
            let afterPrefix = line[range.upperBound...]
            let name = "L10n" + afterPrefix.prefix { $0.isLetter || $0.isNumber }
            guard name != "L10nCatalog", name != "L10nRegistry" else { continue }
            names.append(name)
        }
        return names
    }

    static func domainEnumFiles(under directory: URL) throws -> [URL] {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(directory.path)")
        }
        return e.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "swift" && $0.lastPathComponent.hasPrefix("L10n")
                && $0.lastPathComponent != "L10nCatalog.swift" && $0.lastPathComponent != "L10nRegistry.swift"
        }
    }

    @Test("Sources/AuraCore/L10n*.swift 每個 domain enum 名稱都出現在 L10nRegistry.swift 裡")
    func everyDomainFileIsRegistered() throws {
        let dir = Gate.repoRoot().appendingPathComponent("Sources/AuraCore")
        let files = try Self.domainEnumFiles(under: dir)
        #expect(files.count >= 2, "只掃到 \(files.count) 個 domain enum 檔 —— gate 不能空跑")

        var declared: Set<String> = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            declared.formUnion(Self.declaredDomainEnumNames(in: text))
        }
        #expect(!declared.isEmpty, "掃不到任何 `public enum L10n...` 宣告 —— 解析壞了會讓這條 gate 空轉")

        let registryText = try String(
            contentsOf: dir.appendingPathComponent("L10nRegistry.swift"), encoding: .utf8)
        let missing = declared.filter { !registryText.contains($0) }
        #expect(missing.isEmpty, """
            以下 domain enum 沒有登記進 L10nRegistry.swift：\(missing.sorted())——
            D-5(2)(3) 兩條 gate 會對這些鍵視而不見
            """)
    }

    @Test("正向對照：解析函式抓得到真的宣告")
    func parserCatchesRealDeclaration() {
        let text = "public enum L10nFakeDomain: L10nCatalog {\n    case x\n}\n"
        #expect(Self.declaredDomainEnumNames(in: text) == ["L10nFakeDomain"])
    }

    @Test("負對照：L10nCatalog／L10nRegistry 自己不算 domain enum")
    func parserExcludesInfrastructureTypes() {
        #expect(Self.declaredDomainEnumNames(in: "public enum L10nCatalog {}\n").isEmpty)
        #expect(Self.declaredDomainEnumNames(in: "public enum L10nRegistry {}\n").isEmpty)
    }
}
