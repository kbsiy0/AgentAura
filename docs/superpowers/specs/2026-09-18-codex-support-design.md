---
change: codex-support
release_target: softlaunch
persona_impact: tier1
persona_impact_reason: 動 Sources/AgentAuraApp/**（面板列標籤、Codex 區塊、Options 新列）與 AuraCore 的 PanelAction／PanelModel／面板文案；「接上 Codex」是使用者第一次見到的第二種安裝動作，而我們**無法偵測 Codex 是否已信任這個 hook**（F5），生效與否完全靠畫面把話講清楚——這是純人類面的風險，不是機器面的
revision: r3（2026-09-18，折入 review r2 的 1B／6M／5m）
---

# Change · `codex-support`：讓同一顆燈也照到 Codex

> 正典 `2026-09-08-agentaura-design.md` 為權威；本 change 對正典的修訂在 §8.2。
> 證據層是 `docs/2026-09-18-codex-hook-probe.md`（**F1–F15**，F15 以 `8fdce0b` 的版本為準）。
> **任何關於 Codex 行為的斷言都標了 F 編號；沒有 F 編號的一律寫成「待驗」，不得當事實用。**
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

### 0.2 review r1／r2 之後的裁決（主 session 2026-09-18，已鎖定）

| # | 裁決 | 取代 |
|---|---|---|
| R-1 | 產生器**逐字**輸出 F14 已驗證的形狀：`matcher: ""`、`type: "command"`、`command`，最外層 `hooks` 物件；**不加 `async`** | r1 §4.3 省略 `matcher` 的變體（r1 B1／M11） |
| R-2 | **不算 hash**：把寫入的完整內容存進 `UserDefaults`，刪除前逐位元組比對 | r1 的 D-h（SHA-256 ＋ 注入縫）整條作廢（r1 M1） |
| R-3 | `.notConnected` 的 Codex 卡片**一律單行提示＋按鈕**，不依 Claude 的安裝狀態降級 | r1 §4.6／§9／T09 三處互相矛盾的敘述（r1 M7） |
| **R-4** | **`timeout: 3`**（全部 12 個事件同一個值），這是**對 F14 唯一的數值偏離**，理由與代價見 §4.3 | r2 的 `timeout: 5`（r2 M2） |
| **R-5** | 「這個 bundle 路徑能不能寫進 hooks.json」收斂成**單一純函式判定** `CodexHookPathCheck`，輸入 `(translocated, inDownloads, hookBinaryPath)`；輸出同時餵**路由層**（`CodexState` 的 explain-only 分支，不畫按鈕）與**執行層**（`CodexInstaller.connect` 再做一次當保本，S0-1(ii)） | r2 完全沒有 translocation／路徑字元護欄（r2 B1／M3） |
| **R-6** | app 搬家導致絕對路徑失效 → `CodexState.from` 多吃 `currentExpectedContents`，新增 **`.connectedStalePath`**，UI 給「App 移動過，要重新接上」＋一鍵重接 | r2 的 `.connected` 在搬家後永遠成立（r2 M5） |
| **R-7** | 含空白路徑的**探索性量測**移到互動探針工具包（已備好含空白路徑＋引號的探針）；DoD 實機 ⑦ 只驗「拒絕 ＋ 訊息指名字元 ＋ 有出路」 | r2 實機 ⑦「按接上 → 燈會動」（與 R-5 互斥，r2 M4） |

### 0.3 本 change 自行決定的細節（最終報告逐條標示）

| 決定 | 內容 | 理由 |
|---|---|---|
| D-a | 磁碟上的 `agent` 是 **`String?`**（不是 enum），enum 只在 AuraCore 的邊界解析 | `Codable` 對「未知 rawValue 的 enum」是**整包解碼失敗**——未來多一種 agent，舊版 app 讀到的不是「少一個標籤」而是**那個 session 從面板整個消失**。同 `outstandingSubagents` 必須是 Optional 的既有理由 |
| D-b | `Agent` 只有 `claude`／`codex`；未知值與 nil 一律落回 `.claude`，**且 `.claude` 不顯示標籤** | 保守失敗：寧可少一個標籤，不可把 Codex 的列標成 Claude 的；也讓只用 Claude 的人畫面位元不變 |
| D-c | `.claude` **不寫** `agent` 這個 JSON 鍵（`nil` 即 claude） | Claude 路徑的狀態檔位元組與改動前**完全相同**，可被 gate 直接斷言（CX9） |
| D-d | `--agent` 支援 `--agent codex` 與 `--agent=codex` 兩種寫法；未知值／缺值／沒有這個參數一律 `.claude`，**全程靜默、exit 0** | 只支援一種寫法時，手寫成另一種會**靜默標成 claude**——那是「看起來裝好了其實標錯」的溫床 |
| D-e | Codex 的事件集合是**獨立常數** `EventMapping.codexEvents`（12 個，F2），**不併進 `handledEvents`** | `handledEvents` 是 Claude 側 `hooks.json` 跨層一致性 gate 的來源（`registeredEventsMatchHandledEvents` 是**雙向等式**），而 Claude Code 對 hooks.json 是**全有全無**解析。**本 change 最容易踩的接縫**，見 §4.2 |
| D-f | `handledEvents` **不改名**，只補 doc comment | 三個既有測試檔用字面 `handledEvents` 釘住它；改名等於把既有 gate 的 grep pin 搬家換來零收益 |
| D-g | hooks.json 產生器是**純函式**住 AuraCore（輸入絕對路徑字串，輸出 `Data`），檔案系統操作住 AuraHookFile | `Sources/AuraCore/` 只准 import Foundation（`IsolationTests` 白名單基準） |
| D-h | **（作廢，見 R-2）** 原為「digest 計算住 App 層＋注入縫」。reviewer 實測：`import CommonCrypto` 對 module 基準零影響（只有 `CryptoKit` 會多帶 `CryptoKit`＋`LocalAuthentication`），該裁決的一半前提不成立；而存完整內容本來就是我們真正要的語意 | 留下這一列不刪，是為了讓下一個讀到「為什麼不算 hash」的人看得到來龍去脈 |
| D-i | 寫入用 `open(path, O_CREAT\|O_EXCL\|O_WRONLY\|O_CLOEXEC, 0o644)`，**不是**先 `stat` 再寫 | 「只在不存在時寫」必須是**一個**原子動作。reviewer 實測四種佔用形狀（普通檔／目錄／symlink 指向 `config.toml`／斷鏈 symlink）**一律回 `EEXIST`**，且 `config.toml` 位元組不變 |
| D-j | `~/.codex` 不存在（或不是目錄）時，面板與 Options **完全沒有任何 Codex 元素** | 沒裝 Codex 的人畫面零 diff；既有的 `OptionsExpandTests`／`FooterPositionStabilityTests` 就是這個保證的守衛 |
| D-k | 新增三個 `PanelAction`：`.connectCodex`／`.disconnectCodex`（Options `.mount` 群組的**條件列**）／`.copyCodexSnippet`（進 `nonMenuKinds`）。**R-6 的「重新接上」重用 `.connectCodex`，不開第四個 action** | `nonMenuKinds` 有「恰好等於那四個」的字面集合 gate ——改它是**契約變更**，test-edit scrutiny 逐條列（§6.4）。重用既有 action 讓 94 個呼叫點的 fan-out 不再長大 |
| D-l | 「Codex」標籤放在列的**第一行**（`projectName` ＋ `meta` 那個既有 `HStack`），不另起一行 | `SessionsCardSizing` 的 43／59pt 由 `RowHeightDerivationTests` 從真實 view 推導。另起一行會改列高、裁掉唯一那一列——本 codebase 已踩過兩次的「凍住的數字」家族 |
| D-m | 接上成功的 banner **必須**同時說「下一個 Codex session 起生效」與「Codex 會問你一次是否信任」 | 沿用 D-m 既有教訓（不得寫「立即生效」）；F5 讓「已生效」在 Codex 上比在 Claude 上更不可宣稱 |
| D-n | 完整移除時，codex disconnect 必須排在 `erasePersistentDomain()` **之前** | 比對用的內容住在 persistent domain 裡，清掉之後我們就認不得自己寫的那個檔了。同既有 D-3 的理由 |
| D-o | `verify-uninstall.sh` 第 7 項用**內容判準**（檔案含 `--agent codex`） | 腳本跑的時候 persistent domain 已經清空，沒有比對基準可用 |
| D-p | `~/.codex` 自己是 symlink 時**不拒絕**，但寫入必須落在 `realpath` 底下且差異恰為 `{hooks.json}` | 使用者把 `.codex` 放別的磁碟是合理的；同既有 `ClaudeHomeSkillsSymlinkFixture` 的形狀 |
| D-q | `CodexObservation` 只在 `entryType == .regularFile` **且檔案 ≤ 64 KiB** 時才讀內容 | 我們產生的檔 ~2 KB；超過 64 KiB 的檔**不可能**是我們寫的，不讀它既便宜又等價 |
| **D-r** | `CodexState` 帶 associated value（`.blockedByBundlePath(Rejection)`）因此**不能 `CaseIterable`**；比照既有 `PanelAction`／`PanelActionKind` 的形狀，配一個平行的 `CodexStateKind: String, CaseIterable` ＋ `samples(_:)` 供 gate 推導定義域 | `PanelActionKind` 的 doc comment 逐字寫著「帶 associated value 不能 `CaseIterable`（實測編譯失敗）——這個平行型別供 gate 推導」。`samples(.blockedByBundlePath)` 回**兩種 Rejection 各一個**（同 `setLaunchAtLogin → [true, false]` 的 N7 理由：單一代表值時「一種有接、另一種沒接」照樣全綠） |
| **D-s** | `.blockedByBundlePath` 的兩種 Rejection **出路不同**：`.unsupportedCharacter` 給 snippet ＋「複製」（使用者可自行調整後手動貼）；`.mustMoveToApplications` **不給 snippet**，只給「把 App 移到『應用程式』」的指示 | translocated 的路徑是隨機臨時掛載點、下次開機就消失（`RunningBundle` doc comment 實測記載）——把那個路徑交給使用者複製貼上，等於發一張明天就過期的票。**這是對 R-5「複用 snippet 當出路」的細分，不是否決**（見 §11 待確認列） |

## 1. 目標與範圍

**做**：`--agent` 參數 · Codex 事件集合與 `Interrupt` 映射 · hooks.json 產生器（逐字 F14，唯一偏離 `timeout`）·
`CodexHookPathCheck`（路由層＋執行層雙用）· `CodexInstaller`（probe／connect／disconnect）·
`agent` 欄位貫穿 payload → 檔案 → state → UI 四段 · 面板列標籤 · Codex 區塊與 Options 列 ·
snippet 複製 · 內容憑證 ＋ round-trip 保證 · 搬家偵測與一鍵重接 · 完整移除納入 · 文件與正典回寫 · 全鏈接線 gate。

**不做**：Codex 的 `error` 狀態（沒有來源，F2／F4）· 互動 TUI 探針（`PermissionRequest`／`Interrupt`／
`Subagent*` 的形狀、hook 父行程的 `comm` 與 TUI 行程結構、含空白路徑＋引號的實測，全部在探針工具包待跑）·
分 agent 的聚合燈或分頁（L2 鎖定：一顆燈）· 動 `~/.codex/config.toml` · 動 Claude 側 `plugin/hooks/hooks.json` ·
自動偵測 Codex 是否已信任（F5：做不到）· 第三種 agent 的擴充機制（YAGNI）。

## 2. 架構總覽

```
Codex CLI ──(12 events, F2)──▶ ~/.codex/hooks.json ──▶ <abs>/aura-hook --agent codex  （形狀逐字 F14，timeout 3）
                                                              │ stdin: hook JSON (F3)
                                                              ▼
                             AgentArgument.agent(argv) ──▶ Agent(.codex)
                                                              │  getppid()（F15：session 內 pid 穩定）
        HookPayload(data:) ──▶ MergeRules.merge(payload, agent:) ──▶ SessionSnapshot(agent: "codex")
                                                              │  ~/.agentaura/sessions/<id>.json
                                                              ▼ （與 Claude 同一個目錄、同一條 FSEvents）
        PipelineGraph ──▶ SessionReducer ──▶ SessionState(agent:) ──▶ PanelRow(agentLabel:) ──▶ PanelRowView

RunningBundle.isTranslocated()/isInDownloads()（App 層唯一計算點）
        └──▶ CodexHookPathCheck.rejection(translocated:inDownloads:hookBinaryPath:) ──┬─▶ 路由層：CodexState
                                                （單一純函式，兩個消費者）           └─▶ 執行層：CodexInstaller.connect

CodexInstaller.probe() ──CodexObservation──▶ CodexState.from(_:recordedContents:currentExpectedContents:pathRejection:)
   ▲ connect(json:translocated:inDownloads:)             │
   │ disconnect(ifContentsEqual:)                        ├─ .unavailable         → 面板零 Codex 元素（D-j）
   └── CodexHooksJSON.json(hookBinaryPath:)              ├─ .notConnected        → 單行提示 ＋「接上 Codex」
       （純函式，事件清單從 codexEvents 推導）            ├─ .connected           → 「移除 Codex 掛載…」
                                                         ├─ .connectedStalePath  → 「App 移動過」＋「重新接上」
CodexHookStore（UserDefaults，存完整內容 ＋ round-trip）  ├─ .occupiedByOther     → snippet（不提供按鈕）
                                                         └─ .blockedByBundlePath → 解釋 ＋ 出路（不畫接上鈕）
```

| 單元 | 層 | 狀態 | 職責 |
|---|---|---|---|
| `Agent` | AuraCore | 新（`Agent.swift`） | `enum Agent: String, CaseIterable, Sendable { case claude, codex }`；`storedRawValue`（`.claude` → `nil`）；`init(stored:)`（nil／未知 → `.claude`）；`label`（`.claude` → nil） |
| `AgentArgument` | AuraCore | 新（同檔） | `static func agent(from argv: [String]) -> Agent`：純函式，支援兩種寫法，未知一律 `.claude` |
| `EventMapping` | AuraCore | 改 | `+ codexEvents`（12 個字面集合，F2）、`+ codexOnlyEvents = ["Interrupt"]`；`effect` 的 switch 加 `case "Interrupt": .setActivity(.idle)`。**`handledEvents` 一個字都不動** |
| `CodexHooksJSON` | AuraCore | 新 | `static let agentFlag = "--agent codex"`、`static let hookTimeoutSeconds = 3`（**單一常數**，12 個事件都從它推導）；`json(hookBinaryPath:) -> Data`；`snippet(hookBinaryPath:) -> String` |
| **`CodexHookPathCheck`** | AuraCore | **新（R-5）** | `enum Rejection { case mustMoveToApplications; case unsupportedCharacter(Character) }`；`static let unsupportedCharacters: Set<Character>`（空白／`'`／`"`／`$`／`` ` ``／`\`）；`static func rejection(translocated:inDownloads:hookBinaryPath:) -> Rejection?`。**零 I/O、零平台 API**——兩個布林由呼叫端注入 |
| `CodexObservation` | AuraCore | 新 | 純資料：`codexHomeIsDirectory`、`entryType`（`absent`／`regularFile`／`directory`／`symlink`／`other`）、`contents: Data?`（D-q）、`displayPath: String?` |
| `CodexState` | AuraCore | 新 | 六態（見 §3）；帶 associated value 所以**不** `CaseIterable`，配平行的 `CodexStateKind`（D-r）；`static func from(_:recordedContents:currentExpectedContents:pathRejection:)` **窮盡 switch**、零 I/O |
| `CodexFailure` | AuraCore | 新 | `Error`，**七個 case**：`codexHomeMissing`／`alreadyExists`／`writeFailed(Int32)`／`notOurs`／`unreadable(Int32)`／`mustMoveToApplications`／`unsupportedPathCharacter(Character)`。比照 `InstallerFailure` 住 AuraCore（文案要窮盡推導，m5-r2） |
| `CodexInstaller` | AuraHookFile | 新（獨立檔） | `Sendable`；欄位只有兩個 `URL`；`probe()`／`connect(json:translocated:inDownloads:) throws -> Data`／`disconnect(ifContentsEqual:) throws`。**只碰 `<codexHome>/hooks.json`** |
| `CodexHookStore` | App | 新 | `@MainActor` ＋ 注入 `UserDefaults`；key `AgentAuraCodexHookContents`（值＝寫出去的 JSON **文字**）；`contents: Data?`／`write(_ bytes: Data)`／`clear()`。**`Data` 進、`Data` 出，round-trip 有 gate**（CX31，M6-r2） |
| `PanelAction` / `PanelActionKind` | AuraCore | 改 | `+ .connectCodex`／`.disconnectCodex`／`.copyCodexSnippet`（含 `kind` 與 `samples`）。**不新增第四個**（D-k） |
| `OptionsMenuModel` | AuraCore | 改 | `rows(...)` 多吃 `codex: CodexState`；`.mount` 群組依狀態給列（§4.6 表）；`nonMenuKinds` 加 `.copyCodexSnippet` |
| `PanelModel` | AuraCore | 改 | `+ codex: CodexState`、`+ codexSnippet: String?`；`make(...)` 新參數**不給預設值**（既有 `panelModelMakeHasNoDefaults`） |
| `PanelRow` | AuraCore | 改 | `+ agentLabel: String?`（`.claude` → nil）；由 `PanelViewModel.row` 從 `SessionState.agent` 推導 |
| `SessionSnapshot` / `MergeRules` / `SessionReducer` / `SessionState` | AuraCore | 改 | `agent: String?` 一路帶到 `SessionState.agent: Agent`；`merge(...)` 多一個 `agent:` 參數（**無預設值**） |
| `CodexSectionView` | App | 新 | `.notConnected` 單行提示＋按鈕（R-3）；`.occupiedByOther` 說明＋snippet＋「複製」；`.connectedStalePath` 「App 移動過」＋「重新接上」；`.blockedByBundlePath` 解釋＋出路（D-s）。**不吃 `InstallState`** |
| `PanelRowView` | App | 改 | 第一行 `HStack` 內加標籤（D-l） |
| `AppDelegate+Codex.swift` | App | 新 | `codexInstaller`／`codexStore`／`codexState` 欄位；`reprobeCodex()`（§4.6 四個時機，並在這裡呼叫 `RunningBundle` 與 `CodexHookPathCheck`）／`performConnectCodex()`（含 stale 的 disconnect→connect）／`performDisconnectCodex()`／`performCopyCodexSnippet()` |
| `Uninstaller` | App | 改 | `run()` 在 `erasePersistentDomain()` 前多一步 codex disconnect（D-n） |

**設計選擇**
1. **一條資料流，兩個入口**：Codex 與 Claude 共用 `~/.agentaura/sessions/`、共用 `MergeRules`、共用聚合。
2. **兩份 hooks.json 各自的來源集合分離**（§4.2），都是 source-derived，沒有手維護的第二份清單。
3. **保本動作全部在執行層**（`O_EXCL`、`lstat`、逐位元組比對、路徑判定），不靠上層路由先擋——
   同 `Installer.guardWriteTarget()` 的既有理由（S0-1(ii)：只信路由層的話，拿掉執行層的檢查不會有任何測試變紅）。
4. **憑證存的就是它要比的東西**（R-2）：`UserDefaults` 存完整 JSON 文字，刪除前逐位元組比對。
   文字鍵保留可讀性（`defaults read` 看得到真正寫出去的那份），代價是 `Data → String → Data` 的
   round-trip，由 CX31 專門守（M6-r2：它壞掉的症狀是「完整移除留下殘留」，而 CLAUDE.md 逐字寫著
   「移除乾淨是測試能力的前提」）。
5. **「路徑能不能用」是一個判定、兩個消費者**（R-5）：`CodexHookPathCheck` 純函式，
   路由層拿它決定畫按鈕還是畫解釋，執行層拿它當 guard。**按了才失敗的按鈕比沒有按鈕更糟**，
   而這個 codebase 已經有現成的正確形狀（`InstallAffordance.explainOnly(reason)`）。

## 3. 資料模型

```swift
public enum Agent: String, Sendable, Equatable, CaseIterable {
    case claude, codex
    public init(stored: String?)            // nil／未知 → .claude
    public var storedRawValue: String?      // .claude → nil
    public var label: String?               // .claude → nil；.codex → "Codex"（產品名不進 L10n）
}
public enum AgentArgument { public static func agent(from argv: [String]) -> Agent }

extension EventMapping {
    public static let codexEvents: Set<String>      // 12 個（F2）
    public static let codexOnlyEvents: Set<String>  // ["Interrupt"]
}

public enum CodexHooksJSON {
    public static let agentFlag: String                         // "--agent codex"
    public static let hookTimeoutSeconds: Int                   // 3（R-4；12 個事件唯一來源）
    public static func json(hookBinaryPath: String) -> Data     // 逐字 F14，唯一數值偏離是 timeout
    public static func snippet(hookBinaryPath: String) -> String
}

public enum CodexHookPathCheck {                                // R-5
    public enum Rejection: Equatable, Sendable {
        case mustMoveToApplications
        case unsupportedCharacter(Character)
    }
    public static let unsupportedCharacters: Set<Character>     // " " ' " $ ` \
    public static func rejection(translocated: Bool, inDownloads: Bool,
                                 hookBinaryPath: String) -> Rejection?
}

public struct CodexObservation: Equatable, Sendable {
    public enum EntryType: Equatable, Sendable, CaseIterable { case absent, regularFile, directory, symlink, other }
    public let codexHomeIsDirectory: Bool
    public let entryType: EntryType
    public let contents: Data?          // 只有 regularFile 且 ≤ 64 KiB 才填（D-q）
    public let displayPath: String?
}

public enum CodexState: Equatable, Sendable {                   // 帶 payload → 不能 CaseIterable（D-r）
    case unavailable, notConnected, connected, connectedStalePath, occupiedByOther
    case blockedByBundlePath(CodexHookPathCheck.Rejection)
    public var kind: CodexStateKind                             // 窮盡 switch
    public static func samples(_ kind: CodexStateKind) -> [CodexState]   // blocked → 兩種 Rejection 各一
    public static func from(_ o: CodexObservation, recordedContents: Data?,
                            currentExpectedContents: Data,
                            pathRejection: CodexHookPathCheck.Rejection?) -> CodexState
}
public enum CodexStateKind: String, Sendable, CaseIterable {
    case unavailable, notConnected, connected, connectedStalePath, occupiedByOther, blockedByBundlePath
}
```

判定表（`CodexState.from`，窮盡、零 I/O；**由上而下第一個命中者勝**）：

| # | `codexHomeIsDirectory` | `entryType` | 磁碟 vs `recordedContents` | 磁碟 vs `currentExpectedContents` | `pathRejection` | → |
|---|---|---|---|---|---|---|
| 1 | false | 任意 | — | — | 任意 | `.unavailable` |
| 2 | true | `regularFile` | 兩者非 nil 且**逐位元組相等** | **相等** | 任意 | `.connected` |
| 3 | true | `regularFile` | 兩者非 nil 且**逐位元組相等** | **不等** | 任意 | **`.connectedStalePath`** |
| 4 | true | `regularFile` | 其餘（任一 nil／不等／> 64 KiB 沒讀） | — | 任意 | `.occupiedByOther` |
| 5 | true | `directory`／`symlink`／`other` | — | — | 任意 | `.occupiedByOther` |
| 6 | true | `absent` | — | — | **非 nil** | **`.blockedByBundlePath(r)`** |
| 7 | true | `absent` | — | — | nil | `.notConnected` |

**第 2／3 列排在第 6 列之前是刻意的**：磁碟上已經有我們的檔時，該講的是那個檔的狀態，
不是「你還不能接上」。translocated 的使用者若磁碟上有一份舊的我們的檔，
`currentExpectedContents` 會因為臨時掛載路徑而不同 → 落在第 3 列（`.connectedStalePath`）→
UI 說「App 移動過，要重新接上」→ 按下去 → **執行層 guard 以 `.mustMoveToApplications` 擋下並指名原因**。
這串順序本身就是正確的引導，不必在路由層再分一次岔。

`SessionSnapshot` 加 `public var agent: String? = nil`（CodingKey `agent`）。**必須是 Optional**——
理由與 `outstandingSubagents` 逐字相同。

`UserDefaults`（domain `io.agentaura.app`）新增**一個** key：`AgentAuraCodexHookContents` = 寫出去的 JSON 文字（~2 KB）。

## 4. 核心技術

### 4.1 `--agent` 參數（D-d）
`aura-hook/main.swift` 現在完全不解析 argv（39 行）。新增一行：
`let agent = AgentArgument.agent(from: CommandLine.arguments)`，往下傳給 `MergeRules.merge`。
解析規則：由左至右找第一個 `--agent <值>` 或 `--agent=<值>`；值與 `Agent.rawValue` **大小寫敏感**比對；
任何不匹配一律 `.claude`。**永不 `exit(非零)`、永不寫 stdout／stderr**（正典 Global Constraint）。

### 4.2 事件集合與 `Interrupt` 接縫（本 change 最容易踩的地方）

事實：
- Claude Code 對 `hooks.json` 是**全有全無**解析——多一個它不認識的事件名，整份 hooks `Failed to load`。
- `registeredEventsMatchHandledEvents` 是 `handledEvents` 與 `plugin/hooks/hooks.json` 鍵集合的**雙向等式**。
- 所以 **`Interrupt` 一旦進 `handledEvents`**，那條 gate 會要求 Claude 的 hooks.json 也註冊它，
  而那會讓 Claude 側整份 hooks 靜默失效——**一個「把對照表補齊」的善意動作，後果是產品對 Claude 使用者完全停止運作**。

處置：
1. `codexEvents`（12 個）是**獨立常數**，`codexOnlyEvents = ["Interrupt"]`。
2. `Interrupt` 加進 `EventMapping.effect` 的 switch（共用的映射函式），但**不進 `handledEvents`**。
   **前提（不是實測事實，要講清楚）**：F2 只說「Codex 的 12 個事件名與 Claude Code 同名同形」，
   它**沒有**回答「Claude Code 自己認不認得 `Interrupt`」。我們據以行動的是本專案既有的事實——
   `handledEvents` 的 19 個名字裡沒有它、Claude 側 hooks.json 從未註冊過它、
   而 Claude Code 對 hooks.json 是全有全無解析。CX5 守的就是「沒有註冊」，
   不需要先回答「Claude 認不認得」這個未量到的問題。
3. **`Interrupt` 事件 ≠ `is_interrupt` 欄位**（r1 m2）：`HookPayload.isInterrupt` 讀的是
   payload 裡的 `is_interrupt`（使用者 Ctrl+C 中斷了一個 **tool**，刻意不計入 `tool_failures`），
   與 Codex 的 `Interrupt` **事件**（使用者中斷了整輪）語意不同、來源不同、處置不同。
   兩者的 doc comment 都要互相點名。
4. 四條 gate 守這個接縫（CX2／CX3／CX4／CX5）。其中 **CX4 是 r1 B2 補上的**：
   `Interrupt → idle` 是本 change 唯一的新映射，而 `round4-codex.ndjson` **零筆 `Interrupt`**
   （只有 `SessionStart` 4／`UserPromptSubmit` 4／`Stop` 4／`SessionEnd` 4／`PreToolUse` 1／`PostToolUse` 1），
   沒有 CX4 的話，**把 `case "Interrupt"` 整行刪掉，全部 gate 維持綠**。
5. Codex 那邊反過來很寬容（F7），所以我們**刻意只給它 12 個**，不把 Claude 專屬的 8 個塞進去白付呼叫。

**後果（誠實列出）**：Codex 沒有 `PostToolUseFailure` 也沒有 `StopFailure`（F2），
`tool_response` 只是字串、沒有 exit code（F4）——**Codex 的 session 永遠不會讓燈變紅**（§10-2）。

### 4.3 hooks.json 產生器：逐字照 F14，唯一偏離是 `timeout`（R-1 ＋ R-4）

```
{
  "hooks": {
    "<event>": [ { "matcher": "", "hooks": [ { "type": "command",
                   "command": "<abs>/aura-hook --agent codex", "timeout": 3 } ] } ],
    ...（12 個，事件名排序）
  }
}
```
- 事件清單從 `codexEvents` 排序推導，**不寫第二份**；CX6 反向解析產出的 JSON 驗鍵集合恰等於它，
  **並且把 12 個事件的 entry 逐一逐字對 F14 比對**（m4-r2：不是抽樣一個。產生器若被人為某個事件
  做特例，12 選 1 的抽樣有 11/12 的機率看不到，而逐格比對的成本是同一個迴圈）。
- **`matcher: ""` 不可省**：F14 的「未測」欄第一項就是「省略 `matcher` 是否可行」。
  **不能拿 Claude 側當佐證**（m1-r2；reviewer r1 曾誤稱 Claude 的 19 個 entry 都帶 `matcher`，
  實際只有 `Notification` 一個帶）——Codex 與 Claude 是**兩個解析器**，F7 已經證明它們在
  寬容度上行為相反（Codex 忽略不認得的事件名，Claude 整份拒載），Claude 接受省略推論不到 Codex。
- **`timeout: 3`（R-4）——這是對 F14 唯一的數值偏離，理由與代價都寫在這裡**：
  - 目的：F13 證明 `SessionEnd`／`Interrupt` 的上限恰是 3 秒，寫 5 會讓 Codex 每個 session
    對這兩個事件印一次 `warning: clamping ... to 3s` 到使用者的 stderr。觀測性工具不該在
    使用者的終端機留下警告（正典 Global Constraint 的精神）。
  - **「3 不觸發警告」是推論不是事實**：我們從來沒有觀測過任何 ≤ 3 的值。三種結果都可承受——
    不警告（目的達成）／仍警告（行為與寫 5 完全相同，反正被 clamp 到 3，零損害）／
    被拒（無任何證據支持存在下限；真發生的話實機 ② 當場看得到：檔案寫了但 Codex 不觸發）。
  - **為什麼 12 個統一 3，而不是只給那兩個事件**：F13 只說那兩個有 3 秒上限，**沒說**其餘 10 個也是；
    其餘 10 個設 3 只是「遠低於未知上限」。更重要的是**產生器從單一常數
    `CodexHooksJSON.hookTimeoutSeconds` 推導**，逐事件不同值等於在產生器裡養第二份清單，
    違反本節自己的「不寫第二份」。
  - 代價（m2-r2）：clamping 警告是 F1 賴以斷言「檔案被解析、事件名被認得」的**唯一**不需要燈動
    就能確認「Codex 讀到了」的訊號，消掉它等於失去那個便宜的診斷。補償措施寫進
    `docs/INSTALL.md` troubleshooting：想確認 Codex 有沒有讀到，把 `timeout` 暫時改 5，
    下一個 session 的 stderr 會出現 clamping 警告，確認完改回 3。
  - CX6 為這個刻意偏離配一格自己的 mutation：**把 `timeout` 改回 5 → CX6 必須紅**。
- **不寫 `async`**：F14 的「未測」欄第二項。代價是每個事件同步等一次 `aura-hook`（實測 ~7 ms）。
- `command` **不加引號**：F14 驗證過的形狀是裸路徑。**路徑含特殊字元的行為未測**，
  所以我們在寫入之前就拒絕那些路徑（R-5／§4.4），而不是賭 Codex 怎麼解析。
- `snippet(hookBinaryPath:)`：**內容就是 `json(...)` 的文字形式**（同一個產生器，
  不是另外手寫一份示意——否則使用者貼上的跟我們自己寫的會漂移）。

### 4.4 路徑判定（R-5）與 `CodexInstaller` 的三個動作

**`CodexHookPathCheck.rejection(translocated:inDownloads:hookBinaryPath:)`**（AuraCore 純函式）：
1. `translocated || inDownloads` → `.mustMoveToApplications`。
   依據 `RunningBundle` 的 doc comment（實測）：Gatekeeper 把「從下載的 zip／DMG 直接雙擊」的 app
   跑在**唯讀、隨機命名的臨時掛載點，那個路徑下次啟動就消失**。本 repo 上一個 change 才剛做了
   雙擊安裝的 `.dmg`，**從掛載的 DMG 直接雙擊是新使用者最可能走的第一條路**。
2. 否則掃 `hookBinaryPath`，遇到第一個屬於 `unsupportedCharacters`（空白、`'`、`"`、`$`、`` ` ``、`\`）
   的字元 → `.unsupportedCharacter(那個字元)`。**掃描順序＝路徑字元順序**，所以訊息指名的是
   使用者最先看得到的那個字元。
3. 否則 `nil`。

**注意**：既有 `Installer.connect` 的 `mustMoveToApplications` 擋的**只有** translocated 與 `~/Downloads`，
**沒有**「必須在 `/Applications`」這個條件（`Installer+Connect.swift:42` ＋ `RunningBundle`）。
所以 `~/Applications/`、`~/My Apps/` 這類合法安裝位置**可以含空白**——
「幾乎永遠不觸發」不成立，這是一條會零星踩到、而踩到的人完全不知道為什麼的路徑（r2 M3）。

**兩個消費者，一個判定**：
- 路由層：`AppDelegate.reprobeCodex()` 呼叫 `RunningBundle.isTranslocated()`／`isInDownloads()`
  （App 層唯一計算點——`AuraHookFile` 的白名單沒有 `Security`），把 `pathRejection` 餵進 `CodexState.from`。
- 執行層：`CodexInstaller.connect(json:translocated:inDownloads:)` **第一行**再做一次同樣的判定，
  對應到 `CodexFailure.mustMoveToApplications`／`.unsupportedPathCharacter(c)`。
  兩層都要（§2 設計選擇 3 引的 S0-1(ii)）。

**三個動作**：
- **`probe()`**：`lstat(codexHome)` 判目錄 → `lstat(hooks.json)` 判 `entryType` →
  只有 `regularFile` **且 ≤ 64 KiB**（D-q）才 `open(..., O_RDONLY | O_NOFOLLOW)` 讀內容。
- **`connect(json:translocated:inDownloads:)`**：路徑 guard → `open(path,
  O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC, 0o644)`（D-i）→ 寫入 → `close` → 回傳寫出去的 `Data`。
  `codexHome` 不是目錄時 throw `.codexHomeMissing`（**不建立它**）。
  **`EEXIST` 一律 → `.alreadyExists`**（r1 m1 實測：四種佔用形狀**全部**回 `EEXIST`，
  沒有任何一種回 `EISDIR`——別把目錄那格路由到 `.writeFailed(EISDIR)`，UI 會給錯訊息）。
- **`disconnect(ifContentsEqual:)`**：`open(..., O_RDONLY|O_NOFOLLOW)` → `fstat` 確認 `S_IFREG` →
  讀 → **逐位元組比對** → 不符即 throw `.notOurs`（**不刪**）→ 相符 → **`unlink` 前再 `lstat`
  一次路徑，比對 `fstat` 拿到的 `(dev, ino)`，不同就放棄**（r1 m4）→ `unlink`。
  absent 視為已斷開，冪等成功。

**TOCTOU 誠實交代**：POSIX 沒有「內容相符才 unlink」的原子原語（macOS 也沒有 `funlinkat`），
比對與 `unlink` 之間有一個窄窗，已用同 fd 連續操作 ＋ `(dev, ino)` 二次確認縮到最小（§10-6）。
寫入那一側**沒有**這個問題（`O_EXCL` 本身就是原子的）。

### 4.5 內容憑證、round-trip 與完整移除（R-2 ＋ M6-r2）
- `connect` 成功 → app 層 `CodexHookStore.write(bytes)`；`disconnect` 成功 → `clear()`。
- **憑證的 round-trip 是一條獨立的失敗面**：`connect` 回 `Data`、`disconnect` 比對 `Data`，
  中間經過一個**文字**鍵。任何一處編碼不對等（換行正規化、`String(data:encoding:)` 回 nil 的邊界、
  `defaults` 對某些位元組的處理）都會讓 `disconnect` 永遠比不中 → `.notOurs` →
  **我們永遠刪不掉自己寫的檔** → 完整移除留殘留 → `verify-uninstall.sh` 第 7 項 FAIL。
  CLAUDE.md 逐字寫著「移除乾淨是測試能力的前提」，所以這條由 **CX31** 專門守：
  `store.write(bytes)` → `store.contents == bytes` 逐位元組，**輸入用真正的產生器輸出**
  （不是 `"{}"` 這種玩具）；mutation 在 `write` 裡加一次 `trimmingCharacters` → 必紅。
- `Uninstaller.run()` 的順序：`loginItem.set(false)` → `installer.disconnect()` →
  **`codexInstaller.disconnect(ifContentsEqual: store.contents)`（`try?`）** → `StateDirectoryEraser.erase` →
  `erasePersistentDomain()` → `recycleBundleAndTerminate()`。codex 那步**必須在清 domain 之前**（D-n），
  且與其他步驟一樣 best-effort（Lessons #8）。
- `scripts/verify-uninstall.sh` 第 7 項：`${CODEX_HOME:-$HOME/.codex}/hooks.json` 存在**且**含
  `--agent codex` → FAIL；存在但不含 → PASS；不存在 → PASS。
  **第 7 項必須可以被單獨執行**（`--only 7`）：腳本第 1–6 項查的是**真實** `$HOME`，
  在一台裝著 AgentAura 的開發機上本來就會 FAIL、整支腳本本來就非零退出——
  用「整體 exit code」當判準的 gate 對 mutation 不會紅；而且整支會跑 `osascript`（權限提示）
  與 `sfltool dumpbtm`（腳本自己註解寫實測 39 秒），與「連跑 3 次 0 flake」正面衝突。

### 4.6 面板與 Options

| `CodexState` | 面板 | Options（`.mount` 群組） |
|---|---|---|
| `.unavailable` | **什麼都不畫**（D-j） | 零列 |
| `.notConnected` | **單行提示 ＋ 按鈕**（R-3：一律如此，不看 Claude 的安裝狀態） | 恰一列「接上 Codex」（`.connectCodex`） |
| `.connected` | 不畫說明卡（列上有標籤就夠） | 恰一列「移除 Codex 掛載…」（`.disconnectCodex`） |
| **`.connectedStalePath`** | 「App 移動過，要重新接上」＋ 按鈕 | 恰**兩**列：「重新接上 Codex」（`.connectCodex`）＋「移除 Codex 掛載…」 |
| `.occupiedByOther` | 說明卡：「你已經有自己的 `~/.codex/hooks.json`，我們不會動它」＋ 可選取 snippet ＋「複製」 | 零列（沒有安全的一鍵動作可提供） |
| **`.blockedByBundlePath(.mustMoveToApplications)`** | 解釋：現在的位置（下載資料夾／從 DMG 直接開）下**寫進去的路徑下次開機就消失**；出路＝把 App 移到「應用程式」再回來。**不給 snippet**（D-s） | 零列 |
| **`.blockedByBundlePath(.unsupportedCharacter(c))`** | 解釋 ＋ **指名是哪個字元**（不是籠統的「路徑不支援」）；出路＝可選取 snippet ＋「複製」，讓使用者自行調整後手動貼（D-s） | 零列 |

**「重新接上」重用 `.connectCodex`**（D-k）：`performConnectCodex()` 看見目前是 `.connectedStalePath`
就先 `disconnect(ifContentsEqual:)`（走內容比對，安全）再 `connect`（走 `O_EXCL`）。
不開第四個 `PanelActionKind`，94 個呼叫點的 fan-out 不再長大。

**`reprobeCodex()` 的呼叫時機（r1 M4；沒有這一段，功能會是 tested≠wired）**：
`AppDelegate.refreshPanel()` 是 install 狀態的單一匯集點，`codexState` 同理。
`reprobeCodex()` **必須**在四個時機各呼叫一次：① `applicationDidFinishLaunching` 的同步區
（第一次 `refreshPanel()` **之前**）；② popover `onOpen`；③ `performConnectCodex()` 之後；
④ `performDisconnectCodex()` 之後。它內部依序做：`RunningBundle` 兩個布林 →
`CodexHookPathCheck.rejection(...)` → `installer.probe()` →
`CodexState.from(obs, recordedContents: store.contents, currentExpectedContents:
CodexHooksJSON.json(hookBinaryPath: 現在的路徑), pathRejection:)`。
`refreshPanel(icon:)` 把 `codex: codexState`、`codexSnippet:` 一併帶進 `PanelModel.make`。
**後果若漏接**：使用者裝了 Codex、開面板、什麼都沒有，重開 app 才出現——而全套測試綠。
CX24 第五段守這個。

接上成功的 banner（D-m，兩句都要有）：**「已接上 Codex · 下一個 Codex session 起生效；
Codex 啟動時會問你一次是否信任這個 hook，要按同意才會生效。」**

### 4.7 liveness 與 hook 的父行程（F15；r1 B3、r2 M1）

`aura-hook` 記的是 `getppid()` 與它的 start time，`SessionReducer.resolveLiveness` 要求那個 pid
仍活著，否則整列直接 `.ended`。對 Claude Code 這是量過的；對 Codex 由 **F15** 部分回答。

**已證實（F15）**：五個 session、24 筆事件，每個 session 內所有事件的 `$PPID` 完全相同
（跨 4–6 筆、數秒到數十秒），不同 session 則不同。因此——
(i) 呼叫 hook 的**不是每個事件開一次的短命 shell**；
(ii) 那個行程至少活過「第一個事件到最後一個事件」。
**結論：`getppid()` 判活的前提（pid 在 session 期間穩定）對 Codex 成立**，
這正是 r1 B3 最關鍵的那一格。

**範圍限定（F15，不是細節）**：那五個 session **全部跑在 `codex exec`**。
產品要服務的是**互動 TUI**（F10 說 `waiting` 只在互動 TUI 出現，實機 ③④ 也都要求互動 session）。
exec 模式的行程結構不等於 TUI 模式的——TUI 完全可能由一個常駐的 app 行程 fork 出 session，
那正是下面 fallback 段假設的情況。**實機 ③ 要順帶記 `ps -o ppid=,comm=`。**

**未觀測（F15）**：(a) `SessionEnd` **之後**那個 pid 是否結束——「隨 session 結束」是推論不是事實
（實務後果有限：`resolveLiveness` 的第一個 guard 就是 `!s.terminated`，而 `SessionEnd` 會設它）；
(b) 那個 pid 是 `codex` 原生二進位還是 npm 的 node 啟動器。兩者都列 §10-8。

**預寫的 fallback 決策點**（若實機 ③ 發現父行程其實是跨 session 的常駐行程）：
`--agent codex` 時**不寫 pid**（`MergeRules` 收到的 `pid`／`pidStartedAt` 傳 nil），
改由 `SessionEnd` 的 `terminated` 單獨判死。代價是「terminal 被強制關掉、`SessionEnd` 沒來」
那條路徑在 Codex 上失去保護。**這條現在不做**，寫下來是為了實機失敗時不必重新設計。

## 5. 錯誤處理

| 情況 | 處理 |
|---|---|
| `--agent` 未知值／缺值／重複 | 落回 `.claude`；靜默、exit 0、零輸出 |
| 磁碟上 `agent` 是未知字串／非字串／`null` | `Agent(stored:)` 落回 `.claude`；**整包仍解得開**；那一列沒有標籤 |
| 舊版狀態檔沒有 `agent` 鍵 | `decodeIfPresent` → nil → `.claude`（CX11） |
| `~/.codex` 不存在／是普通檔／是斷鏈 symlink | `.unavailable`；**不建立它**；面板零 Codex 元素 |
| **App 是 translocated 或在 `~/Downloads`** | 路由層 → `.blockedByBundlePath(.mustMoveToApplications)`（不畫接上鈕）；執行層 → `CodexFailure.mustMoveToApplications`。**不寫任何檔** |
| **hook 路徑含空白／`'`／`"`／`$`／`` ` ``／`\`** | 路由層 → `.blockedByBundlePath(.unsupportedCharacter(c))`，訊息**指名那個字元**；執行層 → `CodexFailure.unsupportedPathCharacter(c)`。出路＝snippet ＋「複製」 |
| `~/.codex/hooks.json` 已存在（普通檔／目錄／symlink／斷鏈 symlink） | `connect` 一律 throw `.alreadyExists`（四種形狀都是 `EEXIST`）；**那個路徑（含 symlink 指向的目標）位元組與型別完全不變**（CX15 逐格斷言，含「symlink 指向 `config.toml`」這最惡毒的一格） |
| `hooks.json` 存在但內容對不上（或 > 64 KiB 沒讀） | `.occupiedByOther`；不提供刪除按鈕；`disconnect` 若被呼叫一律 throw `.notOurs` |
| **磁碟內容 == 憑證但 != 現在路徑的預期內容**（App 搬家／改名） | `.connectedStalePath`；UI 說「App 移動過，要重新接上」；一鍵重接 = disconnect（內容比對）→ connect（`O_EXCL`） |
| 憑證遺失（使用者清過偏好設定） | `.occupiedByOther`（保守：認不得就不碰）；UI 顯示 snippet 與「這個檔不是我認得的那份」 |
| `connect` 寫入失敗（權限、磁碟滿） | throw `.writeFailed(errno)` → banner 顯示；**不重試、不 fallback 到非原子寫法** |
| 讀 `hooks.json` 失敗（權限） | `.occupiedByOther`（讀不到不等於不存在） |
| Codex 未信任 hook（F5） | **偵測不到**。UI 不得宣稱已生效；help／INSTALL 寫明「燈不動的第一件事是檢查 Codex 有沒有問過你信任」 |
| 收尾步驟（codex disconnect）在完整移除中失敗 | `try?` 吞掉，後面的步驟照跑（Lessons #8）；`verify-uninstall.sh` 第 7 項會把殘留說出來 |

## 6. 測試策略

T01 先行（測試＋compile-only stub，零生產碼，禁 `fatalError`）。swift-testing（`import Testing`）。
**測試中絕不跑 `codex exec`**（F12）、**絕不碰真的 `~/.codex`／`~/.claude`**。

### 6.1 對抗式 double（Lessons #1；T01 必含）
1. **payload**：缺 `permission_mode`／缺 `model`／`tool_response` 是 200 KB 字串／
   `hook_event_name: "Interrupt"` **帶** `agent_id`／`session_id` 是 UUIDv7。
2. **argv（7 格表）**：`[]`、`["--agent"]`、`["--agent","gemini"]`、`["--agent","CODEX"]`、
   `["--agent=codex"]`、`["--agent","codex","--agent","claude"]`、`["--agent","codex","--agent"]`。
   **這張表是 CX7 與 CX8 共用的唯一來源**。
3. **檔案系統**：`~/.codex/hooks.json` 是**目錄**／是**symlink 指向 `config.toml`**／是斷鏈 symlink／
   是別人的合法 JSON／是 5 MB 的垃圾（> 64 KiB，驗 D-q 不讀它）；`~/.codex` **自己**是 symlink
   指到 codexHome 之外；`~/.codex` 是普通檔；`~/.codex` 不存在。
4. **路徑（R-5）**：`translocated: true`／`inDownloads: true`／六個不支援字元各一條路徑／
   **同時含兩種問題**（translocated ＋ 含空白，驗優先序）／乾淨路徑（負對照）。
5. **`FakeCodexStore`**：可設定「寫進去與讀回來不一致」——守的是「store 壞掉時我們不會誤刪別人的檔」。
6. **`FakeCodexInstaller`**：① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
   ② `disconnect()` 宣稱成功但檔案還在；③ `probe()` 丟錯；④ 記錄 `connect`／`disconnect`／`probe`
   的**呼叫順序與次數**（CX24 第五段與 CX35 要用）。

### 6.2 composition-root smoke（spec §5.2 的既有形狀）
- `codexInstallerIsInjected`：真 `AppDelegate` 啟動後 `codexInstaller`／`codexStore` 非 nil。
- `productionCodexHomeIsRealHome`：生產預設 `codexHome` == `FileManager.default
  .homeDirectoryForCurrentUser.appendingPathComponent(".codex")`；**外加**來源掃描
  `Sources/` 不得用 `environment["HOME"]` 算它。
- `codexConnectChainIsWired`：五段（CX24）。
- `codexRowsReachTheView`：`.notConnected` 時真的渲出按鈕；`.unavailable` 時面板的
  `preferredContentSize` 與零 Codex 狀態**完全相同**。

### 6.3 Gate 表（本 change 新增一律 `CX<n>`，共 **35** 條；既有 gate 寫測試函式名）

| Gate | 層 | 守什麼 | Mutation（→ 指名測試 ≤60s 變紅） |
|---|---|---|---|
| CX1 `codexEventSetIsPinnedToProbe` | AuraCore | `codexEvents` 恰等於 F2 的 12 個字面名。**doc comment 分標兩種證據強度**：六個有 `round4-codex.ndjson` 的真實 payload；`PermissionRequest`／`Interrupt`／`SubagentStart`／`SubagentStop`／`PreCompact`／`PostCompact` 只有二進位字串 `HookEventsToml` 列舉 | 加一個／少一個 |
| **CX2 `interruptNeverEntersHandledEvents`** | AuraCore | `handledEvents.isDisjoint(with: codexOnlyEvents)`；失敗訊息逐字寫「Claude 全有全無」 | 把 `Interrupt` 加進 `handledEvents` |
| CX3 `codexSharedEventsReuseClaudeMapping` | AuraCore | `codexEvents − codexOnlyEvents ⊆ handledEvents`，且每個 `effect` 非 `.noChange` | 從 `handledEvents` 拿掉 `PreCompact` |
| **CX4 `codexOnlyEventsMapToIdle`** | AuraCore | 定義域**從 `codexOnlyEvents` 推導**（不寫 `"Interrupt"` 字面），逐個斷言 `effect == .setActivity(.idle)`。**這是 `Interrupt → idle` 唯一的守衛** | 刪掉 `case "Interrupt"` 整行 |
| CX5 `claudeHooksJSONHasNoInterrupt` | AuraCore | `plugin/hooks/hooks.json` 不含 `Interrupt`（獨立於既有 `registeredEventsMatchHandledEvents`） | 在 Claude hooks.json 加 `Interrupt` |
| **CX6 `codexHooksJSONMatchesF14Verbatim`** | AuraCore | ① `hooks` 鍵集合 == `codexEvents`；② **12 個事件的 entry 逐一逐字等於 F14**（`matcher: ""`、`type`／`command`，**沒有** `async`），**唯一數值偏離是 `timeout` 5→3**，失敗訊息要帶 F13 的 clamping 引文說明為何偏離；③ 乾淨路徑產出可解析且 `command` round-trip | ① 寫死 11 個事件 ② 拿掉 `matcher` ③ 加 `async: true` ④ `command` 漏 `--agent codex` ⑤ **`timeout` 改回 5** |
| CX7 `agentArgumentParsing`（對抗式） | AuraCore | §6.1(2) 的 7 格表逐格 | 未知值改成回 `.codex` |
| CX8 `auraHookStaysSilentForEveryAgentArgument` | E2E（真 spawn） | **同一張 7 格表**，`SpawnGate` 內序列跑：每格 exit 0、stdout 空、stderr 空 | 解析失敗時寫 stderr |
| CX9 `claudeStateFileHasNoAgentKey` | AuraCore | 用 round1／round1b／round2／round3 跑 merge，序列化後**不含** `agent` 鍵 | `.claude` 也寫 `"claude"` |
| CX10 `codexStateFileCarriesAgent` | E2E（真 spawn） | `--agent codex` 真跑 → 檔案含 `"agent":"codex"`，`SessionState.agent == .codex` | `main.swift` 忘了傳 agent |
| CX11 `legacySnapshotWithoutAgentDecodes` | AuraCore | 無 `agent` 鍵的舊 JSON 解得開且 `.claude` | `agent` 改成非 Optional |
| CX12 `unknownAgentFallsBackWithoutFailingDecode` | AuraCore | `"agent":"gemini"` → 整包解得開、`.claude`、無標籤 | `agent` 改成 `Agent?`（enum） |
| CX13 `round4FixtureParsesAndMatchesProbeTable` | AuraCore | 18 筆全部解析；每筆 `effect` 與探針欄位表一致；`isSafeSessionID` 全過；探針表的每個欄位至少出現一次 | **`Stop` 改成 `.noChange`**（fixture 有 4 筆，真的踩得到） |
| **CX14 `codexInstallerTouchesOnlyHooksJSON`** | AuraHookFile | `codexHome` 整棵樹前後快照差異**恰為** `{hooks.json}`；植入的 `config.toml` 位元組完全不變 | connect 順手寫 `hooks.json.bak` |
| **CX15 `codexConnectRefusesEveryOccupiedShape`**（對抗式） | AuraHookFile | §6.1(3) 的佔用形狀各 throw `.alreadyExists`，**且該路徑（含 symlink 目標）位元組與型別不變** | 拿掉 `O_EXCL`（symlink→`config.toml` 那格必須紅） |
| CX16 `codexConnectWritesGeneratorBytes` | AuraHookFile | 成功路徑：檔案內容 == 產生器位元組；回傳值 == 那些位元組 | connect 少寫最後一個 byte |
| CX17 `codexDisconnectOnlyRemovesOurBytes` | AuraHookFile | 逐位元組相符才刪；改一個 byte → 不刪＋throw；`ifContentsEqual` 為 nil → 不刪；`(dev,ino)` 被換掉 → 不刪 | ① 拿掉內容比對 ② 拿掉 `(dev,ino)` 複查 |
| CX18 `codexHomeSymlinkWritesInsideResolvedPath` | AuraHookFile | `~/.codex` 是外部 symlink：字面樹不變、`realpath` 樹差異恰為 `{hooks.json}` | 快照改用字面路徑 |
| CX19 `codexStateCoversEveryObservationShape` | AuraCore | `CodexState.from` 對 §3 判定表逐格；定義域由 `EntryType.allCases × {磁碟 vs 憑證 三態} × {磁碟 vs 現在預期 二態} × `codexHomeIsDirectory` × {pathRejection nil／兩種}` **推導**，不寫格數 | ① 把 `symlink` 併進 `.notConnected` ② 判定表第 2／3 列對調（stale 永遠不出現） |
| CX20 `codexRowsAppearOnlyWhenAvailable` | AuraCore | 逐 `CodexStateKind` 斷言列數與 action：`.unavailable`／`.occupiedByOther`／`.blockedByBundlePath` 各**零列**；`.notConnected`／`.connected` 各**恰一列**；`.connectedStalePath` **恰兩列**且第一列的 action 是 `.connectCodex` | ① `.unavailable` 也給「接上 Codex」 ② `.blockedByBundlePath` 給一列 |
| CX21 既有 `optionsRowsCoverEveryAction` ＋ `nonMenuKindsIsExactlyThatLiteralSet` 擴充 | AuraCore | 代表狀態集合改由 `CodexStateKind.allCases.flatMap(CodexState.samples)` 推導；`nonMenuKinds` 字面集合四個 → 五個 | 把 `.connectCodex` 塞進 `nonMenuKinds` |
| CX22 `agentLabelOnlyForNonClaude` | AuraCore ＋ 像素 | model：claude → nil、codex → "Codex"；像素：同一列 claude vs codex `differingPixels > 0` | 標籤對 claude 也給值 |
| **CX23 `codexLabelDoesNotChangeRowHeight`** | App（離屏） | 帶標籤的列高仍是 43／59pt（±0.5），`SessionsCardSizing` 兩個常數對 codex 列同樣成立 | 標籤另起一行 |
| **CX24 `codexConnectChainIsWired`**（smoke） | App | 五段各自失敗訊息：① `.connectCodex` 有接線 ② fake installer 真的收到 `connect` ③ **憑證進 suite 後取回來是同一串位元組**（不是「非 nil」，M6-r2）④ banner 文字含「下一個 session」與「信任」兩個關鍵詞（從 `L10nCodex` 的鍵推導）⑤ spy 記 `probe()` 次數，`onOpen` 之後 ≥ 1 | ① `.connectCodex` 分支改 `break` ② banner 只留一句 ③ 拿掉 `onOpen` 裡的 `reprobeCodex()` |
| CX25 `productionCodexHomeIsRealHome`（smoke ＋ 來源掃描） | App ＋ AuraCore | §6.2 第二條 | 改成 `environment["HOME"]` |
| CX26 `uninstallRemovesCodexBeforeErasingDefaults` | App | Fake 記錄呼叫順序：codex disconnect **早於** `removePersistentDomain` | 兩步對調 |
| CX27 `verifyUninstallScriptDetectsOurCodexHooks` | script | 暫存 `CODEX_HOME` ＋ **`--only 7`**：含 `--agent codex` → 該項那一行 FAIL；別人的檔 → 該行 PASS。**判準是那一行，不是整體 exit code** | 拿掉腳本第 7 項 |
| CX28 `helpDocsCoverCodexRows` | 文件 | 既有 `HelpDocOptionsRowCoverageTests.allRows` 改成對 `CodexStateKind.allCases` 取**聯集**，兩個語言各自守 | **只刪掉其中一個標題**（例如只刪「重新接上 Codex」）也必須紅 |
| CX29 `securityDocListsEveryPathWeWrite` | 文件 | `README.md`／`SECURITY.md` 必須含 `.codex/hooks.json`（字面來自生產常數） | 從 SECURITY.md 刪掉那一行 |
| CX30 `noCodexExecInRepo` | 全 repo | `Tests/`／`scripts/` 不得出現 `codex exec`（＋暫存目錄正向對照） | 在腳本裡加一行 `codex exec` |
| **CX31 `codexHookStoreRoundTripsBytes`** | App | `store.write(bytes)` → `store.contents == bytes` **逐位元組**；輸入用**真正的產生器輸出**，不是 `"{}"` | 在 `write` 裡加 `trimmingCharacters` |
| **CX32 `codexConnectRefusesBlockedBundlePath`** | AuraHookFile | 注入 `translocated: true`（與 `inDownloads: true`、含空白路徑各一）→ throw 對應的 `CodexFailure`，**且 `codexHome` 整棵樹零差異**（沿用 CX14 的 `DirectoryTreeSnapshot`） | 拿掉 `connect` 第一行的 guard |
| **CX33 `codexPathCheckNamesTheOffendingCharacter`** | AuraCore | `unsupportedCharacters` 六個字元逐格（定義域從那個集合推導）；`Rejection` 帶的是路徑中**第一個**命中的字元；translocated ＋ 含空白時**優先**回 `.mustMoveToApplications`；乾淨路徑回 nil | ① 回傳籠統的 `.unsupportedCharacter(" ")` 不論實際字元 ② 優先序對調 |
| **CX34 `codexStalePathIsDetectedAndOffersReconnect`** | AuraCore | 磁碟 == 憑證 != 現在預期 → `.connectedStalePath`（三者都用真正的產生器輸出，兩個不同路徑）；該狀態的第一列 action 是 `.connectCodex` | `from` 忽略 `currentExpectedContents` |
| **CX35 `stalePathReconnectDisconnectsBeforeConnecting`**（smoke） | App | `.connectedStalePath` 下送 `.connectCodex` → fake installer 記錄的呼叫順序是 `disconnect` → `connect`；`.notConnected` 下只有 `connect` | 直接 `connect`（不先 disconnect）→ 順序斷言紅 |
| 既有全部 gate | — | 繼續綠（尤其 `registeredEventsMatchHandledEvents`、`fileLengthLimit`、`nonUITargetsLoadNoUIModules`、`noStrayLiteralOutsideAllowlist`、`panelModelMakeHasNoDefaults`、`RowHeightDerivationTests`、`FooterPositionStabilityTests`） | — |

### 6.4 test-edit scrutiny 預告（Lessons #3）
1. `OptionsMenuModelTests.nonMenuKindsIsExactlyThatLiteralSet`：四個 → 五個。
   **契約變更不是弱化**——集合仍是「恰好等於」，只多了一個有理由的成員（D-k）。
   **連帶**：`Sources/AuraCore/OptionsMenuModel.swift` 的 doc comment 逐字寫著「字面集合恰為這四個」，
   生產碼註解也要一起改。
2. `PanelModel.make` 新增無預設值參數 → **61 個呼叫點（26 個檔）**全部要加 `codex:`／`codexSnippet:`。
   測試呼叫點一律傳 `.unavailable`／`nil`（＝現況行為），生產呼叫點傳真實狀態。
3. `MergeRules.merge` 新增無預設值 `agent:` → **7 個呼叫點**；測試一律傳 `.claude`。
4. `OptionsMenuModel.rows` 新增無預設值 `codex:` → **26 個呼叫點（10 個檔）**，
   含 `L10nProductionCallSitesPassLanguageTests`（一條來源掃描 gate）與 `HelpDocOptionsRowCoverageTests`。
5. 上面 2／3／4 三批合計 94 個呼叫點：**`#expect` 淨數量不得下降**，報告附改前／改後總數（基準 1652）。
6. `HelpDocOptionsRowCoverageTests.allRows` 改成對 `CodexStateKind.allCases` 取聯集。
7. `ClaudeHomeTreeSnapshot` 的 walk／entry 抽成共用 `DirectoryTreeSnapshot`（CX14／CX32 共用）——
   **純重構**：既有 `installerTouchesOnlyAllowedPaths` 兩條測試必須全綠，
   且它的 mutation 要**當場重跑一次**確認仍然精準紅。

### 6.5 已知不可測（寫進 §10 與最終報告）
- Codex 是否真的載入並執行我們寫的 hooks.json（F12 禁止自動化跑 `codex exec`）→ 實機 ②③。
- 信任提示的 UX 與「拒絕信任」的行為（F5）→ 實機 ④。
- `PermissionRequest`／`Interrupt`／`Subagent*` 的實際 payload 形狀（F10）→ 互動探針。
- hook 父行程的 `comm` 與**互動 TUI 的行程結構**（F15 範圍限定）→ 互動探針 ＋ 實機 ③ 順帶記錄。
- 含空白路徑＋引號的 `command` 是否可行（R-7）→ 互動探針工具包（已備好，argv `--agent codex-quoted`）。

## 7. DoD

門檻與量法見 `docs/superpowers/plans/2026-09-18-codex-support-dod.md`（每條有數字）。

## 8. 檔案佈局與回寫

### 8.1 檔案（估行；`Sources/` 基準 7846 行）
```
Sources/AuraCore/Agent.swift                       新  ~60（Agent ＋ AgentArgument）
Sources/AuraCore/EventMapping.swift                改  +25（codexEvents／codexOnlyEvents／Interrupt case）
Sources/AuraCore/CodexHooksJSON.swift              新  ~80（逐字 F14，每個鍵的出處與 timeout 偏離的理由）
Sources/AuraCore/CodexHookPathCheck.swift          新  ~55（R-5 純函式 ＋ Rejection）
Sources/AuraCore/CodexState.swift                  新  ~110（CodexObservation ＋ CodexState ＋ CodexStateKind
                                                        ＋ samples ＋ CodexFailure；逼近 200 就把 CodexFailure 拆檔）
Sources/AuraCore/SessionSnapshot.swift             改  +10
Sources/AuraCore/MergeRules.swift                  改  +6
Sources/AuraCore/SessionReducer.swift              改  +2
Sources/AuraCore/SessionState.swift                改  +5
Sources/AuraCore/PanelViewModel.swift              改  +6（PanelRow.agentLabel）
Sources/AuraCore/PanelAction.swift                 改  +25（三個 case × kind × samples）
Sources/AuraCore/OptionsMenuModel.swift            改  +24（六態的列 ＋ 註解修正）
Sources/AuraCore/PanelModel.swift                  改  +14
Sources/AuraCore/L10nCodex.swift                   新  ~130（雙語；含兩種 Rejection ＋ stale ＋ 七個 CodexFailure）
Sources/AuraHookFile/CodexInstaller.swift          新  ~125（欄位兩個 URL ＋ 路徑 guard）
Sources/AuraHookFile/CodexInstaller+Probe.swift    新  ~70
Sources/aura-hook/main.swift                       改  +3
Sources/AgentAuraApp/CodexHookStore.swift          新  ~45
Sources/AgentAuraApp/CodexSectionView.swift        新  ~120（六態分支）
Sources/AgentAuraApp/AppDelegate+Codex.swift       新  ~110（reprobe ＋ 四個 perform ＋ stale 的 disconnect→connect）
Sources/AgentAuraApp/AppDelegate+Links.swift       新  ~45（**純搬移**，為 AppDelegate+PanelActions 騰行數）
Sources/AgentAuraApp/AppDelegate+PanelActions.swift 改 −45 +8
Sources/AgentAuraApp/PanelView.swift               改  +8（列標籤 ＋ 掛 CodexSectionView）
Sources/AgentAuraApp/Uninstaller.swift             改  +8
Sources/AgentAuraApp/AppDelegate.swift             改  +10
                                                   合計 ≈ +975（門檻 1050，§7；r2 是 810，R-5／R-6 各約 +80）
Tests/AuraCoreTests/Fixtures/round4-codex.ndjson   已就位（18 筆／4 個 session，唯讀證據）
Tests/AuraCoreTests/AgentArgumentTests.swift、CodexEventSeamTests.swift、CodexHooksJSONTests.swift、
  CodexHookPathCheckTests.swift、CodexStateTests.swift、CodexOptionsRowTests.swift、
  CodexInstallerTests.swift、CodexInstallerClobberTests.swift、CodexPathScopeTests.swift、
  Round4FixtureTests.swift、AgentSnapshotCodableTests.swift                     新
Tests/AuraCoreTests/Support/DirectoryTreeSnapshot.swift  新（從 ClaudeHomeTreeSnapshot 抽出，純重構）
Tests/AgentAuraAppTests/CodexWiringSmokeTests.swift、AppDelegateCodexWiredTests.swift、
  CodexHookStoreTests.swift、CodexRowLabelPixelTests.swift、CodexSectionRenderTests.swift  新
Tests/AgentAuraAppTests/Support/FakeCodexInstaller.swift、FakeCodexStore.swift  新
scripts/verify-uninstall.sh                        改（第 7 項 ＋ CODEX_HOME ＋ --only ＋ 第 2 行註解修正）
```

**單檔上限的六個風險點**（動工前就知道，不是驚喜）：

| 檔案 | 現況行數 | 上限 | 計畫要加什麼 | 處置 |
|---|---|---|---|---|
| `Sources/AgentAuraApp/AppDelegate+PanelActions.swift` | **200** | 200 | 三個新 case ＋ `refreshPanel` 帶 codex | T10 第一步預先搬移 |
| `Tests/AuraCoreTests/OptionsMenuModelTests.swift` | **300** | 300 | CX20／CX21 ＋ `rows(` 新參數 | T07 第一步拆 `CodexOptionsRowTests.swift` |
| `Tests/AgentAuraAppTests/AppDelegatePanelActionsWiredTests.swift` | **300** | 300 | `panelActionsAreWired` 涵蓋 3 個新 kind | T10 第一步拆 `AppDelegateCodexWiredTests.swift` |
| `Tests/AuraCoreTests/MergeRulesTests.swift` | 294 | 300 | `merge(` 新參數（1 處） | 餘裕 6 行；超了就拆 |
| `Tests/AuraCoreTests/PanelViewModelTests.swift` | 288 | 300 | CX22 的 model 半 | 餘裕 12 行；寫不下就放 `CodexRowLabelPixelTests` |
| `Sources/AuraCore/CodexState.swift`（新） | — | 200 | 六態 ＋ `CodexStateKind` ＋ `samples` ＋ `CodexFailure` | 估 ~110；逼近 200 就把 `CodexFailure` 拆成獨立檔 |

### 8.2 回寫（逐句）
| 位置 | 改為 |
|---|---|
| 正典 §2.2 event → activity 對照表 | 加一列 `Interrupt → idle`，註明「Codex only，**不得**進 `handledEvents`（Claude 全有全無）」；並點名它與 payload 欄位 `is_interrupt` 是兩件事 |
| 正典 §2.1 檔案契約 | 加 `agent`（Optional，nil = claude）欄位說明與 D-a／D-c 的理由 |
| 正典 §3.2 安裝機制 | 加一段「第二個入口：Codex 讀 `~/.codex/hooks.json`（F1、F14），只在它不存在時寫、只在內容相符時刪、絕不碰 `config.toml`；bundle 路徑不合法時不寫、改畫解釋」 |
| 正典 §3.5 pid liveness | 加「Codex 的 hook 父行程在 session 內 pid 穩定（F15，**exec 模式實測**），`getppid()` 判活的前提成立；互動 TUI 的行程結構與 `comm` 未辨識」 |
| 正典 §3.7 面板內容 | 加「非 Claude 的 session 在列的第一行帶 agent 標籤；聚合燈不分 agent」 |
| 正典 §9 開放風險 | 加「Codex 無 error 來源」「無法偵測信任狀態」兩條 |
| `CLAUDE.md` Invariants | 加「`CodexInstaller` 只准碰 `<codexHome>/hooks.json`；`config.toml` 位元組不得變動」「`Interrupt` 不得進 `handledEvents`」 |
| `CLAUDE.md` Tier 1 清單 | 加 `Sources/AgentAuraApp/CodexSectionView.swift`、`AppDelegate+Codex.swift`、`Sources/AuraCore/CodexState.swift` |
| `CLAUDE.md` Project 狀態 | 加 codex-support 一行 |
| `README.md` §「What it does to your Mac」 | 加 `~/.codex/hooks.json`（只在你按下按鈕時建立、只在內容仍是我們寫的那份時刪除） |
| `README.zh-TW.md` 對應段 | 同步 |
| `SECURITY.md` §「What this tool can do on your machine」＋「Boundaries that are enforced by tests」 | 加 `~/.codex/hooks.json` 與「`config.toml` 位元組不變」。**注意**：`SECURITY.md` 沒有叫「What it does to your Mac」的段落，那是 `README.md:160` |
| `docs/INSTALL.md` ＋ `.zh-TW` | 新增「Using it with Codex」一節（前提、按哪裡、**Codex 會問你信任**、生效時機、怎麼移除）；troubleshooting 加兩條：①「燈不動？先確認 Codex 有沒有問過你信任」②「想確認 Codex 到底有沒有讀到這個檔：把 `timeout` 暫時改成 5，下一個 session 的 stderr 會出現 clamping 警告；確認完改回 3」（m2-r2） |
| `Resources/help-english.html` ／ `help-traditionalChinese.html` | 新增「Codex」段（CX28 強制涵蓋**每一個**新的 Options 列標題，含「重新接上 Codex」） |

## 9. Persona Impact

- **只用 Codex、不用 Claude Code 的人**：Claude 側是 `.notConnected`（大版說明佔滿），
  Codex 的提示在它下面。R-3：Codex 卡片**一律單行提示＋按鈕**。
  persona 要回答「兩個東西疊在同一張畫面上時，第一次看得懂要按哪個嗎」。
- **兩個都用的人**：列上只有 Codex 有標籤。同一個專案目錄同時跑兩邊時，兩列的 `projectName`
  一模一樣，**只靠標籤區分**——persona 要回答「這樣夠不夠」。
- **已有自己 `~/.codex/hooks.json` 的進階使用者（P2）**：最在意「它會不會蓋掉我的」。
  畫面必須先講「我們不會動它」，再給 snippet；snippet 必須可選取、可一鍵複製，
  且**內容就是我們自己會寫的那份**。**R-5 之後 P2 多兩條具體要求**（不另開硬下限，
  含特殊字元的路徑是稀有分支，硬下限會稀釋 P1–P4）：
  ① 被拒絕時的文案必須**指名是哪個字元**，不是籠統的「路徑不支援」；
  ② 拒絕必須同時給**出路**——`.unsupportedCharacter` 複用 snippet ＋「複製」，
  `.mustMoveToApplications` 給「移到『應用程式』」的明確指示（D-s）。
  **沒有出路的拒絕在這個 change 裡是新的死路。**
- **從 DMG 直接雙擊就按接上的新使用者**：R-5 之前他會寫進一個下次開機就消失的路徑、
  畫面永遠說「已接上」、Codex 那邊一個字都不印（F5）——正是 §10-3 認定「最危險」的那種
  不可觀測失效。R-5 之後他在按下去**之前**就看到解釋與出路。
- **不懂「信任」提示的 vibe coding 使用者**：按了接上、Codex 沒問或問了沒按同意 → 燈永遠不動，
  而我們偵測不到（F5）。畫面與 help 必須把「下次啟動 Codex 會問你一次」講在
  **按下去之前與之後各一次**，且 troubleshooting 第一條就是它。

## 10. Known gaps

| # | 內容 | 性質 |
|---|---|---|
| 1 | `PermissionRequest`／`Interrupt`／`SubagentStart`／`SubagentStop` 的 Codex payload 形狀**未量**（F10：`exec` 強制 `approval: never`）——`waiting` 在 Codex 上目前是**推論**不是實測 | 待驗；互動 TUI 探針 |
| 2 | **Codex 沒有 `error` 來源**（F2、F4）→ Codex 的 session 永遠不會亮紅燈 | 設計代價，不硬推 |
| 3 | **無法偵測 Codex 是否已信任這個 hook**（F5）→ UI 只能講，不能顯示狀態 | 平台限制 |
| 4 | 不寫 `async`：F14 明列為未測 → 每個事件同步等 ~7 ms | 保守選擇 |
| 5 | ~~hooks.json 頂層形狀未知~~ **已由 F14 關閉**：逐字形狀就是被 Codex 成功解析並觸發的那份，產生器逐字照它（R-1） | **已關閉** |
| 6 | 內容比對與 `unlink` 之間的 TOCTOU 窄窗（POSIX 無原子原語，macOS 無 `funlinkat`）；已用 `(dev,ino)` 二次確認縮小 | 接受 |
| 7 | `codex exec` 會寫 `config.toml`（F12）→ 自動化驗收一律不跑它，Codex 端到端只能靠人 | 驗收缺口 |
| 8 | F15 證實 hook 父行程**不是逐事件的 shell**、pid 在 session 期間穩定（判活前提成立）。但：(a) 那五個 session **全部在 `exec` 模式**，互動 TUI 的行程結構未量；(b) `SessionEnd` **之後**那個 pid 是否結束**未觀測**（「隨 session 結束」是推論）；(c) 那個 pid 是 `codex` 原生二進位還是 node 啟動器未辨識 | 範圍限定 ＋ 待驗；實機 ③ 順帶記 `ps -o ppid=,comm=`；fallback 決策點見 §4.7 |
| 9 | **`timeout: 3` 是否真的不觸發 clamping 警告未觀測**——我們從沒量過任何 ≤ 3 的值（F13 只證明上限恰是 3）。三種結果都可承受（§4.3）；代價是失去「clamping 警告」這個最便宜的「Codex 讀到了」訊號，補償寫進 INSTALL troubleshooting | 推論；實機 ②③ 驗 |
| 10 | `command` 是裸路徑（F14 逐字）；**含空白／引號的路徑行為未測**。R-5 讓我們在寫入前就拒絕那些路徑，所以產品不會賭它；放寬與否取決於互動探針工具包的量測結果（已備好含空白路徑＋引號的探針） | 待驗；不阻擋本 change |
| 11 | 兩個 agent 的 session 共用 `~/.agentaura/sessions/`；同一個專案同時跑兩邊時，兩列只靠標籤區分 | persona 打分 |
| 12 | **App 被搬走或改名**：R-6 讓我們偵測得到（`.connectedStalePath`）並提供一鍵重接，但偵測發生在**下一次 `reprobeCodex()`**（啟動或開面板）。在那之前 Codex 那側已經不會動，而我們還沒機會講 | 設計代價；四個 reprobe 時機已是能做到的最密 |

## 11. 風險

| 風險 | 緩解 |
|---|---|
| **`Interrupt` 進 `handledEvents` → Claude 側整份 hooks 靜默失效**（最大爆炸半徑） | CX2 ＋ CX5 兩個獨立觀測點；§4.2 逐字寫明後果；`plugin/hooks/hooks.json` 的 git diff 必須為空 |
| **`Interrupt → idle` 沒有 fixture 證人**（round4 零筆） | CX4，定義域從 `codexOnlyEvents` 推導；CX13 的 mutation 換成 `Stop` |
| 「只在不存在時寫」寫成兩步，symlink 指向 `config.toml` 時覆蓋使用者設定 | `O_EXCL`（D-i）＋ CX15 那一格 fixture ＋ mutation 必須紅在那一格 |
| 產生器偏離 F14 → Codex 根本不載入，而自動化抓不到 | CX6 的 12 格逐字比對；F14 的「未測」三項一項都不碰；唯一的刻意偏離（`timeout`）自己配一格 mutation |
| **寫進一個下次開機就消失的絕對路徑，而 UI 永遠說「已接上」** | R-5 雙層 guard（路由 explain-only ＋ 執行層 guard）＋ CX32／CX33；本 repo 剛做了雙擊 `.dmg`，這是新使用者最可能的第一條路 |
| **App 搬家後 `.connected` 永遠成立、燈永遠不動** | R-6 的 `currentExpectedContents` ＋ `.connectedStalePath` ＋ CX34／CX35 |
| **憑證 round-trip 壞掉 → 永遠刪不掉自己的檔 → 完整移除留殘留** | CX31（逐位元組、輸入用真產生器輸出）＋ CX24③ 改成比對位元組 |
| **`reprobeCodex()` 沒被呼叫 → 裝了 Codex 卻要重開 app 才看得到**，且全套綠 | §4.6 四個時機 ＋ CX24⑤ |
| **94 個呼叫點的機械改動**（`make` 61／`rows` 26／`merge` 7）中夾帶弱化 | §6.4(2)(3)(4)(5)；`#expect` 淨數量不得下降 |
| 列標籤改了列高 → 唯一那一列被裁掉 | D-l ＋ CX23；`RowHeightDerivationTests` 從真實 view 推導 |
| `CodexState` 從 4 態變 6 態，波及四條聯集 gate | 那四條的定義域全部從 `CodexStateKind.allCases` 推導，加 case 是**自動**多驗一格，不是手改清單（D-r） |
| Codex 端到端無法自動驗收（F12） | 實機清單 ①–⑦，且 spec 不得用「已實測」描述沒有實機證據的事 |

**待確認（不自行決定，列給主 session）**：D-s 把 R-5 的「複用 snippet 當出路」細分成兩種
Rejection 各自不同的出路——`.unsupportedCharacter` 給 snippet ＋「複製」（照裁決），
`.mustMoveToApplications` **不給 snippet**、只給「移到『應用程式』」的指示。
理由是 translocated 的路徑是隨機臨時掛載點、下次開機就消失，把它交給使用者複製貼上
等於發一張明天就過期的票。若你要求兩種 Rejection 一律給 snippet，改 §4.6 表格與 D-s 即可，
其餘（CX32／CX33／L10n）不受影響。
