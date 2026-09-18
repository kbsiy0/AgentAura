# Codex hook 探針：量到的事實

**日期** 2026-09-18 · **Codex CLI** 0.155.0（npm 安裝）· **macOS** 26.6.2 · 探針模型 `gpt-5.5`

這份文件是 `change/codex-support` 的證據層——跟 Claude Code 那三輪（`docs/03-measured-corrections.html`、
`Tests/AuraCoreTests/Fixtures/round1-3`）同一個方法：**契約照真實 payload 寫，不照文件。**
Codex 沒有 hook 文件；npm 套件只有二進位。所以先讀二進位字串，再用探針 hook 實抓。

所有路徑與 session id 已去識別化；原始捕獲不進 repo（同 Claude 三輪的處理）。

## 方法

1. `strings` 掃 218 MB 的 codex 二進位，找 hook 事件名、payload 欄位、設定鍵。
2. 探針 hook：一支只會把 stdin、argv、環境變數、cwd 追加進 ndjson 然後 `exit 0` 的腳本。
3. `~/.codex/hooks.json` 註冊全部事件指向探針；用 `codex exec` 跑短 session；每輪結束移除該檔。
4. 六輪成功 session、24 筆事件。`config.toml` 以 md5 前後比對。

## 事實（F1–F13）

| # | 事實 | 證據 |
|---|---|---|
| F1 | **Codex 讀 `~/.codex/hooks.json`**，結構與 Claude Code 相同（`matcher`／`hooks`／`type: command`／`command`／`timeout`） | stderr 出現 `warning: clamping SessionEnd hook timeout to 3s in ~/.codex/hooks.json` —— 檔案被解析、事件名被認得 |
| F2 | **事件名與 Claude Code 完全相同**，共 12 個：`PreToolUse` `PermissionRequest` `PostToolUse` `PreCompact` `PostCompact` `SessionStart` `SessionEnd` `UserPromptSubmit` `SubagentStart` `SubagentStop` `Stop` `Interrupt`。**沒有** `Notification`、`PostToolUseFailure`、`PostModelSwitch` | 二進位字串 `HookEventsToml` 列舉；exec 實抓到其中 6 個 |
| F3 | payload 欄位與 Claude Code 同名同形（見下表） | 24 筆逐欄比對 |
| F4 | shell 工具的 `tool_name` 是 **`"Bash"`**；`tool_response` 是**純字串（stdout）**，沒有 exit code、沒有錯誤欄位 | `PostToolUse` 樣本：`"tool_response": "agentaura-probe\n"`；沙箱擋掉的寫入仍是正常 `PostToolUse`，失敗只出現在 `Stop.last_assistant_message` 的文字裡 |
| F5 | **未信任的 hook 在 `codex exec` 下靜默跳過，零訊息**；`--dangerously-bypass-hook-trust` 會執行 | 同一份 hooks.json：無旗標 0 筆、有旗標 4 筆。信任的持久化位置**找不到**：不在 `config.toml`（無 `[hooks` 段）、不在 `state_5.sqlite`（無 hook 表）、不在 `.codex-global-state.json` |
| F6 | **hook 不在沙箱裡執行** | `--sandbox read-only` 下探針仍寫進 workdir 外的 log。→ `aura-hook` 寫 `~/.agentaura/` 不會被沙箱擋 |
| F7 | **對不認得的事件名寬容**——與 Claude Code 的全有全無相反 | hooks.json 多塞 `Notification`、`PostToolUseFailure`：其餘事件照常觸發，無 `Failed to load hooks` |
| F8 | hook 的 `command` 字串**可以帶參數** | `"command": "…/probe.sh --agent codex"` → 探針收到 `argv = "--agent codex"` |
| F9 | 環境變數**沒有** `CLAUDE_PLUGIN_ROOT`／`PLUGIN_ROOT`；有 `CODEX_MANAGED_PACKAGE_ROOT`、`CODEX_MANAGED_BY_NPM=1`。hook 的 cwd = session 的 cwd | 探針記錄的 `_env`／`_cwd` |
| F10 | **`codex exec` 強制 `approval: never`**，即使 `-c approval_policy="on-request"` 覆寫也一樣；`exec` 子指令沒有 `-a` 旗標 → **`PermissionRequest` 在 exec 模式不可能出現** | stderr banner `approval: never`；`-a` → `error: unexpected argument` |
| F11 | `SessionStart.source = "startup"`；`SessionEnd.reason = "other"`；exec 下 `permission_mode = "bypassPermissions"`（Claude Code 相容的值名） | 樣本 |
| F12 | `codex exec` 會在 **`config.toml` 寫入** `[projects."<cwd>"] trust_level = "trusted"`——這是 Codex 對工作目錄的標準行為，與 hook 無關，但**任何驗收腳本若跑 `codex exec` 都會改到使用者的 config.toml** | md5 前後比對＋diff |
| F13 | `SessionEnd`、`Interrupt` 的 hook timeout 被**強制壓到 3 秒** | stderr clamping 警告。`aura-hook` 單次 ~7 ms，無影響 |

