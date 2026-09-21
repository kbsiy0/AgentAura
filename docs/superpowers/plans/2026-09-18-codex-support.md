# `codex-support` 實作計畫

> spec：`docs/superpowers/specs/2026-09-18-codex-support-design.md`（**r14**）
> 證據：`docs/2026-09-18-codex-hook-probe.md`（**F1–F15**，F15 以 `8fdce0b` 的版本為準）·
> persona r1 報告（2026-09-21，**NO-GO 5.68／6.0**）· 證據圖 `docs/evidence/codex/INDEX.md`
> 分支：`change/codex-support`　Tier：**1**（動 `Sources/AgentAuraApp/**` → integrator 綠後派 persona-tester）
> 節號引用一律指 **r14** 的 spec。
> **gate 編號**：本 change 新增的一律 `CX<n>`（共 **57** 條；CX37 拆成 a／b，CX43 未使用，
> **CX47–CX57 是 T13 的 persona 修復批次**）；提到**既有** gate 一律寫測試函式名。

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
- **負向斷言必須餵正向輸入**（T09 review M1）：斷言「**X 不得出現**」時，輸入必須是
  **若實作錯了 X 就會出現**的那組值——否則那條斷言在任何實作下都成立。
  實例：`.mustMoveToApplications` 那格餵 `codexSnippet: nil` 再斷言「不得畫 snippet」，
  reviewer 把 view 改成會畫 snippet，**紅 0 條**。改成餵真的 snippet 之後，那條斷言才真正在問
  「**給了你 snippet，你還是不准畫出來嗎**」（也才符合 S0-1(ii)：view 是執行層，要自己擋，
  不能只信路由層）。**mutation 必附「把禁令拿掉 → 紅」**，否則不算守住。
  這是本 change 第**三**族「全綠倖存者」——前兩族是「拿生產常數跟自己比」（`timeout`／`agentFlag`）
  與「掃描器口徑比宣稱的窄」（CX46 的跨行寫法）。
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
| T08 | `PanelModel` 欄位 ＋ 63 個呼叫點（機械） | §4.6 | T07 | CX22（model 半）、**CX46** |
| T09 | View 層 ＋ `L10nCodex` | §4.6 | T08 | CX22（像素半）、CX23、**CX36** |
| T10 | `AppDelegate` 接線（**以真實作取代 T07 的 stub**）＋ `CodexHookStore` ＋ `Uninstaller` ＋ **兩側憑證序列不變式** | §4.5、§4.6、§4.8、§6.2 | T06、T09 | CX24–CX26、CX31、CX35、**CX39**、**CX40**、**CX42** ＋ 既有 `panelActionsAreWired` **轉綠** |
| T11 | scripts ／ 文件 ／ 正典回寫 | §8.2 | T07 | CX27–CX30 |
| T12 | 整合 ＋ DoD 量測 | DoD 帳本全表 | 全部 | — |
| **T13** | **persona r1 修復批次（S0×2／S1×7）** | spec r13 §0.4／§3.1／§4.6／§4.10／§4.11 | T12（integrator 綠）＋ persona r1 | **CX47–CX57** ＋ CX24／CX36／CX40 restated |

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
wave 10: T13（persona r1 之後；內部再分三波，見 T13 自己的依賴圖）
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
- **63 個 `PanelModel.make(` 呼叫點、27 個檔**（T08 實測；以**括號配對**量，`grep 'PanelModel\.make('`
  **抓不到隱式成員寫法** `spy.setPanel(.make(icon: …))`）。**這個數字不是驗收條件**（T08 裁決 1）：
  三個新參數都沒有預設值，**編譯通過就證明每個呼叫點都補齊了**；計數只作報告資訊。
  （文字比對數呼叫點／斷言在本 change 已經連錯五次。）
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
  **清查結果要以表列進報告**（哪個檔、哪條測試、靠不靠索引定位、結論），
  **不接受「沒紅所以應該沒事」那種推論**（T09 review m2）——離屏讀不到 `.title` 也讀不到
  `accessibilityIdentifier`，這條檢查是 CLAUDE.md gate 哲學第 5 條直接寫下來的，值得留下紀錄。
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
- **驗收必含：`refreshPanel()` 真的把 `codexState` 交出去**（T08 裁決 3，**取代**「掃 `PanelModel.make(`
  生產呼叫點」那種文字 gate）：讓 `reprobeCodex()` 產出一個**非 `.unavailable`** 的狀態，然後斷言
  `refreshPanel()` 交給 `status.setPanel` 的那個 `PanelModel` 的 **`codex` 等於 `codexState`**、
  **`codexPathRejection` 等於行程常數**。併進 CX24 或 CX35 的段落（CX24 已有 spy 基礎設施）。
  **為什麼不用文字掃描**：`make(` 與 `rows(` 的情況不對稱——`StatusItemController.swift` 的佔位 model
  **永久且正確地**傳 `.unavailable`（popover 掛載前的必要佔位，`contentViewController == nil` 時
  `NSPopover.show` 會丟 NSException 殺行程），文字掃描會對它誤報而需要 allowlist，
  而這個 codebase 對 allowlist 的態度很清楚。行為斷言走真實路徑、對佔位 model 免疫、更難繞過。
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
- **順手清掉一個死分支**（T09 review m3）：`CodexSectionView.swift` 的 `Agent.codex.label ?? "Codex"`
  ——`label` 對 `.codex` 恆為 `"Codex"`，`??` 右側永遠不執行，而它**複製了那個它想避免重複的字面**。
  哪天 `label` 的語意變了（例如改成只在多 agent 並存時才給值），這個 fallback 會**靜默**把舊字面補回去。
  同 D-r 對 `default:` 的態度。**二擇一**：① 加一條 pin test 釘住 `Agent.codex.label == "Codex"`（字面）
  並把 view 改成 `!`；② 給 `Agent` 一個不帶 Optional 的 `displayName` 讓型別說話。
- **驗收必含：補上 `CLAUDE.md` 第三條 invariant（R-8）的第三個 gate 名**
  `bothSidesNeverDisturbEachOthersCredentials`——T11 刻意只列了已存在的兩個（CX37a／CX37b），
  因為 CX42 排在本 task；交付後回去補，那條 invariant 才完整（T11 review m2）。
- `Uninstaller.run()` 在 `erasePersistentDomain()` **之前**多一步
  `codexInstaller.disconnect(ifContentsEqual: store.contents)`（`try?`，D-n）。

**驗收必含：解除 `#if AURA_CODEX_PENDING_T10`**（同 T05 的理由與要求：報告附解除前／後的
`#expect` 數與測試函式數，只准上升；殘留由 CX44 把關）。

**gates**：**CX24**（五段）、CX25、CX26、**CX31**、**CX35**（前提：`pathRejection == nil`）、
**CX39 `codexReconnectNeverDisconnectsWhenPathIsRejected`**（注入 `.connectedStalePath` ＋
`translocated: true` → 送 `.connectCodex` → **`disconnect` 呼叫次數 0**、檔案仍在、
banner 是 `.mustMoveToApplications` 那句）、**CX40 `codexSnippetIsWithheldWhenPathWillVanish`**
（乘積表 `CodexStateKind.allCases × [nil, .mustMoveToApplications, .unsupportedCharacter(" ")]`，
斷言 `.mustMoveToApplications` **整行** `codexSnippet == nil`，含 `.occupiedByOther`）。
**（r13／T13c 之後這條已改名 `codexSnippetIsWithheldForEveryPathRejection` 且期望值整欄翻轉
——上面是 T10 當時的樣子，保留當歷史；要找那支測試請用新名字。）**

