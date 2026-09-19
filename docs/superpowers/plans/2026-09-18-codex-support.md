# `codex-support` 實作計畫

> spec：`docs/superpowers/specs/2026-09-18-codex-support-design.md`（**r10**）
> 證據：`docs/2026-09-18-codex-hook-probe.md`（**F1–F15**，F15 以 `8fdce0b` 的版本為準）
> 分支：`change/codex-support`　Tier：**1**（動 `Sources/AgentAuraApp/**` → integrator 綠後派 persona-tester）
> 節號引用一律指 r10 的 spec。
> **gate 編號**：本 change 新增的一律 `CX<n>`（共 **46** 條；CX37 拆成 a／b）；提到**既有** gate 一律寫測試函式名。

## 0. 給每個 implementer 的共同規則

- **一 task 一 commit**（必要時 refactor 拆第二個）。動工前 `git branch --show-current` 確認不在 `main`
  ——**而且要在 commit 前再確認一次**（多 agent 併行時 branch 會在腳下被換掉）。
- **TDD**：先 RED（理由要正確——不是編譯錯，是斷言失敗或型別還不存在），再 GREEN，再 refactor。
- **每條 gate 都要 mutation 紀錄**：生產碼改壞（完整字串取代）→ 先確認**編譯成功** →
  指名測試 **≤ 60s 內變紅（不是掛住）** → 還原。紀錄寫進報告：`mutation / 指名測試 / 秒數`。
- **起點不是全綠**：`FixtureCodeAnchorTests.everyFixtureModelIsMapped` **目前是紅的**
  （實測：`Jargon.model("gpt-5.5")` 原字回傳，`FixtureCodeAnchorTests.swift:81`）。
  那是 round4 fixture 進 repo 之後暴露的既有 gate 缺口，**本 change 必須修好它**（T05 §4.9），
  **不是**可以弱化或加 allowlist 的對象。除這一條外，開工前 `swift test` 應為全綠。
- **單檔上限**：`Sources/` 200 行、`Tests/` 300 行。**七個檔已經在或逼近上限**（spec §8.1 的表），
  其中三個要預先拆檔（T07／T10 第一步）。撞到紅燈時**不准刪註解擠進去**。
- **swift-testing**（`import Testing` / `@Test` / `#expect`），不是 XCTest。
- **禁止**：`--amend` 已 push 的 commit、`--no-verify`、`git reset --hard|checkout .|clean -f`、
  `fatalError`、在測試裡碰真的 `~/.codex`／`~/.claude`、**在任何地方跑 `codex exec`**（F12）。
- **套件必須維持可編譯**（T07 實測撞到）：上游型別**加 case** 時，**同一個 task** 要讓下游的窮盡
  `switch` 至少以 stub 編得過，**不得把編譯失敗留給後面的 task**。Swift 的窮盡 switch 對新 case 是
  **整個套件的連鎖編譯失敗**，不是「某條測試變紅」——後者可以排進下一個 task，前者會讓那之後的
  每一個 task 都無法開工、也無法量基準紅燈。stub 要標明「**由 T<n> 以真實作取代**」，
  並把「因 stub 而誠實變紅的既有 gate」列進該 task 的預期紅燈（見 T07）。
  **所有等下一個 task 替換的 stub，一律在註解貼 `AURA_CODEX_PENDING_T<nn>`**（沿用既有字面）。
  理由（T07 review M1）：本 change 的四個 stub 分屬三種機制——`#if` 旗標會 `Issue.record` 而紅、
  `switch` 的 `break` 靠既有 gate 誠實紅、窮盡 switch 的暫定值靠「動 view 時一定看到」，
  而 `OptionsSectionView` 硬編 `.unavailable` **既不紅也不在必經路徑上**。
  **只有可 grep 的標記能一次全包**，CX44 因此掃 **`Sources/` ＋ `Tests/`**，不必記得有幾個、在哪裡。
- **gate 不得拿生產常數跟自己比**（T04 review M1／M2，**同一個陷阱已經出現兩次**：`timeout` 與 `agentFlag`）：
  `#expect(產生器輸出 == "...\(CodexHooksJSON.agentFlag)")` 這種寫法，常數被改壞時兩邊一起變、**斷言恆真**
  ——實測把 `agentFlag` 改成 `"--agent codexx"`，全量 808 條測試**零新紅**。**期望值一律寫字面**；
  要證明「產生的東西真的能被消費」就加**跨 module round-trip**（把產物餵進真的消費者），
  不要讓生產者自己當自己的裁判。
- **寫 RED 測試時先把 import 寫齊**（T02 review m5）：`cannot find type 'X' in scope` 這一句，
  **既是** TDD 想要的 RED（型別還沒寫），**也是** harness 壞掉的 RED（漏了 import）。
  動手前先確認「除了本 task 要產出的符號以外，其他東西都解析得到」；報告引用編譯錯誤時，
  要能指出**缺的恰好只有本 task 的符號**。這條擋的是「RED 理由不正確」這整族，
  而那一族的終點是「為了讓它綠而改錯東西」。
- **既有測試不得弱化**：`#expect(` 淨數量不得下降（基準 **1649**，見 DoD #2 的量法更正）；改寫既有斷言要逐條列
  「改前／改後／測的還是不是同一件事」（spec §6.4 已預告九處）。
- **Claude 側零回歸是紅線**：`plugin/hooks/hooks.json` 的 git diff 必須為空；
  `EventMapping.handledEvents` 一個字都不准動。
- 中文 commit message 用 `git commit -F - <<'EOF'`，不要 `-m`。

## 0.1 開工前必讀的五件事（spec-reviewer r4 APPROVED 時附的簡報）

下面五條都已經散在 spec 與各 task 裡，這裡集中一次，因為它們是「讀漏了會做出壞事」的那幾條。

1. **這條 branch 現在就有一條紅，不是你弄壞的。** `FixtureCodeAnchorTests.everyFixtureModelIsMapped`
   已經紅（實跑確認：`Jargon.model("gpt-5.5")` 原字回傳），成因是 fixture 進了 repo 而 `Jargon`
   還不認得 Codex 命名。**T05 之前不要把「全綠」當起點**，也**不要為了讓它綠而去改那條 gate**
   ——它是對的，抓到的是真的缺口。修它的是 §4.9／CX41，**連同 `gpt-5`／`gpt-4.1-mini`／
   `gpt-5.5[high]` 三列一起做**（特別是 `gpt-5`：現行輸出是 `Gpt 5`，不是原樣回傳）。
2. **`Interrupt` 有一個看起來像「把對照表補齊」的錯誤選項，後果是產品對 Claude 使用者完全停止運作。**
   把它加進 `EventMapping.handledEvents` → 既有雙向等式 gate 要求 Claude 側 hooks.json 也註冊它
   → Claude Code 全有全無解析 → 整份 `Failed to load`，症狀是「什麼都沒發生」。CX2／CX5 是唯一守衛。
   同名陷阱：payload 欄位 `is_interrupt`（中斷一個 **tool**）與 Codex 的 `Interrupt` **事件**
   （中斷整輪）是兩件事，兩邊 doc comment 要互相點名。
3. **`connect` 的 `O_EXCL` 是保本動作，而它只有一格輸入測得出來。** 改成「先 `stat` 再寫」在四種
   佔用形狀裡有三種照樣 throw，只有「`hooks.json` 是 symlink 指向 `config.toml`」那一格會把使用者的
   設定覆蓋掉。CX15 的 mutation 報告要**寫明是哪一格紅的**。四種形狀實測**一律回 `EEXIST`**
   （沒有任何一種回 `EISDIR`），全部路由到 `.alreadyExists`。
4. **兩個「位置」錯了就會做壞事的判斷。** ① R-9：`performConnectCodex()` 的 `pathRejection` guard
   必須在**任何 `disconnect` 之前** return——晚一行，使用者只是從 DMG 開了一次 App 就會失去他
   還在運作的 `~/.codex/hooks.json`（CX39 守；CX35 有「`pathRejection == nil`」前提，兩條一起看）。
   ② D-u：`Jargon` 的 Codex 分支排在既有演算法**之前**，既有六條規則**一行不動**，
   判不出來一律落回「原樣回傳」（CX41 的 mutation ⑨ 守這個前後順序）。
