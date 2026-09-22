import AppKit
import AuraCore
import AuraHookFile

/// T10：把 T07 的三個 stub 換成真接線，見 spec §4.5／§4.6／§4.8。
///
/// `AppDelegate.swift` 的 200 行上限放不下這一整套——**stored property 不能放進
/// extension**，所以真正需要落在 `AppDelegate` 本體的只有一個：`codexRuntime`。
/// 其餘（協定、依賴注入縫、五個行程常數的計算）全部收攏進這裡的
/// `CodexInstalling`／`CodexDependencies`／`CodexRuntime` 三個型別，`AppDelegate.init`
/// 只呼叫、不定義。

/// `CodexInstaller`（生產）與 `FakeCodexInstaller`（測試）共同遵守的介面——同
/// `LoginItemControlling`／`AppTerminating` 的既有分工，讓 composition root 能注入替身。
/// **簽章必須逐字對齊 `CodexInstaller`**（T06 已落地，不是暫定）：`probe()` 不 throw
/// （回 `CodexObservation`，真實實作對檔案系統的失敗一律吞成 `.absent` 形狀，同
/// `LinkObservation` 的既有分工），`disconnect(ifContentsEqual:)` 吃 `Data?`（`nil` → 一律
/// 視為「認不得」，見 `CodexInstaller.disconnect` 的既有理由）。
protocol CodexInstalling {
    func probe() -> CodexObservation
    @discardableResult
    func connect(json: Data, translocated: Bool, inDownloads: Bool) throws -> Data
    func disconnect(ifContentsEqual: Data?) throws
}

extension CodexInstaller: CodexInstalling {}

/// `AppDelegate.init` 唯一新增的參數（D-t 的注入縫）。**生產預設值全部是純觀測**——
/// 不猜、不近似：`installer` 是真 `CodexInstaller`，`translocated`／`inDownloads` 是
/// `RunningBundle` 對 `Bundle.main.bundleURL` 現場量出來的值，`writeToPasteboard` 是真的
/// `NSPasteboard`。測試注入 `FakeCodexInstaller`／固定布林／spy 閉包。
///
/// **review m8**：`hookBinaryPath` 併入這個注入袋（原本是 `CodexRuntime.init` 另外吃的
/// 參數，永遠讀 `AppDelegate.productionHookBinaryPath()`，測試沒有注入縫）。**無預設值**
/// （`AppDelegate.productionHookBinaryPath()` 是 `@MainActor` 方法，不能當 struct 屬性
/// 的預設值運算式——同一個「不用預設值」的紀律這裡也適用）：讓編譯器帶路更新每個
/// `CodexDependencies(...)` 建構點，CX40 App 半的乘積表因此能補回第三欄
/// （`.unsupportedCharacter`）：注入一個含不支援字元的 `hookBinaryPath` 即可。
struct CodexDependencies {
    let installer: any CodexInstalling
    let translocated: Bool
    let inDownloads: Bool
    let writeToPasteboard: @MainActor (String) -> Void
    let hookBinaryPath: String

    @MainActor
    static func production() -> CodexDependencies {
        CodexDependencies(
            installer: CodexInstaller.production(),
            translocated: RunningBundle.isTranslocated(),
            inDownloads: RunningBundle.isInDownloads(),
            writeToPasteboard: { text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            },
            hookBinaryPath: AppDelegate.productionHookBinaryPath())
    }
}

/// D-t：`translocated`／`inDownloads`／`pathRejection`／`currentExpectedContents`／
/// `codexSnippet` 五者都是 `Bundle.main.bundleURL` 的純函式，在 `AppDelegate.init`
/// 算**一次**存成欄位——`reprobeCodex()` 只重算 `codexState` 那一段（檔案系統 I/O），
/// 不會在每次 `onOpen` 都重跑 `SecTranslocateIsTranslocatedURL` ＋ 兩次
/// `resolvingSymlinksInPath` ＋ 產 12 個事件的 JSON。
///
/// **review m7**：直接持有 `dependencies`，不重複宣告 `installer`／`translocated`／
/// `inDownloads`／`writeToPasteboard` 四個欄位（省約 12 行）——讀取端改走下面四個
/// computed property，呼叫端逐字不變（`codexRuntime.installer` 等）。
struct CodexRuntime {
    let dependencies: CodexDependencies
    let store: CodexHookStore
    let pathRejection: CodexHookPathCheck.Rejection?
    let currentExpectedContents: Data
    /// R-10：穿過路徑判定的 snippet——`CodexHooksJSON.withheldSnippet(...)` 是唯一來源，
    /// 這裡不重算一次同樣的三元判斷（CX40 守的正是那個判斷本身）。
    let codexSnippet: String?
    /// 唯一的可變欄位——`reprobeCodex()` 的四個時機各自重新算它。
    var codexState: CodexState = .unavailable

