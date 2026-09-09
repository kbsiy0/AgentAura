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
  "model": "claude-opus-5[1m]",
  "source": "startup",
  "reason": null,

  "main_activity": "waiting",
  "main_tool": "Bash",
  "sub_activity": "working",
  "sub_tool": "Grep",
  "sub_agent_type": "Explore",

  "notification_type": null,
  "notification_message": null,
  "tool_description": "Download example.com to dl2.html",
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
| `model` | `SessionStart` 帶 model | **第一輪：任何 event 都沒有；第二輪（2026-09-08）：`SessionStart` 有** `"model":"claude-opus-5[1m]"`。以第二輪為準 —— 面板可顯示模型，但只有 `SessionStart` 提供，須由 `MergeRules` 帶過來 |
| `effort` | 字串 `"high"` | 物件 `{"level":"xhigh"}` → `aura-hook` 攤平存字串 |
| `SessionEnd` 結束原因 | `end_reason` | 實際欄位名是 **`reason`** |
| `SessionStart` | 無額外欄位 | 有 **`source`**（區分 fresh start / resume） |
| `PostToolUse` | 只有 `tool_output` | 有 **`duration_ms`** 與 `tool_response` → 面板可顯示 tool 耗時 |
| `Stop` | `last_assistant_message` | 確認存在，另有 `background_tasks` / `session_crons` / `stop_hook_active` |
| 全部 tool event | — | 皆帶 `scratchpad_dir`、`prompt_id`、`transcript_path` |

`transcript_path` 出現在**每一個** payload 上，是未來 enrichment 的唯一縫（代價是依賴內部
jsonl 格式）—— 不進第一版。

### 2.1.2 第二輪實測補充（2026-09-08，兩個 session、45 個事件）

| 發現 | 內容 |
|---|---|
| `notification_type` **欄位名確認正確** | 實捕 `Notification` payload：`{"notification_type":"idle_prompt","message":"Claude is waiting for your input"}`。此欄位先前只有文件依據，現已量測確認 |
| `Notification` 多一個 `message` 欄位 | 人可讀字串，面板可直接顯示 |
| `Notification` payload **缺** `permission_mode` / `effort` | 各 event 的欄位集合不同 —— 字典式解析（§3.x）天生容忍 |
| `SessionStart` 有 `model` | 見上表 |
| `SubagentStop` 有 `agent_transcript_path` | subagent 的獨立 transcript |
| **內部 subagent 的 `agent_type` 是空字串** | 見 §2.5.1 —— 這導出一個 critical bug |
| `auto` 已是預設權限模式 | `PermissionRequest` 只在**每次都問**的模式觸發（CLI 旗標是 `--permission-mode manual`，文件裡稱 `default`）；`auto` 模式的拒絕走 `PermissionDenied` |
| **Bash exit≠0 不觸發 `PostToolUseFailure`** | 指令回非零只是「tool 成功執行、輸出裡有錯誤」。`PostToolUseFailure` 只在 tool 本身失敗時觸發（實測：`Read` 不存在的檔）。**影響 `tool_failures` 的語意** —— 面板該欄位計的是「tool 層級的錯誤」，不含失敗的 shell 指令。這其實是對的語意（測試紅燈是正常工作），但面板文案不可寫成「指令失敗數」 |
| `PostToolUseFailure` 的錯誤欄位叫 **`error`**，不叫 `tool_error` | **這一列先前是錯的**（原本寫「沒有錯誤欄位」）。錯誤來源是我當時用一份手寫的 key 清單過濾 payload 再印出來，`error` 被自己的過濾器濾掉，卻據此下了「不存在」的結論。實際值是完整的錯誤訊息（例：`File does not exist. Note: your current working directory is …`）。面板可用它顯示 tool 失敗的原因 |
| `PostToolUseFailure` 另帶 **`is_interrupt`**（布林） | 區分「tool 真的失敗」與「使用者按 Ctrl+C 中斷」。**中斷不該計入 `tool_failures`** —— 那是使用者的動作，不是失敗。實測樣本只有 `false`，`true` 的情況未驗證 |
| `PostToolBatch` 帶 **`tool_calls`**（陣列） | 該批次的全部 tool 呼叫。可得批次大小，目前不需要 |
| CLI 的 `--permission-mode manual` 在 payload 裡是 `"default"` | 兩者是同一個模式的不同名字。狀態檔範例用 `"default"` 正確 |
| `PermissionRequest` 帶 `tool_name` / `tool_input` / **`permission_suggestions`** | 最後一項是規則建議陣列。面板可用 `tool_input.description` 顯示「在等你批准什麼」 |
| `SessionEnd` 的 `reason` 實測值：`"prompt_input_exit"` | 確認欄位名是 `reason` |
| **`Notification(permission_prompt)` 沒有觸發** | 真的出現權限提示時，只送 `PermissionRequest`，沒有對應的 `Notification`。§2.2.1 表中的 `permission_prompt` 來自 前一個專案 的 matcher 與文件，實測未出現 —— 保留在表中無害（兩者都映射到 `waiting`），但**主要訊號確定是 `PermissionRequest`**，這驗證了 §2.2.1「不需要靠 Notification 兜底」的判斷 |
| **使用者按 Deny 不產生任何 hook 事件** | 見 §2.4.1 —— 這導出一個 false-positive bug |
| `PermissionDenied` 只在 **auto 模式自動拒絕**時觸發 | 不是使用者手動 Deny。故仍未捕獲，改列 best-effort |

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
| `PostModelSwitch` | 不變 | activity 不變，但**必須讀 `to_model` 更新 model** —— 見下方說明 |
| 未知 `hook_event_name` | 不變 | 只更新 `written_at`，activity 保持原值 |