5. **三個 tested≠wired 的溫床，各自有一條指名的 gate。** ① `reprobeCodex()` 必須在四個時機各呼叫
   一次，漏了就是「裝了 Codex、開面板、什麼都沒有，重開才出現」而全套綠（CX24⑤）；
   ② `CodexHookStore` 的 `Data → 文字 → Data` round-trip 必須逐位元組相等，壞了的症狀不是報錯
   而是**完整移除留殘留**（CX31，輸入要用真產生器輸出，不是 `"{}"`）；
   ③ 兩層 `samples` 的 `switch` **不得有 `default`**——那是兩個平行 Kind 型別存在的唯一理由。

---

## 1. 任務與依賴

| # | Task | 產出 | 依賴 | gates |
|---|---|---|---|---|
| T01 | 測試底座（**零生產碼**） | 對抗式 double、fixture 覆蓋、`DirectoryTreeSnapshot` 抽取、smoke 骨架、**兩側交錯 fixture** | — | 全部 RED 且理由正確 |
| T02 | `Agent` ＋ `AgentArgument`（AuraCore 純函式） | §3、§4.1 | T01 | CX7 |
| T03 | `codexEvents` ＋ `Interrupt` 映射（**接縫**） | §4.2 | T01 | CX1–CX5 |
| T04 | `CodexHooksJSON`（逐字 F14）＋ `CodexHookPathCheck`（含 `RejectionKind`） | §4.3、§4.4 前半 | T03 | CX6、CX33 |
| T05 | `agent` 貫穿四段 ＋ `aura-hook` 接線 ＋ **`Jargon.model` Codex 命名** ＋ **雙 agent 端到端** | §3、§4.1、§4.7、§4.9、§4.8 | T02 | CX8–CX13、**CX38**、**CX41** |
| T06 | `CodexInstaller`（含路徑 guard）＋ **兩側檔案序列不變式** | §4.4、§4.8 | T04 | CX14–CX18、CX32、**CX37a／CX37b** |
| T07 | `CodexState`（六態）＋ `PanelAction` ＋ `OptionsMenuModel` ＋ **`AppDelegate+Links.swift` 純搬移** ＋ **兩個下游 switch 的 stub** | §3、§4.6 | T06 | CX19、CX20、CX21、CX34 |
| T08 | `PanelModel` 欄位 ＋ 61 個呼叫點（機械） | §4.6 | T07 | CX22（model 半） |
| T09 | View 層 ＋ `L10nCodex` | §4.6 | T08 | CX22（像素半）、CX23、**CX36** |
| T10 | `AppDelegate` 接線（**以真實作取代 T07 的 stub**）＋ `CodexHookStore` ＋ `Uninstaller` ＋ **兩側憑證序列不變式** | §4.5、§4.6、§4.8、§6.2 | T06、T09 | CX24–CX26、CX31、CX35、**CX39**、**CX40**、**CX42** ＋ 既有 `panelActionsAreWired` **轉綠** |
| T11 | scripts ／ 文件 ／ 正典回寫 | §8.2 | T07 | CX27–CX30 |
| T12 | 整合 ＋ DoD 量測 | DoD 帳本全表 | 全部 | — |

### 並行策略（有 agent 在跑時，主 session 不在共享工作目錄作業）

```
wave 1: T01                       （單獨，擋住所有人）
wave 2: T02 ∥ T03                 （兩個不同 AuraCore 檔，無交集）
wave 3: T04（需 T03）∥ T05（需 T02）
wave 4: T06（需 T04）
wave 5: T07（需 T06；**動到 Sources/AgentAuraApp/ 兩個檔**——`AppDelegate+Links.swift` 純搬移
        ＋ `AppDelegate+PanelActions.swift`／`OptionsSectionView.swift` 的 stub。Tier 1 不變）
wave 6: T08（需 T07）∥ T11（需 T07 的列標題；只動 scripts/ 與 docs/，與 T08 零交集）
wave 7: T09（需 T08）
wave 8: T10（需 T06、T09）
wave 9: T12
```
衝突檔以 `git worktree add` 隔離，作業完 merge 回 `change/codex-support`。

### 前置條件（已滿足）

`Tests/AuraCoreTests/Fixtures/round4-codex.ndjson` 已就位：18 筆、4 個 session。事件分布（實測）：
`SessionStart` 4／`UserPromptSubmit` 4／`Stop` 4／`SessionEnd` 4／`PreToolUse` 1／`PostToolUse` 1；
**零筆** `Interrupt`／`PermissionRequest`／`Subagent*`／`*Compact`（CX4 必須獨立存在的理由）。
唯一的 `model` 值是 **`gpt-5.5`**、唯一的 `permission_mode` 是 `bypassPermissions`（已在既有映射表裡）、
**沒有 `effort`**。

---

## T01 測試底座（零生產碼）

**目標**：讓後面每一條 gate 都不可能生下來就是綠的。**不寫任何生產碼**，交付時全部 RED，
且每條 RED 的理由必須是「斷言失敗」或「型別還不存在」。

1. **`DirectoryTreeSnapshot` 抽取（純重構，先做）**：把 `ClaudeHomeTreeSnapshot.swift` 的
   `walk`／`entry`／`changedPaths` 抽成通用型別（CX14／CX32／**CX37a／CX37b** 都要用），
   `ClaudeHomeTreeSnapshot` 變成它的 skills-realpath 特化。
   **驗收**：既有 `InstallerPathScopeTests` 兩條全綠，且**當場重跑一次既有
   `installerTouchesOnlyAllowedPaths` 的 mutation**（`connect` 順手寫 `settings.json.bak`）確認仍精準紅。
2. **Codex 檔案系統 fixture**（`CodexHomeFixture`）：八種形狀——`~/.codex` 不存在／是普通檔／
   是目錄（空）／`hooks.json` 是普通檔（別人的合法 JSON）／是目錄／是 **symlink 指向同目錄的
   `config.toml`**／是斷鏈 symlink／是 **5 MB 垃圾**（> 64 KiB，驗 D-q）；外加「`~/.codex` 自己是
   指到 fixture 之外的 symlink」。每種都植入內容已知的 `config.toml`。
3. **兩側交錯 fixture（R-8，CX37a／CX37b 用）**：同一個暫存根底下同時有 `claudeHome`（含 `settings.json`
   與 bundle plugin fixture）與 `codexHome`（含 `config.toml`），兩側都能被各自的 installer 操作。
4. **路徑 fixture（CX32／CX33／CX39 用）**：`translocated: true`／`inDownloads: true`／
   六個不支援字元（空白、`'`、`"`、`$`、`` ` ``、`\`）各一條路徑／**同時 translocated ＋ 含空白**
   （驗優先序）／乾淨路徑（負對照）。
   **每一格要帶 `expectedRejection`，期望值寫死、不從實作反推**（T01 review M1）：
   用不依賴 T04 型別的字串描述（`nil`／`"mustMoveToApplications"`／`"unsupportedCharacter(<字元>)"`），
   比照 argv 表的 `expectedRawValue` 那一招。理由：CX33（T04）／CX32（T06）／CX39（T10）三條 gate
   守的是 R-5 那道安全護欄，期望值若等實作出現才寫，等於三條 gate 都是事後對答案；
   而 `translocatedAndContainsSpace` 要驗的「translocated 優先於字元檢查」**只存在於 case 名字裡**，
   沒有任何資料表達它。
5. **對抗式 payload fixture**（程式合成）：缺 `permission_mode`／缺 `model`／`tool_response`
   是 200 KB 字串／`hook_event_name: "Interrupt"` **帶** `agent_id`／`session_id` 是 UUIDv7。
6. **argv 對抗式表（8 格）**：`[]`、`["--agent"]`、`["--agent","gemini"]`、`["--agent","CODEX"]`、
   `["--agent=codex"]`、`["--agent","codex","--agent","claude"]`、`["--agent","codex","--agent"]`、
   **`["--agent","gemini","--agent","codex"] → `claude`**。
   期望值寫死在表裡，**不是從實作反推**；**這張表是 CX7 與 CX8 共用的唯一來源**，放共用 helper。
   **第 8 格是 T02 review M1 補的**：前七格分辨不出「第一個*出現*者勝」與「第一個*有效*者勝」——
   reviewer 用後者的替代實作實跑，七格**全綠**；而後者等於**讓使用者手寫錯的第一個旗標被後面的
   悄悄蓋過去**，正是 D-d 要防的事。自我測試的格數斷言（`count == 8`）與測試名要一起改。
