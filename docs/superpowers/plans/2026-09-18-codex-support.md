# `codex-support` 實作計畫

> spec：`docs/superpowers/specs/2026-09-18-codex-support-design.md`（**r3**）
> 證據：`docs/2026-09-18-codex-hook-probe.md`（**F1–F15**，F15 以 `8fdce0b` 的版本為準）
> 分支：`change/codex-support`　Tier：**1**（動 `Sources/AgentAuraApp/**` → integrator 綠後派 persona-tester）
> 節號引用一律指 r3 的 spec。
> **gate 編號**：本 change 新增的一律 `CX<n>`（共 35 條）；提到**既有** gate 一律寫測試函式名，不寫 `G<n>`。

## 0. 給每個 implementer 的共同規則

- **一 task 一 commit**（必要時 refactor 拆第二個，但屬同一 task）。動工前 `git branch --show-current`
  確認不在 `main`——**而且要在 commit 前再確認一次**（多 agent 併行時 branch 會在腳下被換掉）。
- **TDD**：先 RED（理由要正確——不是編譯錯，是斷言失敗或型別還不存在），再 GREEN，再 refactor。
- **每條 gate 都要 mutation 紀錄**：把生產碼改壞（完整字串取代）→ 先確認**編譯成功** →
  指名的測試必須在 **≤ 60s 內變紅（不是掛住）** → 還原。紀錄寫進完成報告：`mutation / 指名測試 / 秒數`。
- **單檔上限**：`Sources/` 200 行、`Tests/` 300 行。**六個檔已經在或逼近上限**（spec §8.1 的表），
  其中三個要預先拆檔——見 T07／T10 的第一步。撞到紅燈時**不准刪註解擠進去**。
- **swift-testing**（`import Testing` / `@Test` / `#expect`），不是 XCTest。
- **禁止**：`--amend` 已 push 的 commit、`--no-verify`、`git reset --hard|checkout .|clean -f`、
  `fatalError`、在測試裡碰真的 `~/.codex`／`~/.claude`、**在任何地方跑 `codex exec`**（F12）。
- **既有測試不得弱化**：`#expect` 淨數量不得下降（基準 1652）；改寫既有斷言要逐條列
  「改前／改後／測的還是不是同一件事」（spec §6.4 已預告七處）。
- **Claude 側零回歸是紅線**：`plugin/hooks/hooks.json` 的 git diff 必須為空；
  `EventMapping.handledEvents` 一個字都不准動。
- 中文 commit message 用 `git commit -F - <<'EOF'`，不要 `-m`。

## 1. 任務與依賴

| # | Task | 產出 | 依賴 | gates |
|---|---|---|---|---|
| T01 | 測試底座（**零生產碼**） | 對抗式 double、fixture 覆蓋、`DirectoryTreeSnapshot` 抽取、smoke 骨架 | — | 全部 RED 且理由正確 |
| T02 | `Agent` ＋ `AgentArgument`（AuraCore 純函式） | §3、§4.1 | T01 | CX7 |
| T03 | `codexEvents` ＋ `Interrupt` 映射（**接縫**） | §4.2 | T01 | CX1–CX5 |
| T04 | `CodexHooksJSON`（逐字 F14）＋ **`CodexHookPathCheck`** | §4.3、§4.4 前半 | T03 | CX6、CX33 |
| T05 | `agent` 貫穿四段 ＋ `aura-hook` 接線 | §3、§4.1、§4.7 | T02 | CX8–CX13 |
| T06 | `CodexInstaller`（AuraHookFile，含路徑 guard） | §4.4 | T04 | CX14–CX18、CX32 |
| T07 | `CodexState`（六態）＋ `PanelAction` ＋ `OptionsMenuModel` | §3、§4.6 | T06 | CX19、CX20、CX21、CX34 |
| T08 | `PanelModel` 欄位 ＋ 61 個呼叫點（機械） | §4.6 | T07 | CX22（model 半） |
| T09 | View 層 ＋ `L10nCodex` | §4.6 | T08 | CX22（像素半）、CX23 |
| T10 | `AppDelegate` 接線 ＋ `CodexHookStore` ＋ `Uninstaller` | §4.5、§4.6、§6.2 | T06、T09 | CX24、CX25、CX26、CX31、CX35 |
| T11 | scripts ／ 文件 ／ 正典回寫 | §8.2 | T07 | CX27–CX30 |
| T12 | 整合 ＋ DoD 量測 | DoD 帳本全表 | 全部 | — |

### 並行策略（有 agent 在跑時，主 session 不在共享工作目錄作業）

```
wave 1: T01                       （單獨，擋住所有人）
wave 2: T02 ∥ T03                 （兩個不同 AuraCore 檔，無交集）
wave 3: T04（需 T03）∥ T05（需 T02）
wave 4: T06（需 T04）
wave 5: T07（需 T06）
wave 6: T08（需 T07）∥ T11（需 T07 的列標題；只動 scripts/ 與 docs/，與 T08 零交集）
wave 7: T09（需 T08）
wave 8: T10（需 T06、T09）
wave 9: T12
```
衝突檔以 `git worktree add` 隔離，作業完 merge 回 `change/codex-support`。