`PostModelSwitch` 是拿官方完整 event 清單逐一對照時發現的缺口：`model` 只有 `SessionStart`
提供，使用者中途 `/model` 換模型後，面板會一直顯示開場時的模型。該 event 帶
`from_model` / `to_model`，讀 `to_model` 即可修正。activity 不受影響。

其餘落到 default（不改變 activity）的 event 逐一確認過皆正確：`Setup`（只在 `--init-only`
觸發）、`UserPromptExpansion`（緊接著會有 `UserPromptSubmit`）、`TaskCreated` / `TaskCompleted`、
`InstructionsLoaded`、`ConfigChange`、`CwdChanged`、`DirectoryAdded`、`FileChanged`、
`WorktreeCreate` / `WorktreeRemove`、`PreModelSwitch`（等 `PostModelSwitch` 即可）。
`MessageDisplay` 刻意**不註冊** —— 它在助理訊息串流時持續觸發，量級不適合當狀態訊號。
`TeammateIdle` 待觀察：使用者的 settings 有 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`，
可能真的會觸發，屆時再依實測決定映射。

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

### 2.4.1 `waiting` 不得進入 unacked 尾巴（false-positive 修正）

**第三輪實測發現。** 使用者按 Deny 拒絕權限請求時，**不產生任何 hook 事件** ——
實測序列：

```
+68.44s  PreToolUse         Bash
+68.45s  PermissionRequest  Bash     ← 提示出現
（使用者按 Deny）                      ← 沒有任何事件
+91.04s  SessionEnd         reason=prompt_input_exit
```

`PermissionDenied` 只在 **auto 模式自動拒絕**時觸發，不涵蓋使用者手動 Deny。
所以 session 的最後事件停在 `PermissionRequest` → `main_activity` 卡在 `waiting`。

若 `waiting` 也能進入 unacked 尾巴，結果是：**一個已經結束、而且使用者早就回答過的
session，會讓 icon 一直亮橘燈說「有人在等你」** —— 這正是本產品最不該犯的錯。

**修法：只有 `done` 與 `error` 能進入 unacked 尾巴。**

```swift
if state.liveness != .ended { return true }          // 活著的都可見
// waiting 不是「結果」——已結束的 session 不可能還在等你回答
return (state.activity == .done || state.activity == .error)
       && !acknowledged.contains(state.id)
