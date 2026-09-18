# `codex-support` 實作計畫

> spec：`docs/superpowers/specs/2026-09-18-codex-support-design.md`（**r2**）
> 證據：`docs/2026-09-18-codex-hook-probe.md`（**F1–F15**）——**任何關於 Codex 行為的斷言都要指得回 F 編號**
> 分支：`change/codex-support`　Tier：**1**（動 `Sources/AgentAuraApp/**` → integrator 綠後派 persona-tester）
> 節號引用一律指 r2 的 spec。
> **gate 編號**：本 change 新增的一律 `CX<n>`；提到**既有** gate 一律寫測試函式名，不寫 `G<n>`
> （review r1 M6：新舊編號碰撞會讓 DoD 的 mutation 帳對錯人）。

## 0. 給每個 implementer 的共同規則

- **一 task 一 commit**（必要時 refactor 拆第二個，但屬同一 task）。動工前 `git branch --show-current`
  確認不在 `main`——**而且要在 commit 前再確認一次**（多 agent 併行時 branch 會在腳下被換掉）。
- **TDD**：先 RED（理由要正確——不是編譯錯，是斷言失敗或型別還不存在），再 GREEN，再 refactor。
- **每條 gate 都要 mutation 紀錄**：把生產碼改壞（完整字串取代）→ 先確認**編譯成功** →
  指名的測試必須在 **≤ 60s 內變紅（不是掛住）** → 還原。紀錄寫進完成報告：`mutation / 指名測試 / 秒數`。
- **單檔上限**：`Sources/` 200 行、`Tests/` 300 行（`IsolationTests.fileLengthLimit` 從磁碟推導）。
  **五個檔已經在或逼近上限**（spec §8.1 的表），其中三個要預先拆檔——見 T07／T10 的第一步。
  撞到紅燈時**不准刪註解擠進去**：那是在拆掉別人留下的理由（CLAUDE.md gate 哲學）。
- **swift-testing**（`import Testing` / `@Test` / `#expect`），不是 XCTest。
- **禁止**：`--amend` 已 push 的 commit、`--no-verify`、`git reset --hard|checkout .|clean -f`、
  `fatalError`（會殺掉 `swiftpm-testing-helper`）、在測試裡碰真的 `~/.codex`／`~/.claude`、
  **在任何地方跑 `codex exec`**（F12：它會寫 `[projects."<cwd>"] trust_level` 進使用者的 `config.toml`）。
- **既有測試不得弱化**：`#expect` 淨數量不得下降；改寫既有斷言要在報告裡逐條列
  「改前／改後／測的還是不是同一件事」（spec §6.4 已預告七處）。
- **Claude 側零回歸是紅線**：`plugin/hooks/hooks.json` 的 git diff 必須為空；
  `EventMapping.handledEvents` 一個字都不准動。
- 中文 commit message 用 `git commit -F - <<'EOF'`，不要 `-m`（zsh 的 history expansion 會吃掉 `!`）。

## 1. 任務與依賴

| # | Task | 產出 | 依賴 | gates |
|---|---|---|---|---|
| T01 | 測試底座（**零生產碼**） | 對抗式 double、fixture 覆蓋、`DirectoryTreeSnapshot` 抽取、smoke 骨架 | — | 全部 RED 且理由正確 |
| T02 | `Agent` ＋ `AgentArgument`（AuraCore 純函式） | §3、§4.1 | T01 | CX7 |
| T03 | `codexEvents` ＋ `Interrupt` 映射（**接縫**） | §4.2 | T01 | CX1、CX2、CX3、**CX4**、CX5 |
| T04 | `CodexHooksJSON` 產生器（逐字 F14） | §4.3 | T03 | CX6 |
| T05 | `agent` 貫穿四段 ＋ `aura-hook` 接線 | §3、§4.1、§4.7 | T02 | CX8–CX13 |
| T06 | `CodexInstaller`（AuraHookFile） | §4.4 | T04 | CX14–CX18 |
| T07 | `CodexState` ＋ `PanelAction` ＋ `OptionsMenuModel` | §3、§4.6 | T06 | CX19、CX20、CX21 |
| T08 | `PanelModel` 欄位 ＋ 61 個呼叫點（機械） | §4.6 | T07 | CX22（model 半） |
| T09 | View 層 ＋ `L10nCodex` | §4.6 | T08 | CX22（像素半）、CX23 |
| T10 | `AppDelegate` 接線 ＋ `CodexHookStore` ＋ `Uninstaller` | §4.5、§4.6、§6.2 | T06、T09 | CX24、CX25、CX26 |
| T11 | scripts ／ 文件 ／ 正典回寫 | §8.2 | T07 | CX27、CX28、CX29、CX30 |
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
外層 `_t`／`_payload` 與既有 round1–3 同格式。事件分布（實測，T01 的斷言以此為準）：

| 事件 | 筆數 |
|---|---|
| `SessionStart` | 4 |
| `UserPromptSubmit` | 4 |
| `Stop` | 4 |
| `SessionEnd` | 4 |
| `PreToolUse` | 1 |
| `PostToolUse` | 1 |