**⚠️ 注意：R-10（snippet 被扣住）目前在任何一層都還沒有守衛**——CX40 尚未存在，而**決策點與
它的 gate 落在同一個 task**（就是本 task）。也就是說，在 CX40 寫出來之前，「`.occupiedByOther`
＋ translocated 時不給 snippet」這件事沒有任何東西擋著；它正是 r3 M1 指出的那扇側門。
**先寫 CX40（RED）再寫實作**，不要反過來。
**CX40 的 mutation 措辭**：「讓 `reprobeCodex` 在 `.mustMoveToApplications` 時**仍然給 snippet**
→ CX40 必須紅」（T09 review m1）。view 層那一半的守衛由 CX36 的第③格 mutation 負責，
兩層要一起看——**D-s 在這兩者落地之前零強制力**。

其餘 gates：
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
  **CLAUDE.md 的 Invariants 只准指名*已存在*的 gate**（T11 review m2）：它每個 session 都會被載入，
  而本專案的紀律是「文件指名一個 gate 就是在宣稱它存在」。R-8 那條**本輪只列 CX37a／CX37b 兩個**；
  第三個 `bothSidesNeverDisturbEachOthersCredentials`（CX42）**等 T10 交付後再補**
  ——CLAUDE.md 是 invariant 清單，不是計畫表。
- 正典：§2.1／§2.2／§3.2／§3.5／§3.7／§9 **六處**回寫（§3.5 要帶 F15 的**範圍限定**、
  §3.2 要帶 R-8 的不變式）。
- **`Jargon` 那條不在正典**：它要回寫的是 **app-shell spec（`2026-09-10-app-shell-design.md`）§3.4
  文案映射（M-7，D-c）**——兩份 spec 撞章節號，而 `Jargon.swift` 第 3 行的麵包屑指的是 app-shell
  那一份（T11 review m3）。回寫要落在被指名的那份文件上，否則照麵包屑找過去會看不到。

**gates**：CX27（暫存 `CODEX_HOME` ＋ `--only 7`，**判準是那一行的 PASS/FAIL**；**外加兩格參數驗證**，
見下）、CX28、**CX29（三份文件參數化）**、**CX30（roots 含 `.github/`）**。

**`--only` 的參數驗證（T11 review M1，腳本要改、gate 要補兩格）**：
- 實測 `--only 77`／`--only 0`／`--only seven`：**一項都沒跑，然後印「完整移除驗收 PASS」**
  （`should_run()` 是純字串比對，對不上就全跳過，而最後那句 `echo PASS` 不在任何 `should_run` 裡）。
- 實測 `--only`（缺值）：**無限迴圈、零輸出**（`--only)` 分支無條件 `shift 2`，bash 在 `$# < 2` 時
  `shift 2` 不改 `$#` 也不中止，而腳本只有 `set -uo pipefail` 沒有 `-e`）。
- **這直接違反腳本第 4 項自己寫下的原則**——那一項為了不把「問不到」誤當「通過」特地多寫了
  `LOGIN_ASKED`，而 `--only` 把同一個錯犯在**整支腳本的總結論**上；它正是「移除乾淨是測試能力的
  前提」那條 invariant 的驗收工具。
- 修法：`while` 迴圈後加值域檢查（`[1-7]`，否則印用法並 `exit 2`），`--only)` 先確認有值。

**mutation**：① 拿掉腳本第 7 項 → CX27 紅；② **只刪掉其中一個 Codex 列標題** → CX28 紅；
③ 從 **`SECURITY.md`／`README.md`／`README.zh-TW.md` 任一份**刪掉 `.codex/hooks.json` → CX29 紅
（三份各試一次——T11 review m1 實測：兩邊都刪當時只紅 1 條）；④ 在 `scripts/` 或 **`.github/`**
加一行 `codex exec` → CX30 紅；⑤ **拿掉 `--only` 的值域檢查 → CX27 的新格必須紅**。

---

## T12 整合 ＋ DoD

**本 task 要補兩份清查**：① **位置索引斷言的清查表**（T09 若未附，在這裡補齊：哪個檔、哪條測試、
靠不靠索引定位、結論）；② `docs/INSTALL.md` 的「Codex: the light never moves」那一節**補一句
「Codex 沒有 error 燈」的交叉引用**（T11 review m4：那節標題就叫「燈不會動」，正是「我跑失敗了
燈卻沒變紅」的使用者會查的地方，而它目前只解釋了信任提示；help 兩個語言版本都已有明講）。

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

## T13 persona r1 修復批次（S0×2／S1×7）

> spec r13 §0.4（D-v–D-ad）· §3.1（雙 agent 狀態字串矩陣）· §4.6（六態表）· §4.10（高度天花板）·
> §4.11（確認框）· §6.3（CX47–CX57）· §9.1（persona 對應）· §10-17–22（新 known gaps）。
> persona r1 報告全文是本 task 的**需求來源**，不是背景資料——每一條 S0／S1 都要能指回一個子項。

**r14 折入 r13 review（0 BLOCKING／3 MAJOR／5 minor）**：九條決策一條都沒被推翻，改的是
**CX56 的定義域**（補 `install`×`banner` 兩維 ＋ snippet 下限 ＋ 先量後定）、
**CX51 的方法**（三處渲染同一個字串，`contains` 分辨不出是哪一處壞了 → 三條可分辨斷言）、
**並行圖的事實錯誤**（`PanelModel*.swift` 上三個子項互撞），以及五條 minor。
**T13i 的基準表要在派工前先量**——它會決定 780 這個產品數字是否維持。

**這批的性質**：persona r1 判 **NO-GO**（加權 5.68／門檻 6.0；兩條 S0；P2 = 5.2 低於自己的 ≥6 硬下限）。
**四個 persona 裡三個的失分不是來自 Codex 功能做錯，而是來自既有的 Claude-only 表面沒有跟著新訊號更新**
——所以本 task 大部分的 diff 落在**不是這個 change 寫的碼**上（`effectiveBanner`／`PanelModel.title`／
`PanelFooterView`／`emptyRowsMessage`）。**改既有推導時，「Codex 不在場時位元組不變」是每一條的第一個斷言**。

### T13 的共同規則（在 §0 之上再加四條）

1. **每個子項一個 commit**，型別 `fix(codex)` 或 `feat(codex)`；commit 訊息第一行點名它關掉哪一條
   persona finding（例如 `fix(codex): S0-1 接上 banner 不再被 Claude 的列抹掉`）。
2. **先 RED 再實作，而且 RED 要打在「r12 的實作」上**。這批每一條 gate 都有一個共同性質：
   **它必須在 r12 的程式碼上是紅的**。寫完測試先跑一次確認紅（不是編譯錯）、記下輸出，再動生產碼。
   任何一條「寫完測試就已經綠」的，代表它守錯了東西，**停下來重寫測試，不要往下做**。