7. **`FakeCodexInstaller`**：① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
   ② `disconnect()` 宣稱成功但檔案還在；③ `probe()` 丟錯；
   ④ **記錄 `connect`／`disconnect`／`probe` 的呼叫順序與次數**（CX24⑤、CX35、CX39 都要用）；
   ⑤ **`connect` 在 `translocated == true` 時拒絕**。
   **本地協定的簽章必須就是 spec §4.4 已定案的那個**（T01 review M2）：
   `connect(json:translocated:inDownloads:) throws -> Data`、`disconnect(ifContentsEqual:) throws`。
   四個參數都不需要任何 T04／T06 的新型別，現在就能編譯；**簽章少一個維度不是「之後微調」，
   是情境表達不出來**——CX39 的全部意義是「`connect` 因為 `translocated` 被拒，所以 `disconnect`
   的呼叫次數必須是 0」，`connect()` 收不到 `translocated` 就承載不了它；`disconnect()` 沒有
   `ifContentsEqual:` 則 CX35／CX17 的「內容不符就不刪」同樣表達不出來。
   **`FakeCodexStore`**：可設定「寫進去與讀回來不一致」；**原始值欄位設 `private`，只留 `read()`**
   （T01 review m2：`contents` 與 `read()` 並存時，一條寫 `store.contents == written` 的測試會完全
   繞過 corruption，而 CX24③ 正是最該被它咬到的地方）。真的需要看原始值就叫
   `rawContentsForAssertion`，讓繞過變成一個看得見的動作。
8. **round4 fixture 覆蓋測試骨架**（CX13）：18 筆逐筆解析；**期望值來自探針文件的欄位表**，
   不是從 `HookPayload` 現有行為反推；外加**兩層**反向斷言——事件層（表列的每個事件都有樣本）
   **與欄位層（表列的每個欄位在該事件的樣本裡至少出現一次）**。
   **欄位層不可省**（T01 review M3，主 session 裁決保留）：只有事件層的話，把 fixture 裡每一筆的
   `model` 欄位拿掉會全綠，而那正好讓跨層錨點 `everyFixtureModelIsMapped` 從紅變綠——
   **用縮小證據來消滅一條紅燈**。`ProbeRow` 因此要帶 `fields: [String]`（六列逐字抄探針文件
   「每種事件的欄位」表）。
9. **composition-root smoke 骨架**：`CodexWiringSmokeTests` 的**五段**（CX24），
   第三段要比對**位元組**（不是「非 nil」）。
10. **像素 harness 沿用**：`renderPinned` ＋ `differingPixels`；CX22／CX23／CX36 用它們。

**驗收**：`swift test` 全跑得完（不掛住），且**兩類分開講**（T01 review m5）——
**gate 骨架**必須 RED 且理由正確（「斷言失敗」或「型別還不存在」）；
**fixture／double 的自我測試**必須 GREEN（它們驗的是 fixture 自己，純 Foundation／POSIX，
RED 沒有意義）。兩類各自逐條說明。
**外加**：`grep -rn "codex exec" Tests/ scripts/` 為零（CX30 的人工預跑）。
**再外加**：自我測試的 `switch` **不得有 `default`**（同 D-r 的禁令，理由一字不差適用於測試碼——
新增一個 fixture 形狀會靜默落進 `default` 被當成別的東西）；5 MB 垃圾檔用
`Data(repeating:count:)` 而不是逐 byte 隨機（隨機性不是需求，而 T06 還會反覆建它）。

---

## T02 `Agent` ＋ `AgentArgument`

- `Agent` 的安全預設是 `.claude`（D-b），**保守失敗**（少一個標籤 vs 標錯），doc comment 寫明
  這個不對稱，以及為什麼不套用 `Language` 那種「不給預設值」的紀律。
- `storedRawValue` 對 `.claude` 回 `nil`（D-c）——CX9 的單一機制。
- `AgentArgument.agent(from:)` 支援兩種寫法；由左至右取**第一個**匹配；大小寫敏感；不匹配一律 `.claude`。
- `label` 對 `.codex` 回 `"Codex"`——**產品名不進 L10n**，doc comment 寫明是刻意的。

**gates**：CX7（定義域＝T01 的 **8 格**共用表 ＋ 非空守衛）。
**mutation**：① 未知值改成回 `.codex` → CX7 紅；② `storedRawValue` 對 `.claude` 回 `"claude"` →
CX9 紅（T05 之後才觀測得到，本 task 先記）。

---

## T03 `codexEvents` ＋ `Interrupt` 映射（本 change 最容易踩的接縫）

**先讀 spec §4.2 再動手**——有一個會讓產品對 Claude 使用者完全停止運作的錯誤選項
（把 `Interrupt` 加進 `handledEvents`），而它看起來像是「把對照表補齊」。

- `codexEvents`：12 個字面名（F2）。doc comment **分標兩種證據強度**（六個有真實 payload／
  六個只有二進位字串 `HookEventsToml` 列舉）。
- `codexOnlyEvents = ["Interrupt"]`；`effect` 加 `case "Interrupt": .setActivity(.idle)`。
  doc comment 必須點名 **`Interrupt` 事件 ≠ `is_interrupt` 欄位**；`HookPayload.isInterrupt`
  的 doc comment 也加一句反向指回。
- **`handledEvents` 一個字都不准動**。

**gates**：CX1、**CX2**（失敗訊息**寫出後果** ＋ §4.2 的 runtime 限定語，不要求逐字某四個字）、
CX3、**CX4**（定義域從 `codexOnlyEvents` 推導）、**CX5（要加定義域非空守衛**——`hooks` 物件解析成
空字典時 `try #require` 會通過、交集為空而靜默全綠；CX1／CX3／CX4 都有這個守衛，只有它沒有）。
**mutation**：① `Interrupt` 加進 `handledEvents` → CX2 紅（**且**既有
`registeredEventsMatchHandledEvents` 也紅，兩條都記）；② 拿掉 `PreCompact` → CX3 紅；
③ **刪掉 `case "Interrupt"` 整行 → CX4 紅**（報告要記「加 CX4 之前同一個 mutation 全綠」）；
④ Claude hooks.json 加 `Interrupt` → CX5 紅；⑤ `codexEvents` 少一個 → CX1 紅。

---

## T04 `CodexHooksJSON` ＋ `CodexHookPathCheck`

兩個都是 AuraCore 純函式、只 import Foundation。

### 4a `CodexHooksJSON`
- 逐字 F14：`{ "hooks": { "<event>": [ { "matcher": "", "hooks": [ { "type": "command",
  "command": "<abs> --agent codex", "timeout": 3 } ] } ] } }`，12 個事件，鍵從 `codexEvents` 排序推導。
- **`timeout` 從單一常數 `hookTimeoutSeconds = 3` 推導**。doc comment 寫齊三件事：
  ① 對 F14 **唯一的數值偏離**；② 目的是避免 F13 的 clamping 警告落在使用者 stderr；
  ③ **「3 不觸發警告」是推論不是事實**。**不准**為某個事件做特例。
- **`matcher: ""` 不可省**，理由只引 F14 的「未測」欄。**不得**拿 Claude 側當佐證
  （Claude 的 19 個 entry 裡只有 `Notification` 帶 `matcher`；兩個解析器寬容度相反，F7）。
- **不加 `async`**；`command` **不加引號**。`snippet(...)` 就是 `json(...)` 的文字形式。

**gates**：CX6（① 鍵集合 == `codexEvents`；② **12 個 entry 逐一逐字等於 F14**；③ 乾淨路徑 round-trip）。
**mutation**：① 寫死 11 個 ② 拿掉 `matcher` ③ 加 `async: true` ④ 漏 `--agent codex`
⑤ **`timeout` 改回 5** → 各自紅在 CX6 的對應段。

