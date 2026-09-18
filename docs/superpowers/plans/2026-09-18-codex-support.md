# `codex-support` 實作計畫

> spec：`docs/superpowers/specs/2026-09-18-codex-support-design.md`（**r1**）
> 證據：`docs/2026-09-18-codex-hook-probe.md`（F1–F13）——**任何關於 Codex 行為的斷言都要指得回 F 編號**
> 分支：`change/codex-support`　Tier：**1**（動 `Sources/AgentAuraApp/**` → integrator 綠後派 persona-tester）
> 節號引用一律指 r1 的 spec。

## 0. 給每個 implementer 的共同規則

- **一 task 一 commit**（必要時 refactor 拆第二個，但屬同一 task）。動工前 `git branch --show-current`
  確認不在 `main`——**而且要在 commit 前再確認一次**（多 agent 併行時 branch 會在腳下被換掉）。
- **TDD**：先 RED（理由要正確——不是編譯錯，是斷言失敗或型別還不存在），再 GREEN，再 refactor。
- **每條 gate 都要 mutation 紀錄**：把生產碼改壞（完整字串取代）→ 先確認**編譯成功** →
  指名的測試必須在 **≤ 60s 內變紅（不是掛住）** → 還原。紀錄寫進完成報告：`mutation / 指名測試 / 秒數`。
- **單檔上限**：`Sources/` 200 行、`Tests/` 300 行（`IsolationTests.fileLengthLimit` 從磁碟推導）。
  **`Sources/AgentAuraApp/AppDelegate+PanelActions.swift` 目前恰好 200 行**——碰它之前先看 T10。
- **swift-testing**（`import Testing` / `@Test` / `#expect`），不是 XCTest。
- **禁止**：`--amend` 已 push 的 commit、`--no-verify`、`git reset --hard|checkout .|clean -f`、
  `fatalError`（會殺掉 `swiftpm-testing-helper`）、在測試裡碰真的 `~/.codex`／`~/.claude`、
  **在任何地方跑 `codex exec`**（F12：它會寫 `[projects."<cwd>"] trust_level` 進使用者的 `config.toml`）。
- **既有測試不得弱化**：`#expect` 淨數量不得下降；改寫既有斷言要在報告裡逐條列
  「改前／改後／測的還是不是同一件事」（spec §6.4 已預告五處）。
- **Claude 側零回歸是紅線**：`plugin/hooks/hooks.json` 的 git diff 必須為空；
  `EventMapping.handledEvents` 一個字都不准動。
- 中文 commit message 用 `git commit -F - <<'EOF'`，不要 `-m`（zsh 的 history expansion 會吃掉 `!`）。

## 1. 任務與依賴

| # | Task | 產出 | 依賴 | gates |
|---|---|---|---|---|
| T01 | 測試底座（**零生產碼**） | 對抗式 double、fixture 覆蓋、`DirectoryTreeSnapshot` 抽取、smoke 骨架 | round4 fixture 就位 | 全部 RED 且理由正確 |
| T02 | `Agent` ＋ `AgentArgument`（AuraCore 純函式） | §3、§4.1 | T01 | G6 |
| T03 | `codexEvents` ＋ `Interrupt` 映射（**接縫**） | §4.2 | T01 | G1、G2、G3、G5 |
| T04 | `CodexHooksJSON` 產生器（AuraCore 純函式） | §4.3 | T03 | G4 |
| T05 | `agent` 貫穿四段 ＋ `aura-hook` 接線 | §3、§4.1 | T02 | G7、G8、G9、G10、G11、G12 |
| T06 | `CodexInstaller`（AuraHookFile） | §4.4 | T04 | G13、G14、G15、G16、G17 |
| T07 | `CodexState` ＋ `PanelAction` ＋ `OptionsMenuModel` | §3、§4.6 | T06 | G18、G19、G20 |
| T08 | `PanelModel` 欄位 ＋ 61 個呼叫點（機械） | §4.6 | T07 | G21（model 半） |
| T09 | View 層 ＋ `L10nCodex` | §4.6 | T08 | G21（像素半）、G22 |
| T10 | `AppDelegate` 接線 ＋ `CodexHookStore` ＋ `Uninstaller` | §4.5、§6.2 | T06、T09 | G23、G24、G25 |
| T11 | scripts ／ 文件 ／ 正典回寫 | §8.2 | T07 | G26、G27、G28、G29 |
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