3. **負向斷言必須餵正向輸入**（§0 既有規則，本批特別容易踩）：CX49「不得畫 snippet」必須餵**真的**
   `codexSnippet`；CX48 的負向對照（Codex 列出現時 banner 該退場）必須真的放一列 Codex 的 session。
4. **不新增任何 SwiftUI view 型別**（DoD #11 執行檔已超標約 3 倍、#7 已超 377 行）。
   修法只准落在四類：`PanelModel` 的推導字串／`L10n*` 的文案／既有 view 內的分支與修飾子／一個注入縫。
   **每一行都要有理由**——`Sources/` 增量逐檔記在報告裡（spec §8.1 的 r13 表是估算，報告填「實」）。

### 子項與依賴

```
兩條可以並行的鏈（r14 更正，見下方衝突檔表）：

鏈 A（AuraCore 的 PanelModel*.swift，**必須序列**）
  T13b（S0-1 banner）→ T13f（S1-1 狀態字串）→ T13g（S1-2 空列句）

鏈 B（Codex 文案與卡片，**必須序列**）
  T13c（S0-2 決策層，CodexHooksJSON）→ T13d（S0-2 view＋文案）→ T13e（S2-1 stale 拆句）
      → T13h（S1-3 合併指示＋help）→ T13i（S1-4 高度天花板）

獨立：T13a（純搬移）→ T13j（確認框）

收尾（全部之後，序列）：T13k（文件／CLAUDE.md）→ T13l（證據圖重渲）
```

**r13 的並行圖是錯的**（review M3）：它寫「T13b／T13c／T13f 彼此獨立，可並行（**不同檔**）」，
但 T13b 與 T13f **改的是同樣兩個檔**，T13g 也改其中一個。**「不同檔」那句是事實錯誤，已刪除。**
照字面派工會在共享工作目錄上撞車，而本專案有明確的實證事故紀錄（未追蹤檔被別人的廣域
`git add` 掃走、branch 指到錯的 commit）。

**衝突檔表（派工前逐列看一次）**：

| 檔 | 被哪些子項改 | 處置 |
|---|---|---|
| `Sources/AuraCore/PanelModel+ConnectCTA.swift` | **T13b、T13f** | 鏈 A 內序列 |
| `Sources/AuraCore/PanelModel.swift` | **T13b、T13f、T13g** | 鏈 A 內序列 |
| `Sources/AgentAuraApp/CodexSectionView.swift` | T13d、T13e、T13h、T13i | 鏈 B 內序列 ✓ |
| `Sources/AuraCore/L10nCodexCards.swift`（新） | T13d、T13e、T13h | 鏈 B 內序列 ✓ |
| `Sources/AgentAuraApp/AppDelegate.swift` | T13a、T13j | 本來就序列 ✓ |

**鏈 A 與鏈 B 之間零交集**，可以並行——但**若要真的同時派兩個 agent，兩條鏈各開一個
`git worktree` 再 merge 回 change branch**，不要在同一個工作目錄上同時跑（user-level CLAUDE.md
的既有規則）。T13a／T13j 那條最短，可以插在任一條鏈的空檔。

---

### T13a 純搬移：`applicationDidFinishLaunching` → `AppDelegate+Lifecycle.swift`（零行為變更）

- **為什麼要先做**：`AppDelegate.swift` 是 **196/200**，T13j 要加一個 stored property ＋ init 參數 ＋
  預設值 ＋ 指派（約 +8 行）會直接撞上限。照 spec §8.1 既有規則：**先做一次零行為變更的純搬移 commit**。
- **搬什麼**：`AppDelegate.swift:119-195` 的 `applicationDidFinishLaunching(_:)` 整個函式，
  搬進 `AppDelegate+Lifecycle.swift`（目前 23 行，`applicationWillTerminate(_:)` 已經住在那裡
  ——**這證明 `NSApplicationDelegate` 的方法放在 extension 在本 repo 可行**，不是理論推測）。
- **禁止**：刪註解、刪空行、改函式名、改函式體任何一個字元、順手 refactor。
- **驗收必含**：`swift test` 綠（與搬移前同一組結果）；`grep -rho '#expect(' Tests | wc -l` **不變**；
  `git diff --stat` 只有兩個檔、增減行數對稱；`IsolationTests.fileLengthLimit` 綠
  （`AppDelegate.swift` ≈ 126、`AppDelegate+Lifecycle.swift` ≈ 101，兩者都在 200 以內）。
- **gate**：無新 gate（純搬移）。**但要當場重跑** `AppDelegateFirstRunTests`／
  `AppDelegateOnOpenTests`／`CompositionSmokeTests`／`AppDelegateCompositionInjectionTests`
  ——它們是「啟動序列還對不對」的既有證人。

---

### T13b　S0-1：`.codexConnected` banner 自己的 kind ＋ 自己的退場條件（D-v）

- **改哪些檔**：
  - `Sources/AuraCore/PanelModel.swift`：`PanelBanner.Kind` 加 `codexConnected`；
    `PanelBanner.codexConnected(language:)` 改用它（約 +4）。
  - `Sources/AuraCore/PanelModel+ConnectCTA.swift`：新增 `hasCodexRow`；
    `effectiveBanner` 依 kind 分流（約 +20，含理由 doc comment）。
- **`hasCodexRow` 的判斷式**：`rows.contains { $0.agentLabel == Agent.codex.label }`，
  **不是 `agentLabel != nil`**——第三種 agent 進來時這個判斷仍然只認 Codex。
  （`Agent.codex.label` 恆非 nil，已由既有 `CodexRowLabelTests.codexLabelIsPinnedToLiteralCodex` 釘住字面。）
- **開工前先確認的事**（10 分鐘，寫進報告）：全 repo 對 `PanelBanner.Kind` **沒有窮盡 `switch`**
  （2026-09-21 掃描：只有 `AppDelegate+Verification.swift:104`／`BannerView.swift:36`／
  `PanelModel+ConnectCTA.swift:70` 三處 `==` 比較）。**這是待驗證的宣稱，不是背景知識**——
  實跑 `grep -rn "\.kind" Sources/ | grep -i banner` 確認，再動手。若真的出現窮盡 switch，
  那是 §0「套件必須維持可編譯」的情境，同一個 commit 處理掉。