**零筆** `Interrupt`／`PermissionRequest`／`SubagentStart`／`SubagentStop`／`PreCompact`／`PostCompact`——
這正是 CX4 必須獨立存在的理由（見 T03），也是 CX1 的 doc comment 要分標兩種證據強度的理由。

---

## T01 測試底座（零生產碼）

**目標**：讓後面每一條 gate 都不可能生下來就是綠的。**這個 task 不寫任何生產碼**，
交付時全部測試是 RED，且每條 RED 的理由必須是「斷言失敗」或「型別還不存在」，不能是「harness 自己壞了」。

1. **`DirectoryTreeSnapshot` 抽取（純重構，先做）**：把 `Tests/AuraCoreTests/Support/
   ClaudeHomeTreeSnapshot.swift` 的 `walk`／`entry`／`changedPaths` 抽成通用
   `DirectoryTreeSnapshot`，`ClaudeHomeTreeSnapshot` 變成它的 skills-realpath 特化。
   **驗收**：既有 `InstallerPathScopeTests` 兩條全綠，且**當場重跑一次既有
   `installerTouchesOnlyAllowedPaths` 的 mutation**（`connect` 順手寫 `settings.json.bak`）
   確認仍然精準紅——抽取機制沒有讓既有 gate 變鈍。
2. **Codex 檔案系統 fixture**（`CodexHomeFixture`）：可組出八種形狀——
   `~/.codex` 不存在／是普通檔／是目錄（空）／`hooks.json` 是普通檔（別人的合法 JSON）／
   `hooks.json` 是目錄／`hooks.json` 是 **symlink 指向同目錄的 `config.toml`**／
   `hooks.json` 是斷鏈 symlink／`hooks.json` 是 **5 MB 的垃圾**（> 64 KiB，驗 spec D-q 不讀它）；
   外加一種「`~/.codex` 自己是指到 fixture 之外的 symlink」（比照既有 `ClaudeHomeSkillsSymlinkFixture`）。
   每種都植入一個內容已知的 `config.toml`，供「位元組完全不變」的斷言使用。
3. **對抗式 payload fixture**（不進 `Fixtures/`，用程式合成）：缺 `permission_mode`／缺 `model`／
   `tool_response` 是 200 KB 字串／`hook_event_name: "Interrupt"` **帶** `agent_id`／
   `session_id` 是 UUIDv7（`isSafeSessionID` 必須放行）。
4. **argv 對抗式表（7 格）**：`[]`、`["--agent"]`、`["--agent","gemini"]`、`["--agent","CODEX"]`、
   `["--agent=codex"]`、`["--agent","codex","--agent","claude"]`、`["--agent","codex","--agent"]`。
   每一格的期望值寫死在表裡，**不是從實作反推**。
   **這張表是 CX7（純函式）與 CX8（真 spawn）共用的唯一來源**（review M12），
   放在共用 helper 裡，兩條 gate 都迭代它，不各寫一份。
5. **`FakeCodexInstaller`**：① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
   ② `disconnect()` 宣稱成功但檔案還在；③ `probe()` 丟錯。
   **`FakeCodexStore`**：可設定「寫進去與讀回來不一致」（比照既有 `FakeLoginItem.isEnabled`）——
   R-2 之後它守的是「store 壞掉時我們不會誤刪別人的檔」，不再與 digest 有關。
6. **round4 fixture 覆蓋測試骨架**（CX13）：18 筆逐筆解析；**期望值來自探針文件的欄位表**，
   不是從 `HookPayload` 現有行為反推。外加反向斷言：探針表列出的每個欄位至少出現一次
   （否則 fixture 自己縮水了也看不出來）。
7. **composition-root smoke 骨架**：`SpyRenderer` 不必動（`onAction` 已是單一入口）；
   新增 `CodexWiringSmokeTests` 的**五段**骨架（§6.2／CX24），每段獨立失敗訊息——
   第五段（`probe()` 呼叫次數）需要 `FakeCodexInstaller` 記錄呼叫次數，這裡一併備好。
8. **像素 harness 沿用**：`renderPinned` ＋ `differingPixels`（既有）；CX22／CX23 用它們，
   不准各測試自己決定 appearance。

**驗收**：`swift test` 全跑得完（不掛住），新增測試全 RED，逐條說明 RED 的理由。
**外加一條非測試驗收**：`grep -rn "codex exec" Tests/ scripts/` 為零（CX30 的人工預跑）。

---

## T02 `Agent` ＋ `AgentArgument`

**目標**：§3 的 `Agent`（含 `init(stored:)`／`storedRawValue`／`label`）與 §4.1 的 argv 解析，純函式、零 I/O。

- `Agent` 對 `Language` 那種「不給預設值」的紀律**不適用**——這裡的安全預設就是 `.claude`（D-b），
  而且它是**保守失敗**（少一個標籤 vs 標錯），doc comment 要寫明這個不對稱。
- `storedRawValue` 對 `.claude` 回 `nil`（D-c）——這是 CX9「Claude 狀態檔位元組不變」的單一機制。
- `AgentArgument.agent(from:)` 支援 `--agent <值>` 與 `--agent=<值>`；由左至右取**第一個**匹配；
  大小寫敏感；任何不匹配一律 `.claude`。
- `label` 對 `.codex` 回 `"Codex"`——**產品名不進 L10n**（兩個語言都叫 Codex），
  doc comment 要寫明這是刻意的、不是漏搬。