### 前置條件（已滿足）

`Tests/AuraCoreTests/Fixtures/round4-codex.ndjson` **已就位**：18 筆、4 個 session，
外層 `_t`／`_payload` 與既有 round1–3 同格式。事件分布（實測）：

| 事件 | 筆數 |
|---|---|
| `SessionStart` | 4 |
| `UserPromptSubmit` | 4 |
| `Stop` | 4 |
| `SessionEnd` | 4 |
| `PreToolUse` | 1 |
| `PostToolUse` | 1 |

**零筆** `Interrupt`／`PermissionRequest`／`SubagentStart`／`SubagentStop`／`PreCompact`／`PostCompact`——
這正是 CX4 必須獨立存在的理由（T03），也是 CX1 的 doc comment 要分標兩種證據強度的理由。

---

## T01 測試底座（零生產碼）

**目標**：讓後面每一條 gate 都不可能生下來就是綠的。**這個 task 不寫任何生產碼**，
交付時全部測試是 RED，且每條 RED 的理由必須是「斷言失敗」或「型別還不存在」。

1. **`DirectoryTreeSnapshot` 抽取（純重構，先做）**：把 `ClaudeHomeTreeSnapshot.swift` 的
   `walk`／`entry`／`changedPaths` 抽成通用 `DirectoryTreeSnapshot`，`ClaudeHomeTreeSnapshot`
   變成它的 skills-realpath 特化（CX14／CX32 都要用）。
   **驗收**：既有 `InstallerPathScopeTests` 兩條全綠，且**當場重跑一次既有
   `installerTouchesOnlyAllowedPaths` 的 mutation**（`connect` 順手寫 `settings.json.bak`）
   確認仍然精準紅——抽取沒有讓既有 gate 變鈍。
2. **Codex 檔案系統 fixture**（`CodexHomeFixture`）：八種形狀——`~/.codex` 不存在／是普通檔／
   是目錄（空）／`hooks.json` 是普通檔（別人的合法 JSON）／是目錄／是 **symlink 指向同目錄的
   `config.toml`**／是斷鏈 symlink／是 **5 MB 的垃圾**（> 64 KiB，驗 D-q 不讀它）；
   外加「`~/.codex` 自己是指到 fixture 之外的 symlink」。每種都植入內容已知的 `config.toml`。