- **gates**：
  - **CX47 `codexConnectedBannerOnlyRetiresOnCodexRow`**（AuraCore，`PanelModelTests` 或新檔
    `CodexBannerLifecycleTests.swift`）。定義域 `PanelBanner.Kind.allCases` ×
    {空／只有 Claude 列／只有 Codex 列／兩者都有}，**程式推導**。
    **mutation**：① `.codexConnected` 改用 `!rows.isEmpty`（＝ r12 行為）→ **必須紅，≤ 5s**；
    ② `hasCodexRow` 改成 `agentLabel != nil` → **預期綠（等價 mutant）**，報告要寫出來並說明
    它守的是未來的第三種 agent，不是今天的行為。
  - **CX48 `codexTrustWarningIsDrawnWithClaudeRowsPresent`**（App，`CodexWiringSmokeTests+Banner.swift`
    或 `CodexSectionViewTests` 同族的新檔）。用既有 `leafStrings(_:)` 掃**整個 `PanelView(model:).body`**。
    正向：`banner = .codexConnected` ＋ `rows = [一列 Claude 的活 session]` → 兩個關鍵詞都在。
    負向對照：`rows = [一列 Codex 的活 session]` → 兩個關鍵詞都不在。
    **mutation**：① `codexConnected` 改回 `kind: .connected` → **必須紅，≤ 10s**（這就是 persona 抓到的那行）；
    ② 刪掉 `effectiveBanner` 的 `.codexConnected` 分支 → 必須紅；
    ③ 讓 banner 永不退場 → **負向那格必須紅**（沒有它，「永不退場」是綠的）。
- **驗收必含**：CX24④ 的 doc comment 補一句指向 CX48（「儲存值那一半在這裡，畫面那一半在 CX48」），
  **兩條互相點名**（同 CX37a／CX37b、CX9 兩層的既有做法）。
- **禁止**：把 `effectiveBanner` 的 A7 條件整個拿掉讓 Claude banner 也永遠留著。
  那是**弱化既有行為**（A7 修掉的是 banner 在條件兌現後還佔著頂端 40pt），不是修 bug。
- **必須重跑的既有 gate**：`BannerLifecycleRenderTests`（`.first` 前提：`BannerView` 只有一顆按鈕——
  本子項不動 `BannerView`，但新 kind 會經過它）、`CodexWiringSmokeTests`（CX24 五段）、`PanelPixelTests`。

---

### T13c　S0-2 決策層：`withheldSnippet` 改成「有 rejection 就扣住」（D-w）

- **改哪些檔**：`Sources/AuraCore/CodexHooksJSON.swift`（`pathRejection == .mustMoveToApplications`
  → `pathRejection != nil`，約 +4 含理由）。
- **gate**：**CX40 改名 ＋ 期望值整欄翻轉**（`codexSnippetIsWithheldWhenPathWillVanish`
  → **`codexSnippetIsWithheldForEveryPathRejection`**）。
  乘積表定義域不變（`CodexStateKind.allCases × [nil, .mustMoveToApplications, .unsupportedCharacter(" ")]`），
  期望值改成：**兩種 rejection 整行 nil、只有 `nil` 整行非 nil**。
  **mutation**：① 拿掉條件（無條件給）→ 必須紅；
  ② **改回 `== .mustMoveToApplications`（只扣一種）→ `.unsupportedCharacter` 整行必須紅**
  ——這是 r13 的新守衛，**r12 的實作在這個 mutation 下是綠的**，報告要把這句話連同實跑輸出寫下來。
- **test-edit scrutiny（必附三欄）**：改名 ＋ 翻轉是**契約變更不是弱化**——被測性質不變
  （snippet 有沒有穿過路徑判定）、定義域不變、格數不變、**斷言變強**（多一整行從非 nil 變 nil）。
  **名字必須跟著改**：「會消失」不再是判準，留著舊名會讓下一個人照名字推回舊條件。
- **必須重跑**：`CodexWiringSmokeTests`（CX40 的 App 半）、`CodexStateTests`。

---

### T13d　S0-2 view 層：`.unsupportedCharacter` 不給 snippet ＋ 問題／解法兩句（D-w）

- **改哪些檔**：
  - `Sources/AuraCore/L10nCodexCards.swift`（**新檔 ~70 行**）：新的 `L10nCatalog` enum，放
    `unsupportedCharacterWayOut`（出路句）、`mergeInstruction`／`helpLinkLabel`（T13h 用）、
    `staleOtherCopyIntro`（T13e 用）。**不塞進 `L10nCodex.swift`**——那個檔 158/200，
    `text(_:)` 的窮盡 `switch` 無法跨檔拆（`L10nUninstallConfirmation` 從 `L10nConfirmationAlerts`
    分出去的既有理由）。**也不塞進 `L10nPanel.swift`**（55/200，行數塞得下，r13 review (c) 問過）：
    那個 catalog 的既有語意是**面板本體的通用字串**，把 Codex 卡片的四句混進去會讓
    「哪個 catalog 管什麼」這條線消失；省下的約 25–30 行不改變 DoD #7 早已宣告的 MISS。
  - `Sources/AgentAuraApp/CodexSectionView.swift`：`.unsupportedCharacter` 分支拿掉 snippet 區塊、
    加出路句；`.occupiedByOther` 的 withheld 理由改成**依 rejection 分流**。
- **文案**（spec §4.6 表逐字）：`.unsupportedCharacter` = 既有的 `unsupportedCharacterExplanation(c)`
  ＋ 新的「把 App 移到路徑不含該字元的位置（例如『應用程式』），再回來重新接上。」
  英文：`Move the app somewhere without that character — Applications, for example — then come back and connect.`
- **驗收必含**：新的 `L10nCodexCards` **登記進 `L10nRegistry.allEntries`**，否則
  `L10nRegistryCoverageSourceScanTests` 紅（這條 gate 是 source scan，會自己抓到）。
- **gates**：
  - **CX49 `blockedCharacterCardWithholdsSnippetAndOffersAWayOut`**（App，`CodexSectionViewTests`）。
    **輸入餵真的 `codexSnippet`**（`CodexHooksJSON.snippet(hookBinaryPath:)` 對一條**含空白**的路徑的實際輸出）。
    斷言：含那個字元、含出路句、**不含** snippet 的前 40 個字元、**沒有** `.copyCodexSnippet` 按鈕。
    **mutation**：① 改回會畫 snippet → 必須紅；② 拿掉出路句 → 必須紅；
    ③ **把輸入的 `codexSnippet` 改成 nil → 這條會全綠**（等價 mutant，報告要寫出來——
    那正是 T09 review M1 在 `.mustMoveToApplications` 那格抓到的形狀）。
  - **CX36 擴充**：`.unsupportedCharacter` 那格加入同一條規則（餵真 snippet、斷言不得畫、必須有出路句），
    新增 mutation ④⑤（spec §6.3）。
- **禁止**：在 snippet 裡替路徑加引號當作「另一種修法」。`command` 的解析方式未測（§10-10），
  加引號同樣是賭，只是換一邊賭；解鎖條件寫在 §10-17，屬於**後續 change**。
- **必須重跑**：`CodexSectionViewTests` 全檔（九個代表值）、`L10nStrayLiteralSourceScanTests`、
  `L10nExhaustivenessSourceScanTests`（新 L10n 檔的窮盡 `switch` 不得有 `default`）、
  `L10nLanguagesDifferTests`（兩種語言的字串不得相同）。

---

### T13e　S2-1：`staleOtherCopyMessage` 拆成中性開場 ＋ 依 rejection 的成因／出路（D-x）

- **為什麼**：那句話對 `.unsupportedCharacter` **可查證為假**——`~/My Apps/…` 不會消失。
  P2 是會去查證的人，**一句可查證為假的話比一句含糊的話更傷信任**。
