---
change: codex-support
release_target: softlaunch
persona_impact: tier1
persona_impact_reason: 動 Sources/AgentAuraApp/**（面板列標籤、Codex 區塊、Options 新列）與 AuraCore 的 PanelAction／PanelModel／面板文案；「接上 Codex」是使用者第一次見到的第二種安裝動作，而我們**無法偵測 Codex 是否已信任這個 hook**（F5），生效與否完全靠畫面把話講清楚——這是純人類面的風險，不是機器面的
revision: r1
---

# Change · `codex-support`：讓同一顆燈也照到 Codex

> 正典 `2026-09-08-agentaura-design.md` 為權威；本 change 對正典的修訂在 §8.2。
> 證據層是 `docs/2026-09-18-codex-hook-probe.md`（F1–F13）。**本文件中任何關於 Codex 行為的
> 斷言都標了 F 編號；沒有 F 編號的 Codex 行為一律寫成「待驗」，不得當事實用。**

## 0. 背景與裁決

Codex CLI 0.155.0 讀 `~/.codex/hooks.json`，結構與 Claude Code 相同（F1），事件名有 12 個、
其中 11 個與 Claude Code **同名同形**（F2、F3）。所以這個 change 不是「再做一套」，
是「把既有的那一套多接一條進水管」。

### 0.1 使用者 2026-09-18 拍板（鎖定，不重開）

| # | 決策 |
|---|---|
| L1 | **同一顆 `aura-hook` 二進位**，加 `--agent codex` 參數；預設（無參數）＝ claude。Claude 那側的 `plugin/hooks/hooks.json` **不改**（本 change 對它的 git diff 必須為空） |
| L2 | `SessionSnapshot` 加 `agent` 欄位；面板列顯示「Codex」標籤；**聚合燈不分 agent**，還是一顆 |
| L3 | 事件映射沿用既有 `EventMapping.effect`；新事件 **`Interrupt` → `.setActivity(.idle)`**；`waiting` 來自 `PermissionRequest`（形狀待驗）；**Codex 沒有 `error` 狀態的來源**（F2、F4）——列 known gap，不硬推 |
| L4 | 安裝模型：「接上 Codex」**只在 `~/.codex/` 存在時顯示**；按下去**只在 `~/.codex/hooks.json` 不存在時寫入**（12 個事件、`command` 用 bundle 內 `aura-hook` 的**絕對路徑** ＋ `--agent codex`，F9）；寫入時記下內容的 digest（`UserDefaults`，與既有 `AgentAuraHookVerified` 同一層）；斷開**只在 digest 相符時刪除**。檔案已存在（別人的）→ 不動它，顯示可複製的 snippet。**絕不碰 `~/.codex/config.toml`**。UI 必須明講「Codex 會在下次啟動時問你一次是否信任這個 hook」（F5） |
| L5 | 「完整移除」**必須一併移除我們寫的 `~/.codex/hooks.json`**（digest 相符時），讓機器回到從未安裝過的狀態 |
| L6 | 文件（README × 2、INSTALL × 2、`Resources/help-*.html`、SECURITY、CLAUDE.md）都要更新；**英文為主**，中文同步 |

### 0.2 本 change 自行決定的細節（最終報告逐條標示）

| 決定 | 內容 | 理由 |
|---|---|---|
| D-a | 磁碟上的 `agent` 是 **`String?`**（不是 enum），enum 只在 AuraCore 的邊界解析 | `Codable` 對「未知 rawValue 的 enum」是**整包解碼失敗**——未來多一種 agent，舊版 app 讀到的不是「少一個標籤」而是**那個 session 從面板整個消失**。同 `outstandingSubagents` 必須是 Optional 的既有理由（`SessionSnapshot` doc comment） |
| D-b | `Agent` 只有 `claude`／`codex`；未知值與 nil 一律落回 `.claude`，**且 `.claude` 不顯示標籤** | 保守失敗：寧可少一個標籤，不可把 Codex 的列標成 Claude 的；也讓只用 Claude 的人畫面位元不變 |
| D-c | `.claude` **不寫** `agent` 這個 JSON 鍵（`nil` 即 claude） | Claude 路徑的狀態檔位元組與改動前**完全相同**，可被 gate 直接斷言（G8） |
| D-d | `--agent` 支援 `--agent codex` 與 `--agent=codex` 兩種寫法；未知值／缺值／沒有這個參數一律 `.claude`，**全程靜默、exit 0** | 只支援一種寫法時，手寫成另一種會**靜默標成 claude**——那是「看起來裝好了其實標錯」的溫床。解析失敗不得有任何輸出（正典 Global Constraint） |
| D-e | Codex 的事件集合是**獨立常數** `EventMapping.codexEvents`（12 個，F2），**不併進 `handledEvents`** | `handledEvents` 是 Claude 側 `hooks.json` 跨層一致性 gate 的來源（`PluginWiringTests.registeredEventsMatchHandledEvents` 是**雙向等式**），而 Claude Code 對 hooks.json 是**全有全無**解析：多一個它不認識的 `Interrupt`，整份 hooks 會 `Failed to load`。**這是本 change 最容易踩的接縫**，見 §4.2 |
| D-f | `handledEvents` **不改名**（不改成 `claudeEvents`），只補 doc comment | 三個既有測試檔用字面 `handledEvents` 釘住它；改名等於把既有 gate 的 grep pin 搬家換來零收益 |
| D-g | hooks.json 產生器是**純函式**住 AuraCore（輸入絕對路徑字串，輸出 `Data`），檔案系統操作住 AuraHookFile | `Sources/AuraCore/` 只准 import Foundation（`IsolationTests` 白名單基準） |
| D-h | digest 的**計算**住 AgentAuraApp（CryptoKit SHA-256 hex），`CodexInstaller` 以 `@Sendable (Data) -> String` **注入**取得 | `IsolationTests` 的 module 基準：AuraCore = Foundation、AuraHookFile = Foundation ＋ CoreServices。CryptoKit／CommonCrypto 兩者都會讓那條 gate 紅。UI target 是唯一被賺到豁免的一層。形狀比照既有 R1（`Sendable` 的 `Installer` 不得碰 `UserDefaults`，憑證由 app 層寫） |
| D-i | 寫入用 `open(path, O_CREAT\|O_EXCL\|O_WRONLY\|O_CLOEXEC, 0o644)`，**不是**先 `stat` 再寫 | 「只在不存在時寫」必須是**一個**原子動作。`O_EXCL` 對既有檔、目錄、**symlink（含斷鏈）**一律 `EEXIST`／`EISDIR` —— 兩步寫法在 probe 與 write 之間的窗裡會沿著 symlink 寫到 `config.toml` 去 |
| D-j | `~/.codex` 不存在（或不是目錄）時，面板與 Options **完全沒有任何 Codex 元素** | 沒裝 Codex 的人畫面零 diff；既有的 `OptionsExpandTests`／`FooterPositionStabilityTests` 就是這個保證的守衛（版面數字一動它們就紅） |
| D-k | 新增三個 `PanelAction`：`.connectCodex`／`.disconnectCodex`（Options `.mount` 群組的**條件列**，同 `recheckHook` 的既有形狀）／`.copyCodexSnippet`（進 `nonMenuKinds`，它住在說明區塊、需要 snippet 的脈絡） | `nonMenuKinds` 有一條「恰好等於那四個」的字面集合 gate ——改它是**契約變更**，不是弱化，test-edit scrutiny 逐條列（§6.4） |
| D-l | 「Codex」標籤放在列的**第一行**（`projectName` ＋ `meta` 那個既有 `HStack`），不另起一行 | `SessionsCardSizing` 的 43／59pt 由 `RowHeightDerivationTests` 從真實 view 推導。另起一行會改列高、裁掉唯一那一列——那正是這個 codebase 已經踩過兩次的「凍住的數字」家族（CLAUDE.md gate 哲學 §2） |
| D-m | 接上成功的 banner **必須**同時說「下一個 Codex session 起生效」與「Codex 會問你一次是否信任」 | 沿用 D-m 既有教訓（不得寫「立即生效」，那是 S0-A1 修掉的謊）；F5 讓「已生效」在 Codex 上比在 Claude 上更不可宣稱 |
| D-n | 完整移除時，codex disconnect 必須排在 `erasePersistentDomain()` **之前** | digest 住在 persistent domain 裡，清掉之後我們就認不得自己寫的那個檔了。同既有 D-3（登入項目要在清 defaults 之前處理）的理由 |
| D-o | `verify-uninstall.sh` 第 7 項用**內容判準**（檔案含 `--agent codex`），不是 digest | 腳本跑的時候 persistent domain 已經清空，沒有 digest 可用。需要的語意是「有沒有殘留**我們的**那份」，內容判準剛好足夠 |
| D-p | `~/.codex` 自己是 symlink 時**不拒絕**，但寫入必須落在 `realpath` 底下且差異恰為 `{hooks.json}` | 使用者把 `.codex` 放別的磁碟是合理的；同既有 `ClaudeHomeSkillsSymlinkFixture` 的處理形狀 |

## 1. 目標與範圍

**做**：`--agent` 參數 · Codex 事件集合與 `Interrupt` 映射 · hooks.json 產生器 · `CodexInstaller`
（probe／connect／disconnect）· `agent` 欄位貫穿 payload → 檔案 → state → UI 四段 · 面板列標籤 ·
Codex 區塊與 Options 兩列 · snippet 複製 · digest 憑證 · 完整移除納入 · 文件與正典回寫 · 全鏈接線 gate。

**不做**：Codex 的 `error` 狀態（沒有來源，F2／F4）· 互動 TUI 探針（`PermissionRequest`／`Interrupt`／
`Subagent*` 的形狀待驗）· 分 agent 的聚合燈或分頁（L2 鎖定：一顆燈）· 動 `~/.codex/config.toml` ·
動 Claude 側 `plugin/hooks/hooks.json` · 自動偵測 Codex 是否已信任（F5：做不到）· 第三種 agent 的擴充機制（YAGNI）。

## 2. 架構總覽

```
Codex CLI ──(12 events, F2)──▶ ~/.codex/hooks.json ──▶ "<abs>/aura-hook" --agent codex
                                                              │ stdin: hook JSON (F3)
                                                              ▼
                             AgentArgument.agent(argv) ──▶ Agent(.codex)
                                                              │
        HookPayload(data:) ──▶ MergeRules.merge(payload, agent:) ──▶ SessionSnapshot(agent: "codex")
                                                              │  ~/.agentaura/sessions/<id>.json
                                                              ▼ （與 Claude 同一個目錄、同一條 FSEvents）
        PipelineGraph ──▶ SessionReducer ──▶ SessionState(agent:) ──▶ PanelRow(agentLabel:) ──▶ PanelRowView

CodexInstaller.probe() ──CodexObservation──▶ CodexState.from(_:recordedDigest:) ──▶ PanelModel.codex
   ▲ connect(json) / disconnect(expectedDigest:)            │
   └── CodexHooksJSON.json(hookBinaryPath:)                 ├─ .unavailable  → 面板零 Codex 元素（D-j）
       （純函式，事件清單從 codexEvents 推導）               ├─ .notConnected → 「接上 Codex」
                                                            ├─ .connected    → 「移除 Codex 掛載」
CodexHookStore（UserDefaults ＋ SHA-256）                    └─ .occupiedByOther → snippet（不提供按鈕）
```

| 單元 | 層 | 狀態 | 職責 |
|---|---|---|---|
| `Agent` | AuraCore | 新（`Agent.swift`） | `enum Agent: String, CaseIterable, Sendable { case claude, codex }`；`storedRawValue`（`.claude` → `nil`，D-c）；`init(stored:)`（nil／未知 → `.claude`，D-b） |
| `AgentArgument` | AuraCore | 新（同檔） | `static func agent(from argv: [String]) -> Agent`：純函式，支援兩種寫法，未知一律 `.claude`（D-d） |
| `EventMapping` | AuraCore | 改 | `+ codexEvents`（12 個字面集合，F2）、`+ codexOnlyEvents = ["Interrupt"]`；`effect` 的 switch 加 `case "Interrupt": .setActivity(.idle)`。**`handledEvents` 一個字都不動**（D-e／D-f） |
| `CodexHooksJSON` | AuraCore | 新 | `static let agentFlag = "--agent codex"`；`static func json(hookBinaryPath: String) -> Data`：事件鍵從 `codexEvents` **排序後推導**（不寫第二份清單），`command` = `"<path>" --agent codex`（路徑走 JSON 字串跳脫）；輸出穩定、可重現（同輸入 → 同位元組） |
| `CodexObservation` | AuraCore | 新 | 純資料：`codexHomeIsDirectory`、`entryType`（`absent`／`regularFile`／`directory`／`symlink`／`other`）、`contentsDigest: String?`、`displayPath: String?` |
| `CodexState` | AuraCore | 新 | `enum { unavailable, notConnected, connected, occupiedByOther }`（`CaseIterable`，供 gate 推導定義域）；`static func from(_:recordedDigest:)` **窮盡 switch**、零 I/O |
| `CodexFailure` | AuraCore | 新 | `Error`：`codexHomeMissing`／`alreadyExists`／`writeFailed(Int32)`／`notOurs`／`unreadable(Int32)`。比照 `InstallerFailure` 住 AuraCore（文案要窮盡推導） |
| `CodexInstaller` | AuraHookFile | 新（獨立檔，**不塞進 `Installer`**） | `Sendable`；欄位 `codexHome`／`hookBinaryURL`／`digest: @Sendable (Data) -> String`；`probe()`／`connect(json:) throws -> String`（回 digest）／`disconnect(expectedDigest:) throws`。**只碰 `<codexHome>/hooks.json`** |
| `CodexHookStore` | App | 新 | `@MainActor` ＋ 注入 `UserDefaults`（比照 `HookVerificationStore`）；key `AgentAuraCodexHookDigest`；`static let sha256Hex: @Sendable (Data) -> String`（CryptoKit，D-h） |
| `PanelAction` / `PanelActionKind` | AuraCore | 改 | `+ .connectCodex`／`.disconnectCodex`／`.copyCodexSnippet`（含 `kind` 與 `samples`） |
| `OptionsMenuModel` | AuraCore | 改 | `rows(...)` 多吃 `codex: CodexState`；`.mount` 群組在 `.notConnected`／`.connected` 各多一列；`nonMenuKinds` 加 `.copyCodexSnippet` |
| `PanelModel` | AuraCore | 改 | `+ codex: CodexState`、`+ codexSnippet: String?`；`make(...)` 新參數**不給預設值**（G13） |
| `PanelRow` | AuraCore | 改 | `+ agentLabel: String?`（`.claude` → nil，D-b）；由 `PanelViewModel.row` 從 `SessionState.agent` 推導 |
| `SessionSnapshot` / `MergeRules` / `SessionReducer` / `SessionState` | AuraCore | 改 | `agent: String?` 一路帶到 `SessionState.agent: Agent`；`merge(...)` 多一個 `agent:` 參數（**無預設值**） |
| `CodexSectionView` | App | 新 | `.notConnected`／`.occupiedByOther` 的說明與按鈕；snippet 用 `.textSelection(.enabled)` ＋「複製」 |
| `PanelRowView` | App | 改 | 第一行 `HStack` 內加標籤（D-l） |
| `AppDelegate+Codex.swift` | App | 新 | `performConnectCodex()`／`performDisconnectCodex()`／`performCopyCodexSnippet()`／`reprobeCodex()`；`codexInstaller`／`codexStore` 欄位 |
| `Uninstaller` | App | 改 | `run()` 在 `erasePersistentDomain()` 前多一步 codex disconnect（D-n） |

**設計選擇**
1. **一條資料流，兩個入口**：Codex 與 Claude 共用 `~/.agentaura/sessions/`、共用 `MergeRules`、
   共用聚合。`agent` 只是狀態上多一個顯示層欄位，不是第二條 pipeline。
2. **兩份 hooks.json 各自的來源集合分離**（§4.2）：Claude 那份由 `handledEvents` 推導（既有 gate 不動），
   Codex 那份由 `codexEvents` 推導（新 gate）。兩份都是 source-derived，都沒有手維護的第二份清單。
3. **安裝的保本動作全部在執行層**（`O_EXCL`、`lstat`、digest 比對），不靠上層路由先擋——
   同 `Installer.guardWriteTarget()` 的既有理由（S0-1(ii)：只信路由層的話，拿掉執行層的檢查不會有任何測試變紅）。

## 3. 資料模型

```swift
public enum Agent: String, Sendable, Equatable, CaseIterable {
    case claude, codex
    public init(stored: String?)            // nil／未知 → .claude（D-b）
    public var storedRawValue: String?      // .claude → nil（D-c）
    public var label: String?               // .claude → nil；.codex → "Codex"（不進 L10n：產品名不翻譯）
}
public enum AgentArgument { public static func agent(from argv: [String]) -> Agent }

extension EventMapping {
    public static let codexEvents: Set<String>      // 12 個（F2）
    public static let codexOnlyEvents: Set<String>  // ["Interrupt"]
}

public enum CodexHooksJSON {
    public static let agentFlag: String             // "--agent codex"
    public static func json(hookBinaryPath: String) -> Data
    public static func snippet(hookBinaryPath: String) -> String   // 給 .occupiedByOther 複製用
}

public struct CodexObservation: Equatable, Sendable {
    public enum EntryType: Equatable, Sendable { case absent, regularFile, directory, symlink, other }
    public let codexHomeIsDirectory: Bool
    public let entryType: EntryType
    public let contentsDigest: String?
    public let displayPath: String?
}
public enum CodexState: Equatable, Sendable, CaseIterable {
    case unavailable, notConnected, connected, occupiedByOther
    public static func from(_ o: CodexObservation, recordedDigest: String?) -> CodexState
}
```

判定表（`CodexState.from`，窮盡、零 I/O）：

| `codexHomeIsDirectory` | `entryType` | `recordedDigest` vs `contentsDigest` | → |
|---|---|---|---|
| false | 任意 | 任意 | `.unavailable` |
| true | `absent` | 任意 | `.notConnected` |
| true | `regularFile` | 兩者非 nil 且相等 | `.connected` |
| true | `regularFile` | 其餘（任一 nil／不等） | `.occupiedByOther` |
| true | `directory`／`symlink`／`other` | 任意 | `.occupiedByOther` |

`SessionSnapshot` 加 `public var agent: String? = nil`（CodingKey `agent`）。**必須是 Optional**——
理由與 `outstandingSubagents` 逐字相同（synthesized `Decodable` 對 Optional 用 `decodeIfPresent`，
缺這個 key 時自然是 nil；換成非 Optional 帶預設值仍會要求 key 存在，舊狀態檔整包解碼失敗）。

`UserDefaults`（domain `io.agentaura.app`）新增**一個** key：`AgentAuraCodexHookDigest` = SHA-256 hex。

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
   而 Claude Code 對 hooks.json 是**全有全無**解析（既有 `PluginWiringTests` 的 doc comment
   與散佈相容性紀錄）。所以共用 switch 多一個 case 對 Claude 側零影響；反過來，
   把它**註冊進** Claude 的 hooks.json 才是那個會爆的動作。G5 守的就是「沒有註冊」，
   不需要先回答「Claude 認不認得」這個未量到的問題。
3. 三條 gate 守這個接縫（§6.3 G2／G3／G5）：
   - `handledEvents` 與 `codexOnlyEvents` **不相交**（失敗訊息逐字寫明「Claude 全有全無」的後果）；
   - `codexEvents − codexOnlyEvents ⊆ handledEvents`（共用的 11 個真的共用同一份映射，不是各寫一份）；
   - `plugin/hooks/hooks.json` 不含 `Interrupt`（**獨立於**既有雙向等式的第二個觀測點——
     同時改壞兩邊時，只有雙向等式的話會一起變綠）。
4. Codex 那邊反過來很寬容（F7：不認得的事件名不會讓整份掛掉），所以我們**刻意只給它 12 個**，
   不把 Claude 專屬的 8 個（`PostToolUseFailure`／`PostToolBatch`／`PermissionDenied`／`Elicitation`／
   `ElicitationResult`／`Notification`／`StopFailure`／`PostModelSwitch`）塞進去白付呼叫。

**後果（誠實列出）**：Codex 沒有 `PostToolUseFailure` 也沒有 `StopFailure`（F2），
`tool_response` 只是字串、沒有 exit code（F4）——**Codex 的 session 永遠不會讓燈變紅**。
這是 known gap（§10-2），不用猜測性的啟發式去硬推。

### 4.3 hooks.json 產生器（D-g）
```
{
  "description": "...",
  "hooks": {
    "<event>": [ { "hooks": [ { "type": "command", "command": "\"<abs>/aura-hook\" --agent codex" } ] } ],
    ...（12 個，事件名排序）
  }
}
```
- 事件清單從 `codexEvents` 排序推導，**不寫第二份**；gate 反向解析產出的 JSON 驗鍵集合恰等於它。
- `command` 帶引號（`$HOME` 含空白時才不會裂開，同 Claude 側既有慣例）；路徑走 JSON 字串跳脫，
  含引號／反斜線的路徑仍是合法 JSON（G4 的對抗式輸入）。
- **不寫 `async`**：Claude 側那個鍵在 Codex 上未量到（F1 只證明 `matcher`／`hooks`／`type`／
  `command`／`timeout` 被認得）。代價是每個事件同步等一次 `aura-hook`（實測 ~7 ms，
  而 `SessionEnd`／`Interrupt` 的 timeout 被 Codex 自己壓到 3 秒，F13）。列 known gap（§10-4）。
- **不寫 `timeout`**：沒有需要縮短的理由，多一個未量到的鍵只是多一個未知數。

### 4.4 `CodexInstaller`：三個動作
- **`probe()`**：`lstat(codexHome)` 判目錄 → `lstat(hooks.json)` 判 `entryType` →
  只有 `regularFile` 才 `open(..., O_RDONLY | O_NOFOLLOW)` 讀內容算 digest（讀取上限 1 MiB，
  超過視為 `.occupiedByOther`，不把別人的大檔整包吃進記憶體）。
- **`connect(json:)`**：`open(path, O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC, 0o644)`（D-i）→ 寫入 →
  `close` → 回傳 `digest(json)`。`codexHome` 不是目錄時先 throw `.codexHomeMissing`（**不建立它**——
  同「`~/.claude` 不存在時拒絕接上、不得建立它」的既有 invariant）。`EEXIST` → `.alreadyExists`。
- **`disconnect(expectedDigest:)`**：`open(..., O_RDONLY|O_NOFOLLOW)` → `fstat` 確認 `S_IFREG` →
  讀 → digest 比對 → 不符即 throw `.notOurs`（**不刪**）→ 相符才 `unlink`。
  absent 視為已斷開，冪等成功（同 `Installer.disconnect()`）。

**TOCTOU 誠實交代**：POSIX 沒有「內容相符才 unlink」的原子原語，比對與 `unlink` 之間有一個窄窗。
我們把窗縮到最小（同一個 fd 讀完立刻比對立刻 unlink，中間不做別的），並接受殘留風險——
列 known gap（§10-6）。寫入那一側**沒有**這個問題（`O_EXCL` 本身就是原子的）。

### 4.5 digest 憑證與完整移除
- `connect` 成功 → app 層 `CodexHookStore.write(digest)`；`disconnect` 成功 → `clear()`。
- `Uninstaller.run()` 的順序變成：`loginItem.set(false)` → `installer.disconnect()` →
  **`codexInstaller.disconnect(expectedDigest: store.digest)`（try?）** → `StateDirectoryEraser.erase` →
  `erasePersistentDomain()` → `recycleBundleAndTerminate()`。codex 那步**必須在清 domain 之前**（D-n），
  且與其他步驟一樣 best-effort：它失敗不得卡住後面的步驟（Lessons #8）。
- `scripts/verify-uninstall.sh` 第 7 項：`${CODEX_HOME:-$HOME/.codex}/hooks.json` 存在**且**含
  `--agent codex` → FAIL；存在但不含 → PASS（那是別人的檔，本來就不該動）；不存在 → PASS。
  `CODEX_HOME` 覆寫存在的唯一理由是讓這一項**可以被測試**（G26），不是給使用者用的。

### 4.6 面板與 Options
| 狀態 | 面板 | Options（`.mount` 群組） |
|---|---|---|
| `.unavailable` | **什麼都不畫**（D-j） | 零列 |
| `.notConnected` | 說明卡：「你有 Codex，要不要也接上」＋ 按鈕 | 「接上 Codex」 |
| `.connected` | 不畫說明卡（列上有標籤就夠） | 「移除 Codex 掛載…」 |
| `.occupiedByOther` | 說明卡：「你已經有自己的 `~/.codex/hooks.json`，我們不會動它」＋ 可選取的 snippet ＋「複製」 | 零列（沒有安全的一鍵動作可提供） |

接上成功的 banner（D-m，兩句都要有）：**「已接上 Codex · 下一個 Codex session 起生效；
Codex 啟動時會問你一次是否信任這個 hook，要按同意才會生效。」**（F5：我們偵測不到信任狀態，
所以這句不能省，也不能改寫成「已生效」。）

## 5. 錯誤處理

| 情況 | 處理 |
|---|---|
| `--agent` 未知值／缺值／重複 | 落回 `.claude`；靜默、exit 0、零輸出（D-d） |
| 磁碟上 `agent` 是未知字串／非字串／`null` | `Agent(stored:)` 落回 `.claude`；**整包仍解得開**（D-a）；那一列沒有標籤 |
| 舊版狀態檔沒有 `agent` 鍵 | `decodeIfPresent` → nil → `.claude`（G10） |
| `~/.codex` 不存在／是普通檔／是斷鏈 symlink | `.unavailable`；**不建立它**；面板零 Codex 元素 |
| `~/.codex/hooks.json` 已存在（普通檔／目錄／symlink／斷鏈 symlink） | `connect` 一律 throw `.alreadyExists`；**那個路徑（含 symlink 指向的目標）位元組與型別完全不變**（G14 逐格斷言，含「symlink 指向 `config.toml`」這最惡毒的一格） |
| `hooks.json` 存在但 digest 對不上 | `.occupiedByOther`；不提供刪除按鈕；`disconnect` 若被呼叫一律 throw `.notOurs` |
| digest 記錄遺失（使用者清過偏好設定） | `.occupiedByOther`（保守：認不得就不碰）；UI 顯示 snippet 與「這個檔不是我認得的那份」 |
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
2. **argv**：`[]`／`["--agent"]`／`["--agent","gemini"]`／`["--agent","CODEX"]`／`["--agent=codex"]`／
   `["--agent","codex","--agent","claude"]`／`["--agent","codex","--agent"]`。
3. **檔案系統**：`~/.codex/hooks.json` 是**目錄**／是**symlink 指向 `config.toml`**／是斷鏈 symlink／
   是別人的合法 JSON／是 5 MB 的垃圾；`~/.codex` **自己**是 symlink 指到 codexHome 之外；
   `~/.codex` 是普通檔；`~/.codex` 不存在。
4. **digest double**：`FakeCodexStore` 可設定「寫了但讀回來不一樣」（比照 `FakeLoginItem`
   的 `isEnabled` 與剛設定的值不一致）。
5. **`FakeCodexInstaller`**：① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
   ② `disconnect()` 宣稱成功但檔案還在；③ `probe()` 丟錯。

### 6.2 composition-root smoke（spec §5.2 的既有形狀）
- `codexInstallerIsInjected`：真 `AppDelegate` 啟動後 `codexInstaller` 非 nil、`codexStore` 非 nil。
- `productionCodexHomeIsRealHome`：生產預設 `codexHome` == `FileManager.default
  .homeDirectoryForCurrentUser.appendingPathComponent(".codex")`；**外加**來源掃描
  `Sources/` 不得用 `environment["HOME"]` 算它（CLAUDE.md 陷阱：`homeDirectoryForCurrentUser`
  不吃 `$HOME`，用環境變數算會在生產與測試給出不同答案）。
- `codexConnectChainIsWired`：`spy.onAction!(.connectCodex)` → fake installer 真的收到 `connect`、
  digest 真的進了注入的 suite、`banner` 出現且文字**同時**含「下一個 session」與「信任」兩個關鍵詞
  （關鍵詞從 `L10nCodex` 的鍵推導，不寫死字面）。
- `codexRowsReachTheView`：`.notConnected` 時真的渲出按鈕（像素 > 門檻）；`.unavailable` 時
  面板的 `preferredContentSize` 與零 Codex 狀態**完全相同**。

### 6.3 Gate 表

| Gate | 層 | 守什麼 | Mutation（→ 指名測試 ≤60s 變紅） |
|---|---|---|---|
| G1 `codexEventSetIsPinnedToProbe` | AuraCore | `codexEvents` 恰等於探針 F2 的 12 個字面名 | 加一個／少一個 |
| **G2 `interruptNeverEntersHandledEvents`** | AuraCore | `handledEvents.isDisjoint(with: codexOnlyEvents)`；失敗訊息逐字寫「Claude 全有全無」 | 把 `Interrupt` 加進 `handledEvents` |
| G3 `codexSharedEventsReuseClaudeMapping` | AuraCore | `codexEvents − codexOnlyEvents ⊆ handledEvents`，且每個的 `effect` 非 `.noChange` | 從 `handledEvents` 拿掉 `PreCompact` |
| G4 `codexHooksJSONRegistersExactlyCodexEvents` | AuraCore | 產出 JSON 解析後：`hooks` 鍵集合 == `codexEvents`；每個 `command` == `"<path>" \(agentFlag)`；路徑含空白／引號仍可解析回原路徑 | 產生器改成寫死 11 個事件 |
| G5 `claudeHooksJSONHasNoInterrupt` | AuraCore | `plugin/hooks/hooks.json` 不含 `Interrupt`（**獨立於**既有雙向等式） | 在 Claude hooks.json 加 `Interrupt` |
| G6 `agentArgumentParsing`（對抗式） | AuraCore | §6.1(2) 七種 argv 的期望值逐格 | 未知值改成 `.codex` |
| G7 `auraHookStaysSilentForEveryAgentArgument` | E2E（真 spawn） | 三種 argv：exit 0、stdout 空、stderr 空 | 在解析失敗時 `FileHandle.standardError.write` |
| G8 `claudeStateFileHasNoAgentKey` | AuraCore | 用 round1–3 fixture 跑 merge，序列化後**不含** `agent` 鍵 | `.claude` 也寫 `"claude"` |
| G9 `codexStateFileCarriesAgent` | E2E（真 spawn） | `--agent codex` 真跑一次 → 檔案含 `"agent":"codex"`，`SessionState.agent == .codex` | `main.swift` 忘了把 agent 傳進 merge |
| G10 `legacySnapshotWithoutAgentDecodes` | AuraCore | 無 `agent` 鍵的舊 JSON 解得開且 `.claude` | 把 `agent` 改成非 Optional |
| G11 `unknownAgentFallsBackWithoutFailingDecode` | AuraCore | `"agent":"gemini"` → 整包解得開、`.claude`、無標籤 | 把 `agent` 改成 `Agent?`（enum）讓整包失敗 |
| G12 `round4FixtureParsesAndMatchesProbeTable` | AuraCore | 18 筆全部 `HookPayload` 非 nil；每筆 `effect` 與探針欄位表一致；`isSafeSessionID` 全過；探針表列的每個欄位至少出現一次 | `effect` 對 `Interrupt` 改回 `.noChange` |
| **G13 `codexInstallerTouchesOnlyHooksJSON`** | AuraHookFile | `codexHome` 整棵樹前後快照，差異**恰為** `{hooks.json}`；植入的 `config.toml` 位元組完全不變 | connect 順手寫一個 `hooks.json.bak` |
| G14 `codexConnectRefusesEveryOccupiedShape`（對抗式） | AuraHookFile | §6.1(3) 六種佔用形狀各 throw，**且該路徑（含 symlink 目標）位元組與型別不變** | 拿掉 `O_EXCL`（symlink→`config.toml` 那格必須紅） |
| G15 `codexConnectWritesGeneratorBytes` | AuraHookFile | 成功路徑：檔案內容 == `CodexHooksJSON.json(...)` 位元組；回傳 digest == `digest(那些位元組)` | connect 少寫最後一個 byte |
| G16 `codexDisconnectOnlyRemovesOurBytes` | AuraHookFile | digest 相符才刪；改一個 byte → 不刪＋throw；`expectedDigest` 為 nil → 不刪 | 拿掉 digest 比對 |
| G17 `codexHomeSymlinkWritesInsideResolvedPath` | AuraHookFile | `~/.codex` 是外部 symlink：字面樹不變、`realpath` 樹差異恰為 `{hooks.json}` | 用字面路徑取快照（必須紅） |
| G18 `codexStateCoversEveryObservationShape` | AuraCore | `CodexState.from` 對 §3 判定表逐格；定義域由 `EntryType × {digest 三態} × codexHomeIsDirectory` **推導** | 把 `symlink` 併進 `.notConnected` |
| G19 `codexRowsAppearOnlyWhenAvailable` | AuraCore | `.unavailable` → rows 零 codex kind；其餘三態各自恰含預期列 | `.unavailable` 也給「接上 Codex」 |
| G20 `optionsRowsCoverEveryAction`（既有 G10 擴充） | AuraCore | 代表狀態集合加上 `CodexState.allCases`；`nonMenuKinds` 字面集合加 `.copyCodexSnippet` | 把 `.connectCodex` 塞進 `nonMenuKinds` |
| G21 `agentLabelOnlyForNonClaude` | AuraCore ＋ 像素 | model：claude → nil、codex → "Codex"；像素：同一列 claude vs codex `differingPixels > 0` | 標籤對 claude 也給值 |
| **G22 `codexLabelDoesNotChangeRowHeight`** | App（離屏） | 帶標籤的列高仍是 43／59pt（±0.5），`SessionsCardSizing` 兩個常數對 codex 列同樣成立 | 標籤另起一行 |
| G23 `codexConnectChainIsWired`（smoke） | App | §6.2 第三條，四段各自獨立失敗訊息 | 刪 `status.onAction` 的 `.connectCodex` 分支 |
| G24 `productionCodexHomeIsRealHome`（smoke ＋ 來源掃描） | App ＋ AuraCore | §6.2 第二條 | 改成 `environment["HOME"]` |
| G25 `uninstallRemovesCodexBeforeErasingDefaults` | App | Fake 記錄呼叫順序：codex disconnect **早於** `removePersistentDomain` | 兩步對調 |
| G26 `verifyUninstallScriptDetectsOurCodexHooks` | script | 暫存 `CODEX_HOME` 跑兩次：含 `--agent codex` → 非零退出；別人的檔 → 該項 PASS | 拿掉第 7 項 |
| G27 `helpDocsCoverCodexRows`（既有擴充） | 文件 | `HelpDocOptionsRowCoverageTests` 的代表狀態加 codex 態，兩個語言各自守 | help 少寫「接上 Codex」 |
| G28 `securityDocListsEveryPathWeWrite` | 文件 | `README.md`／`SECURITY.md` 必須含 `.codex/hooks.json`（字面來自生產常數，不手抄） | 從 SECURITY.md 刪掉那一行 |
| G29 `noCodexExecInRepo` | 全 repo | `Tests/`／`scripts/` 不得出現 `codex exec`（＋暫存目錄正向對照） | 在腳本裡加一行 `codex exec` |
| 既有全部 gate | — | 繼續綠（尤其 `registeredEventsMatchHandledEvents`、`fileLengthLimit`、`nonUITargetsLoadNoUIModules`、`noStrayLiteralOutsideAllowlist`、`RowHeightDerivation`、`FooterPositionStability`） | — |

### 6.4 test-edit scrutiny 預告（Lessons #3）
1. `OptionsMenuModelTests.nonMenuKindsIsExactlyThatLiteralSet`：四個 → 五個。
   **這是契約變更不是弱化**——集合仍然是「恰好等於」，只是多了一個有理由的成員（D-k）；
   報告要把改前／改後／理由三欄擺在一起。
2. `PanelModel.make` 新增無預設值參數 → **61 個呼叫點**（26 個檔）全部要加 `codex:`。
   測試呼叫點一律傳 `.unavailable`（＝現況行為），生產呼叫點傳真實狀態。
   **`#expect` 淨數量不得下降**；不得有任何既有斷言因為「加了參數」被改成更弱的形式。
3. `MergeRules.merge` 新增無預設值 `agent:` → 7 個呼叫點；測試一律傳 `.claude`。
4. `HelpDocOptionsRowCoverageTests.allRows` 的代表狀態要能踩到 codex 列，否則 help gate 對新列空跑。
5. `ClaudeHomeTreeSnapshot` 的 walk／entry 抽成共用 `DirectoryTreeSnapshot`（G13 要用同一套機制）——
   **純重構**：既有 G2 兩條測試必須全綠，且 G2 的 mutation 要**當場重跑一次**確認仍然精準紅。

### 6.5 已知不可測（寫進 §10 與最終報告）
- Codex 是否真的載入並執行我們寫的 hooks.json（要真的跑 Codex，而自動化不准跑 `codex exec`，F12）→ 實機 ②③。
- 信任提示的 UX 與「拒絕信任」的行為（F5 找不到持久化位置）→ 實機 ④。
- `PermissionRequest`／`Interrupt`／`Subagent*` 的實際 payload 形狀（探針只在 `exec` 模式跑過，
  F10：`exec` 強制 `approval: never`，`PermissionRequest` 在那個模式不可能出現）→ 互動探針跑完才升級。

## 7. DoD

門檻與量法見 `docs/superpowers/plans/2026-09-18-codex-support-dod.md`（每條有數字）。

## 8. 檔案佈局與回寫

### 8.1 檔案（估行；`Sources/` 基準 7846 行）
```
Sources/AuraCore/Agent.swift                       新  ~60（Agent ＋ AgentArgument）
Sources/AuraCore/EventMapping.swift                改  +25（codexEvents／codexOnlyEvents／Interrupt case）
Sources/AuraCore/CodexHooksJSON.swift              新  ~70
Sources/AuraCore/CodexState.swift                  新  ~75（CodexObservation ＋ CodexState ＋ CodexFailure）
Sources/AuraCore/SessionSnapshot.swift             改  +10
Sources/AuraCore/MergeRules.swift                  改  +6
Sources/AuraCore/SessionReducer.swift              改  +2
Sources/AuraCore/SessionState.swift                改  +5
Sources/AuraCore/PanelViewModel.swift              改  +6（PanelRow.agentLabel）
Sources/AuraCore/PanelAction.swift                 改  +25（三個 case × kind × samples）
Sources/AuraCore/OptionsMenuModel.swift            改  +18
Sources/AuraCore/PanelModel.swift                  改  +14
Sources/AuraCore/L10nCodex.swift                   新  ~95（雙語；產品名 "Codex" 不翻）
Sources/AuraHookFile/CodexInstaller.swift          新  ~120
Sources/AuraHookFile/CodexInstaller+Probe.swift    新  ~70（撞 200 行就拆這裡）
Sources/aura-hook/main.swift                       改  +3
Sources/AgentAuraApp/CodexHookStore.swift          新  ~55
Sources/AgentAuraApp/CodexSectionView.swift        新  ~90
Sources/AgentAuraApp/AppDelegate+Codex.swift       新  ~95
Sources/AgentAuraApp/AppDelegate+Links.swift       新  ~45（**純搬移**：把 openHelp／helpURL／reportIssue
                                                        從已經 200 行的 AppDelegate+PanelActions.swift 搬出來）
Sources/AgentAuraApp/AppDelegate+PanelActions.swift 改 −45 +6（搬走 ＋ 三個新 case）
Sources/AgentAuraApp/PanelView.swift               改  +8（列標籤 ＋ 掛 CodexSectionView）
Sources/AgentAuraApp/Uninstaller.swift             改  +8
Sources/AgentAuraApp/AppDelegate.swift             改  +10
                                                   合計 ≈ +830（門檻 900，§7）
Tests/AuraCoreTests/Fixtures/round4-codex.ndjson   新（主 session 提供，18 筆，唯讀證據）
Tests/AuraCoreTests/AgentArgumentTests.swift、CodexEventSeamTests.swift、CodexHooksJSONTests.swift、
  CodexStateTests.swift、CodexInstallerTests.swift、CodexInstallerClobberTests.swift、
  CodexPathScopeTests.swift、Round4FixtureTests.swift、AgentSnapshotCodableTests.swift  新
Tests/AuraCoreTests/Support/DirectoryTreeSnapshot.swift  新（從 ClaudeHomeTreeSnapshot 抽出，純重構）
Tests/AgentAuraAppTests/CodexWiringSmokeTests.swift、CodexHookStoreTests.swift、
  CodexRowLabelPixelTests.swift、CodexSectionRenderTests.swift  新
Tests/AgentAuraAppTests/Support/FakeCodexInstaller.swift、FakeCodexStore.swift  新
scripts/verify-uninstall.sh                        改（第 7 項 ＋ CODEX_HOME 覆寫）
```

**單檔 200 行的三個風險點**（動工前就知道，不是驚喜）：
`AppDelegate+PanelActions.swift` 目前**恰好 200 行**（加任何一個 case 都會超），
`StatusItemController.swift` 199，`InstallAffordance.swift` 194。前者由 T10 的預先搬移處理，
後兩者本 change 不動。

### 8.2 回寫（逐句）
| 位置 | 改為 |
|---|---|
| 正典 §2.2 event → activity 對照表 | 加一列 `Interrupt → idle`，註明「Codex only，**不得**進 `handledEvents`（Claude 全有全無）」 |
| 正典 §2.1 檔案契約 | 加 `agent`（Optional，nil = claude）欄位說明與 D-a／D-c 的理由 |
| 正典 §3.2 安裝機制 | 加一段「第二個入口：Codex 讀 `~/.codex/hooks.json`（F1），我們只在它不存在時寫、只在 digest 相符時刪、絕不碰 `config.toml`」 |
| 正典 §3.7 面板內容 | 加「非 Claude 的 session 在列的第一行帶 agent 標籤；聚合燈不分 agent」 |
| 正典 §9 開放風險 | 加「Codex 無 error 來源」「無法偵測信任狀態」兩條 |
| `CLAUDE.md` Invariants | 加「`CodexInstaller` 只准碰 `<codexHome>/hooks.json`；`config.toml` 位元組不得變動」「`Interrupt` 不得進 `handledEvents`」 |
| `CLAUDE.md` Tier 1 清單 | 加 `Sources/AgentAuraApp/CodexSectionView.swift`、`AppDelegate+Codex.swift`、`Sources/AuraCore/CodexState.swift` |
| `CLAUDE.md` Project 狀態 | 加 codex-support 一行 |
| `README.md` §「What it does to your Mac」 | 加 `~/.codex/hooks.json`（只在你按下按鈕時建立、只在內容仍是我們寫的那份時刪除） |
| `README.zh-TW.md` 對應段 | 同步 |
| `SECURITY.md` §「What this tool can do on your machine」＋「Boundaries that are enforced by tests」 | 加 `~/.codex/hooks.json` 與「`config.toml` 位元組不變」這條被測試強制的邊界 |
| `docs/INSTALL.md` ＋ `.zh-TW` | 新增「Using it with Codex」一節：前提、按哪裡、**Codex 會問你信任**、生效時機、怎麼移除 |
| `Resources/help-english.html` ／ `help-traditionalChinese.html` | 新增「Codex」段（G27 強制涵蓋新的 Options 列標題） |

## 9. Persona Impact

- **只用 Codex、不用 Claude Code 的人**：第一次開面板時 Claude 側是 `.notConnected`（大版說明佔滿），
  Codex 的說明卡在它下面——**兩張「還沒接上」的卡片疊在一起是這個 change 最可能的可用性事故**。
  處置：`.notConnected`（Claude）＋ `.notConnected`（Codex）時，Codex 卡改成單行提示＋按鈕，
  不用大版說明（persona 打分驗這一格）。
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
| 4 | hooks.json 的 `async` 鍵在 Codex 上未量到 → 不寫，代價是每個事件同步等 ~7 ms | 保守選擇 |
| 5 | 「事件是否必須包在最外層 `hooks` 物件內」：F1 只證明探針那份檔**被解析**，那份檔的逐字形狀沒有進證據文件 → 若形狀猜錯，實機 ② 會直接失敗（hooks 不觸發） | 待實機驗收 |
| 6 | digest 比對與 `unlink` 之間的 TOCTOU 窄窗（POSIX 無原子原語） | 接受，窗已縮到最小 |
| 7 | `codex exec` 會寫 `config.toml`（F12）→ 自動化驗收一律不跑它，Codex 端到端只能靠人 | 驗收缺口 |
| 8 | 兩個 agent 的 session 共用 `~/.agentaura/sessions/`；同一個專案同時跑兩邊時，兩列只靠標籤區分 | persona 打分 |

## 11. 風險

| 風險 | 緩解 |
|---|---|
| **`Interrupt` 進 `handledEvents` → Claude 側整份 hooks 靜默失效**（本 change 最大的爆炸半徑） | G2 ＋ G5 兩個獨立觀測點；§4.2 逐字寫明後果；`plugin/hooks/hooks.json` 的 git diff 必須為空（DoD 一條） |
| 「只在不存在時寫」寫成兩步（stat → write），symlink 指向 `config.toml` 時把使用者的設定覆蓋掉 | `O_EXCL`（D-i）＋ G14 那一格對抗式 fixture ＋ mutation 必須紅在那一格 |
| digest 記在 `UserDefaults`，使用者清偏好設定後我們就不敢刪自己的檔 | 設計上保守失敗（`.occupiedByOther`）；UI 給 snippet 與「這不是我認得的那份」；`verify-uninstall.sh` 第 7 項用內容判準補上（D-o） |
| `PanelModel.make` 加無預設值參數 → 61 個呼叫點，機械改動中夾帶弱化 | §6.4(2) 的 test-edit scrutiny；`#expect` 淨數量不得下降 |
| 列標籤改了列高 → 唯一那一列被裁掉（本 codebase 已踩過同族兩次） | D-l ＋ G22；`RowHeightDerivationTests` 從真實 view 推導，不是常數對常數 |
| 兩張「還沒接上」卡片疊在一起（§9 第一條） | 設計上降級成單行；persona 硬下限一條 |
| Codex 端到端無法自動驗收（F12） | 實機清單 ①–⑥（DoD），且 spec 不得用「已實測」描述沒有實機證據的事 |