**gates**：CX7（`agentArgumentParsing`，定義域＝T01 的 7 格共用表，逐格）。

**mutation**：① 未知值改成回 `.codex` → CX7 紅；② `storedRawValue` 對 `.claude` 改成回 `"claude"` →
CX9 紅（T05 之後才觀測得到，本 task 先記在報告裡，T05 完成時補跑）。

---

## T03 `codexEvents` ＋ `Interrupt` 映射（本 change 最容易踩的接縫）

**目標**：§4.2 全部。**先讀 spec §4.2 再動手**——這個 task 有一個會讓產品對 Claude 使用者
完全停止運作的錯誤選項（把 `Interrupt` 加進 `handledEvents`），而那個錯誤選項看起來像是「把對照表補齊」。

- `EventMapping.codexEvents`：12 個字面名（F2）。doc comment 要**分標兩種證據強度**（review m5）：
  六個有 `round4-codex.ndjson` 的真實 payload（`SessionStart`／`UserPromptSubmit`／`PreToolUse`／
  `PostToolUse`／`Stop`／`SessionEnd`），另六個只有二進位字串 `HookEventsToml` 列舉這一層證據
  （`PermissionRequest`／`Interrupt`／`SubagentStart`／`SubagentStop`／`PreCompact`／`PostCompact`）。
  不分標的話，下一個人會以為 12 個都跑過真實 session。
- `EventMapping.codexOnlyEvents = ["Interrupt"]`。
- `effect` 的 switch 加 `case "Interrupt": return .setActivity(.idle)`（L3）。
  doc comment 必須點名：**`Interrupt` 事件 ≠ `is_interrupt` 欄位**（review m2）——後者是
  `HookPayload.isInterrupt`（使用者 Ctrl+C 中斷了一個 tool，刻意不計入 `tool_failures`），
  兩者語意／來源／處置都不同。`HookPayload.isInterrupt` 的 doc comment 也加一句反向指回來。
- **`handledEvents` 一個字都不准動**；只加 doc comment 說明它是 Claude 側的來源集合，
  以及為什麼 `Interrupt` 不能進來。

**gates**：CX1、**CX2**（`interruptNeverEntersHandledEvents`，失敗訊息要逐字寫出「Claude Code 對
hooks.json 是全有全無解析，多一個它不認識的事件名 → 整份 `Failed to load`」）、CX3、
**CX4**（`codexOnlyEventsMapToIdle`——定義域**從 `codexOnlyEvents` 推導**，不寫 `"Interrupt"` 字面；
這是 `Interrupt → idle` 唯一的守衛，fixture 零筆 `Interrupt`）、CX5。

**mutation**：① 把 `Interrupt` 加進 `handledEvents` → CX2 紅（**且**既有
`registeredEventsMatchHandledEvents` 也必須紅——兩條都要記，這證明 CX2 不是多餘的，
它在「有人同時改兩邊」時是唯一還活著的那條）；② 從 `handledEvents` 拿掉 `PreCompact` → CX3 紅；
③ **刪掉 `case "Interrupt"` 整行 → CX4 紅**（改之前先確認：不加 CX4 的話這個 mutation 全綠——
報告要把「加 CX4 之前全綠／加之後變紅」兩次結果都寫上，這是 review r1 B2 的直接回歸證人）；
④ 在 `plugin/hooks/hooks.json` 加 `Interrupt` → CX5 紅；⑤ `codexEvents` 少一個 → CX1 紅。

---

## T04 `CodexHooksJSON` 產生器（逐字 F14）

**目標**：§4.3。純函式、住 AuraCore、只 import Foundation。

- 輸出**逐字**照 F14：最外層 `hooks` 物件；每個事件的值是
  `[ { "matcher": "", "hooks": [ { "type": "command", "command": "<abs> --agent codex", "timeout": 5 } ] } ]`。
  **一個鍵不多、一個鍵不少**：`matcher` 不可省、`timeout: 5` 照寫、**不加 `async`**。
  三個「未測」欄的項目（省略 `matcher`／`async` 是否被接受／省略 `timeout` 的預設值）**一項都不碰**。
- 事件鍵從 `EventMapping.codexEvents` **排序後推導**，不寫第二份清單。
- `command` **不加引號**（F14 驗證過的是裸路徑）；Claude 側那份加引號是 Claude 的慣例，兩份互不相干。
  路徑含空白／引號的行為未測 → spec §10-10、實機 ⑦。
- doc comment 要逐鍵寫出處（哪個鍵來自 F14 的哪一行、哪個是「未測所以不加」），
  否則下一個人會「順手補上 `async`」。
- `snippet(hookBinaryPath:)`：給 `.occupiedByOther` 複製用，**內容就是 `json(...)` 的文字形式**
  （同一個產生器，不是另外手寫一份示意——否則使用者貼上的跟我們自己寫的會漂移）。