- **改哪些檔**：`L10nCodexCards.swift`（`staleOtherCopyIntro`）、`L10nCodex.swift`
  （`staleOtherCopyMessage` 的 doc comment 標明已被拆，或整個移除該 case——**移除要確認沒有其他消費者**）、
  `CodexSectionView.swift`（`.connectedStalePath` ＋ `pathRejection != nil` 分支改成兩段）。
- **重用**：第二段**直接用 T13d 那組**（`.mustMoveToApplications` 用既有兩句、`.unsupportedCharacter`
  用指名字元＋出路句）。**零新增文案**，這是選「拆兩句」而不是「只刪子句」的主要理由。
- **gate**：擴充 **CX36**（`.connectedStalePath` 的兩個 rejection 那兩格）——
  斷言兩格的文字**不相同**（r12 是同一句，證據圖 `10`／`11` 因此位元組完全相同），
  且 `.unsupportedCharacter` 那格含那個字元。
  **mutation**：兩格改回共用一句 → 必須紅。
- **必須重跑**：`CodexSectionViewTests`、`HelpDocOptionsRowCoverageTests`（不受影響，但便宜）。

---

### T13f　S1-1：三處狀態字串改雙 agent 感知（D-y）

- **改哪些檔**：
  - `Sources/AuraCore/PanelModel+ConnectCTA.swift`：`statusLabel(_:)`（約 +14 含理由）。
  - `Sources/AuraCore/L10nCodex+Failures.swift`：`codexConnectedStatus(claudeHalf:language:)`
    帶參數模板（約 +12，**不新增 enum case**，同 `unsupportedCharacterExplanation` 的既有形狀）。
  - `Sources/AuraCore/PanelModel.swift`：`title(for:install:language:)` 的非 connected 分支改讀 `statusLabel`。
  - `Sources/AgentAuraApp/PanelFooterView.swift` ＋ `PanelView.swift`：各 1 行改讀 `model.statusLabel(model.language)`。
- **規則只有一條**（spec §3.1）：`codex == .connected` 時加 Codex 子句，否則**逐位元組等於**
  `install.healthLabel(l)`。**Codex 子句在前**（footer chip 是 `lineLimit(1)` ＋ `.tail` 截斷，
  被截掉的一定是尾巴）。
- **gates**：
  - **CX50 `panelStatusLabelIsDualAgentAware`**（AuraCore）：**四條**斷言（零 diff `==`／含診斷子字串／
    Codex 子句在最前／**`title` 非 connected 分支 `==` `statusLabel`**）。
    定義域**逐字寫 `InstallStateAllCases.all()`**（test target 既有符號，由 `Reason.allCases ×
    MountOwner.allCases` 推導，`Tests/AuraCoreTests/` 已有六處在用）——**不得寫「代表值」然後手列**，
    手列會漏掉 `broken(reason, owner:)` 的變體，而斷言②正是為那些變體存在的（r13 review m4）。
    **mutation**：① 忽略 `codex` → ②③ 紅；② 無條件加子句 → ① 紅；
    ③ **子句改到尾端 → ③ 紅**；④ 把 `.connectedStalePath` 也算成已接上 → ① 紅；
    ⑤ **`title` 的非 connected 分支改回 `install.healthLabel` → 第④條必須紅**。
  - **CX51 `dualAgentStatusLabelReachesAllThreeSites`**（App，view 值樹）。
    **⚠️ r13 的寫法不成立，不要照抄**（review M2）：三處渲染的是**同一個字串**、`leafStrings` 回的是
    **扁平陣列**，所以「三處都 `contains(statusLabel)`」在任一處被改回 `install.healthLabel` 之後
    **仍然成立**——r13 宣告的三個 mutation **一個都不會紅**。
    r14 的三條**可分辨**斷言：
    ① **footer 比對複合字面** `"\(statusLabel) · v\(version)"`（版本後綴讓它唯一）；
    ② **裸 `statusLabel` 葉節點出現次數恰為 2**（標題 ＋ CTA 窄條，任一處被改回就變 1）；
    ③ **`install.healthLabel(l)` 不得以裸葉節點單獨出現**。
    標題那一處另由 **CX50④** 在純函式層守，兩條 doc comment 互相點名。
    **mutation 三個，都要跑、逐處記**：footer 改回 → ①紅；標題改回 → ②（2→1）＋③紅**且 CX50④ 也紅**；
    CTA 窄條改回 → ②（2→1）＋③紅。
  - **CX52 `healthLabelReadersAreTheNamedSet`**（來源掃描，**兩個 root**）。
    ① `Sources/AgentAuraApp/` 的 `.healthLabel(` 命中數**恰為 0**；
    ② `Sources/AuraCore/` 底下**含有** `.healthLabel(` 的**檔案集合恰等於具名清單**
    ——`InstallAffordance.swift`（宣告處）、`TooltipText.swift`、`PanelBanner+InstallerFailure.swift`、
    `PanelModel+ConnectCTA.swift`（`statusLabel` 唯一讀取點）。**用具名集合不用命中數**
    （數字會被無關增刪推著走）。**為什麼要第二格**（review m1）：三處裡的**標題住在 AuraCore**，
    只掃 App 層等於只守到 2/3，而 r13 的風險表卻寫「站點集合 source-derived」——那是 overclaim。
    **mutation**：① 任一 view 加回一行 → 第①格紅；② **把 `title` 的讀取點改回 `PanelModel.swift`
    → 第②格紅**（集合多一個檔）。
    **開工前先實跑兩個 grep 記下現況**（2026-09-21 實測：App 層 2 命中
    `PanelView.swift:41`／`PanelFooterView.swift:19`；AuraCore 側 4 命中，分布在
    `TooltipText.swift:21`／`PanelModel.swift:157`／`PanelBanner+InstallerFailure.swift:20,21`）
    ——「命中數／檔案集合是什麼」是待驗證的宣稱，不是背景知識。
- **量測任務（寫進報告，spec §10-22）**：**三處都要量**（r13 只寫了 footer，review m3）。
  量的字串是 `"Codex connected · Claude Code: Not connected yet"`（footer 再加 ` · v1.4.2`）：
  1. **footer chip**：11pt system，可用寬度 = 380 − 左右 14×2 − 圓點 8 − 間距 − Options 按鈕。
     只截到版本號是**可接受的取捨**；**若連 `Codex` 這個字都被截掉**，才改用更短的子句。
  2. **標題**（`PanelView.swift:20`）：13pt semibold、**沒有 `lineLimit`** → **會不會換行**。
  3. **CTA 窄條 label**（`ConnectCTABannerView`）：同樣沒有寬度保護。
  **標題若換行，把換行後的高度增量交給 T13i 的基準表**——它會直接推高面板，回饋進 §4.10 的天花板。
  **先量再決定**（gate 哲學第 7 條），不要先改設計。
- **禁止**：另寫一套雙 agent 的 `healthLabel`（十五種變體會 drift，而且會弄丟 `broken` 的診斷字）；
  「Codex 已接上時不畫 Claude 的 CTA 窄條」（那會讓只用 Codex 的人永遠看不到接上 Claude 的入口，
  把文案問題換成功能問題）。
