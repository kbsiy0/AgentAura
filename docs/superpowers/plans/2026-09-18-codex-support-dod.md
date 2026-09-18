# DoD 帳本 · `change/codex-support`（T12）

spec `docs/superpowers/specs/2026-09-18-codex-support-design.md`（**r8**）§7 為門檻來源；
證據層 `docs/2026-09-18-codex-hook-probe.md`（**F1–F15**，F15 以 `8fdce0b` 的版本為準）。
基準取自 `change/codex-support` 分支點（`c131c30`，＝ `main` ＋ 探針文件），量測時用
`git worktree add <temp> <基準> --detach` 取乾淨副本，**不動共享工作目錄**。

**本檔在 T12 執行前寫好門檻與量法；「實測」「判定」兩欄由 T12 填。**
門檻不得在量完之後往下調——miss 就記 known gap（本專案已有兩次前例：+292 KB、+746 KB，
都是如實記錄不調門檻）。

**gate 編號**：本 change 新增的一律 `CX<n>`（**45 條**；CX37 拆成 a／b）；既有 gate 一律寫測試函式名。

**起點不是全綠**：`FixtureCodeAnchorTests.everyFixtureModelIsMapped` **目前是紅的**——
round4 fixture 進 repo 之後，`Jargon.model("gpt-5.5")` 原字回傳（實測輸出：
`Expectation failed: (Jargon.model(v) → "gpt-5.5") != (v → "gpt-5.5")`，`FixtureCodeAnchorTests.swift:81`）。
**這一條是本 change 必須修好的既有 gate**（spec §4.9／T05），**不是**弱化或加 allowlist 的對象。
DoD #1 的「全綠」以「修好它之後」為準。

## 基準值（2026-09-18 量）

| 項目 | 基準 |
|---|---|
| `Sources/` 總行數 | **7846**（104 個 `.swift`） |
| `Tests/` 的 `#expect(` 總數 | **1649**（176 個 `.swift`）。**2026-09-18 更正**（T02 review m3／T03 review m2）：原本用 `grep -rho '#expect'`（1652），改用 **`grep -rho '#expect(' Tests \| wc -l`**——差額恰好是三處**寫在 doc comment 裡的散文提及**（`SnapshotIOTests.swift:48`、`PanelViewModelTests.swift:136`、`InstallLayoutTests.swift:43`），那些不是斷言、不該算。兩種算法各自內部一致，沒有人算錯，但 DoD 與各 task 報告用了不同指令，T12 彙總時會出現對不上的總數 |
| `build/AgentAura.app/Contents/MacOS/AgentAuraApp` | **3,140,864 bytes**（universal） |
| `plugin/hooks/hooks.json` | 19 個事件；19 個 entry 中**只有 `Notification` 帶 `matcher`** |
| 機械改動 fan-out | `PanelModel.make(` **61 處／26 檔**；`OptionsMenuModel.rows(` **26 處／10 檔**；`MergeRules.merge(` **7 處** |
| 已在上限的檔 | `AppDelegate+PanelActions.swift` **200**／`OptionsMenuModelTests.swift` **300**／`AppDelegatePanelActionsWiredTests.swift` **300**（另 `MergeRulesTests` 294、`PanelViewModelTests` 288、`EndToEndWiredGateTests` 149） |
| `round4-codex.ndjson` | 18 筆／4 個 session；`SessionStart` 4、`UserPromptSubmit` 4、`Stop` 4、`SessionEnd` 4、`PreToolUse` 1、`PostToolUse` 1；**零筆 `Interrupt`**。唯一 `model` = `gpt-5.5`；唯一 `permission_mode` = `bypassPermissions`（已在映射表）；**無 `effort`** |
| 既有紅燈 | `everyFixtureModelIsMapped` 1 issue（見上） |
| `~/.codex/config.toml` | T12 開工當下現場存一份副本，全程用 `diff` 比對 |

## DoD 全表