**gates**：CX6（`codexHooksJSONMatchesF14Verbatim`：① `hooks` 鍵集合 == `codexEvents`；
② 任取一個事件，**整個 entry 逐字等於 F14**（含 `matcher: ""`、`timeout: 5`，且**沒有** `async`）；
③ 含空白／`"`／`\` 的路徑產出仍是合法 JSON 且 `command` 解析回原字串）。

**mutation**：① 產生器寫死 11 個事件 → CX6① 紅；② **拿掉 `matcher`** → CX6② 紅；
③ **加上 `"async": true`** → CX6② 紅；④ `command` 漏掉 `--agent codex` → CX6② 紅；
⑤ 路徑不跳脫直接拼字串（用含 `"` 的路徑）→ CX6③ 紅。

---

## T05 `agent` 貫穿四段 ＋ `aura-hook` 接線

**目標**：payload → 檔案 → state → UI 四段都走完（`SessionState.model` 與 `toolDescription`
各自都曾經只走完兩段就以為做完了——`SessionState.swift` 的 doc comment 逐字記著這兩次）。

- `SessionSnapshot.agent: String?`（CodingKey `agent`），doc comment 逐字引用
  `outstandingSubagents` 那段「必須是 Optional」的理由。
- `MergeRules.merge(_:into:pid:pidStartedAt:agent:now:)`——**`agent` 不給預設值**（7 個呼叫點，
  測試一律傳 `.claude`）。寫入規則：`s.agent = agent.storedRawValue ?? s.agent`
  （carry-forward，比照 `cwd`／`model` 的既有形狀）。
- `SessionReducer.state(from:liveness:)` → `SessionState.agent: Agent`（`Agent(stored: s.agent)`）。
- `PanelViewModel.row` → `PanelRow.agentLabel: String?`（= `s.agent.label`）。
- `aura-hook/main.swift`：`let agent = AgentArgument.agent(from: CommandLine.arguments)`，
  傳進 `merge`。**不得新增任何 stdout／stderr 輸出、不得有非零 exit 路徑**。
- **liveness 不改**（spec §4.7）：`getppid()` 照舊。F15 已確認 Codex 的 hook 父行程與 session
  同壽命（五個 session、24 筆事件，session 內 `$PPID` 恆定），所以判活成立。
  `main.swift` 的既有註解（「若判定父行程是 shell 而非 claude，改為不寫 pid」）要補一句引 F15，
  並指向 spec §4.7 的 fallback 決策點。**本 task 不實作 fallback。**

**gates**：CX8（**7 格共用表**真 spawn，`SpawnGate` 內序列跑：每格 exit 0、stdout 空、stderr 空）、
CX9（`claudeStateFileHasNoAgentKey`：用 round1／round1b／round2／round3 跑完 merge，
序列化後的 JSON **不含** `agent` 鍵）、CX10（真 spawn `--agent codex` → 檔案含 `"agent":"codex"`，
經 `SessionReducer` 後 `.codex`）、CX11、CX12、CX13。

**mutation**：① `main.swift` 忘了把 agent 傳進 merge → CX10 紅；② `storedRawValue` 對 `.claude`
回 `"claude"` → CX9 紅（補跑 T02 的 mutation ②）；③ `SessionSnapshot.agent` 改成非 Optional → CX11 紅；
④ 把 `agent` 改成 `Agent?`（enum）讓未知值整包解碼失敗 → CX12 紅；
⑤ **`effect` 對 `Stop` 改成 `.noChange` → CX13 紅**（fixture 有 4 筆 `Stop`，真的踩得到；
r1 原本寫的 `Interrupt` mutation 物理上不可能紅，那條改由 T03 的 CX4 負責）。

**注意**：CX8／CX10 要真的 spawn `aura-hook`，**必須經 `SpawnGate`**（既有 T10b 的 flake 防線）。
`Tests/AuraCoreTests/MergeRulesTests.swift` 目前 294 行，加一個參數還有 6 行餘裕；超了就拆檔。

---

## T06 `CodexInstaller`

**目標**：§4.4 全部。**獨立型別、獨立檔**，不塞進既有 `Installer`（157 行）或 `Installer+Connect`（125 行）。

- `Sendable`；**欄位只有兩個 `URL`**（`codexHome`／`hookBinaryURL`）——R-2 之後沒有 digest 注入縫。
  **`Sources/AuraHookFile/` 不得出現 `UserDefaults(`／`UserDefaults.`**（既有
  `HookVerificationStoreSourceScanTests` 會抓）。
- `probe()`：`lstat` → `entryType`；只有 `regularFile` **且 ≤ 64 KiB**（D-q）才
  `open(..., O_RDONLY | O_NOFOLLOW)` 讀內容。超過 64 KiB 不讀（`contents = nil` → `.occupiedByOther`）。
- `connect(json:)`：`open(path, O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC, 0o644)`（**這一行是保本動作，
  不准改成先 stat 再寫**）→ 寫 → close → 回傳寫出去的 `Data`。
  `codexHome` 不是目錄先 throw `.codexHomeMissing`，**不建立它**。
  **`EEXIST` 一律路由到 `.alreadyExists`**——reviewer 實測四種佔用形狀（普通檔／目錄／
  symlink 指向 `config.toml`／斷鏈 symlink）**全部**回 `EEXIST`，沒有任何一種回 `EISDIR`；
  把目錄那格寫成 `.writeFailed(EISDIR)` 會讓 UI 給錯訊息（review m1）。
