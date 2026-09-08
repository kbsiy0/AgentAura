# AgentAura — 設計文件

**日期**：2026-09-08
**狀態**：已核准，待產實作計畫
**討論記錄**：`docs/01-approach-comparison.html`（方案比較）、`docs/02-design.html`（設計呈現）

---

## 0. 目的與範圍

一個 macOS menu bar app，讓使用者不用切視窗就能看出所有 Claude Code session 的運行狀態。
靈感來自硬體產品 SidePulse（SD 卡槽 8 顆 RGB LED），本專案做純軟體版本。

### 已鎖定的需求決策

| 編號 | 決策 | 理由 |
|---|---|---|
| R1 | **多 session 聚合儀表板** | 使用者常多 agent 併行、整夜跑 pipeline；單 session 模式只會看到其中一個 |
| R2 | **按開源標準寫，先自用跑起來** | 不寫死路徑、安裝可逆；不進 App Store，故不受 App Sandbox 限制，可自由讀 `~/.claude/` |
| R3 | **read-only（只看）** | 不做遠端核准、不跳回 terminal。事件單向流入，架構乾淨、無雙向通道 |
| D1 | **聚合優先序 `error > waiting > working > done > idle`** | 使用者裁決。紅色絕對優先，最不易錯過 |
| D2 | **打開面板即 acknowledge** | scope 是只看，面板是唯一互動，用它當確認手勢摩擦最低 |
| D3 | **方案 1（plugin + 單檔狀態信箱）** | 見 §3.1 |
| R4 | **注意力預算：只有需要你行動的狀態才會動** | 前一個同類專案 前一個專案 失敗於「太吵」。常態一直動 → 「動起來」失去訊號價值（§3.6） |
| R5 | **形態用證據決定，不預先鎖定** | 前一個專案 失敗於「形態不對」。M4 同時做兩個原型打分再選（§8） |
| R6 | **一步安裝、一步移除、自我健檢** | 前一個專案 失敗於「安裝維護太麻煩」，且移除後在 settings.json 留下 7 個指向不存在執行檔的死 hook（§3.8） |

R4-R6 三條直接來自使用者對 前一個專案 的失敗歸因（形態不對／狀態語意不準太吵／安裝維護麻煩）。
「狀態語意不準」已由 §2.2.1 的 `Notification` 型別分流與 §2.5 的 main/sub 分槽處理。

### 明確不做（YAGNI）

- 遠端核准權限請求（需雙向同步通道，會阻塞 agent，安全面複雜）→ 可能的 v2
- 手機推播 / 跨裝置 → 可能的 v2
- 支援 Codex / Cursor / Gemini CLI → 介面已留縫（§3.4），不進第一版
- 可自訂的 LED 動畫 DSL（SidePulse 有）→ 內建固定幾套狀態動畫即足夠
- 歷史統計 / 花費追蹤 → 非本專案目的

---

## 1. 架構總覽

```
claude (session A) ─┐
claude (session B) ─┼─→ aura-hook ─→ ~/.agentaura/sessions/<session_id>.json
claude (session C) ─┘   (async hook)      (每 session 一檔，flock 下 merge-write)
                                                     │
                                                     │ FSEvents
                                                     ▼
                                          AgentAura.app
                                          ├─ SessionReducer   → SessionState
                                          ├─ SessionRegistry  → 現存 + unacked 尾巴
                                          ├─ AggregatePolicy  → IconState
                                          ├─ NSStatusItem     → LED 動畫
                                          └─ SwiftUI 面板     → 詳細列表
```

### 核心問題

Hook 提供的是**狀態轉移**，UI 需要的是**當前狀態**。這個落差製造三個必須處理的失效模式：

1. **殘留狀態** — terminal 被強制關閉，`SessionEnd` 永不觸發 → session 永遠卡在 working
2. **app 未運行時的事件** — hook 照樣觸發但無人接收 → app 啟動後對現況一無所知
3. **不可拖慢 agent** — 每個 tool call 都觸發 hook；同步 hook 會直接卡住 Claude Code

### 關鍵設計洞見

**per-session 狀態幾乎是最後一個事件的純函數**：`activity = f(last_event)`。

前提是 `waiting` / `done` / `error` 三者皆為**靜止態** —— 在使用者採取行動前不會有新事件覆寫它們。
（原始設計把 `PostToolUseFailure` 映射成 `error` 破壞了這個性質，已修正為 `working`，見 §2.2。）

此性質成立後：不需要 event log、不需要 replay、不需要處理亂序。每個 session 一個檔案直接覆寫，
app 啟動掃一次目錄即得正確現況。整個設計因此塌縮成很小的東西。

### 兩層狀態模型

必須明確區分（原始呈現未講清，導致誤解）：

| 層 | 輸入 | 規則 | 輸出 |
|---|---|---|---|
| 第 1 層 · per-session | 該 session 的最後事件 | `activity = f(last_event)`；各 session 一檔互不影響 | `SessionState` |
| 第 2 層 · 聚合 | 全部 `SessionState` | **優先級取最大**，純函數，與寫入順序無關 | `IconState` |