3. **路徑 fixture（R-5，CX32／CX33 用）**：`translocated: true`／`inDownloads: true`／
   六個不支援字元（空白、`'`、`"`、`$`、`` ` ``、`\`）各一條路徑／**同時 translocated ＋ 含空白**
   （驗優先序）／乾淨路徑（負對照）。
4. **對抗式 payload fixture**（程式合成）：缺 `permission_mode`／缺 `model`／`tool_response`
   是 200 KB 字串／`hook_event_name: "Interrupt"` **帶** `agent_id`／`session_id` 是 UUIDv7。
5. **argv 對抗式表（7 格）**：`[]`、`["--agent"]`、`["--agent","gemini"]`、`["--agent","CODEX"]`、
   `["--agent=codex"]`、`["--agent","codex","--agent","claude"]`、`["--agent","codex","--agent"]`。
   每格期望值寫死在表裡，**不是從實作反推**。**這張表是 CX7 與 CX8 共用的唯一來源**，放共用 helper。
6. **`FakeCodexInstaller`**：① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
   ② `disconnect()` 宣稱成功但檔案還在；③ `probe()` 丟錯；
   ④ **記錄 `connect`／`disconnect`／`probe` 的呼叫順序與次數**（CX24⑤、CX35 要用）。
   **`FakeCodexStore`**：可設定「寫進去與讀回來不一致」——守「store 壞掉時我們不會誤刪別人的檔」。
7. **round4 fixture 覆蓋測試骨架**（CX13）：18 筆逐筆解析；**期望值來自探針文件的欄位表**，
   不是從 `HookPayload` 現有行為反推。外加反向斷言：探針表列出的每個欄位至少出現一次。
8. **composition-root smoke 骨架**：`CodexWiringSmokeTests` 的**五段**骨架（CX24），
   每段獨立失敗訊息；第三段要比對**位元組**（不是「非 nil」）。
9. **像素 harness 沿用**：`renderPinned` ＋ `differingPixels`（既有）；CX22／CX23 用它們。

**驗收**：`swift test` 全跑得完（不掛住），新增測試全 RED，逐條說明 RED 的理由。
**外加**：`grep -rn "codex exec" Tests/ scripts/` 為零（CX30 的人工預跑）。

---

## T02 `Agent` ＋ `AgentArgument`

**目標**：§3 的 `Agent`（`init(stored:)`／`storedRawValue`／`label`）與 §4.1 的 argv 解析，純函式、零 I/O。

- `Agent` 的安全預設就是 `.claude`（D-b），而且它是**保守失敗**（少一個標籤 vs 標錯），
  doc comment 要寫明這個不對稱，以及為什麼不套用 `Language` 那種「不給預設值」的紀律。
- `storedRawValue` 對 `.claude` 回 `nil`（D-c）——這是 CX9「Claude 狀態檔位元組不變」的單一機制。
- `AgentArgument.agent(from:)` 支援 `--agent <值>` 與 `--agent=<值>`；由左至右取**第一個**匹配；
  大小寫敏感；任何不匹配一律 `.claude`。
- `label` 對 `.codex` 回 `"Codex"`——**產品名不進 L10n**，doc comment 寫明是刻意的。

**gates**：CX7（定義域＝T01 的 7 格共用表，逐格）。

**mutation**：① 未知值改成回 `.codex` → CX7 紅；② `storedRawValue` 對 `.claude` 改成回 `"claude"` →
CX9 紅（T05 之後才觀測得到，本 task 先記，T05 補跑）。

---

## T03 `codexEvents` ＋ `Interrupt` 映射（本 change 最容易踩的接縫）

**先讀 spec §4.2 再動手**——這個 task 有一個會讓產品對 Claude 使用者完全停止運作的錯誤選項
（把 `Interrupt` 加進 `handledEvents`），而那個錯誤選項看起來像是「把對照表補齊」。

- `EventMapping.codexEvents`：12 個字面名（F2）。doc comment **分標兩種證據強度**：
  六個有 `round4-codex.ndjson` 的真實 payload；`PermissionRequest`／`Interrupt`／`SubagentStart`／
  `SubagentStop`／`PreCompact`／`PostCompact` 只有二進位字串 `HookEventsToml` 列舉這一層證據。
- `EventMapping.codexOnlyEvents = ["Interrupt"]`。
- `effect` 加 `case "Interrupt": return .setActivity(.idle)`。doc comment 必須點名
  **`Interrupt` 事件 ≠ `is_interrupt` 欄位**（後者是 `HookPayload.isInterrupt`，使用者 Ctrl+C
  中斷了一個 tool，刻意不計入 `tool_failures`）；`HookPayload.isInterrupt` 的 doc comment 也加一句反向指回。
- **`handledEvents` 一個字都不准動**；只加 doc comment 說明它是 Claude 側的來源集合。

**gates**：CX1、**CX2**（失敗訊息逐字寫「Claude Code 對 hooks.json 是全有全無解析，
多一個它不認識的事件名 → 整份 `Failed to load`」）、CX3、**CX4**（定義域從 `codexOnlyEvents`
推導，不寫 `"Interrupt"` 字面）、CX5。

**mutation**：① 把 `Interrupt` 加進 `handledEvents` → CX2 紅（**且**既有
`registeredEventsMatchHandledEvents` 也必須紅——兩條都要記）；② 從 `handledEvents` 拿掉
`PreCompact` → CX3 紅；③ **刪掉 `case "Interrupt"` 整行 → CX4 紅**（報告要把「加 CX4 之前
同一個 mutation 全綠／加之後變紅」兩次結果都寫上，這是 r1 B2 的回歸證人）；
④ 在 `plugin/hooks/hooks.json` 加 `Interrupt` → CX5 紅；⑤ `codexEvents` 少一個 → CX1 紅。

---

## T04 `CodexHooksJSON`（逐字 F14）＋ `CodexHookPathCheck`

兩個都是 AuraCore 純函式、只 import Foundation，放同一個 wave。

### 4a `CodexHooksJSON`

- 輸出**逐字**照 F14：最外層 `hooks` 物件；每個事件的值是
  `[ { "matcher": "", "hooks": [ { "type": "command", "command": "<abs> --agent codex", "timeout": 3 } ] } ]`。
- 事件鍵從 `EventMapping.codexEvents` **排序後推導**，不寫第二份清單。
- **`timeout` 從單一常數 `hookTimeoutSeconds = 3` 推導**（R-4）。doc comment 必須寫齊三件事：
  ① 這是對 F14 **唯一的數值偏離**；② 目的是避免 F13 的 clamping 警告出現在使用者的 stderr；
  ③ **「3 不觸發警告」是推論不是事實**（從沒量過 ≤ 3 的值），三種結果都可承受。
  **不准**為某個事件做特例（逐事件不同值＝在產生器裡養第二份清單）。
- **`matcher: ""` 不可省**，理由只引 F14 的「未測」欄。**不得**拿 Claude 側當佐證——
  Claude 的 19 個 entry 裡只有 `Notification` 帶 `matcher`，而且 Codex 與 Claude 是兩個解析器，
  F7 已證明它們寬容度相反（Codex 忽略不認得的事件名，Claude 整份拒載）。
- **不加 `async`**（F14 未測欄第二項）；`command` **不加引號**（F14 是裸路徑）。
- `snippet(hookBinaryPath:)`：**就是 `json(...)` 的文字形式**（同一個產生器）。

**gates**：CX6（① `hooks` 鍵集合 == `codexEvents`；② **12 個事件的 entry 逐一逐字等於 F14**，
唯一數值偏離是 `timeout` 5→3，失敗訊息帶 F13 的 clamping 引文；③ 乾淨路徑 round-trip）。

**mutation**：① 寫死 11 個事件 → CX6① 紅；② 拿掉 `matcher` → ② 紅；③ 加 `async: true` → ② 紅；
④ `command` 漏 `--agent codex` → ② 紅；⑤ **`timeout` 改回 5 → ② 紅**（刻意偏離要有自己的守衛）。

### 4b `CodexHookPathCheck`（R-5）

- `rejection(translocated:inDownloads:hookBinaryPath:) -> Rejection?`：
  ① `translocated || inDownloads` → `.mustMoveToApplications`；
  ② 否則掃路徑，**第一個**命中 `unsupportedCharacters`（空白、`'`、`"`、`$`、`` ` ``、`\`）
  的字元 → `.unsupportedCharacter(那個字元)`；③ 否則 nil。