- `disconnect(ifContentsEqual:)`：`O_RDONLY|O_NOFOLLOW` → `fstat` 確認 `S_IFREG` → 讀 →
  **逐位元組比對** → 不符 throw `.notOurs`（不刪）→ 相符 → **`unlink` 前再 `lstat` 一次路徑，
  比對 `fstat` 拿到的 `(dev, ino)`，不同就放棄不刪**（review m4）→ `unlink`。
  absent 視為已斷開、冪等成功。

**gates**：
- **CX14**（最重要）：connect＋disconnect 前後對 `codexHome` 整棵樹取 `DirectoryTreeSnapshot`，
  差異集合**恰為** `{hooks.json}`；植入的 `config.toml` 元組（含位元組）完全不變。
- **CX15**（對抗式）：T01 的佔用形狀各自 throw `.alreadyExists`，**且該路徑與 symlink 指向的
  目標位元組／型別完全不變**。「`hooks.json` 是 symlink 指向 `config.toml`」那一格是這條 gate
  的核心——它是唯一能區分 `O_EXCL` 與「先 stat 再寫」的輸入。
- CX16（成功路徑：檔案內容 == 產生器位元組；回傳值 == 那些位元組）。
- CX17（逐位元組相符才刪；改一個 byte → 不刪＋throw；`ifContentsEqual` 為 nil → 不刪；
  `(dev,ino)` 在 unlink 前被換掉 → 不刪）。
- CX18（`~/.codex` 是外部 symlink：字面樹不變、`realpath` 樹差異恰為 `{hooks.json}`）。

**mutation**：① `connect` 順手寫 `hooks.json.bak` → CX14 紅；② 拿掉 `O_EXCL`（改成
`O_CREAT|O_WRONLY|O_TRUNC`）→ **CX15 的 symlink→`config.toml` 那格必須紅**（其餘格可能仍綠，
報告要寫明是哪一格紅的）；③ 拿掉內容比對 → CX17 紅；④ 快照改用字面路徑（不解 `realpath`）
→ CX18 紅；⑤ `connect` 少寫最後一個 byte → CX16 紅；⑥ 拿掉 unlink 前的 `(dev,ino)` 複查 →
CX17 的該段紅。

---

## T07 `CodexState` ＋ `PanelAction` ＋ `OptionsMenuModel`

**第一步（純搬移，獨立 commit）**：`Tests/AuraCoreTests/OptionsMenuModelTests.swift`
**目前恰好 300 行**（＝測試檔上限），而本 task 要在這裡加 CX20／CX21 與 `rows(` 的新參數。
先把既有的 codex 無關測試中可獨立的一組（或把新增的 codex 測試）落在新檔
`Tests/AuraCoreTests/CodexOptionsRowTests.swift`。
**零行為變更**：搬完 `swift test` 全綠、`#expect` 總數不變、被搬動的測試函式名一字不改。

**第二步**：
- `CodexState.from(_:recordedContents:)` 對 `EntryType` **窮盡 switch**、無 `default`。
- `PanelAction` 加 `.connectCodex`／`.disconnectCodex`／`.copyCodexSnippet`，
  同步補 `kind`（窮盡 switch）與 `samples`。
- `OptionsMenuModel.rows(...)` 多吃 `codex: CodexState`（**不給預設值**，比照 `PanelModel.make`
  的既有紀律——這裡猜錯的後果是「沒裝 Codex 的人看到 Codex 列」）；
  `.mount` 群組在 `.notConnected`／`.connected` 各多一列，**`.unavailable` 與 `.occupiedByOther` 各零列**。
- `nonMenuKinds` 加 `.copyCodexSnippet`，**並同步改 `Sources/AuraCore/OptionsMenuModel.swift`
  的 doc comment**（它逐字寫著「字面集合恰為這四個」，review m6）。

**fan-out（review M2，r1 漏算的第三條）**：`OptionsMenuModel.rows(` 實測 **26 處、跨 10 個檔**，
其中含 `L10nProductionCallSitesPassLanguageTests`（一條來源掃描 gate）與
`HelpDocOptionsRowCoverageTests`。測試呼叫點一律傳 `codex: .unavailable`。

**gates**：CX19（`codexStateCoversEveryObservationShape`：定義域由
`EntryType.allCases × {contents 三態} × codexHomeIsDirectory` **推導**，不寫「10 格」這種數字）、
CX20（**`.unavailable` 與 `.occupiedByOther` 各零列；`.notConnected`／`.connected` 各恰一列**）、
CX21（既有 `optionsRowsCoverEveryAction` 擴充：代表狀態集合加 `CodexState.allCases`；
既有 `nonMenuKindsIsExactlyThatLiteralSet` 四個 → 五個）。

**test-edit scrutiny**：`nonMenuKindsIsExactlyThatLiteralSet` 的修改要在報告裡列
「改前四個／改後五個／為什麼 `.copyCodexSnippet` 屬於非選單」（spec D-k）——
**這是契約變更不是弱化**，判準是「集合仍然是恰好等於，只是多了一個有理由的成員」；
生產碼註解的同步修改也要列進去。

**mutation**：① 把 `symlink` 併進 `.notConnected` → CX19 紅；② `.unavailable` 也給「接上 Codex」
→ CX20 紅；③ `.occupiedByOther` 給一列 → CX20 紅；④ 把 `.connectCodex` 塞進 `nonMenuKinds` → CX21 紅。