### 前置條件

`Tests/AuraCoreTests/Fixtures/round4-codex.ndjson`（18 筆真實 Codex payload，已去識別化）
由主 session 提供。**T01 在它就位之前不准開工**——沒有它，T01 的 fixture 覆蓋測試會變成
「對著自己捏的資料測自己」，那正是 gates-share-one-eye 的起點。

---

## T01 測試底座（零生產碼）

**目標**：讓後面每一條 gate 都不可能生下來就是綠的。**這個 task 不寫任何生產碼**，
交付時全部測試是 RED，且每條 RED 的理由必須是「斷言失敗」或「型別還不存在」，不能是「harness 自己壞了」。

1. **`DirectoryTreeSnapshot` 抽取（純重構，先做）**：把 `Tests/AuraCoreTests/Support/
   ClaudeHomeTreeSnapshot.swift` 的 `walk`／`entry`／`changedPaths` 抽成通用
   `DirectoryTreeSnapshot`，`ClaudeHomeTreeSnapshot` 變成它的 skills-realpath 特化。
   **驗收**：既有 `InstallerPathScopeTests` 兩條全綠，且**當場重跑一次 G2 的 mutation**
   （`connect` 順手寫 `settings.json.bak`）確認仍然精準紅——抽取機制沒有讓既有 gate 變鈍。
2. **Codex 檔案系統 fixture**（`CodexHomeFixture`）：可組出七種 `~/.codex` 形狀——
   不存在／是普通檔／是目錄（空）／`hooks.json` 是普通檔（別人的合法 JSON）／`hooks.json` 是目錄／
   `hooks.json` 是 **symlink 指向同目錄的 `config.toml`**／`hooks.json` 是斷鏈 symlink；
   外加一種「`~/.codex` 自己是指到 fixture 之外的 symlink」（比照既有 `ClaudeHomeSkillsSymlinkFixture`）。
   每種都植入一個內容已知的 `config.toml`，供「位元組完全不變」的斷言使用。
3. **對抗式 payload fixture**（不進 `Fixtures/`，用程式合成）：缺 `permission_mode`／缺 `model`／
   `tool_response` 是 200 KB 字串／`hook_event_name: "Interrupt"` **帶** `agent_id`／
   `session_id` 是 UUIDv7。
4. **argv 對抗式表**（G6 的定義域）：`[]`、`["--agent"]`、`["--agent","gemini"]`、`["--agent","CODEX"]`、
   `["--agent=codex"]`、`["--agent","codex","--agent","claude"]`、`["--agent","codex","--agent"]`
   ——每一格的期望值寫死在表裡，**不是從實作反推**。
5. **`FakeCodexInstaller`**：① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
   ② `disconnect()` 宣稱成功但檔案還在；③ `probe()` 丟錯。**`FakeCodexStore`**：可設定
   「寫進去與讀回來不一致」（比照既有 `FakeLoginItem.isEnabled` 的對抗式形狀）。
6. **round4 fixture 覆蓋測試骨架**（G12）：18 筆逐筆解析；**期望值來自探針文件的欄位表**，
   不是從 `HookPayload` 現有行為反推。外加反向斷言：探針表列出的每個欄位至少出現一次
   （否則 fixture 自己縮水了也看不出來）。
7. **composition-root smoke 骨架**：`SpyRenderer` 不必動（`onAction` 已是單一入口）；
   新增 `CodexWiringSmokeTests` 的四段骨架（§6.2），每段獨立失敗訊息。
8. **像素 harness 沿用**：`renderPinned` ＋ `differingPixels`（既有）；G21／G22 用它們，
   不准各測試自己決定 appearance。