例：3 個 session，2 個 working、1 個 error → icon 為 error（紅色），與哪個先寫入無關。

---

## 2. 資料模型

### 2.1 檔案契約

`~/.agentaura/sessions/<session_id>.json`，由 `aura-hook` 寫入：

```json
{
  "schema": 1,
  "session_id": "abc123",
  "hook_event_name": "PermissionRequest",
  "written_at": "2026-09-08T17:42:03.117Z",
  "pid": 48213,
  "pid_started_at": 1757352011,
  "cwd": "/Users/you/Code/Vibe/AgentAura",
  "permission_mode": "default",
  "effort": "xhigh",
  "source": "startup",
  "reason": null,

  "main_activity": "waiting",
  "main_tool": "Bash",
  "sub_activity": "working",
  "sub_tool": "Grep",
  "sub_agent_type": "Explore",

  "notification_type": null,
  "last_message": null,
  "tool_duration_ms": 12403,

  "turn_started_at": "2026-09-08T17:41:12.004Z",
  "subagents": { "Explore": 2, "implementer": 1 },
  "tool_failures": 3
}
```

由當次事件直接覆寫的欄位，與由 `aura-hook` 在 `flock` 下 read-merge-write 帶過來的**累積欄位**
（`main_*` / `sub_*` / `turn_started_at` / `subagents` / `tool_failures`）分開。

### 2.1.1 依實測 payload 的校正（2026-09-06 錄製，33 個真實事件）

前一版此表建立在文件推測上。實測後修正如下 —— 見 §10。

| 欄位 | 文件／前一版假設 | **實測** |
|---|---|---|
| `model` | `SessionStart` 帶 model | **任何 event 都沒有**。面板無法顯示模型 |
| `effort` | 字串 `"high"` | 物件 `{"level":"xhigh"}` → `aura-hook` 攤平存字串 |
| `SessionEnd` 結束原因 | `end_reason` | 實際欄位名是 **`reason`** |
| `SessionStart` | 無額外欄位 | 有 **`source`**（區分 fresh start / resume） |
| `PostToolUse` | 只有 `tool_output` | 有 **`duration_ms`** 與 `tool_response` → 面板可顯示 tool 耗時 |
| `Stop` | `last_assistant_message` | 確認存在，另有 `background_tasks` / `session_crons` / `stop_hook_active` |
| 全部 tool event | — | 皆帶 `scratchpad_dir`、`prompt_id`、`transcript_path` |

`transcript_path` 出現在**每一個** payload 上。模型名稱等 hook 拿不到的資訊，未來若要補，
這是唯一的 enrichment 縫（代價是依賴內部 jsonl 格式）—— 不進第一版。

### 2.2 event → activity 對照表

```swift
enum Activity: Int, Comparable {
    case idle = 0, done = 1, working = 2, waiting = 3, error = 4   // rawValue 即 D1 的優先序
}
```

| 最後收到的 hook event | activity | 備註 |
|---|---|---|
| `SessionStart` | `idle` | 已開但還沒下第一個 prompt |
| `UserPromptSubmit` | `working` | 一輪開始，設定 `turn_started_at` |
| `PreToolUse` / `PostToolUse` | `working` | 面板顯示 `tool_name` |
| `PostToolUseFailure` | `working` | **修正**：tool 中途失敗是 agent 工作的正常組成，不變紅；只累加 `tool_failures` |
| `PostToolBatch` | `working` | 並行 tool 批次結束 |
| `SubagentStart` / `SubagentStop` | `working` | 累加 `subagents[agent_type]` |
| `PreCompact` / `PostCompact` | `working` | 面板可標「壓縮中」 |
| `PermissionRequest` | `waiting` | 最重要的訊號：agent 被擋住 |
| `PermissionDenied` | `working` | auto mode 自行拒絕，不需使用者 |
| `Elicitation` | `waiting` | MCP server 要求輸入 |
| `ElicitationResult` | `working` | 已回覆 |
| `Notification` | 見 §2.2.1 | 12 種型別需分流。**未知型別不改變 activity** |
| `Stop` | `done` | 靜止態，標 unacked，存 `last_assistant_message` 摘要 |
| `StopFailure` | `error` | 靜止態，標 unacked，存 `error_type` |
| `SessionEnd` | — | 若 unacked 則移入尾巴清單；否則移除 |
| pid 已死（app 偵測） | — | 同上。crash / 強制關窗走這條 |
| 未知 `hook_event_name` | 不變 | 只更新 `written_at`，activity 保持原值 |

### 2.2.1 `Notification` 的 12 種型別

`Notification` 不是單一訊號。前一版寫「未知型別一律 fallback 成 `waiting`，寧可誤報」——**這是錯的**：
未知空間裡佔多數的是雜訊（auth、quota），誤報會讓 icon 無故亮橘。

