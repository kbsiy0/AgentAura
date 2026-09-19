---
change: codex-support
release_target: softlaunch
persona_impact: tier1
persona_impact_reason: 動 Sources/AgentAuraApp/**（面板列標籤、Codex 區塊、Options 新列）與 AuraCore 的 PanelAction／PanelModel／面板文案；「接上 Codex」是使用者第一次見到的第二種安裝動作，而我們**無法偵測 Codex 是否已信任這個 hook**（F5），生效與否完全靠畫面把話講清楚——這是純人類面的風險，不是機器面的
revision: r11（2026-09-19，折入 T11／T08 review；不送審）
---

# Change · `codex-support`：讓同一顆燈也照到 Codex

> 正典 `2026-09-08-agentaura-design.md` 為權威；本 change 對正典的修訂在 §8.2。
> 證據層是 `docs/2026-09-18-codex-hook-probe.md`（**F1–F15**，F15 以 `8fdce0b` 的版本為準）。
> **任何關於 Codex 行為的斷言都標了 F 編號；沒有 F 編號的一律寫成「待驗」，不得當事實用。**
> gate 編號慣例：**本 change 新增的 gate 一律 `CX<n>`**（共 **46** 條；CX37 拆成 a／b）；提到**既有** gate 一律寫
> 測試函式名（例如 `installerTouchesOnlyAllowedPaths`），**不寫 `G<n>`**。

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
| L4 | 安裝模型：「接上 Codex」**只在 `~/.codex/` 存在時顯示**；按下去**只在 `~/.codex/hooks.json` 不存在時寫入**（12 個事件、`command` 用 bundle 內 `aura-hook` 的**絕對路徑** ＋ `--agent codex`，F9）；寫入時記下內容；斷開**只在內容相符時刪除**。檔案已存在（別人的）→ 不動它，顯示可複製的 snippet。**絕不碰 `~/.codex/config.toml`**。UI 必須明講「Codex 會在下次啟動時問你一次是否信任這個 hook」（F5） |
| L5 | 「完整移除」**必須一併移除我們寫的 `~/.codex/hooks.json`**（內容相符時） |
| L6 | 文件（README × 2、INSTALL × 2、`Resources/help-*.html`、SECURITY、CLAUDE.md）都要更新；**英文為主**，中文同步 |

### 0.2 review r1／r2／r3 之後的裁決（主 session 2026-09-18，已鎖定）

| # | 裁決 | 取代 |
|---|---|---|
| R-1 | 產生器**逐字**輸出 F14 已驗證的形狀：`matcher: ""`、`type: "command"`、`command`，最外層 `hooks` 物件；**不加 `async`** | r1 §4.3 省略 `matcher` 的變體 |
| R-2 | **不算 hash**：把寫入的完整內容存進 `UserDefaults`，刪除前逐位元組比對 | r1 的 D-h |
| R-3 | `.notConnected` 的 Codex 卡片**一律單行提示＋按鈕**，不依 Claude 的安裝狀態降級 | r1 §4.6／§9／T09 的矛盾敘述 |
| R-4 | **`timeout: 3`**（全部 12 個事件同一個值），對 F14 **唯一的數值偏離**，理由與代價見 §4.3 | r2 的 `timeout: 5` |
| R-5 | 「這個 bundle 路徑能不能寫進 hooks.json」收斂成**單一純函式判定** `CodexHookPathCheck`；輸出餵**路由層**（`CodexState` 的 explain-only 分支）與**執行層**（`connect` 的 guard），**r4 再加第三個消費者**：`performConnectCodex()` 的前置 guard（R-9） | r2 完全沒有 translocation／路徑字元護欄 |
| R-6 | app 搬家導致絕對路徑失效 → `CodexState.from` 多吃 `currentExpectedContents`，新增 **`.connectedStalePath`**，UI 給「App 移動過，要重新接上」＋一鍵重接 | r2 的 `.connected` 在搬家後永遠成立 |
| R-7 | 含空白路徑的**探索性量測**移到互動探針工具包；DoD 實機 ⑦ 只驗「拒絕 ＋ 訊息指名字元 ＋ 有出路」 | r2 實機 ⑦「按接上 → 燈會動」 |
| **R-8** | **兩側互不干擾、最終都要成功**（使用者 2026-09-18 口述）：對任一側做 connect／disconnect／reconnect／完整移除的**任意操作序列**，另一側的檔案位元組與 `InstallState`／`CodexState` 不變；兩側都接上時，兩側都**真的能運作**。寫成不變式 ＋ 三條 gate（CX37a／CX37b 檔案、CX42 憑證、CX38 端到端）＋ 實機一格，見 §4.8 | r3 完全沒有把「兩側共存」寫成契約 |
| **R-9** | **「重新接上」在路徑被拒時不得先刪檔**：`performConnectCodex()` 第一行先看 `pathRejection`，非 nil 就顯示 banner／explain-only 並在**任何 `disconnect` 之前 return**；`.connectedStalePath` 的文案依 `pathRejection` 分兩種（非 nil 那種**不給按鈕**）。判定表列序**不動** | r3 的「stale → 先 disconnect 再 connect」在 translocated 下會刪掉使用者還在運作的檔（r3 B1） |
| **R-10** | **snippet 也要穿過 `CodexHookPathCheck`**：`pathRejection == .mustMoveToApplications` 時 `codexSnippet = nil`，`.occupiedByOther` 的 snippet 區塊換成「先把 App 移到『應用程式』，我們才給得出一份不會過期的設定」 | r3 的 `.occupiedByOther` 無條件給 snippet，繞過 D-s（r3 M1） |

### 0.3 本 change 自行決定的細節（最終報告逐條標示）

| 決定 | 內容 | 理由 |
|---|---|---|
| D-a | 磁碟上的 `agent` 是 **`String?`**（不是 enum），enum 只在 AuraCore 的邊界解析 | `Codable` 對「未知 rawValue 的 enum」是**整包解碼失敗**——未來多一種 agent，舊版 app 讀到的是**那個 session 從面板整個消失**。同 `outstandingSubagents` 的既有理由 |
| D-b | `Agent` 只有 `claude`／`codex`；未知值與 nil 一律落回 `.claude`，**且 `.claude` 不顯示標籤** | 保守失敗：寧可少一個標籤，不可把 Codex 的列標成 Claude 的 |
| D-c | `.claude` **不寫** `agent` 這個 JSON 鍵 | Claude 路徑的狀態檔位元組與改動前**完全相同**（CX9） |
| D-d | `--agent` 支援 `--agent codex` 與 `--agent=codex`；未知值／缺值一律 `.claude`，**全程靜默、exit 0** | 只支援一種寫法時，手寫成另一種會**靜默標成 claude** |
| D-e | Codex 的事件集合是**獨立常數** `codexEvents`，**不併進 `handledEvents`** | `handledEvents` 是 Claude 側 hooks.json 雙向等式 gate 的來源，而 Claude Code 對 hooks.json 是**全有全無**解析。**最容易踩的接縫**，見 §4.2 |
| D-f | `handledEvents` **不改名**，只補 doc comment | 三個既有測試檔用字面 `handledEvents` 釘住它 |
| D-g | hooks.json 產生器是**純函式**住 AuraCore | `Sources/AuraCore/` 只准 import Foundation |
| D-h | **（作廢，見 R-2）** 原為「digest 計算住 App 層＋注入縫」 | 保留來龍去脈給下一個讀到「為什麼不算 hash」的人 |
| D-i | 寫入用 `open(path, O_CREAT\|O_EXCL\|O_WRONLY\|O_CLOEXEC, 0o644)` | 「只在不存在時寫」必須是**一個**原子動作。四種佔用形狀實測**一律回 `EEXIST`** |
| D-j | `~/.codex` 不存在（或不是目錄）時，面板與 Options **完全沒有任何 Codex 元素** | 沒裝 Codex 的人畫面零 diff |
| D-k | 新增三個 `PanelAction`；**R-6 的「重新接上」重用 `.connectCodex`，不開第四個** | 重用讓 94 個呼叫點的 fan-out 不再長大 |
| D-l | 「Codex」標籤放在列的**第一行**，不另起一行 | 列高 43／59pt 由 `RowHeightDerivationTests` 從真實 view 推導 |
| D-m | 接上成功的 banner **必須**同時說「下一個 Codex session 起生效」與「Codex 會問你一次是否信任」 | F5 讓「已生效」在 Codex 上比在 Claude 上更不可宣稱 |
| D-n | 完整移除時，codex disconnect 必須排在 `erasePersistentDomain()` **之前** | 比對用的內容住在 persistent domain 裡 |
| D-o | `verify-uninstall.sh` 第 7 項用**內容判準** | 腳本跑的時候 persistent domain 已清空 |
| D-p | `~/.codex` 自己是 symlink 時**不拒絕**，但寫入必須落在 `realpath` 底下 | 同既有 `ClaudeHomeSkillsSymlinkFixture` 的形狀 |
| D-q | 只在 `regularFile` **且 ≤ 64 KiB** 時才讀內容 | 我們的檔 ~2 KB；超過的不可能是我們寫的 |
| D-r | `CodexState` 帶 associated value 故**不能 `CaseIterable`**；配平行的 `CodexStateKind` ＋ `samples(_:)`。**r4 再往下一層**：`Rejection` 也配 `RejectionKind: CaseIterable` ＋ `Rejection.samples(_:)`，`CodexState.samples(.blockedByBundlePath)` 由它推導（r3 m1）。**兩層的 `switch` 都不得有 `default`**（r3 m2） | 既有 `PanelActionKind` 的 doc comment 逐字寫著這個理由。`default: []` 是一個看起來很無害的「防禦性」寫法，卻能讓整條推導鏈靜默失效——所以要寫成禁令，不是慣例 |
| D-s | `.blockedByBundlePath` 的兩種 Rejection **出路不同**：`.unsupportedCharacter` 給 snippet ＋「複製」；`.mustMoveToApplications` **不給 snippet**，只給「把 App 移到『應用程式』」的指示。**R-10 讓這條也適用於 `.occupiedByOther`** | translocated 的路徑是隨機臨時掛載點、下次開機就消失，把它交給使用者複製貼上等於發一張明天就過期的票 |
| **D-t** | `translocated`／`inDownloads`／`pathRejection`／`currentExpectedContents` 四個**行程常數**在 `applicationDidFinishLaunching` 算一次存成欄位；`reprobeCodex()` 只重做檔案系統那一段 | 四者都是 `Bundle.main.bundleURL` 的純函式，在行程生命週期內不會變。r3 讓每次 `onOpen` 都重算一次 `SecTranslocateIsTranslocatedURL`（Security 框架呼叫）＋ 兩次 `resolvingSymlinksInPath` ＋ 產 12 個事件的 JSON——面板開啟延遲是這個專案量過、在意過的東西（`Installer.probe()` 的 128 µs 分解寫在生產碼註解裡）（r3 m3） |
| **D-u** | `Jargon.model` 要認得 Codex 的模型命名；**保留既有 Claude 家族演算法不動**，新分支排在它之前，判不出來一律沿用既有的「原樣回傳」 | fixture 進 repo 之後，既有 gate `FixtureCodeAnchorTests.everyFixtureModelIsMapped` **已經紅**（`Jargon.model("gpt-5.5")` 原字回傳）。那是本 change 必須修好的既有 gate，不是弱化對象。見 §4.9 |

## 1. 目標與範圍

**做**：`--agent` 參數 · Codex 事件集合與 `Interrupt` 映射 · hooks.json 產生器（逐字 F14，唯一偏離 `timeout`）·
`CodexHookPathCheck`（三個消費者）· `CodexInstaller`（probe／connect／disconnect）·
`agent` 欄位貫穿 payload → 檔案 → state → UI 四段 · **`Jargon.model` 的 Codex 命名** ·
面板列標籤 · Codex 區塊與 Options 列 · snippet 複製（穿過路徑判定）· 內容憑證 ＋ round-trip 保證 ·
搬家偵測與一鍵重接 · **兩側互不干擾的不變式（R-8）** · 完整移除納入 · 文件與正典回寫 · 全鏈接線 gate。

**不做**：Codex 的 `error` 狀態（F2／F4）· 互動 TUI 探針（`PermissionRequest`／`Interrupt`／`Subagent*`
的形狀、hook 父行程的 `comm` 與 TUI 行程結構、含空白路徑＋引號的實測，全部在探針工具包待跑）·
分 agent 的聚合燈或分頁 · 動 `~/.codex/config.toml` · 動 Claude 側 `plugin/hooks/hooks.json` ·
自動偵測 Codex 是否已信任（F5）· 第三種 agent 的擴充機制（YAGNI）。

## 2. 架構總覽

```
Codex CLI ──(12 events, F2)──▶ ~/.codex/hooks.json ──▶ <abs>/aura-hook --agent codex  （逐字 F14，timeout 3）
Claude Code ─(19 events)────▶ ~/.claude/skills/agentaura → bundle plugin → aura-hook   （無參數＝claude）
                                                              │ stdin: hook JSON (F3)
                                                              ▼  兩側共用同一顆二進位、同一個狀態目錄（R-8）
                             AgentArgument.agent(argv) ──▶ Agent(.claude / .codex)
        HookPayload(data:) ──▶ MergeRules.merge(payload, agent:) ──▶ SessionSnapshot(agent:)
                                                              ▼ ~/.agentaura/sessions/<id>.json
        PipelineGraph ──▶ SessionReducer ──▶ SessionState(agent:) ──▶ PanelRow(agentLabel:) ──▶ PanelRowView
                                                                         └─ meta 走 Jargon.model（§4.9）

啟動時算一次（D-t）：RunningBundle.isTranslocated()/isInDownloads()
        └──▶ pathRejection = CodexHookPathCheck.rejection(...)      三個消費者：
             currentExpectedContents = CodexHooksJSON.json(...)     ① 路由層 CodexState
                                                                    ② performConnectCodex() 前置 guard（R-9）
                                                                    ③ 執行層 CodexInstaller.connect
             codexSnippet = (rejection == .mustMoveToApplications) ? nil : snippet(...)（R-10）

reprobeCodex()：只重做 installer.probe() ──▶ CodexState.from(obs, recorded, currentExpected, pathRejection)
   ▲ connect(json:translocated:inDownloads:) / disconnect(ifContentsEqual:)
   └── 六態 → §4.6 表
```

| 單元 | 層 | 狀態 | 職責 |
|---|---|---|---|
| `Agent` | AuraCore | 新 | `enum Agent: String, CaseIterable, Sendable { case claude, codex }`；`storedRawValue`（`.claude` → nil）；`init(stored:)`；`label`（`.claude` → nil） |
| `AgentArgument` | AuraCore | 新（同檔） | `agent(from argv:) -> Agent`：純函式，兩種寫法，未知一律 `.claude` |
| `EventMapping` | AuraCore | 改 | `+ codexEvents`（12 個，F2）、`+ codexOnlyEvents = ["Interrupt"]`；`effect` 加 `case "Interrupt"`。**`handledEvents` 一個字都不動** |
| `CodexHooksJSON` | AuraCore | 新 | `agentFlag`、`hookTimeoutSeconds = 3`（**單一常數**）；`json(hookBinaryPath:) -> Data`；`snippet(hookBinaryPath:) -> String` |
| `CodexHookPathCheck` | AuraCore | 新 | `enum Rejection { mustMoveToApplications, unsupportedCharacter(Character) }` ＋ **`RejectionKind: String, CaseIterable`** ＋ `Rejection.samples(_:)`（窮盡 switch，**不得有 `default`**）；`unsupportedCharacters: Set<Character>`；`rejection(translocated:inDownloads:hookBinaryPath:) -> Rejection?`。**零 I/O、零平台 API** |
| `CodexObservation` | AuraCore | 新 | `codexHomeIsDirectory`、`entryType`、`contents: Data?`（D-q）、`displayPath: String?` |
| `CodexState` | AuraCore | 新 | 六態（§3）；`CodexStateKind` ＋ `samples(_:)`（兩層都不得有 `default`，D-r）；`from(_:recordedContents:currentExpectedContents:pathRejection:)` 窮盡、零 I/O |
| `CodexFailure` | AuraCore | 新 | 七個 case：`codexHomeMissing`／`alreadyExists`／`writeFailed(Int32)`／`notOurs`／`unreadable(Int32)`／`mustMoveToApplications`／`unsupportedPathCharacter(Character)` |
| **`Jargon`** | AuraCore | **改** | `model(_:)` 前面加 Codex 家族分支（§4.9）。既有 Claude 家族演算法**一行不動** |
| `CodexInstaller` | AuraHookFile | 新 | `Sendable`；兩個 `URL`；`probe()`／`connect(json:translocated:inDownloads:) throws -> Data`／`disconnect(ifContentsEqual:) throws`。**只碰 `<codexHome>/hooks.json`** |
| `CodexHookStore` | App | 新 | `@MainActor` ＋ 注入 `UserDefaults`；key `AgentAuraCodexHookContents`；`Data` 進、`Data` 出，round-trip 有 gate（CX31） |
| `PanelAction` / `PanelActionKind` | AuraCore | 改 | `+ .connectCodex`／`.disconnectCodex`／`.copyCodexSnippet`。**不新增第四個**。`samples` 的 doc comment 補「**不得有 `default`**」（r3 m2 順手補既有註解） |
| `OptionsMenuModel` | AuraCore | 改 | `rows(...)` 多吃**兩個**參數 `codex: CodexState` ＋ **`codexPathRejection: Rejection?`**（後者不進 case 的 payload，理由見 §3）；列數依 §4.6；`nonMenuKinds` 加 `.copyCodexSnippet` |
| `PanelModel` | AuraCore | 改 | **三個**新欄位：`+ codex: CodexState`、`+ codexSnippet: String?`、**`+ codexPathRejection: CodexHookPathCheck.Rejection?`**；`make(...)` 新參數**不給預設值** |
| `PanelRow` | AuraCore | 改 | `+ agentLabel: String?` |
| `SessionSnapshot` / `MergeRules` / `SessionReducer` / `SessionState` | AuraCore | 改 | `agent: String?` 一路帶到 `SessionState.agent: Agent`；`merge(...)` 多一個 `agent:`（無預設值） |
| `CodexSectionView` | App | 新 | 六態 ＋ 兩種 Rejection 的分支（§4.6 表）。**不吃 `InstallState`** |
| `PanelRowView` | App | 改 | 第一行 `HStack` 內加標籤 |
| `AppDelegate+Codex.swift` | App | 新 | **四個行程常數欄位（D-t）** ＋ `reprobeCodex()`／`performConnectCodex()`（**第一行 guard**，R-9）／`performDisconnectCodex()`／`performCopyCodexSnippet()` |
| `Uninstaller` | App | 改 | `run()` 在 `erasePersistentDomain()` 前多一步 codex disconnect |

**設計選擇**
1. **一條資料流，兩個入口**：Codex 與 Claude 共用 `~/.agentaura/sessions/`、共用 `MergeRules`、共用聚合。
2. **兩份 hooks.json 各自的來源集合分離**（§4.2），都是 source-derived。
3. **保本動作全部在執行層**，不靠上層路由先擋（S0-1(ii)）。
4. **憑證存的就是它要比的東西**（R-2）；文字鍵的 round-trip 由 CX31 專守。
5. **「路徑能不能用」是一個判定、三個消費者**（R-5 ＋ R-9）：路由層決定畫按鈕還是畫解釋，
   `performConnectCodex()` 決定要不要動手，執行層是最後一道。**按了才失敗的按鈕比沒有按鈕更糟；
   而「按了會先刪檔再失敗」比兩者都糟**——這正是 r3 B1 的形狀（§4.6）。
6. **兩側互不干擾是契約不是巧合**（R-8）：共用二進位、共用狀態目錄，但兩側的安裝物件
   （`~/.claude/skills/agentaura` 的 symlink vs `~/.codex/hooks.json` 的檔案）互不重疊，
   §4.8 把它寫成不變式並配兩層 gate。

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

public enum CodexHookPathCheck {
    public enum RejectionKind: String, Sendable, CaseIterable {  // r4／r3 m1
        case mustMoveToApplications, unsupportedCharacter
    }
    public enum Rejection: Equatable, Sendable {
        case mustMoveToApplications
        case unsupportedCharacter(Character)
        public var kind: RejectionKind                           // 窮盡 switch，不得有 default
        public static func samples(_ k: RejectionKind) -> [Rejection]   // 同上
    }
    public static let unsupportedCharacters: Set<Character>      // 八個：空白 ' " $ ` \ \n \t（見 §4.4）
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
    public var kind: CodexStateKind                             // 窮盡 switch，不得有 default
    public static func samples(_ kind: CodexStateKind) -> [CodexState]
        // .blockedByBundlePath 那一格 = RejectionKind.allCases.flatMap(Rejection.samples)
        //                                 .map(CodexState.blockedByBundlePath)
    public static func from(_ o: CodexObservation, recordedContents: Data?,
                            currentExpectedContents: Data,
                            pathRejection: CodexHookPathCheck.Rejection?) -> CodexState
}
public enum CodexStateKind: String, Sendable, CaseIterable {
    case unavailable, notConnected, connected, connectedStalePath, occupiedByOther, blockedByBundlePath
}
```

**`pathRejection` 不進任何 case 的 payload**（T07 review 的主管問題 4 裁決）——它是**橫跨**
`.connectedStalePath` 與 `.occupiedByOther` 的 **UI 輸入**：`rows(codex:codexPathRejection:)` 另傳一個參數，
`PanelModel` 也因此有**三個**新欄位（`codex`／`codexSnippet`／`codexPathRejection`）。
**區分原則**：只有 **`.blockedByBundlePath(Rejection)` 的 payload 是構成性的**——判定表第 6 列的
成立條件**就是**它非 nil；`pathRejection` 對第 2／3 列是**附帶的**（判定表寫「任意」，`from(...)`
走到 `.connectedStalePath` 根本不看它）。把附帶資料塞進 payload 有三個具體代價：
① `Equatable` 被污染——`.connectedStalePath(nil) != .connectedStalePath(.mustMoveToApplications)`，
但那是**同一個世界狀態**（磁碟==憑證≠現在預期），而 CX19／CX34 都靠 `Equatable` 比對；
② `samples` 膨脹成 `[nil] + 全部 Rejection`，把每一條聯集 gate 的定義域放大，其中多數在行為上相同；
③ **R-10 要求 `.occupiedByOther` 在 `pathRejection == .mustMoveToApplications` 時不給 snippet**，
若只放進 `.connectedStalePath` 的 payload，`.occupiedByOther` 仍得另外拿一次 → 兩套機制並存。

**兩層 `samples` 的 `switch` 都不得有 `default`**（D-r／r3 m2）——那正是這兩個平行 Kind 型別
存在的**唯一**理由：新增一個 case 時編譯器會擋下來。加一個 `default: []` 看起來像防禦性寫法，
實際是把整條定義域推導鏈靜默關掉。這句話要**逐字**寫進兩個 `samples` 的 doc comment，
並順手補進既有的 `PanelAction.samples`（一行，零風險）。

判定表（`CodexState.from`，窮盡、零 I/O；**由上而下第一個命中者勝**；**r4 不動這個列序**）：

| # | `codexHomeIsDirectory` | `entryType` | 磁碟 vs `recordedContents` | 磁碟 vs `currentExpectedContents` | `pathRejection` | → |
|---|---|---|---|---|---|---|
| 1 | false | 任意 | — | — | 任意 | `.unavailable` |
| 2 | true | `regularFile` | 兩者非 nil 且**逐位元組相等** | **相等** | 任意 | `.connected` |
| 3 | true | `regularFile` | 兩者非 nil 且**逐位元組相等** | **不等** | 任意 | `.connectedStalePath` |
| 4 | true | `regularFile` | 其餘（任一 nil／不等／> 64 KiB 沒讀） | — | 任意 | `.occupiedByOther` |
| 5 | true | `directory`／`symlink`／`other` | — | — | 任意 | `.occupiedByOther` |
| 6 | true | `absent` | — | — | **非 nil** | `.blockedByBundlePath(r)` |
| 7 | true | `absent` | — | — | nil | `.notConnected` |

**第 2／3 列排在第 6 列之前是刻意的**：磁碟上已經有我們的檔時，該講的是那個檔的狀態。
**但那條「正確的引導」在 r3 是錯的**——r3 讓使用者按下「重新接上」後先 `disconnect`，
於是一個只是打開了 DMG 副本的人，會把他指向 `/Applications` 真本、**還在運作**的
`~/.codex/hooks.json` 弄丟。R-9 的處置是**不動列序**，改在 UI 與 `performConnectCodex()`
兩處讓那個按鈕在 `pathRejection != nil` 時**根本不存在**（§4.6）。

`SessionSnapshot` 加 `public var agent: String? = nil`（CodingKey `agent`）。**必須是 Optional**。
`UserDefaults`（domain `io.agentaura.app`）新增**一個** key：`AgentAuraCodexHookContents`。

## 4. 核心技術

### 4.1 `--agent` 參數（D-d）
`aura-hook/main.swift` 新增一行 `let agent = AgentArgument.agent(from: CommandLine.arguments)`
往下傳給 `MergeRules.merge`。由左至右找第一個 `--agent <值>` 或 `--agent=<值>`；大小寫敏感；
任何不匹配一律 `.claude`。**永不 `exit(非零)`、永不寫 stdout／stderr**。

### 4.2 事件集合與 `Interrupt` 接縫（本 change 最容易踩的地方）

- **Claude Code 對 hooks.json 是全有全無解析——這是跨機器實測，不是本機驗證器說的**（T03 review M1）：
  2026-09-15 在**同事的機器**上，一個平台不認得的 `PostModelSwitch` 讓**整個 plugin 不運作**，
  其餘合法 event 一起陪葬（專案記憶 `distribution-and-hook-compat`）。
  **本機 `claude plugin validate --strict` 對未知 event 只給 warning「entry ignored at runtime」**，
  看起來像是只有那一條被忽略——**本機通過不構成反證**，這與 Claude Code 的版本有關。
  沒有這句限定語，下一個維護者讀到「整份拒載」、順手跑一次本機 validator 看到只是 warning，
  最合理的推論就是「這段誇大了」，然後把 CX2／CX5 當成過度防禦而放寬。
  `registeredEventsMatchHandledEvents` 是雙向等式，所以 **`Interrupt` 一旦進 `handledEvents`**，
  那條 gate 會要求 Claude 的 hooks.json 也註冊它 → Claude 側整份 hooks 失效。
  **一個「把對照表補齊」的善意動作，後果是產品對 Claude 使用者完全停止運作。**
- `codexEvents`（12 個）獨立常數，`codexOnlyEvents = ["Interrupt"]`；`Interrupt` 只進 `effect` 的 switch。
  **前提**：F2 沒有回答「Claude Code 自己認不認得 `Interrupt`」；我們據以行動的是既有事實
  （`handledEvents` 19 個名字裡沒有它、Claude 側 hooks.json 從未註冊過它）。CX5 守的是「沒有註冊」。
- **`Interrupt` 事件 ≠ `is_interrupt` 欄位**：後者是 `HookPayload.isInterrupt`（使用者 Ctrl+C
  中斷了一個 **tool**，刻意不計入 `tool_failures`）。兩者 doc comment 互相點名。
- 四條 gate（CX2／CX3／CX4／CX5）**加上第四道平台自己的防線**：**`claude plugin validate --strict`**
  （DoD #16 要求零 warning）對註冊 `Interrupt` 會**直接失敗**（reviewer 實測：`unknown hook event;
  entry ignored at runtime` ＋ `--strict` 視 warning 為 error）。**它是唯一一道不依賴我們自己寫的斷言的防線**
  ——問的是平台，不是我們對平台的理解（gate 哲學第 1 條）。**CX4 是必要的**：`round4-codex.ndjson` **零筆 `Interrupt`**
  （`SessionStart` 4／`UserPromptSubmit` 4／`Stop` 4／`SessionEnd` 4／`PreToolUse` 1／`PostToolUse` 1），
  沒有它，刪掉 `case "Interrupt"` 整行全部 gate 維持綠。
- **後果**：Codex 沒有 `PostToolUseFailure` 也沒有 `StopFailure`（F2），`tool_response` 只是字串（F4）
  → **Codex 的 session 永遠不會讓燈變紅**（§10-2）。

### 4.3 hooks.json 產生器：逐字照 F14，唯一偏離是 `timeout`（R-1 ＋ R-4）

```
{ "hooks": { "<event>": [ { "matcher": "", "hooks": [ { "type": "command",
             "command": "<abs>/aura-hook --agent codex", "timeout": 3 } ] } ], ...（12 個，事件名排序） } }
```
- 事件清單從 `codexEvents` 排序推導，**不寫第二份**；CX6 驗鍵集合恰等於它，
  **並把 12 個事件的 entry 逐一逐字對 F14 比對**（抽樣有 11/12 的機率看不到特例）。
- **`matcher: ""` 不可省**：F14 的「未測」欄第一項就是它。**不能拿 Claude 側當佐證**——
  Claude 的 19 個 entry 裡只有 `Notification` 帶 `matcher`，而且 Codex 與 Claude 是**兩個解析器**，
  F7 已證明它們寬容度相反（Codex 忽略不認得的事件名，Claude 整份拒載）。
- **`timeout: 3`（R-4）——對 F14 唯一的數值偏離**：目的是避免 F13 的 clamping 警告落在使用者的
  stderr；**「3 不觸發警告」是推論不是事實**（從沒量過 ≤ 3 的值）；三種結果都可承受；
  12 個統一是因為**產生器從單一常數推導**，逐事件不同值等於養第二份清單。
  代價是失去 F1 賴以斷言「Codex 讀到了」的唯一便宜訊號，補償寫進 INSTALL troubleshooting。
  CX6 為這個刻意偏離配一格自己的 mutation（**改回 5 → 必紅**）。
- **不寫 `async`**（F14 未測欄第二項）；`command` **不加引號**（F14 是裸路徑）。
- `snippet(hookBinaryPath:)` **就是 `json(...)` 的文字形式**（同一個產生器）。

### 4.4 路徑判定（R-5）與 `CodexInstaller` 的三個動作

`CodexHookPathCheck.rejection(...)`：① `translocated || inDownloads` → `.mustMoveToApplications`
（`RunningBundle` 的 doc comment 實測記載：Gatekeeper 把「從下載的 zip／DMG 直接雙擊」的 app
跑在**唯讀、隨機命名的臨時掛載點，那個路徑下次啟動就消失**；本 repo 上一個 change 才剛做了
雙擊安裝的 `.dmg`）；② 否則掃路徑，**第一個**命中 `unsupportedCharacters` 的字元 →
`.unsupportedCharacter(那個字元)`；③ 否則 nil。

**`unsupportedCharacters` 目前是八個**：空白、`'`、`"`、`$`、`` ` ``、`\`、**換行、tab**（T04 review M3）。
**這是啟發式，不是完備集合**——它的定位是「**已知最可能出問題、且不會過度拒絕的最小集合**」，
不是「所有會出問題的字元」。刻意**未擋**的包括 `(`／`)`（「AgentAura (beta)」「Projects (2026)」
這類資料夾名很常見）、`;`／`&`／`|`／`>`／`<`／`*`／`?`。理由：擋它們的前提是「Codex 把 `command`
交給 shell」，而**我們並不知道它是不是**（§10-10：`command` 的解析方式未測，R-7 已把量測移到互動探針）；
在不知道的情況下擴到二十幾個字元會過度拒絕。換行與 tab 是例外——**兩種解析假設下都危險**
（就算只是「用空白切分參數」也會裂開），零過度拒絕風險，所以納入。
完整集合**待互動探針量到 Codex 的實際解析方式再決定**。
下一個人看到 `(` 沒擋時，要知道那是**已知的取捨**，不是漏寫。
**CX33 的逐字元格從這個生產常數推導**，所以集合改大改小，gate 的定義域自動跟上（現在是 8 格）。

**注意**：既有 `Installer.connect` 的 `mustMoveToApplications` 擋的**只有** translocated 與
`~/Downloads`，**沒有**「必須在 `/Applications`」。所以 `~/Applications/`、`~/My Apps/` 這類
合法位置**可以含空白**——「幾乎永遠不觸發」不成立。

**三個消費者，一個判定**（R-5 ＋ R-9）：路由層（`CodexState.from` 的 `pathRejection`）／
`performConnectCodex()` 的前置 guard／執行層 `CodexInstaller.connect` 的第一行。

**三個動作**：
- **`probe()`**：`lstat(codexHome)` → `lstat(hooks.json)` → 只有 `regularFile` **且 ≤ 64 KiB**（D-q）
  才 `open(..., O_RDONLY | O_NOFOLLOW)` 讀內容。
- **`connect(json:translocated:inDownloads:)`**：路徑 guard → `open(path,
  O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC, 0o644)`（D-i）→ 寫 → close → 回傳寫出去的 `Data`。
  `codexHome` 不是目錄時 throw `.codexHomeMissing`（**不建立它**）。
  **`EEXIST` 一律 → `.alreadyExists`**（四種佔用形狀實測全部 `EEXIST`，沒有 `EISDIR`）。
- **`disconnect(ifContentsEqual:)`**：`O_RDONLY|O_NOFOLLOW` → `fstat` 確認 `S_IFREG` → 讀 →
  **逐位元組比對** → 不符 throw `.notOurs`（**不刪**）→ 相符 → **`unlink` 前再 `lstat` 一次路徑，
  比對 `fstat` 拿到的 `(dev, ino)`，不同就放棄** → `unlink`。absent 冪等成功。

**TOCTOU**：POSIX 沒有「內容相符才 unlink」的原子原語（macOS 也沒有 `funlinkat`），
窄窗已用同 fd 連續操作 ＋ `(dev, ino)` 二次確認縮到最小（§10-6）。寫入那一側沒有這個問題。

**保本動作擋不住「在錯誤的時機正確地執行」**（r3 B1 的教訓）：`disconnect` 的兩道保護
（逐位元組比對、`(dev,ino)` 複查）在那個情境下**全部生效**，檔案確實是我們的，所以刪得理直氣壯。
要擋的是**呼叫它的時機**，那是 R-9。

### 4.5 內容憑證、round-trip 與完整移除（R-2 ＋ r2 M6）
- `connect` 成功 → `CodexHookStore.write(bytes)`；`disconnect` 成功 → `clear()`。
- **round-trip 是獨立的失敗面**：`connect` 回 `Data`、`disconnect` 比對 `Data`，中間經過一個
  **文字**鍵。任何編碼不對等 → `disconnect` 永遠比不中 → `.notOurs` → **永遠刪不掉自己寫的檔**
  → 完整移除留殘留 → `verify-uninstall.sh` 第 7 項 FAIL。CLAUDE.md 逐字寫著
  「移除乾淨是測試能力的前提」，所以由 **CX31** 專守（輸入用**真正的產生器輸出**）。
- `Uninstaller.run()`：`loginItem.set(false)` → `installer.disconnect()` →
  **`codexInstaller.disconnect(ifContentsEqual: store.contents)`（`try?`）** → `StateDirectoryEraser.erase` →
  `erasePersistentDomain()` → `recycleBundleAndTerminate()`。codex 那步**必須在清 domain 之前**（D-n）。
- `verify-uninstall.sh` 第 7 項用內容判準（D-o），且**必須可以單獨執行**（`--only 7`）：
  第 1–6 項查**真實** `$HOME`，開發機上本來就會 FAIL、整支本來就非零退出——
  用整體 exit code 當判準的 gate 對 mutation 不會紅；整支還會跑 `osascript` 與 `sfltool dumpbtm`。

### 4.6 面板、Options 與「重新接上」的時機（R-9 ＋ R-10）

**這張表吃兩個輸入**：`CodexState` **與** `pathRejection`（後者不是 state 的 payload，見 §3 的區分原則）。

| `CodexState` ＋ `pathRejection` | 面板 | snippet | Options（`.mount` 群組） |
|---|---|---|---|
| `.unavailable` | **什麼都不畫**（D-j） | — | 零列 |
| `.notConnected` | 單行提示 ＋ 按鈕（R-3，一律如此） | — | 恰一列「接上 Codex」（`.connectCodex`） |
| `.connected` | 不畫說明卡 | — | 恰一列「移除 Codex 掛載…」 |
| `.connectedStalePath`，`pathRejection == nil` | 「App 移動過，要重新接上」**＋ 按鈕** | — | 恰**兩**列：「重新接上 Codex」（`.connectCodex`）＋「移除 Codex 掛載…」 |
| **`.connectedStalePath`，`pathRejection != nil`** | **「這份設定指向另一個位置的 AgentAura；這個副本跑在一個下次開機就會消失的位置」**＋ 出路（先把要留下的那份放進「應用程式」再回來）**不給按鈕**（R-9）。**文案不預設成因**（r4 m2）：觸發條件是「磁碟 == 憑證 ≠ 現在預期」，而「現在預期」用的是**當下這個行程的** bundle 路徑——使用者同時有正本與一份 DMG／備份副本時，從副本啟動就會落進這一列，而 App 其實**沒有**移動過 | — | **恰一列**「移除 Codex 掛載…」（不給「重新接上」） |
| `.occupiedByOther`，`codexSnippet != nil` | 「你已經有自己的 `~/.codex/hooks.json`，我們不會動它」＋ 可選取 snippet ＋「複製」 | 有 | 零列 |
| **`.occupiedByOther`，`codexSnippet == nil`** | 同上，但 snippet 區塊換成「先把 App 移到『應用程式』，我們才給得出一份不會過期的設定」（R-10） | 無 | 零列 |
| `.blockedByBundlePath(.mustMoveToApplications)` | 解釋 ＋ 出路＝把 App 移到「應用程式」。**不給 snippet**（D-s） | 無 | 零列 |
| `.blockedByBundlePath(.unsupportedCharacter(c))` | 解釋 ＋ **指名是哪個字元** ＋ 出路＝snippet ＋「複製」 | 有 | 零列 |

**`codexSnippet` 的產生穿過路徑判定**（R-10）：
`codexSnippet = (pathRejection == .mustMoveToApplications) ? nil : CodexHooksJSON.snippet(...)`。
理由與 D-s 一字不差：那個路徑是隨機臨時掛載點，**P2 是最會真的照著貼的那個 persona**，
而失效是靜默的（F5）。r3 把這扇門留著沒關——`.occupiedByOther`（第 4／5 列）優先於
`.blockedByBundlePath`（第 6 列），所以「有自己的 hooks.json ＋ 從 DMG 開」會拿到一份
`command` 指向 `/private/var/folders/.../AppTranslocation/<uuid>/...` 的 snippet。

**`performConnectCodex()` 的第一行是 guard**（R-9）：
```
guard pathRejection == nil else { banner = .error(對應文案); refreshPanel(); return }   // 在任何 disconnect 之前
if codexState == .connectedStalePath { try? installer.disconnect(ifContentsEqual: store.contents) }
try installer.connect(json:..., translocated:..., inDownloads:...)
```
**這個 guard 不是為了「少一次失敗」，是為了「不要先刪檔」**：r3 的順序在 translocated 下會
`disconnect` 成功（內容確實相符）→ 檔案被刪、`store.clear()` → 然後 `connect` 才撞上執行層 guard。
淨結果是「使用者只是打開了一次 DMG 裡的副本，他那份還在運作的 hook 就沒了」，而按鈕上寫「重新接上」。

**`reprobeCodex()` 的內容與時機**：
- **行程常數在啟動時算一次**（D-t）：`translocated`／`inDownloads`／`pathRejection`／
  `currentExpectedContents`／`codexSnippet` 五者都是 `Bundle.main.bundleURL` 的純函式，
  在 `applicationDidFinishLaunching` 算一次存成欄位。
- `reprobeCodex()` **只重做檔案系統那一段**：`installer.probe()` →
  `CodexState.from(obs, recordedContents: store.contents, currentExpectedContents: 欄位, pathRejection: 欄位)`。
- **四個時機**：① `applicationDidFinishLaunching` 同步區（第一次 `refreshPanel()` **之前**）
  ② popover `onOpen` ③ `performConnectCodex()` 之後 ④ `performDisconnectCodex()` 之後。
  漏接的後果：使用者裝了 Codex、開面板、什麼都沒有，重開 app 才出現——而全套測試綠（CX24⑤ 守）。

接上成功的 banner（D-m）：**「已接上 Codex · 下一個 Codex session 起生效；
Codex 啟動時會問你一次是否信任這個 hook，要按同意才會生效。」**

### 4.7 liveness 與 hook 的父行程（F15）

**已證實（F15）**：五個 session、24 筆事件，每個 session 內所有事件的 `$PPID` 完全相同 →
(i) 呼叫 hook 的**不是每個事件開一次的短命 shell**；(ii) 那個行程至少活過第一個到最後一個事件。
**結論：`getppid()` 判活的前提（pid 在 session 期間穩定）對 Codex 成立。**

**範圍限定（F15，不是細節）**：那五個 session **全部跑在 `codex exec`**。產品要服務的是**互動 TUI**
（F10）。exec 模式的行程結構不等於 TUI 模式的——TUI 完全可能由常駐 app 行程 fork 出 session。
**實機 ③ 要順帶記 `ps -o ppid=,comm=`。**

**未觀測（F15）**：(a) `SessionEnd` **之後**那個 pid 是否結束（「隨 session 結束」是推論；
實務後果有限，`resolveLiveness` 第一個 guard 就是 `!s.terminated`）；(b) 那個 pid 是 `codex`
原生二進位還是 node 啟動器。

**預寫的 fallback 決策點**（若實機 ③ 發現父行程跨 session 常駐）：`--agent codex` 時**不寫 pid**，
改由 `SessionEnd` 的 `terminated` 單獨判死。**這條現在不做。**

### 4.8 兩側互不干擾、最終都要成功（R-8）

**不變式（寫成契約，不是巧合）**：
1. **隔離**：對任一側做 connect／disconnect／reconnect／完整移除的**任意操作序列**，
   另一側的檔案位元組不變、另一側的 `InstallState`／`CodexState` 不變。
2. **共存**：兩側都接上時，兩側都**真的能運作**——同一顆 `aura-hook` 同時服務兩個上游，
   兩邊的事件各自寫到 `~/.agentaura/sessions/` 且**互不覆蓋**、`agent` 各自正確。

不變式成立的結構理由（要寫進 doc comment，讓下一個人知道它靠什麼）：
兩側的安裝物件**不重疊**——Claude 側只碰 `<claudeHome>/skills[/agentaura]`
（既有 `installerTouchesOnlyAllowedPaths` 守），Codex 側只碰 `<codexHome>/hooks.json`（CX14 守）；
狀態檔以 `session_id` 分檔，兩個上游的 id 空間不交集（Claude 的 UUID 與 Codex 的 UUIDv7）。
**但「不重疊」是兩條獨立 gate 各自的結論，沒有人驗過「交錯操作」本身**——R-8 補的就是那個。

**不變式 1 由兩條 gate 共同守，缺一不可**（r4 M3）：`InstallState` = `LinkObservation`（檔案）
＋ `verification`（App 層三個 `AgentAuraHook*` 鍵）；`CodexState` = `CodexObservation`（檔案）
＋ `recordedContents`（App 層 `AgentAuraCodexHookContents`）。**CX37a／CX37b 住 AuraHookFile，
只看得到檔案那一半**；憑證那一半（真實 App 層有沒有把兩邊的鍵搞混）由 **CX42** 守。
三條 gate（CX37a／CX37b／CX42）的 doc comment 要互相點名，否則下一個人讀到檔案那兩條會以為整條不變式都守住了。

**CX37a／CX37b 序列 gate**（AuraHookFile 層，fixture home，見 §6.3）：對
`{connectClaude, connectCodex, disconnectClaude, disconnectCodex, reconnectCodex(stale)}`
**程式推導**出序列（不手列），每一步之後對「另一側」整棵樹取 `DirectoryTreeSnapshot`
斷言零差異；序列結束時若兩側皆 connected，兩側 `probe()` 推導出的狀態皆為 connected。
**拆成兩條，覆蓋不減、spawn 從 586 次降到 11 次**（r4 M2）：

- **CX37a（檔案不變式，全部 780 條序列）**：`connectClaude` 這一步**直接呼叫
  `installer.guardWriteTarget()` ＋ `installer.atomicReplace()`**，零 spawn。
  **這不是抄近路，是等價**：那兩步就是 `claudeHome` 底下唯一會被碰到的動作，
  `verifyByExecuting` 對 `claudeHome` 的樹**沒有任何貢獻**（它只寫 `verificationRootOverride`
  指定的位置，`removexattr` 作用在 bundle 內的二進位）。先例：
  `InstallerClobberTests.performConnectStepsGuardsWriteTargetDirectly` 就是直接呼叫內部步驟，
  doc comment 逐字寫著理由；`@testable import AuraHookFile` 在 `Tests/AuraCoreTests/` 已有十個檔在用。
  序列數 5＋25＋125＋625 = **780**，總操作數 2930，毫秒級，**全跑，不縮減**。
- **CX37b（生產路徑，長度 ≤ 2 共 30 條）**：走完整的
  `installer.connect(force:translocated:inDownloads:)`，**含 spawn**，注入小的 `verificationTimeout`。
  `connectClaude` 出現次數 = 1（長度 1）＋ 10（25 條 × 2 步 ÷ 5）= **11 次真 spawn**，走 `SpawnGate`。
  守的是「完整流程也不碰另一側」，接住 CX37a 跳過那一步可能漏掉的東西。

兩條的 doc comment 要**互相點名**：a 要寫「為什麼跳過 spawn 是等價的」，b 要寫「為什麼只到長度 2」。
（**注意**：`verificationRootOverride`／`verificationTimeout` **都不能免 spawn**——前者只改驗證
session 的寫入位置，後者只改等待上限；`verifyByExecuting` 是 `performConnectSteps()` 的無條件最後一步。）

**CX38 雙 agent 端到端 wired gate**（沿用 `EndToEndWiredGateTests` 的真 spawn，見 §6.3）：
同一顆 `aura-hook`，先以 Claude payload（round1 fixture）**無參數**呼叫、再以 Codex payload
（round4 fixture）`--agent codex` 呼叫，寫到**同一個** `AGENTAURA_ROOT`；斷言兩個 snapshot
各自 `agent` 正確、activity 對；接著**反序再跑一次**。
**「互不覆蓋」是結構性結論，不是被測性質**（r4 m1）：`SnapshotIO` 以 `<session_id>.json` 分檔，
而兩份 fixture 的 session id 本來就不同，所以那個斷言在任何實作下都會通過（包括完全壞掉的實作）。
CX38 真正有牙齒的是另外兩半（同一顆二進位服務兩個上游、兩邊 `agent` 各自正確），
mutation（`--agent` 一律回 `.claude`）打的也是那兩半。gate 的 doc comment 要把這件事標明。
**明寫的假設**：兩個上游的 session id 空間不交集（Claude 的 UUID 與 Codex 的 UUIDv7）——
實務上不碰撞，但那是假設、不是我們控制的東西，列進 §10-16。

### 4.9 Codex 的模型命名：`Jargon.model`（D-u）

**這是一個既有 gate 正在紅的缺口，不是新需求。** fixture 進 repo 之後，
`FixtureCodeAnchorTests.everyFixtureModelIsMapped`（「fixture 裡出現過的每一個 model 值經
`Jargon.model` 後不再是原始代碼字」）**已經紅**：fixture 的唯一 model 值是 `gpt-5.5`，
而 `Jargon.model` 的六條規則以 `claude-` 家族的命名為前提——`gpt-5.5` 切成 `["gpt", "5.5"]`，
兩段都不是純數字（`5.5` 含 `.`），命中規則 6「多於一個非數字段 → 原樣回傳」。

**處置**：在既有演算法**之前**加一個 Codex 家族分支；**既有六條規則一行不動**，
判不出來一律落回既有的「原樣回傳」。

**Codex 家族分支的規則（四步，讓下表每一列都可推導）**：
1. 先抓 `[...]` 尾綴 → ` (內容大寫)`，其餘部分繼續處理（**與既有規則 1 同形**，不是另一套）。
2. 第一段（以 `-` 切）若是 `o` ＋ 數字開頭（`o3`、`o4`）→ **整串原樣回傳**（OpenAI 的 `o` 系列
   品牌寫法是小寫，**不得**改成 `O3`）。
3. 否則前綴必須是 `gpt-`，去前綴後名字部分固定為 `GPT`；**第一個剩餘段以連字號接上**
   （`GPT-<第一段>`，不論它是不是純數字——`4o` 也走這條，所以是 `GPT-4o` 不是 `GPT 4o`）。
4. 之後每一段**首字大寫、以空白連接**。任一步不符（沒有 `gpt-` 前綴、去前綴後為空）→ 落回既有演算法。

期望值**寫死在表裡**（`!= raw` 這種弱斷言不足以定義行為——把每個輸入都回傳 `"x"`
也能讓既有 gate 變綠）：

| 輸入 | 輸出 | 證據強度 |
|---|---|---|
| `gpt-5.5` | `GPT-5.5` | **實測**（`round4-codex.ndjson` 的唯一 model 值） |
| `gpt-5.5-codex` | `GPT-5.5 Codex` | 預期；**未在任何 payload 觀測過** |
| `gpt-4o` | `GPT-4o` | 既有測試表裡的字面（見下方 test-edit scrutiny） |
| **`gpt-5`** | **`GPT-5`** | 預期；**現行輸出是 `Gpt 5`（不是原樣回傳），本 change 刻意變更**。`["gpt","5"]` 的 `5` 是純數字 → 既有演算法**成功**並回傳 `Gpt 5`。它不在任何 fixture（層一看不到）也不在原本的釘死表（層二看不到），**正好掉在兩層守衛之間**——必須釘住，否則是一個使用者看得到的字串靜默改變（r4 M1） |
| **`gpt-4.1-mini`** | **`GPT-4.1 Mini`** | 預期；用來釘住規則 3／4 的分工（第一段連字號、其餘空白＋首字大寫） |
| **`gpt-5.5[high]`** | **`GPT-5.5 (HIGH)`** | 預期；用來釘住規則 1（Codex 分支**先**處理 `[...]` 尾綴，與既有規則同形，不是各寫一套） |
| `o3` | `o3` | 預期；規則 2 |
| `o4-mini` | `o4-mini` | 同上 |
| **`o3[high]`** | **`o3[high]`** | 預期；**兩個家族對 `[...]` 尾綴刻意不對稱**——`gpt-5.5[high]` 走規則 1 重組成 `GPT-5.5 (HIGH)`，`o` 系列則是規則 2「整串原樣回傳」，**不套用已剝除的 bracket 重組**，所以中括號原樣留著。`o` 系列有沒有 bracket 尾綴完全沒有證據，這個不對稱是刻意的；補這一列是為了讓它**被釘住**而不是只活在註解裡（T05 review m3） |
| `claude-fable-5-1` 等既有九列 | 與現在**完全相同** | 既有 `JargonTests` 釘死 |

**test-edit scrutiny（必須逐條寫進報告）**：既有 `JargonTests.modelTwoNonNumericSegmentsPassesThrough`
逐字釘死 **`Jargon.model("gpt-4o") == "gpt-4o"`**。D-u 必然會改到它。判準：
- 那條測試的**原意**是「兩個非數字段 → 原樣回傳」（Claude 家族演算法的一條性質），
  不是「gpt-4o 必須原樣回傳」。
- 所以**性質要保住**：把輸入換成不屬於 Codex 家族的例子（例如 `foo-bar-5`），
  原斷言形狀不變；**另外新增**一列釘死 `gpt-4o` 的新期望值。
- **換掉的輸入必須真的落在既有演算法的規則 6**（`foo-bar-5` → 兩個非數字段 `foo`／`bar`
  ＋ 一個數字段 → 命中規則 6，形狀成立）。換一個其實走別條規則的輸入，等於把那條測試
  換成測別的東西。
- 報告要附**「改前／改後／測的還是不是同一件事」三欄**。
- 這是**對齊新契約**不是弱化（測試名不變、被測性質不變、斷言數**增加**一條）。
  若實作者選擇直接刪掉那條測試，那就是弱化，要退回。

**守衛分兩層**：既有 `everyFixtureModelIsMapped`（fixture 推導的跨層錨點，只驗 `!= raw`）
＋ 新的 CX41（釘死的輸入→輸出表）。前者保證「fixture 裡真的出現過的值有被處理」，
後者保證「處理的方式是我們講好的那個」。**兩條都要**，缺前者會漏掉未來新增的 fixture 值，
缺後者會讓任何胡亂的映射通過。

## 5. 錯誤處理

| 情況 | 處理 |
|---|---|
| `--agent` 未知值／缺值／重複 | 落回 `.claude`；靜默、exit 0、零輸出 |
| 磁碟上 `agent` 是未知字串／非字串／`null` | `Agent(stored:)` 落回 `.claude`；**整包仍解得開**；那一列沒有標籤 |
| 舊版狀態檔沒有 `agent` 鍵 | `decodeIfPresent` → nil → `.claude`（CX11） |
| `~/.codex` 不存在／是普通檔／是斷鏈 symlink | `.unavailable`；**不建立它**；面板零 Codex 元素 |
| App 是 translocated 或在 `~/Downloads` | 路由層 → `.blockedByBundlePath(.mustMoveToApplications)`；`performConnectCodex()` 前置 guard → banner，**不動任何檔**；執行層 → `CodexFailure.mustMoveToApplications`。snippet 一律 nil（R-10） |
| hook 路徑含空白／`'`／`"`／`$`／`` ` ``／`\` | 三層同上，訊息**指名那個字元**；snippet **照給**（那個路徑不會消失，只是我們不敢替他寫） |
| **已接上、但 App 現在跑在被拒的位置** | `.connectedStalePath` ＋ `pathRejection != nil` → 面板**不給「重新接上」按鈕**，只說「先把 App 移回去」；即使有別的路徑送出 `.connectCodex`，`performConnectCodex()` 的第一行 guard 也會在**任何 `disconnect` 之前** return（R-9） |
| `~/.codex/hooks.json` 已存在（普通檔／目錄／symlink／斷鏈 symlink） | `connect` 一律 throw `.alreadyExists`；**那個路徑（含 symlink 指向的目標）位元組與型別完全不變**（CX15，含「symlink 指向 `config.toml`」那一格） |
| `hooks.json` 存在但內容對不上（或 > 64 KiB 沒讀） | `.occupiedByOther`；不提供刪除按鈕；`disconnect` 若被呼叫一律 throw `.notOurs` |
| 磁碟內容 == 憑證但 != 現在路徑的預期內容 | `.connectedStalePath`（兩種文案見上） |
| 憑證遺失（使用者清過偏好設定） | `.occupiedByOther`（保守：認不得就不碰） |
| `connect` 寫入失敗（權限、磁碟滿） | throw `.writeFailed(errno)` → banner；**不重試、不 fallback 到非原子寫法** |
| 讀 `hooks.json` 失敗（權限） | `.occupiedByOther`（讀不到不等於不存在） |
| Codex 未信任 hook（F5） | **偵測不到**。UI 不得宣稱已生效；help／INSTALL 寫明 |
| **對任一側的操作影響到另一側** | 不得發生（R-8 §4.8 的不變式）；檔案半由 CX37a／CX37b 守、**憑證半由 CX42 守**、端到端由 CX38 守 |
| 收尾步驟（codex disconnect）在完整移除中失敗 | `try?` 吞掉，後面步驟照跑（Lessons #8）；`verify-uninstall.sh` 第 7 項會把殘留說出來 |

## 6. 測試策略

T01 先行（測試＋compile-only stub，零生產碼，禁 `fatalError`）。swift-testing。
**測試中絕不跑 `codex exec`**（F12）、**絕不碰真的 `~/.codex`／`~/.claude`**。

### 6.1 對抗式 double（Lessons #1；T01 必含）
1. **payload**：缺 `permission_mode`／缺 `model`／`tool_response` 是 200 KB 字串／
   `hook_event_name: "Interrupt"` **帶** `agent_id`／`session_id` 是 UUIDv7。
2. **argv（8 格表）**：`[]`、`["--agent"]`、`["--agent","gemini"]`、`["--agent","CODEX"]`、
   `["--agent=codex"]`、`["--agent","codex","--agent","claude"]`、`["--agent","codex","--agent"]`、
   **`["--agent","gemini","--agent","codex"] → `claude`**（T02 review M1）。
   **第 8 格釘住的是「第一個*出現*者勝」而不是「第一個*有效*者勝」**——前七格兩種語意給的答案完全相同，
   reviewer 用一個「未知值不回傳、繼續往後掃」的替代實作實跑，七格**全綠**。而「第一個有效者勝」等於
   **讓使用者手寫錯的第一個旗標被後面的悄悄蓋過去**，正是 D-d 那段理由要防的事。
   **CX7 與 CX8 共用的唯一來源**——盲點會原封不動傳給另一條（Lessons #1 的形狀）。
3. **檔案系統**：`hooks.json` 是目錄／symlink 指向 `config.toml`／斷鏈 symlink／別人的合法 JSON／
   5 MB 垃圾（> 64 KiB，驗 D-q）；`~/.codex` 自己是外部 symlink／是普通檔／不存在。
4. **路徑**：`translocated: true`／`inDownloads: true`／六個不支援字元各一／**同時 translocated
   ＋ 含空白**（驗優先序）／乾淨路徑（負對照）。
5. **兩側交錯（R-8）**：同一個 fixture home 下同時有 `claudeHome` 與 `codexHome`，供 CX37a／CX37b 推導序列；
   App 層另備 fake installer／fake store ＋ 注入 suite，供 CX42 的 20 條序列使用（零 spawn）。
6. **`FakeCodexStore`**：可設定「寫進去與讀回來不一致」。
7. **`FakeCodexInstaller`**：① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
   ② `disconnect()` 宣稱成功但檔案還在；③ `probe()` 丟錯；
   ④ **記錄 `connect`／`disconnect`／`probe` 的呼叫順序與次數**（CX24⑤、CX35、CX39 要用）。

### 6.2 composition-root smoke
- `codexInstallerIsInjected`；`productionCodexHomeIsRealHome`（行為 ＋ 來源掃描不得用
  `environment["HOME"]`）；`codexConnectChainIsWired`（五段，CX24）；
  `codexRowsReachTheView`（`.unavailable` 時 `preferredContentSize` 與零 Codex 狀態完全相同）。

### 6.3 Gate 表（新增一律 `CX<n>`，共 **46** 條；CX37 拆成 a／b；既有 gate 寫測試函式名）

| Gate | 層 | 守什麼 | Mutation（→ 指名測試 ≤60s 變紅） |
|---|---|---|---|
| CX1 `codexEventSetIsPinnedToProbe` | AuraCore | `codexEvents` 恰等於 F2 的 12 個字面名；doc comment **分標兩種證據強度**（六個有真實 payload／六個只有二進位字串列舉） | 加一個／少一個 |
| **CX2 `interruptNeverEntersHandledEvents`** | AuraCore | `handledEvents.isDisjoint(with: codexOnlyEvents)`；**失敗訊息必須寫出後果**（Claude 側整份 hooks 失效、產品對 Claude 使用者完全停止運作），**並帶 §4.2 的 runtime 限定語**（本機 validator 只給 warning，整份拒載是跨機器實測）。**不要求逐字某四個字**——寫得更完整的訊息不該被改回更短的（T03 review m3） | 把 `Interrupt` 加進 `handledEvents` |
| CX3 `codexSharedEventsReuseClaudeMapping` | AuraCore | `codexEvents − codexOnlyEvents ⊆ handledEvents`，每個 `effect` 非 `.noChange` | 從 `handledEvents` 拿掉 `PreCompact` |
| **CX4 `codexOnlyEventsMapToIdle`** | AuraCore | 定義域**從 `codexOnlyEvents` 推導**；`Interrupt → idle` 的唯一守衛 | 刪掉 `case "Interrupt"` 整行 |
| CX5 `claudeHooksJSONHasNoInterrupt` | AuraCore | `plugin/hooks/hooks.json` 不含 `Interrupt`（獨立於既有雙向等式）；**加定義域非空守衛**——`hooks` 物件若解析成**空字典**，`try #require` 會通過、`registered` 為空集合、交集為空而靜默全綠（T03 review m1；CX1／CX3／CX4 三條姊妹 gate 都有這個守衛，只有它沒有） | 在 Claude hooks.json 加 `Interrupt` |
| **CX6 `codexHooksJSONMatchesF14Verbatim`** | AuraCore | ① 鍵集合 == `codexEvents`；② **12 個 entry 逐一逐字等於 F14**（`matcher: ""`、無 `async`），唯一數值偏離 `timeout` 5→3，失敗訊息帶 F13 引文。**`command` 與 `agentFlag` 的期望值一律寫死字面**（`== "<path> --agent codex"`），**不得引用 `CodexHooksJSON.agentFlag`**——拿產生器的輸出跟產生器自己的常數比，常數被改壞時兩邊一起變、斷言恆真（T04 review M1 實測：把 `agentFlag` 改成 `"--agent codexx"`，全量 808 條測試**零新紅**）；③ **對抗式路徑 round-trip**：含**空白／`"`／`\`** 的路徑產出仍是合法 JSON 且 `command` 解析回原路徑（不是理論情境——D-s／R-10 明訂 `.unsupportedCharacter` **仍要給 snippet**，所以生產必然會用含這些字元的路徑呼叫 `snippet(...)`；跳脫壞了，使用者複製到的是壞掉的 JSON，而他正是只剩手動貼上這條路的人）；④ **跨 module round-trip `generatedFlagIsUnderstoodByTheParser`**：把產生出來的旗標拆成 argv 餵進**真的** `AgentArgument.agent(from:)`，斷言回 `.codex`——這是 T02↔T04 的接縫（`CodexHooksJSON` 寫出去的字面與 `Agent.codex.rawValue` 是兩份各自維護的字串），**兩個方向都擋**（改壞產生器、或改壞解析規則） | ① 寫死 11 個 ② 拿掉 `matcher` ③ 加 `async: true` ④ 漏 `--agent codex` ⑤ **`timeout` 改回 5** ⑥ **`agentFlag` 改成 `"--agent codexx"` → ②與④必須紅** |
| CX7 `agentArgumentParsing` | AuraCore | §6.1(2) 的 **8 格**表逐格；**開頭加定義域非空守衛**（`cases.count == 8`，本 repo 既有慣例是把非空守衛寫進 gate 自己，否則 `--filter` 單獨跑時表變空會靜默全綠） | ① 未知值改成回 `.codex` ② **改成「第一個*有效*者勝」（未知值不回傳、繼續往後掃）→ 第 8 格必須紅** |
| CX8 `auraHookStaysSilentForEveryAgentArgument` | E2E（真 spawn） | 同一張 **8 格**表，`SpawnGate` 內序列跑：exit 0、stdout 空、stderr 空 | 解析失敗時寫 stderr |
| CX9 `claudeStateFileHasNoAgentKey` | AuraCore ＋ **E2E** | **兩層，缺一不可**（T05 review M1）：① **純函式層**——round1／1b／2／3 跑 merge，用**生產的 `SnapshotIO.encoder`**（不是測試自建的 `JSONEncoder`：gate 哲學第 1 條，不要在生產機制外面再包一層自己的近似）序列化後**不含** `agent` 鍵，涵蓋四份 fixture 的每一筆；② **生產層**——**不帶 `--agent` 真 spawn 一次**，讀**原始檔案文字**斷言 `!raw.contains("\"agent\"")`（CX10 那條位元組斷言的鏡像，走完整 `main.swift` → `SnapshotIO.encoder` → 檔案）。理由：**`agent == nil` 與「檔案裡沒有這個鍵」不是同一件事**——哪天有人寫自訂 `encode(to:)`，檔案可能出現 `"agent":null`，解碼回來仍是 nil、上游 gate 全綠，而 DoD #5 宣稱的「位元組完全相同」已經破了。兩條的 doc comment 互相點名（一條驗鍵不存在、跑得快；一條驗真檔案位元組、只跑一次） | ① `.claude` 也寫 `"claude"` ② **`agent` 改成非 Optional 帶預設 `""`（或加一個會寫 null 的自訂 encode）→ 生產層那半必須紅** |
| CX10 `codexStateFileCarriesAgent` | E2E（真 spawn） | `--agent codex` 真跑 → 檔案含 `"agent":"codex"` | `main.swift` 忘了傳 agent |
| CX11 `legacySnapshotWithoutAgentDecodes` | AuraCore | 無 `agent` 鍵的舊 JSON 解得開且 `.claude` | `agent` 改成非 Optional |
| CX12 `unknownAgentFallsBackWithoutFailingDecode` | AuraCore | `"agent":"gemini"` → 整包解得開、`.claude`、無標籤 | `agent` 改成 `Agent?`（enum） |
| CX13 `round4FixtureParsesAndMatchesProbeTable` | AuraCore | 18 筆全解析；`effect` 與欄位表一致；`isSafeSessionID` 全過；**外加欄位層反向斷言：探針表列出的每個欄位，在該事件的樣本裡至少出現一次**（T01 review M3：事件層的反向斷言擋不住「把 fixture 裡每一筆的 `model` 欄位拿掉」——那會讓跨層錨點 `everyFixtureModelIsMapped` 從紅變綠，**用縮小證據來消滅一條紅燈**；欄位層是唯一看得到它的東西，與那條錨點是同一條防線） | ① **`Stop` 改成 `.noChange`** ② **從 fixture 抽掉某個事件的一個欄位**（例如 `SessionStart` 的 `model`）→ 欄位層那半必須紅 |
| **CX14 `codexInstallerTouchesOnlyHooksJSON`** | AuraHookFile | 整棵樹差異**恰為** `{hooks.json}`；`config.toml` 位元組不變 | connect 順手寫 `hooks.json.bak` |
| **CX15 `codexConnectRefusesEveryOccupiedShape`** | AuraHookFile | 佔用形狀各 throw `.alreadyExists`，且該路徑（含 symlink 目標）位元組與型別不變 | 拿掉 `O_EXCL`（symlink→`config.toml` 那格必須紅） |
| CX16 `codexConnectWritesGeneratorBytes` | AuraHookFile | 檔案內容 == 產生器位元組；回傳值 == 那些位元組 | 少寫最後一個 byte |
| CX17 `codexDisconnectOnlyRemovesOurBytes` | AuraHookFile | 逐位元組相符才刪；改一 byte → 不刪＋throw；nil → 不刪；`(dev,ino)` 被換 → 不刪 | ① 拿掉內容比對 ② 拿掉 `(dev,ino)` 複查 |
| CX18 `codexHomeSymlinkWritesInsideResolvedPath` | AuraHookFile | 字面樹不變、`realpath` 樹差異恰為 `{hooks.json}` | 快照改用字面路徑 |
| CX19 `codexStateCoversEveryObservationShape` | AuraCore | 判定表逐格；定義域由五個維度的乘積**推導**，不寫格數 | ① `symlink` 併進 `.notConnected` ② 第 2／3 列對調 |
| CX20 `codexRowsAppearOnlyWhenAvailable` | AuraCore | 逐 `CodexStateKind`（含兩種 Rejection）斷言列數與 action：`.unavailable`／`.occupiedByOther`／`.blockedByBundlePath` 零列；`.notConnected`／`.connected` 恰一列；**`.connectedStalePath` 依 `pathRejection` 分兩列／一列**（R-9） | ① `.unavailable` 也給「接上 Codex」 ② 被拒時仍給「重新接上」 |
| CX21 既有 `optionsRowsCoverEveryAction` ＋ `nonMenuKindsIsExactlyThatLiteralSet` 擴充 | AuraCore | 代表狀態集合由 `CodexStateKind.allCases.flatMap(CodexState.samples)` 推導；`nonMenuKinds` 四個 → 五個 | 把 `.connectCodex` 塞進 `nonMenuKinds` |
| CX22 `agentLabelOnlyForNonClaude` | AuraCore ＋ 像素 | model：claude → nil、codex → "Codex"；像素：同一列兩者 `differingPixels > 0` | 標籤對 claude 也給值 |
| **CX23 `codexLabelDoesNotChangeRowHeight`** | App（離屏） | 帶標籤的列高仍是 43／59pt（±0.5） | 標籤另起一行 |
| **CX24 `codexConnectChainIsWired`** | App | 五段：① 接線 ② fake 收到 `connect` ③ **憑證取回是同一串位元組** ④ banner 含兩個關鍵詞（從 `L10nCodex` 鍵推導）⑤ spy 記 `probe()` 次數，`onOpen` 後 ≥ 1 | ① 分支改 `break` ② banner 只留一句 ③ 拿掉 `onOpen` 的 `reprobeCodex()` |
| CX25 `productionCodexHomeIsRealHome` | App ＋ 掃描 | §6.2 第二條 | 改成 `environment["HOME"]` |
| CX26 `uninstallRemovesCodexBeforeErasingDefaults` | App | codex disconnect **早於** `removePersistentDomain` | 兩步對調 |
| CX27 `verifyUninstallScriptDetectsOurCodexHooks` | script | 暫存 `CODEX_HOME` ＋ `--only 7`；**判準是那一行的 PASS/FAIL**。**外加兩格參數驗證**（T11 review M1 實測）：① **`--only`（缺值）在有界時間內以非零退出**（實測會**無限迴圈且零輸出**——`--only)` 分支無條件 `shift 2`，而 bash 在 `$# < 2` 時 `shift 2` 不改 `$#` 也不中止，腳本只有 `set -uo pipefail` 沒有 `-e`）；② **`--only 77` 以非零退出，且輸出不得含「PASS」**（實測 `--only 77`／`--only 0`／`--only seven` 都是**一項都沒跑、然後印「完整移除驗收 PASS」**）。理由：腳本**第 4 項自己**為了不把「問不到」誤當「通過」特地多寫了 `LOGIN_ASKED`，而 `--only` 這條路徑把同一個錯犯在**整支腳本的總結論**上——而它正是「移除乾淨是測試能力的前提」那條 invariant 的驗收工具 | ① 拿掉腳本第 7 項 ② **拿掉 `--only` 的值域檢查（`[1-7]`）→ ②那格必須紅** |
| CX28 `helpDocsCoverCodexRows` | 文件 | `allRows` 對 `CodexStateKind.allCases` 取**聯集**，兩語言各守 | **只刪其中一個標題**也必須紅 |
| CX29 `securityDocListsEveryPathWeWrite` | 文件 | **三份文件都要含** `.codex/hooks.json`（字面來自生產常數）：`SECURITY.md`、`README.md`、**`README.zh-TW.md`**，寫成 `@Test(arguments: [...])` **參數化**而不是三條各寫一遍。T11 review m1 實測：把路徑從 SECURITY.md 與 README.md **兩邊都刪掉**，當時只紅 **1** 條——內容是有的，缺的是守衛 | 從**任一份**刪掉那一行都必須紅（三份各試一次） |
| CX30 `noCodexExecInRepo` | 全 repo | **roots = `Tests/` ＋ `scripts/` ＋ `.github/`** 不得出現 `codex exec`（＋暫存目錄正向對照）。`.github/` 是新加的：repo 有 CI（`ci.yml`），**那裡的指令會真的被執行**，而 F12 的代價（改使用者的 `config.toml`）在 CI 上同樣成立。**`docs/` 刻意不納入**——F12 的證據文件必須**逐字**寫出那個指令名，掃它等於要求證據文件自我審查。**新增任何可執行面時 roots 要跟著加，而沒有測試會提醒你**（這是這條 gate 已知的人工維護點） | 在 `scripts/` 或 `.github/` 加一行 `codex exec` |
| **CX31 `codexHookStoreRoundTripsBytes`** | App | `write(bytes)` → `contents == bytes` **逐位元組**；輸入用**真正的產生器輸出** | 在 `write` 裡加 `trimmingCharacters` |
| **CX32 `codexConnectRefusesBlockedBundlePath`** | AuraHookFile | translocated／inDownloads／含空白各一 → throw 對應 `CodexFailure`，**且整棵樹零差異** | 拿掉 `connect` 第一行的 guard |
| **CX33 `codexPathCheckNamesTheOffendingCharacter`** | AuraCore | 六個字元逐格（定義域從集合推導）；帶**第一個**命中的字元；translocated 優先；乾淨路徑 nil | ① 一律回 `.unsupportedCharacter(" ")` ② 優先序對調 |
| **CX34 `codexStalePathIsDetectedAndOffersReconnect`** | AuraCore | 磁碟 == 憑證 != 現在預期 → `.connectedStalePath`（三份內容都用真產生器輸出、兩個不同路徑）。**fixture 的兩條路徑都不得含 `unsupportedCharacters` 的字元**（例如 `/Applications/AgentAura-2.app`，不要 `AgentAura (2).app`——含空白的路徑在生產中會先落到 `.blockedByBundlePath`，那是一個不可能發生的搬家情境，T07 review m4） | `from` 忽略 `currentExpectedContents` |
| **CX35 `stalePathReconnectDisconnectsBeforeConnecting`** | App | **（前提：`pathRejection == nil`）** `.connectedStalePath` 下送 `.connectCodex` → 呼叫順序是 `disconnect` → `connect`；`.notConnected` 下只有 `connect` | 直接 `connect`（不先 disconnect） |
| **CX36 `codexSectionRendersEveryState`** | App（離屏） | 六態 ＋ 兩種 Rejection 各渲一次：預期元素在（按鈕／snippet 區塊／指名字元的文案）；`.unavailable` 不畫任何東西 | ① 錯誤文案不插字元（籠統句） ② 被拒時仍畫「重新接上」按鈕 |
| **CX37a `bothSidesNeverDisturbEachOthersFiles`** | AuraHookFile | R-8 不變式 1（檔案半）：**程式推導**全部長度 ≤ 4 的操作序列（**780 條，全跑**），`connectClaude` 走 `guardWriteTarget()` ＋ `atomicReplace()`（零 spawn，等價理由見 §4.8）；每步之後「另一側」整棵樹零差異；結束時若兩側皆 connected，兩側 `probe()` 皆 connected | `CodexInstaller.connect` 順手 touch `<claudeHome>/skills/agentaura` 的 mtime |
| **CX37b `bothSidesNeverDisturbEachOthersFilesOnProductionPath`** | AuraHookFile | 同上不變式，但 `connectClaude` 走**完整** `connect(force:translocated:inDownloads:)`（含 spawn，注入小 `verificationTimeout`）；長度 ≤ 2 共 **30 條**、**11 次真 spawn**、走 `SpawnGate`。接住 CX37a 跳過 exec 驗證可能漏掉的東西 | 同 CX37a（兩條都必須紅） |
| **CX38 `oneBinaryServesBothAgentsInOneRoot`** | E2E（真 spawn） | R-8 不變式 2：同一顆 `aura-hook`，Claude payload（round1，無參數）與 Codex payload（round4，`--agent codex`）寫進**同一個** `AGENTAURA_ROOT`；兩個 snapshot 的 `agent`／activity 各自正確；**反序再跑一次**。**「互不覆蓋」在 doc comment 標成結構性結論**（id 空間不交集），不是被測性質 | `--agent` 解析改成一律回 `.claude` |
| **CX39 `codexReconnectNeverDisconnectsWhenPathIsRejected`** | App | 注入 `.connectedStalePath` ＋ `translocated: true` → 送 `.connectCodex` → **`disconnect` 呼叫次數 0**、檔案仍在、banner 是 `.mustMoveToApplications` 那句 | 把 guard 移到 `disconnect` 之後 |
| **CX40 `codexSnippetIsWithheldWhenPathWillVanish`** | AuraCore ＋ App | **乘積表**：定義域 `CodexStateKind.allCases × [nil, .mustMoveToApplications, .unsupportedCharacter(" ")]`，斷言 `.mustMoveToApplications` **整行** `codexSnippet == nil`（含 `.occupiedByOther`）；`.unsupportedCharacter` 整行非 nil | 拿掉 `codexSnippet` 的條件 |
| **CX41 `jargonModelCoversCodexNaming`** | AuraCore | §4.9 的**釘死輸入→輸出表九列**（含 `gpt-5`／`gpt-4.1-mini`／`gpt-5.5[high]` 與 `o` 系列維持小寫）；既有九列反例輸出**完全不變** | ① Codex 分支回傳 raw ② 把 `o3` 改成 `O3` ③ **把 Codex 分支從既有演算法之前移到之後 → `gpt-5` 那列必須紅**（那是唯一能區分前置／後置的輸入） |
| **CX42 `bothSidesNeverDisturbEachOthersCredentials`** | App | R-8 不變式 1（憑證半，r4 M3）：定義域 `{performConnect, performDisconnect, performConnectCodex, performDisconnectCodex}` 的**全部長度 ≤ 2 序列＝20 條**（程式推導，不手列）；fake installer／fake store ＋ 注入的 `UserDefaults` suite，全記憶體、**零 spawn**。每步之後斷言**另一側的鍵位元組完全不變**（Claude 側三個 `AgentAuraHook*` vs Codex 側 `AgentAuraCodexHookContents`），且該 suite **沒有其他鍵被新增或刪除**（用鍵集合的**差集**斷言，不逐鍵列舉——鍵清單會 drift） | `performDisconnect()` 順手 `defaults.removeObject(forKey: CodexHookStore.key)` |
| **CX44 `noPendingFlagRemains`** | 全 repo 掃描 | **`Sources/` ＋ `Tests/`** 都不得殘留 `AURA_CODEX_PENDING`（T07 review M1：本 change 有**四個**「等下一個 task 替換」的 stub，分屬三種機制——`#if` 旗標會 `Issue.record` 而紅、`switch` 的 `break` 靠既有 gate 誠實紅、窮盡 switch 的暫定值靠「動 view 時一定看到」、而 `OptionsSectionView` 硬編 `.unavailable` **既不紅也不在必經路徑上**。**只有可 grep 的標記能一次全包**，所以四處一律貼 `AURA_CODEX_PENDING_T<nn>` 註解，掃描範圍含 `Sources/`）。**＋暫存目錄正向對照**證明掃描沒壞（比照 CX30 的形狀） | 在 `Sources/` 與 `Tests/` 各留一個 `AURA_CODEX_PENDING_T08`（兩處都要紅） |
| **CX46 `optionsRowsCallSitePassesRealCodexState`** | AuraCore（來源掃描） | `Sources/` 不得出現字面 `codex: .unavailable` 或 `codexPathRejection: nil`——生產呼叫點必須傳**真的值**。比照既有 `L10nProductionCallSitesPassLanguageTests`（那條 gate 存在的理由與這裡一模一樣）。**為什麼需要它**：T07 在 `OptionsSectionView` 的生產渲染路徑硬編 `.unavailable`／`nil` 當 stub，而**那個 stub 的失效是靜默的**——`.unavailable` 正是目前所有測試期待的值，T08 忘了替換也沒有任何一條會紅，後果正是本 spec 花四輪在防的那類：使用者裝了 Codex、面板開了、Options 裡什麼都沒有，而全套測試綠（T07 review M1） **已知假陰性（寫進 gate 的 doc comment）**：① **跨行寫法掃不到**——`OptionsMenuModel` 換行再接 `.rows(` 時，單行比對看不見（T08 review m1 實測）；② 註解過濾有兩個缺口（block comment、行尾註解），**兩個缺口方向相反**（一個漏抓、一個誤抓），而誤抓那側**失敗得很大聲**（gate 紅在一個其實沒問題的地方，有人會去看）。CX24／CX35 的**行為斷言**才是這條路徑的主守衛，本條是便宜的第二道 | 把 view 那一行改回 `codex: .unavailable, codexPathRejection: nil` |
| **CX45 `sessionStateProductionConstructionSitesPassAgent`** | AuraCore（來源掃描） | `Sources/` 底下 `SessionState(` 的出現次數**恰為 1**，且那一處包含 `agent:`。失敗訊息寫明「新增生產建構點時必須明傳 `agent`，**預設值只服務測試**」。（T05 review m1：預設值本身是對齊既有慣例、不是 tested≠wired——生產建構點恰一個且明傳，刪掉明傳會讓既有 gate 立刻紅；殘餘缺口只有「未來新增第二個生產建構點」這個方向，本 repo 已有同型 gate 可抄：`L10nProductionCallSitesPassLanguageTests`、`HookVerificationStoreSourceScanTests`） | 在 `Sources/` 加第二個 `SessionState(` 建構點且不傳 `agent:` |
| 既有全部 gate | — | 繼續綠（尤其 `registeredEventsMatchHandledEvents`、`installerTouchesOnlyAllowedPaths`、`everyFixtureModelIsMapped`（**目前紅，本 change 必須修好**）、`fileLengthLimit`、`nonUITargetsLoadNoUIModules`、`noStrayLiteralOutsideAllowlist`、`panelModelMakeHasNoDefaults`、`RowHeightDerivationTests`、`FooterPositionStabilityTests`） | — |

### 6.4 test-edit scrutiny 預告（Lessons #3）
1. `nonMenuKindsIsExactlyThatLiteralSet`：四個 → 五個（契約變更不是弱化）；
   **連帶**改 `OptionsMenuModel.swift` 逐字寫著「字面集合恰為這四個」的 doc comment。
2. `PanelModel.make` 新增無預設值參數 → **63 個呼叫點（27 個檔）**（T08 實測；以括號配對量，`grep 'PanelModel\.make('` **抓不到隱式成員寫法** `spy.setPanel(.make(icon: …))`）。
3. `MergeRules.merge` 新增 `agent:` → **7 個呼叫點**。
4. `OptionsMenuModel.rows` 新增 `codex:` → **26 個呼叫點（10 個檔）**。
4b. **`SessionState.init` 的 20 個測試建構點（19 個檔）——第四條 fan-out**（T05 review m4）。
   **本條以預設值 `.claude` 吸收**，不是 94 個呼叫點那種逐點改：`SessionState.init` 本來就有
   `toolDescription`／`notificationMessage` 兩個預設值，不是為了這次方便而發明的慣例；
   **生產建構點恰好一個**（`SessionReducer`）且明傳 `agent:`。理由與守衛見 `SessionState.agent`
   的 doc comment 與 **CX45**（來源掃描，防的是「未來新增第二個生產建構點時忘了傳」）。
   **這條要記在帳上**——T08 做 `PanelModel.make` 那 61 處時，帳上三條與實際四條對不起來，
   而「有幾條 fan-out」正是 test-edit scrutiny 用來判斷「這批機械改動有沒有夾帶弱化」的基準。
5. **無預設值參數的呼叫點計數不再是驗收條件**（T08 裁決 1）——**編譯器已經代答了**：
   三個新參數都沒有預設值，所以「有沒有漏」由編譯通過證明，grep 的數字對它零貢獻。
   而那個數字**已經連錯五次**（T02 差 3、T03 差 3、T04 差 1、T05d 差 51、T08 的隱式成員寫法漏抓）。
   計數**只作報告資訊**，不作驗收。真正需要數字的是 `#expect(` 淨增（編譯器代答不了），
   而它一律用**合併後 head 的絕對值**。
5b. 上面 2／3／4 合計 96 個呼叫點（**4b 不計入**，它以預設值吸收）：**`#expect(` 淨數量不得下降**
   （基準 **1649**，量法見 DoD #2 的更正）。
6. `HelpDocOptionsRowCoverageTests.allRows` 改成對 `CodexStateKind.allCases` 取聯集。
7. `ClaudeHomeTreeSnapshot` 抽成共用 `DirectoryTreeSnapshot`（CX14／CX32／CX37a／CX37b 共用）——**純重構**，
   既有 `installerTouchesOnlyAllowedPaths` 全綠且 **mutation 當場重跑**確認仍精準紅。
8. **`JargonTests.modelTwoNonNumericSegmentsPassesThrough`**（§4.9）：輸入從 `gpt-4o` 換成
   非 Codex 家族的例子以保住原性質，**另外新增**一列釘死 `gpt-4o` 的新期望值。
   直接刪掉那條測試＝弱化，要退回。
9. **`PanelAction.samples` 的 doc comment** 補「`switch` 不得有 `default`」一句（r3 m2，順手，零風險）。

### 6.5 已知不可測（寫進 §10 與最終報告）
- Codex 是否真的載入並執行我們寫的 hooks.json（F12）→ 實機 ②③。
- 信任提示的 UX 與「拒絕信任」的行為（F5）→ 實機 ④。
- `PermissionRequest`／`Interrupt`／`Subagent*` 的實際 payload 形狀（F10）→ 互動探針。
- hook 父行程的 `comm` 與**互動 TUI 的行程結構**（F15 範圍限定）→ 互動探針 ＋ 實機 ③。
- 含空白路徑＋引號的 `command` 是否可行（R-7）→ 互動探針工具包。
- **兩側同時真的在跑**（R-8 不變式 2 的人類面）→ 實機 ⑧（CX38 只驗到同一顆二進位與兩邊 `agent` 各自正確，
  沒有驗到兩個上游**同時**真的觸發它）。

## 7. DoD

門檻與量法見 `docs/superpowers/plans/2026-09-18-codex-support-dod.md`（每條有數字）。

## 8. 檔案佈局與回寫

### 8.1 檔案（估行；`Sources/` 基準 7846 行）
```
Sources/AuraCore/Agent.swift                       新  ~60
Sources/AuraCore/EventMapping.swift                改  +25
Sources/AuraCore/CodexHooksJSON.swift              新  ~80
Sources/AuraCore/CodexHookPathCheck.swift          新  ~75（＋RejectionKind／Rejection.samples，r4）
Sources/AuraCore/CodexState.swift                  新  ~115（逼近 200 就把 CodexFailure 拆檔）
Sources/AuraCore/Jargon.swift                      改  +30（Codex 家族分支；既有六條規則一行不動）
Sources/AuraCore/SessionSnapshot.swift             改  +10
Sources/AuraCore/MergeRules.swift                  改  +6
Sources/AuraCore/SessionReducer.swift              改  +2
Sources/AuraCore/SessionState.swift                改  +5
Sources/AuraCore/PanelViewModel.swift              改  +6
Sources/AuraCore/PanelAction.swift                 改  +27（三個 case × kind × samples ＋ default 禁令註解）
Sources/AuraCore/OptionsMenuModel.swift            改  +26（六態＋stale 兩種列數 ＋ 註解修正）
Sources/AuraCore/PanelModel.swift                  改  +14
Sources/AuraCore/L10nCodex.swift                   新  ~145（含兩種 Rejection、stale 兩句、snippet withheld 一句、七個 CodexFailure）
Sources/AuraHookFile/CodexInstaller.swift          新  ~125
Sources/AuraHookFile/CodexInstaller+Probe.swift    新  ~70
Sources/aura-hook/main.swift                       改  +3
Sources/AgentAuraApp/CodexHookStore.swift          新  ~45
Sources/AgentAuraApp/CodexSectionView.swift        新  ~130（六態＋兩種 Rejection＋snippet 有無）
Sources/AgentAuraApp/AppDelegate+Codex.swift       新  ~120（五個行程常數欄位＋前置 guard＋四個 perform）
Sources/AgentAuraApp/AppDelegate+Links.swift       新  ~45（**純搬移，r9 起落在 T07**）
Sources/AgentAuraApp/AppDelegate+PanelActions.swift 改 −45 +8
Sources/AgentAuraApp/PanelView.swift               改  +8
Sources/AgentAuraApp/Uninstaller.swift             改  +8
Sources/AgentAuraApp/AppDelegate.swift             改  +10
                                                   合計 ≈ +1060（門檻 1150，§7；r3 是 975／門檻 1050，
                                                   r4 增量＝Jargon +30、RejectionKind +20、
                                                   stale/snippet 兩種文案與分支 +35）
Tests/AuraCoreTests/Fixtures/round4-codex.ndjson   已就位（18 筆／4 個 session，唯讀證據）
Tests/AuraCoreTests/*（新）：AgentArgumentTests、CodexEventSeamTests、CodexHooksJSONTests、
  CodexHookPathCheckTests、CodexStateTests、CodexOptionsRowTests、CodexInstallerTests、
  CodexInstallerClobberTests、CodexPathScopeTests、CodexCoexistenceSequenceTests（CX37a／CX37b）、
  Round4FixtureTests、AgentSnapshotCodableTests、JargonCodexModelTests（CX41）
Tests/AuraCoreTests/Support/DirectoryTreeSnapshot.swift  新（從 ClaudeHomeTreeSnapshot 抽出，純重構）
Tests/AgentAuraAppTests/*（新）：CodexWiringSmokeTests、AppDelegateCodexWiredTests、
  CodexHookStoreTests、CodexRowLabelPixelTests、CodexSectionRenderTests（CX36）、
  CodexCredentialSequenceTests（CX42）、
  Support/FakeCodexInstaller、Support/FakeCodexStore
Tests/AuraCoreTests/EndToEndWiredGateTests.swift   改（CX38 兩個方向；注意 300 行上限，必要時拆
                                                   EndToEndDualAgentTests.swift）
scripts/verify-uninstall.sh                        改（第 7 項 ＋ CODEX_HOME ＋ --only ＋ 第 2 行註解）
```

**單檔上限的八個風險點**：

| 檔案 | 現況行數 | 上限 | 要加什麼 | 處置 |
|---|---|---|---|---|
| `Sources/AgentAuraApp/AppDelegate+PanelActions.swift` | **200** | 200 | 三個新 case（**T07**，它的 `switch action` 窮盡無 `default`）＋ `refreshPanel` 帶 codex（T10） | **T07 第一步 (b)** 預先搬移到 `AppDelegate+Links.swift`（r9：原排 T10，但加 case 與讓它編得過必須在同一個 task） |
| `Tests/AuraCoreTests/OptionsMenuModelTests.swift` | **300** | 300 | CX20／CX21 ＋ `rows(` 新參數 | T07 第一步拆 `CodexOptionsRowTests.swift` |
| `Tests/AgentAuraAppTests/AppDelegatePanelActionsWiredTests.swift` | **300** | 300 | `panelActionsAreWired` 涵蓋 3 個新 kind | T10 第一步拆 `AppDelegateCodexWiredTests.swift` |
| `Tests/AuraCoreTests/MergeRulesTests.swift` | 294 | 300 | `merge(` 新參數（1 處） | 餘裕 6 行 |
| `Tests/AuraCoreTests/PanelViewModelTests.swift` | 288 | 300 | CX22 的 model 半 | 餘裕 12 行；寫不下放 `CodexRowLabelPixelTests` |
| `Tests/AuraCoreTests/EndToEndWiredGateTests.swift` | 149 | 300 | CX38 兩個方向 | 餘裕充足；超了就拆 `EndToEndDualAgentTests.swift` |
| `Sources/AuraCore/CodexState.swift`（新） | — | 200 | 六態 ＋ Kind ＋ samples ＋ `CodexFailure` | 估 ~115；逼近 200 就把 `CodexFailure` 拆檔 |
| **`Sources/AgentAuraApp/StatusItemController.swift`** | **200** | 200 | **本 change 預期不動它**——它的佔位 model 永遠是 `.unavailable`，不隨 Codex 狀態變（那是 popover 掛載前的必要佔位：`contentViewController == nil` 時 `NSPopover.show` 會丟 NSException 殺行程），`AppDelegate` 首次 `refreshPanel()` 就會覆蓋 | **寫觸發條件，不做預防性搬移**（T08 裁決 6）：**若** T09／T10 發現必須在這個檔加任何一行，**先停下來**做一次零行為變更的純搬移 commit（照 T07 `AppDelegate+Links.swift` 的形狀：`#expect(` 前後不變、被搬函式名一字不改），**不准刪註解或空行擠**。為沒人要碰的檔做預防性搬移是 churn，而純搬移本身也有風險（T07 兩次都撞到別的 gate） |

### 8.2 回寫（逐句）
| 位置 | 改為 |
|---|---|
| 正典 §2.2 對照表 | 加 `Interrupt → idle`（Codex only，**不得**進 `handledEvents`）；點名它與 `is_interrupt` 是兩件事 |
| 正典 §2.1 檔案契約 | 加 `agent`（Optional，nil = claude）與 D-a／D-c 的理由 |
| 正典 §3.2 安裝機制 | 加「第二個入口：Codex 讀 `~/.codex/hooks.json`（F1、F14），只在不存在時寫、只在內容相符時刪、絕不碰 `config.toml`；bundle 路徑不合法時不寫、改畫解釋」**＋ R-8 的兩側互不干擾不變式** |
| **app-shell spec（`2026-09-10-app-shell-design.md`）§3.4 文案映射（M-7，D-c）** | 加「`Jargon.model` 同時認得 Claude 家族與 Codex 家族的命名；判不出來一律原樣回傳」。**不是正典的 §3.4**（T11 review m3／問題 6）：兩份 spec 撞章節號——正典的 §3.4 是別的主題，而 `Jargon.swift` 第 3 行的麵包屑指的是 app-shell 那一份。回寫要落在被指名的那份文件上，否則下一個人照麵包屑找過去會看不到 |
| 正典 §3.5 pid liveness | 加「Codex 的 hook 父行程在 session 內 pid 穩定（F15，**exec 模式實測**），判活前提成立；互動 TUI 的行程結構與 `comm` 未辨識」 |
| 正典 §3.7 面板內容 | 加「非 Claude 的 session 在列的第一行帶 agent 標籤；聚合燈不分 agent」 |
| 正典 §9 開放風險 | 加「Codex 無 error 來源」「無法偵測信任狀態」兩條 |
| `CLAUDE.md` Invariants | 加「`CodexInstaller` 只准碰 `<codexHome>/hooks.json`；`config.toml` 位元組不得變動」「`Interrupt` 不得進 `handledEvents`」**「對任一側的安裝操作不得改動另一側的任何位元組」** |
| `CLAUDE.md` Tier 1 清單 | 加 `CodexSectionView.swift`、`AppDelegate+Codex.swift`、`Sources/AuraCore/CodexState.swift` |
| `CLAUDE.md` Project 狀態 | 加 codex-support 一行 |
| `README.md` ＋ `.zh-TW` §「What it does to your Mac」 | 加 `~/.codex/hooks.json` |
| `SECURITY.md` §「What this tool can do on your machine」＋「Boundaries that are enforced by tests」 | 加 `~/.codex/hooks.json` 與「`config.toml` 位元組不變」**「兩側互不干擾」**。**注意**：`SECURITY.md` 沒有叫「What it does to your Mac」的段落，那是 `README.md:160` |
| `docs/INSTALL.md` ＋ `.zh-TW` | 新增「Using it with Codex」；troubleshooting 加兩條（信任提示／暫時把 `timeout` 改 5 看 clamping 警告） |
| `Resources/help-*.html` 兩份 | 新增「Codex」段（CX28 強制涵蓋**每一個**新的 Options 列標題，含「重新接上 Codex」） |

## 9. Persona Impact

- **只用 Codex 的人**：Claude 側是 `.notConnected`（大版說明），Codex 的提示在它下面（R-3 單行）。
  persona 要回答「兩個東西疊在同一張畫面上時，第一次看得懂要按哪個嗎」。
- **兩個都用的人（P4）**：列上只有 Codex 有標籤；同一專案同時跑兩邊時兩列 `projectName` 一樣，
  **只靠標籤區分**。R-8 之後還要回答：兩側都接上時，**兩邊的燈都真的會動嗎**（實機 ⑧）。
- **已有自己 `~/.codex/hooks.json` 的進階使用者（P2）**：最在意「會不會蓋掉我的」。
  **R-5／R-10 之後 P2 有三條具體要求**（不另開硬下限）：① 被拒時文案**指名是哪個字元**；
  ② 拒絕必須給**出路**；③ **從 DMG／下載資料夾打開時，我們寧可不給 snippet 也不給一份會過期的**
  （R-10 關掉的那扇側門：P2 是最會真的照著貼的那個 persona，而失效是靜默的）。
- **從 DMG 直接雙擊的新使用者**：R-5 讓他在按下去之前就看到解釋與出路；
  **R-9 讓他即使已經接上過，也不會因為打開一次 DMG 副本就把還在運作的 hook 弄丟**。
- **不懂「信任」提示的 vibe coding 使用者**：F5 讓我們偵測不到，畫面與 help 必須把
  「下次啟動 Codex 會問你一次」講在**按下去之前與之後各一次**。

## 10. Known gaps

| # | 內容 | 性質 |
|---|---|---|
| 1 | `PermissionRequest`／`Interrupt`／`Subagent*` 的 Codex payload 形狀**未量**（F10）——`waiting` 目前是**推論** | 待驗；互動探針 |
| 2 | **Codex 沒有 `error` 來源**（F2、F4）→ 永遠不會亮紅燈 | 設計代價 |
| 3 | **無法偵測 Codex 是否已信任**（F5）→ UI 只能講 | 平台限制 |
| 4 | 不寫 `async`（F14 未測）→ 每個事件同步等 ~7 ms | 保守選擇 |
| 5 | ~~hooks.json 頂層形狀未知~~ **已由 F14 關閉** | **已關閉** |
| 6 | 內容比對與 `unlink` 之間的 TOCTOU 窄窗 | 接受 |
| 7 | `codex exec` 會寫 `config.toml`（F12）→ 端到端只能靠人 | 驗收缺口 |
| 8 | F15 的範圍限定：(a) 五個 session 全在 `exec`，互動 TUI 行程結構未量；(b) `SessionEnd` 之後 pid 是否結束**未觀測**；(c) `comm` 未辨識 | 範圍限定 ＋ 待驗；實機 ③ |
| 9 | **`timeout: 3` 是否真的不觸發 clamping 未觀測**；代價是失去最便宜的「Codex 讀到了」訊號 | 推論；實機 ②③ |
| 10 | `command` 是裸路徑；**含空白／引號的路徑行為未測**（R-5 讓產品不賭它） | 待驗；互動探針 |
| 11 | 兩個 agent 共用 `~/.agentaura/sessions/`；同專案同時跑時兩列只靠標籤區分 | persona |
| 12 | **App 被搬走或改名**：R-6 偵測得到，但偵測發生在**下一次 `reprobeCodex()`**（啟動或開面板）；在那之前 Codex 那側已經不動而我們還沒機會講 | 設計代價 |
| 13 | **R-8 的不變式 2（兩側同時真的在跑）自動化只驗到「同一顆二進位、兩邊 `agent` 各自正確」**（CX38）；「兩個上游**同時**真的觸發它」只有實機 ⑧ | 驗收缺口 |
| 14 | **序列長度上限**：CX37a **全部 ≤ 4**（780 條全跑）、CX37b **生產路徑 ≤ 2**（30 條）、CX42 **憑證 ≤ 2**（20 條）。更長的交錯序列未涵蓋——那是成本與覆蓋的取捨，不是「N 步之後就安全了」的論證 | 覆蓋缺口，明寫 |
| 15 | **`Jargon.model` 的 Codex 分支只有 `gpt-5.5` 是實測**；其餘八列（含 `gpt-5` 的**刻意變更**）是預期值，任何一個實際出現時要回頭對照（既有 `everyFixtureModelIsMapped` 會在新 fixture 進來時把沒處理到的值變紅） | 待驗；有守衛 |
| 16 | **兩個上游的 session id 空間不交集是明寫的假設，不是我們控制的東西**（Claude 的 UUID vs Codex 的 UUIDv7）。`SnapshotIO` 以 `<session_id>.json` 分檔，所以「互不覆蓋」在結構上必然成立——CX38 的那個斷言在任何實作下都會通過，**它是結構性結論不是被測性質**（r4 m1） | 假設，明寫 |

## 11. 風險

| 風險 | 緩解 |
|---|---|
| **`Interrupt` 進 `handledEvents` → Claude 側整份 hooks 靜默失效** | CX2 ＋ CX5 兩個獨立觀測點；`plugin/hooks/hooks.json` 的 git diff 必須為空 |
| **`Interrupt → idle` 沒有 fixture 證人** | CX4（定義域從 `codexOnlyEvents` 推導）；CX13 的 mutation 換成 `Stop` |
| 「只在不存在時寫」寫成兩步 → symlink 指向 `config.toml` 時覆蓋使用者設定 | `O_EXCL` ＋ CX15 那一格 fixture |
| 產生器偏離 F14 → Codex 根本不載入，而自動化抓不到 | CX6 的 12 格逐字比對；唯一刻意偏離自己配一格 mutation |
| **寫進一個下次開機就消失的絕對路徑，而 UI 永遠說「已接上」** | R-5 三層 guard ＋ CX32／CX33 |
| **「重新接上」先刪掉使用者還在運作的檔** | R-9 的前置 guard ＋ 面板不給按鈕 ＋ CX39；CX35 加「無 rejection 時」前提 |
| **把一份會過期的 snippet 交給最會照著貼的 persona** | R-10 ＋ CX40 的乘積表（`CodexState` 與 `Rejection` 是兩個獨立維度，只驗一維會漏掉交會格） |
| **App 搬家後 `.connected` 永遠成立** | R-6 ＋ CX34／CX35 |
| **憑證 round-trip 壞掉 → 永遠刪不掉自己的檔 → 完整移除留殘留** | CX31 ＋ CX24③ |
| **`reprobeCodex()` 沒被呼叫 → 裝了 Codex 卻要重開 app 才看得到** | §4.6 四個時機 ＋ CX24⑤ |
| **兩側互相干擾**（新需求 R-8） | CX37a／CX37b（檔案序列）＋ **CX42（憑證序列）** ＋ CX38（端到端）＋ 實機 ⑧；結構理由寫進 §4.8 |
| **既有 `everyFixtureModelIsMapped` 目前是紅的** | D-u／§4.9；CX41 的釘死表 ＋ 既有 gate 當跨層錨點。DoD 起點寫明「這一條紅是本 change 必須修好的既有 gate，不是弱化對象」 |
| **94 個呼叫點的機械改動**中夾帶弱化 | §6.4(2)(3)(4)(5)；`#expect` 淨數量不得下降 |
| `CodexState` 六態 ＋ 兩種 Rejection，四條聯集 gate 的定義域 | 全部從 `CodexStateKind.allCases` ＋ `RejectionKind.allCases` 推導（D-r 兩層都不得有 `default`） |
| **CX37 的 780 條序列會跑 586 次真 spawn**（r4 M2 算出來的數字） | 拆成 CX37a（零 spawn、780 條全跑）＋ CX37b（生產路徑、30 條、11 次 spawn）；覆蓋不減、spawn 降約 53 倍，**不必縮減序列** |
| Codex 端到端無法自動驗收（F12） | 實機清單 ①–⑧ |

**待確認（不自行決定，列給主 session）**：見最終報告的「裁決有問題之處」四點。