**驗收**：`swift test` 全跑得完（不掛住），新增測試全 RED，逐條說明 RED 的理由。
**外加一條非測試驗收**：`grep -rn "codex exec" Tests/ scripts/` 為零（G29 的人工預跑）。

---

## T02 `Agent` ＋ `AgentArgument`

**目標**：§3 的 `Agent`（含 `init(stored:)`／`storedRawValue`／`label`）與 §4.1 的 argv 解析，純函式、零 I/O。

- `Agent` 對 `Language` 那種「不給預設值」的紀律**不適用**——這裡的安全預設就是 `.claude`（D-b），
  而且它是**保守失敗**（少一個標籤 vs 標錯），doc comment 要寫明這個不對稱。
- `storedRawValue` 對 `.claude` 回 `nil`（D-c）——這是 G8「Claude 狀態檔位元組不變」的單一機制。
- `AgentArgument.agent(from:)` 支援 `--agent <值>` 與 `--agent=<值>`；由左至右取**第一個**匹配；
  大小寫敏感；任何不匹配一律 `.claude`。
- `label` 對 `.codex` 回 `"Codex"`——**產品名不進 L10n**（兩個語言都叫 Codex），
  但要在 doc comment 寫明這是刻意的，不是漏搬（`noStrayLiteralOutsideAllowlist` 只擋中文字面，
  這行說明是給下一個人看的）。

**gates**：G6（`agentArgumentParsing`，定義域＝T01 那張表，逐格）。

**mutation**：① 未知值改成回 `.codex` → G6 紅；② `storedRawValue` 對 `.claude` 改成回 `"claude"` →
G8 紅（T05 之後才觀測得到，本 task 先記在報告裡，T05 完成時補跑）。

---

## T03 `codexEvents` ＋ `Interrupt` 映射（本 change 最容易踩的接縫）

**目標**：§4.2 全部。**先讀 spec §4.2 再動手**——這個 task 有一個會讓產品對 Claude 使用者
完全停止運作的錯誤選項（把 `Interrupt` 加進 `handledEvents`），而那個錯誤選項看起來像是「把對照表補齊」。

- `EventMapping.codexEvents`：12 個字面名（F2），doc comment 標 F2 並寫明「這是外部量測進入程式碼的邊界，
  所以是字面集合；往下游的每一份清單都從它推導」。
- `EventMapping.codexOnlyEvents = ["Interrupt"]`。
- `effect` 的 switch 加 `case "Interrupt": return .setActivity(.idle)`（L3）。
- **`handledEvents` 一個字都不准動**；只加 doc comment 說明它是 Claude 側的來源集合，
  以及為什麼 `Interrupt` 不能進來。

**gates**：G1（`codexEventSetIsPinnedToProbe`）、**G2**（`interruptNeverEntersHandledEvents`，
失敗訊息要逐字寫出「Claude Code 對 hooks.json 是全有全無解析，多一個它不認識的事件名 → 整份
`Failed to load`」）、G3（`codexSharedEventsReuseClaudeMapping`：`codexEvents − codexOnlyEvents`
⊆ `handledEvents` 且每個 `effect` 非 `.noChange`）、G5（`claudeHooksJSONHasNoInterrupt`，
**獨立於**既有 `registeredEventsMatchHandledEvents` 的第二個觀測點）。

**mutation**：① 把 `Interrupt` 加進 `handledEvents` → G2 紅（**且**既有
`registeredEventsMatchHandledEvents` 也必須紅——兩條都要在報告裡記，這證明 G2 不是多餘的，
它在「有人同時改兩邊」時是唯一還活著的那條）；② 從 `handledEvents` 拿掉 `PreCompact` → G3 紅；
③ 在 `plugin/hooks/hooks.json` 加 `Interrupt` → G5 紅；④ `codexEvents` 少一個 → G1 紅。

---

## T04 `CodexHooksJSON` 產生器

**目標**：§4.3。純函式、住 AuraCore、只 import Foundation。

- 事件鍵從 `EventMapping.codexEvents` **排序後推導**，不寫第二份清單。
- `command` = `"\(path)" \(agentFlag)`，`agentFlag` 是 `public static let`（給 `verify-uninstall.sh`
  的 gate 反查同一個字面，G28／G26 都用它）。