### 4b `CodexHookPathCheck`（含 `RejectionKind`，r3 m1／m2）
- `rejection(translocated:inDownloads:hookBinaryPath:)`：① `translocated || inDownloads` →
  `.mustMoveToApplications`；② 否則掃路徑，**第一個**命中 `unsupportedCharacters` 的字元 →
  `.unsupportedCharacter(c)`；③ 否則 nil。**零 I/O、零平台 API**。
- **`RejectionKind: String, CaseIterable`** ＋ `Rejection.kind` ＋ `Rejection.samples(_:)`，
  **兩個 `switch` 都不得有 `default`**——doc comment 要逐字寫「那正是這個平行型別存在的唯一理由；
  加一個 `default: []` 會讓整條定義域推導鏈靜默失效」。
- doc comment 寫明既有 `Installer` 的 `mustMoveToApplications` **沒有**「必須在 `/Applications`」
  這個條件，所以 `~/Applications/`、`~/My Apps/` 可以含空白，「幾乎永遠不觸發」不成立。

**gates**：CX33（六個字元逐格，定義域從 `unsupportedCharacters` 推導；帶**第一個**命中的字元；
translocated 優先；乾淨路徑 nil）。
**mutation**：① 一律回 `.unsupportedCharacter(" ")` → 紅；② 優先序對調 → 紅。

---

## T05 `agent` 貫穿四段 ＋ `aura-hook` 接線 ＋ `Jargon` ＋ 雙 agent 端到端

**目標**：payload → 檔案 → state → UI 四段都走完（`SessionState.model` 與 `toolDescription`
各自都曾經只走完兩段就以為做完了）。

### 5a `agent` 貫穿
- `SessionSnapshot.agent: String?`（CodingKey `agent`），doc comment 引用 `outstandingSubagents`
  那段「必須是 Optional」的理由。
- `MergeRules.merge(_:into:pid:pidStartedAt:agent:now:)`——**`agent` 不給預設值**（7 個呼叫點）；
  `s.agent = agent.storedRawValue ?? s.agent`（carry-forward，比照 `cwd`／`model`）。
- `SessionReducer` → `SessionState.agent: Agent`；`PanelViewModel.row` → `PanelRow.agentLabel`。
- `aura-hook/main.swift`：`let agent = AgentArgument.agent(from: CommandLine.arguments)` 傳進 merge。
  **不得新增任何 stdout／stderr 輸出、不得有非零 exit 路徑**。
- **liveness 不改**（§4.7）。`main.swift` 既有註解補一句：F15 已證實 Codex 的 hook 父行程
  **不是逐事件的 shell**、pid 在 session 期間穩定；**但那五個 session 全在 `exec` 模式，
  互動 TUI 的行程結構未量**，並指向 §4.7 的 fallback 決策點。**本 task 不實作 fallback。**

### 5b `Jargon.model` 的 Codex 命名（§4.9；**修一條目前是紅的既有 gate**）
- 現況（實測）：`swift test --filter FixtureCodeAnchorTests` → `everyFixtureModelIsMapped` **紅**，
  訊息 `Expectation failed: (Jargon.model(v) → "gpt-5.5") != (v → "gpt-5.5")`。
- 在既有演算法**之前**加 Codex 家族分支；**既有六條規則一行不動**；判不出來落回「原樣回傳」。
- **Codex 分支的四步規則見 §4.9**（`[...]` 尾綴先處理 → `o` 系列原樣 → `gpt-` 去前綴、第一段以
  **連字號**接上 → 其餘段首字大寫、以空白連接）。四步是為了讓下表每一列都可推導，不是各列各寫一套。
- 期望值**寫死在表裡**（§4.9 的**十列**）：`gpt-5.5` → `GPT-5.5`（**唯一實測值**）、
  `gpt-5.5-codex` → `GPT-5.5 Codex`、`gpt-4o` → `GPT-4o`、**`gpt-5` → `GPT-5`**、
  **`gpt-4.1-mini` → `GPT-4.1 Mini`**、**`gpt-5.5[high]` → `GPT-5.5 (HIGH)`**、
  `o3` → `o3`、`o4-mini` → `o4-mini`（**`o` 系列維持小寫**）、**`o3[high]` → `o3[high]`**、
  既有九列輸出**完全不變**。
- **`o3[high]` 那一列釘的是兩個家族對 `[...]` 尾綴的刻意不對稱**（T05 review m3）：`gpt-5.5[high]` 走規則 1
  重組成 `GPT-5.5 (HIGH)`，`o` 系列走規則 2「整串原樣回傳」、**不套用已剝除的 bracket 重組**。
  沒有這一列，那個不對稱只活在註解裡。
- **`gpt-5` 那一列是重點**（r4 M1）：它是唯一一個**現行行為不是原樣回傳**的輸入——
  `["gpt","5"]` 的 `5` 是純數字，既有演算法**成功**並回傳 **`Gpt 5`**。新分支排在既有演算法之前，
  所以它會從 `Gpt 5` 變成 `GPT-5`：**一個使用者看得到的字串靜默改變**，而它不在任何 fixture
  （層一看不到）也不在原本的表（層二看不到），正好掉在兩層守衛之間。必須釘住，
  讓它成為一個**被記錄的決定**而不是副作用。
- **test-edit scrutiny（必須逐條寫進報告）**：既有 `JargonTests.modelTwoNonNumericSegmentsPassesThrough`
  逐字釘死 `Jargon.model("gpt-4o") == "gpt-4o"`。那條測試的**原意**是「兩個非數字段 → 原樣回傳」，
  不是「gpt-4o 必須原樣回傳」。所以：**把輸入換成非 Codex 家族的例子**（例如 `foo-bar-5`）
  保住原性質，**另外新增**一列釘死 `gpt-4o` 的新期望值。
  **換掉的輸入必須真的落在既有演算法的規則 6**（`foo-bar-5` → 兩個非數字段 ＋ 一個數字段，
  形狀成立）；換一個其實走別條規則的輸入，等於把那條測試換成測別的東西。
  報告要附**「改前／改後／測的還是不是同一件事」三欄**（測試名不變、被測性質不變、
  斷言數**增加**一條）。**直接刪掉那條測試＝弱化，要退回。**

### 5c 雙 agent 端到端（R-8 不變式 2）
- CX38：同一顆 `aura-hook`，先 Claude payload（round1 fixture，**無參數**）、再 Codex payload
  （round4 fixture，`--agent codex`），寫進**同一個** `AGENTAURA_ROOT`；斷言兩個 snapshot 的
  `agent`／activity 各自正確；**反序再跑一次**。
- **「互不覆蓋」在 doc comment 標成結構性結論，不是被測性質**（r4 m1）：`SnapshotIO` 以
  `<session_id>.json` 分檔，而兩份 fixture 的 id 本來就不同，所以那個斷言在任何實作下都會通過
  （包括完全壞掉的實作）。真正有牙齒的是「同一顆二進位服務兩個上游」與「兩邊 `agent` 各自正確」，
  mutation 打的也是那兩半。id 空間不交集是**明寫的假設**，列在 §10-16。
- 真 spawn **必須經 `SpawnGate`**。`EndToEndWiredGateTests` 目前 149 行，餘裕充足；
  超過 300 就拆 `EndToEndDualAgentTests.swift`。

**gates**：CX8（**8 格**共用表真 spawn）、CX9、CX10、CX11、CX12、CX13、**CX38**、**CX41**。

**驗收必含：解除 `#if AURA_CODEX_PENDING_T05`**（T01 review m1）。T01 用這個旗標讓 gate 骨架在
依賴的型別落地前仍可編譯，而 `Package.swift` 沒有任何 `-D`（DoD #9 要求它的 diff 為空），
所以**那些分支從未被型別檢查過**——解除等於「在最想看到綠燈的時刻，對一段沒編譯過的程式碼
做無上限的編輯」。報告要附**解除前／後的 `#expect` 數與測試函式數，只准上升**；
殘留由 T12 的 CX44 掃描把關。
**mutation**：① `main.swift` 忘了傳 agent → CX10 紅；② `storedRawValue` 對 `.claude` 回 `"claude"`
→ CX9 紅；③ `agent` 改成非 Optional → CX11 紅；④ 改成 `Agent?`（enum）→ CX12 紅；
⑤ `effect` 對 `Stop` 改成 `.noChange` → CX13 紅；⑥ **`--agent` 解析改成一律回 `.claude` → CX38 紅**；
⑦ **Codex 分支回傳 raw → CX41 紅且既有 `everyFixtureModelIsMapped` 也紅**（兩條都記）；
⑧ **把 `o3` 改成 `O3` → CX41 紅**；
⑨ **把 Codex 分支從既有演算法之前移到之後 → CX41 的 `gpt-5` 那列必須紅**
（那是唯一能區分前置／後置的輸入——其餘 gpt 列在後置時仍會落到 Codex 分支）。