- **必須重跑**：`PanelPixelTests`、`FooterPixelTests`、`CTABannerStripRenderTests`、
  `NotConnectedRenderTests`、`FooterPositionStabilityTests`、`TooltipText` 相關測試
  （`TooltipText` 也讀 `install.healthLabel`，但它在 AuraCore、**不在 CX52 的掃描範圍**——
  這是刻意的，tooltip 是選單列的 hover 文字，不是面板的三處狀態字串；在報告裡寫明這個邊界）。

---

### T13g　S1-2：`emptyRowsMessage` 依 Codex 狀態分兩句（D-z）

- **改哪些檔**：`Sources/AuraCore/L10nPanel.swift`（新 case `emptyRowsMessageWithCodex`，約 +10）、
  `Sources/AuraCore/PanelModel.swift`（`emptyRowsMessage` 加一個 `codex == .connected` 分支，約 +4）。
- **gate**：**CX53 `emptyRowsMessageIsAgentAware`**（AuraCore）。
  期望值**寫死字面**，不引用 `L10nPanel.emptyRowsMessage`——拿產生器跟自己比的老陷阱，本 change 已踩過兩次
  （`timeout`／`agentFlag`）。
  **mutation**：① 一律回舊句 → `.connected` 那格紅；② 一律回新句 → 其餘五格紅。
- **test-edit scrutiny**：既有釘死那句字面的測試改成**分兩格**（舊字面留在「非 `.connected`」那格）。
  **直接把舊斷言改成新字面＝弱化**（會讓 mutation ② 全綠），要退回。

---

### T13h　S1-3：`.occupiedByOther` 加合併指示 ＋ 通往 help 的入口（D-aa）

- **改哪些檔**：`L10nCodexCards.swift`（`mergeInstruction`／`helpLinkLabel`）、
  `CodexSectionView.swift`（一行文字 ＋ 一顆 `.openHelp` 按鈕）、
  `Resources/help-english.html` ＋ `help-traditionalChinese.html`（補「不要整份取代」那句）。
- **重用 `.openHelp`，不開第四個 `PanelAction`**：新增 action 會拖動 `PanelActionKind`／`samples`／
  `nonMenuKinds`／`panelActionsAreWired`／CX28 五條既有 gate 的定義域，換來的只是同一個目的地。
  `NotConnectedView.swift:46` 已有 `Button(...) { onAction(.openHelp) }` 的既有形狀可抄。
- **文案**：「把這些 entry **併進**你現有的 hooks 物件，**不要整份取代**。」
  英文：`Add these entries into your existing hooks object — don't replace the whole file.`
- **現況確認（已實跑，寫進報告當基準）**：兩份 help 目前只說「shows a snippet to add by hand instead」／
  「只會顯示一段可以手動貼上的設定」，**都沒有講「不要整份取代」**；那句話只存在於 `docs/INSTALL.md:91-92`
  （同樣只有 "copy and add to it by hand"）。所以 CX55 落地前，**兩份 help 都要真的補字**。
- **gates**：
  - **CX54 `occupiedCardTellsYouToMergeAndOffersHelp`**（App，view 值樹 ＋ 點遍按鈕收集 action）。
    含**負向對照**：`codexSnippet == nil` 那格不得有合併指示與 help 按鈕。
    **mutation**：① 拿掉合併指示 → 紅；② help 按鈕改送別的 action → 紅；
    ③ 讓 `codexSnippet == nil` 那格也畫 → 負向那格紅。
  - **CX55 `helpDocsExplainMergingIntoExistingHooks`**（文件，`@Test(arguments:)` 參數化**兩份**）。
    **mutation**：從**任一份**刪掉那段 → 必須紅（兩份各試一次——CX29 的既有教訓：
    內容有、守衛沒有，兩邊都刪當時只紅 1 條）。
- **禁止**：用 `@Test` 寫兩條各驗一份（CX29 已經吃過這個虧）；把 help 入口做成 tooltip
  （P3 的 legend ⓘ 就是 tooltip，persona 明講「面板裡沒有任何從 A 通往 B 的**路徑**」）。
- **必須重跑**：`NotConnectedRenderTests.notConnectedViewAddsExactlyItsOwnButtons`
  （**用「數量差」的形狀**——它的兩個 model 的 `codex` 都是 `.unavailable`，所以不受影響，
  但這條推論要在報告裡寫出來，**不接受「沒紅所以應該沒事」**）、`PanelPixelTests.panelViewForwardsAction`
  （點遍按鈕收集 `PanelAction` 集合 → **新按鈕送的是既有的 `.openHelp`，期望集合不變**，同樣要寫明推論）。

---

### T13i　S1-4：snippet 區塊固定高度 ＋ 可捲 ＋ 面板高度天花板（D-ab）

- **先量修前基準**（gate 哲學第 7 條，**這一步不可省，而且是本子項的第一個交付物**）：
  **五個維度的乘積**——`CodexState` 代表值 × 兩語言 × {rows 空, 3 列} ×
  **`install ∈ {.connected, 一個 affordance == .connect 的代表值}`** ×
  **`banner ∈ {nil, .codexConnected}`**，量 `preferredContentSize.height`，**整張表寫進報告**；
  另外把 `optionsExpanded == true` 的版本也量一次，數字填進 spec §10-20。
- **⚠️ r13 的域漏了 `install` 與 `banner` 兩欄**（review M1）：persona 量到的 944pt 出自證據圖
  `05`／`07`，而 `CodexEvidenceRenderer.swift:115,131` **兩張都是 `install: connected`**。
  最壞組合是 **`install` 非 connected（整版 CTA 或窄條）＋ `.occupiedByOther` 有 snippet
  ＋ `.codexConnected` banner 尚未退場**（剛接上、還沒跑過 Codex session——**那正是最常見的那一刻**），
  **它從來沒有被量過**。照 r13 的域挑 snippet 上限，CX56 會全綠而那個使用者的「複製」鈕仍在畫面外。
- **780 在量完之前是「提案」不是「已驗證可達」**：**先量後定**。量完再挑 snippet 上限。
  **snippet 區塊有下限：至少能同時顯示 6 個視覺列**（從真實 view 推導，不寫死 pt）。
  **若在下限之下仍然到不了 780，停下來**把數字與三個選項交回主 session／使用者
  （調整天花板數字／整張 Codex 卡片納入可捲／該組合下不同時顯示 banner 與 snippet 卡——
  **第三個會動到 D-v，屬於決策變更，必須回 spec**）。**不准自己去砍別處的內容讓它變綠。**
- **改哪些檔**：`Sources/AuraCore/CodexSnippetSizing.swift`（**新檔 ~40 行**，形狀照抄
  `SessionsCardSizing`：從真實內容推導 ＋ 夾到上限）、`CodexSectionView.swift`
  （snippet 區塊包 `ScrollView`、吃一個**算好的固定高度**）。
- **關鍵約束**：**用固定高度，不用 `.frame(maxHeight:)`**。T22 已實測 `ScrollView` 垂直方向貪婪，
  只設上限會讓它吃滿外層提案高度，footer 位置又會變回「依畫布而定」——那正是
  `FooterPositionStabilityTests` 守的東西。