- 路徑跳脫：用 `JSONSerialization`（或等價）產出，**不要自己拼字串再祈禱**——
  含空白／引號／反斜線的路徑必須 round-trip 回原值。
- `snippet(hookBinaryPath:)`：給 `.occupiedByOther` 複製用，**內容就是 `json(...)` 的文字形式**
  （同一個產生器，不是另外手寫一份示意——否則使用者貼上的跟我們自己寫的會漂移）。
- **不寫 `async`、不寫 `timeout`**（§4.3 的理由；doc comment 要寫進去，否則下一個人會「順手補上」）。

**gates**：G4（`codexHooksJSONRegistersExactlyCodexEvents`：解析回來的 `hooks` 鍵集合 == `codexEvents`；
每個 `command` == 期望字串；三種惡意路徑（含空白／含 `"`／含 `\`）都 round-trip）。

**mutation**：① 產生器改成寫死 11 個事件 → G4 紅；② `command` 漏掉 `--agent codex` → G4 紅；
③ 路徑不跳脫直接拼字串（用含 `"` 的路徑）→ G4 的 round-trip 那段紅。

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

**gates**：G7（真 spawn：三種 argv 都 exit 0、stdout 空、stderr 空）、
G8（`claudeStateFileHasNoAgentKey`：用 round1–3 fixture 跑完 merge，序列化後的 JSON **不含** `agent` 鍵）、
G9（真 spawn `--agent codex` → 檔案含 `"agent":"codex"`，經 `SessionReducer` 後 `.codex`）、
G10（無 `agent` 鍵的舊 JSON 解得開且 `.claude`）、G11（`"agent":"gemini"` → 整包解得開、`.claude`、無標籤）、
G12（round4 fixture 18 筆，T01 的骨架填實）。

**mutation**：① `main.swift` 忘了把 agent 傳進 merge → G9 紅；② `storedRawValue` 對 `.claude`
回 `"claude"` → G8 紅（補跑 T02 的 mutation ②）；③ `SessionSnapshot.agent` 改成非 Optional → G10 紅；
④ 把 `agent` 改成 `Agent?`（enum）讓未知值整包解碼失敗 → G11 紅；⑤ `effect` 對 `Interrupt`
改回 `.noChange` → G12 紅。

**注意**：G7／G9 要真的 spawn `aura-hook`，**必須經 `SpawnGate`**（既有 T10b 的 flake 防線）。

---

## T06 `CodexInstaller`

**目標**：§4.4 全部。**獨立型別、獨立檔**，不塞進既有 `Installer`（157 行）或 `Installer+Connect`（125 行）。

- `Sendable`；欄位只有 `URL`／`URL` ／`@Sendable (Data) -> String`。
  **`Sources/AuraHookFile/` 不得出現 `UserDefaults(`／`UserDefaults.`**（既有
  `HookVerificationStoreSourceScanTests` 會抓）。
- **不得 import CryptoKit／CommonCrypto**——`IsolationTests` 的 AuraHookFile 基準是
  Foundation ＋ CoreServices，加任何一個那條 gate 就紅（D-h 的成因）。digest 靠注入。
- `probe()`：`lstat` → `entryType`；只有 `regularFile` 才 `open(..., O_RDONLY | O_NOFOLLOW)` 讀，
  上限 1 MiB。`codexHome` 不是目錄 → `codexHomeIsDirectory = false`，其餘欄位保守值。
- `connect(json:)`：`open(path, O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC, 0o644)`（**這一行是保本動作，
  不准改成先 stat 再寫**）→ 寫 → close → 回 `digest(json)`。`codexHome` 不是目錄先 throw
  `.codexHomeMissing`，**不建立它**。
- `disconnect(expectedDigest:)`：`O_RDONLY|O_NOFOLLOW` → `fstat` 確認 `S_IFREG` → 讀 → 比對 →
  不符 throw `.notOurs`（不刪）→ 相符才 `unlink`。absent 視為已斷開、冪等成功。

