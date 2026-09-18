import Foundation

/// codex-support T01 佔位：`FakeCodexStore`（spec §6.1(6)、§8.1 file layout：
/// `Tests/AgentAuraAppTests/Support/FakeCodexStore`）——`CodexHookStore`（T10）的
/// 記憶體替身。可設定「寫進去與讀回來不一致」，模擬 round-trip 壞掉的對抗情境
/// （CX31 的鄰居）。純 `Data` 進、`Data` 出，不依賴任何 Codex 專屬型別——T10 之前
/// 就能編譯、能用。
///
/// **T01b（review m2）**：原始內容故意不公開成 `contents` 屬性——一條寫
/// `store.contents == written` 的測試會完全繞過 `corruptOnRead`，看不到這個對抗式
/// double 想咬的東西（CX24 第③段「憑證位元組往返」正是最該被它咬到的地方）。
/// 要看讀出來的值一律呼叫 `read()`；真的需要看原始寫入值（例如驗證 `corruptOnRead`
/// 本身有沒有生效）才呼叫 `rawContentsForAssertion()`，讓「繞過」變成一個看得見的動作。
final class FakeCodexStore {
    private var contents: Data?

    /// 非 nil 時，`read()` 回傳這個轉換之後的結果而不是原始寫入值——
    /// 模擬「寫進去的位元組與讀回來的位元組不一致」（例如編碼往返失真）。
    var corruptOnRead: ((Data) -> Data)?

    private(set) var writeCallCount = 0
    private(set) var clearCallCount = 0

    init(contents: Data? = nil) { self.contents = contents }

    func write(_ bytes: Data) {
        writeCallCount += 1
        contents = bytes
    }

    func read() -> Data? {
        guard let c = contents else { return nil }
        return corruptOnRead?(c) ?? c
    }

    /// 只給「刻意要繞過 `corruptOnRead` 看原始值」的測試用——名字本身就是警告標籤。
    func rawContentsForAssertion() -> Data? { contents }

    func clear() {
        clearCallCount += 1
        contents = nil
    }
}