## 每種事件的欄位（exec 實抓）

| 事件 | 欄位 |
|---|---|
| `SessionStart` | `session_id` `cwd` `hook_event_name` `model` `permission_mode` `source` `transcript_path` |
| `UserPromptSubmit` | 上述 ＋ `turn_id` `prompt` |
| `PreToolUse` | 上述 ＋ `turn_id` `tool_name` `tool_input` `tool_use_id` |
| `PostToolUse` | `PreToolUse` ＋ `tool_response`（字串） |
| `Stop` | `session_id` `cwd` `hook_event_name` `model` `permission_mode` `turn_id` `transcript_path` `last_assistant_message` `stop_hook_active` |
| `SessionEnd` | `session_id` `cwd` `hook_event_name` `transcript_path` `reason` |

`session_id` 與 `turn_id` 是 UUIDv7。`transcript_path` 形如
`~/.codex/sessions/YYYY/MM/DD/rollout-<ISO 時戳>-<session_id>.jsonl`。
主 agent 的事件**沒有** `agent_type` 欄位——與 Claude Code 主 agent 相同（`HookPayload` 現有邏輯直接適用）。

## 去識別化樣本

```json
{"session_id":"<uuidv7>","transcript_path":"/Users/you/.codex/sessions/2026/09/18/rollout-2026-09-18T15-40-33-<uuidv7>.jsonl","cwd":"/Users/you/Code/demo-project","hook_event_name":"SessionStart","model":"gpt-5.5","permission_mode":"bypassPermissions","source":"startup"}
{"session_id":"<uuidv7>","turn_id":"<uuidv7>","transcript_path":"…","cwd":"/Users/you/Code/demo-project","hook_event_name":"UserPromptSubmit","model":"gpt-5.5","permission_mode":"bypassPermissions","prompt":"[redacted] user prompt"}
{"session_id":"<uuidv7>","turn_id":"<uuidv7>","transcript_path":"…","cwd":"/Users/you/Code/demo-project","hook_event_name":"PreToolUse","model":"gpt-5.5","permission_mode":"bypassPermissions","tool_name":"Bash","tool_input":{"command":"echo agentaura-probe"},"tool_use_id":"<id>"}
{"session_id":"<uuidv7>","turn_id":"<uuidv7>","transcript_path":"…","cwd":"/Users/you/Code/demo-project","hook_event_name":"PostToolUse","model":"gpt-5.5","permission_mode":"bypassPermissions","tool_name":"Bash","tool_input":{"command":"echo agentaura-probe"},"tool_use_id":"<id>","tool_response":"agentaura-probe\n"}
{"session_id":"<uuidv7>","turn_id":"<uuidv7>","transcript_path":"…","cwd":"/Users/you/Code/demo-project","hook_event_name":"Stop","model":"gpt-5.5","permission_mode":"bypassPermissions","stop_hook_active":false,"last_assistant_message":"OK"}
{"session_id":"<uuidv7>","transcript_path":"…","cwd":"/Users/you/Code/demo-project","hook_event_name":"SessionEnd","reason":"other"}
```