安全的理由：**`PermissionRequest` 是獨立的 hook event**，已經直接覆蓋「有人在等你」這個最重要的情況，
不需要靠 `Notification` 兜底。故未知型別一律**不改變 activity**。

| `notification_type` | activity |
|---|---|
| `permission_prompt` | `waiting` |
| `idle_prompt` | `waiting` |
| `agent_needs_input` | `waiting` |
| `elicitation_dialog` / `elicitation_url_dialog` | `waiting` |
| `agent_completed` | `done` —— **不是 waiting** |
| `auth_success` | 不改變 |
| `elicitation_complete` / `elicitation_response` | 不改變 |
| `quota_auto_resume_fired` / `_stale` / `_disabled` | 不改變 |
| 未知型別 | 不改變 |

安裝時 `Notification` hook 加 matcher 只收前 6 種，作為縱深防禦；
但**payload 內的型別檢查才是正確性保證**（matcher 支援度可能隨版本變動）。

### 2.3 記憶體模型

```swift
struct SessionState {
    let id: String
    let projectPath: String
    let permissionMode: String?
    let effort: String?               // 由 {"level":…} 攤平
    let activity: Activity            // max(mainActivity, subActivity) —— 見 §2.5
    let mainActivity: Activity
    let subActivity: Activity?
    let currentTool: String?
    let subagentTool: String?         // 形如 "Explore → Grep"
    let toolDurationMs: Int?
    let turnStartedAt: Date?
    let subagents: [String: Int]
    let toolFailures: Int
    let lastMessage: String?
    let errorType: String?
    let acknowledged: Bool
    let liveness: Liveness            // .alive(pid_t) | .ended
    let updatedAt: Date
}

struct IconState {
    let activity: Activity            // 聚合結果（D1 優先序取最大）
    let counts: [Activity: Int]       // 各 activity 的 session 數，面板標題直接由此組字
    let liveCount: Int                // liveness == .alive 的 session 數
}

// 「需要你」的定義（面板標題與 badge 用）：counts[.error] + counts[.waiting]。
// done 不計入 —— 它是「你可以去看了」，不是「你被擋著」。
```

### 2.4 unacknowledged 尾巴

session 進入靜止態（`waiting` / `done` / `error`）時 `acknowledged = false`。
即使 `SessionEnd` 抵達或 pid 死亡，該 session 仍留在 `SessionRegistry` 並**參與 icon 聚合**，
直到使用者打開面板（D2）。

理由：整夜跑 pipeline、terminal 自行收掉的情境下，若不保留，使用者早上回來看到暗燈，
產品最大價值被抵銷。

確認後：已結束且已確認的 session 移出 registry，其狀態檔刪除。

### 2.5 主 agent 與 subagent 必須分槽（critical）

**實測發現的 bug。** Subagent 的 tool 事件**共用父 session 的 `session_id`**，只靠
`agent_id` / `agent_type` 區分（主 agent 為 `null`）。兩者高頻交錯 —— 實測一個 session_id
內切換 5 次，最密的相鄰事件間隔 20ms。

在單純 last-write-wins 下的後果：

```
主 agent   PermissionRequest        → waiting      ← 你被需要了
subagent   PostToolUse (20ms 後)    → working      ← 蓋掉了
```

**「有人在等你」這個產品唯一最重要的訊號被靜默抹除。** 實測時序中已可見同型態的覆蓋：
主 agent 一個 Bash 跑了 19.5s，期間 subagent 插入 12 個事件。

修法 —— 檔案裡分兩槽，session 的 activity 取兩者在 D1 優先序下的**最大值**：

```swift
// aura-hook 寫入時
if payload.agent_id == nil { file.main_activity = activity(of: payload) }
else                       { file.sub_activity  = activity(of: payload) }

// SessionReducer 讀取時
let activity = max(file.main_activity, file.sub_activity ?? .idle)   // Activity: Comparable
```

因為 `waiting`(3) > `working`(2)，`max` 天生保住 waiting。此修法不新增機制，
純粹複用 D1 已定義的優先序。

清空規則：主 agent 的 `Stop` / `StopFailure` 抵達時，`sub_activity` 一併歸零
（該輪的 subagent 都已結束）。

面板顯示：主 agent 的 tool 為主行，subagent 的以 `Explore → Grep` 形式附註。

---

## 3. 核心技術

### 3.1 為何選方案 1

三個候選方案的逐項比較見 `docs/01-approach-comparison.html` §4。摘要：

| 判準 | 方案 1 plugin+檔案 | 方案 2 local HTTP | 方案 3 zero-config 觀測 |
|---|---|---|---|
| 不拖慢 agent | 通過（async） | 通過（零 spawn） | 通過（不介入） |
| app 未運行時 | **狀態落地在檔案** | 事件永久遺失 | 歷史都在 |
| 「在等你」精準度 | 高 | 高 | 低（靠靜止時間猜） |
| 契約依賴 | 公開 hook API | 公開 hook API | 內部 jsonl，隨時變 |
| 實作複雜度 | **低** | 中（port 衝突、重連） | 高（parser + heuristic） |