- **零 I/O、零平台 API**：兩個布林由呼叫端注入（`AuraHookFile` 的白名單沒有 `Security`，
  `RunningBundle` 是 App 層唯一的計算點）。
- doc comment 要寫明既有 `Installer` 的 `mustMoveToApplications` **沒有**「必須在 `/Applications`」
  這個條件，所以 `~/Applications/`、`~/My Apps/` 這類合法位置可以含空白——
  「幾乎永遠不觸發」不成立。

**gates**：CX33（六個字元逐格，定義域從 `unsupportedCharacters` 推導；帶的是**第一個**命中的字元；
translocated ＋ 含空白時優先回 `.mustMoveToApplications`；乾淨路徑回 nil）。

**mutation**：① 不論實際字元一律回 `.unsupportedCharacter(" ")` → CX33 紅；② 兩條規則優先序對調 → 紅。

---

## T05 `agent` 貫穿四段 ＋ `aura-hook` 接線

**目標**：payload → 檔案 → state → UI 四段都走完（`SessionState.model` 與 `toolDescription`
各自都曾經只走完兩段就以為做完了）。

- `SessionSnapshot.agent: String?`（CodingKey `agent`），doc comment 逐字引用
  `outstandingSubagents` 那段「必須是 Optional」的理由。
- `MergeRules.merge(_:into:pid:pidStartedAt:agent:now:)`——**`agent` 不給預設值**（7 個呼叫點）。
  寫入規則 `s.agent = agent.storedRawValue ?? s.agent`（carry-forward，比照 `cwd`／`model`）。
- `SessionReducer` → `SessionState.agent: Agent`；`PanelViewModel.row` → `PanelRow.agentLabel`。
- `aura-hook/main.swift`：`let agent = AgentArgument.agent(from: CommandLine.arguments)` 傳進 merge。
  **不得新增任何 stdout／stderr 輸出、不得有非零 exit 路徑**。
- **liveness 不改**（spec §4.7）。`main.swift` 的既有註解要補一句：F15 已證實 Codex 的 hook
  父行程**不是逐事件的 shell**、pid 在 session 期間穩定，所以 `getppid()` 判活的前提成立；
  **但那五個 session 全在 `exec` 模式，互動 TUI 的行程結構未量**，並指向 spec §4.7 的 fallback
  決策點。**本 task 不實作 fallback。**

**gates**：CX8（7 格共用表真 spawn，`SpawnGate` 內序列跑）、CX9、CX10、CX11、CX12、CX13。

**mutation**：① `main.swift` 忘了傳 agent → CX10 紅；② `storedRawValue` 對 `.claude` 回
`"claude"` → CX9 紅（補跑 T02 的 ②）；③ `agent` 改成非 Optional → CX11 紅；
④ `agent` 改成 `Agent?`（enum）→ CX12 紅；⑤ **`effect` 對 `Stop` 改成 `.noChange` → CX13 紅**。

**注意**：CX8／CX10 要真的 spawn，**必須經 `SpawnGate`**。`MergeRulesTests` 目前 294 行，餘裕 6 行。

---

## T06 `CodexInstaller`

**獨立型別、獨立檔**，不塞進既有 `Installer`（157 行）或 `Installer+Connect`（125 行）。

- `Sendable`；**欄位只有兩個 `URL`**。**`Sources/AuraHookFile/` 不得出現 `UserDefaults(`／
  `UserDefaults.`**（既有 `HookVerificationStoreSourceScanTests` 會抓），**也不得 import Security**
  （module 白名單只有 Foundation ＋ CoreServices）。
- `probe()`：`lstat` → `entryType`；只有 `regularFile` **且 ≤ 64 KiB**（D-q）才
  `open(..., O_RDONLY | O_NOFOLLOW)` 讀。超過不讀（`contents = nil` → `.occupiedByOther`）。
- **`connect(json:translocated:inDownloads:)`**：
  **第一行**呼叫 `CodexHookPathCheck.rejection(...)`，非 nil 就 throw 對應的 `CodexFailure`
  （`.mustMoveToApplications`／`.unsupportedPathCharacter(c)`）——**這是保本動作，
  不准只信路由層**（S0-1(ii)：只信路由層的話，拿掉執行層的檢查不會有任何測試變紅）。
  接著 `open(path, O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC, 0o644)`（D-i）→ 寫 → close → 回傳寫出去的 `Data`。
  `codexHome` 不是目錄先 throw `.codexHomeMissing`，**不建立它**。
  **`EEXIST` 一律 → `.alreadyExists`**（四種佔用形狀實測全部回 `EEXIST`，沒有 `EISDIR`）。