| # | 項目 | 門檻 | 量法 | 實測 | 判定 |
|---|---|---|---|---|---|
| 1 | 測試全綠 | 連跑 **3 次** 0 flake，**含修好 `everyFixtureModelIsMapped`**、**且 `AURA_CODEX_PENDING_T05`／`_T10` 兩個旗標都已解除**（T05／T10 各自的驗收要附解除前／後的 `#expect` 與測試函式數，**只准上升**）；每次存全量 log | `swift test` ×3 ＋ CX44 | | |
| 2 | 新增測試數 | `#expect(` 淨增 **≥ 180**（基準 **1649**）；新增測試函式 **≥ 65**。**量法一次定案**（T04 review m3）：指令固定 `grep -rho '#expect(' Tests \| wc -l`，**每個 task 的報告附該 commit 的絕對值**（不只增量）——只報增量時，兩個端點各差 3 也看不出來。r4 是 170／62，**r5 增量＝CX42 約 +5、Jargon 三列 +3、CX37 拆 a／b +2**（`grep -c '#expect'` 數的是**原始碼出現次數**，迴圈只算一次——20／780 條序列不會讓這個數字暴增） | 前後 **`grep -rho '#expect(' Tests \| wc -l`**；`swift test` 的 tests 計數 | | |
| 3 | gate mutation 帳 | **45 條**（CX1–CX45，CX37 拆 a／b）逐條有 `mutation / 指名測試 / 秒數`；**抽驗 5 筆現場重跑**（必含 CX2、CX4、CX15、CX32、**CX39**） | 彙整 T02–T11 的完成報告 ＋ 現場重跑 | | |
| 4 | **Claude 側零回歸**（紅線） | `git diff <基準>..HEAD -- plugin/hooks/hooks.json` **完全為空**；`handledEvents` 的 19 個名字一字未動 | `git diff` ＋ 逐行看 `EventMapping.swift` 的 diff | | |
| 5 | **Claude 狀態檔位元組不變** | round1／1b／2／3 跑 merge（用**生產的** `SnapshotIO.encoder`）序列化後**不含 `agent` 鍵**；**且**不帶 `--agent` 真 spawn 一次後，**原始檔案文字**不含 `"agent"` | CX9 **兩層**；**這一格的證據以生產層那半為準**（`agent == nil` ≠「檔案裡沒有這個鍵」——自訂 encode 可能寫出 `"agent":null`，解碼回來仍是 nil 而上游全綠） | | |
| 6a | **`config.toml` 零變動（自動化側）** | `swift test` ×3 全程位元組完全不變 | 開工前存副本，跑完 `diff` | | |
| 6b | **`config.toml` 受控變動（實機側）** | 實機 ①–⑧ 跑完：**不得新增任何 `[hooks*]` 段**，diff **僅限** `[projects.*] trust_level`（F12） | `diff <副本> ~/.codex/config.toml` 逐行判讀 | | |
| 7 | `Sources/` 淨增 | **≤ 1150 行**（基準 7846 → ≤ 8996）；逐檔估算 ≈ 1060（spec §8.1），留 8% 餘裕。r3 是 975／門檻 1050；**r4 增量＝Jargon +30、RejectionKind +20、stale/snippet 兩種文案與分支 +35**。**若 R-5／R-6 日後被砍，門檻要跟著降回 900／啟動 +2 ms**，否則就變成「先加需求再放寬門檻」的通道。**超過就先砍 instrumentation 與非必要碼，不調門檻** | `find Sources -name '*.swift' \| xargs cat \| wc -l` | | |
| 8 | 單檔行數 | `Sources/` ≤ 200、`Tests/` ≤ 300，**零例外**；三個預先拆檔各自是零行為變更的獨立 commit | `IsolationTests.fileLengthLimit` ＋ 手動複查最大的 5 個檔 ＋ 三個搬移 commit 的 diff | | |
| 9 | 零新依賴／新 target | `Package.swift` diff 為空 | `git diff -- Package.swift` | | |
| 10 | module 基準 | `AuraCore` = Foundation、`AuraHookFile` = Foundation ＋ CoreServices。**`AuraHookFile` 不得 import Security**（`RunningBundle` 是 App 層唯一計算點） | `IsolationTests.nonUITargetsLoadNoUIModules` | | |
| 11 | 執行檔增量 | **≤ +200 KB** universal（基準 3,140,864）。依據：既有兩次量到的「每新增一個 SwiftUI view ≈ 60–80 KB/arch」，本 change 新增 1 個 view | `./scripts/build-app.sh` 後 `ls -l` | | |
| 12 | **面板路徑成本** | **`reprobeCodex()` 100 次 ≤ 10 ms**（穩態；`.notConnected` 與 `.connected` **各量一次並分開記**）。**量 `reprobeCodex()` 端到端，不是只量 `probe()`**——那才是 `onOpen` 實際跑的東西（r3 m3）。可並列 `CodexInstaller.probe()` 的數字供分解 | 行程內暫時測試（`ContinuousClock`），跑完即刪、`git status` 確認乾淨 | | |
| 13 | 啟動時間增幅 | **≤ +3 ms**（多一次 `lstat`、最多讀 64 KiB、一次 `SecTranslocateIsTranslocatedURL`、一次產生器呼叫——**四個行程常數搬到啟動時算**，D-t） | `applicationDidFinishLaunching` 首尾時戳，各 3 輪 × 10 次取中位數；基準側在 worktree 量 | | |
| 14 | RSS 增幅 | **≤ 1 MB** | `scripts/measure-cpu.sh`（先隔離量測者自己的 session） | | |
| 15 | 動畫態 CPU | 不得比基準更差（五態各量） | `scripts/measure-cpu.sh`，連續兩輪 | | |
| 16 | plugin 契約 | 零 error 零 warning。**這也是 `Interrupt` 接縫的第四道防線、且是唯一一道不依賴我們自己寫的斷言的**（T03 review 實測：註冊 `Interrupt` → `unknown hook event; entry ignored at runtime` ＋ `--strict` 視 warning 為 error → 失敗）。**注意**：本機 validator 只給 warning，**整份拒載是 2026-09-15 在同事機器上量到的**（`distribution-and-hook-compat`）——本機通過不構成「全有全無」的反證 | `claude plugin validate --strict ./plugin` 與 `.` | | |
| 17 | 安裝鏈路（Claude） | 全項 PASS（含 `settings.json` 零污染、一輪真的 `claude -p`） | `./scripts/verify-install.sh` | | |
| 18 | 完整移除 | `verify-uninstall.sh` **7 項全 PASS**；第 7 項兩個方向都驗過；`--only 7` 可單獨執行且**不觸發** `osascript`／`sfltool` | CX27 ＋ 實機 ⑥ | | |
| 19 | bundle 佈局 | PASS，缺 bundle 時 FAIL 不 skip | `./scripts/verify-app.sh` | | |
| 20 | 測試不得跑 `codex exec` | `Tests/`／`scripts/` 命中數 **= 0**（＋正向對照） | CX30 | | |
| 21 | 文件路徑一致 | `README.md`／`SECURITY.md` 都含 `.codex/hooks.json` | CX29 | | |
| 22 | help 涵蓋 | 兩個語言都涵蓋**每一個**新的 Options 列標題（含「重新接上 Codex」） | CX28 | | |
| 23 | **CX37a／CX37b 的成本** | CX37a **780 條全跑、零 spawn**（毫秒級，**不縮減**）；CX37b **30 條、11 次真 spawn**、走 `SpawnGate`。兩條的 doc comment 要互相點名（a 的等價理由／b 的長度上限理由）。**實測秒數寫進報告** | T06 的完成報告 ＋ 現場重跑 | | |
| 24 | persona | 加權 **≥ 6.0**；硬下限四條（見下） | Tier 1，integrator 綠後派 persona-tester | | |