方案 2 唯一勝出的是延遲，但 loopback 往返與 2ms process spawn 對「人眼看 menu bar」毫無差別——
拿永久遺失事件換使用者感知不到的延遲不划算。
方案 3 的價值在零安裝與跨 agent 通用性，留為 `EventSource` 的第二個實作，不進第一版。

### 3.2 安裝機制：Claude Code plugin

Plugin 自帶 `hooks/hooks.json`，以 `/plugin install` / `/plugin uninstall` 管理。

- 完全不修改 `~/.claude/settings.json` → 天生可逆、天生不破壞使用者現有 hooks
- 所有 hook 皆 `"async": true`（fire-and-forget，agent 不等待）
- command 路徑用 `${CLAUDE_PLUGIN_ROOT}` 或指向 app bundle 內的 `aura-hook`

### 3.3 aura-hook：為何 read-merge-write

面板需顯示「本輪已跑多久」、「subagent 數量」、「tool 失敗次數」——三者皆為累積量，
非最後事件的函數。兩個選項：

- app 在記憶體累積 → app 重啟即歸零，整夜 pipeline 情境下面板變空白，不可接受
- helper 在檔案累積 → 永久正確

選後者。競態安全靠 `flock(LOCK_EX)`：

- 檔案為 per-session，**跨 session 零競爭**
- 同一 session 內事件近乎循序，但 `async: true` 理論上可能重疊 → 鎖是必要的，不是可選的
- app 端讀取取 `LOCK_SH`；解析失敗時**保留上一次已知狀態並重試**，絕不當成 session 不存在

**`aura-hook` 任何錯誤都靜默 `exit 0`**（磁碟滿、目錄不可寫、JSON 畸形）。
依 user CLAUDE.md Lessons Learned #8：觀測性動作絕不可干擾主路徑。

### 3.4 介面縫

```swift
protocol EventSource {
    func bootstrap() throws -> [SessionSnapshot]      // app 啟動時掃目錄還原現況
    var snapshots: AsyncStream<SessionSnapshot> { get }
}

protocol AggregatePolicy { func aggregate(_ s: [SessionState]) -> IconState }
protocol IconRenderer    { func render(_ s: IconState) }
protocol LivenessProber  { func isAlive(pid: pid_t, startedAt: time_t) -> Bool }
```

`EventSource` 是方案 3 未來接入點。`IconRenderer` 讓核心邏輯測試不需要 AppKit。

`AuraCore` 不 import AppKit —— **此約束由測試強制，不靠自律**。

### 3.5 pid liveness 與 pid 回收

`kill(pid, 0)` 只證明「某個 process 存在」，不證明是原本那個 —— pid 會被系統回收。
故 `aura-hook` 記錄 `pid_started_at`（`proc_pidinfo` 的 `pbi_start_tvsec`），
app 比對 pid **與**啟動時戳，兩者皆符才算活著。

輪詢間隔 5s。

### 3.6 Menu bar 渲染

- `NSStatusItem` + 自繪 `NSView`（`LEDStripView`，8 顆 LED）。
  不用 SwiftUI `MenuBarExtra` —— 自繪動畫的控制權需要 AppKit 層級。
- **狀態動畫語言 —— 注意力預算（R4）**

  核心規則：**只有 `waiting` 與 `error` 會動。** 其餘全部靜態。

  | activity | 是否常態 | 呈現 | 動畫 |
  |---|---|---|---|
  | `idle` | 常態 | 極暗單點，近乎不可見 | 無 |
  | `working` | **常態** | 低對比暗藍，極慢呼吸（4s 週期、透明度 0.35→0.6） | 極微 · ≤10 fps |
  | `done` | 需注意但不急 | 恆亮綠 | **無 · 0 fps** |
  | `waiting` | **需要行動** | 橘色明顯呼吸（1.1s 週期） | 有 |
  | `error` | **需要行動** | 紅色 double blink | 有 |

  為什麼這樣分配：使用者的常態是多 agent 併行、整夜跑 pipeline。若 `working` 跑
  comet，menu bar 幾乎永遠在動 —— 「動起來」就失去訊號價值，必須辨色才知道發生什麼事。
  這正是 前一個專案「太吵」的同一個病。

  改成「動 = 需要你」之後得到三件事：
  1. 常態安靜，不干擾
  2. **餘光就能判斷**，不需辨色 —— 單一、無歧義的規則
  3. 大多數時間零重繪，電池成本趨近於零

  前一版把 `working` 設成 comet 跑動是設計錯誤，已在此修正。
- `AnimationDriver` 在以下情況停止重繪：螢幕睡眠（`NSWorkspace` 通知）、
  `NSStatusItem.isVisible == false`、系統開啟「減少動態效果」（改為靜態色塊）。