---

## T08 `PanelModel` 欄位 ＋ 呼叫點機械更新

**目標**：`PanelModel` 加 `codex: CodexState` 與 `codexSnippet: String?`；
`PanelRow` 加 `agentLabel`（T05 已做則只驗）；`make(...)` 新參數**不給預設值**
（既有 `panelModelMakeHasNoDefaults` 守）。

- **61 個 `PanelModel.make(` 呼叫點、26 個檔**（改動前實測值；動工時先重新數一次並記在報告裡）。
  測試呼叫點一律傳 `codex: .unavailable`、`codexSnippet: nil`（＝現況行為）；
  生產呼叫點（`AppDelegate+PanelActions.refreshPanel`／`StatusItemController`）傳真實狀態。
- 改完 `wc -l` 檢查那 26 個檔沒有任何一個越過 300 行（`PanelPixelTests` 275、
  `Phase2EvidenceRenderer` 194 且有 15 個呼叫點——這兩個最接近）。
- `Tests/AuraCoreTests/PanelViewModelTests.swift` 目前 288 行，CX22 的 model 半若寫不下，
  放到 `CodexRowLabelPixelTests` 去（不要刪既有註解騰空間）。

**gates**：既有 `panelModelMakeHasNoDefaults` 必須繼續綠；CX22 的 model 半
（`agentLabelOnlyForNonClaude`：claude → nil、codex → `"Codex"`）。

**test-edit scrutiny**：`#expect` 淨數量**不得下降**；不得有任何既有斷言因為「加了參數」
被改成更弱的形式。報告要附改前／改後的 `#expect` 總數（基準 1652）。

**mutation**：① `make` 忽略傳進來的 `codex`（固定用 `.unavailable`）→ 由 T09／T10 的渲染與
smoke gate 抓（本 task 先記，後續補跑）；② `agentLabel` 對 `.claude` 也給值 → CX22 紅。

---

## T09 View 層 ＋ `L10nCodex`

**目標**：列標籤（D-l）、`CodexSectionView`、snippet 複製入口、雙語字串。

- **所有新的中文字面必須住在 `Sources/AuraCore/L10nCodex.swift`**（`noStrayLiteralOutsideAllowlist`
  是真正生效的 gate，`pendingMigrationFiles` 已清空），並登記進 `L10nRegistry.allEntries`
  （`L10nRegistryCoverageSourceScanTests` 會抓漏登記）。產品名「Codex」走 `Agent.label`，不進字串表。
- **列標籤放在既有的第一行 `HStack`（`projectName` ＋ `meta` 那個）**，不另起一行（D-l）。
- `CodexSectionView`：
  - `.notConnected` → **單行提示 ＋ 按鈕，一律如此**（R-3）。**不看 Claude 的安裝狀態**，
    所以這個 view **不吃 `InstallState`**（r1 的條件式降級三處敘述互相矛盾，已裁決取消）。
  - `.occupiedByOther` → 說明 ＋ 可選取 snippet（`.textSelection(.enabled)`）＋「複製」按鈕。
  - `.unavailable`／`.connected` → 不畫。
  按鈕**必須用 `.borderless`**（離屏渲染下 `.bordered` 會被包進 `_FocusRingView` 而走訪不到，
  CLAUDE.md gate 哲學 §5）。
- 新增按鈕會動到既有離屏測試的**位置索引斷言**（離屏讀不到 `.title` 也讀不到
  `.accessibilityIdentifier`）——改完要逐一檢查 `FooterPixelTests`／`OptionsExpandTests`
  有沒有靠索引定位的斷言，報告裡列出檢查結果。

**gates**：CX22 的像素半（同一列 claude vs codex，`differingPixels > 0`）、
**CX23**（`codexLabelDoesNotChangeRowHeight`：帶標籤的列高仍是 `SessionsCardSizing.compactRowHeight`
43／`tallRowHeight` 59（±0.5pt），從真實 `NSHostingView(PanelRowView(...))` 量，**不是**常數對常數）、
`CodexSectionRenderTests`（`.notConnected`／`.occupiedByOther` 各自渲得出按鈕，非白像素 > 門檻）、
既有 `RowHeightDerivationTests`／`FooterPositionStabilityTests`／`OptionsExpandTests` 繼續綠。

**mutation**：① 標籤另起一行 → CX23 紅；② `CodexSectionView` 在 `.unavailable` 也畫 →
`OptionsExpandTests` 的高度斷言紅（**這一格要特別確認**：如果它沒紅，代表「`.unavailable`
畫面零 diff」這件事沒有守衛，要補一條）；③ snippet 改成手寫字串（不走 `CodexHooksJSON.snippet`）
→ 新增一條「snippet 與產生器同源」的斷言必須紅。

---

## T10 `AppDelegate` 接線 ＋ `CodexHookStore` ＋ `Uninstaller`

**第一步（兩個純搬移，獨立 commit）**：
1. `Sources/AgentAuraApp/AppDelegate+PanelActions.swift` **目前恰好 200 行**，加任何一個 case
   都會讓 `fileLengthLimit` 紅。把 `openHelp`／`helpResourceName`／`helpURL`／`reportIssue`
   （約 45 行含註解）搬到新的 `AppDelegate+Links.swift`。