### persona 硬下限（低於門檻即 no-go，不得用平均分蓋過）

| 代號 | persona | 問題 | 下限 |
|---|---|---|---|
| P1 | 只用 Codex 的人 | Claude 的大版說明與 Codex 的單行提示疊在同一張畫面上，30 秒內知道該按哪個 | **≥ 5** |
| P2 | 已有自己 `~/.codex/hooks.json` 的進階使用者 | 相信我們**不會**動他的檔；snippet 可貼、貼了會動。**三條具體要求**（不另開硬下限）：① 路徑被拒時文案**指名是哪個字元**；② 拒絕必須給出路；③ **從 DMG／下載資料夾打開時，寧可不給 snippet 也不給一份會過期的**（R-10） | **≥ 6** |
| P3 | 不懂「信任」提示的 vibe coding 使用者 | 按下接上之後，知道「還要在 Codex 裡按一次同意」才會生效 | **≥ 5** |
| P4 | 兩個都用的人 | 同專案同時跑時兩列分得出來；**兩側都接上時兩邊的燈都真的會動**（R-8） | **≥ 5** |

## Gate mutation 帳（45 條；T12 彙整，✓現場 = 抽驗重跑）

| Gate | 位置 | Mutation | 指名測試 | 秒數 | 來源 task |
|---|---|---|---|---|---|
| CX1 | `CodexEventSeamTests` | `codexEvents` 少一個事件（**拿掉的是 `codexEvents` 那一份**；從 `handledEvents` 拿會打到 CX3 而不是這裡） | `codexEventSetIsPinnedToProbe` | | T03 |
| **CX2** | `CodexEventSeamTests` | 把 `Interrupt` 加進 `handledEvents` | `interruptNeverEntersHandledEvents`（**＋既有 `registeredEventsMatchHandledEvents` 也必須紅**） | | T03 · **抽驗必做** |
| CX3 | `CodexEventSeamTests` | **從 `handledEvents`** 拿掉 `PreCompact`（子集檢查落空；**從 `codexEvents` 拿只會紅 CX1**，別把「CX3 沒紅」誤讀成 gate 失效——T03 review 實測兩種拿法打到不同 gate） | `codexSharedEventsReuseClaudeMapping` | | T03 |
| **CX4** | `CodexEventSeamTests` | 刪掉 `case "Interrupt"` 整行 | `codexOnlyEventsMapToIdle`（**同時記「加這條 gate 之前同一個 mutation 全綠」**） | | T03 · **抽驗必做** |
| CX5 | `CodexEventSeamTests` | Claude hooks.json 加 `Interrupt`（**三個獨立觀測點都會紅**：CX5、既有 `registeredEventsMatchHandledEvents`、`claude plugin validate --strict`） | `claudeHooksJSONHasNoInterrupt`（**含定義域非空守衛**） | | T03 |
| CX6 | `CodexHooksJSONTests` | ① 寫死 11 個 ② 拿掉 `matcher` ③ 加 `async: true` ④ 漏 `--agent codex` ⑤ **`timeout` 改回 5** ⑥ **`agentFlag` 改成 `"--agent codexx"`**（T04 review M1：字面釘死之前這個 mutation **全量零新紅**） | `codexHooksJSONMatchesF14Verbatim`（12 個 entry 逐格 ＋ 對抗式路徑 round-trip ＋ 跨 module `generatedFlagIsUnderstoodByTheParser`） | | T04 |
| CX7 | `AgentArgumentTests` | ① 未知值改成回 `.codex` ② **改成「第一個*有效*者勝」→ 第 8 格必須紅** | `agentArgumentParsing`（**8 格**共用表 ＋ 定義域非空守衛） | | T02／T01b |
| CX8 | `AuraHookCLITests`（E2E） | 解析失敗時寫 stderr | `auraHookStaysSilentForEveryAgentArgument`（**同一張 8 格表**） | | T05 |
| CX9 | `AgentThreadingTests` ＋ `EndToEndWiredGateTests` | ① `storedRawValue` 對 `.claude` 回 `"claude"` ② **`agent` 改成非 Optional 帶預設 `""`（或自訂 encode 寫出 null）→ 生產層那半必須紅** | `claudeStateFileHasNoAgentKey`（**兩層**：純函式層用生產的 `SnapshotIO.encoder` 驗鍵不存在；生產層真 spawn 讀原始檔案驗位元組） | | T05 |
| CX10 | `EndToEndWiredGateTests` | `main.swift` 忘了傳 agent | `codexStateFileCarriesAgent` | | T05 |
| CX11 | `AgentSnapshotCodableTests` | `agent` 改成非 Optional | `legacySnapshotWithoutAgentDecodes` | | T05 |
| CX12 | `AgentSnapshotCodableTests` | `agent` 改成 `Agent?`（enum） | `unknownAgentFallsBackWithoutFailingDecode` | | T05 |
| CX13 | `Round4FixtureTests` | ① `Stop` 改成 `.noChange` ② **從 fixture 抽掉某個事件的一個欄位**（例如 `SessionStart` 的 `model`）→ **欄位層那半必須紅** | `round4FixtureParsesAndMatchesProbeTable`（事件層 ＋ **欄位層**兩層反向斷言） | | T05／T01 |
| **CX14** | `CodexPathScopeTests` | connect 順手寫 `hooks.json.bak` | `codexInstallerTouchesOnlyHooksJSON` | | T06 |
| **CX15** | `CodexInstallerClobberTests` | 拿掉 `O_EXCL` | `codexConnectRefusesEveryOccupiedShape`（**報告寫明哪一格紅：symlink→`config.toml`**） | | T06 · **抽驗必做** |
| CX16 | `CodexInstallerTests` | 少寫最後一個 byte | `codexConnectWritesGeneratorBytes` | | T06 |
| CX17 | `CodexInstallerTests` | ① 拿掉內容比對 ② 拿掉 `(dev,ino)` 複查 | `codexDisconnectOnlyRemovesOurBytes` | | T06 |
| CX18 | `CodexPathScopeTests` | 快照改用字面路徑 | `codexHomeSymlinkWritesInsideResolvedPath` | | T06 |
| CX19 | `CodexStateTests` | ① `symlink` 併進 `.notConnected` ② 判定表第 2／3 列對調 | `codexStateCoversEveryObservationShape` | | T07 |
| CX20 | `CodexOptionsRowTests` | ① `.unavailable` 也給「接上 Codex」 ② **被拒時仍給「重新接上」** | `codexRowsAppearOnlyWhenAvailable` | | T07 |
| CX21 | `OptionsMenuModelTests`／`CodexOptionsRowTests` | `.connectCodex` 塞進 `nonMenuKinds` | 既有 `optionsRowsCoverEveryAction` ＋ `nonMenuKindsIsExactlyThatLiteralSet` | | T07 |
| CX22 | `PanelViewModelTests` ＋ `CodexRowLabelPixelTests` | `agentLabel` 對 `.claude` 也給值 | `agentLabelOnlyForNonClaude`（model ＋ 像素兩半） | | T08／T09 |
| **CX23** | `CodexRowLabelPixelTests` | 標籤另起一行 | `codexLabelDoesNotChangeRowHeight` | | T09 |
| **CX24** | `CodexWiringSmokeTests` | ① 分支改 `break` ② banner 只留一句 ③ 拿掉 `onOpen` 的 `reprobeCodex()` | `codexConnectChainIsWired`（五段；③ 紅在第五段；第③段比對**位元組**） | | T10 |
| CX25 | `CodexWiringSmokeTests` ＋ 掃描 | `codexHome` 改成 `environment["HOME"]` | `productionCodexHomeIsRealHome` | | T10 |
| CX26 | `UninstallerTests` | codex disconnect 與 `erasePersistentDomain` 對調 | `uninstallRemovesCodexBeforeErasingDefaults` | | T10 |
| CX27 | script gate | 拿掉腳本第 7 項 | `verifyUninstallScriptDetectsOurCodexHooks`（**判準是 `--only 7` 那一行**） | | T11 |
| CX28 | `HelpDocOptionsRowCoverageTests` | **只刪掉其中一個 Codex 列標題** | `allRows` 對 `CodexStateKind.allCases` 取聯集後的兩語言各一條 | | T11 |
| CX29 | 文件掃描 | 從 SECURITY.md 刪掉 `.codex/hooks.json` | `securityDocListsEveryPathWeWrite` | | T11 |
| CX30 | 全 repo 掃描 | 腳本加一行 `codex exec` | `noCodexExecInRepo` | | T11 |
| **CX31** | `CodexHookStoreTests` | 在 `write` 裡加 `trimmingCharacters` | `codexHookStoreRoundTripsBytes`（輸入用**真正的產生器輸出**，逐位元組） | | T10 |
| **CX32** | `CodexInstallerClobberTests` | 拿掉 `connect` 第一行的 guard | `codexConnectRefusesBlockedBundlePath`（**且整棵樹零差異**） | | T06 · **抽驗必做** |
| **CX33** | `CodexHookPathCheckTests` | ① 一律回 `.unsupportedCharacter(" ")` ② 優先序對調 | `codexPathCheckNamesTheOffendingCharacter`（定義域從 `unsupportedCharacters` 推導） | | T04 |
| **CX34** | `CodexStateTests` | `from` 忽略 `currentExpectedContents` | `codexStalePathIsDetectedAndOffersReconnect` | | T07 |
| **CX35** | `CodexWiringSmokeTests` | stale 時直接 `connect`（不先 disconnect） | `stalePathReconnectDisconnectsBeforeConnecting`（**前提：`pathRejection == nil`**） | | T10 |
| **CX36** | `CodexSectionRenderTests` | ① 錯誤文案不插字元（籠統句） ② **被拒時仍畫「重新接上」按鈕** | `codexSectionRendersEveryState`（六態 ＋ 兩種 Rejection） | | T09 |
| **CX37a** | `CodexCoexistenceSequenceTests` | `CodexInstaller.connect` 順手 touch `<claudeHome>/skills/agentaura` 的 mtime（**CX37a 與 CX37b 都必須紅**，兩條都記） | `bothSidesNeverDisturbEachOthersFiles`（**780 條全跑**，`connectClaude` 走 `guardWriteTarget()` ＋ `atomicReplace()`，零 spawn） | | T06 |
| **CX37b** | `CodexCoexistenceSequenceTests` | 同 CX37a | `bothSidesNeverDisturbEachOthersFilesOnProductionPath`（長度 ≤ 2 共 30 條，完整 `connect`，11 次真 spawn） | | T06 |
| **CX38** | `EndToEndWiredGateTests`（或拆出的 `EndToEndDualAgentTests`） | `--agent` 解析改成一律回 `.claude` | `oneBinaryServesBothAgentsInOneRoot`（兩個方向各跑一次） | | T05 |
| **CX39** | `CodexWiringSmokeTests` | **把 R-9 的 guard 移到 `disconnect` 之後** | `codexReconnectNeverDisconnectsWhenPathIsRejected`（`disconnect` 次數 0、檔案仍在） | | T10 · **抽驗必做** |
| **CX40** | `CodexStateTests` ＋ `CodexWiringSmokeTests` | 拿掉 `codexSnippet` 的條件（無條件給 snippet） | `codexSnippetIsWithheldWhenPathWillVanish`（**乘積表**，`.mustMoveToApplications` 整行 nil） | | T10 |
| **CX41** | `JargonCodexModelTests` | ① Codex 分支回傳 raw（**既有 `everyFixtureModelIsMapped` 也必須紅**，兩條都記） ② 把 `o3` 改成 `O3` ③ **把 Codex 分支移到既有演算法之後 → `gpt-5` 那列必須紅** | `jargonModelCoversCodexNaming`（釘死的輸入→輸出表**九列**，含 `gpt-5`／`gpt-4.1-mini`／`gpt-5.5[high]`；既有九列輸出完全不變） | | T05 |
| **CX42** | `CodexCredentialSequenceTests` | `performDisconnect()` 順手 `defaults.removeObject(forKey: CodexHookStore.key)` | `bothSidesNeverDisturbEachOthersCredentials`（**20 條**長度 ≤ 2 序列，fake ＋ 注入 suite、零 spawn；另一側鍵位元組不變 ＋ 鍵集合**差集**斷言） | | T10 |
| **CX44** | 全 repo 掃描 | 在 `Tests/` 留一個 `#if AURA_CODEX_PENDING_T05` | `noPendingFlagRemains`（`Tests/` 不得殘留 `AURA_CODEX_PENDING`；**含暫存目錄正向對照**） | | T12 |
| **CX45** | `SessionState` 來源掃描 | 在 `Sources/` 加第二個 `SessionState(` 建構點且不傳 `agent:` | `sessionStateProductionConstructionSitesPassAgent`（`Sources/` 的 `SessionState(` 恰 1 處且含 `agent:`） | | T05d |