**gates**：
- **G13**（`codexInstallerTouchesOnlyHooksJSON`，最重要）：connect＋disconnect 前後對 `codexHome`
  整棵樹取 `DirectoryTreeSnapshot`，差異集合**恰為** `{hooks.json}`；植入的 `config.toml`
  元組（含位元組）完全不變。
- **G14**（`codexConnectRefusesEveryOccupiedShape`，對抗式）：T01 的六種佔用形狀各自 throw，
  **且該路徑與 symlink 指向的目標位元組／型別完全不變**。「`hooks.json` 是 symlink 指向
  `config.toml`」那一格是這條 gate 的核心——它是唯一能區分 `O_EXCL` 與「先 stat 再寫」的輸入。
- G15（成功路徑：檔案內容 == 產生器位元組；回傳 digest == `digest(那些位元組)`）。
- G16（digest 相符才刪；改一個 byte → 不刪＋throw；`expectedDigest` 為 nil → 不刪）。
- G17（`~/.codex` 是外部 symlink：字面樹不變、`realpath` 樹差異恰為 `{hooks.json}`）。

**mutation**：① `connect` 順手寫 `hooks.json.bak` → G13 紅；② 拿掉 `O_EXCL`（改成
`O_CREAT|O_WRONLY|O_TRUNC`）→ **G14 的 symlink→`config.toml` 那格必須紅**（其餘格可能仍綠，
報告要寫明是哪一格紅的）；③ 拿掉 digest 比對 → G16 紅；④ 快照改用字面路徑（不解 `realpath`）
→ G17 紅；⑤ `connect` 少寫最後一個 byte → G15 紅。

---

## T07 `CodexState` ＋ `PanelAction` ＋ `OptionsMenuModel`

**目標**：§3 的判定表與 §4.6 的列。

- `CodexState.from(_:recordedDigest:)` 對 `EntryType` **窮盡 switch**、無 `default`。
- `PanelAction` 加 `.connectCodex`／`.disconnectCodex`／`.copyCodexSnippet`，
  同步補 `kind`（窮盡 switch）與 `samples`。
- `OptionsMenuModel.rows(...)` 多吃 `codex: CodexState`（**不給預設值**，比照 `PanelModel.make`
  的既有紀律——這裡猜錯的後果是「沒裝 Codex 的人看到 Codex 列」）；`.mount` 群組在
  `.notConnected`／`.connected` 各多一列，`.unavailable`／`.occupiedByOther` 零列。
- `nonMenuKinds` 加 `.copyCodexSnippet`。

**gates**：G18（`codexStateCoversEveryObservationShape`：定義域由
`EntryType.allCases × {digest 三態} × codexHomeIsDirectory` **推導**，不寫「10 格」這種數字）、
G19（`.unavailable` → rows 零 codex kind；其餘三態各自恰含預期列）、
G20（既有 `optionsRowsCoverEveryAction` 擴充：代表狀態集合加 `CodexState.allCases`；
`nonMenuKindsIsExactlyThatLiteralSet` 四個 → 五個）。

**test-edit scrutiny**：`nonMenuKindsIsExactlyThatLiteralSet` 的修改要在報告裡列
「改前四個／改後五個／為什麼 `.copyCodexSnippet` 屬於非選單」（spec D-k）——
**這是契約變更不是弱化**，判準是「集合仍然是恰好等於，只是多了一個有理由的成員」。

**mutation**：① 把 `symlink` 併進 `.notConnected` → G18 紅；② `.unavailable` 也給「接上 Codex」
→ G19 紅；③ 把 `.connectCodex` 塞進 `nonMenuKinds` → G20 紅。

---

## T08 `PanelModel` 欄位 ＋ 呼叫點機械更新

**目標**：`PanelModel` 加 `codex: CodexState` 與 `codexSnippet: String?`；
`PanelRow` 加 `agentLabel`（T05 已做則只驗）；`make(...)` 新參數**不給預設值**（G13 的既有 gate）。