- `disconnect(ifContentsEqual:)`：`O_RDONLY|O_NOFOLLOW` → `fstat` 確認 `S_IFREG` → 讀 →
  **逐位元組比對** → 不符 throw `.notOurs`（不刪）→ 相符 → **`unlink` 前再 `lstat` 一次路徑，
  比對 `fstat` 拿到的 `(dev, ino)`，不同就放棄** → `unlink`。absent 視為已斷開、冪等成功。

**gates**：**CX14**（整棵樹差異恰為 `{hooks.json}`；`config.toml` 位元組完全不變）、
**CX15**（對抗式佔用形狀各 throw `.alreadyExists`，且該路徑與 symlink 目標位元組／型別不變；
「symlink 指向 `config.toml`」那一格是核心）、CX16、CX17、CX18、
**CX32**（`translocated: true`／`inDownloads: true`／含空白路徑各一 → throw 對應的 `CodexFailure`，
**且 `codexHome` 整棵樹零差異**）。

**mutation**：① `connect` 順手寫 `hooks.json.bak` → CX14 紅；② 拿掉 `O_EXCL` → **CX15 的
symlink→`config.toml` 那格必須紅**（報告寫明是哪一格）；③ 拿掉內容比對 → CX17 紅；
④ 拿掉 unlink 前的 `(dev,ino)` 複查 → CX17 該段紅；⑤ 快照改用字面路徑 → CX18 紅；
⑥ `connect` 少寫最後一個 byte → CX16 紅；⑦ **拿掉 `connect` 第一行的路徑 guard → CX32 紅**。

---

## T07 `CodexState`（六態）＋ `PanelAction` ＋ `OptionsMenuModel`

**第一步（純搬移，獨立 commit）**：`Tests/AuraCoreTests/OptionsMenuModelTests.swift`
**目前恰好 300 行**，而本 task 要加 CX20／CX21 與 `rows(` 的新參數。
新增 `Tests/AuraCoreTests/CodexOptionsRowTests.swift` 承接 codex 相關斷言。
**零行為變更**：`#expect` 總數不變、被搬動的測試函式名一字不改。

**第二步**：
- `CodexState` 六態（含 `.blockedByBundlePath(Rejection)`、`.connectedStalePath`）；
  **帶 associated value 所以不能 `CaseIterable`**，配平行的 `CodexStateKind: String, CaseIterable`
  ＋ `samples(_:)`（D-r，比照既有 `PanelAction`／`PanelActionKind`）。
  `samples(.blockedByBundlePath)` 回**兩種 Rejection 各一個**（N7：單一代表值時「一種有接、
  另一種沒接」照樣全綠）。
- `CodexState.from(_:recordedContents:currentExpectedContents:pathRejection:)` 對 `EntryType`
  **窮盡 switch**、無 `default`，**判定順序照 spec §3 的七列表，由上而下第一個命中者勝**。
- `CodexFailure` **七個 case**（加 `mustMoveToApplications`／`unsupportedPathCharacter(Character)`）。
- `PanelAction` 加 `.connectCodex`／`.disconnectCodex`／`.copyCodexSnippet`，補 `kind` 與 `samples`。
  **不開第四個**——「重新接上」重用 `.connectCodex`（D-k）。
- `OptionsMenuModel.rows(...)` 多吃 `codex: CodexState`（**不給預設值**）；列數依 spec §4.6 表：
  `.unavailable`／`.occupiedByOther`／`.blockedByBundlePath` 各零列；`.notConnected`／`.connected`
  各恰一列；**`.connectedStalePath` 恰兩列**（「重新接上 Codex」＋「移除 Codex 掛載…」）。
- `nonMenuKinds` 加 `.copyCodexSnippet`，**並同步改 `OptionsMenuModel.swift` 的 doc comment**
  （它逐字寫著「字面集合恰為這四個」）。

**fan-out**：`OptionsMenuModel.rows(` 實測 **26 處、跨 10 個檔**，含
`L10nProductionCallSitesPassLanguageTests`（來源掃描 gate）與 `HelpDocOptionsRowCoverageTests`。
測試呼叫點一律傳 `codex: .unavailable`。

**gates**：CX19（定義域由 `EntryType.allCases × {磁碟 vs 憑證 三態} × {磁碟 vs 現在預期 二態} ×
`codexHomeIsDirectory` × {pathRejection nil／兩種}` **推導**，不寫格數）、
CX20（逐 `CodexStateKind` 斷言列數與 action）、
CX21（既有 `optionsRowsCoverEveryAction` 的代表狀態集合改由
`CodexStateKind.allCases.flatMap(CodexState.samples)` 推導；`nonMenuKindsIsExactlyThatLiteralSet`
四個 → 五個）、**CX34**（磁碟 == 憑證 != 現在預期 → `.connectedStalePath`，
三份內容都用真正的產生器輸出、兩個不同路徑；該狀態第一列的 action 是 `.connectCodex`）。

**test-edit scrutiny**：`nonMenuKindsIsExactlyThatLiteralSet` 的修改要列
「改前四個／改後五個／為什麼 `.copyCodexSnippet` 屬於非選單」——**契約變更不是弱化**；
生產碼註解的同步修改也要列。