- 跟隨深淺色外觀。

### 3.7 面板內容

排序：`error → waiting → working → done`（與 D1 優先序一致），同組內最近活動優先。
已結束但未確認者置於各組下半部。

每列顯示：專案名（`cwd` 的 basename）、effort、permission_mode、
當前 tool 或等待原因（含 tool 耗時）、subagent 的 tool（附註行）、本輪已跑多久、
subagent 數、tool 失敗數、完成訊息摘要（done）、相對時間。

**不顯示模型** —— 實測確認 hook payload 完全不帶 `model`（§2.1.1）。

打開面板即 acknowledge（D2）。語意明確定義為：**面板開啟的瞬間，registry 中所有
`acknowledged == false` 的 session 一律標為已確認**（不論是否捲動到、是否可見）。
已結束且已確認者隨即移出 registry 並刪除狀態檔。

### 3.8 安裝可逆性與自我健檢（R6）

前一個專案 的實際失效方式：直接改 `settings.json`，app 被移除後 7 個 hook 全部孤兒化，
指向不存在的執行檔，每個 tool call 白 fork 一次並拿到 exit 127 —— 而且**完全靜默**，
使用者無從發現。2026-09-08 才被找出並清除。

AgentAura 的對應要求：

1. **安裝／移除各一步** —— `/plugin install` / `/plugin uninstall`，不碰 `settings.json`
2. **不需重啟** —— 實測確認 hook 設定變更立即對執行中的 session 生效（§10），
   安裝完成的提示不得叫使用者重啟
3. **自我健檢** —— app 啟動時掃描 `~/.claude/settings.json` 與已啟用 plugin 的 hook 設定，
   偵測 command 指向不存在或不可執行的檔案（**包含 AgentAura 自己的**），
   在面板顯示可行動的警告。這條直接防止重演 前一個專案 的殘留問題
4. **移除驗證** —— 移除流程的驗收條件是「`settings.json` 與 plugin 設定中不留任何
   AgentAura 引用，且 `~/.agentaura/` 可安全手動刪除」

---

## 4. 錯誤處理

| 失效模式 | 若不處理的後果 | 處理 |
|---|---|---|
| terminal 強制關閉，`SessionEnd` 未觸發 | 永遠卡 working | `LivenessProber` 每 5s 驗證所有 `.alive` |
| pid 被回收給其他 process | 死 session 誤判為活著 | 比對 `pid_started_at`，不只比 pid（§3.5） |
| 讀到寫入一半的 JSON | session 閃現／消失 | `LOCK_SH` 讀取；解析失敗保留上次已知狀態並重試 |
| subagent 事件蓋掉主 agent 的 `waiting` | **最重要的訊號被靜默抹除** | main / sub 分槽，取 D1 優先序 max（§2.5） |
| 未知 `notification_type` | 無故亮橘燈（auth / quota 雜訊） | 不改變 activity；`PermissionRequest` 已覆蓋真正的等待情況（§2.2.1） |
| Claude Code 新增 hook event | 解析爆掉 | 未知 event 不改變 activity，只更新時戳；`schema` 欄位擋不相容 |
| app 未運行時累積事件 | 啟動後畫面空白 | `bootstrap()` 掃目錄；靜止態天生在檔案裡 |
| 殘留檔案（機器重開） | 幽靈 session | 啟動時 pid 一律驗證；已死且已確認者刪檔 |
| 磁碟滿 / 目錄不可寫 | hook 錯誤噴到 agent 畫面 | `aura-hook` 任何錯誤靜默 `exit 0` |
| session 數量爆掉（50+） | menu bar 卡頓 | 聚合為 O(n) 純函數；重繪節流 ≥ 100ms；面板列表虛擬化 |
| 螢幕睡眠 / menu bar 被遮蔽 | 白吃電池 | `AnimationDriver` 停止重繪（§3.6） |
| `session_id` 含 path traversal 字元 | 寫到目錄外 | `aura-hook` 白名單過濾檔名字元，不合法即 `exit 0` |
| 時鐘倒退（`turn_started_at` 在未來） | 顯示負數時間 | 相對時間格式化 clamp 到 0 |

---

## 5. 測試策略

依 user CLAUDE.md Lessons Learned #1：**T01 不含任何生產碼**，只建對抗式測試底座。
四道 SDD 關卡若共用同一批「樂於配合」的 fixture，縱深防禦是假象。

### 5.1 對抗式 double

刻意回傳 happy-path fixture 不會回的東西：

