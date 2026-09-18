import Foundation

/// codex-support T01 必辦②：`~/.codex` 的九種磁碟形狀，供 T04／T06 的
/// `CodexHookPathCheck`／`CodexInstaller` 測試共用（CX14／CX15／CX17／CX19／CX32）。
///
/// 每種形狀（除了 `.absent`／`.codexHomeIsRegularFile`，沒有目錄可放）都植入一份
/// **內容已知**的 `config.toml`（`knownConfigTomlContents`）——D-q／CX14 要斷言
/// 「`config.toml` 位元組完全不變」，必須先知道原始內容才比得出「沒變」。
///
/// 純 Foundation／POSIX，零依賴 `AuraCore`／`AuraHookFile` 的任何型別——這樣即使
/// `CodexInstaller`（T06）還沒寫出來，這個 fixture 也能先存在、先編譯。
enum CodexHomeFixture {
    /// 已知內容的 `config.toml`——事後逐位元組比對用。刻意長得像真的 Codex 設定檔
    /// （F12 的 `[projects."<cwd>"] trust_level` 形狀），不是空字串或隨機亂數。
    static let knownConfigTomlContents = Data(#"""
        [projects."/Users/demo/Code/example-project"]
        trust_level = "trusted"

        """#.utf8)

    struct Layout {
        let root: URL
        let codexHome: URL
        /// 只有 `.codexHomeIsExternalSymlink` 這個形狀才非 nil——`codexHome` 實際落地
        /// 的目的地（在 `root` 之外），CX18 用它斷言 realpath 樹的差異。
        let externalCodexHomeTarget: URL?
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    enum Shape: String, CaseIterable {
        case absent
        case codexHomeIsRegularFile
        case codexHomeIsEmptyDirectory
        case hooksJSONIsRegularFile              // 別人的合法 JSON（occupiedByOther）
        case hooksJSONIsDirectory
        case hooksJSONIsSymlinkToConfigToml      // CX15 最關鍵那一格（r4 M1）
        case hooksJSONIsDanglingSymlink
        case hooksJSONIsGarbageOver64KiB         // > 64 KiB，驗 D-q
        case codexHomeIsExternalSymlink          // 第九種：~/.codex 自己是外指 symlink
    }

    static func make(_ shape: Shape) throws -> Layout {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-codex-fixture-\(shape.rawValue)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let codexHome = root.appendingPathComponent("codexHome")
        let fm = FileManager.default

        switch shape {
        case .absent:
            break   // codexHome 這個路徑什麼都不建

        case .codexHomeIsRegularFile:
            try Data("not a directory".utf8).write(to: codexHome)

        case .codexHomeIsEmptyDirectory:
            try fm.createDirectory(at: codexHome, withIntermediateDirectories: true)
            try seedKnownConfigToml(in: codexHome)

        case .hooksJSONIsRegularFile:
            try fm.createDirectory(at: codexHome, withIntermediateDirectories: true)
            try seedKnownConfigToml(in: codexHome)
            try Data(#"{"someone_elses":"hooks","version":1}"#.utf8)
                .write(to: codexHome.appendingPathComponent("hooks.json"))

        case .hooksJSONIsDirectory:
            try fm.createDirectory(at: codexHome, withIntermediateDirectories: true)
            try seedKnownConfigToml(in: codexHome)
            try fm.createDirectory(at: codexHome.appendingPathComponent("hooks.json"),
                                   withIntermediateDirectories: true)

        case .hooksJSONIsSymlinkToConfigToml:
            try fm.createDirectory(at: codexHome, withIntermediateDirectories: true)
            try seedKnownConfigToml(in: codexHome)
            try fm.createSymbolicLink(at: codexHome.appendingPathComponent("hooks.json"),
                                      withDestinationURL: codexHome.appendingPathComponent("config.toml"))

        case .hooksJSONIsDanglingSymlink:
            try fm.createDirectory(at: codexHome, withIntermediateDirectories: true)
            try seedKnownConfigToml(in: codexHome)
            try fm.createSymbolicLink(
                at: codexHome.appendingPathComponent("hooks.json"),
                withDestinationURL: codexHome.appendingPathComponent("does-not-exist-\(UUID().uuidString)"))

        case .hooksJSONIsGarbageOver64KiB:
            try fm.createDirectory(at: codexHome, withIntermediateDirectories: true)
            try seedKnownConfigToml(in: codexHome)
            // T01b（review m4）：固定 byte 0xEE，128 KiB——遠超過 D-q 的 64 KiB 上限，
            // 足以驗證「> 64 KiB 就不讀」；不必逐 byte 隨機（原本 5 MB 隨機讓自我測試
            // 多花約 3.6 秒，且 T06 之後會反覆用到這個形狀）。0xEE 不是合法 JSON 開頭，
            // 證明這不是我們認得的形狀，跟隨不隨機無關。
            let garbage = Data(repeating: 0xEE, count: 128 * 1024)
            try garbage.write(to: codexHome.appendingPathComponent("hooks.json"))

        case .codexHomeIsExternalSymlink:
            let external = root.appendingPathComponent("external-codex-home")
            try fm.createDirectory(at: external, withIntermediateDirectories: true)
            try seedKnownConfigToml(in: external)
            try fm.createSymbolicLink(at: codexHome, withDestinationURL: external)
            return Layout(root: root, codexHome: codexHome, externalCodexHomeTarget: external)
        }
        return Layout(root: root, codexHome: codexHome, externalCodexHomeTarget: nil)
    }

    static func seedKnownConfigToml(in codexHome: URL) throws {
        try knownConfigTomlContents.write(to: codexHome.appendingPathComponent("config.toml"))
    }
}
