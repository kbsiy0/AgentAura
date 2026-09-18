import Foundation

/// codex-support T01 佔位：`FakeCodexStore`（spec §6.1(6)、§8.1 file layout：
/// `Tests/AgentAuraAppTests/Support/FakeCodexStore`）——`CodexHookStore`（T10）的
/// 記憶體替身。可設定「寫進去與讀回來不一致」，模擬 round-trip 壞掉的對抗情境
/// （CX31 的鄰居）。純 `Data` 進、`Data` 出，不依賴任何 Codex 專屬型別——T10 之前
/// 就能編譯、能用。
final class FakeCodexStore {
    private(set) var contents: Data?

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

    func clear() {
        clearCallCount += 1
        contents = nil
    }
}