1. 截斷／半截 JSON（模擬讀到寫入中）
2. pid 已死；pid 被回收成另一個啟動時戳更晚的 process
3. 事件亂序落地（`async` 導致 `Stop` 比 `PostToolUse` 早寫入）
4. 未知 `hook_event_name`、未知 `notification_type`、缺必要欄位、多出未知欄位
5. 50 個 session 併發寫同一目錄
6. emoji / unicode / 超長專案路徑；`session_id` 含 `../` 等 path traversal
7. 時鐘倒退（`turn_started_at` 落在未來）
8. 磁碟滿 / 目錄唯讀 → `aura-hook` 必須靜默成功
9. 同一 session 兩個 `aura-hook` 行程重疊寫入（驗證 `flock`）
10. `subagents` 累積跨 app 重啟後仍正確
11. **主 agent `PermissionRequest` 後 20ms 內插入 subagent `PostToolUse`** → activity 必須維持 `waiting`（§2.5）
12. 主 agent 長 tool（19.5s）期間 subagent 連發 12 個事件 → 主 agent 的 tool 名不可被覆蓋
13. `Notification` 的 12 種型別逐一驗證，特別是 `agent_completed → done`、`auth_success → 不改變`
14. `effort` 送 `{"level":"xhigh"}` 物件形狀；也送字串與 `null`（防上游改格式）
15. `SessionEnd` 用 `reason` 欄位；也送舊的 `end_reason`（兩者都要能容忍）

### 5.2 composition-root smoke

**測過的能力 ≠ 接線的能力**（Lessons Learned #5）。實跑 `AppDelegate.buildGraph()` 並斷言：

- FSEvents watcher **真的**訂閱到 `~/.agentaura/sessions`
- `StatusItemController` **真的**收到 `IconState` 更新（spy 斷言呼叫確實發生，不是被 catch-all 吞掉）
- `LivenessProber` 非 nil，且在 production config 下真的接通
- **plugin 的 `hooks/hooks.json` 裡的 command 路徑，指向真實存在且可執行的 `aura-hook`**
  —— 這是 tested≠wired 最經典的位置：路徑一錯，整個產品靜默失效而所有單元測試照樣全綠
- 端到端 wired-gate：用**真的** `aura-hook` 二進位 + 真的檔案 + 真的 FSEvents，
  不 mock 任何一層，斷言 `IconState` 改變

### 5.3 Mutation 驗證

關鍵 gate 一律做（暫時撤除實作 → 對應測試必 RED → 還原回綠）：

| 撤除 | 必須 RED 的測試 |
|---|---|
| `AggregatePolicy` 的優先序 | 「2 working + 1 error 應為 error」 |
| unacked 尾巴保留 | 「session 結束後 unacked error 仍計入 icon」 |
| `PostToolUseFailure → working` 改回 `error` | 「tool 失敗不改變 activity」 |
| `aura-hook` 路徑改成不存在 | composition-root smoke |
| `flock` | 「重疊寫入不遺失累積欄位」 |
| `pid_started_at` 比對 | 「pid 回收不誤判為活著」 |
| main/sub 分槽（改回單槽 last-write-wins） | 「subagent 事件不得蓋掉主 agent 的 waiting」 |
| `Notification` 型別分流（改回一律 waiting） | 「`auth_success` 不改變 activity」 |

### 5.4 UI 驗收

M4/M5 動視覺路徑 → **Tier 1**，須派 persona-tester（3+ persona 並行打分 → 加權信心指數 → go/no-go）。
另附 menu bar 各狀態截圖作為完成證明。

---

## 6. 檔案佈局與 migration

```
AgentAura/
├─ Package.swift                     SwiftPM · executable + test targets
├─ Sources/AuraCore/                 純邏輯，零 AppKit 依賴
│   ├─ SessionSnapshot.swift         檔案 schema · 容錯 Decodable
│   ├─ Activity.swift                狀態列舉 + event→activity 對照表
│   ├─ SessionReducer.swift          Snapshot → SessionState
│   ├─ SessionRegistry.swift         現存 session + unacked 尾巴
│   ├─ AggregatePolicy.swift         [SessionState] → IconState（D1 優先序在此）
│   ├─ PanelViewModel.swift          排序 · 相對時間格式化
│   ├─ Liveness.swift                pid + 啟動時戳驗證
│   └─ EventSource.swift             protocol
├─ Sources/AuraHookFile/
│   ├─ HookFileSource.swift          FSEvents watch + bootstrap
│   └─ SnapshotIO.swift              flock 讀寫 · 原子 rename
├─ Sources/aura-hook/                helper CLI，被 hook 呼叫
│   ├─ main.swift                    stdin → merge → write · 任何錯誤 exit 0
│   └─ MergeRules.swift              累積欄位合併
├─ Sources/AgentAuraApp/             AppKit / SwiftUI
│   ├─ AppDelegate.swift             composition root（唯一組裝點）
│   ├─ StatusItemController.swift    NSStatusItem
│   ├─ LEDStripView.swift            8 顆 LED 繪製
│   ├─ AnimationDriver.swift         省電節流
│   └─ Panel/PanelView.swift         SwiftUI 面板
├─ plugin/                           Claude Code plugin
│   ├─ .claude-plugin/plugin.json
│   └─ hooks/hooks.json              全部 async: true
├─ docs/                             設計討論 HTML + spec
└─ Tests/AuraCoreTests/              對抗式 double + composition-root smoke
```