- **61 個 `PanelModel.make(` 呼叫點、26 個檔**（改動前實測值；動工時先重新數一次並記在報告裡）。
  測試呼叫點一律傳 `codex: .unavailable`、`codexSnippet: nil`（＝現況行為）；
  生產呼叫點（`AppDelegate+PanelActions.refreshPanel`／`StatusItemController`）傳真實狀態。
- 改完 `wc -l` 檢查那 26 個檔沒有任何一個越過 300 行（`PanelPixelTests` 275、
  `Phase2EvidenceRenderer` 194 且有 15 個呼叫點——這兩個最接近）。

**gates**：既有 `panelModelMakeHasNoDefaults`（G13）必須繼續綠；G21 的 model 半
（`agentLabelOnlyForNonClaude`：claude → nil、codex → `"Codex"`）。

**test-edit scrutiny**：`#expect` 淨數量**不得下降**；不得有任何既有斷言因為「加了參數」
被改成更弱的形式。報告要附 `grep -rc "#expect" Tests/ | ...` 的改前／改後總數。

**mutation**：① `make` 忽略傳進來的 `codex`（固定用 `.unavailable`）→ 由 T09 的渲染 gate 抓
（本 task 先記，T09 補跑）；② `agentLabel` 對 `.claude` 也給值 → G21 紅。

---

## T09 View 層 ＋ `L10nCodex`

**目標**：列標籤（D-l）、`CodexSectionView`、snippet 複製入口、雙語字串。

- **所有新的中文字面必須住在 `Sources/AuraCore/L10nCodex.swift`**（`noStrayLiteralOutsideAllowlist`
  是真正生效的 gate，`pendingMigrationFiles` 已清空），並登記進 `L10nRegistry.allEntries`
  （`L10nRegistryCoverageSourceScanTests` 會抓漏登記）。兩個語言的字面若刻意相同，
  要進 `allowedSameAcrossLanguages` 並寫理由——「Codex」是產品名，走 `Agent.label` 不進字串表（T02 已定）。
- **列標籤放在既有的第一行 `HStack`（`projectName` ＋ `meta` 那個）**，不另起一行（D-l）。
- `CodexSectionView`：`.notConnected` 單行提示＋按鈕（§9 第一條：Claude 也未接上時不得用大版說明）；
  `.occupiedByOther` 說明＋可選取 snippet（`.textSelection(.enabled)`）＋「複製」按鈕。
  按鈕**必須用 `.borderless`**（離屏渲染下 `.bordered` 會被包進 `_FocusRingView` 而走訪不到，
  CLAUDE.md gate 哲學 §5）。
- 新增按鈕會動到既有離屏測試的**位置索引斷言**（離屏讀不到 `.title` 也讀不到
  `.accessibilityIdentifier`）——改完要逐一檢查 `FooterPixelTests`／`OptionsExpandTests`
  有沒有靠索引定位的斷言，報告裡列出檢查結果。

**gates**：G21 的像素半（同一列 claude vs codex，`differingPixels > 0`）、
**G22**（`codexLabelDoesNotChangeRowHeight`：帶標籤的列高仍是 `SessionsCardSizing.compactRowHeight`
43／`tallRowHeight` 59（±0.5pt），從真實 `NSHostingView(PanelRowView(...))` 量，**不是**常數對常數）、
`CodexSectionRenderTests`（`.notConnected`／`.occupiedByOther` 各自渲得出按鈕，非白像素 > 門檻）、
既有 `RowHeightDerivationTests`／`FooterPositionStabilityTests`／`OptionsExpandTests` 繼續綠。

**mutation**：① 標籤另起一行 → G22 紅；② `CodexSectionView` 在 `.unavailable` 也畫 →
`OptionsExpandTests` 的高度斷言紅（**這一格要特別確認**：如果它沒紅，代表「`.unavailable`
畫面零 diff」這件事沒有守衛，要補一條）；③ snippet 改成手寫字串（不走 `CodexHooksJSON.snippet`）
→ 新增一條「snippet 與產生器同源」的斷言必須紅。

---

## T10 `AppDelegate` 接線 ＋ `CodexHookStore` ＋ `Uninstaller`