**注意**：`MergeRulesTests` 目前 294 行，加一個參數餘裕 6 行。

---

## T06 `CodexInstaller` ＋ 兩側序列不變式

**獨立型別、獨立檔**，不塞進既有 `Installer`（157 行）或 `Installer+Connect`（125 行）。

**本 task 不需要 fake installer**（T01 review m6）：這裡測的是**真** `CodexInstaller` 對真 fixture 目錄，
CX37a／CX37b 用的也是真 installer。App 層的 fake 住在 `Tests/AgentAuraAppTests/Support`，
兩個 test target 互不可見——**不要抄一份過來**。需要 fake 的是 T10 那些 smoke（CX24／CX35／CX39／CX42）。

**動手前先量一件事**（T01 review 給 T06 的提醒）：`DirectoryTreeSnapshot.take(root:)` 內部用
`FileManager.enumerator(at:)`，而它對「指向目錄的 symlink」會**穿透**去列舉目標內容。
CX18 想斷言的是「字面樹不變、`realpath` 樹差異恰為 `{hooks.json}`」——若 `take(root:)` 穿透，
兩棵樹在 `codexHomeIsExternalSymlink` 這個形狀下**可能是同一棵**，斷言就變成套套邏輯。
先用一個一次性測試量 `take(root:)` 對 symlink root 的實際行為，必要時在 `DirectoryTreeSnapshot`
加一個「**不穿透 root symlink**」的取法，再寫 CX18。量到的結果寫進 CX18 的 doc comment。

- `Sendable`；**欄位只有兩個 `URL`**。**`Sources/AuraHookFile/` 不得出現 `UserDefaults(`／
  `UserDefaults.`**（既有 `HookVerificationStoreSourceScanTests` 會抓），**也不得 import Security**。
- `probe()`：只有 `regularFile` **且 ≤ 64 KiB**（D-q）才 `open(..., O_RDONLY | O_NOFOLLOW)` 讀。
- **`connect(json:translocated:inDownloads:)`**：**第一行**呼叫 `CodexHookPathCheck.rejection(...)`，
  非 nil 就 throw 對應的 `CodexFailure`——**保本動作，不准只信路由層**（S0-1(ii)）。
  接著 `O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC`（D-i）→ 寫 → close → 回傳寫出去的 `Data`。
  `codexHome` 不是目錄先 throw `.codexHomeMissing`，**不建立它**。
  **`EEXIST` 一律 → `.alreadyExists`**（四種佔用形狀實測全部 `EEXIST`，沒有 `EISDIR`）。
- `disconnect(ifContentsEqual:)`：`O_RDONLY|O_NOFOLLOW` → `fstat` 確認 `S_IFREG` → 讀 →
  **逐位元組比對** → 不符 throw `.notOurs`（不刪）→ 相符 → **`unlink` 前再 `lstat` 比對
  `(dev, ino)`，不同就放棄** → `unlink`。absent 冪等成功。

**CX37a／CX37b 序列 gate（R-8 不變式 1 的檔案半）**：對
`{connectClaude, connectCodex, disconnectClaude, disconnectCodex, reconnectCodex(stale)}`
**程式推導**序列（**不手列**），每步之後對「另一側」整棵樹取 `DirectoryTreeSnapshot` 斷言**零差異**；
序列結束時若兩側皆 connected，兩側 `probe()` 推導的狀態皆為 connected。**拆成兩條**（r4 M2）：

- **CX37a（全部 780 條，零 spawn）**：`connectClaude` 這一步**直接呼叫
  `installer.guardWriteTarget()` ＋ `installer.atomicReplace()`**。**這不是抄近路，是等價**——
  那兩步就是 `claudeHome` 底下唯一會被碰到的動作，`verifyByExecuting` 對 `claudeHome` 的樹
  **沒有任何貢獻**（它只寫 `verificationRootOverride` 指定的位置，`removexattr` 作用在 bundle 內的
  二進位）。先例：`InstallerClobberTests.performConnectStepsGuardsWriteTargetDirectly` 就是直接呼叫
  內部步驟，doc comment 逐字寫著理由；`@testable import AuraHookFile` 在 `Tests/AuraCoreTests/`
  已有十個檔在用。5＋25＋125＋625 = 780 條、2930 次操作，毫秒級，**全跑，不縮減**。
- **CX37b（生產路徑，長度 ≤ 2 共 30 條）**：走完整的
  `installer.connect(force:translocated:inDownloads:)`，**含 spawn**，注入小的 `verificationTimeout`。
  `connectClaude` 出現次數 = 1 ＋ 10 = **11 次真 spawn**，走 `SpawnGate`。
  守的是「完整流程也不碰另一側」，接住 CX37a 跳過那一步可能漏掉的東西。

兩條的 doc comment **互相點名**：a 寫「為什麼跳過 spawn 是等價的」，b 寫「為什麼只到長度 2」。
**不要用 `verificationRootOverride`／`verificationTimeout` 試圖免 spawn**——前者只改驗證 session 的
寫入位置、後者只改等待上限；`verifyByExecuting` 是 `performConnectSteps()` 的**無條件最後一步**。

**gates**：**CX14**、**CX15**、CX16、CX17、CX18、**CX32**、**CX37a**、**CX37b**。
**mutation**：① `connect` 順手寫 `hooks.json.bak` → CX14 紅；② 拿掉 `O_EXCL` → **CX15 的
symlink→`config.toml` 那格必須紅**（報告寫明哪一格）；③ 拿掉內容比對 → CX17 紅；
④ 拿掉 `(dev,ino)` 複查 → CX17 該段紅；⑤ 快照用字面路徑 → CX18 紅；⑥ 少寫一個 byte → CX16 紅；
⑦ 拿掉 `connect` 第一行 guard → CX32 紅；
⑧ **`CodexInstaller.connect` 順手 touch `<claudeHome>/skills/agentaura` 的 mtime → CX37a 與 CX37b 都必須紅**（兩條都記）。

---

## T07 `CodexState`（六態）＋ `PanelAction` ＋ `OptionsMenuModel`

**第一步 (a)（純搬移，獨立 commit）**：`OptionsMenuModelTests.swift` **恰好 300 行**，
新增 `CodexOptionsRowTests.swift` 承接 codex 斷言。**零行為變更**：`#expect` 總數不變、
被搬動的測試函式名一字不改。

**第一步 (b)（純搬移，獨立 commit；原本排在 T10，r9 提前到這裡）**：
`Sources/AgentAuraApp/AppDelegate+PanelActions.swift` **恰好 200 行**，把 `openHelp`／
`helpResourceName`／`helpURL`／`reportIssue`（約 45 行含註解）搬到 `AppDelegate+Links.swift`。
**零行為變更**：`swift test` 全綠、`#expect(` 總數不變、既有 `HelpResourceNameTests` 一字不改。
**為什麼提前**：本 task 給 `PanelAction`／`PanelActionKind` 加三個 case，而
`AppDelegate+PanelActions.swift:18` 的 `switch action` 是**窮盡、無 `default`** 的——
不在同一個 task 裡讓它編得過，T08 之後的每一個 task 都開不了工（§0 的「套件必須維持可編譯」）。
那個檔剛好在 200 行上限，所以得先騰出空間才加得了 case。