```

理由：尾巴存在的目的是「讓你看到還沒看過的**結果**」。`waiting` 不是結果，
是一個已經無從行動的中間狀態。同理，pid 死亡（crash）時卡在 `waiting` 的 session
也一併丟棄。

**誠實的限制**：本次實測中使用者在 Deny 後 22 秒就退出，所以無法確認「若繼續留著，
最終是否會有 `Stop` 抵達」。上述修法在兩種情況下都正確，故不因此阻塞。

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

### 2.5.1 主 agent 靜止後必須忽略 subagent 事件（critical）

**第二輪實測發現的第二個 bug，比第一個更普遍 —— 它會影響每一個跑完的 session。**

Claude Code 會執行**內部 subagent**（摘要／標題那類），特徵：

- `agent_type` 是**空字串**（不是 null），`agent_id` 正常
- **只送 `SubagentStop`，不送 `SubagentStart`**
- 在主 agent 的 `Stop` **之後**才送 —— 實測兩個 session 皆重現，間隔 **+2.58s** 與 **+184.37s**

在只有 §2.5 分槽 + `max` 的設計下：

```
Stop            → main = done,  sub = nil   → 綠燈
SubagentStop    → sub  = working             → max(done, working) = working
（2.6 秒後）                                  → 綠燈變藍燈，且永遠回不去
```

不會有第二個 `Stop` 把它救回來，所以**每個 session 完成後的綠燈都會在幾秒內變成藍燈**。
`done` 是最常見的完成訊號，這等於把它整個廢掉。

**修法：主 agent 處於靜止態（`waiting` / `done` / `error`）時，完全忽略 subagent 事件** ——
不寫 sub 槽，只更新 `written_at`。

```swift
if payload.isSubagent {
    guard !file.main_activity.isQuiescent else { /* 只更新時戳 */ }
    file.sub_activity = activity(of: payload)
}
```

理由：主 agent 已停下時，殘留的 subagent 活動不是內部雜務就是與「這個 session 是否在為你工作」
無關。這條規則同時**更直接地**保護了 §2.5 的原始情境（main = waiting 時 subagent 蓋不掉它），
比單靠 `max` 更強。

**連帶修正：**

1. `agent_type` 為空字串時正規化為 `nil` —— 否則 `subagents` 會出現 `"": N` 這種鍵
2. `subagents` 只在 `SubagentStart` **且** `agent_type` 非空時累加 —— 內部 subagent 因此不計入
3. **已驗證**（2026-09-08 派真實 subagent 實測）：真實 subagent **確實**送 `SubagentStart`，
   且 `agent_type` 有意義的值。實測捕獲 `SubagentStart` / `PreToolUse` ×9 /
   `PostToolUse` ×8 / `PostToolBatch` ×5 / `PostToolUseFailure` ×1，`agent_type` 皆為
   `"aura-t02"`（dispatch 時給的 agent 名稱）。故「以 `SubagentStart` 且 `agent_type` 非空
   計數」的規則成立，內部 subagent（空字串）自然被排除

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

**顯示模型** —— 這裡原本寫「不顯示模型 —— 實測確認 hook payload 完全不帶 `model`」，
那是**第一輪的結論，已被第二輪推翻**（§2.1.1 的表格記錄了推翻，這一句沒有同步 ——
同一份文件裡兩個相反的陳述）。

實際：`SessionStart` 帶 `"model":"claude-opus-5[1m]"`（`round2.ndjson` 有 2 筆），
由 `MergeRules` carry-forward；使用者中途 `/model` 換模型時，`PostModelSwitch`
帶 `to_model` 更新它。面板的 meta 行顯示「模型 · effort · permission_mode」，
缺值整段省略不留懸空分隔符。

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
| 讀到寫入一半的 JSON | session 閃現／消失 | `LOCK_SH` 讀取；解析失敗保留上次已知狀態並重試。**已有實證**：T01 的探針用 `printf >>` 併發 append，150 行裡有 2 行被寫壞（UTF-8 解碼失敗）—— 這正是 `aura-hook` 必須用 `flock` 而非 append 的理由 |
| subagent 事件蓋掉主 agent 的 `waiting` | **最重要的訊號被靜默抹除** | main / sub 分槽，取 D1 優先序 max（§2.5） |
| 內部 subagent 在 `Stop` 之後送 `SubagentStop` | **每個完成的 session 綠燈都變藍燈且回不去** | 主 agent 靜止態時完全忽略 subagent 事件（§2.5.1） |
| 使用者按 Deny 後 session 結束，卡在 `waiting` | **已結束又已回答的 session 一直亮橘燈說「有人在等你」** | 只有 `done` / `error` 能進 unacked 尾巴（§2.4.1） |
| `agent_type` 為空字串 | `subagents` 出現 `"": N` 這種無意義鍵 | 空字串正規化為 nil，計數時跳過（§2.5.1） |
| 未知 `notification_type` | 無故亮橘燈（auth / quota 雜訊） | 不改變 activity；`PermissionRequest` 已覆蓋真正的等待情況（§2.2.1） |
| Claude Code 新增 hook event | 解析爆掉 | 未知 event 不改變 activity，只更新時戳；`schema` 欄位擋不相容 |
| app 未運行時累積事件 | 啟動後畫面空白 | `bootstrap()` 掃目錄；靜止態天生在檔案裡 |
| 殘留檔案（機器重開） | 幽靈 session | 啟動時 pid 一律驗證；已死且已確認者刪檔 |
| **狀態檔被外部刪除**（使用者手動 `rm`） | 面板永遠顯示已不存在的幽靈 session，且無任何路徑可清除 | `refreshLiveness` 讀不到檔案即從 registry 移除 —— 檔案是狀態的唯一真實來源。若該 session 其實還活著，下一個 hook 事件會重建它 |
| **狀態目錄被整個刪除** | 後續所有 hook 寫入失敗（`aura-hook` 靜默 exit 0），面板永久凍結在刪除前的狀態且無任何錯誤跡象 | `refreshLiveness` 每輪確保目錄存在 |
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
16. **主 agent `Stop` 之後 2.6s 送 `SubagentStop`（`agent_type` 空字串）→ activity 必須維持 `done`**（§2.5.1）
17. 主 agent `StopFailure` 之後送 `SubagentStop` → 必須維持 `error`
18. 主 agent `PermissionRequest` 之後送 `SubagentStop` → 必須維持 `waiting`
19. 只有 `SubagentStop` 沒有 `SubagentStart` 的 subagent → 不得計入 `subagents`
20. `Notification` payload 缺 `permission_mode` / `effort` → 不得使既有值被清掉
21. `SessionStart` 帶 `model`，後續 event 不帶 → `model` 必須被帶過來
22. **`PermissionRequest` 後直接 `SessionEnd`（使用者按 Deny 的實測序列）→ 該 session 不得留在尾巴亮橘燈**（§2.4.1）
23. pid 死亡且最後狀態是 `waiting` → 同上，必須丟棄
24. 已結束的 `done` / `error` → 必須留在尾巴

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
| 主 agent 靜止時忽略 subagent 事件（改回一律寫 sub 槽） | 「`Stop` 後的 `SubagentStop` 不得把 done 變成 working」 |
| `agent_type` 空字串正規化 | 「`subagents` 不得出現空字串鍵」 |
| 尾巴的 `done`/`error` 限制（改回收所有靜止態） | 「`PermissionRequest` 後 `SessionEnd` 的 session 不得亮橘燈」 |

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

### 第二輪（2026-09-08）

`docs/evidence/hook-payloads/round2/`（`probe.sh` + `log.ndjson`）。兩個 session、45 個事件。

補齊：`Notification`（含確認 `notification_type` 欄位名）、`SessionStart`（含 `model`）、
`Stop`、`SubagentStop`、`PostToolBatch`、`PostToolUseFailure`、`UserPromptSubmit`。

仍缺：`PermissionRequest`、`PermissionDenied`（需 `default` 權限模式，`auto` 已是預設）、
`SubagentStart`、`StopFailure`、`PreCompact` / `PostCompact`。

**產出**：§2.1.2 的補充，以及 §2.5.1 的 critical bug —— 那個 bug 影響每一個
跑完的 session，且只有靠真實時序資料才看得到（單靠文件推不出「內部 subagent 會在
Stop 之後才送 SubagentStop」）。這是 M0 排在最前面的具體回報。

### 第三輪（2026-09-08，`--permission-mode manual`）

同一份 `round2/log.ndjson`（累計 101 個事件、4 個 session）。

補齊：`PermissionRequest`（×2，含 `permission_suggestions`）、`SessionEnd`（含
`reason="prompt_input_exit"`）、`PostToolUseFailure`。

**產出**：§2.4.1 的 false-positive bug（使用者按 Deny 不產生事件 → session 卡在
`waiting` → 已結束又已回答卻一直亮橘燈），以及確認「真的出現權限提示時只送
`PermissionRequest`、沒有對應的 `Notification`」—— 這驗證了 §2.2.1 不靠 Notification
兜底的判斷。

仍缺（全部改列 best-effort）：`PermissionDenied`（只在 auto 模式自動拒絕時觸發）、
`SubagentStart`（內部 subagent 不送；真實 subagent 待 T02 dispatch 時觀察）、
`StopFailure`、`PreCompact` / `PostCompact`。