    var installer: any CodexInstalling { dependencies.installer }
    var translocated: Bool { dependencies.translocated }
    var inDownloads: Bool { dependencies.inDownloads }
    var writeToPasteboard: @MainActor (String) -> Void { dependencies.writeToPasteboard }

    init(dependencies: CodexDependencies, store: CodexHookStore) {
        self.dependencies = dependencies
        self.store = store
        let rejection = CodexHookPathCheck.rejection(
            translocated: dependencies.translocated, inDownloads: dependencies.inDownloads,
            hookBinaryPath: dependencies.hookBinaryPath)
        pathRejection = rejection
        currentExpectedContents = CodexHooksJSON.json(hookBinaryPath: dependencies.hookBinaryPath)
        codexSnippet = CodexHooksJSON.withheldSnippet(hookBinaryPath: dependencies.hookBinaryPath, pathRejection: rejection)
    }
}

extension AppDelegate {
    /// F9：Codex 沒有 `CLAUDE_PLUGIN_ROOT` 這類環境變數可用，`command` 必須是完整絕對路徑——
    /// `scripts/build-app.sh` 把 `plugin/bin/aura-hook` 複製進
    /// `Contents/Resources/plugin/bin/aura-hook`（同一顆二進位，Claude 側走 symlink、
    /// Codex 側走這個 bundle 內路徑，R-8：兩側各自的安裝物件不重疊）。
    static func productionHookBinaryPath() -> String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/plugin/bin/aura-hook").path
    }

    /// **只重做檔案系統那一段**（D-t）：`installer.probe()` → `CodexState.from(...)`。
    /// **四個時機**（漏接的症狀是「裝了 Codex、開面板、什麼都沒有，重開才出現」，CX24⑤）：
    /// ① launch 同步區、第一次 `refreshPanel()` 之前 ② popover `onOpen`
    /// ③ `performConnectCodex()` 之後 ④ `performDisconnectCodex()` 之後。
    func reprobeCodex() {
        let obs = codexRuntime.installer.probe()
        codexRuntime.codexState = CodexState.from(
            obs, recordedContents: codexRuntime.store.contents,
            currentExpectedContents: codexRuntime.currentExpectedContents,
            pathRejection: codexRuntime.pathRejection)
    }

    /// **第一行是 R-9 guard，在任何 `disconnect` 之前 return**：r3 的順序在 translocated 下
    /// 會先 `disconnect` 成功（內容確實相符）→ 檔案被刪 → `connect` 才撞上執行層 guard，
    /// 淨結果是使用者只是打開了一次 DMG 副本、他那份還在運作的 hook 就沒了（CX39 守）。
    func performConnectCodex() {
        guard let pathRejection = codexRuntime.pathRejection else {
            performConnectCodexUnblocked()
            return
        }
        banner = .error(L10nCodex.failureMessage(CodexFailure(rejection: pathRejection), language: language))
        refreshPanel()
    }

    /// 前提已由 `performConnectCodex()` 確認 `pathRejection == nil`（CX35）：`.connectedStalePath`
    /// 先 best-effort disconnect 掉舊憑證再 connect，其餘狀態直接 connect。
    private func performConnectCodexUnblocked() {
        if codexRuntime.codexState == .connectedStalePath {
            try? codexRuntime.installer.disconnect(ifContentsEqual: codexRuntime.store.contents)
        }
        do {
            let written = try codexRuntime.installer.connect(
                json: codexRuntime.currentExpectedContents,
                translocated: codexRuntime.translocated, inDownloads: codexRuntime.inDownloads)
            codexRuntime.store.write(written)
            // D-m：必須同時講「下一個 session 起生效」與「Codex 會問你信任」（F5）。
            banner = .codexConnected(language: language)
        } catch let failure as CodexFailure {
            banner = .error(L10nCodex.failureMessage(failure, language: language))
        } catch {
            banner = .error(L10nConfirmationAlerts.connectFailed(underlying: error.localizedDescription, language: language))
        }
        reprobeCodex()
        refreshPanel()
    }

    func performDisconnectCodex() {
        do {
            try codexRuntime.installer.disconnect(ifContentsEqual: codexRuntime.store.contents)
            codexRuntime.store.clear()
            banner = .codexDisconnected(language: language)
        } catch let failure as CodexFailure {
            banner = .error(L10nCodex.failureMessage(failure, language: language))
        } catch {
            banner = .error(L10nConfirmationAlerts.disconnectFailed(underlying: error.localizedDescription, language: language))
        }
        reprobeCodex()
        refreshPanel()
    }

    /// R-10／D-s：`codexSnippet == nil` 時沒有東西可複製——`CodexSectionView` 只在
    /// snippet 非 nil 時才畫出「複製」按鈕，這裡的 guard 是第二道防線，不是唯一防線。
    /// **不設 banner**（T07 review m3）：真實副作用是寫剪貼簿，不是每個副作用都需要文字回饋。
    func performCopyCodexSnippet() {
        guard let snippet = codexRuntime.codexSnippet else { return }
        codexRuntime.writeToPasteboard(snippet)
    }
}