2. `Tests/AgentAuraAppTests/AppDelegatePanelActionsWiredTests.swift` **目前恰好 300 行**，
   而 `panelActionsAreWired` 要涵蓋三個新 kind。新增 `AppDelegateCodexWiredTests.swift` 承接
   codex 相關的接線斷言。
**兩者都零行為變更**：搬完 `swift test` 必須全綠、`#expect` 總數不變、
既有 `HelpResourceNameTests` 一個字都不用改（若要改，代表搬移不純，停下來重做）。

**第二步**：
- `CodexHookStore`（App，`@MainActor` ＋ 注入 `UserDefaults`，比照 `HookVerificationStore`）：
  key `AgentAuraCodexHookContents`，值＝寫出去的 JSON 文字。`contents`／`write(_:)`／`clear()`。
  **不算 hash**（R-2）。
- `AppDelegate+Codex.swift`：`codexInstaller`／`codexStore`／`codexState` 欄位；
  `reprobeCodex()`／`performConnectCodex()`／`performDisconnectCodex()`／`performCopyCodexSnippet()`。
  生產預設 `codexHome` = `FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(".codex")`（**不得用 `environment["HOME"]`**——`homeDirectoryForCurrentUser`
  讀密碼資料庫、不吃 `$HOME`，用環境變數算會在生產與測試給出不同答案）。
- **`reprobeCodex()` 的四個呼叫時機（spec §4.6；漏接＝功能 tested≠wired）**：
  ① `applicationDidFinishLaunching` 同步區，第一次 `refreshPanel()` **之前**；
  ② popover `onOpen`（使用者可能在 app 開著的期間才裝 Codex）；
  ③ `performConnectCodex()` 之後；④ `performDisconnectCodex()` 之後。
  `refreshPanel(icon:)` 把 `codex: codexState`、`codexSnippet:` 一併帶進 `PanelModel.make`。
- 剪貼簿走注入縫 `writeToPasteboard: @MainActor (String) -> Void`（測試不碰真剪貼簿，
  比照 `openURL`／`confirmDisconnect` 的既有慣例）。
- 接上成功的 banner 必須**同時**含「下一個 Codex session 起生效」與「Codex 會問你信任」兩句（D-m）。
- `Uninstaller.run()` 在 `erasePersistentDomain()` **之前**多一步
  `codexInstaller.disconnect(ifContentsEqual: store.contents)`（`try?`，D-n）。

**gates**：**CX24**（`codexConnectChainIsWired`，五段各自獨立失敗訊息：① action 有接線
② fake installer 真的收到 `connect` ③ 內容真的進注入的 suite ④ banner 文字含兩個關鍵詞
（**從 `L10nCodex` 的鍵推導，不寫死字面**）⑤ **spy 記 `probe()` 次數，`onOpen` 之後 ≥ 1**）、
CX25（`productionCodexHomeIsRealHome` ＋ 來源掃描 `Sources/` 不得用 `environment["HOME"]` 算它）、
CX26（`uninstallRemovesCodexBeforeErasingDefaults`：Fake 記錄呼叫順序）、
既有 `panelActionsAreWired`（`PanelActionKind.allCases.flatMap(samples)` 逐一送）必須涵蓋三個新 kind。

**mutation**：① 刪 `.connectCodex` 分支的 body（改 `break`）→ CX24① 紅；
② banner 只留一句 → CX24④ 紅；③ **拿掉 `onOpen` 裡的 `reprobeCodex()` → CX24⑤ 紅**
（這是 review M4 的直接回歸證人：沒有它，使用者裝了 Codex 要重開 app 才看得到，而全套綠）；
④ `codexHome` 改成 `environment["HOME"]` → CX25 紅；⑤ codex disconnect 與
`erasePersistentDomain` 兩步對調 → CX26 紅。

---

## T11 scripts ／ 文件 ／ 正典回寫

- `scripts/verify-uninstall.sh`：
  - 新增第 7 項（`${CODEX_HOME:-$HOME/.codex}/hooks.json` 存在**且**含 `--agent codex` → FAIL；
    存在但不含 → PASS；不存在 → PASS）。
  - **必須可以單獨執行第 7 項**：加 `--only <n>`（或把每一項抽成可 `source` 的函式）。
    理由：第 1–6 項查的是**真實** `$HOME`，在一台裝著 AgentAura 的開發機上本來就會 FAIL、
    整支腳本本來就非零退出——用整體 exit code 當 gate 判準，mutation「拿掉第 7 項」不會紅；
    而且從測試呼叫整支會跑 `osascript`（權限提示）與 `sfltool dumpbtm`（腳本自己註解寫實測 39 秒、
    watchdog 90 秒），與 DoD「連跑 3 次 0 flake」正面衝突（review M9）。
  - `CODEX_HOME` 覆寫存在的唯一理由是讓這一項可被測試，**不是給使用者的介面**，註解要寫明。
  - **順手修腳本第 2 行的註解**：現在寫「D-1 五個殘留位置」，實際已有六項，加第七項時一併改正。
  - 既有六項的文字不得變（diff 要看得出只是加了一項＋一個旗標）。