- **gate**：**CX56 `snippetCardFitsOnA13InchScreen`**（App，**渲染後座標**）。
  `optionsExpanded == false`，定義域是上面那**五個維度的乘積**（全部程式推導）：
  `preferredContentSize.height ≤ 780pt`；snippet 那些態的「複製」按鈕與 footer 按鈕
  **轉換到 hosting 座標後**的 `minY` 都 `< 780`；**另一格**斷言 snippet 區塊高度**不低於 6 個視覺列**。
  **按鈕身份用點擊辨識，不得用陣列索引**（`FooterPositionStabilityTests` 的既有手法與踩過的坑）。
  **mutation**：① 拿掉固定高度（改回無上限）→ 必須紅；
  ② **改成 `.frame(maxHeight:)` → `FooterPositionStabilityTests` 必須紅**（兩條一起看）；
  ③ **把域縮回 r13 的「只有 `install: .connected` ＋ `banner: nil`」→ 必須能重現 r13 的假綠**
  ——報告要附這一格的實跑輸出（同一個 snippet 上限下，**窄域全綠、全域紅**），
  那是「域不夠 ＝ gate 沒有牙齒」最直接的證據；
  ④ **拿掉下限那格並把上限壓到 1 列 → 下限那格必須紅**。
- **禁止**：
  - 用「宣告順序」代替渲染座標（CLAUDE.md gate 哲學第 4 條：A4 的 gate 一直是綠的，
    實機上 footer 仍被推走 −257pt）。
  - 把 Options 展開的組合綁進這條 gate（那是本 change 之前就存在的條件，會讓新 gate 去回答舊問題
    ——**「換題目」的形狀**）。數字記進 §10-20 就好。
  - 為了讓 780 變綠而去砍別處的留白。**780 紅掉時的第一個問題是「面板是不是又長高了」**
    （icon-shapes 那次的教訓：收斂到一個已經換了題目的 gate，看起來跟正確的紀律一模一樣）。
  - **把 snippet 壓成一條縫**讓天花板變綠——下限那格（6 個視覺列）就是擋這個的。
  - **在只量過 `install: connected` 的基準上挑 snippet 上限**（r13 的錯）。
- **必須重跑（特別警告）**：`FooterPositionStabilityTests`。
  它的畫布**已經改成從現場量到的自然高度推導**（`surplusCanvasHeight()` = `max(collapsed, expanded) + 100`，
  `/simplify` icon-shapes 波次修過），所以**不會**再發生「寫死 600pt 被面板長大追上」那件事
  ——但本子項會**改變**那個自然高度，**要重跑並把新的畫布數字記進報告**。
  另外重跑 `OptionsExpandTests`、`PanelPixelTests`、`SessionsCardSizingDerivationTests`。

---

### T13j　S1-5：「移除 Codex 掛載…」走確認框（D-ac）　**依賴 T13a**

- **改哪些檔**：
  - `Sources/AgentAuraApp/AppDelegate.swift`：第四個注入縫 `confirmDisconnectCodex`
    （stored `let` ＋ doc ＋ init 參數 ＋ 預設值 ＋ 指派，約 +8）。**T13a 之後才有空間**。
  - `Sources/AgentAuraApp/AppDelegate+PanelActions.swift`：`.disconnectCodex` 包一層
    `self.confirmDisconnectCodex(self.language) { [weak self] in self?.performDisconnectCodex() }`
    （照 `.disconnect` 的既有形狀，約 +2）。
  - `Sources/AgentAuraApp/AppEnvironment.swift`：`CodexDisconnectConfirmation`
    （照 `DisconnectConfirmation` 的形狀，共用 `ConfirmationAlert.present`，約 +16）。
  - `Sources/AuraCore/L10nConfirmationAlerts.swift`：三句（標題／內文／確認按鈕，約 +40）。
- **文案要點名 agent**：標題「移除 Codex 掛載？」／`Remove the Codex mount?`
  （對照既有 `disconnectTitle` 已經點名 Claude Code）。內文要講清楚**只刪我們自己寫的那份**
  （逐位元組比對過才刪，別人的 `hooks.json` 不會被碰）。**刪節號保留**——現在它說的是實話了。
- **gate**：**CX57 `codexDisconnectGoesThroughConfirmation`**（App）。
  兩格：注入**不呼叫** `onConfirm` 的假身 → `disconnectCallCount == 0` ＋ 憑證鍵位元組不變；
  注入**會呼叫**的 → `== 1`。第三格：確認框文案含 `Agent.codex.label!`。
  **mutation**：① 改回直接呼叫 `performDisconnectCodex()` → 第一格必須紅；② 文案拿掉 agent 名 → 第三格紅。
- **test-edit scrutiny（必附三欄）**：`AppDelegatePanelActionsWiredTests+Codex.swift` 的
  `.disconnectCodex` 那格要改成「經確認框才有副作用」。
  **注入的預設假身不得是「直接呼叫 onConfirm」**——否則 CX57 第一格在任何實作下都成立。
- **必須重跑**：`AppDelegatePanelActionsWiredTests`（`panelActionsAreWired` 對三個 Codex kind）、
  `CodexWiringSmokeTests`、`AppDelegateCompositionInjectionTests`（新注入縫的預設值）、
  `CompositionSmokeTests`、`UninstallerTests`（完整移除路徑呼叫的是 `codexInstaller.disconnect`，
  **不經確認框**——那是使用者已經在完整移除確認框裡同意過的動作，**不要**在那條路徑上再問一次，
  報告要寫明這個邊界）。

---

### T13k　文件與回寫（spec §8.2 的 r13 三列）

- `docs/INSTALL.md` ＋ `.zh-TW`：「State directory」那節的「one file per **Claude Code** session」
  改成涵蓋兩個 agent（persona r1 S2-6——這是本 change 造成的事實錯誤）。
- `CLAUDE.md` Invariants：加兩條（D-y 的三處狀態字串、D-v 的 banner 退場條件），
  **只列已經存在的 gate 名**（T11 review m2 的既有規則）。
- `CLAUDE.md` Tier 1 清單：確認 `PanelModel+ConnectCTA.swift` 在不在（它現在承載 `statusLabel`）。
- spec §10 的 17–22 六條 known gap，其中 **20（Options 展開＋snippet 的高度）與 22（chip 寬度）
  的數字由 T13i／T13f 填**——交付時必須是真數字，不是「待量」。

---

### T13l　證據圖重渲（D-ad）　**最後一個子項**

- **S1-6／S1-7 已經由 commit `493e0bf`（`docs(codex): 證據圖補 S1-6／S1-7`）交付**，那是
  **r13 之前的修前基準**：#07 的 snippet 現在由真的含空白的路徑
  （`/Users/someone/My Apps/AgentAura.app/Contents/PlugIns/aura-hook`）產生、#12 已經存在。
  **T13l 是在那個 commit 之上做 r13 的修後版本**，不是重做它。
  開工前先 `git log --oneline -3 -- docs/evidence/codex/` 確認那個 commit 還在、工作目錄乾淨。