**第一步 (c)（兩個下游 switch 的最小 stub，可與第二步同一個 commit）**：
- `AppDelegate+PanelActions.swift` 的 `switch action`：三個新 case 各給 `break`。
- `OptionsSectionView.swift` 的 `OptionsRowIconView.systemName(for:)`：三個新 case 各給暫定 icon。
兩處都要標明「**T10／T09 必須以真實作取代**」。
**預期紅燈分兩類**（報告要分開列）：① 本 task 自己的 gate 骨架（CX19／CX20／CX21／CX34）；
② **因 stub 而誠實變紅的既有 gate**——`panelActionsAreWired` 對三個新 kind 會紅到 T10 接線為止。
②**不算基準紅**，也**不准**為了讓它綠而弱化它：那是 tested≠wired 守衛正在做它該做的事。

**第二步**：
- `CodexState` 六態（含 `.blockedByBundlePath(Rejection)`、`.connectedStalePath`）；
  `CodexStateKind: String, CaseIterable` ＋ `samples(_:)`，其中
  **`.blockedByBundlePath` 那一格 = `RejectionKind.allCases.flatMap(Rejection.samples).map(...)`**
  （T04 已備好下層）。**`switch` 不得有 `default`**，doc comment 逐字寫明理由。
  **順手補進既有 `PanelAction.samples` 的 doc comment**（一行，零風險，r3 m2）。
- `CodexState.from(_:recordedContents:currentExpectedContents:pathRejection:)`：對 `EntryType`
  **窮盡 switch**、無 `default`，**判定順序照 spec §3 的七列表，由上而下第一個命中者勝**
  （**r4 不動列序**）。
- `CodexFailure` **七個 case**。
- `PanelAction` 加三個 case，補 `kind` 與 `samples`。**不開第四個**——「重新接上」重用 `.connectCodex`。
- `OptionsMenuModel.rows(...)` 多吃 `codex: CodexState`（**不給預設值**）；列數依 §4.6 表：
  `.unavailable`／`.occupiedByOther`／`.blockedByBundlePath` 各零列；`.notConnected`／`.connected`
  各恰一列；**`.connectedStalePath` 依 `pathRejection` 分兩列（nil）／一列（非 nil，只有「移除掛載」）**。
- `nonMenuKinds` 加 `.copyCodexSnippet`，**同步改 `OptionsMenuModel.swift` 的 doc comment**。

**fan-out**：`OptionsMenuModel.rows(` 實測 **26 處、跨 10 個檔**，含
`L10nProductionCallSitesPassLanguageTests` 與 `HelpDocOptionsRowCoverageTests`。
測試呼叫點一律傳 `codex: .unavailable`。

**gates**：CX19（定義域由五個維度乘積推導）、CX20（逐 `CodexStateKind` ＋ 兩種 Rejection 斷言
列數與 action）、CX21、**CX34**。
**mutation**：① `symlink` 併進 `.notConnected` → CX19 紅；② 判定表第 2／3 列對調 → CX19／CX34 紅；
③ `.unavailable` 也給「接上 Codex」→ CX20 紅；④ **被拒時仍給「重新接上」→ CX20 紅**；
⑤ `from` 忽略 `currentExpectedContents` → CX34 紅；⑥ `.connectCodex` 塞進 `nonMenuKinds` → CX21 紅。

---

## T08 `PanelModel` 欄位 ＋ 呼叫點機械更新

- `PanelModel` 加**三個**欄位：`codex: CodexState`、`codexSnippet: String?`、
  **`codexPathRejection: CodexHookPathCheck.Rejection?`**；`make(...)` 新參數**不給預設值**。
  **第三個欄位是主管問題 4 的裁決**（spec §3）：`pathRejection` **不進任何 case 的 payload**，
  它是橫跨 `.connectedStalePath` 與 `.occupiedByOther` 的 UI 輸入（R-10 給不給 snippet 也看它）。
- **替換 T07 在 `OptionsSectionView` 留下的 stub**：那裡硬編 `codex: .unavailable, codexPathRejection: nil`
  （貼著 `AURA_CODEX_PENDING_T08`），本 task 換成 `model.codex`／`model.codexPathRejection`。
  **這個 stub 的失效是靜默的**——`.unavailable` 正是目前所有測試期待的值，忘了替換不會有任何一條紅，
  後果是「使用者裝了 Codex、面板開了、Options 裡什麼都沒有，而全套測試綠」（T07 review M1）。
- **61 個 `PanelModel.make(` 呼叫點、26 個檔**（動工時重新數一次並記在報告裡）。
  測試呼叫點一律傳 `.unavailable`／`nil`；生產呼叫點傳真實狀態。
- 改完 `wc -l` 檢查那 26 個檔沒有越過 300 行（`PanelPixelTests` 275、`Phase2EvidenceRenderer` 194
  且有 15 個呼叫點最接近）。`PanelViewModelTests` 288 行，CX22 的 model 半寫不下就放
  `CodexRowLabelPixelTests`（不要刪既有註解騰空間）。

**gates**：既有 `panelModelMakeHasNoDefaults` 繼續綠；CX22 的 model 半；
**CX46 `optionsRowsCallSitePassesRealCodexState`**（新）——來源掃描，`Sources/` 不得出現字面
`codex: .unavailable` 或 `codexPathRejection: nil`，比照既有 `L10nProductionCallSitesPassLanguageTests`
（那條 gate 存在的理由與這裡一模一樣：生產呼叫點必須傳真的值，不能傳寫死的）。
**test-edit scrutiny**：`#expect(` 淨數量**不得下降**；報告附改前／改後總數（基準 **1649**，量法見 DoD #2）。
**mutation**：① `make` 忽略 `codex` → 由 T09／T10 的 gate 抓（本 task 先記）；
② `agentLabel` 對 `.claude` 也給值 → CX22 紅；
③ **把 view 那一行改回 `codex: .unavailable, codexPathRejection: nil` → CX46 紅**。

---

## T09 View 層 ＋ `L10nCodex`

- **所有新的中文字面必須住在 `Sources/AuraCore/L10nCodex.swift`** 並登記進 `L10nRegistry.allEntries`。
  至少涵蓋：六態說明句、**兩種 `Rejection` 的文案**（`.unsupportedCharacter` 要能把字元插進句子）、
  **`.connectedStalePath` 的兩句**（有／無 `pathRejection`）、**snippet 被扣住時的那句**（R-10）、
  「重新接上 Codex」列標題、七個 `CodexFailure` 的 banner 文案。產品名「Codex」走 `Agent.label`。
- **以真實作取代 T07 的 stub**：`OptionsSectionView.swift` 的 `OptionsRowIconView.systemName(for:)`
  三個新 case 在 T07 是暫定 icon（§0「套件必須維持可編譯」），本 task 換成正式的。
- **列標籤放在既有的第一行 `HStack`**，不另起一行（D-l）。
- `CodexSectionView` 依 §4.6 表分支（六態 ＋ 兩種 Rejection ＋ snippet 有無）：
  - `.notConnected` → 單行提示 ＋ 按鈕（R-3），**不吃 `InstallState`**。
  - `.connectedStalePath`：`pathRejection == nil` → 「App 移動過」＋按鈕；
    **`!= nil` → 「這份設定指向另一個位置的 AgentAura；這個副本跑在一個下次開機就會消失的位置」
    ＋出路，不給按鈕**（R-9）。**文案不預設成因**（r4 m2）：使用者同時有正本與一份 DMG／備份副本時，
    從副本啟動就會落進這一列，而 App 其實**沒有**移動過。
  - `.occupiedByOther`：`codexSnippet != nil` → 說明＋snippet＋「複製」；
    **`== nil` → 說明＋「先把 App 移到『應用程式』，我們才給得出一份不會過期的設定」**（R-10）。
  - `.blockedByBundlePath(.unsupportedCharacter(c))` → 解釋 ＋ **指名那個字元** ＋ snippet ＋「複製」。
  - `.blockedByBundlePath(.mustMoveToApplications)` → 解釋 ＋ 移動指示，**不給 snippet**（D-s）。
  - `.unavailable`／`.connected` → 不畫。
  按鈕**必須用 `.borderless`**（離屏渲染下 `.bordered` 會被包進 `_FocusRingView` 而走訪不到）。
- 新增按鈕會動到既有離屏測試的**位置索引斷言**——逐一檢查 `FooterPixelTests`／`OptionsExpandTests`，
  報告列出檢查結果。