**mutation**：① 把 `symlink` 併進 `.notConnected` → CX19 紅；② 判定表第 2／3 列對調
（stale 永遠不出現）→ CX19／CX34 紅；③ `.unavailable` 也給「接上 Codex」→ CX20 紅；
④ `.blockedByBundlePath` 給一列 → CX20 紅；⑤ `from` 忽略 `currentExpectedContents` → CX34 紅；
⑥ 把 `.connectCodex` 塞進 `nonMenuKinds` → CX21 紅。

---

## T08 `PanelModel` 欄位 ＋ 呼叫點機械更新

- `PanelModel` 加 `codex: CodexState`、`codexSnippet: String?`；`make(...)` 新參數**不給預設值**
  （既有 `panelModelMakeHasNoDefaults` 守）。
- **61 個 `PanelModel.make(` 呼叫點、26 個檔**（動工時先重新數一次並記在報告裡）。
  測試呼叫點一律傳 `codex: .unavailable`、`codexSnippet: nil`；生產呼叫點傳真實狀態。
- 改完 `wc -l` 檢查那 26 個檔沒有任何一個越過 300 行（`PanelPixelTests` 275、
  `Phase2EvidenceRenderer` 194 且有 15 個呼叫點最接近）。
- `PanelViewModelTests` 目前 288 行，CX22 的 model 半若寫不下就放 `CodexRowLabelPixelTests`
  （不要刪既有註解騰空間）。

**gates**：既有 `panelModelMakeHasNoDefaults` 繼續綠；CX22 的 model 半。

**test-edit scrutiny**：`#expect` 淨數量**不得下降**；報告附改前／改後總數（基準 1652）。

**mutation**：① `make` 忽略傳進來的 `codex` → 由 T09／T10 的渲染與 smoke gate 抓（本 task 先記）；
② `agentLabel` 對 `.claude` 也給值 → CX22 紅。

---

## T09 View 層 ＋ `L10nCodex`

- **所有新的中文字面必須住在 `Sources/AuraCore/L10nCodex.swift`**（`noStrayLiteralOutsideAllowlist`
  是真正生效的 gate），並登記進 `L10nRegistry.allEntries`。內容至少涵蓋：六態的說明句、
  兩種 `Rejection` 的文案（**`.unsupportedCharacter` 要能把字元插進句子裡**）、
  「重新接上 Codex」列標題、七個 `CodexFailure` 的 banner 文案。產品名「Codex」走 `Agent.label`。
- **列標籤放在既有的第一行 `HStack`**，不另起一行（D-l）。
- `CodexSectionView` 六態分支（spec §4.6 表）：
  - `.notConnected` → **單行提示 ＋ 按鈕，一律如此**（R-3），**不吃 `InstallState`**。
  - `.connectedStalePath` → 「App 移動過，要重新接上」＋ 按鈕（送 `.connectCodex`）。
  - `.occupiedByOther` → 說明 ＋ 可選取 snippet（`.textSelection(.enabled)`）＋「複製」。
  - `.blockedByBundlePath(.unsupportedCharacter(c))` → 解釋 ＋ **指名那個字元** ＋ snippet ＋「複製」。
  - `.blockedByBundlePath(.mustMoveToApplications)` → 解釋 ＋「移到『應用程式』」指示，
    **不給 snippet**（D-s：那個路徑下次開機就消失，給了等於發一張明天過期的票）。
  - `.unavailable`／`.connected` → 不畫。
  按鈕**必須用 `.borderless`**（離屏渲染下 `.bordered` 會被包進 `_FocusRingView` 而走訪不到）。
- 新增按鈕會動到既有離屏測試的**位置索引斷言**——改完逐一檢查 `FooterPixelTests`／
  `OptionsExpandTests` 有沒有靠索引定位的斷言，報告列出檢查結果。

**gates**：CX22 的像素半、**CX23**（帶標籤的列高仍是 43／59pt ±0.5，從真實
`NSHostingView(PanelRowView(...))` 量，不是常數對常數）、`CodexSectionRenderTests`
（六態各自渲得出預期元素；`.blockedByBundlePath` 兩種各渲一次）、
既有 `RowHeightDerivationTests`／`FooterPositionStabilityTests`／`OptionsExpandTests` 繼續綠。

**mutation**：① 標籤另起一行 → CX23 紅；② `CodexSectionView` 在 `.unavailable` 也畫 →
`OptionsExpandTests` 的高度斷言紅（**這一格要特別確認**：沒紅代表「`.unavailable` 畫面零 diff」
沒有守衛，要補一條）；③ snippet 改成手寫字串（不走 `CodexHooksJSON.snippet`）→
「snippet 與產生器同源」的斷言必須紅；④ 錯誤文案不插字元（籠統句）→ `CodexSectionRenderTests` 紅。

---

## T10 `AppDelegate` 接線 ＋ `CodexHookStore` ＋ `Uninstaller`

**第一步（兩個純搬移，獨立 commit）**：
1. `Sources/AgentAuraApp/AppDelegate+PanelActions.swift` **恰好 200 行**，把 `openHelp`／
   `helpResourceName`／`helpURL`／`reportIssue`（約 45 行含註解）搬到 `AppDelegate+Links.swift`。