**額外必記的三筆（不是新 gate，是回歸證人）**
1. T01 的 `DirectoryTreeSnapshot` 抽取之後，**當場重跑既有 `installerTouchesOnlyAllowedPaths`
   的 mutation** 確認仍精準紅。
2. 三個純搬移（`AppDelegate+Links.swift`／`CodexOptionsRowTests.swift`／`AppDelegateCodexWiredTests.swift`）：
   搬完 `#expect` 總數不變，被搬動的測試函式名一字不改。
3. **`JargonTests.modelTwoNonNumericSegmentsPassesThrough` 的輸入從 `gpt-4o` 換成非 Codex 家族的
   例子**（性質保住）＋**新增**一列釘死 `gpt-4o` 的新期望值——報告要把「改前／改後／測的還是不是
   同一件事」三欄擺在一起。直接刪掉那條測試＝弱化，要退回。

## 里程碑量測（T12 之前的實測紀錄，逐 task 累積）

DoD #2 要求**每個 task 的報告附該 commit 的絕對值**，這裡是彙總；T12 直接引用，不必回頭翻報告。

| 里程碑 | commit | `grep -rho '#expect(' Tests \| wc -l` | 全量 `swift test` |
|---|---|---|---|
| 基準 | `be136d6` | **1649** | — |
| T04 交付 | `6da2ea6` | **1758** | — |
| **T05 交付（T01–T05 已 merge）** | `ad174e7` | **1792** | **828 tests / 1 issue** |