**單檔 200 行上限**（user CLAUDE.md 通用架構原則）。

### Migration

新專案，無既有資料需遷移。需定義的演進策略：

- **狀態檔 schema 版本**：`schema: 1`。app 讀到更高版本時忽略未知欄位而非拒絕；
  讀到不相容的舊版本時刪檔重建（狀態是瞬時的，可安全丟棄）
- **plugin 安裝／移除**：`/plugin install` / `/plugin uninstall`。
  移除後 `~/.agentaura/` 需可手動刪除，app 對空目錄正常運作
- **從零安裝流程**：M6 驗收 —— 乾淨機器上照 README 從零裝起來能跑

---

## 7. DoD（可量測）

| 項目 | 門檻 | 量測方式 |
|---|---|---|
| hook 延遲 | p95 < 5ms | `hyperfine` 對 `aura-hook` |
| 端到端反應（hook → 畫面） | p95 < 250ms | 端到端 wired-gate 計時 |
| `AuraCore` 覆蓋率 | ≥ 90% | `swift test --enable-code-coverage` |
| 單檔行數 | ≤ 200 | CI 檢查腳本 |
| `idle`／`done` CPU | < 0.1% | `top` 取樣 60s（此二狀態應為完全靜態、零重繪） |
| `working` CPU | < 0.3% | `top` 取樣 60s（4s 低對比呼吸，低幀率足夠） |
| `waiting`／`error` CPU | < 1.5% | `top` 取樣 60s |
| 50 session 記憶體 | < 60 MB | Instruments |
| agent 減速 | 0 ms | `async: true`，以 hook 前後 timestamp 驗證 |
| `idle`／`done` 幀率 | **0 fps** | 注意力預算（R4）：完全靜態，`AnimationDriver` 不得排程任何重繪 |
| `working` 幀率 | ≤ 10 fps | 4s 週期、透明度僅 0.35→0.6，低幀率視覺上已足夠平滑 |
| `waiting`／`error` 幀率 | ≥ 30 fps | 動畫必須流暢，否則失去警示效果 |
| 死 hook 偵測 | 100% | 自我健檢（R6）；植入一個指向不存在檔案的 hook，必須被偵測 |

---

## 8. 里程碑

| 階段 | 內容 | 出場條件 |
|---|---|---|
| **M0** 補錄剩餘 payload | 大部分已由復原的 前一個專案 probe 產出取代（§10）。只需補錄 `Notification` / `PermissionRequest` / `StopFailure` / `SubagentStart` / `SubagentStop` 這 5 個未捕獲的 event，並驗證 `getppid()` 與 plugin `async` | 5 個 event 有真實樣本 + 3 個機制驗證完成 |
| **M1** 測試底座 | §5.1 對抗式 double + §5.2 composition-root smoke。零生產碼 | 測試全部 RED 且理由正確 |
| **M2** AuraCore | Reducer / Registry / AggregatePolicy / Liveness · TDD | M1 全綠 + §5.3 mutation 驗證通過 |
| **M3** hook 管線 | `aura-hook` + plugin + `HookFileSource` | 端到端 wired-gate 綠（真二進位、真檔案、真 FSEvents） |
| **M4** Menu bar 形態決策 | **同時**做兩個原型：(A) 8 顆迷你 LED 燈條、(B) 單一符號 + 顏色 + 動畫。兩者共用同一份 `IconState`，只換 `IconRenderer` 實作 | persona-tester 對 A/B 打分（含**餘光辨識**與**遠距辨識**項目）→ 依證據選定一個。CPU／重繪率 DoD 達標 + 兩形態截圖 |
| **M5** 面板 + 自我健檢 | SwiftUI 詳細面板 + acknowledge + §3.8 死 hook 健檢 | Tier 1 → persona-tester 過門檻；死 hook 偵測 DoD 達標 |
| **M6** 開源 | 安裝器 · README · 移除流程 · ad-hoc 簽章說明 | 乾淨機器上照 README 從零裝起來能跑 |

### 為何 M0 仍排在最前（但已大幅縮減）

原本列的 6 項未驗證事項，已有 4 項由復原的實測資料回答（§10）。**剩下 3 項機制問題 +
5 個未捕獲的 event**，仍必須實測才能建 fixture —— 否則整套測試建在猜測的 schema 上，
正是 user CLAUDE.md 說的「gates share one eye」的起點。

**仍待實測：**

1. `Notification` 的真實 payload —— 12 個型別的來源是 前一個專案 的 matcher 設定與文件，
   **從未捕獲過活的 `Notification` payload**，連 `notification_type` 這個欄位名本身都未經量測