## 對設計的直接後果

- **同一顆 `aura-hook` 可以吃 Codex 的事件**（F2／F3）。來源用 `--agent codex` 參數分辨（F8），不猜環境變數（F9 顯示沒有可靠的 Codex 專屬變數——npm 以外的安裝方式不會有 `CODEX_MANAGED_*`）。
- **hooks.json 裡的路徑必須是絕對路徑**（F9：沒有 `CLAUDE_PLUGIN_ROOT`）。
- **Codex session 沒有 `error` 狀態的來源**（F2、F4）。列為 known gap，不硬推。
- **`waiting` 只會在互動 TUI 出現**（F10）。`exec` 跑的 session 永遠不 waiting——正確，它不能等人。
- **安裝要求使用者在 Codex 裡按一次信任**（F5），且我們**無法偵測**是否已信任。UI 只能明講，不能假裝知道。
- **不要在驗收腳本裡跑 `codex exec`**，或跑了要說明它會改 `config.toml`（F12）。
- 兩邊可以**共用一份 hooks.json 的事件清單**（F7）：多出來的 Claude 專屬事件 Codex 會忽略；反過來 Claude Code 是全有全無，所以給 Claude 的那份**不能**含 `Interrupt`。

## 尚未量到（需要互動 TUI）

`PermissionRequest` 的 payload 形狀、`Interrupt` 的形狀、`SubagentStart`／`SubagentStop`、
信任提示的 UX 與持久化位置。互動探針工具包已備好，待有空檔時跑一次。
**這些在量到之前，spec 只能寫成「待驗」，不能寫成事實。**

## 補充：探針用的 `~/.codex/hooks.json` 逐字形狀（F14）

被 Codex 成功解析並觸發的那份檔案，每個事件的值是下面這個形狀（`matcher` 為空字串、`timeout` 秒；
最外層是 `hooks` 物件，與 Claude Code 的 `plugin/hooks/hooks.json` 相同）：

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "/abs/path/to/aura-hook --agent codex", "timeout": 5 }
        ]
      }
    ]
  }
}
```

**未測**：省略 `matcher` 是否可行、Claude 側用的 `"async": true` Codex 是否接受或拒絕、`timeout` 省略時的預設值。
產生器一律照上面這個**已驗證**的形狀輸出，不加未測欄位。

## 補充：hook 的父行程在整個 session 裡是同一個（F15）

spec review 指出 `aura-hook` 的判活靠 `getppid()`（父行程死了整列就顯示已結束），而 Codex 側的父行程沒量過。
回頭查探針原始紀錄：每筆都記了探針腳本自己的 `$PPID`。**五個 session、共 24 筆事件，每個 session 內的所有事件
（`SessionStart` 到 `SessionEnd`，跨 4–6 筆、數秒到數十秒）`$PPID` 完全相同**；不同 session 則不同。
→ 呼叫 hook 的**不是每個事件開一次的短命 shell**，而是一個至少活過「第一個事件到最後一個事件」的行程。
`getppid()` 判活的前提（pid 在 session 期間穩定）對 Codex 成立。

**範圍限定**：這五個 session **全部跑在 `codex exec`**。互動 TUI 的行程結構未量——TUI 有可能由一個常駐行程 fork 出 session，
那樣的話父行程會跨 session 存活。實機驗收時要順帶記 `ps -o ppid=,comm=`。

**未觀測**：(a) `SessionEnd` **之後**那個 pid 是否結束（探針沒有在 session 結束後再查）——「隨 session 結束」是推論，不是事實；
實務後果有限，因為 `SessionEnd` 會設 `terminated`，判活的第一個 guard 就是它。(b) 那個 pid 是 `codex` 原生二進位還是 npm 的
node 啟動器（探針沒記 `ps -o comm=`）。互動探針工具包已補上 `comm` 與祖父行程的記錄以便釐清。