2. `Tests/AgentAuraAppTests/AppDelegatePanelActionsWiredTests.swift` **恰好 300 行**，
   新增 `AppDelegateCodexWiredTests.swift` 承接 codex 接線斷言。
**兩者都零行為變更**：`swift test` 全綠、`#expect` 總數不變、既有 `HelpResourceNameTests` 一字不改
（若要改，代表搬移不純，停下來重做）。

**第二步**：
- `CodexHookStore`（`@MainActor` ＋ 注入 `UserDefaults`）：key `AgentAuraCodexHookContents`，
  值＝寫出去的 JSON 文字；`contents: Data?`／`write(_ bytes: Data)`／`clear()`。**不算 hash**。
- `AppDelegate+Codex.swift`：`codexInstaller`／`codexStore`／`codexState`；
  `reprobeCodex()`／`performConnectCodex()`／`performDisconnectCodex()`／`performCopyCodexSnippet()`。
  生產預設 `codexHome` = `FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(".codex")`（**不得用 `environment["HOME"]`**——它不吃 `$HOME`）。
- **`reprobeCodex()` 的內容與四個時機**（spec §4.6；漏接＝ tested≠wired）：
  內容＝`RunningBundle.isTranslocated()`／`isInDownloads()` → `CodexHookPathCheck.rejection(...)`
  → `installer.probe()` → `CodexState.from(obs, recordedContents: store.contents,
  currentExpectedContents: CodexHooksJSON.json(hookBinaryPath: 現在的路徑), pathRejection:)`。
  時機＝① launch 同步區（第一次 `refreshPanel()` **之前**）② popover `onOpen`
  ③ `performConnectCodex()` 之後 ④ `performDisconnectCodex()` 之後。
  `refreshPanel(icon:)` 把 `codex:`／`codexSnippet:` 帶進 `PanelModel.make`。
- **`performConnectCodex()` 要處理 stale**：目前是 `.connectedStalePath` 就先
  `disconnect(ifContentsEqual: store.contents)` 再 `connect`；其餘狀態只 `connect`。
  `connect` 的兩個布林從 `RunningBundle` 現場取。
- 剪貼簿走注入縫 `writeToPasteboard: @MainActor (String) -> Void`（測試不碰真剪貼簿）。
- 接上成功的 banner 必須**同時**含「下一個 Codex session 起生效」與「Codex 會問你信任」（D-m）。
- `Uninstaller.run()` 在 `erasePersistentDomain()` **之前**多一步
  `codexInstaller.disconnect(ifContentsEqual: store.contents)`（`try?`，D-n）。

**gates**：**CX24**（五段：① 接線 ② fake installer 真的收到 `connect`
③ **憑證進 suite 後取回來是同一串位元組**（不是「非 nil」）④ banner 含兩個關鍵詞（從 `L10nCodex`
的鍵推導）⑤ spy 記 `probe()` 次數，`onOpen` 之後 ≥ 1）、CX25、CX26、
**CX31**（`store.write(bytes)` → `store.contents == bytes` 逐位元組，輸入用**真正的產生器輸出**）、
**CX35**（`.connectedStalePath` 下送 `.connectCodex` → fake 記錄的順序是 `disconnect` → `connect`；
`.notConnected` 下只有 `connect`）、
既有 `panelActionsAreWired` 必須涵蓋三個新 kind。

**mutation**：① `.connectCodex` 分支改 `break` → CX24① 紅；② banner 只留一句 → CX24④ 紅；
③ **拿掉 `onOpen` 裡的 `reprobeCodex()` → CX24⑤ 紅**（r1 M4 的回歸證人）；
④ `codexHome` 改成 `environment["HOME"]` → CX25 紅；⑤ codex disconnect 與
`erasePersistentDomain` 對調 → CX26 紅；⑥ **在 `write` 裡加 `trimmingCharacters` → CX31 紅**；
⑦ **stale 時直接 `connect`（不先 disconnect）→ CX35 紅**。

---

## T11 scripts ／ 文件 ／ 正典回寫

- `scripts/verify-uninstall.sh`：
  - 新增第 7 項（`${CODEX_HOME:-$HOME/.codex}/hooks.json` 存在**且**含 `--agent codex` → FAIL；
    存在但不含 → PASS；不存在 → PASS）。
  - **必須可以單獨執行第 7 項**：加 `--only <n>`（或每一項抽成可 `source` 的函式）。
    理由：第 1–6 項查**真實** `$HOME`，開發機上本來就會 FAIL、整支本來就非零退出——
    用整體 exit code 當判準，mutation「拿掉第 7 項」不會紅；而且整支會跑 `osascript`（權限提示）
    與 `sfltool dumpbtm`（註解寫實測 39 秒），與「連跑 3 次 0 flake」衝突。
  - `CODEX_HOME` 覆寫的唯一理由是讓這一項可被測試，**不是給使用者的介面**，註解寫明。
  - **順手修第 2 行註解**：現在寫「D-1 五個殘留位置」，實際已六項，加第七項時一併改正。
  - 既有六項的文字不得變。