**gates**：CX22 像素半、**CX23**、**CX36 `codexSectionRendersEveryState`**（六態 ＋ 兩種 Rejection
各渲一次；`.unavailable` 不畫任何東西）。
**CX36 的定義域必須走 `CodexState.samples(.blockedByBundlePath)`，不要直接迭代 `Rejection`**——
它是**兩層 samples 鏈的第一個真正的消費者**（T07 review m1 實測：在 T09 之前把那兩個代表值改成
單一值，全相關 suite **全綠**，因為兩個 Rejection 在 `rows` 層行為完全相同、都是零列，
`kind` 又把它們收斂成同一個）。所以 **CX36 必須能分辨它們**：一個給 snippet ＋「複製」、一個不給（D-s）。
**CX36 的定義域必須走 `CodexState.samples(.blockedByBundlePath)`，不要直接迭代 `Rejection`**——
它是**兩層 samples 鏈的第一個真正的消費者**（T07 review m1 實測：在 T09 之前把那兩個代表值改成
單一值，全相關 suite 全綠，因為兩個 Rejection 在 `rows` 層行為完全相同、都是零列，`kind` 又把它們
收斂成同一個）。所以 CX36 **必須能分辨它們**：一個給 snippet ＋「複製」、一個不給（D-s）、既有 `RowHeightDerivationTests`／
`FooterPositionStabilityTests`／`OptionsExpandTests` 繼續綠。
**mutation**：① 標籤另起一行 → CX23 紅；② `CodexSectionView` 在 `.unavailable` 也畫 →
`OptionsExpandTests` 的高度斷言紅（**特別確認**：沒紅代表「`.unavailable` 畫面零 diff」沒有守衛，
要補一條）；③ snippet 改成手寫字串 → 「snippet 與產生器同源」斷言紅；
④ **錯誤文案不插字元（籠統句）→ CX36 紅**；⑤ **被拒時仍畫「重新接上」按鈕 → CX36 紅**。

---

## T10 `AppDelegate` 接線 ＋ `CodexHookStore` ＋ `Uninstaller`

**第一步（純搬移，獨立 commit）**：`AppDelegatePanelActionsWiredTests.swift` **恰好 300 行**，
新增 `AppDelegateCodexWiredTests.swift`。**零行為變更**：`swift test` 綠（除既有 pending 紅）、
`#expect(` 總數不變。
（**原本的第一步 (1)** ——`AppDelegate+Links.swift` 的純搬移——**已於 r9 提前到 T07**，
理由見 T07 第一步 (b)：那個檔的窮盡 `switch` 必須與加 case 在同一個 task 裡編得過。）

**第二步**：
- `CodexHookStore`（`@MainActor` ＋ 注入 `UserDefaults`）：key `AgentAuraCodexHookContents`，
  值＝寫出去的 JSON 文字；`contents: Data?`／`write(_ bytes: Data)`／`clear()`。**不算 hash**。
- **以真實作取代 T07 的 stub**：`AppDelegate+PanelActions.swift` 的 `switch action` 三個新 case
  在 T07 是 `break`（§0「套件必須維持可編譯」，貼著 `AURA_CODEX_PENDING_T10`），本 task 換成真的接線。
  **驗收必含：既有 `panelActionsAreWired` 對三個新 kind 從紅轉綠**——它從 T07 起就誠實地紅著，
  那是 tested≠wired 守衛在等這一刻；報告要附轉綠前後的輸出。
- **驗收必含：把 `verifyCodexActionsAreStubbed` 換成三個 kind 各自的「真副作用」斷言，並改名**
  （T07 review m3）。T07 用 `banner != nil` 是當時唯一不弱化的選擇，但 T10 之後**任何** banner 都能
  滿足它，函式名也會變成謊言。特別注意 **`.copyCodexSnippet` 的真實副作用是寫剪貼簿、不一定設 banner**
  ——屆時的壓力會是「把斷言放寬成 `banner != nil`」，**那是弱化**；正確的動作是斷言對準剪貼簿注入縫。
- **`AppDelegatePanelActionsWiredTests.swift` 現在是 300/300、零餘裕**（T07 是靠刪一行空行塞進新 case 的）。
  本 task 動它時，**把一兩個既有 case 的驗證體也搬進 `+Codex.swift`，留出 20–30 行餘裕**；
  **不准刪註解或空行擠**（那正是 r3 標過的形狀的輕量版）。
- `AppDelegate+Codex.swift`：
  - **五個行程常數欄位（D-t）**，在 `applicationDidFinishLaunching` 算**一次**：
    `translocated`／`inDownloads`／`pathRejection`／`currentExpectedContents`／`codexSnippet`
    （後者 = `pathRejection == .mustMoveToApplications ? nil : CodexHooksJSON.snippet(...)`，R-10）。
    理由：五者都是 `Bundle.main.bundleURL` 的純函式；r3 讓每次 `onOpen` 都重算一次
    `SecTranslocateIsTranslocatedURL` ＋ 兩次 `resolvingSymlinksInPath` ＋ 產 12 個事件的 JSON。
  - `reprobeCodex()` **只重做檔案系統那一段**：`installer.probe()` → `CodexState.from(obs,
    recordedContents: store.contents, currentExpectedContents: 欄位, pathRejection: 欄位)`。
    **四個時機**：① launch 同步區（第一次 `refreshPanel()` **之前**）② popover `onOpen`
    ③ `performConnectCodex()` 之後 ④ `performDisconnectCodex()` 之後。
  - **`performConnectCodex()` 第一行是 guard（R-9）**：
    `guard pathRejection == nil else { banner = .error(對應文案); refreshPanel(); return }`
    ——**在任何 `disconnect` 之前**。接著才是「若 `.connectedStalePath` 先 disconnect」再 connect。
    **這個 guard 不是為了少一次失敗，是為了不要先刪檔**：r3 的順序在 translocated 下會
    `disconnect` 成功（內容確實相符）→ 檔案被刪、`store.clear()` → 然後 `connect` 才撞上執行層 guard。
  - 生產預設 `codexHome` = `FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".codex")`（**不得用 `environment["HOME"]`**）。
- 剪貼簿走注入縫 `writeToPasteboard: @MainActor (String) -> Void`。
- 接上成功的 banner 必須**同時**含「下一個 Codex session 起生效」與「Codex 會問你信任」（D-m）。
- `Uninstaller.run()` 在 `erasePersistentDomain()` **之前**多一步
  `codexInstaller.disconnect(ifContentsEqual: store.contents)`（`try?`，D-n）。

**驗收必含：解除 `#if AURA_CODEX_PENDING_T10`**（同 T05 的理由與要求：報告附解除前／後的
`#expect` 數與測試函式數，只准上升；殘留由 CX44 把關）。

**gates**：**CX24**（五段）、CX25、CX26、**CX31**、**CX35**（前提：`pathRejection == nil`）、
**CX39 `codexReconnectNeverDisconnectsWhenPathIsRejected`**（注入 `.connectedStalePath` ＋
`translocated: true` → 送 `.connectCodex` → **`disconnect` 呼叫次數 0**、檔案仍在、
banner 是 `.mustMoveToApplications` 那句）、**CX40 `codexSnippetIsWithheldWhenPathWillVanish`**
（乘積表 `CodexStateKind.allCases × [nil, .mustMoveToApplications, .unsupportedCharacter(" ")]`，
斷言 `.mustMoveToApplications` **整行** `codexSnippet == nil`，含 `.occupiedByOther`）、
**CX42 `bothSidesNeverDisturbEachOthersCredentials`**（見下）、
既有 `panelActionsAreWired` 涵蓋三個新 kind。

**CX42（R-8 不變式 1 的憑證半，r4 M3）**：CX37a／CX37b 住 AuraHookFile，只看得到**檔案**那一半；
`InstallState` 還吃 App 層的三個 `AgentAuraHook*` 鍵、`CodexState` 還吃 `AgentAuraCodexHookContents`。
風險就在那一半：`performDisconnect()`（Claude）清到 Codex 的鍵、`performConnectCodex()` 寫到
Claude 的鍵、或新程式碼順手 `removePersistentDomain`——**全是 r4 才新增的程式碼**。
- 定義域：`{performConnect, performDisconnect, performConnectCodex, performDisconnectCodex}` 的
  **全部長度 ≤ 2 序列＝4 ＋ 16 = 20 條**（程式推導，**不手列**）。
