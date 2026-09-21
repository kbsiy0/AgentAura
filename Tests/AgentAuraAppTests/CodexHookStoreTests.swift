import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// CX31：`CodexHookStore.write(_:)` → `.contents` 必須逐位元組相等——round-trip 是獨立的
/// 失敗面（spec §4.5）：`connect()` 回 `Data`、`disconnect(ifContentsEqual:)` 比對 `Data`，
/// 中間經過 `CodexHookStore` 的一個文字鍵。任何編碼不對等 → `disconnect` 永遠比不中 →
/// `.notOurs` → 永遠刪不掉自己寫的檔 → 完整移除留殘留（`verify-uninstall.sh` 第 7 項 FAIL）。
///
/// **輸入用真正的產生器輸出**（`CodexHooksJSON.json(hookBinaryPath:)`），不是 `"{}"`——
/// 生產路徑餵進 `write(_:)` 的一律是這個產生器的輸出，含真實 JSON 的引號／跳脫序列，
/// 那才是可能踩到編碼問題的形狀。
@MainActor
@Suite("CodexHookStore round-trip（CX31）")
struct CodexHookStoreTests {

    func freshDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suite = "io.agentaura.tests.codexhookstore.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test("write(_:) 之後 contents 與真正的產生器輸出逐位元組相等")
    func codexHookStoreRoundTripsBytes() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CodexHookStore(defaults: defaults)
        #expect(store.contents == nil, "尚未 write 過時應為 nil")

        let bytes = CodexHooksJSON.json(hookBinaryPath: "/Applications/AgentAura.app/Contents/Resources/plugin/bin/aura-hook")
        store.write(bytes)
        #expect(store.contents == bytes, "write(_:) 之後 contents 應與寫入的位元組逐位元組相等")

        store.clear()
        #expect(store.contents == nil, "clear() 之後 contents 應回到 nil")
    }

    /// 對抗式路徑（同 CX6③ 的理由）：`hookBinaryPath` 含空白／引號／反斜線時，產生器輸出
    /// 帶跳脫序列——round-trip 仍必須逐位元組相等，不能只在乾淨路徑上驗過。
    @Test("write(_:) 對含特殊字元路徑的產生器輸出仍逐位元組相等",
          arguments: ["/Applications/Agent Aura.app/aura-hook",
                      "/Applications/Agent\"Aura.app/aura-hook",
                      "/Applications/Agent\\Aura.app/aura-hook"])
    func codexHookStoreRoundTripsAdversarialPaths(_ path: String) throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CodexHookStore(defaults: defaults)
        let bytes = CodexHooksJSON.json(hookBinaryPath: path)
        store.write(bytes)
        #expect(store.contents == bytes, "含特殊字元路徑的產生器輸出，round-trip 仍應逐位元組相等")
    }

    /// **`CodexHooksJSON.json` 目前的輸出永遠不含開頭／結尾空白**（`JSONSerialization`
    /// 不加）——只餵乾淨的產生器輸出測不出「`write` 裡偷加了一個字串正規化」這整族 bug
    /// （例如 `.trimmingCharacters(in:)`）：對這份輸入，trim 是全等的 no-op，測試在那個
    /// mutation 下也會照樣綠。這裡額外附加開頭／結尾空白位元組，模擬「future 生產者可能
    /// 產生帶空白的內容」的邊界情境——`CodexHookStore` 的契約是「存什麼、還什麼」，不該
    /// 預設自己知道「多的空白」不重要。
    @Test("write(_:) 對帶開頭／結尾空白的位元組仍逐位元組相等（不做任何正規化）")
    func codexHookStoreDoesNotTrimBoundaryWhitespace() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CodexHookStore(defaults: defaults)
        let generated = CodexHooksJSON.json(hookBinaryPath: "/Applications/AgentAura.app/aura-hook")
        let bytes = Data(" \n".utf8) + generated + Data(" \n".utf8)
        store.write(bytes)
        #expect(store.contents == bytes, "write(_:) 不得對輸入做任何正規化——開頭／結尾空白必須原封不動保留")
    }
}
