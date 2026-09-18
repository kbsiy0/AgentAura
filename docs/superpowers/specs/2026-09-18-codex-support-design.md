---
change: codex-support
release_target: softlaunch
persona_impact: tier1
persona_impact_reason: 動 Sources/AgentAuraApp/**（面板列標籤、Codex 區塊、Options 新列）與 AuraCore 的 PanelAction／PanelModel／面板文案；「接上 Codex」是使用者第一次見到的第二種安裝動作，而我們**無法偵測 Codex 是否已信任這個 hook**（F5），生效與否完全靠畫面把話講清楚——這是純人類面的風險，不是機器面的
revision: r2（2026-09-18，折入 review r1 的 3B／12M／6m）
---

# Change · `codex-support`：讓同一顆燈也照到 Codex

> 正典 `2026-09-08-agentaura-design.md` 為權威；本 change 對正典的修訂在 §8.2。
> 證據層是 `docs/2026-09-18-codex-hook-probe.md`（**F1–F15**）。**任何關於 Codex 行為的斷言都標了
> F 編號；沒有 F 編號的一律寫成「待驗」，不得當事實用。**
> gate 編號慣例（review r1 M6）：**本 change 新增的 gate 一律 `CX<n>`**；提到**既有** gate 一律寫
> 測試函式名（例如 `installerTouchesOnlyAllowedPaths`），**不寫 `G<n>`**——既有編號屬於別的 change，
> 混用會讓 DoD 的 mutation 帳對錯人。

## 0. 背景與裁決

Codex CLI 0.155.0 讀 `~/.codex/hooks.json`，結構與 Claude Code 相同（F1、F14），事件名有 12 個、
其中 11 個與 Claude Code **同名同形**（F2、F3）。所以這個 change 不是「再做一套」，
是「把既有的那一套多接一條進水管」。

### 0.1 使用者 2026-09-18 拍板（鎖定，不重開）

| # | 決策 |
|---|---|
| L1 | **同一顆 `aura-hook` 二進位**，加 `--agent codex` 參數；預設（無參數）＝ claude。Claude 那側的 `plugin/hooks/hooks.json` **不改**（本 change 對它的 git diff 必須為空） |
| L2 | `SessionSnapshot` 加 `agent` 欄位；面板列顯示「Codex」標籤；**聚合燈不分 agent**，還是一顆 |
| L3 | 事件映射沿用既有 `EventMapping.effect`；新事件 **`Interrupt` → `.setActivity(.idle)`**；`waiting` 來自 `PermissionRequest`（形狀待驗）；**Codex 沒有 `error` 狀態的來源**（F2、F4）——列 known gap，不硬推 |
| L4 | 安裝模型：「接上 Codex」**只在 `~/.codex/` 存在時顯示**；按下去**只在 `~/.codex/hooks.json` 不存在時寫入**（12 個事件、`command` 用 bundle 內 `aura-hook` 的**絕對路徑** ＋ `--agent codex`，F9）；寫入時記下內容（`UserDefaults`，與既有 `AgentAuraHookVerified` 同一層）；斷開**只在內容相符時刪除**。檔案已存在（別人的）→ 不動它，顯示可複製的 snippet。**絕不碰 `~/.codex/config.toml`**。UI 必須明講「Codex 會在下次啟動時問你一次是否信任這個 hook」（F5） |
| L5 | 「完整移除」**必須一併移除我們寫的 `~/.codex/hooks.json`**（內容相符時），讓機器回到從未安裝過的狀態 |
| L6 | 文件（README × 2、INSTALL × 2、`Resources/help-*.html`、SECURITY、CLAUDE.md）都要更新；**英文為主**，中文同步 |

### 0.2 review r1 之後的裁決（主 session 2026-09-18，已鎖定）

| # | 裁決 | 取代 |
|---|---|---|
| R-1 | 產生器**逐字**輸出 F14 已驗證的形狀：`matcher: ""`、`type: "command"`、`command`、`timeout: 5`，最外層 `hooks` 物件；**不加 `async`** | r1 §4.3 省略 `matcher` 的變體（B1／M11） |
| R-2 | **不算 hash**：把寫入的完整內容存進 `UserDefaults`，刪除前逐位元組比對 | r1 的 D-h（SHA-256 ＋ 注入縫）整條作廢（M1） |
| R-3 | `.notConnected` 的 Codex 卡片**一律單行提示＋按鈕**，不依 Claude 的安裝狀態降級 | r1 §4.6／§9／T09 三處互相矛盾的敘述（M7） |

### 0.3 本 change 自行決定的細節（最終報告逐條標示）

| 決定 | 內容 | 理由 |
|---|---|---|
| D-a | 磁碟上的 `agent` 是 **`String?`**（不是 enum），enum 只在 AuraCore 的邊界解析 | `Codable` 對「未知 rawValue 的 enum」是**整包解碼失敗**——未來多一種 agent，舊版 app 讀到的不是「少一個標籤」而是**那個 session 從面板整個消失**。同 `outstandingSubagents` 必須是 Optional 的既有理由（`SessionSnapshot` doc comment） |
| D-b | `Agent` 只有 `claude`／`codex`；未知值與 nil 一律落回 `.claude`，**且 `.claude` 不顯示標籤** | 保守失敗：寧可少一個標籤，不可把 Codex 的列標成 Claude 的；也讓只用 Claude 的人畫面位元不變 |
| D-c | `.claude` **不寫** `agent` 這個 JSON 鍵（`nil` 即 claude） | Claude 路徑的狀態檔位元組與改動前**完全相同**，可被 gate 直接斷言（CX9） |
| D-d | `--agent` 支援 `--agent codex` 與 `--agent=codex` 兩種寫法；未知值／缺值／沒有這個參數一律 `.claude`，**全程靜默、exit 0** | 只支援一種寫法時，手寫成另一種會**靜默標成 claude**——那是「看起來裝好了其實標錯」的溫床。解析失敗不得有任何輸出（正典 Global Constraint） |
| D-e | Codex 的事件集合是**獨立常數** `EventMapping.codexEvents`（12 個，F2），**不併進 `handledEvents`** | `handledEvents` 是 Claude 側 `hooks.json` 跨層一致性 gate 的來源（`PluginWiringTests.registeredEventsMatchHandledEvents` 是**雙向等式**），而 Claude Code 對 hooks.json 是**全有全無**解析：多一個它不認識的 `Interrupt`，整份 hooks 會 `Failed to load`。**這是本 change 最容易踩的接縫**，見 §4.2 |
| D-f | `handledEvents` **不改名**（不改成 `claudeEvents`），只補 doc comment | 三個既有測試檔用字面 `handledEvents` 釘住它；改名等於把既有 gate 的 grep pin 搬家換來零收益 |
| D-g | hooks.json 產生器是**純函式**住 AuraCore（輸入絕對路徑字串，輸出 `Data`），檔案系統操作住 AuraHookFile | `Sources/AuraCore/` 只准 import Foundation（`IsolationTests` 白名單基準） |
| D-h | **（作廢，見 R-2）** 原為「digest 計算住 App 層＋注入縫」。reviewer 實測：`import CommonCrypto` 對 module 基準零影響（只有 `CryptoKit` 會多帶 `CryptoKit`＋`LocalAuthentication`），該裁決的一半前提不成立；而存完整內容本來就是我們真正要的語意 | 留下這一列不刪，是為了讓下一個讀到「為什麼不算 hash」的人看得到來龍去脈 |
| D-i | 寫入用 `open(path, O_CREAT\|O_EXCL\|O_WRONLY\|O_CLOEXEC, 0o644)`，**不是**先 `stat` 再寫 | 「只在不存在時寫」必須是**一個**原子動作。reviewer 實測四種佔用形狀（普通檔／目錄／symlink 指向 `config.toml`／斷鏈 symlink）**一律回 `EEXIST`**（沒有任何一種回 `EISDIR`），且 `config.toml` 位元組不變。兩步寫法在 probe 與 write 之間的窗裡會沿著 symlink 寫到 `config.toml` 去 |
| D-j | `~/.codex` 不存在（或不是目錄）時，面板與 Options **完全沒有任何 Codex 元素** | 沒裝 Codex 的人畫面零 diff；既有的 `OptionsExpandTests`／`FooterPositionStabilityTests` 就是這個保證的守衛（版面數字一動它們就紅） |
| D-k | 新增三個 `PanelAction`：`.connectCodex`／`.disconnectCodex`（Options `.mount` 群組的**條件列**，同 `recheckHook` 的既有形狀）／`.copyCodexSnippet`（進 `nonMenuKinds`，它住在說明區塊、需要 snippet 的脈絡） | `nonMenuKinds` 有一條「恰好等於那四個」的字面集合 gate ——改它是**契約變更**，不是弱化，test-edit scrutiny 逐條列（§6.4） |
| D-l | 「Codex」標籤放在列的**第一行**（`projectName` ＋ `meta` 那個既有 `HStack`），不另起一行 | `SessionsCardSizing` 的 43／59pt 由 `RowHeightDerivationTests` 從真實 view 推導。另起一行會改列高、裁掉唯一那一列——那正是這個 codebase 已經踩過兩次的「凍住的數字」家族（CLAUDE.md gate 哲學 §2） |
| D-m | 接上成功的 banner **必須**同時說「下一個 Codex session 起生效」與「Codex 會問你一次是否信任」 | 沿用 D-m 既有教訓（不得寫「立即生效」，那是 S0-A1 修掉的謊）；F5 讓「已生效」在 Codex 上比在 Claude 上更不可宣稱 |
| D-n | 完整移除時，codex disconnect 必須排在 `erasePersistentDomain()` **之前** | 比對用的內容住在 persistent domain 裡，清掉之後我們就認不得自己寫的那個檔了。同既有 D-3（登入項目要在清 defaults 之前處理）的理由 |
| D-o | `verify-uninstall.sh` 第 7 項用**內容判準**（檔案含 `--agent codex`），不是逐位元組 | 腳本跑的時候 persistent domain 已經清空，沒有比對基準可用。需要的語意是「有沒有殘留**我們的**那份」，內容判準剛好足夠 |
| D-p | `~/.codex` 自己是 symlink 時**不拒絕**，但寫入必須落在 `realpath` 底下且差異恰為 `{hooks.json}` | 使用者把 `.codex` 放別的磁碟是合理的；同既有 `ClaudeHomeSkillsSymlinkFixture` 的處理形狀 |
| D-q | `CodexObservation` 只在 `entryType == .regularFile` **且檔案 ≤ 64 KiB** 時才讀內容；超過一律視為 `.occupiedByOther` | 我們產生的檔 ~2 KB；超過 64 KiB 的檔**不可能**是我們寫的，所以不讀它既便宜又等價——不必為了比對而把別人的 5 MB 檔整包吃進記憶體 |

## 1. 目標與範圍

**做**：`--agent` 參數 · Codex 事件集合與 `Interrupt` 映射 · hooks.json 產生器（逐字 F14）·
`CodexInstaller`（probe／connect／disconnect）· `agent` 欄位貫穿 payload → 檔案 → state → UI 四段 ·
面板列標籤 · Codex 區塊與 Options 兩列 · snippet 複製 · 內容憑證 · 完整移除納入 · 文件與正典回寫 · 全鏈接線 gate。

**不做**：Codex 的 `error` 狀態（沒有來源，F2／F4）· 互動 TUI 探針（`PermissionRequest`／`Interrupt`／
`Subagent*` 的形狀、hook 父行程的 `comm` 待驗）· 分 agent 的聚合燈或分頁（L2 鎖定：一顆燈）·
動 `~/.codex/config.toml` · 動 Claude 側 `plugin/hooks/hooks.json` · 自動偵測 Codex 是否已信任（F5：做不到）·
第三種 agent 的擴充機制（YAGNI）。

## 2. 架構總覽

```
Codex CLI ──(12 events, F2)──▶ ~/.codex/hooks.json ──▶ <abs>/aura-hook --agent codex   （形狀逐字照 F14）
                                                              │ stdin: hook JSON (F3)
                                                              ▼
                             AgentArgument.agent(argv) ──▶ Agent(.codex)
                                                              │  getppid()（F15：session 內恆定）
        HookPayload(data:) ──▶ MergeRules.merge(payload, agent:) ──▶ SessionSnapshot(agent: "codex")
                                                              │  ~/.agentaura/sessions/<id>.json
                                                              ▼ （與 Claude 同一個目錄、同一條 FSEvents）
        PipelineGraph ──▶ SessionReducer ──▶ SessionState(agent:) ──▶ PanelRow(agentLabel:) ──▶ PanelRowView

CodexInstaller.probe() ──CodexObservation──▶ CodexState.from(_:recordedContents:) ──▶ PanelModel.codex
   ▲ connect(json) / disconnect(ifContentsEqual:)           │
   └── CodexHooksJSON.json(hookBinaryPath:)                 ├─ .unavailable  → 面板零 Codex 元素（D-j）
       （純函式，事件清單從 codexEvents 推導）               ├─ .notConnected → 單行提示 ＋「接上 Codex」
                                                            ├─ .connected    → 「移除 Codex 掛載」
CodexHookStore（UserDefaults，存完整內容）                   └─ .occupiedByOther → snippet（不提供按鈕）
```

| 單元 | 層 | 狀態 | 職責 |
|---|---|---|---|
| `Agent` | AuraCore | 新（`Agent.swift`） | `enum Agent: String, CaseIterable, Sendable { case claude, codex }`；`storedRawValue`（`.claude` → `nil`，D-c）；`init(stored:)`（nil／未知 → `.claude`，D-b）；`label`（`.claude` → nil） |
| `AgentArgument` | AuraCore | 新（同檔） | `static func agent(from argv: [String]) -> Agent`：純函式，支援兩種寫法，未知一律 `.claude`（D-d） |
| `EventMapping` | AuraCore | 改 | `+ codexEvents`（12 個字面集合，F2）、`+ codexOnlyEvents = ["Interrupt"]`；`effect` 的 switch 加 `case "Interrupt": .setActivity(.idle)`。**`handledEvents` 一個字都不動**（D-e／D-f） |
| `CodexHooksJSON` | AuraCore | 新 | `static let agentFlag = "--agent codex"`；`static func json(hookBinaryPath:) -> Data`（逐字 F14）；`static func snippet(hookBinaryPath:) -> String`（同一個產生器的文字形式） |
| `CodexObservation` | AuraCore | 新 | 純資料：`codexHomeIsDirectory`、`entryType`（`absent`／`regularFile`／`directory`／`symlink`／`other`）、`contents: Data?`（D-q）、`displayPath: String?` |
| `CodexState` | AuraCore | 新 | `enum { unavailable, notConnected, connected, occupiedByOther }`（`CaseIterable`，供 gate 推導定義域）；`static func from(_:recordedContents:)` **窮盡 switch**、零 I/O |
| `CodexFailure` | AuraCore | 新 | `Error`：`codexHomeMissing`／`alreadyExists`／`writeFailed(Int32)`／`notOurs`／`unreadable(Int32)`。比照 `InstallerFailure` 住 AuraCore（文案要窮盡推導） |
| `CodexInstaller` | AuraHookFile | 新（獨立檔，**不塞進 `Installer`**） | `Sendable`；欄位**只有兩個 `URL`**（`codexHome`／`hookBinaryURL`，R-2 之後不再有注入縫）；`probe()`／`connect(json:) throws -> Data`（回寫出去的位元組）／`disconnect(ifContentsEqual:) throws`。**只碰 `<codexHome>/hooks.json`** |
| `CodexHookStore` | App | 新 | `@MainActor` ＋ 注入 `UserDefaults`（比照 `HookVerificationStore`）；key `AgentAuraCodexHookContents`（值＝寫出去的 JSON 文字）；`contents`／`write(_:)`／`clear()` |
| `PanelAction` / `PanelActionKind` | AuraCore | 改 | `+ .connectCodex`／`.disconnectCodex`／`.copyCodexSnippet`（含 `kind` 與 `samples`） |
| `OptionsMenuModel` | AuraCore | 改 | `rows(...)` 多吃 `codex: CodexState`；`.mount` 群組在 `.notConnected`／`.connected` 各多一列；`nonMenuKinds` 加 `.copyCodexSnippet` |
| `PanelModel` | AuraCore | 改 | `+ codex: CodexState`、`+ codexSnippet: String?`；`make(...)` 新參數**不給預設值**（既有 `panelModelMakeHasNoDefaults`） |
| `PanelRow` | AuraCore | 改 | `+ agentLabel: String?`（`.claude` → nil，D-b）；由 `PanelViewModel.row` 從 `SessionState.agent` 推導 |
| `SessionSnapshot` / `MergeRules` / `SessionReducer` / `SessionState` | AuraCore | 改 | `agent: String?` 一路帶到 `SessionState.agent: Agent`；`merge(...)` 多一個 `agent:` 參數（**無預設值**） |
| `CodexSectionView` | App | 新 | `.notConnected` **單行提示＋按鈕**（R-3）；`.occupiedByOther` 說明＋可選取 snippet＋「複製」。**不吃 `InstallState`**（R-3 之後沒有條件式降級，不必把 Claude 的安裝狀態耦合進來） |
| `PanelRowView` | App | 改 | 第一行 `HStack` 內加標籤（D-l） |
| `AppDelegate+Codex.swift` | App | 新 | `codexInstaller`／`codexStore`／`codexState` 欄位；`reprobeCodex()`（呼叫時機見 §4.6）／`performConnectCodex()`／`performDisconnectCodex()`／`performCopyCodexSnippet()` |
| `Uninstaller` | App | 改 | `run()` 在 `erasePersistentDomain()` 前多一步 codex disconnect（D-n） |

**設計選擇**
1. **一條資料流，兩個入口**：Codex 與 Claude 共用 `~/.agentaura/sessions/`、共用 `MergeRules`、
   共用聚合。`agent` 只是狀態上多一個顯示層欄位，不是第二條 pipeline。
2. **兩份 hooks.json 各自的來源集合分離**（§4.2）：Claude 那份由 `handledEvents` 推導（既有 gate 不動），
   Codex 那份由 `codexEvents` 推導（新 gate）。兩份都是 source-derived，都沒有手維護的第二份清單。
3. **安裝的保本動作全部在執行層**（`O_EXCL`、`lstat`、逐位元組比對），不靠上層路由先擋——
   同 `Installer.guardWriteTarget()` 的既有理由（S0-1(ii)：只信路由層的話，拿掉執行層的檢查不會有任何測試變紅）。
4. **憑證存的就是它要比的東西**（R-2）：`UserDefaults` 存完整 JSON 文字，刪除前逐位元組比對。
   沒有 digest 這一層間接，也就沒有「digest 算錯／算法換了」這一類失敗模式；
   使用者 `defaults read io.agentaura.app` 看到的是真正寫出去的那份，不是一串 hex。

## 3. 資料模型

```swift
public enum Agent: String, Sendable, Equatable, CaseIterable {
    case claude, codex
    public init(stored: String?)            // nil／未知 → .claude（D-b）
    public var storedRawValue: String?      // .claude → nil（D-c）
    public var label: String?               // .claude → nil；.codex → "Codex"（產品名不進 L10n）
}
public enum AgentArgument { public static func agent(from argv: [String]) -> Agent }

extension EventMapping {
    public static let codexEvents: Set<String>      // 12 個（F2）
    public static let codexOnlyEvents: Set<String>  // ["Interrupt"]
}

public enum CodexHooksJSON {
    public static let agentFlag: String                            // "--agent codex"
    public static func json(hookBinaryPath: String) -> Data        // 逐字 F14
    public static func snippet(hookBinaryPath: String) -> String
}

public struct CodexObservation: Equatable, Sendable {
    public enum EntryType: Equatable, Sendable, CaseIterable { case absent, regularFile, directory, symlink, other }
    public let codexHomeIsDirectory: Bool
    public let entryType: EntryType
    public let contents: Data?          // 只有 regularFile 且 ≤ 64 KiB 才填（D-q）
    public let displayPath: String?
}
public enum CodexState: Equatable, Sendable, CaseIterable {
    case unavailable, notConnected, connected, occupiedByOther
    public static func from(_ o: CodexObservation, recordedContents: Data?) -> CodexState
}
```

判定表（`CodexState.from`，窮盡、零 I/O）：

| `codexHomeIsDirectory` | `entryType` | `contents` vs `recordedContents` | → |
|---|---|---|---|
| false | 任意 | 任意 | `.unavailable` |
| true | `absent` | 任意 | `.notConnected` |
| true | `regularFile` | 兩者非 nil 且**逐位元組相等** | `.connected` |
| true | `regularFile` | 其餘（任一 nil／不等／超過 64 KiB 沒讀） | `.occupiedByOther` |
| true | `directory`／`symlink`／`other` | 任意 | `.occupiedByOther` |

`SessionSnapshot` 加 `public var agent: String? = nil`（CodingKey `agent`）。**必須是 Optional**——
理由與 `outstandingSubagents` 逐字相同（synthesized `Decodable` 對 Optional 用 `decodeIfPresent`，
缺這個 key 時自然是 nil；換成非 Optional 帶預設值仍會要求 key 存在，舊狀態檔整包解碼失敗）。

`UserDefaults`（domain `io.agentaura.app`）新增**一個** key：`AgentAuraCodexHookContents` = 寫出去的 JSON 文字（~2 KB）。

## 4. 核心技術

### 4.1 `--agent` 參數（D-d）
`aura-hook/main.swift` 現在完全不解析 argv（39 行）。新增一行：
`let agent = AgentArgument.agent(from: CommandLine.arguments)`，往下傳給 `MergeRules.merge`。
解析規則：由左至右找第一個 `--agent`（後接一個值）或 `--agent=<值>`；值與 `Agent.rawValue`
**大小寫敏感**比對；任何不匹配（未知值、`--agent` 在最後一個位置、完全沒有這個參數）一律 `.claude`。
**永不 `exit(非零)`、永不寫 stdout／stderr**（正典 Global Constraint；代價是 exit code 不能當驗收，
驗收看產物——同既有慣例）。

### 4.2 事件集合與 `Interrupt` 接縫（本 change 最容易踩的地方）

事實：
- Claude Code 對 `hooks.json` 是**全有全無**解析——多一個它不認識的事件名，整份 hooks `Failed to load`。
- `PluginWiringTests.registeredEventsMatchHandledEvents` 是 `handledEvents` 與 `plugin/hooks/hooks.json`
  鍵集合的**雙向等式**。
- 所以 **`Interrupt` 一旦進 `handledEvents`**，那條 gate 會要求 Claude 的 hooks.json 也註冊它，
  而那會讓 Claude 側整份 hooks 靜默失效——**一個「把對照表補齊」的善意動作，後果是產品對 Claude 使用者完全停止運作**。

處置：
1. `codexEvents`（12 個）是**獨立常數**，`codexOnlyEvents = ["Interrupt"]`。
2. `Interrupt` 加進 `EventMapping.effect` 的 switch（共用的映射函式），但**不進 `handledEvents`**。
   **前提（不是實測事實，要講清楚）**：F2 只說「Codex 的 12 個事件名與 Claude Code 同名同形」，
   它**沒有**回答「Claude Code 自己認不認得 `Interrupt`」。我們據以行動的是本專案既有的事實——
   `handledEvents` 的 19 個名字裡沒有它、Claude 側 hooks.json 從未註冊過它、
   而 Claude Code 對 hooks.json 是全有全無解析。所以共用 switch 多一個 case 對 Claude 側零影響；
   反過來，把它**註冊進** Claude 的 hooks.json 才是那個會爆的動作。CX5 守的就是「沒有註冊」，
   不需要先回答「Claude 認不認得」這個未量到的問題。
3. **`Interrupt` 事件 ≠ `is_interrupt` 欄位**（review m2）：`HookPayload.isInterrupt` 讀的是
   payload 裡的 `is_interrupt`（使用者 Ctrl+C 中斷了一個 **tool**，刻意不計入 `tool_failures`），
   與 Codex 的 `Interrupt` **事件**（使用者中斷了整輪）語意不同、來源不同、處置不同。
   兩者的 doc comment 都要互相點名，否則下一個人很容易把它們接在一起。
4. 四條 gate 守這個接縫（§6.3 CX2／CX3／CX4／CX5）。其中 **CX4 是 review r1 B2 補上的**：
   `Interrupt → idle` 是本 change 唯一的新映射，而 `round4-codex.ndjson` **零筆 `Interrupt`**
   （實測：只有 `SessionStart` 4／`UserPromptSubmit` 4／`Stop` 4／`SessionEnd` 4／`PreToolUse` 1／
   `PostToolUse` 1），CX1 只驗集合成員、CX3 刻意把 `codexOnlyEvents` 排除在「effect 非 `.noChange`」
   的檢查外——沒有 CX4 的話，**把 `case "Interrupt"` 整行刪掉，全部 gate 維持綠**。
5. Codex 那邊反過來很寬容（F7：不認得的事件名不會讓整份掛掉），所以我們**刻意只給它 12 個**，
   不把 Claude 專屬的 8 個（`PostToolUseFailure`／`PostToolBatch`／`PermissionDenied`／`Elicitation`／
   `ElicitationResult`／`Notification`／`StopFailure`／`PostModelSwitch`）塞進去白付呼叫。

**後果（誠實列出）**：Codex 沒有 `PostToolUseFailure` 也沒有 `StopFailure`（F2），
`tool_response` 只是字串、沒有 exit code（F4）——**Codex 的 session 永遠不會讓燈變紅**。
這是 known gap（§10-2），不用猜測性的啟發式去硬推。

### 4.3 hooks.json 產生器：逐字照 F14（R-1）

F14 是**唯一被 Codex 成功解析並觸發**的那份檔案的逐字形狀。產生器照它輸出，一個鍵不多、一個鍵不少：

```
{
  "hooks": {
    "<event>": [ { "matcher": "", "hooks": [ { "type": "command",
                   "command": "<abs>/aura-hook --agent codex", "timeout": 5 } ] } ],
    ...（12 個，事件名排序）
  }
}
```
- 事件清單從 `codexEvents` 排序推導，**不寫第二份**；CX6 反向解析產出的 JSON 驗鍵集合恰等於它，
  **並且把單一事件的整個 entry 逐字對 F14 比對**（不只驗鍵集合——r1 就是在「只驗鍵集合」的寬鬆度裡
  把 `matcher` 弄丟的）。
- **`matcher: ""` 不可省**：F14 的「未測」欄第一項就是「省略 `matcher` 是否可行」。
  在唯一沒有自動化安全網的地方（Codex 端到端只能靠實機，F12），選未驗證的變體沒有道理。
- **`timeout: 5` 照寫**：這個鍵**是量過的**——F1 把它列在被認得的鍵裡，F13 更是靠 Codex 印出的
  clamping 警告才知道 `SessionEnd`／`Interrupt` 被壓到 3 秒，那個警告的存在本身就證明 Codex 讀了它。
  （r1 寫「`timeout` 未量到」是錯的，review M11 指正。）**代價**：F13 的 clamping 警告會出現在
  使用者的 Codex stderr，見 §10-9。
- **不寫 `async`**：F14 的「未測」欄第二項——Claude 側用的 `"async": true` 在 Codex 上是接受還是拒絕
  未測。代價是每個事件同步等一次 `aura-hook`（實測 ~7 ms，遠小於被 clamp 後的 3 秒）。
- `command` **不加引號**：F14 驗證過的形狀是裸路徑。Claude 側那份加引號是 Claude 的慣例，
  兩份檔互不相干。**路徑含空白時的行為未測**（F14 的樣本路徑無空白，引號是否被支援也未測）→ §10-10。
- `snippet(hookBinaryPath:)` 給 `.occupiedByOther` 複製用，**內容就是 `json(...)` 的文字形式**
  （同一個產生器，不是另外手寫一份示意——否則使用者貼上的跟我們自己寫的會漂移）。

### 4.4 `CodexInstaller`：三個動作
- **`probe()`**：`lstat(codexHome)` 判目錄 → `lstat(hooks.json)` 判 `entryType` →
  只有 `regularFile` **且 ≤ 64 KiB**（D-q）才 `open(..., O_RDONLY | O_NOFOLLOW)` 讀內容。
- **`connect(json:)`**：`open(path, O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC, 0o644)`（D-i）→ 寫入 →
  `close` → 回傳寫出去的 `Data`。`codexHome` 不是目錄時先 throw `.codexHomeMissing`（**不建立它**——
  同「`~/.claude` 不存在時拒絕接上、不得建立它」的既有 invariant）。
  **`EEXIST` → `.alreadyExists`**（review m1 實測：四種佔用形狀**全部**回 `EEXIST`，
  沒有任何一種回 `EISDIR`——別把目錄那格路由到 `.writeFailed(EISDIR)`，UI 會給錯訊息）。
- **`disconnect(ifContentsEqual:)`**：`open(..., O_RDONLY|O_NOFOLLOW)` → `fstat` 確認 `S_IFREG` →
  讀 → **逐位元組比對** → 不符即 throw `.notOurs`（**不刪**）→ 相符才 `unlink`。
  absent 視為已斷開，冪等成功（同 `Installer.disconnect()`）。

**TOCTOU 誠實交代**：POSIX 沒有「內容相符才 unlink」的原子原語（macOS 也沒有 `funlinkat`），
比對與 `unlink` 之間有一個窄窗。兩件事把它縮到最小：① 同一個 fd 讀完立刻比對立刻 unlink，
中間不做別的；② **`unlink` 之前再 `lstat` 一次路徑，比對 `fstat` 拿到的 `(dev, ino)`，不同就放棄**
（review m4；這不關窗，但把「攻擊者換檔後我們刪到別人的」變成需要更精準的時序）。殘餘風險列 §10-6。
寫入那一側**沒有**這個問題（`O_EXCL` 本身就是原子的）。

### 4.5 內容憑證與完整移除（R-2）
- `connect` 成功 → app 層 `CodexHookStore.write(bytes)`（存 JSON 文字）；`disconnect` 成功 → `clear()`。
- `Uninstaller.run()` 的順序變成：`loginItem.set(false)` → `installer.disconnect()` →
  **`codexInstaller.disconnect(ifContentsEqual: store.contents)`（`try?`）** → `StateDirectoryEraser.erase` →
  `erasePersistentDomain()` → `recycleBundleAndTerminate()`。codex 那步**必須在清 domain 之前**（D-n），
  且與其他步驟一樣 best-effort：它失敗不得卡住後面的步驟（Lessons #8）。
- `scripts/verify-uninstall.sh` 第 7 項：`${CODEX_HOME:-$HOME/.codex}/hooks.json` 存在**且**含
  `--agent codex` → FAIL；存在但不含 → PASS（那是別人的檔，本來就不該動）；不存在 → PASS。
  **第 7 項必須可以被單獨執行**（`--only 7`，見 §6.3 CX27 與 §10 的理由）：腳本第 1–6 項查的是**真實**
  `$HOME`，在一台裝著 AgentAura 的開發機上本來就會 FAIL、整支腳本本來就非零退出——
  用「整體 exit code」當判準的 gate 對 mutation 不會紅。

### 4.6 面板與 Options
| 狀態 | 面板 | Options（`.mount` 群組） |
|---|---|---|
| `.unavailable` | **什麼都不畫**（D-j） | 零列 |
| `.notConnected` | **單行提示 ＋ 按鈕**（R-3：一律如此，不看 Claude 的安裝狀態） | 「接上 Codex」 |
| `.connected` | 不畫說明卡（列上有標籤就夠） | 「移除 Codex 掛載…」 |
| `.occupiedByOther` | 說明卡：「你已經有自己的 `~/.codex/hooks.json`，我們不會動它」＋ 可選取的 snippet ＋「複製」 | 零列（沒有安全的一鍵動作可提供） |

**`reprobeCodex()` 的呼叫時機（review M4；沒有這一段，功能會是 tested≠wired）**：
`AppDelegate.refreshPanel()` 是 install 狀態的單一匯集點，它讀的是儲存屬性——`codexState` 同理。
`reprobeCodex()` **必須**在四個時機各呼叫一次：① `applicationDidFinishLaunching` 的同步區
（第一次 `refreshPanel()` **之前**）；② popover `onOpen`（使用者可能在 app 開著的期間才裝 Codex）；
③ `performConnectCodex()` 之後；④ `performDisconnectCodex()` 之後。
`refreshPanel(icon:)` 把 `codex: codexState`、`codexSnippet:` 一併帶進 `PanelModel.make`。
**後果若漏接**：使用者裝了 Codex、開面板、什麼都沒有，重開 app 才出現——而全套測試綠。
CX24 的第五段就是守這個（spy 記 `probe()` 呼叫次數，斷言 `onOpen` 之後 ≥ 1）。

接上成功的 banner（D-m，兩句都要有）：**「已接上 Codex · 下一個 Codex session 起生效；
Codex 啟動時會問你一次是否信任這個 hook，要按同意才會生效。」**（F5：我們偵測不到信任狀態，
所以這句不能省，也不能改寫成「已生效」。）

### 4.7 liveness 與 hook 的父行程（F15；review B3）
`aura-hook` 記的是 `getppid()` 與它的 start time（`main.swift`），`SessionReducer.resolveLiveness`
要求那個 pid 仍活著，否則整列直接 `.ended`。對 Claude Code 這是量過的；對 Codex 由 **F15** 回答：
五個 session、24 筆事件，**每個 session 內所有事件的 `$PPID` 完全相同**（跨 4–6 筆、數秒到數十秒），
不同 session 則不同 → 呼叫 hook 的是一個**與 session 同壽命的長命行程**，不是每個事件開一次的 shell。
**`getppid()` 判活對 Codex 成立。**

殘餘未知（§10-8）：那個 pid 是 `codex` 原生二進位還是 npm 的 node 啟動器（探針沒記 `ps -o comm=`，
互動探針工具包已補）。兩者對判活的結論相同（都隨 session 結束）。

**預寫的 fallback 決策點**（實機 ③ 若發現父行程其實是跨 session 的常駐行程）：
`--agent codex` 時**不寫 pid**（`MergeRules` 收到的 `pid`／`pidStartedAt` 傳 nil），
改由 `SessionEnd` 的 `terminated` 單獨判死。代價是「terminal 被強制關掉、`SessionEnd` 沒來」
那條路徑在 Codex 上失去保護（列已知缺口）。**這條現在不做**，寫下來是為了實機失敗時不必重新設計。

## 5. 錯誤處理

| 情況 | 處理 |
|---|---|
| `--agent` 未知值／缺值／重複 | 落回 `.claude`；靜默、exit 0、零輸出（D-d） |
| 磁碟上 `agent` 是未知字串／非字串／`null` | `Agent(stored:)` 落回 `.claude`；**整包仍解得開**（D-a）；那一列沒有標籤 |
| 舊版狀態檔沒有 `agent` 鍵 | `decodeIfPresent` → nil → `.claude`（CX11） |
| `~/.codex` 不存在／是普通檔／是斷鏈 symlink | `.unavailable`；**不建立它**；面板零 Codex 元素 |
| `~/.codex/hooks.json` 已存在（普通檔／目錄／symlink／斷鏈 symlink） | `connect` 一律 throw `.alreadyExists`（四種形狀都是 `EEXIST`，m1）；**那個路徑（含 symlink 指向的目標）位元組與型別完全不變**（CX15 逐格斷言，含「symlink 指向 `config.toml`」這最惡毒的一格） |
| `hooks.json` 存在但內容對不上（或 > 64 KiB 沒讀） | `.occupiedByOther`；不提供刪除按鈕；`disconnect` 若被呼叫一律 throw `.notOurs` |
| 憑證遺失（使用者清過偏好設定） | `.occupiedByOther`（保守：認不得就不碰）；UI 顯示 snippet 與「這個檔不是我認得的那份」 |
| `connect` 寫入失敗（權限、磁碟滿） | throw `.writeFailed(errno)` → banner 顯示；**不重試、不 fallback 到非原子寫法** |
| 讀 `hooks.json` 失敗（權限） | `.occupiedByOther`（不是 `.notConnected`——讀不到不等於不存在） |
| Codex 未信任 hook（F5） | **偵測不到**。UI 不得宣稱已生效；help／INSTALL 寫明「燈不動的第一件事是檢查 Codex 有沒有問過你信任」 |
| 收尾步驟（codex disconnect）在完整移除中失敗 | `try?` 吞掉，後面的步驟照跑（Lessons #8）；`verify-uninstall.sh` 第 7 項會把殘留說出來 |

## 6. 測試策略

T01 先行（測試＋compile-only stub，零生產碼，禁 `fatalError`）。swift-testing（`import Testing`）。
**測試中絕不跑 `codex exec`**（F12：它會寫 `[projects."<cwd>"] trust_level` 進使用者的 `config.toml`）、
**絕不碰真的 `~/.codex`／`~/.claude`**。

### 6.1 對抗式 double（Lessons #1；T01 必含）
1. **payload**：缺 `permission_mode`／缺 `model`／`tool_response` 是 200 KB 字串／
   `hook_event_name: "Interrupt"` **帶** `agent_id`（形狀待驗，所以要先問「萬一是這樣呢」）／
   `session_id` 是 UUIDv7（`isSafeSessionID` 必須放行）。
2. **argv**：`[]`、`["--agent"]`、`["--agent","gemini"]`、`["--agent","CODEX"]`、`["--agent=codex"]`、
   `["--agent","codex","--agent","claude"]`、`["--agent","codex","--agent"]`。
   **這張 7 格表是 CX7 與 CX8 共用的唯一來源**（review M12：r1 讓真 spawn 只跑 3 格，
   而「exit 0、零輸出」最可能破的正是解析失敗那幾格）。
3. **檔案系統**：`~/.codex/hooks.json` 是**目錄**／是**symlink 指向 `config.toml`**／是斷鏈 symlink／
   是別人的合法 JSON／是 5 MB 的垃圾（> 64 KiB，驗 D-q 不讀它）；`~/.codex` **自己**是 symlink
   指到 codexHome 之外；`~/.codex` 是普通檔；`~/.codex` 不存在。
4. **`FakeCodexStore`**：可設定「寫進去與讀回來不一致」（比照既有 `FakeLoginItem.isEnabled`
   的對抗式形狀）——R-2 之後這個 double 守的是「store 壞掉時我們不會誤刪」，不再是 digest 相關。
5. **`FakeCodexInstaller`**：① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
   ② `disconnect()` 宣稱成功但檔案還在；③ `probe()` 丟錯。

### 6.2 composition-root smoke（spec §5.2 的既有形狀）
- `codexInstallerIsInjected`：真 `AppDelegate` 啟動後 `codexInstaller` 非 nil、`codexStore` 非 nil。
- `productionCodexHomeIsRealHome`：生產預設 `codexHome` == `FileManager.default
  .homeDirectoryForCurrentUser.appendingPathComponent(".codex")`；**外加**來源掃描
  `Sources/` 不得用 `environment["HOME"]` 算它（CLAUDE.md 陷阱：`homeDirectoryForCurrentUser`
  不吃 `$HOME`，用環境變數算會在生產與測試給出不同答案）。
- `codexConnectChainIsWired`：五段（§6.3 CX24）。
- `codexRowsReachTheView`：`.notConnected` 時真的渲出按鈕（像素 > 門檻）；`.unavailable` 時
  面板的 `preferredContentSize` 與零 Codex 狀態**完全相同**。

### 6.3 Gate 表（本 change 新增一律 `CX<n>`；既有 gate 寫測試函式名）

| Gate | 層 | 守什麼 | Mutation（→ 指名測試 ≤60s 變紅） |
|---|---|---|---|
| CX1 `codexEventSetIsPinnedToProbe` | AuraCore | `codexEvents` 恰等於探針 F2 的 12 個字面名。**doc comment 要分標兩種證據強度**（review m5）：`SessionStart`／`UserPromptSubmit`／`PreToolUse`／`PostToolUse`／`Stop`／`SessionEnd` 六個有 `round4-codex.ndjson` 的真實 payload；`PermissionRequest`／`Interrupt`／`SubagentStart`／`SubagentStop`／`PreCompact`／`PostCompact` 六個只有二進位字串 `HookEventsToml` 列舉這一層證據 | 加一個／少一個 |
| **CX2 `interruptNeverEntersHandledEvents`** | AuraCore | `handledEvents.isDisjoint(with: codexOnlyEvents)`；失敗訊息逐字寫「Claude 全有全無」 | 把 `Interrupt` 加進 `handledEvents` |
| CX3 `codexSharedEventsReuseClaudeMapping` | AuraCore | `codexEvents − codexOnlyEvents ⊆ handledEvents`，且每個的 `effect` 非 `.noChange` | 從 `handledEvents` 拿掉 `PreCompact` |
| **CX4 `codexOnlyEventsMapToIdle`** | AuraCore | 定義域**從 `codexOnlyEvents` 推導**（不寫 `"Interrupt"` 字面），逐個斷言 `effect(forEvent:) == .setActivity(.idle)`。**這是 `Interrupt → idle` 唯一的守衛**（fixture 零筆 `Interrupt`，B2） | 刪掉 `case "Interrupt"` 整行 |
| CX5 `claudeHooksJSONHasNoInterrupt` | AuraCore | `plugin/hooks/hooks.json` 不含 `Interrupt`（**獨立於**既有 `registeredEventsMatchHandledEvents` 的第二個觀測點） | 在 Claude hooks.json 加 `Interrupt` |
| **CX6 `codexHooksJSONMatchesF14Verbatim`** | AuraCore | ① `hooks` 鍵集合 == `codexEvents`；② **任取一個事件，它的 entry 逐字等於 F14**（`matcher` ""、`hooks` 陣列、`type`／`command`／`timeout: 5`，且**沒有** `async`）；③ 含空白／`"`／`\` 的路徑產出仍是合法 JSON 且 `command` 解析回原字串 | ① 產生器寫死 11 個事件 ② 拿掉 `matcher` ③ 加上 `async: true` ④ `command` 漏 `--agent codex` |
| CX7 `agentArgumentParsing`（對抗式） | AuraCore | §6.1(2) 的 7 格表逐格 | 未知值改成回 `.codex` |
| CX8 `auraHookStaysSilentForEveryAgentArgument` | E2E（真 spawn） | **同一張 7 格表**，`SpawnGate` 內序列跑：每格 exit 0、stdout 空、stderr 空 | 在解析失敗時 `FileHandle.standardError.write` |
| CX9 `claudeStateFileHasNoAgentKey` | AuraCore | 用 round1／round1b／round2／round3 fixture 跑 merge，序列化後**不含** `agent` 鍵 | `.claude` 也寫 `"claude"` |
| CX10 `codexStateFileCarriesAgent` | E2E（真 spawn） | `--agent codex` 真跑一次 → 檔案含 `"agent":"codex"`，`SessionState.agent == .codex` | `main.swift` 忘了把 agent 傳進 merge |
| CX11 `legacySnapshotWithoutAgentDecodes` | AuraCore | 無 `agent` 鍵的舊 JSON 解得開且 `.claude` | 把 `agent` 改成非 Optional |
| CX12 `unknownAgentFallsBackWithoutFailingDecode` | AuraCore | `"agent":"gemini"` → 整包解得開、`.claude`、無標籤 | 把 `agent` 改成 `Agent?`（enum）讓整包失敗 |
| CX13 `round4FixtureParsesAndMatchesProbeTable` | AuraCore | 18 筆全部 `HookPayload` 非 nil；每筆 `effect` 與探針欄位表一致；`isSafeSessionID` 全過；探針表列的每個欄位至少出現一次 | **`Stop` 改成 `.noChange`**（fixture 有 4 筆，真的踩得到；r1 寫的 `Interrupt` mutation 物理上不可能紅） |
| **CX14 `codexInstallerTouchesOnlyHooksJSON`** | AuraHookFile | `codexHome` 整棵樹前後快照，差異**恰為** `{hooks.json}`；植入的 `config.toml` 位元組完全不變 | connect 順手寫一個 `hooks.json.bak` |
| **CX15 `codexConnectRefusesEveryOccupiedShape`**（對抗式） | AuraHookFile | §6.1(3) 的佔用形狀各 throw `.alreadyExists`，**且該路徑（含 symlink 目標）位元組與型別不變** | 拿掉 `O_EXCL`（symlink→`config.toml` 那格必須紅） |
| CX16 `codexConnectWritesGeneratorBytes` | AuraHookFile | 成功路徑：檔案內容 == `CodexHooksJSON.json(...)` 位元組；回傳值 == 那些位元組 | connect 少寫最後一個 byte |
| CX17 `codexDisconnectOnlyRemovesOurBytes` | AuraHookFile | 逐位元組相符才刪；改一個 byte → 不刪＋throw；`ifContentsEqual` 為 nil → 不刪；`(dev,ino)` 在 unlink 前被換掉 → 不刪（m4） | 拿掉內容比對 |
| CX18 `codexHomeSymlinkWritesInsideResolvedPath` | AuraHookFile | `~/.codex` 是外部 symlink：字面樹不變、`realpath` 樹差異恰為 `{hooks.json}` | 用字面路徑取快照（必須紅） |
| CX19 `codexStateCoversEveryObservationShape` | AuraCore | `CodexState.from` 對 §3 判定表逐格；定義域由 `EntryType.allCases × {contents 三態} × codexHomeIsDirectory` **推導** | 把 `symlink` 併進 `.notConnected` |
| CX20 `codexRowsAppearOnlyWhenAvailable` | AuraCore | **`.unavailable` 與 `.occupiedByOther` 各零列；`.notConnected`／`.connected` 各恰一列**（review m3：r1 的「其餘三態各含預期列」與 §4.6 表格互相矛盾） | `.unavailable` 也給「接上 Codex」 |
| CX21 既有 `optionsRowsCoverEveryAction` ＋ `nonMenuKindsIsExactlyThatLiteralSet` 擴充 | AuraCore | 代表狀態集合加 `CodexState.allCases`；`nonMenuKinds` 字面集合四個 → 五個 | 把 `.connectCodex` 塞進 `nonMenuKinds` |
| CX22 `agentLabelOnlyForNonClaude` | AuraCore ＋ 像素 | model：claude → nil、codex → "Codex"；像素：同一列 claude vs codex `differingPixels > 0` | 標籤對 claude 也給值 |
| **CX23 `codexLabelDoesNotChangeRowHeight`** | App（離屏） | 帶標籤的列高仍是 43／59pt（±0.5），`SessionsCardSizing` 兩個常數對 codex 列同樣成立 | 標籤另起一行 |
| **CX24 `codexConnectChainIsWired`**（smoke） | App | 五段各自獨立失敗訊息：① `.connectCodex` 有接線 ② fake installer 真的收到 `connect` ③ 內容真的進注入的 suite ④ banner 文字含「下一個 session」與「信任」兩個關鍵詞（**從 `L10nCodex` 的鍵推導，不寫死字面**）⑤ **spy 記 `probe()` 次數：`onOpen` 之後 ≥ 1**（M4） | ① `.connectCodex` 分支改 `break` ② banner 只留一句 ③ **拿掉 `onOpen` 裡的 `reprobeCodex()`** |
| CX25 `productionCodexHomeIsRealHome`（smoke ＋ 來源掃描） | App ＋ AuraCore | §6.2 第二條 | 改成 `environment["HOME"]` |
| CX26 `uninstallRemovesCodexBeforeErasingDefaults` | App | Fake 記錄呼叫順序：codex disconnect **早於** `removePersistentDomain` | 兩步對調 |
| CX27 `verifyUninstallScriptDetectsOurCodexHooks` | script | 暫存 `CODEX_HOME` ＋ **`--only 7`**（只跑第 7 項，不碰 `osascript`／`sfltool`）：含 `--agent codex` → **該項那一行是 FAIL**；別人的檔 → 該行 PASS。**判準是那一行，不是整體 exit code**（M9：開發機上第 1–6 項本來就會 FAIL） | 拿掉腳本第 7 項 |
| CX28 `helpDocsCoverCodexRows` | 文件 | 既有 `HelpDocOptionsRowCoverageTests.allRows` 改成**對 `CodexState.allCases` 取聯集**（型別推導，不寫數字），兩個語言各自守 | **只刪掉其中一個標題**（例如只刪「移除 Codex 掛載」）也必須紅（M5） |
| CX29 `securityDocListsEveryPathWeWrite` | 文件 | `README.md`／`SECURITY.md` 必須含 `.codex/hooks.json`（字面來自生產常數，不手抄） | 從 SECURITY.md 刪掉那一行 |
| CX30 `noCodexExecInRepo` | 全 repo | `Tests/`／`scripts/` 不得出現 `codex exec`（＋暫存目錄正向對照） | 在腳本裡加一行 `codex exec` |
| 既有全部 gate | — | 繼續綠（尤其 `registeredEventsMatchHandledEvents`、`fileLengthLimit`、`nonUITargetsLoadNoUIModules`、`noStrayLiteralOutsideAllowlist`、`panelModelMakeHasNoDefaults`、`RowHeightDerivationTests`、`FooterPositionStabilityTests`） | — |

### 6.4 test-edit scrutiny 預告（Lessons #3）
1. `OptionsMenuModelTests.nonMenuKindsIsExactlyThatLiteralSet`：四個 → 五個。
   **這是契約變更不是弱化**——集合仍然是「恰好等於」，只是多了一個有理由的成員（D-k）；
   報告要把改前／改後／理由三欄擺在一起。
   **連帶**：`Sources/AuraCore/OptionsMenuModel.swift` 的 doc comment 逐字寫著「字面集合恰為這四個」
   （review m6）——生產碼註解也要一起改，否則留下一句與程式碼矛盾的話。
2. `PanelModel.make` 新增無預設值參數 → **61 個呼叫點（26 個檔）**全部要加 `codex:`／`codexSnippet:`。
   測試呼叫點一律傳 `.unavailable`／`nil`（＝現況行為），生產呼叫點傳真實狀態。
3. `MergeRules.merge` 新增無預設值 `agent:` → **7 個呼叫點**；測試一律傳 `.claude`。
4. **`OptionsMenuModel.rows` 新增無預設值 `codex:` → 26 個呼叫點（10 個檔）**（review M2：
   r1 漏算了這條 fan-out，而它包含 `L10nProductionCallSitesPassLanguageTests` 這條來源掃描 gate
   與 `HelpDocOptionsRowCoverageTests`）。測試呼叫點一律傳 `.unavailable`。
5. 上面 2／3／4 三批合計 94 個呼叫點：**`#expect` 淨數量不得下降**，報告附改前／改後總數；
   不得有任何既有斷言因為「加了參數」被改成更弱的形式。
6. `HelpDocOptionsRowCoverageTests.allRows` 改成對 `CodexState.allCases` 取聯集（M5）。
7. `ClaudeHomeTreeSnapshot` 的 walk／entry 抽成共用 `DirectoryTreeSnapshot`（CX14 要用同一套機制）——
   **純重構**：既有 `installerTouchesOnlyAllowedPaths` 兩條測試必須全綠，且它的 mutation 要
   **當場重跑一次**確認仍然精準紅。

### 6.5 已知不可測（寫進 §10 與最終報告）
- Codex 是否真的載入並執行我們寫的 hooks.json（要真的跑 Codex，而自動化不准跑 `codex exec`，F12）→ 實機 ②③。
- 信任提示的 UX 與「拒絕信任」的行為（F5 找不到持久化位置）→ 實機 ④。
- `PermissionRequest`／`Interrupt`／`Subagent*` 的實際 payload 形狀（探針只在 `exec` 模式跑過，
  F10：`exec` 強制 `approval: never`，`PermissionRequest` 在那個模式不可能出現）→ 互動探針跑完才升級。
- hook 父行程的 `comm`（F15 未辨識）→ 互動探針清單已補 `ps -o comm= -p $PPID`。

## 7. DoD

門檻與量法見 `docs/superpowers/plans/2026-09-18-codex-support-dod.md`（每條有數字）。

## 8. 檔案佈局與回寫

### 8.1 檔案（估行；`Sources/` 基準 7846 行）
```
Sources/AuraCore/Agent.swift                       新  ~60（Agent ＋ AgentArgument）
Sources/AuraCore/EventMapping.swift                改  +25（codexEvents／codexOnlyEvents／Interrupt case）
Sources/AuraCore/CodexHooksJSON.swift              新  ~75（逐字 F14，每個鍵的出處寫進 doc comment）
Sources/AuraCore/CodexState.swift                  新  ~75（CodexObservation ＋ CodexState ＋ CodexFailure）
Sources/AuraCore/SessionSnapshot.swift             改  +10
Sources/AuraCore/MergeRules.swift                  改  +6
Sources/AuraCore/SessionReducer.swift              改  +2
Sources/AuraCore/SessionState.swift                改  +5
Sources/AuraCore/PanelViewModel.swift              改  +6（PanelRow.agentLabel）
Sources/AuraCore/PanelAction.swift                 改  +25（三個 case × kind × samples）
Sources/AuraCore/OptionsMenuModel.swift            改  +18（含 m6 的註解修正）
Sources/AuraCore/PanelModel.swift                  改  +14
Sources/AuraCore/L10nCodex.swift                   新  ~95（雙語；產品名 "Codex" 不翻）
Sources/AuraHookFile/CodexInstaller.swift          新  ~115（欄位只有兩個 URL，R-2）
Sources/AuraHookFile/CodexInstaller+Probe.swift    新  ~70（撞 200 行就拆這裡）
Sources/aura-hook/main.swift                       改  +3
Sources/AgentAuraApp/CodexHookStore.swift          新  ~40（存內容，不算 hash，R-2）
Sources/AgentAuraApp/CodexSectionView.swift        新  ~90
Sources/AgentAuraApp/AppDelegate+Codex.swift       新  ~95
Sources/AgentAuraApp/AppDelegate+Links.swift       新  ~45（**純搬移**：把 openHelp／helpURL／reportIssue
                                                        從已經 200 行的 AppDelegate+PanelActions.swift 搬出來）
Sources/AgentAuraApp/AppDelegate+PanelActions.swift 改 −45 +8（搬走 ＋ 三個新 case ＋ refreshPanel 帶 codex）
Sources/AgentAuraApp/PanelView.swift               改  +8（列標籤 ＋ 掛 CodexSectionView）
Sources/AgentAuraApp/Uninstaller.swift             改  +8
Sources/AgentAuraApp/AppDelegate.swift             改  +10
                                                   合計 ≈ +810（門檻 900，§7）
Tests/AuraCoreTests/Fixtures/round4-codex.ndjson   已就位（18 筆／4 個 session，唯讀證據）
Tests/AuraCoreTests/AgentArgumentTests.swift、CodexEventSeamTests.swift、CodexHooksJSONTests.swift、
  CodexStateTests.swift、CodexOptionsRowTests.swift、CodexInstallerTests.swift、
  CodexInstallerClobberTests.swift、CodexPathScopeTests.swift、Round4FixtureTests.swift、
  AgentSnapshotCodableTests.swift                  新
Tests/AuraCoreTests/Support/DirectoryTreeSnapshot.swift  新（從 ClaudeHomeTreeSnapshot 抽出，純重構）
Tests/AgentAuraAppTests/CodexWiringSmokeTests.swift、AppDelegateCodexWiredTests.swift、
  CodexHookStoreTests.swift、CodexRowLabelPixelTests.swift、CodexSectionRenderTests.swift  新
Tests/AgentAuraAppTests/Support/FakeCodexInstaller.swift、FakeCodexStore.swift  新
scripts/verify-uninstall.sh                        改（第 7 項 ＋ CODEX_HOME 覆寫 ＋ --only ＋ 第 2 行註解修正）
```

**單檔上限的五個風險點**（動工前就知道，不是驚喜）：

| 檔案 | 現況行數 | 上限 | 計畫要加什麼 | 處置 |
|---|---|---|---|---|
| `Sources/AgentAuraApp/AppDelegate+PanelActions.swift` | **200** | 200 | 三個新 case ＋ `refreshPanel` 帶 codex | T10 第一步預先搬移 |
| `Tests/AuraCoreTests/OptionsMenuModelTests.swift` | **300** | 300 | CX20／CX21 ＋ `rows(` 新參數 | T07 第一步拆 `CodexOptionsRowTests.swift` |
| `Tests/AgentAuraAppTests/AppDelegatePanelActionsWiredTests.swift` | **300** | 300 | `panelActionsAreWired` 涵蓋 3 個新 kind | T10 第一步拆 `AppDelegateCodexWiredTests.swift` |
| `Tests/AuraCoreTests/MergeRulesTests.swift` | 294 | 300 | `merge(` 新參數（1 處） | 餘裕 6 行，夠；超了就拆 |
| `Tests/AuraCoreTests/PanelViewModelTests.swift` | 288 | 300 | CX22 的 model 半 | 餘裕 12 行；CX22 的 model 半若寫不下就放 `CodexRowLabelPixelTests` |

`Sources/AgentAuraApp/StatusItemController.swift`（199）與 `Sources/AuraCore/InstallAffordance.swift`（194）
本 change 不動。

### 8.2 回寫（逐句）
| 位置 | 改為 |
|---|---|
| 正典 §2.2 event → activity 對照表 | 加一列 `Interrupt → idle`，註明「Codex only，**不得**進 `handledEvents`（Claude 全有全無）」；並點名它與 payload 欄位 `is_interrupt` 是兩件事 |
| 正典 §2.1 檔案契約 | 加 `agent`（Optional，nil = claude）欄位說明與 D-a／D-c 的理由 |
| 正典 §3.2 安裝機制 | 加一段「第二個入口：Codex 讀 `~/.codex/hooks.json`（F1、F14），我們只在它不存在時寫、只在內容相符時刪、絕不碰 `config.toml`」 |
| 正典 §3.5 pid liveness | 加一句「Codex 的 hook 父行程與 session 同壽命（F15），`getppid()` 判活成立；父行程的 `comm` 未辨識」 |
| 正典 §3.7 面板內容 | 加「非 Claude 的 session 在列的第一行帶 agent 標籤；聚合燈不分 agent」 |
| 正典 §9 開放風險 | 加「Codex 無 error 來源」「無法偵測信任狀態」兩條 |
| `CLAUDE.md` Invariants | 加「`CodexInstaller` 只准碰 `<codexHome>/hooks.json`；`config.toml` 位元組不得變動」「`Interrupt` 不得進 `handledEvents`」 |
| `CLAUDE.md` Tier 1 清單 | 加 `Sources/AgentAuraApp/CodexSectionView.swift`、`AppDelegate+Codex.swift`、`Sources/AuraCore/CodexState.swift` |
| `CLAUDE.md` Project 狀態 | 加 codex-support 一行 |
| `README.md` §「What it does to your Mac」 | 加 `~/.codex/hooks.json`（只在你按下按鈕時建立、只在內容仍是我們寫的那份時刪除） |
| `README.zh-TW.md` 對應段 | 同步 |
| `SECURITY.md` §「What this tool can do on your machine」＋「Boundaries that are enforced by tests」 | 加 `~/.codex/hooks.json` 與「`config.toml` 位元組不變」這條被測試強制的邊界。**注意**：`SECURITY.md` 沒有叫「What it does to your Mac」的段落，那是 `README.md:160` |
| `docs/INSTALL.md` ＋ `.zh-TW` | 新增「Using it with Codex」一節：前提、按哪裡、**Codex 會問你信任**、生效時機、怎麼移除 |
| `Resources/help-english.html` ／ `help-traditionalChinese.html` | 新增「Codex」段（CX28 強制涵蓋**每一個**新的 Options 列標題） |

## 9. Persona Impact

- **只用 Codex、不用 Claude Code 的人**：Claude 側是 `.notConnected`（大版說明佔滿），
  Codex 的提示在它下面。R-3 裁決：Codex 卡片**一律單行提示＋按鈕**，不做條件式降級——
  實作最簡、persona 風險最低，也不必把 Claude 的安裝狀態耦合進 Codex 元件。
  persona 要回答的是「兩個東西疊在同一張畫面上時，第一次看得懂要按哪個嗎」。
- **兩個都用的人**：列上只有 Codex 有標籤（D-b）。同一個專案目錄同時跑 Claude 與 Codex 時，
  兩列的 `projectName` 一模一樣，**只靠標籤區分**——persona 要回答「這樣夠不夠」。
- **已有自己 `~/.codex/hooks.json` 的進階使用者**：最在意的是「它會不會蓋掉我的」。
  畫面必須先講「我們不會動它」，再給 snippet；snippet 必須可選取、可一鍵複製，
  且**內容就是我們自己會寫的那份**（同一個產生器，不是另外手寫一份示意）。
- **不懂「信任」提示的 vibe coding 使用者**：按了接上、Codex 沒問或問了沒按同意 → 燈永遠不動，
  而我們偵測不到（F5）。畫面與 help 必須把「下次啟動 Codex 會問你一次」講在**按下去之前與之後各一次**，
  且 troubleshooting 第一條就是它。

## 10. Known gaps

| # | 內容 | 性質 |
|---|---|---|
| 1 | `PermissionRequest`／`Interrupt`／`SubagentStart`／`SubagentStop` 的 Codex payload 形狀**未量**（F10：`exec` 強制 `approval: never`）——`waiting` 在 Codex 上目前是**推論**不是實測 | 待驗；互動 TUI 探針跑完才升級為事實 |
| 2 | **Codex 沒有 `error` 來源**（F2、F4）：沒有 `PostToolUseFailure`／`StopFailure`，`tool_response` 只是字串 → Codex 的 session 永遠不會亮紅燈 | 設計代價，不硬推 |
| 3 | **無法偵測 Codex 是否已信任這個 hook**（F5：不在 `config.toml`、不在 `state_5.sqlite`、不在 `.codex-global-state.json`）→ UI 只能講，不能顯示狀態 | 平台限制 |
| 4 | 不寫 `async`：F14 明列「Claude 側用的 `async: true` Codex 是否接受或拒絕」為未測 → 代價是每個事件同步等 ~7 ms | 保守選擇 |
| 5 | ~~hooks.json 頂層形狀未知~~ **已由 F14 驗證**：逐字形狀（最外層 `hooks` 物件、`matcher: ""`、`type`／`command`／`timeout`）就是被 Codex 成功解析並觸發的那份，產生器逐字照它（R-1） | **已關閉** |
| 6 | 內容比對與 `unlink` 之間的 TOCTOU 窄窗（POSIX 無原子原語，macOS 無 `funlinkat`）；已用 `(dev,ino)` 二次確認縮小（m4） | 接受，窗已縮到最小 |
| 7 | `codex exec` 會寫 `config.toml`（F12）→ 自動化驗收一律不跑它，Codex 端到端只能靠人 | 驗收缺口 |
| 8 | hook 父行程與 session 同壽命已由 **F15** 確認（`getppid()` 判活成立），但那個 pid 是 `codex` 原生二進位還是 node 啟動器**未辨識**（探針沒記 `comm`）。若互動探針發現父行程其實跨 session 常駐，走 §4.7 的 fallback 決策點 | 待辨識；結論不受影響 |
| 9 | `timeout: 5` 會讓 Codex 對 `SessionEnd`／`Interrupt` 印出 clamping 警告（F13）到使用者的 stderr——那是 F14 那份**已驗證**的檔案本來就有的行為 | 見 §11 的待裁決列 |
| 10 | `command` 是裸路徑（F14 逐字）；**路徑含空白／引號時的行為未測**——F14 的樣本路徑無空白，引號是否被 Codex 支援也未測 | 待驗；實機清單 ⑦ |
| 11 | 兩個 agent 的 session 共用 `~/.agentaura/sessions/`；同一個專案同時跑兩邊時，兩列只靠標籤區分 | persona 打分 |

## 11. 風險

| 風險 | 緩解 |
|---|---|
| **`Interrupt` 進 `handledEvents` → Claude 側整份 hooks 靜默失效**（本 change 最大的爆炸半徑） | CX2 ＋ CX5 兩個獨立觀測點；§4.2 逐字寫明後果；`plugin/hooks/hooks.json` 的 git diff 必須為空（DoD 一條） |
| **`Interrupt → idle` 沒有 gate**（r1 的漏洞：fixture 零筆 `Interrupt`，刪掉整行也全綠） | CX4，定義域從 `codexOnlyEvents` 推導；CX13 的 mutation 換成 fixture 真的踩得到的 `Stop` |
| 「只在不存在時寫」寫成兩步（stat → write），symlink 指向 `config.toml` 時把使用者的設定覆蓋掉 | `O_EXCL`（D-i）＋ CX15 那一格對抗式 fixture ＋ mutation 必須紅在那一格 |
| 產生器偏離 F14 → Codex 根本不載入，而自動化抓不到 | CX6 的逐字 entry 比對；F14 的「未測」欄三項（省略 `matcher`／`async`／省略 `timeout`）一項都不碰 |
| **`reprobeCodex()` 沒被呼叫 → 裝了 Codex 卻要重開 app 才看得到**，且全套綠 | §4.6 明寫四個呼叫時機；CX24 第五段（spy 記 `probe()` 次數） |
| 憑證存在 `UserDefaults`，使用者清偏好設定後我們就不敢刪自己的檔 | 設計上保守失敗（`.occupiedByOther`）；UI 給 snippet 與「這不是我認得的那份」；`verify-uninstall.sh` 第 7 項用內容判準補上（D-o） |
| **94 個呼叫點的機械改動**（`make` 61／`rows` 26／`merge` 7）中夾帶弱化 | §6.4(2)(3)(4)(5) 的 test-edit scrutiny；`#expect` 淨數量不得下降 |
| 列標籤改了列高 → 唯一那一列被裁掉（本 codebase 已踩過同族兩次） | D-l ＋ CX23；`RowHeightDerivationTests` 從真實 view 推導，不是常數對常數 |
| Codex 端到端無法自動驗收（F12） | 實機清單 ①–⑦，且 spec 不得用「已實測」描述沒有實機證據的事 |

**待裁決（不自行決定，列給主 session）**：§10-9 的 clamping 警告。照 F14 寫 `timeout: 5`，
Codex 每個 session 會對 `SessionEnd`（與 `Interrupt`）印一次 `warning: clamping ... to 3s` 到使用者的 stderr；
把 12 個事件的 `timeout` 一律改成 `3` 可以讓那個警告消失（3 秒仍是實測 ~7 ms 的 400 倍餘裕），
但那就偏離了「逐字照 F14」的裁決。本文件照裁決寫 `5`。