**T01–T05 merge 後只剩 1 個紅**：`codexConnectChainIsWired`（pending T10）。
T01 時的三條紅已經關掉兩條——`round4FixtureParsesAndMatchesProbeTable`（T05 解除 pending）、
`everyFixtureModelIsMapped`（T05b 的 `Jargon` Codex 命名修好，那是 fixture 進 repo 暴露的既有缺口）。
**T06 及之後的 implementer 開工前看到這 1 條是正常的**，其餘任何紅都不是基準。

## 使用者實機清單（自動化做不到的八件事；T12 交付）

`codex exec` 會寫 `[projects."<cwd>"] trust_level`（F12），**這八項一律由人跑，不進任何腳本**。
跑之前先 `cp ~/.codex/config.toml <副本>`，跑完用 `diff` 對 #6b 判讀。

| # | 操作 | 預期 | 實際（請填） |
|---|---|---|---|
| ① | 在**有** `~/.codex` 的機器開面板；再在**沒有**的機器開一次 | 有：看得到「接上 Codex」；沒有：**完全看不到任何 Codex 字樣**，版面與改動前一致 | |
| ② | 按「接上 Codex」 | `~/.codex/hooks.json` 出現；內容**逐字**是 F14 的形狀（12 個事件、`matcher: ""`、無 `async`、絕對路徑 ＋ `--agent codex`），**唯一數值偏離是 `timeout: 3`**；`config.toml` 未新增 `[hooks*]` 段 | |
| ③ | 開一個**新的** Codex session（互動 TUI，不是 `codex exec`）→ 問信任 → 同意 → 跑一個工具 | (a) 燈真的動（working → done），面板出現帶「Codex」標籤的列。(b) **stderr 不得出現 clamping 警告**（`timeout: 3` 的預期；若仍出現，記下原文——代表 Codex 用 `>=`，行為無損但 §10-9 的推論要更新）。(c) **記 `ps -o ppid=,comm=`** 補 F15 的範圍限定 | |
| ④ | 再開一個 session，信任提示**按拒絕** | 燈不動；**App 不得宣稱已生效** | |
| ⑤ | 先手動放一份自己的 `~/.codex/hooks.json`（不含 `--agent codex`）→ 開面板 | 顯示 snippet、**沒有**一鍵接上按鈕；該檔位元組前後相同；複製鈕真的把 snippet 放進剪貼簿 | |
| ⑥ | 在 ② 的狀態下執行「完整移除」→ 跑 `scripts/verify-uninstall.sh` | 7 項全 PASS；接著重做 ⑤ 的情境再移除一次 → **別人的 hooks.json 仍在** | |
| ⑦ | 把 app 放在路徑含空白的位置（`~/My Apps/AgentAura.app`）→ 開面板；另外從掛載的 `.dmg` 直接雙擊開一次 | 兩者都**看不到「接上 Codex」按鈕**，改看到解釋：含空白那次**指名那個字元**且提供 snippet ＋「複製」；DMG 那次說「先把 App 移到『應用程式』」且**不提供 snippet**。兩次都**不得**產生 `~/.codex/hooks.json` | |
| ⑧ | **(R-8)** 先接 Claude → 接 Codex → 對 Codex 斷開、重接、完整移除各一次 → 檢查 Claude 側；反向同理（對 Claude 操作後檢查 Codex 側）；最後兩側都接上、**各開一個 session** | 每一步之後：另一側的 `~/.claude/settings.json` 與 `skills/agentaura`（或 `~/.codex/hooks.json`）**位元組不變**，面板上另一側的狀態不變；最後**兩邊的燈都會動**，面板同時看得到兩側的列（Codex 那列有標籤） | |
| ⑧補 | **在 ② 的狀態下，從 DMG 副本打開一次 App**（r3 B1 的情境） | 面板說「先把 App 移到『應用程式』再回來重新接上」、**沒有「重新接上」按鈕**；**`~/.codex/hooks.json` 必須還在**（位元組不變）——這是 R-9 的人類面驗收 | |