- **要做的事**：
  1. **#07 重渲**：新政策下它會是「不給 snippet」的圖。
     **`realSnippetWithSpace` 這個輸入常數要留著繼續餵進去**（`493e0bf` 加的）——
     負向斷言餵正向輸入的同一條原則，圖上要證明「**即使 snippet 產得出來，我們也沒有畫**」。
     渲染器 doc comment 與 INDEX 裡 `493e0bf` 寫的「**r13 前的修前基準**，T13 落地後要重渲」
     兩處附註要同步改成「r13 後」（**它們現在是預告，重渲後會變成謊**）。
  2. **#12 保留**（`install: .notConnected` ＋ 一列活著的 Codex session）：r13 之後這張圖的
     標題與 footer chip 應該寫「Codex connected · Claude Code: Not connected yet」
     ——**這張圖是 S1-1 修好沒有的直接證據**。
  3. **新增 #13**：`.codexConnected` banner ＋ 一列活著的 **Claude** session（S0-1 的修後證據：
     banner 不再被抹掉）。兩語言。
  4. **#05／#10／#11 重渲**：#05 多了合併指示與 help 按鈕、snippet 區塊變成固定高度；
     #10／#11 的文案在 D-x 之後**不再逐字相同**（persona 現場驗過 r12 兩組圖位元組完全相同）。
  4b. **新增 #14：最壞高度組合**（r13 review m5）——`install` 非 connected ＋ `.occupiedByOther`
     有 snippet ＋ `.codexConnected` banner，兩語言。現有 12 張圖裡只有 #12 是
     `install: .notConnected`，而它的 codex 是 `.connected`（**不畫卡片**），所以 §4.10 講的那一格
     **目前沒有任何一張圖**。這張是 persona r2 判「S1-4 有沒有真的關掉」的直接證據，
     也要與 T13i 基準表的同一格數字對得上（圖是 @2x px、基準表是 pt，**不要混用**）。
  5. INDEX 的「persona r1 指出的視覺問題對照」段逐條標成「已修／明寫接受」，並指向對應的 D-xx。
- **驗收必含**：`AURA_RENDER_EVIDENCE=1 swift test --filter renderCodexEvidence` 跑完之後，
  `git status` 只動到 `docs/evidence/codex/` 與渲染器本身；每一張改動的圖都在 INDEX 有對應說明。

---

### T13 整批的驗收（交付前逐條打勾）

| # | 項目 | 判準 |
|---|---|---|
| 1 | 兩條 S0 關閉 | CX47／CX48（S0-1）與 CX40／CX49／CX36④⑤（S0-2）全綠，且各自的 mutation 在 **r12 的碼上是紅的** |
| 2 | 七條 S1 關閉或明寫接受 | S1-1 → CX50/51/52；S1-2 → CX53；S1-3 → CX54/55；S1-4 → CX56；S1-5 → CX57；S1-6／S1-7 → T13l 的圖 |
| 3 | 三條「Codex 不在場時位元組不變」 | CX50①、CX53、`.unavailable` 的既有零像素守衛，**全部是 `==` 不是「看起來一樣」** |
| 4 | mutation 帳 | CX47–CX57 **11 條**逐條 `mutation / 指名測試 / 秒數`；**兩個等價 mutant 也要記**（CX47②、CX49③） |
| 5 | test-edit scrutiny | CX40 改名＋翻轉、CX36 擴充、`emptyRowsMessage` 分格、`.disconnectCodex` 那格——**四處各附三欄** |
| 6 | 單檔行數 | `IsolationTests.fileLengthLimit` 綠；**特別看** `PanelView.swift`（189→190，餘裕 10）、 `PanelModel.swift`（172→180）、`AppDelegate.swift`（T13a 之後 ≈126） |
| 7 | `Sources/` 淨增 | 逐檔「估／實」兩欄（spec §8.1 的 r13 表）；DoD #7 **仍是 MISS，不調門檻**，超標數字如實更新 |
| 8 | `#expect(` 淨增 | 只准上升；附 HEAD 絕對值（指令固定 `grep -rho '#expect(' Tests \| wc -l`，**基準 2026**——2026-09-21 於 `7515b44` 實測。r13 寫的 2025 是 T12 帳本裡的舊值，**本 change 第二次犯同族的端點漂移**，而 DoD #2 要求附絕對值正是為了抓它） |
| 9 | 既有 gate 全綠 | 連跑 3 次 0 flake；**特別重跑清單**見下 |
| 10 | 量測數字入帳 | §10-20（Options 展開＋snippet 的高度）與 §10-22（chip 寬度）必須是真數字 |

**必須重跑的既有 gate（彙總，逐條在報告裡寫結論）**：
`CodexWiringSmokeTests`（CX24 五段）· `CodexSectionViewTests`（CX36 九個代表值）·
`CodexStateTests`（CX40 純函式半）· `CodexOptionsRowTests`（CX20）· `CodexRowLabelRenderTests`（CX23 列高）·
`AppDelegatePanelActionsWiredTests`（＋`+Codex`）· `PanelPixelTests` · `FooterPixelTests` ·
**`FooterPositionStabilityTests`**（畫布已改為推導，但自然高度會被 T13i 改變，**新數字要記**）·
`OptionsExpandTests` · `NotConnectedRenderTests` · `CTABannerStripRenderTests` · `BannerLifecycleRenderTests` ·
`SessionsCardSizingDerivationTests` · `CompositionSmokeTests` · `AppDelegateCompositionInjectionTests` ·
`UninstallerTests` · `HelpDocOptionsRowCoverageTests`（CX28）· `L10nRegistryCoverageSourceScanTests` ·
`L10nStrayLiteralSourceScanTests` · `L10nExhaustivenessSourceScanTests` · `L10nLanguagesDifferTests` ·
`IsolationTests.fileLengthLimit` · `panelModelMakeHasNoDefaults` · `CX44 noPendingFlagRemains`。

**T13 的 persona r2 送審條件**（同 DoD 帳本的 persona 段）：兩條 S0 全關 · 七條 S1 全關或在 spec 明寫接受 ·
四條硬下限全過 · 加權 ≥ 6.0。

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

### T13（persona r1 修復批次）額外的四條

16. **這批改的是「不是這個 change 寫的碼」**（`effectiveBanner`／`PanelModel.title`／`PanelFooterView`／
    `emptyRowsMessage`）。**最容易犯的錯是把 Claude-only 的既有行為一起改掉**——
    每一條的第一個斷言都必須是「Codex 不在場時**逐位元組**不變」（CX50①／CX53／`.unavailable` 零像素）。
17. **兩個等價 mutant 是預期的，不是失敗**（CX47② 的 `agentLabel != nil`、CX49③ 的把輸入改成 nil）。
    **要記進報告並寫明它守的是什麼**，不要為了「讓 mutation 紅」而把 gate 改成另一件事。
18. **780pt 天花板是產品天花板，不是量出來的自然高度**。它紅掉時的第一個問題是
    「面板是不是又長高了」——icon-shapes 那次的教訓是**收斂到一個已經換了題目的 gate，
    看起來跟正確的紀律一模一樣**。
19. **`.unsupportedCharacter` 不給 snippet 是刻意的，不是遺漏**（D-w／§10-17，有解鎖條件）。
    實作時會很想「順手加個引號就能給了」——`command` 的解析方式未測，加引號同樣是賭。