- `docs/INSTALL.md` ＋ `.zh-TW`：新增「Using it with Codex」一節（前提、按哪裡、
  **Codex 會問你一次信任**、生效時機、怎麼移除）；troubleshooting 加兩條：
  ①「燈不動？先確認 Codex 有沒有問過你信任」
  ②「想確認 Codex 到底有沒有讀到這個檔：把 `timeout` 暫時改成 5，下一個 session 的 stderr
  會出現 clamping 警告（F13）；確認完改回 3」（m2-r2——`timeout: 3` 消掉了那個訊號，這是補償）。
- `README.md` ＋ `.zh-TW`：「What it does to your Mac」加 `~/.codex/hooks.json`。
- `SECURITY.md`：「What this tool can do on your machine」加同一條；
  「Boundaries that are enforced by tests」加「`config.toml` 位元組不變、差異集合恰為 `{hooks.json}`」。
  **注意**：`SECURITY.md` 沒有叫「What it does to your Mac」的段落（那是 `README.md:160`）。
- `Resources/help-*.html` 兩份：新增 Codex 段（CX28 強制涵蓋**每一個**新的 Options 列標題，
  含「重新接上 Codex」）。
- `CLAUDE.md`：Project 狀態、Invariants（兩條）、Tier 1 清單（三個檔）。
- 正典：§2.1／§2.2／§3.2／§3.5／§3.7／§9 六處回寫（逐句對照表在 spec §8.2；
  §3.5 要帶 F15 的**範圍限定**，不能只寫「判活成立」）。

**gates**：CX27（暫存 `CODEX_HOME` ＋ `--only 7`，**判準是該項那一行的 PASS/FAIL**）、
CX28（`allRows` 改對 `CodexStateKind.allCases` 取聯集，兩個語言各自守）、CX29、CX30。

**mutation**：① 拿掉腳本第 7 項 → CX27 紅；② **只刪掉其中一個 Codex 列標題**（例如只刪
「重新接上 Codex」）→ CX28 必須紅；③ 從 SECURITY.md 刪掉 `.codex/hooks.json` → CX29 紅；
④ 在腳本裡加一行 `codex exec` → CX30 紅。

---

## T12 整合 ＋ DoD

跑 DoD 帳本全表：`swift test` 全綠且連跑 3 次 0 flake、gate mutation 帳（**35 條**，
抽驗 3 筆現場重跑）、`Sources/` 淨增、單檔行數、執行檔增量、`CodexInstaller.probe()` 成本、
啟動時間增幅、`claude plugin validate --strict`、`verify-install.sh`、`verify-uninstall.sh`、
**`plugin/hooks/hooks.json` 的 git diff 必須為空**、`~/.codex/config.toml` 自動化側位元組不變。
產出實機清單 ①–⑦ 給使用者。Tier 1 → integrator 綠後派 persona-tester。

---

## 2. 已知風險（開工前就知道，不是驚喜）

1. **`Interrupt` 進 `handledEvents` 會讓 Claude 側整份 hooks 靜默失效**——症狀是「什麼都沒發生」。
   T03 的 CX2／CX5 是唯一的守衛。
2. **`Interrupt → idle` 沒有天然的 fixture 證人**（round4 零筆），CX4 是唯一守衛；
   T03 的 mutation ③ 要把「加 CX4 之前全綠」也記下來。
3. `~/.codex/hooks.json` 是 symlink 指向 `config.toml` 時，「先 stat 再寫」會覆蓋使用者設定。
   T06 的 `O_EXCL` ＋ CX15 那一格 fixture 是唯一能區分正確與錯誤實作的輸入。
4. **產生器一旦偏離 F14，Codex 根本不會載入，而自動化抓不到**（F12）。T04 逐字照 F14、
   CX6 的 12 格逐字比對；唯一刻意偏離（`timeout`）自己配一格 mutation。
5. **寫進一個下次開機就消失的絕對路徑**（translocated／`~/Downloads`）而 UI 永遠說「已接上」：
   R-5 雙層 guard。**只擋執行層不夠**——那會做出一顆「按了才失敗的按鈕」，比沒有按鈕更糟。
6. **App 搬家後 `.connected` 永遠成立**：R-6 的 `currentExpectedContents`。
   注意偵測發生在下一次 `reprobeCodex()`，在那之前 Codex 那側已經不動而我們還沒機會講（§10-12）。
7. **憑證的 `Data → String → Data` round-trip**：壞掉的症狀是「永遠刪不掉自己的檔 → 完整移除留殘留」，
   而 CLAUDE.md 逐字寫著「移除乾淨是測試能力的前提」。CX31 是唯一守衛。
8. **`reprobeCodex()` 漏接會讓功能 tested≠wired**：裝了 Codex 卻要重開 app 才看得到，而全套綠。
9. **94 個呼叫點的機械改動**（`make` 61／`rows` 26／`merge` 7）最容易夾帶弱化。
10. **三個檔已經在上限**——沒先拆就動它們，implementer 最省事的動作是刪註解擠進去。
11. Codex 端到端只有實機能驗；報告與 spec 都不得用「已實測」描述它。