**⑦ 不再量「含空白路徑貼上去 Codex 會不會動」**——那是探索性量測，已移到互動探針工具包
（argv `--agent codex-quoted`）。DoD 實機清單是**驗收**，不該混進探索性量測（r2 M4）。

## Known gaps（spec §10 沿用 15 條；T12 若有新增在此追加）

沿用 spec r5 §10 第 1–16 條（Codex 互動事件形狀待驗、無 error 來源、無法偵測信任、不寫 `async`、
**第 5 條已由 F14 關閉**、TOCTOU 窄窗、`codex exec` 不可用於自動驗收、F15 的三項範圍限定、
`timeout: 3` 未觀測 ＋ 失去診斷訊號、裸路徑遇到空白未測、兩個 agent 共用狀態目錄、
App 搬家的偵測延遲、**R-8 不變式 2 的人類面只有實機 ⑧**、
**序列長度上限**（CX37a 全部 ≤4／CX37b 生產路徑 ≤2／CX42 憑證 ≤2）、
**`Jargon` 的 Codex 分支只有 `gpt-5.5` 是實測**、
**兩個上游的 session id 空間不交集是明寫的假設**——CX38 的「互不覆蓋」是結構性結論不是被測性質），
逐字見 spec §10。

| # | 內容 | 性質 | 落點 |
|---|---|---|---|
| | （T12 量測後追加） | | |