**目標**：composition root 真的接上，完整移除真的涵蓋 Codex。

**第一步（純搬移，獨立 commit）**：`AppDelegate+PanelActions.swift` **目前恰好 200 行**，
加任何一個 case 都會讓 `fileLengthLimit` 紅。把 `openHelp`／`helpResourceName`／`helpURL`／
`reportIssue`（約 45 行含註解）搬到新的 `AppDelegate+Links.swift`。
**零行為變更**：搬完 `swift test` 必須全綠、`#expect` 總數不變、
既有 `HelpResourceNameTests` 一個字都不用改（若要改，代表搬移不純，停下來重做）。

**第二步**：
- `CodexHookStore`（App，`@MainActor` ＋ 注入 `UserDefaults`，比照 `HookVerificationStore`）：
  key `AgentAuraCodexHookDigest`；`static let sha256Hex: @Sendable (Data) -> String`（CryptoKit）。
- `AppDelegate+Codex.swift`：`performConnectCodex()`／`performDisconnectCodex()`／
  `performCopyCodexSnippet()`／`reprobeCodex()`；`codexInstaller`／`codexStore` 欄位；
  生產預設 `codexHome` = `FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(".codex")`（**不得用 `environment["HOME"]`**——`homeDirectoryForCurrentUser`
  讀密碼資料庫、不吃 `$HOME`，用環境變數算會在生產與測試給出不同答案）。
- 剪貼簿走注入縫 `writeToPasteboard: @MainActor (String) -> Void`（測試不碰真剪貼簿，
  比照 `openURL`／`confirmDisconnect` 的既有慣例）。
- 接上成功的 banner 必須**同時**含「下一個 Codex session 起生效」與「Codex 會問你信任」兩句（D-m）。
- `Uninstaller.run()` 在 `erasePersistentDomain()` **之前**多一步 codex disconnect（`try?`，D-n）。

**gates**：G23（`codexConnectChainIsWired`，四段：action 有接線／fake installer 真的收到 connect／
digest 真的進注入的 suite／banner 文字含兩個關鍵詞——**關鍵詞從 `L10nCodex` 的鍵推導，不寫死字面**）、
G24（`productionCodexHomeIsRealHome` ＋ 來源掃描 `Sources/` 不得用 `environment["HOME"]` 算它）、
G25（`uninstallRemovesCodexBeforeErasingDefaults`：Fake 記錄呼叫順序）、
既有 `panelActionsAreWired`（`PanelActionKind.allCases.flatMap(samples)` 逐一送）必須涵蓋三個新 kind。

**mutation**：① 刪 `.connectCodex` 分支的 body（改 `break`）→ G23 第一段紅；
② `codexHome` 改成 `environment["HOME"]` → G24 紅；③ codex disconnect 與
`erasePersistentDomain` 兩步對調 → G25 紅；④ banner 只留一句 → G23 第四段紅。

---

## T11 scripts ／ 文件 ／ 正典回寫

- `scripts/verify-uninstall.sh`：新增第 7 項（`${CODEX_HOME:-$HOME/.codex}/hooks.json` 存在**且**
  含 `--agent codex` → FAIL；存在但不含 → PASS；不存在 → PASS）。
  `CODEX_HOME` 覆寫存在的唯一理由是讓這一項可被測試（G26），**不是給使用者的介面**，
  腳本註解要寫明。項次編號往後移時，既有六項的文字不得變（diff 要看得出只是加了一項）。
- `docs/INSTALL.md` ＋ `.zh-TW`：新增「Using it with Codex」一節——前提（有 `~/.codex`）、
  按哪裡、**Codex 會問你一次信任**、生效時機（下一個 Codex session）、怎麼移除、
  以及 troubleshooting 第一條「燈不動？先確認 Codex 有沒有問過你信任」。
- `README.md` ＋ `.zh-TW`：「What it does to your Mac」加 `~/.codex/hooks.json`
  （只在你按下按鈕時建立、只在內容仍是我們寫的那份時刪除、`config.toml` 從不碰）。