2. plugin 的 `hooks/hooks.json` 是否支援 `async: true`（前一個專案 走 settings.json，沒驗過 plugin 路徑）
3. hook 子行程的 `getppid()` 是否等於 claude 本體的 pid（可能中間隔一層 shell）
4. `${CLAUDE_PLUGIN_ROOT}` 在 plugin hook command 中的實際展開結果
5. `PermissionRequest` / `StopFailure` / `SubagentStart` / `SubagentStop` 的真實 payload

**已由 §10 回答：** payload 欄位集合、事件時序、`PreToolUse` 與權限提示的相對順序、
subagent 事件的 session_id 共用行為、`model` 不存在、`effort` 形狀、`SessionEnd` 欄位名、
hooks 改完立即生效。

M0 的產出是 `Tests/Fixtures/real-payloads/*.json`，M1 的所有 fixture 由此衍生。

---

## 9. 開放風險

| 風險 | 影響 | 緩解 |
|---|---|---|
| `getppid()` 不是 claude 本體 | liveness 偵測失效 | M0 驗證；退路是從 `transcript_path` 反推或改用 session 心跳 TTL |
| plugin hooks 不支援 `async` | 可能拖慢 agent | M0 驗證；退路是改用使用者層 `settings.json` 合併安裝（需自行處理可逆性） |
| `notification_type` 欄位名或值域與推測不符 | `Notification` 分流全錯 | M0 必須捕獲活的 payload 才能依賴此欄位；在此之前 `Notification` 一律不改變 activity（fail-safe，靠 `PermissionRequest` 承擔） |
| Claude Code hook API 未來變更 | 解析失效 | 未知 event 不改變 activity；`schema` 版本欄位；M0 fixture 可重錄 |
| menu bar 8 顆 LED 在遠距辨識度不足 | 產品核心價值受損 | **已升級為 M4 的明確 gate**（R5）：A/B 兩形態並行原型 + persona-tester 打分決定，不預先鎖定。前一個同類專案 前一個專案 即失敗於形態選擇 |
| 常態動畫導致使用者關掉 app | 產品被棄用（前一個專案 的實際結局之一） | R4 注意力預算：只有 waiting／error 會動；重繪率列入 DoD（§7） |

---

## 10. 實測資料出處（provenance）

本 spec 的 payload 契約與時序假設，來自 2026-09-06 一次真實量測 —— 那是使用者先前的
同類專案 **前一個專案** 留下的 hook probe 產出。前一個專案 本身已被移除（app、repo 皆不存在），
但其量測產物仍在，並已成為本專案的證據基礎。

### 來源檔案

```
/private/tmp/claude-501/-Users-si-Code-Vibe-前一個專案/
  e69dc6d9-7364-4619-a438-159b48151b02/scratchpad/hookprobe/
    ├─ T2-FINDINGS.md              112 行 · 量測結論
    ├─ log.ndjson                   24 個真實 payload
    ├─ log-mysession.ndjson          9 個真實 payload
    ├─ probe-hook.sh                探針（stdin → ndjson）
    └─ settings.json.ORIGINAL       前一個專案 安裝前的乾淨基線（無 hooks key）
```

原始位置在 `/private/tmp` 下（暫存路徑，隨時可能被系統清除），
**已於 2026-09-08 複製進 repo 保存**：`docs/evidence/hook-payloads/`（唯讀證據）。
M1 的測試 fixture 由此衍生至 `Tests/Fixtures/real-payloads/`。

### 涵蓋範圍與缺口

| | 已捕獲 | 事件數 |
|---|---|---|
| ✅ | `PreToolUse` | 15 |
| ✅ | `PostToolUse` | 14 |
| ✅ | `SessionStart` · `UserPromptSubmit` · `Stop` · `SessionEnd` | 各 1 |
| ❌ | `Notification` · `PermissionRequest` · `StopFailure` · `PostToolUseFailure` · `SubagentStart` · `SubagentStop` · `PostToolBatch` · `PreCompact` / `PostCompact` | 0 |

只涵蓋 2 個 session、1 種 subagent 型別（`implementer`）、1 種 effort（`xhigh`）。
**缺口即 M0 的工作範圍。**

### 一個必須避免的錯誤解讀

初次分析時，把兩個 log 檔合併後依時間排序，看到「`SessionEnd` 之後 11 秒還有事件」，
一度判定為嚴重 bug（殭屍 session 復活）。

按 `session_id` 重新分組後證實是**合併造成的假象** —— probe hook 是全域安裝的，
兩個檔案含兩個不同 session 的事件交錯。單一 session（`91a40169`）的時序完全乾淨：
`SessionStart → UserPromptSubmit → (PreToolUse/PostToolUse)* → Stop → SessionEnd`，
`SessionEnd` 之後 0 個事件。

同一份資料裡，**subagent 覆蓋主 agent 狀態則是真的**（§2.5）：
單一 `session_id` 內主／subagent 交錯 5 次。

教訓：跨 session 的資料一律先按 `session_id` 分組再看時序。此規則寫入 §5.1 案例 11-12。