- `docs/INSTALL.md` ＋ `.zh-TW`：新增「Using it with Codex」一節——前提（有 `~/.codex`）、
  按哪裡、**Codex 會問你一次信任**、生效時機（下一個 Codex session）、怎麼移除、
  以及 troubleshooting 第一條「燈不動？先確認 Codex 有沒有問過你信任」。
- `README.md` ＋ `.zh-TW`：「What it does to your Mac」加 `~/.codex/hooks.json`
  （只在你按下按鈕時建立、只在內容仍是我們寫的那份時刪除、`config.toml` 從不碰）。
- `SECURITY.md`：「What this tool can do on your machine」加同一條；
  「Boundaries that are enforced by tests」加「`~/.codex/config.toml` 位元組不變、
  差異集合恰為 `{hooks.json}`」。
  **注意**：`SECURITY.md` 沒有叫「What it does to your Mac」的段落（那是 `README.md:160`）。
- `Resources/help-english.html` ＋ `help-traditionalChinese.html`：新增 Codex 段
  （CX28 會強制涵蓋**每一個**新的 Options 列標題）。
- `CLAUDE.md`：Project 狀態、Invariants（兩條，見 spec §8.2）、Tier 1 清單（三個檔）。
- 正典 `docs/superpowers/specs/2026-09-08-agentaura-design.md`：§2.1／§2.2／§3.2／§3.5／§3.7／§9
  六處回寫（逐句對照表在 spec §8.2；§3.5 是 F15 的 liveness 那句）。

**gates**：CX27（`verifyUninstallScriptDetectsOurCodexHooks`：暫存 `CODEX_HOME` ＋ `--only 7` 跑兩次，
**判準是該項那一行的 PASS/FAIL，不是整體 exit code**）、
CX28（`helpDocsCoverCodexRows`：既有 `HelpDocOptionsRowCoverageTests.allRows` 改成
**對 `CodexState.allCases` 取聯集**（型別推導，不寫數字），兩個語言各自守）、
CX29（`securityDocListsEveryPathWeWrite`）、CX30（`noCodexExecInRepo`）。

**mutation**：① 拿掉腳本第 7 項 → CX27 紅；② **只刪掉其中一個 Codex 列標題**（例如只刪
「移除 Codex 掛載」）→ CX28 必須紅（review M5：單一代表狀態只守得到兩列中的一列）；
③ 從 SECURITY.md 刪掉 `.codex/hooks.json` 那一行 → CX29 紅；④ 在腳本裡加一行 `codex exec` → CX30 紅。

---

## T12 整合 ＋ DoD

跑 DoD 帳本全表（`docs/superpowers/plans/2026-09-18-codex-support-dod.md`）：
`swift test` 全綠且連跑 3 次 0 flake、gate mutation 帳（**30 條**，抽驗 3 筆現場重跑）、
`Sources/` 淨增、單檔行數、執行檔增量、`CodexInstaller.probe()` 成本、啟動時間增幅、
`claude plugin validate --strict`、`verify-install.sh`、`verify-uninstall.sh`、
**`plugin/hooks/hooks.json` 的 git diff 必須為空**、`~/.codex/config.toml` 自動化側位元組不變。
產出實機清單 ①–⑦ 給使用者。Tier 1 → integrator 綠後派 persona-tester。

---

## 2. 已知風險（開工前就知道，不是驚喜）

1. **`Interrupt` 進 `handledEvents` 會讓 Claude 側整份 hooks 靜默失效**——爆炸半徑是整個產品對
   Claude 使用者停止運作，而症狀是「什麼都沒發生」。T03 的 CX2／CX5 是唯一的守衛。
2. **`Interrupt → idle` 本身沒有天然的 fixture 證人**（round4 零筆），CX4 是唯一守衛；
   T03 的 mutation ③ 要把「加 CX4 之前全綠」也記下來，否則後人看不出它為什麼存在。
3. `~/.codex/hooks.json` 是 symlink 指向 `config.toml` 時，「先 stat 再寫」會覆蓋使用者的設定。
   T06 的 `O_EXCL` ＋ CX15 那一格 fixture 是唯一能區分正確與錯誤實作的輸入。
4. **產生器一旦偏離 F14，Codex 根本不會載入，而自動化抓不到**（F12：不准跑 `codex exec`）。
   T04 逐字照 F14、CX6 逐字比對 entry；F14 的三個「未測」項一項都不碰。
5. **`reprobeCodex()` 漏接會讓功能 tested≠wired**：裝了 Codex 卻要重開 app 才看得到，而全套綠。
   T10 的四個呼叫時機 ＋ CX24⑤。
6. **94 個呼叫點的機械改動**（`make` 61／`rows` 26／`merge` 7）最容易夾帶弱化（T07／T08 的 scrutiny）。
7. **三個檔已經在上限**（`AppDelegate+PanelActions.swift` 200、`OptionsMenuModelTests.swift` 300、
   `AppDelegatePanelActionsWiredTests.swift` 300）——沒先拆就動它們，implementer 最省事的動作
   是刪註解擠進去，那是在拆掉別人留下的理由。
8. Codex 端到端只有實機能驗；報告與 spec 都不得用「已實測」描述它。