- `SECURITY.md`：「What this tool can do on your machine」加同一條；
  「Boundaries that are enforced by tests」加「`~/.codex/config.toml` 位元組不變、
  差異集合恰為 `{hooks.json}`」。
  **注意**：`SECURITY.md` 沒有叫「What it does to your Mac」的段落（那是 `README.md:160`）——
  兩個檔案各自的段落名不同，別搞混。
- `Resources/help-english.html` ＋ `help-traditionalChinese.html`：新增 Codex 段
  （G27 會強制涵蓋新的 Options 列標題）。
- `CLAUDE.md`：Project 狀態、Invariants（兩條，見 spec §8.2）、Tier 1 清單（三個檔）。
- 正典 `docs/superpowers/specs/2026-09-08-agentaura-design.md`：§2.1／§2.2／§3.2／§3.7／§9 五處回寫
  （逐句對照表在 spec §8.2）。

**gates**：G26（`verifyUninstallScriptDetectsOurCodexHooks`：暫存 `CODEX_HOME` 跑兩次——
含 `--agent codex` → 腳本非零退出；別人的檔 → 該項 PASS）、
G27（既有 `HelpDocOptionsRowCoverageTests` 的代表狀態加 codex 態，兩個語言各自守）、
G28（`securityDocListsEveryPathWeWrite`：`README.md`／`SECURITY.md` 必須含
`CodexInstaller` 的相對路徑常數字面，不手抄）、
G29（`noCodexExecInRepo`：`Tests/`／`scripts/` 不得出現 `codex exec`，＋暫存目錄正向對照）。

**mutation**：① 拿掉腳本第 7 項 → G26 紅；② help 少寫「接上 Codex」→ G27 紅；
③ 從 SECURITY.md 刪掉 `.codex/hooks.json` 那一行 → G28 紅；④ 在腳本裡加一行 `codex exec` → G29 紅。

---

## T12 整合 ＋ DoD

跑 DoD 帳本全表（`docs/superpowers/plans/2026-09-18-codex-support-dod.md`）：
`swift test` 全綠且連跑 3 次 0 flake、gate mutation 帳（29 條，抽驗 3 筆現場重跑）、
`Sources/` 淨增、單檔行數、執行檔增量、`CodexInstaller.probe()` 成本、啟動時間增幅、
`claude plugin validate --strict`、`verify-install.sh`、`verify-uninstall.sh`、
**`plugin/hooks/hooks.json` 的 git diff 必須為空**、`~/.codex/config.toml` 全程 md5 不變。
產出實機清單 ①–⑥ 給使用者。Tier 1 → integrator 綠後派 persona-tester。

---

## 2. 已知風險（開工前就知道，不是驚喜）

1. **`Interrupt` 進 `handledEvents` 會讓 Claude 側整份 hooks 靜默失效**——爆炸半徑是整個產品對
   Claude 使用者停止運作，而症狀是「什麼都沒發生」。T03 的 G2／G5 是唯一的守衛。
2. `~/.codex/hooks.json` 是 symlink 指向 `config.toml` 時，「先 stat 再寫」會覆蓋使用者的設定。
   T06 的 `O_EXCL` ＋ G14 那一格 fixture 是唯一能區分正確與錯誤實作的輸入。
3. **Codex 端到端無法自動驗收**（F12：不准跑 `codex exec`）——「Codex 真的載入了我們的 hooks.json」
   這件事只有實機 ②③ 能證明。spec 與報告都不得用「已實測」描述它。
4. hooks.json 的頂層形狀（事件是否包在 `"hooks"` 物件內）只有 F1 的間接證據（§10-5）。
   若猜錯，實機 ② 會直接失敗；不要在測試裡「補一個更寬鬆的解析」來掩蓋。
5. `PanelModel.make` 的 61 個呼叫點是機械改動，最容易在其中夾帶弱化（T08 的 test-edit scrutiny）。
6. `AppDelegate+PanelActions.swift` 恰好 200 行——T10 第一步沒做就動它，`fileLengthLimit` 會紅，
   而那時人會傾向「把註解刪掉擠進去」，那是在拆掉別人留下的理由。