- 用既有的 fake installer／fake store ＋ 注入的 `UserDefaults` suite，**全記憶體、零 spawn**。
- 每步之後斷言：**另一側的鍵位元組完全不變**（Claude 側三個 `AgentAuraHook*` vs Codex 側
  `AgentAuraCodexHookContents`），且該 suite **沒有其他鍵被新增或刪除**——用鍵集合的**差集**斷言，
  **不逐鍵列舉**（鍵清單會 drift）。
- doc comment 要與 CX37a／CX37b **互相點名**（「不變式 1 的另一半在那裡」），
  否則下一個人讀到 CX37a／CX37b 會以為整條不變式都守住了。

**mutation**：① `.connectCodex` 分支改 `break` → CX24① 紅；② banner 只留一句 → CX24④ 紅；
③ 拿掉 `onOpen` 的 `reprobeCodex()` → CX24⑤ 紅；④ `codexHome` 改成 `environment["HOME"]` → CX25 紅；
⑤ codex disconnect 與 `erasePersistentDomain` 對調 → CX26 紅；⑥ `write` 裡加 `trimmingCharacters`
→ CX31 紅；⑦ stale 時直接 `connect`（不先 disconnect）→ CX35 紅；
⑧ **把 R-9 的 guard 移到 `disconnect` 之後 → CX39 紅**；
⑨ **拿掉 `codexSnippet` 的條件（無條件給 snippet）→ CX40 紅**；
⑩ **`performDisconnect()` 順手 `defaults.removeObject(forKey: CodexHookStore.key)` → CX42 紅**。

---

## T11 scripts ／ 文件 ／ 正典回寫

- `scripts/verify-uninstall.sh`：新增第 7 項（`${CODEX_HOME:-$HOME/.codex}/hooks.json` 存在**且**含
  `--agent codex` → FAIL）；**必須可以單獨執行**（`--only <n>`）——第 1–6 項查**真實** `$HOME`，
  開發機上本來就會 FAIL、整支本來就非零退出，用整體 exit code 當判準 mutation 不會紅；
  整支還會跑 `osascript`（權限提示）與 `sfltool dumpbtm`（註解寫實測 39 秒）。
  `CODEX_HOME` **不是給使用者的介面**，註解寫明。**順手修第 2 行「五個殘留位置」的註解**。
  既有六項的文字不得變。
- `docs/INSTALL.md` ＋ `.zh-TW`：新增「Using it with Codex」；troubleshooting 加兩條
  ①「燈不動？先確認 Codex 有沒有問過你信任」②「想確認 Codex 有沒有讀到這個檔：把 `timeout`
  暫時改成 5，下一個 session 的 stderr 會出現 clamping 警告（F13）；確認完改回 3」。
- `README.md` ＋ `.zh-TW`：「What it does to your Mac」加 `~/.codex/hooks.json`。
- `SECURITY.md`：「What this tool can do on your machine」加同一條；「Boundaries that are enforced
  by tests」加「`config.toml` 位元組不變、差異集合恰為 `{hooks.json}`」**與「兩側互不干擾」（R-8）**。
  **注意**：`SECURITY.md` 沒有叫「What it does to your Mac」的段落（那是 `README.md:160`）。
- `Resources/help-*.html` 兩份：新增 Codex 段（CX28 強制涵蓋**每一個**新的 Options 列標題，
  含「重新接上 Codex」）。
- `CLAUDE.md`：Project 狀態、Invariants（**三條**，含 R-8 的「對任一側的安裝操作不得改動另一側的
  任何位元組」）、Tier 1 清單（三個檔）。
- 正典：§2.1／§2.2／§3.2／§3.4／§3.5／§3.7／§9 **七處**回寫（§3.4 是 `Jargon` 那條、
  §3.5 要帶 F15 的**範圍限定**、§3.2 要帶 R-8 的不變式）。

**gates**：CX27（暫存 `CODEX_HOME` ＋ `--only 7`，**判準是那一行的 PASS/FAIL**）、CX28、CX29、CX30。
**mutation**：① 拿掉腳本第 7 項 → CX27 紅；② **只刪掉其中一個 Codex 列標題** → CX28 紅；
③ 從 SECURITY.md 刪掉 `.codex/hooks.json` → CX29 紅；④ 腳本加一行 `codex exec` → CX30 紅。

---

## T12 整合 ＋ DoD

**本 task 新增一條 gate**：**CX44 `noPendingFlagRemains`**——來源掃描，**`Sources/` ＋ `Tests/`** 都不得殘留
`AURA_CODEX_PENDING`（比照既有 `noStrayLiteralOutsideAllowlist`／CX30 的形狀，
**含暫存目錄正向對照**證明掃描沒壞）。理由：T05／T10 的驗收已經要求解除，但那靠人記得；
有這條就不靠人記得。**mutation**：在 **`Sources/` 與 `Tests/` 各留一個** `AURA_CODEX_PENDING_T08` 標記 → **兩處都要紅**
（只掃 `Tests/` 的話，T07 那四個 stub 裡有三個在 `Sources/`，掃不到）。

跑 DoD 帳本全表：`swift test` 全綠（含**修好** `everyFixtureModelIsMapped`）且連跑 3 次 0 flake、
gate mutation 帳（**46 條**，抽驗 5 筆現場重跑）、`Sources/` 淨增（**逐檔列「估／實」兩欄**，
不是只看總數——T02 review m4：`Agent.swift` 估 60／實 80（+33%，多出來的是 review 要求的
doc comment，**不該砍**），單一個檔就吃掉 20 行餘裕；漂移要看得見）、單檔行數、執行檔增量、
`reprobeCodex()` 成本、啟動時間增幅、`claude plugin validate --strict`、`verify-install.sh`、
`verify-uninstall.sh`、**`plugin/hooks/hooks.json` 的 git diff 必須為空**、
`~/.codex/config.toml` 自動化側位元組不變。產出實機清單 ①–⑧。Tier 1 → integrator 綠後派 persona-tester。

---

## 2. 已知風險（開工前就知道，不是驚喜）

1. **`Interrupt` 進 `handledEvents` 會讓 Claude 側整份 hooks 靜默失效**——症狀是「什麼都沒發生」。
2. **`Interrupt → idle` 沒有天然的 fixture 證人**（round4 零筆），CX4 是唯一守衛。
3. `hooks.json` 是 symlink 指向 `config.toml` 時，「先 stat 再寫」會覆蓋使用者設定（CX15 那一格）。
4. **產生器一旦偏離 F14，Codex 根本不會載入，而自動化抓不到**（F12）。
5. **寫進一個下次開機就消失的絕對路徑**：R-5 三層 guard。
6. **「重新接上」先刪掉使用者還在運作的檔**（r3 B1）：R-9 的前置 guard ＋ 面板不給按鈕 ＋ CX39。
   **保本動作擋不住「在錯誤的時機正確地執行」**——`disconnect` 的兩道保護在那個情境下全部生效。
7. **把一份會過期的 snippet 交給最會照著貼的 persona**（r3 M1）：R-10 ＋ CX40 的乘積表。
8. **App 搬家後 `.connected` 永遠成立**：R-6；偵測延遲到下一次 `reprobeCodex()`（§10-12）。
9. **憑證 round-trip 壞掉 → 永遠刪不掉自己的檔 → 完整移除留殘留**：CX31。
10. **`reprobeCodex()` 漏接會讓功能 tested≠wired**：CX24⑤。
11. **兩側互相干擾**（R-8）：不變式 1 由 **CX37a／CX37b（檔案）＋ CX42（憑證）共同守**，
    缺一條就只守到一半；不變式 2 由 CX38 ＋ 實機 ⑧。
12. **`everyFixtureModelIsMapped` 目前是紅的**：本 change 必修，不是弱化對象（T05 §4.9）。
13. **94 個呼叫點的機械改動**最容易夾帶弱化。
14. **三個檔已經在上限**——沒先拆就動它們，最省事的動作是刪註解擠進去。
15. Codex 端到端只有實機能驗；報告與 spec 都不得用「已實測」描述它。
