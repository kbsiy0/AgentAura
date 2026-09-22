# DoD 帳本 · `change/codex-support`（T12）

spec `docs/superpowers/specs/2026-09-18-codex-support-design.md`（**r16**）§7 為門檻來源；
證據層 `docs/2026-09-18-codex-hook-probe.md`（**F1–F15**，F15 以 `8fdce0b` 的版本為準）。
基準取自 `change/codex-support` 分支點（`c131c30`，＝ `main` ＋ 探針文件），量測時用
`git worktree add <temp> <基準> --detach` 取乾淨副本，**不動共享工作目錄**。

**本檔在 T12 執行前寫好門檻與量法；「實測」「判定」兩欄由 T12 填。**
門檻不得在量完之後往下調——miss 就記 known gap（本專案已有兩次前例：+292 KB、+746 KB，
都是如實記錄不調門檻）。

**gate 編號**：本 change 新增的一律 `CX<n>`（**57 條**；CX37 拆成 a／b，CX43 未使用，**CX47–CX57 是 T13 的 persona r1 修復批次**）；既有 gate 一律寫測試函式名。

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
| 機械改動 fan-out | `PanelModel.make(` **63 處／27 檔**（T08 實測，括號配對；`grep` 抓不到隱式成員寫法）；`OptionsMenuModel.rows(` **26 處／10 檔**；`MergeRules.merge(` **7 處**。**這些數字不是驗收條件**（T08 裁決 1）——三個新參數無預設值，編譯通過即證明全部呼叫點已更新；計數只作報告資訊（文字比對數呼叫點在本 change 已連錯五次） |
| 已在上限的檔 | `AppDelegate+PanelActions.swift` **200**／`OptionsMenuModelTests.swift` **300**／`AppDelegatePanelActionsWiredTests.swift` **300**（另 `MergeRulesTests` 294、`PanelViewModelTests` 288、`EndToEndWiredGateTests` 149） |
| `round4-codex.ndjson` | 18 筆／4 個 session；`SessionStart` 4、`UserPromptSubmit` 4、`Stop` 4、`SessionEnd` 4、`PreToolUse` 1、`PostToolUse` 1；**零筆 `Interrupt`**。唯一 `model` = `gpt-5.5`；唯一 `permission_mode` = `bypassPermissions`（已在映射表）；**無 `effort`** |
| 既有紅燈 | `everyFixtureModelIsMapped` 1 issue（見上） |
| `~/.codex/config.toml` | T12 開工當下現場存一份副本，全程用 `diff` 比對 |

## DoD 全表

| # | 項目 | 門檻 | 量法 | 實測 | 判定 |
|---|---|---|---|---|---|
| 1 | 測試全綠 | 連跑 **3 次** 0 flake，**含修好 `everyFixtureModelIsMapped`**、**且 `AURA_CODEX_PENDING_T05`／`_T10` 兩個旗標都已解除**（T05／T10 各自的驗收要附解除前／後的 `#expect` 與測試函式數，**只准上升**）；每次存全量 log | `swift test` ×3 ＋ CX44 | **T12（首輪）**：3 輪皆 646＋291＝937 tests／0 issue。**T12b（T13 之後重跑，2026-09-22，tip `c22fb12`）**：3 輪皆 **657＋312＝969 tests／0 issue／0 flake**（log：`scratchpad/t12b/swift-test-run1/2/3.log`）；三輪皆未觀測到既有 `CompositionRootTests` flake（grep 三份 log 皆 0 命中，未觸發不代表已修復，只是這 3 輪沒撞上）。`grep AURA_CODEX_PENDING Sources Tests` 兩處皆 0 命中 | **PASS** |
| 2 | 新增測試數 | `#expect(` 淨增 **≥ 180**（基準 **1649**）；新增測試函式 **≥ 65**。**量法一次定案**（T04 review m3）：指令固定 `grep -rho '#expect(' Tests \| wc -l`，**每個 task 的報告附該 commit 的絕對值**（不只增量）——只報增量時，兩個端點各差 3 也看不出來。r4 是 170／62，**r5 增量＝CX42 約 +5、Jargon 三列 +3、CX37 拆 a／b +2**（`grep -c '#expect'` 數的是**原始碼出現次數**，迴圈只算一次——20／780 條序列不會讓這個數字暴增） | 前後 **`grep -rho '#expect(' Tests \| wc -l`**；`swift test` 的 tests 計數 | **T12（首輪）**：HEAD `#expect(`=2025、`@Test`=941。**T12b（T13 之後，tip `c22fb12`）**：HEAD `#expect(`=**2083**、`@Test`=**977**。對 `c131c30`（1649／768）：+434／+209。對現 main `9ec85d0`（1652／770，真實貢獻）：+431／+207。兩個基準都遠超門檻（≥180／≥65） | **PASS** |
| 3 | gate mutation 帳 | **57 條**（CX1–CX57，CX37 拆 a／b，CX43 未使用）逐條有 `mutation / 指名測試 / 秒數`；**抽驗 5 筆現場重跑**（必含 CX2、CX4、CX15、CX32、**CX39**）。**T13 追加**：CX47–CX57 **11 條全部**要有秒數（不是抽驗——它們是本輪新寫的），**含兩個等價 mutant**（CX47②／CX49③）的「預期綠」紀錄 | 彙整 T02–T11 的完成報告 ＋ 現場重跑 | **T12（首輪）5 筆抽驗**：CX2 0.001s、CX4 0.001s、CX15 0.008s、CX32 0.007s、CX39 0.180s，皆還原後乾淨＋CX44 新做（Sources 0.032s／Tests 0.056s）。**T12b（T13 之後）新增 3 筆現場重跑**（team-lead 指定）：**CX40**（mutation②「只扣 `.mustMoveToApplications` 一種」，App 半 `codexConnectChainIsWired` 14 issues／**0.228s**，與帳本記載的 0.222s 一致）；**CX51**（標題讀取點改回 `install.healthLabel`，②③ 2 issues／**0.004s**，**且 CX50④ 同時紅**——58 issues／0.018s，跟文件「標題改回→②③紅且 CX50④ 也紅」逐字相符）；**CX56**（拿掉 snippet 固定高度，用**指名的 gate 名** `--filter snippetCardFitsOnA13InchScreen` 一次跑出 `_1`–`_4` 四支，2 issues／**2.232s**，與帳本記載 3.9s 同一量級）。三筆皆還原後 `git status` 乾淨。**新增：CX1–CX57 gate 名 `--filter` 全量掃描**（T12b 常設項目，見下方新表與 known gap 37）——66 個候選名稱裡 **14 個帳本指名的函式不存在**（逐一核對原始碼、找出真正的測試函式名），另兩個是「概念性描述」而非字面函式名（CX21／CX28）、一個是腳本層 gate（CX27，非 swift test，掃描方法本身不適用）。**其餘 ~34 條沒有秒數的仍未彙整**（同 T12 首輪缺口，73 個 commit 全文本轉錄超出本輪時間預算） | **PARTIAL**（8 筆現場重跑全部成功；gate 名掃描新增發現 14 處文件/程式碼名稱不符，已列表並更正；46 條逐一秒數仍未全部彙整齊） |
| 4 | **Claude 側零回歸**（紅線） | `git diff <基準>..HEAD -- plugin/hooks/hooks.json` **完全為空**；`handledEvents` 的 19 個名字一字未動 | `git diff` ＋ 逐行看 `EventMapping.swift` 的 diff | `git diff c131c30..HEAD -- plugin/hooks/hooks.json` 輸出為空。`EventMapping.swift` 的 diff 只有純新增（`codexEvents`／`codexOnlyEvents`／`case "Interrupt"`），`handledEvents` 陣列內文字一行未動（逐行核對過） | **PASS** |
| 5 | **Claude 狀態檔位元組不變** | round1／1b／2／3 跑 merge（用**生產的** `SnapshotIO.encoder`）序列化後**不含 `agent` 鍵**；**且**不帶 `--agent` 真 spawn 一次後，**原始檔案文字**不含 `"agent"` | CX9 **兩層**；**這一格的證據以生產層那半為準**（`agent == nil` ≠「檔案裡沒有這個鍵」——自訂 encode 可能寫出 `"agent":null`，解碼回來仍是 nil 而上游全綠） | `swift test --filter "claudeStateFileHasNoAgentKey\|codexStateFileCarriesAgent"`：3 tests 全綠（純函式層 0.017s；生產層真 spawn 0.022s；CX10 真 spawn 1.006s） | **PASS** |
| 6a | **`config.toml` 零變動（自動化側）** | `swift test` ×3 全程位元組完全不變 | 開工前存副本，跑完 `diff` | 開工前存 md5＝`74472e19f4985c5f6675df4ce20d3f7a`；3 輪 `swift test` 全跑完後 `diff`／`md5` 完全相符；`~/.codex/hooks.json` 全程未出現 | **PASS** |
| 6b | **`config.toml` 受控變動（實機側）** | 實機 ①–⑧ 跑完：**不得新增任何 `[hooks*]` 段**，diff **僅限** `[projects.*] trust_level`（F12） | `diff <副本> ~/.codex/config.toml` 逐行判讀 | 實機清單留給使用者跑，integrator 不執行互動式安裝流程 | **N/A（實機，留給使用者）** |
| 7 | `Sources/` 淨增 | **≤ 1150 行**（基準 7846 → ≤ 8996）；逐檔估算 ≈ 1060（spec §8.1），留 8% 餘裕。r3 是 975／門檻 1050；**r4 增量＝Jargon +30、RejectionKind +20、stale/snippet 兩種文案與分支 +35**。**若 R-5／R-6 日後被砍，門檻要跟著降回 900／啟動 +2 ms**，否則就變成「先加需求再放寬門檻」的通道。**超過就先砍 instrumentation 與非必要碼，不調門檻** | `find Sources -name '*.swift' \| xargs cat \| wc -l` | HEAD＝**9403**。對 `c131c30`（7846）：**+1557**。對現 main `9ec85d0`（7876，merge main 對 Sources 淨增實測是 **0**——見下方「merge main 對 Sources 無淨增」附註）：**+1527（本 change 真實貢獻）**。兩個基準都超門檻 1150。逐檔估／實對照與可砍候選見下方新增小節 | **MISS**（超標 377–407 行，逐檔對照見下）。**T13 後（2026-09-22，`c3db1da`）：9713 行——對 `c131c30` +1867、對 main `9ec85d0` +1837，MISS 約 687–717。T13 自己的增量約 310（9403 → 9713），r13 估 270。門檻不調（known gap 26）。** |
| 8 | 單檔行數 | `Sources/` ≤ 200、`Tests/` ≤ 300，**零例外**；三個預先拆檔各自是零行為變更的獨立 commit（`AppDelegate+Links.swift` **在 T07**——r9 從 T10 提前，理由見 plan T07 第一步 (b)；`CodexOptionsRowTests.swift` 在 T07；`AppDelegateCodexWiredTests.swift` 在 T10） | `IsolationTests.fileLengthLimit` ＋ 手動複查最大的 5 個檔 ＋ 三個搬移 commit 的 diff | **T12（首輪）**：GREEN，三個搬移 commit 核對過。**T12b（T13 之後）**：`IsolationTests.fileLengthLimit` 仍 GREEN（含在 969 tests 裡）。現場複查最緊的檔：`Sources/AgentAuraApp/StatusItemController.swift` **200/200（零餘裕）**、`PanelModel.swift` 194、`InstallAffordance.swift` 194、`PanelView.swift` 190、`InstallState.swift` 179。**Tests/ 也有兩個零餘裕的檔，T13k 的驗收清單沒提到**：`Tests/AuraCoreTests/SnapshotIOTests.swift` **300/300**、`Tests/AgentAuraAppTests/CodexEvidenceRenderer.swift` **300/300**（另 `AppDelegatePanelActionsWiredTests.swift` 298/300，T13k 已記）——下一次動這三個 Tests 檔也要先拆 | **PASS**（新發現兩個零餘裕的 Tests 檔，已補進報告與 known gaps） |
| 9 | 零新依賴／新 target | `Package.swift` diff 為空 | `git diff -- Package.swift` | `git diff c131c30..HEAD -- Package.swift` 輸出為空 | **PASS** |
| 10 | module 基準 | `AuraCore` = Foundation、`AuraHookFile` = Foundation ＋ CoreServices。**`AuraHookFile` 不得 import Security**（`RunningBundle` 是 App 層唯一計算點） | `IsolationTests.nonUITargetsLoadNoUIModules` | 測試 GREEN（17.05s）；`grep -rn "import Security" Sources/AuraHookFile/` 0 命中；全 repo 只有 `Sources/AgentAuraApp/RunningBundle.swift` import Security | **PASS** |
| 11 | 執行檔增量 | **≤ +200 KB** universal（基準 3,140,864）。依據：既有兩次量到的「每新增一個 SwiftUI view ≈ 60–80 KB/arch」，本 change 新增 1 個 view | `./scripts/build-app.sh` 後 `ls -l` | **T12（首輪）**：簽章後 HEAD＝3,774,704，對 `c131c30`（3,170,688）+604,016 bytes、對 `9ec85d0`（3,170,192）+604,512 bytes（`build-app.sh` 的 stale-lipo bug 仍在，沿用手動 lipo 法）。**T12b（T13 之後，tip `c22fb12`）**：手動 lipo＋簽章＝**3,815,328 bytes**。對 `c131c30`：**+644,640 bytes（+630 KB）**；對 `9ec85d0`：**+645,136 bytes（+630 KB）**；對 T12 首輪 HEAD（T13 自己這批的貢獻）：**+40,624 bytes（+40 KB）**——persona r1 修復批次本身只加了約 40 KB，符合「主要膨脹在 T01–T12 就已發生，T13 是修復不是新功能」的預期 | **MISS**（超標約 3.2 倍；`build-app.sh` 的 stale-lipo bug 仍未修，見 known gap 21） |
| 12 | **面板路徑成本** | **`reprobeCodex()` 100 次 ≤ 10 ms**（穩態；`.notConnected` 與 `.connected` **各量一次並分開記**）。**量 `reprobeCodex()` 端到端，不是只量 `probe()`**——那才是 `onOpen` 實際跑的東西（r3 m3）。可並列 `CodexInstaller.probe()` 的數字供分解 | 行程內暫時測試（`ContinuousClock`），跑完即刪、`git status` 確認乾淨 | **T12（首輪）**：`.notConnected` 0.0714–0.0814 ms、`.connected` 0.1173–0.1276 ms。**T12b（T13 之後，`applicationDidFinishLaunching` 已搬到 `AppDelegate+Lifecycle.swift`，公開 API 不變）**：暫時測試檔 `_T12bTempPerfTests.swift` 3 輪：`.notConnected` 100 次 = **0.0774–0.0789 ms**、`.connected` 100 次 = **0.1157–0.1289 ms**——與 T13 前幾乎相同，T13a 純搬移沒有引入任何成本。量完已刪，`git status` 乾淨 | **PASS**（遠低於 10 ms，餘裕 ＞98%） |
| 13 | 啟動時間增幅 | **≤ +3 ms**（多一次 `lstat`、最多讀 64 KiB、一次 `SecTranslocateIsTranslocatedURL`、一次產生器呼叫——**四個行程常數搬到啟動時算**，D-t） | `applicationDidFinishLaunching` 首尾時戳，各 3 輪 × 10 次取中位數；基準側在 worktree 量 | **T12（首輪）**：HEAD（`production()`＋`init`＋`launch`＋`terminate`）3 輪中位數 1.127／1.210／1.293 ms；基準（`c131c30`）2.052／2.092／2.112 ms，增量為負。**T12b（T13 之後）**：同一支暫時測試在 T13 tip 重跑，3 輪中位數 **1.091／1.093／1.077 ms**——與 T12 首輪幾乎相同（±0.1ms 內），confirm T13a 的純搬移沒有改變啟動路徑的實際成本。沿用 T12 首輪的基準（`c131c30` 2.052–2.112 ms，T13 未動基準側程式碼），**增量仍為負** | **PASS**（未偵測到回歸；跨量測輪次噪訊在 ±0.1ms 內，遠小於 3ms 門檻） |
| 14 | RSS 增幅 | **≤ 1 MB** | `scripts/measure-cpu.sh`（先隔離量測者自己的 session） | **T12（首輪）**：未量到——`measure-cpu.sh` 第一步 `pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp"` 會連帶殺掉使用者機器上正在跑的正式安裝（DoD#19 已實測證實此風險），且腳本結尾不會自動重開，全程 5 態 × (6s+60s) ≈ 5.5 分鐘期間使用者選單列會被換成本地測試 build。**T12b（T13 之後）**：team-lead 已指示本輪不跑（沿用 T12 判定），bundle 佈局 T13 沒動，pkill bug 仍待獨立 change 修 | **未量到（環境風險，沿用 T12 判定，需使用者裁決量測時機/方式）** |
| 15 | 動畫態 CPU | 不得比基準更差（五態各量） | `scripts/measure-cpu.sh`，連續兩輪 | 同 #14，同一支腳本、同一個風險，**T12b 沿用 T12 判定不重跑** | **未量到（同 #14 原因，沿用 T12 判定）** |
| 16 | plugin 契約 | 零 error 零 warning。**這也是 `Interrupt` 接縫的第四道防線、且是唯一一道不依賴我們自己寫的斷言的**（T03 review 實測：註冊 `Interrupt` → `unknown hook event; entry ignored at runtime` ＋ `--strict` 視 warning 為 error → 失敗）。**注意**：本機 validator 只給 warning，**整份拒載是 2026-09-15 在同事機器上量到的**（`distribution-and-hook-compat`）——本機通過不構成「全有全無」的反證 | `claude plugin validate --strict ./plugin` 與 `.` | 兩者皆輸出「✔ Validation passed」，零 error 零 warning | **PASS** |
| 17 | 安裝鏈路（Claude） | 全項 PASS（含 `settings.json` 零污染、一輪真的 `claude -p`） | `./scripts/verify-install.sh` | **T12（首輪）與 T12b（T13 之後）皆重跑**：全 5 大項全部 ✓（plugin 二進位／已註冊／validator 乾淨／settings.json 零污染／實機跑一輪狀態檔數量遞增／狀態檔內容合理）。T12b 這次狀態檔 5→6。跑前後安裝狀態（symlink 指向 `/Applications/AgentAura.app`、settings.json 零污染）未被腳本改動 | **PASS** |
| 18 | 完整移除 | `verify-uninstall.sh` **7 項全 PASS**；第 7 項兩個方向都驗過；`--only 7` 可單獨執行且**不觸發** `osascript`／`sfltool` | CX27 ＋ 實機 ⑥ | **T12（首輪）與 T12b（T13 之後）皆重跑** `./scripts/verify-uninstall.sh --only 7` → 「✓ Codex hook 已移除或從未接上」，未觸發 `osascript`／`sfltool`。CX27 相關測試在全量 `swift test`（969 tests）中已綠 | **PASS**（`--only 7` 這一項；兩個方向的實機驗證與 ⑥ 留給使用者實機清單） |
| 19 | bundle 佈局 | PASS，缺 bundle 時 FAIL 不 skip | `./scripts/verify-app.sh` | **T12（首輪）**：全 6 大項全部 ✓；腳本收尾 `pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp"` 誤殺了使用者正式安裝（PID 2194），已立即重開恢復（新 PID 47885）。**T12b（T13 之後）**：team-lead 已指示本輪不跑（T13 沒動 bundle 佈局，沿用 T12 判定），pkill 風險仍在、待獨立 change 修 | **PASS（沿用 T12 首輪結果）**；連帶殺掉使用者正式安裝的風險已記錄，建議腳本改成只 kill 自己剛開的那個 PID |
| 20 | 測試不得跑 `codex exec` | `Tests/`／`scripts/` 命中數 **= 0**（＋正向對照） | CX30 | `grep -rn "codex exec" Tests/ scripts/ .github/` 只命中 `NoCodexExecInRepoTests.swift`／`CodexEventsTests.swift` 的 doc comment（`///` 開頭，非可執行行）。CX30 測試套件全綠 | **PASS** |
| 21 | 文件路徑一致 | `README.md`／`SECURITY.md` 都含 `.codex/hooks.json` | CX29 | `grep -l ".codex/hooks.json" README.md README.zh-TW.md SECURITY.md` 三份全部命中 | **PASS** |
| 22 | help 涵蓋 | 兩個語言都涵蓋**每一個**新的 Options 列標題（含「重新接上 Codex」） | CX28 | `HelpDocOptionsRowCoverageTests` 全綠（含 CX28 mutation②正向對照，6 test case） | **PASS** |
| 23 | **CX37a／CX37b 的成本** | CX37a **780 條全跑、零 spawn**（毫秒級，**不縮減**）；CX37b **30 條、11 次真 spawn**、走 `SpawnGate`。兩條的 doc comment 要互相點名（a 的等價理由／b 的長度上限理由）。**實測秒數寫進報告** | T06 的完成報告 ＋ 現場重跑 | 現場重跑：CX37a 780 test cases，gate 內部計時 **2.315s**；CX37b 30 test cases，gate 內部計時 **2.291s**。commit 訊息記載的原始數字：CX37a 1.9s／2930 次操作；CX37b 4.2–8.4s（視全套件負載）／11 次 `installer.connect(` 呼叫 | **PASS** |
| 24 | persona | 加權 **≥ 6.0**；硬下限四條（見下） | Tier 1，integrator 綠後派 persona-tester | **r1（2026-09-21）：加權 5.68 / 10，NO-GO**。P1 6.0（下限 5，PASS）· **P2 5.2（下限 6，FAIL）** · P3 5.2（下限 5，PASS 但內含 S0）· P4 6.4（下限 5，PASS）。**S0 × 2、S1 × 7、S2 × 6**。三條 no-go 規則各自獨立成立：兩條 S0 硬否決／P2 低於自己的下限／加權不足。**強 gate**（寫使用者真實 `~/.codex/hooks.json`、公開散佈）→ 判定**綁定、不可繞**。修復批次＝**T13**（spec r13 §0.4 D-v–D-ad），完成後送 **r2 retest** | **FAIL（r1）→ 待 r2** |

### DoD #7 逐檔「估／實」對照（T12 補；估算來自 spec §8.1）

「改」檔的「實」欄是 **HEAD 行數 − c131c30 行數**（該檔淨變化），不是 HEAD 絕對行數。

| 檔案 | 估 | 實（淨變化） | 差 | 備註 |
|---|---|---|---|---|
| `Agent.swift`（新） | ~60 | 80 | +33% | reviewer 已知（doc comment 撐大） |
| `EventMapping.swift`（改） | +25 | +43 | +72% | `codexEvents`／`codexOnlyEvents` 兩個集合＋大段防呆 doc comment |
| `CodexHooksJSON.swift`（新） | ~80 | 79 | −1% | 幾乎精準 |
| `CodexHookPathCheck.swift`（新） | ~75 | 87 | +16% | |
| `CodexState.swift`（新） | ~115 | 67 | −42% | `CodexFailure` 真的被拆出去了（見下一列），母檔因此變小 |
| `CodexFailure.swift`（**新，估算表沒列**） | 0 | 38 | — | spec §8.1 有預告「逼近 200 就拆檔」但沒給獨立估算，這裡是那個拆檔的實際重量 |
| `Jargon.swift`（改） | +30 | +49 | +63% | Codex 命名分支比預期複雜（`gpt-5.5[high]` 等變體） |
| `SessionSnapshot.swift`（改） | +10 | +13 | +30% | |
| `MergeRules.swift`（改） | +6 | +7 | +17% | |
| `SessionReducer.swift`（改） | +2 | +1 | −50% | 絕對值太小，無意義 |
| `SessionState.swift`（改） | +5 | +11 | +120% | |
| `PanelViewModel.swift`（改） | +6 | +4 | −33% | |
| `PanelAction.swift`（改） | +27 | +23 | −15% | |
| `OptionsMenuModel.swift`（改） | +26 | +19 | −27% | 部分邏輯被拆進 `OptionsMenuModel+Codex.swift`（見下） |
| `OptionsMenuModel+Codex.swift`（**新，估算表沒列**） | 0 | 38 | — | 同 `CodexFailure.swift`，母檔變小是因為這裡多了一個檔 |
| `PanelModel.swift`（改） | +14 | +39 | +179% | 本輪單一最大漂移；六態＋兩種 Rejection 的欄位與委派邏輯比估算重 |
| `L10nCodex.swift`（新） | ~145 | 158 | +9% | |
| `L10nCodex+Failures.swift`（**新，估算表完全沒列**） | 0 | 75 | — | 七個 `CodexFailure` 案例的雙語文案，估算表漏列整份檔案 |
| `CodexInstaller.swift`（新） | ~125 | 160 | +28% | |
| `CodexInstaller+Probe.swift`（新） | ~70 | 59 | −16% | |
| `aura-hook/main.swift`（改） | +3 | +15 | +400% | 絕對值小（15 行），比例失真 |
| `CodexHookStore.swift`（新） | ~45 | 41 | −9% | |
| `CodexSectionView.swift`（新） | ~130 | 117 | −10% | |
| `CodexObservation.swift`（**新，估算表沒列**） | 0 | 32 | — | `probe()` 回傳型別，估算表漏列 |
| `CodexState+From.swift`（**新，估算表沒列**） | 0 | 42 | — | 七列判定表抽出的獨立檔，估算表漏列 |
| `AppDelegate+Codex.swift`（新） | ~120 | 174 | +45% | 第二大漂移；`CodexRuntime`／四個 perform／五個常數欄位比估算重 |
| `AppDelegate+Links.swift`（新，純搬移） | ~45 | 49 | +9% | |
| `AppDelegate+PanelActions.swift`（改） | −45+8 | −25（200→175） | — | 淨變化與估算的「−37」方向一致，幅度略小 |
| `PanelView.swift`（改） | +8 | +19 | +138% | |
| `Uninstaller.swift`（改） | +8 | +6 | −25% | |
| `AppDelegate.swift`（改） | +10 | +8 | −20% | |
| 其他零散（`OptionsSectionView.swift`／`StatusItemController+SystemPanels.swift`／`StatusItemController.swift`／`ColorPickerCoordinator.swift`／`IconRendering.swift`／`HookPayload.swift`／`L10nRegistry.swift`／`AppDelegate+Verification.swift`／`main.swift`） | 0（未列） | 約 +69 合計 | — | 其中 `ColorPickerCoordinator.swift`／`IconRendering.swift`／`StatusItemController+SystemPanels.swift` 三個是 PR #7 色板抑制的內容（本 change 分支獨立收斂出同款改動，見「merge main 對 Sources 無淨增」附註），不算 Codex 功能貢獻；`OptionsSectionView.swift` 才是真正漏列的 Codex 相關檔 |

**六個完全沒被 spec §8.1 估算表列到的新檔**（`CodexFailure.swift` 38 行、`CodexObservation.swift` 32 行、`CodexState+From.swift` 42 行、`L10nCodex+Failures.swift` 75 行、`OptionsMenuModel+Codex.swift` 38 行、`OptionsSectionView.swift` 淨 +16 行）合計 **241 行**——這是「逐檔漂移要看得見」原則下最大的單一發現：超標的 377–407 行裡，六成以上來自估算表本身沒預見的檔案拆分，不是既有檔案膨脹。

**可砍候選（只列，不砍——裁決留給使用者）**：
- 逐檔比對後看不到明顯的 instrumentation／偵錯碼；除 `PanelModel.swift`（+179%）與 `AppDelegate+Codex.swift`（+45%）兩個最大漂移外，其餘增幅多是 doc comment（reviewer 已多輪要求加強理由說明，如 `Agent.swift`／`EventMapping.swift`）與拆檔本身的樣板（extension 宣告、import）。
- `L10nCodex+Failures.swift`（75 行）全是雙語文案字串，若能接受較不完整的錯誤訊息覆蓋率，理論上可精簡，但這牴觸「七個 `CodexFailure` 案例都要有雙語訊息」的既有要求，屬於**功能取捨**而非**清理**。
- reviewer 在 T10 review 已試過砍 `EventMapping.swift`／`CodexInstaller.swift` 的 doc comment，結果反而 **+12 行**（m7，doc comment 補得比砍掉的多）——這是本 change 前一輪已驗證過「砍不動」的證據，不是我這輪的猜測。

### persona 硬下限（低於門檻即 no-go，不得用平均分蓋過）

| 代號 | persona | 問題 | 下限 |
|---|---|---|---|
| P1 | 只用 Codex 的人 | Claude 的大版說明與 Codex 的單行提示疊在同一張畫面上，30 秒內知道該按哪個 | **≥ 5** |
| P2 | 已有自己 `~/.codex/hooks.json` 的進階使用者 | 相信我們**不會**動他的檔；snippet 可貼、貼了會動。**三條具體要求**（不另開硬下限）：① 路徑被拒時文案**指名是哪個字元**；② 拒絕必須給出路；③ **從 DMG／下載資料夾打開時，寧可不給 snippet 也不給一份會過期的**（R-10） | **≥ 6** |
| P3 | 不懂「信任」提示的 vibe coding 使用者 | 按下接上之後，知道「還要在 Codex 裡按一次同意」才會生效 | **≥ 5** |
| P4 | 兩個都用的人 | 同專案同時跑時兩列分得出來；**兩側都接上時兩邊的燈都真的會動**（R-8） | **≥ 5** |

### persona r1 結果與 r2 送審條件（2026-09-21）

**r1 判定：NO-GO（加權 5.68／門檻 6.0）**。報告全文由主 session 保管；逐條 finding 與 r13 決策的對應見
spec §9.1。**最值得留著的一句觀察**：四個 persona 裡三個的失分**不是**來自 Codex 功能做錯，
而是來自**既有的 Claude-only 表面沒有跟著這個新訊號一起更新**（S0-1 是 A7 的退場條件、
S1-1 是三個狀態字串、S1-2 是空狀態句）。那些表面在 diff 裡幾乎沒被動到，**所以四道機器關卡全綠是合理的
——它們守的是被改動的碼**。這是 CLAUDE.md Lessons #4（整合接縫）的另一種形狀。

| finding | persona | 處置 | gate |
|---|---|---|---|
| **S0-1** 接上成功 banner 在面板有任何 session 列時被靜默抑制 | P3 | **D-v**（`.codexConnected` 自己的 kind ＋ 退場條件＝出現 **Codex** 的列） | CX47 · **CX48** |
| **S0-2** `.unsupportedCharacter` 點名問題、不點名解法，還遞出含那條壞路徑的設定檔 | P2 | **D-w**（兩種 rejection 都扣住 snippet ＋ 問題／解法兩句） | **CX40 翻轉** · CX49 · CX36④⑤ |
| S1-1 三處狀態字串只反映 Claude | P1／P4 | **D-y** | CX50 · CX51 · CX52 |
| S1-2 Codex banner 下方寫「Once Claude Code starts running…」 | P1／P3 | **D-z** | CX53 |
| S1-3 遞出完整替換檔、零合併指示 | P2 | **D-aa** | CX54 · CX55 |
| S1-4 snippet 區塊無上限不可捲，複製鈕與 footer 被裁出畫面 | P2 | **D-ab** | CX56 |
| S1-5 Codex 移除無確認框，但標題有刪節號、兄弟列有確認框 | P4 | **D-ac** | CX57 |
| S1-6 證據圖 #07 的 snippet 由不含空白的路徑產生 | P2 | **D-ad** | （證據，無 gate） |
| S1-7 頭號情境完全沒有證據圖 | P1 | **D-ad**（新增 #12） | （證據，無 gate） |
| S2-1 stale 那句對 `.unsupportedCharacter` 可查證為假 | P2 | **D-x** | CX36⑥ |
| S2-2 列上「Codex」標籤與權限文字同字級同色 | P4 | **明寫接受** | spec §10-19 |
| S2-3 `.connected` 零常駐正向確認 | P1 | **D-y 順帶關閉** | CX51 |
| S2-4 legend「Error」沒有通往「Codex 沒有 error 燈」的面板內路徑 | P3 | **明寫接受** | spec §10-18 |
| S2-5 10pt 等寬 snippet 是全 app 最小的字、不吃 Dynamic Type | a11y | 既有形狀，本 change 加劇；**明寫接受** | spec §10（沿用） |
| S2-6 `INSTALL.md` 仍寫「one file per Claude Code session」 | doc | **T13k 修** | （文件） |

**r2 retest 的送審條件（四條全部滿足才送）**：
1. **兩條 S0 全關**，且各自的 mutation 在 r12 的碼上實跑過是紅的（不是「應該會紅」）。
2. **七條 S1 全關**，或在 spec §10 明寫接受並附理由（目前規劃全關）。
3. **四條硬下限全過**（P1 ≥5、**P2 ≥6**、P3 ≥5、P4 ≥5）。
4. **加權 ≥ 6.0**。

**r2 要重打的三個地方**（派工時附給 persona-tester）：① 接上 Codex 之後、面板上**有別的 agent 的列**時，
兩句信任警語還在不在；② 只接 Codex 時，標題與 footer chip 寫什麼；
③ `.unsupportedCharacter` 的卡片**現在不給 snippet 了**——要判的是「它有沒有給我一條真的能走的出路」，
不是「為什麼不給我 snippet」（不給的理由見 spec D-w／§10-17，**有解鎖條件**）。

## Gate mutation 帳（57 條；T12 彙整 CX1–CX46，**CX47–CX57 由 T13 填**；✓現場 = 抽驗重跑）

**T12b 提醒**：下表 14 個 gate 的「指名測試」欄字面函式名與原始碼不符（真正的函式名見上方
「T12b：CX1–CX57 gate 名 `--filter` 全量掃描」小節的更正表：CX6、CX17、CX19、CX20、CX22、
CX28、CX29、CX32（已知）、CX33、CX34、CX36、CX41、CX46）——**gate 本身都存在且通過**，
只是文件指名的字面跟實作用的函式名不同步，直接 `--filter <帳本寫的名字>` 會得到 0 tests。
下表暫不逐列改寫（避免跟上面的更正表出現兩份可能漂移的副本），**要用 `--filter` 找測試時
以上面那張表為準**。

| Gate | 位置 | Mutation | 指名測試 | 秒數 | 來源 task |
|---|---|---|---|---|---|
| CX1 | `CodexEventSeamTests` | `codexEvents` 少一個事件（**拿掉的是 `codexEvents` 那一份**；從 `handledEvents` 拿會打到 CX3 而不是這裡） | `codexEventSetIsPinnedToProbe` | | T03 |
| **CX2** | `CodexEventSeamTests` | 把 `Interrupt` 加進 `handledEvents` | `interruptNeverEntersHandledEvents`（**＋既有 `registeredEventsMatchHandledEvents` 也必須紅**） | **0.001s**（T12 現場重跑，兩條都紅） | T03 · **抽驗必做 ✓現場** |
| CX3 | `CodexEventSeamTests` | **從 `handledEvents`** 拿掉 `PreCompact`（子集檢查落空；**從 `codexEvents` 拿只會紅 CX1**，別把「CX3 沒紅」誤讀成 gate 失效——T03 review 實測兩種拿法打到不同 gate） | `codexSharedEventsReuseClaudeMapping` | | T03 |
| **CX4** | `CodexEventSeamTests` | 刪掉 `case "Interrupt"` 整行 | `codexOnlyEventsMapToIdle`（**同時記「加這條 gate 之前同一個 mutation 全綠」**） | **0.001s**（T12 現場重跑） | T03 · **抽驗必做 ✓現場** |
| CX5 | `CodexEventSeamTests` | Claude hooks.json 加 `Interrupt`（**三個獨立觀測點都會紅**：CX5、既有 `registeredEventsMatchHandledEvents`、`claude plugin validate --strict`） | `claudeHooksJSONHasNoInterrupt`（**含定義域非空守衛**） | | T03 |
| CX6 | `CodexHooksJSONTests` | ① 寫死 11 個 ② 拿掉 `matcher` ③ 加 `async: true` ④ 漏 `--agent codex` ⑤ **`timeout` 改回 5** ⑥ **`agentFlag` 改成 `"--agent codexx"`**（T04 review M1：字面釘死之前這個 mutation **全量零新紅**） | `codexHooksJSONMatchesF14Verbatim`（12 個 entry 逐格 ＋ 對抗式路徑 round-trip ＋ 跨 module `generatedFlagIsUnderstoodByTheParser`） | | T04 |
| CX7 | `AgentArgumentTests` | ① 未知值改成回 `.codex` ② **改成「第一個*有效*者勝」→ 第 8 格必須紅** | `agentArgumentParsing`（**8 格**共用表 ＋ 定義域非空守衛） | **~1s**（commit 訊息記載：兩個 mutation 各 1 秒內變紅） | T02／T01b |
| CX8 | `AuraHookCLITests`（E2E） | 解析失敗時寫 stderr | `auraHookStaysSilentForEveryAgentArgument`（**同一張 8 格表**） | | T05 |
| CX9 | `AgentThreadingTests` ＋ `EndToEndWiredGateTests` | ① `storedRawValue` 對 `.claude` 回 `"claude"` ② **`agent` 改成非 Optional 帶預設 `""`（或自訂 encode 寫出 null）→ 生產層那半必須紅** | `claudeStateFileHasNoAgentKey`（**兩層**：純函式層用生產的 `SnapshotIO.encoder` 驗鍵不存在；生產層真 spawn 讀原始檔案驗位元組） | **0.75s**（commit 訊息，`SessionSnapshot.agent` 改非 Optional 帶預設值，2 issues／144 issues）；T12 現場：純函式層 0.017s、生產層 0.022s（正常路徑，非 mutation） | T05 |
| CX10 | `EndToEndWiredGateTests` | `main.swift` 忘了傳 agent | `codexStateFileCarriesAgent` | T12 現場（正常路徑）：1.006s（真 spawn） | T05 |
| CX11 | `AgentSnapshotCodableTests` | `agent` 改成非 Optional | `legacySnapshotWithoutAgentDecodes` | | T05 |
| CX12 | `AgentSnapshotCodableTests` | `agent` 改成 `Agent?`（enum） | `unknownAgentFallsBackWithoutFailingDecode` | | T05 |
| CX13 | `Round4FixtureTests` | ① `Stop` 改成 `.noChange` ② **從 fixture 抽掉某個事件的一個欄位**（例如 `SessionStart` 的 `model`）→ **欄位層那半必須紅** | `round4FixtureParsesAndMatchesProbeTable`（事件層 ＋ **欄位層**兩層反向斷言） | | T05／T01 |
| **CX14** | `CodexPathScopeTests` | connect 順手寫 `hooks.json.bak` | `codexInstallerTouchesOnlyHooksJSON` | | T06 |
| **CX15** | `CodexInstallerClobberTests` | 拿掉 `O_EXCL` | `codexConnectRefusesEveryOccupiedShape`（**報告寫明哪一格紅：symlink→`config.toml`**） | **0.008s**（T12 現場重跑，4 個 test case 全紅，含 symlink→config.toml 那格，delta 顯示 `["config.toml"]` 被覆寫） | T06 · **抽驗必做 ✓現場** |
| CX16 | `CodexInstallerTests` | 少寫最後一個 byte | `codexConnectWritesGeneratorBytes` | | T06 |
| CX17 | `CodexInstallerTests` | ① 拿掉內容比對 ② 拿掉 `(dev,ino)` 複查 | `codexDisconnectOnlyRemovesOurBytes` | | T06 |
| CX18 | `CodexPathScopeTests` | 快照改用字面路徑 | `codexHomeSymlinkWritesInsideResolvedPath` | | T06 |
| CX19 | `CodexStateTests` | ① `symlink` 併進 `.notConnected` ② 判定表第 2／3 列對調 | `codexStateCoversEveryObservationShape` | | T07 |
| CX20 | `CodexOptionsRowTests` | ① `.unavailable` 也給「接上 Codex」 ② **被拒時仍給「重新接上」** | `codexRowsAppearOnlyWhenAvailable` | | T07 |
| CX21 | `OptionsMenuModelTests`／`CodexOptionsRowTests` | `.connectCodex` 塞進 `nonMenuKinds` | 既有 `optionsRowsCoverEveryAction` ＋ `nonMenuKindsIsExactlyThatLiteralSet` | | T07 |
| CX22 | `PanelViewModelTests` ＋ `CodexRowLabelPixelTests` | `agentLabel` 對 `.claude` 也給值 | `agentLabelOnlyForNonClaude`（model ＋ 像素兩半） | | T08／T09 |
| **CX23** | `CodexRowLabelPixelTests` | 標籤另起一行 | `codexLabelDoesNotChangeRowHeight` | | T09 |
| **CX24** | `CodexWiringSmokeTests` | ① 分支改 `break` ② banner 只留一句 ③ 拿掉 `onOpen` 的 `reprobeCodex()` | `codexConnectChainIsWired`（五段；③ 紅在第五段；第③段比對**位元組**）。**T13 註記**：④ 斷言的是**儲存值** `delegate.banner?.text` 且 session graph 是空的——**渲染那一半由 CX48 守**，persona r1 的 S0-1 就活在這個縫裡 | | T10（CX48 於 T13b） |
| CX25 | `CodexWiringSmokeTests` ＋ 掃描 | `codexHome` 改成 `environment["HOME"]` | `productionCodexHomeSourceNeverReadsHomeEnvVar`（來源掃描半，0.022s 變紅）。**`productionCodexHomeIsRealHome`（型別／接線半）對這個 mutation 是等價 mutant**——開發機上 `$HOME` 就等於真 home，實測綠，不代表這條 gate 空轉，它守的是另一件事（生產注入的是真 `CodexInstaller`，不是 fake） | | T10 |
| CX26 | `UninstallerTests` | codex disconnect 與 `erasePersistentDomain` 對調 | `uninstallRemovesCodexBeforeErasingDefaults` | | T10 |
| CX27 | script gate | ① 拿掉腳本第 7 項 ② **拿掉 `--only` 的值域檢查（`[1-7]`）** | `verifyUninstallScriptDetectsOurCodexHooks`（**判準是 `--only 7` 那一行**；**外加兩格**：`--only`（缺值）在有界時間內非零退出、`--only 77` 非零退出且**輸出不含「PASS」**） | | T11 |
| CX28 | `HelpDocOptionsRowCoverageTests` | **只刪掉其中一個 Codex 列標題** | `allRows` 對 `CodexStateKind.allCases` 取聯集後的兩語言各一條 | | T11 |
| CX29 | 文件掃描 | 從 **`SECURITY.md`／`README.md`／`README.zh-TW.md` 任一份**刪掉 `.codex/hooks.json`（**三份各試一次**） | `securityDocListsEveryPathWeWrite`（`@Test(arguments:)` 參數化三份文件） | | T11 |
| CX30 | 全 repo 掃描 | 在 `scripts/` 或 **`.github/`** 加一行 `codex exec` | `noCodexExecInRepo`（roots = `Tests/` ＋ `scripts/` ＋ **`.github/`**；`docs/` 刻意不納入——F12 的證據文件必須逐字寫指令名） | | T11 |
| **CX31** | `CodexHookStoreTests` | 在 `write` 裡加 `trimmingCharacters` | `codexHookStoreRoundTripsBytes`（輸入用**真正的產生器輸出**，逐位元組）——**這個 mutation 對這條輸入是等價 mutant**：`JSONSerialization` 的輸出天生沒有開頭／結尾空白，trim 是 no-op，實測綠。真正紅的是 `codexHookStoreDoesNotTrimBoundaryWhitespace`（0.006s，產生器輸出前後各接一段空白位元組，斷言 `write`／`contents` 不做任何正規化） | | T10 |
| **CX32** | `CodexInstallerClobberTests` | 拿掉 `connect` 第一行的 guard | **帳本原記 `codexConnectRefusesBlockedBundlePath` 是 MARK 註解分組名，不是函式名——實際函式是 `codexConnectRefusesTranslocated`／`codexConnectRefusesInDownloads`**（且整棵樹零差異） | **0.007s**（T12 現場重跑，兩條測試都紅） | T06 · **抽驗必做 ✓現場** |
| **CX33** | `CodexHookPathCheckTests` | ① 一律回 `.unsupportedCharacter(" ")` ② 優先序對調 | `codexPathCheckNamesTheOffendingCharacter`（定義域從 `unsupportedCharacters` 推導） | | T04 |
| **CX34** | `CodexStateTests` | `from` 忽略 `currentExpectedContents` | `codexStalePathIsDetectedAndOffersReconnect` | | T07 |
| **CX35** | `CodexWiringSmokeTests` | stale 時直接 `connect`（不先 disconnect） | `stalePathReconnectDisconnectsBeforeConnecting`（**前提：`pathRejection == nil`**） | | T10 |
| **CX36** | `CodexSectionViewTests` | ① 錯誤文案不插字元（籠統句） ② **被拒時仍畫「重新接上」按鈕** ③ **把 `.mustMoveToApplications` 分支改成會畫 snippet → 必須紅**（T09 review M1：輸入改成真 snippet 之前，這個 mutation 紅 0 條） ④ **T13：把 `.unsupportedCharacter` 分支改回會畫 snippet → 必須紅** ⑤ **T13：拿掉 `.unsupportedCharacter` 的出路句 → 必須紅** ⑥ **T13：`.connectedStalePath` 兩個 rejection 改回共用一句 → 必須紅**（r12 是同一句，證據圖 `10`／`11` 因此位元組完全相同） | `codexSectionRendersEveryState`（六態 ＋ 兩種 Rejection；**兩個** blocked 那格都**必須餵真的 `codexSnippet`**） | | T09 · **T13d／T13e 擴充** |
| **CX37a** | `CodexCoexistenceSequenceTests` | `CodexInstaller.connect` 順手 touch `<claudeHome>/skills/agentaura` 的 mtime（**CX37a 與 CX37b 都必須紅**，兩條都記） | `bothSidesNeverDisturbEachOthersFiles`（**780 條全跑**，`connectClaude` 走 `guardWriteTarget()` ＋ `atomicReplace()`，零 spawn） | commit 訊息：**1.9s**／780 條／2930 次操作。T12 現場（正常路徑，非 mutation）：gate 內部計時 2.315s | T06 |
| **CX37b** | `CodexCoexistenceSequenceTests` | 同 CX37a | `bothSidesNeverDisturbEachOthersFilesOnProductionPath`（長度 ≤ 2 共 30 條，完整 `connect`，11 次真 spawn） | commit 訊息：**4.2–8.4s**（視全套件負載）／11 次 `installer.connect(`。T12 現場（正常路徑，非 mutation）：gate 內部計時 2.291s | T06 |
| **CX38** | `EndToEndWiredGateTests`（或拆出的 `EndToEndDualAgentTests`） | `--agent` 解析改成一律回 `.claude` | `oneBinaryServesBothAgentsInOneRoot`（兩個方向各跑一次） | commit 訊息：**1.6s**（8 個斷言，4 個 codex session × 正序／反序各一次） | T05 |
| **CX39** | `CodexWiringSmokeTests` | **把 R-9 的 guard 移到 `disconnect` 之後** | `codexReconnectNeverDisconnectsWhenPathIsRejected`（`disconnect` 次數 0、檔案仍在） | **0.180s**（T12 現場重跑，`fakeInstaller.disconnectCallCount` 從預期 0 變成 1） | T10 · **抽驗必做 ✓現場** |
| **CX40**（**T13c 改名＋期望值翻轉**） | `CodexStateTests` ＋ `CodexWiringSmokeTests` | ① **讓 `reprobeCodex` 無條件給 snippet**（拿掉條件） ② **T13：改回 `pathRejection == .mustMoveToApplications`（只扣一種）→ `.unsupportedCharacter` 整行必須紅**——**r12 的實作在這個 mutation 下是綠的**，實跑輸出要寫進報告 | **`codexSnippetIsWithheldForEveryPathRejection`**（原 `...WhenPathWillVanish`；**乘積表**，**兩種 rejection 整行 nil**，只有 `nil` 整行非 nil）。**與 CX36③④ 是同一條不變式的兩層**（決策層／view 層），**D-s／D-w 在兩者落地前零強制力**。改名理由：「會消失」不再是判準，留著舊名會讓下一個人照名字推回舊條件 | | T10 · **T13c 翻轉** |
| **CX41** | `JargonCodexModelTests` | ① Codex 分支回傳 raw（**既有 `everyFixtureModelIsMapped` 也必須紅**，兩條都記） ② 把 `o3` 改成 `O3` ③ **把 Codex 分支移到既有演算法之後 → `gpt-5` 那列必須紅** | `jargonModelCoversCodexNaming`（釘死的輸入→輸出表**九列**，含 `gpt-5`／`gpt-4.1-mini`／`gpt-5.5[high]`；既有九列輸出完全不變） | | T05 |
| **CX42** | `CodexCredentialSequenceTests` | `performDisconnect()` 順手 `defaults.removeObject(forKey: CodexHookStore.key)` | `bothSidesNeverDisturbEachOthersCredentials`（**20 條**長度 ≤ 2 序列，fake ＋ 注入 suite、零 spawn；另一側鍵位元組不變 ＋ 鍵集合**差集**斷言） | | T10 |
| **CX44** | `NoPendingFlagRemainsTests` | 在 **`Sources/` 與 `Tests/` 各留一個** `AURA_CODEX_PENDING_T08`（**兩處都要紅**） | `sourcesHasNoPendingFlag`／`testsHasNoPendingFlag`（**`Sources/` ＋ `Tests/`** 都不得殘留 pending 標記；**含暫存目錄正向對照** `scanCatchesRealPendingFlag`） | **Sources 0.032s／Tests 0.056s**（T12 新做，兩處各放一個探針檔，兩處都紅；還原後乾淨） | T12 · **✓現場** |
| **CX45** | `SessionState` 來源掃描 | 在 `Sources/` 加第二個 `SessionState(` 建構點且不傳 `agent:` | `sessionStateProductionConstructionSitesPassAgent`（`Sources/` 的 `SessionState(` 恰 1 處且含 `agent:`） | | T05d |
| **CX46** | `OptionsMenuModel` 呼叫點來源掃描 | 把 view 那一行改回 `codex: .unavailable, codexPathRejection: nil` | `optionsRowsCallSitePassesRealCodexState`（`Sources/` 不得出現那兩個字面）。**已知假陰性**：跨行寫法掃不到、註解過濾兩個缺口——主守衛是 T10 的**行為斷言**，本條是便宜的第二道 | | T08 |

| **CX47** | `CodexBannerLifecycleTests`（新） | ① **`.codexConnected` 改用 `!rows.isEmpty`（＝ r12 行為）→ 必須紅** ② `hasCodexRow` 改成 `agentLabel != nil` → **預期綠（等價 mutant，要記）** | `codexConnectedBannerOnlyRetiresOnCodexRow`（定義域 `PanelBanner.Kind.allCases` × 四種列組合，程式推導；本 gate 是 `Kind.allCases` 的第一個消費者） | | T13b |
| **CX48** | `CodexWiringSmokeTests+Banner`（新） | ① **`codexConnected` 改回 `kind: .connected` → 必須紅**（persona r1 抓到的那一行） ② 刪 `effectiveBanner` 的 `.codexConnected` 分支 ③ 讓 banner 永不退場 → **負向對照那格必須紅** | `codexTrustWarningIsDrawnWithClaudeRowsPresent`（`leafStrings` 掃整個 `PanelView.body`；**與 CX24④ 是同一件事的兩層**，doc comment 互相點名） | | T13b |
| **CX49** | `CodexSectionViewTests` | ① 改回會畫 snippet ② 拿掉出路句 ③ **把輸入的 `codexSnippet` 改成 nil → 全綠（等價 mutant，要記）** | `blockedCharacterCardWithholdsSnippetAndOffersAWayOut`（**輸入餵真的含空白路徑產出的 snippet**——負向斷言餵正向輸入） | | T13d |
| **CX50** | `PanelStatusLabelTests`（新） | ① 忽略 `codex` ② 無條件加子句 ③ **子句改到尾端** ④ 把 `.connectedStalePath` 也算成已接上 ⑤ **r14：`title` 的非 connected 分支改回 `install.healthLabel` → 第④條斷言必須紅** | `panelStatusLabelIsDualAgentAware`（定義域**逐字寫 `InstallStateAllCases.all()`**，不是「代表值」——test target 既有符號，由 `Reason.allCases × MountOwner.allCases` 推導；× `CodexStateKind.allCases` × 兩語言。**四條**斷言：**零 diff `==`**／含診斷子字串／Codex 子句在最前／**`title` 非 connected 分支 `==` `statusLabel`**（把住在 AuraCore 的標題那一處下推到純函式層守）） | | T13f |
| **CX51** | `CodexWiringSmokeTests+Banner` 或 `PanelPixelTests` 同族 | **逐處三個，都要跑、逐處記**：footer 改回 → 斷言①紅；標題改回 → ②（2→1）＋③紅**且 CX50④ 也紅**；CTA 窄條改回 → ②（2→1）＋③紅 | `dualAgentStatusLabelReachesAllThreeSites`（persona r1 的頭號情境）。**r14 改方法**：r13 寫的「三處都 `contains(statusLabel)`」**對它自己宣告的三個 mutation 全部不紅**——三處渲染同一個字串、`leafStrings` 回扁平陣列，任一處改回後另外兩處還在。改成三條**可分辨**斷言：① footer 比對複合字面 `"<statusLabel> · v<version>"`；② **裸 `statusLabel` 葉節點出現次數恰 2**；③ `install.healthLabel(l)` **不得**以裸葉節點單獨出現 | | T13f |
| **CX52** | 來源掃描（**兩個 root**） | ① 在任一 view 加回一行 `model.install.healthLabel(model.language)` → 第①格紅 ② **r14：把 `title` 的讀取點改回 `PanelModel.swift` → 第②格紅**（具名集合多一個檔） | **`healthLabelReadersAreTheNamedSet`**（r14 改名）：① `Sources/AgentAuraApp/` 的 **`.healthLabel(`（有前導點，抓讀取點）** 命中數**恰 0**；② `Sources/AuraCore/` 含有 **`healthLabel(`（無前導點，才涵蓋宣告處）** 的**檔案集合恰等於具名清單**（`InstallAffordance`／`TooltipText`／`PanelBanner+InstallerFailure`／`PanelModel+ConnectCTA`）。**r14 為什麼補第②格**：三處裡的標題住在 AuraCore，r13 只掃 App 層＝只守到 2/3，而風險表卻寫「站點集合 source-derived」（overclaim）。已知假陰性同 CX46：跨行寫法／block comment。**r15（review n2）：兩格 pattern 刻意不同**——實跑 AuraCore 無點 5 命中／4 檔、有點 4 命中／3 檔，差的正是宣告處 `InstallAffordance.swift`；寫成有點會在 T13f 落地當天就紅（3 檔 vs 清單 4 檔） | | T13f |
| **CX53** | `PanelStatusLabelTests` | ① 一律回舊句 → `.connected` 那格紅 ② 一律回新句 → 其餘五格紅 | `emptyRowsMessageIsAgentAware`（期望值**寫死字面**，不引用 `L10nPanel.emptyRowsMessage`——拿產生器跟自己比的老陷阱，本 change 已踩過兩次） | | T13g |
| **CX54** | `CodexSectionViewTests` | ① 拿掉合併指示 ② help 按鈕改送別的 action ③ 讓 `codexSnippet == nil` 那格也畫 → **負向對照必須紅** | `occupiedCardTellsYouToMergeAndOffersHelp`（重用既有 `.openHelp`，不開第四個 `PanelAction`；按鈕用點遍收集 action，不用索引） | | T13h |
| **CX55** | 文件掃描 | 從 `help-english.html`／`help-traditionalChinese.html` **任一份**刪掉那段（兩份各試一次） | `helpDocsExplainMergingIntoExistingHooks`（`@Test(arguments:)` 參數化兩份——CX29 的既有教訓：內容有、守衛沒有） | | T13h |
| **CX56**（**T13i 交付，2026-09-21，已落地；2026-09-22 鏈 A merge 後重量確認不受影響，見 DoD #36**） | `CodexSnippetHeightTests`（新，AgentAuraAppTests） | ① 拿掉 snippet 的固定高度 → 2 issues，3.9s ② **改成 `.frame(maxHeight:)` → `FooterPositionStabilityTests` 必須紅**（兩條一起看）→ 「外層畫布超過自然高度」的既有技巧量不到（`PanelView.body` 頂層 `.frame(maxHeight: .infinity, alignment: .top)` 把畫布餘裕整個吸收在最外層），改用「同一份 model 換不同 snippet 內容長度」→ 1 issue，1.7s（short=409pt long=552pt，差 143pt） ③ **把域縮回「只有 `install: .connected` ＋ `banner: nil`」→ 重現 r13 的假綠**：量出窄域結構性最壞 467pt（vs 全域 538pt，差 71pt），構造一個窄域會選到但全域不夠的上限值 276pt，套用後窄域 0 violations（假綠）、全域 1 violation（784pt，紅）——域不夠＝gate 沒有牙齒的直接證據 ④ 拿掉下限那格並把上限壓到 1 列 → 1 issue，1.8s ⑤ 把 `CodexSnippetSizing.lineHeight` 改 13→17（+4pt）→ `CodexSnippetSizingDerivationTests` 1 issue，2.0s **指名測試（2026-09-22 review 第四次「文件指名的 gate 不存在」修正）**：`snippetCardFitsOnA13InchScreen_1`（CX56①：五維乘積 224 格 `preferredContentSize.height ≤ 780pt`）／`_2`（CX56①補：`.occupiedByOther` `codexSnippet == nil` 矮子變體，review m1 順手補）／`_3`（CX56②：「複製」與 footer 按鈕的 `minY` 都在天花板內，**渲染後座標**、按鈕**用點擊辨識不用索引**）／`_4`（CX56③：snippet 區塊不得低於 6 個視覺列下限）——`swift test --filter snippetCardFitsOnA13InchScreen` 現在回 4 tests。**r14 定義域補兩維**：`CodexState` × 兩語言 × {rows 空,3 列} × **`install ∈ {.connected, affordance == .connect 的代表值}`** × **`banner ∈ {nil, .codexConnected}`**——最壞組合（整版 CTA ＋ 有 snippet ＋ 尚未退場的 banner）**從未被量過**，證據圖 `05`／`07` 兩張都是 `install: connected`。**另加下限**：snippet 區塊不得低於 6 個視覺列——**r15（n4）：下限的基準由本 gate 在 App 層渲 6 行等寬文字量出來，不得寫進 AuraCore**（那層量不了文字，只會變成寫死的行高常數），**r16（n6）：與 `CodexSnippetSizing` 上限用的行高是同一個量到的值**。**r16 另配一支 `CodexSnippetSizingDerivationTests`**（照既有 `SessionsCardSizingDerivationTests`：離屏渲染真實 view ±0.5pt）守那個行高常數——先例的第一版就是寫死一個量錯的常數被 review 退回（`SessionsCardSizing.swift:15`）。**r15（n3）：`install` 代表值由 T13i 實測四種 affordance 後釘死**，不是挑 `.connect`。**r15（N1）語意前置條件：要求 T13b 已落地**（`.codexConnected` 有自己的 kind 之前，`banner` 那一維在 rows 非空的格子裡是惰性的，量到的高度與 `banner: nil` 相同）。**780 在 T13i 量完之前是提案**，到不了要停下來回報三個選項，不得自行砍內容。Options 展開的組合**刻意排除**，見 spec §10-20 | | T13i |
| **CX57** | `AppDelegatePanelActionsWiredTests+Codex` | ① **改回直接呼叫 `performDisconnectCodex()` → 第一格必須紅** ② 確認框文案拿掉 agent 名 | `codexDisconnectGoesThroughConfirmation`（不確認 → `disconnectCallCount == 0` ＋ 憑證鍵不變；確認 → 1；文案含 `Agent.codex.label!`） | | T13j |

**額外必記的三筆（不是新 gate，是回歸證人）**
1. T01 的 `DirectoryTreeSnapshot` 抽取之後，**當場重跑既有 `installerTouchesOnlyAllowedPaths`
   的 mutation** 確認仍精準紅。
2. 三個純搬移（`AppDelegate+Links.swift`／`CodexOptionsRowTests.swift`／
   `AppDelegatePanelActionsWiredTests+Codex.swift`——**T12 核對：帳本原記的檔名
   `AppDelegateCodexWiredTests.swift` 不存在，實際檔名如上，commit `e6ef148`**）：
   搬完 `#expect` 總數不變，被搬動的測試函式名一字不改（T12 逐一 diff 核對過，見 DoD#8）。
3. **`JargonTests.modelTwoNonNumericSegmentsPassesThrough` 的輸入從 `gpt-4o` 換成非 Codex 家族的
   例子**（性質保住）＋**新增**一列釘死 `gpt-4o` 的新期望值——報告要把「改前／改後／測的還是不是
   同一件事」三欄擺在一起。直接刪掉那條測試＝弱化，要退回。

## T12b：CX1–CX57 gate 名 `--filter` 全量掃描（新增常設項目）

**方法**：`swift test list`（`--list-tests`）一次列出全部 972 行 `Module.Suite/functionName()` 規格
（`scratchpad/t12b/all-tests-list.txt`），再對帳本每一列「指名測試」欄抽出的候選函式名逐一
`grep`（子字串比對，比照 swift-testing `--filter` 的實際語意——**不能要求緊接 `(`**，
`CX56` 那種 `_1`／`_2` 尾綴會被緊鄰匹配誤判成 0，這是本輪第一次繞的坑，已改用純子字串比對）。
**這比真的執行 `swift test --filter` 快兩個數量級**（972 行的靜態清單 vs 逐一起爐建置檢查），
建議作為 CX58（下方）的實作基礎。

**執行摘要**：66 個候選名稱裡，**14 個帳本指名的函式在原始碼裡確實不存在**（逐一以 `grep -rn`
核對原始碼確認，不是掃描方法的偽陰性）；**2 個是概念性描述而非字面函式名**（CX21、CX28，
沿用既有「敘述句嵌函式名」的寫法）；**1 個是腳本層 gate**（CX27，`verify-uninstall.sh` 本身
的 bash 邏輯，不是 swift test，掃描方法在這裡不適用，不算真的缺口）。

| Gate | 帳本指名的函式 | 是否存在 | 真正的函式（已核對原始碼） | 檔案 |
|---|---|---|---|---|
| CX6 | `codexHooksJSONMatchesF14Verbatim` | ✗ | `everyEntryMatchesF14Verbatim` | `CodexHooksJSONTests.swift` |
| CX17 | `codexDisconnectOnlyRemovesOurBytes` | ✗ | `disconnectRemovesOnExactMatch`（＋`disconnectRefusesOnContentMismatch`／`unlinkGuardRefusesWhenIdentityDoesNotMatchCurrentFile`／`unlinkGuardRemovesWhenIdentityMatchesCurrentFile` 共同覆蓋這個不變式） | `CodexInstallerTests.swift` |
| CX19 | `codexStateCoversEveryObservationShape` | ✗ | 七列分別是 `notDirectoryAlwaysUnavailable`／`regularFileMatchingBothIsConnected`／`regularFileMatchingRecordedButNotCurrentIsStale`／`regularFileMismatchIsOccupied`／`nonRegularOccupyingTypesAreOccupied`／`absentWithRejectionIsBlocked`／`absentWithoutRejectionIsNotConnected`，另 `samplesKindsCoverAllSixStates` 守六態聯集 | `CodexStateTests.swift` |
| CX20 | `codexRowsAppearOnlyWhenAvailable` | ✗ | `zeroRowStates`（＋其他列數格） | `CodexOptionsRowTests.swift` |
| CX21 | `optionsRowsCoverEveryAction` | △ | 這是**檔案 doc comment／`@Suite` 顯示名**用的概念性標籤，不是字面函式名——同 CX28 的 `allRows` 那種寫法 | `OptionsMenuModelTests.swift` |
| CX22 | `agentLabelOnlyForNonClaude` | ✗ | `agentLabelSurvivesThroughPanelModelMake` | `CodexRowLabelTests.swift`（帳本寫的「`CodexRowLabelPixelTests`」這個檔名也不存在） |
| CX27 | `verifyUninstallScriptDetectsOurCodexHooks` | N/A | 這是 **bash 腳本**（`verify-uninstall.sh`）本身的邏輯，不是 swift test——「掃描不到」是分類不適用，不是缺口 | `scripts/verify-uninstall.sh` |
| CX28 | `allRows` | ✗ | `allRows` 是**靜態 helper**（`static func allRows(language:) -> [OptionsRow]`），真正的 gate 測試是 `scanCatchesRealCodexOmission`（mutation②正向對照）。**帳本的「位置」欄也錯**：寫著含蓄的位置，實際檔案在 `Tests/AuraCoreTests/HelpDocOptionsRowCoverageTests.swift` | `HelpDocOptionsRowCoverageTests.swift` |
| CX29 | `securityDocListsEveryPathWeWrite` | ✗ | `docListsCodexHooksPath`（`@Test(arguments:)` 參數化三份文件） | `SecurityDocCodexPathTests.swift`（帳本「位置」欄只寫「文件掃描」，沒給檔名） |
| CX32a | `codexConnectRefusesBlockedBundlePath` | ✗（**T12 首輪已記過**） | `codexConnectRefusesTranslocated`／`codexConnectRefusesInDownloads`（帳本這個名字是 MARK 註解分組名） | `CodexInstallerClobberTests.swift` |
| CX33 | `codexPathCheckNamesTheOffendingCharacter` | ✗ | `returnsFirstOffendingCharacterLeftToRight` | `CodexHookPathCheckTests.swift` |
| CX34 | `codexStalePathIsDetectedAndOffersReconnect` | ✗ | `regularFileMatchingRecordedButNotCurrentIsStale`（@Test 描述裡明寫「(CX34)」，確認是同一顆） | `CodexStateTests.swift` |
| CX36 | `codexSectionRendersEveryState` | ✗ | 拆成約 7–9 個函式：`emptyStatesRenderNothing`／`notConnectedShowsPromptAndConnectButton`／`staleWithoutRejectionShowsReconnectButton`／`staleWithRejectionWithholdsReconnectButton`／`staleWithRejectionRendersDifferentTextPerRejectionKind`（CX36⑥）／`occupiedWithSnippetShowsSnippetAndCopyButton` 等 | `CodexSectionViewTests.swift` |
| CX41 | `jargonModelCoversCodexNaming`（檔案「`JargonCodexModelTests`」） | ✗✗ | **檔案本身不存在**；九列分別是 `modelCodexGpt55`／`modelCodexGpt55Codex`／`modelCodexGpt4o`／`modelCodexGpt5`／`modelCodexGpt41Mini`／`modelCodexGpt55High`／`modelCodexO3`／`modelCodexO4Mini`／`modelCodexO3WithBracketSuffix` | `JargonTests.swift`（不是獨立檔） |
| CX46 | `optionsRowsCallSitePassesRealCodexState` | ✗ | `productionCallSitePassesModelCodexState` | `OptionsMenuModelRowsCallSiteSourceScanTests.swift` |

**CX50／CX51／CX52／CX56／CX57 一開始也顯示 0**，但那是掃描方法的偽陰性（緊鄰 `(` 的比對規則
被 `_1`／`_2` 這類參數化尾綴或多個 `@Test` 案例打敗），改用純子字串比對後**全部確認存在**
（CX50 4 命中、CX51 2 命中、CX52 2 命中、CX56 4 命中、CX57 3 命中）——這些**不算**文件/程式碼
名稱不符，只是我第一版掃描腳本的己方 bug，記在這裡是為了讓下一個做同類掃描的人不要重踩。

**這是「文件指名的 gate 不存在」這個模式的第五、六次出現**（前四次：r1 M4、鏈 A phase-2 review M1、
鏈 A phase-2 review N1、CX56 review 第四次修正）——team-lead 派工訊息裡提到的「四次」在這一輪
變成至少 **14 處新命中**，證實這不是偶發，是系統性問題：implementer 常在落地時把單一顆大 gate
拆成多顆小函式（分頁多、對抗式覆蓋更細），但沒有回頭同步 DoD 帳本裡「指名測試」欄的字面。

### 建議新增 CX58（`everyNamedGateResolvesToAtLeastOneTest`）

**未實作為真的 swift test**（時間預算緣故），只留下方法與資料供下一輪落地：
- **輸入**：從 `docs/superpowers/plans/2026-09-18-codex-support-dod.md` 的「Gate mutation 帳」表
  用 markdown 解析抽出每列「指名測試」欄的第一個 backtick 識別碼（本輪用 python 手刻，若要變成
  真測試，這段解析邏輯要挪進 `Sources/` 之外的一個測試專用 helper，或整份帳本改成機器可讀格式
  如一份 JSON 附錄，供測試直接讀，不必每次重新解析 markdown 散文——**這是落地前要先決定的設計
  取捨，不是實作細節**）。
- **比對**：`swift test list` 的輸出（或編譯期用 `XCTestCase`／swift-testing 的反射 API 列舉，
  若能找到不需要跑子行程的方式更好）逐一子字串比對。
- **已知假陽性**：CX21／CX28 這種「概念性標籤」寫法會被誤判成缺失——如果要落地，帳本本身要先
  統一「指名測試」欄只准寫字面函式名，概念性描述移到 mutation 欄或另一欄，否則這條新 gate
  自己会一直帶著兩個「已知例外」跑，形狀就跟它想避免的「文件與程式碼對不上」很像。
- **已知範圍限制**：CX27 這種 script-level gate 天生不在 swift test 的宇宙裡，需要一個獨立的
  「script gate 名冊」不同的驗證方式（例如直接 grep `scripts/*.sh` 裡的函式/區塊名）。

## 里程碑量測（T12 之前的實測紀錄，逐 task 累積）

DoD #2 要求**每個 task 的報告附該 commit 的絕對值**，這裡是彙總；T12 直接引用，不必回頭翻報告。

| 里程碑 | commit | `grep -rho '#expect(' Tests \| wc -l` | 全量 `swift test` |
|---|---|---|---|
| 基準 | `be136d6` | **1649** | — |
| T04 交付 | `6da2ea6` | **1758** | — |
| **T05 交付（T01–T05 已 merge）** | `ad174e7` | **1792** | **828 tests / 1 issue** |
| **T07 交付** | `fc4f218` | **1880** | **875 tests / 4 issues**（1 條 T10 pending ＋ **3 條因 T07 的 stub 而誠實紅**） |
| **T08b／T11 交付** | `08140a6` | **1911** | **893 tests / 4 issues**（同上組成：1 條 T10 pending ＋ 3 條 stub 誠實紅） |
| **T09 交付** | `d3e954e` | **1959** | **915 tests / 4 issues**（同上組成） |
| T10 交付（r1） | `52ca62e` | 1997 | 927 / 0 |
| T10 review 修復（r2 APPROVED） | `5ad5256` | 2018 | 933 / 0 |
| merge main（PR #7） | `f6cd5f1` | **2018**（`git diff 5ad5256..f6cd5f1 --stat -- Tests` 也是空——merge 對 `Tests/` 淨增同樣是 0，跟 `Sources/` 同一個故事：codex-support 分支自己早已收斂） | 未單獨量（HEAD 已含後續 commit） |
| T12 CX44 交付 | `ecd323e` | **2025**（+7，恰好等於 `NoPendingFlagRemainsTests.swift` 自己的 7 個 `#expect(`） | **646＋291＝937 tests / 0 issues**（HEAD，3 輪皆同） |
| **T13 交付（persona r1 修復批次，兩條鏈已 merge）** | `c3db1da` | **2083**（基準 2026，**+57**；`@Test` **977**，T12 是 941 → +36） | **969 tests／0 issues**（657+312，鏈 B rebase 後實測，known gap 36）。**連跑 3 次 0 flake 留 integrator 重跑**（T13k／T13l 期間主目錄與 worktree 同時在動，避免搶 `.build`） |
| **T13k 文件與正典回寫** | 本 commit | 2083（文件 commit，不動 `Tests/`） | 未跑（只動 `docs/`、`CLAUDE.md`；`Sources/` 現場實測 **9713** 行、單檔上限 0 超標、`AURA_CODEX_PENDING` 0 命中、`plugin/hooks/hooks.json` 與 `Package.swift` 對基準 diff 為空） |
| **T12b 整合重跑（本輪，tip `c22fb12`）** | `c22fb12` | **2083**（不變，T13l 只動 `docs/evidence/`） | **連跑 3 次，657+312=969 tests／0 issue／0 flake**（`swift-test-run1/2/3.log`）——**補上 T13k 留給 integrator 的那一項**（「連跑 3 次 0 flake 留 integrator 重跑」，本輪已完成） |

**merge main（`f6cd5f1`）對 `Sources/` 淨增實測是 0，不是預期的 +30**：`git diff 5ad5256..f6cd5f1 --stat -- Sources` 輸出為空——`change/codex-support` 分支在 merge **之前**（`cc26b72`，2026-09-19）就已經獨立收斂出跟 main PR #7 完全相同的色板抑制改動（`ColorPickerCoordinator.swift`／`IconRendering.swift`／`StatusItemController+SystemPanels.swift` 三個檔逐位元組相同）；只有 `AppDelegate.swift` 有 38 行差異，屬於本 change 自己的 Codex 接線，跟 merge 無關。**這推翻了 T10 review r2 派工訊息裡「merge main 會讓 Sources/ +30」的預期**——實測 0，`Sources/` 的所有增量都來自 codex-support 自己的 commit，見 DoD#7。

**T07 交付時的 4 個紅**：`codexConnectChainIsWired`（pending T10）＋ 三條因 T07 的 stub 而誠實紅的
既有 gate（`panelActionsAreWired` 對三個新 kind）——**後三條不算基準紅**，它們是 tested≠wired 守衛
在等 T10 接線，**不准為了讓它綠而弱化**（plan §0「套件必須維持可編譯」）。

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
| 17 | **CX40 App 半／純函式半的重量已分工釐清**（T10 review r2 定稿）：App 半 `CodexStateKind.allCases`（6）× `PathScenario.allCases`（3）＋「任何 rejection 都扣住」→ 14 issues／0.222s；純函式半 10 case → 8 issues／0.004s。**r1 記過的「App 半重量」known gap 已取消**——m8 之後 `hookBinaryPath` 有注入縫，不再是缺口 | 已關閉（r1 記過，r2 取消） | T10 review |
| 18 | **CX42 spawn 數的正確措辭**：不是零 spawn——Codex 側零，Claude 側 `performConnect` 從未連上時零、連上時經 `Installer.verifyByExecuting` 真 spawn，20 條序列最多 8 次，全條 2.586s，走 `SpawnGate` | 措辭修正，非新缺口 | T10 review |
| 19 | **`Sources/AgentAuraApp/AppDelegate.swift:79` 的 `installer: Installer = .production()` 預設值，是本 change 安全事故（2026-09-14 BTM 事故同型、風險更高）的先例**——`AppDelegate` 若被以預設值直接建構（忘記顯式傳測試替身），會在測試或工具程式碼裡真的碰 `~/.claude`。**建議獨立立一個 change 拿掉這個預設值**（同本 change 對 `codexDependencies` 的處置：review M3 已把 `codexDependencies` 拿掉預設值，`installer` 卻還留著），本 change 範圍未動它 | 建議後續 change | T10 review 定稿 |
| 20 | **connect 成功但 probe 不同意時，banner 與卡片短暫矛盾**：`performConnectCodex()` 回報成功寫入的瞬間到下一次 `reprobeCodex()` 之間，banner 可能講「已接上」而卡片仍顯示舊狀態。裁決：狀態以 `probe()` 為真相、banner 只講動作結果，這個窗口在生產環境不可達（寫入用 `O_CREAT\|O_EXCL`，構造出的 fake 才會不同意）。已有守衛：`CodexWiringSmokeTests+Adversarial.connectSuccessButProbeDisagreesTrustsProbe` | 已有守衛，記錄裁決理由 | T10 review 定稿 |
| 21 | **`build-app.sh`／`build-plugin.sh` 在 Xcode 27／Swift 6.4 的 `swiftbuild` 系統下，`lipo` 撈到的是舊版 native build system 遺留的 stale 二進位**（`.build/<arch>-apple-macosx/release/`，2026-09-17 切換前的殘留），不是目前程式碼真的建置結果——`swiftbuild` 把每個 `--arch` 呼叫都寫到同一個共用路徑 `.build/out/Products/Release/`（互相覆寫），`build-app.sh` 卻還在讀舊路徑。**T12 用手動 lipo 繞過取得真數字**（DoD#11），但這個 bug 本身會讓任何人在這台機器上跑 `./scripts/build-app.sh` 都拿到「看起來建置成功、實際是舊碼拼出來」的 bundle，且**完全靜默**（沒有任何警告會被使用者看到——`lipo` 的 warning 只在直接跑指令時才印，`build-app.sh` 沒有檢查 lipo 是否真的用了新鮮輸入）。建議獨立 change 修 `build-app.sh`／`build-plugin.sh` 的路徑（改讀 `.build/out/Products/Release/` 或用 `swift build --show-bin-path` 動態解析），並加一條 gate 斷言 bundle 內執行檔的 mtime 新於最後一次原始碼變更 | **建議獨立 change 修，影響所有依賴 `build-app.sh` 的驗收腳本與量測** | T12 新發現 |
| 22 | **`scripts/measure-cpu.sh`／`scripts/verify-app.sh` 的收尾 `pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp"` 會連帶殺掉使用者機器上正在跑的正式安裝**（不分辨是 `build/` 的測試副本還是 `/Applications/` 的正式安裝）。T12 實測跑 `verify-app.sh` 時已證實發生（PID 2194 的正式安裝被殺，已手動 `open /Applications/AgentAura.app` 復原）；`measure-cpu.sh` 風險更高（5 態 × 66s ≈ 5.5 分鐘期間使用者選單列會是測試 build，且腳本本身不會自動重開正式安裝），因此本輪 DoD#14／#15 未執行。建議兩支腳本改成只 `kill` 自己剛 `open` 出來的那個 PID，不要用路徑字面比對 | **建議修，影響安全量測的可行性** | T12 新發現 |
| 23 | **spec §8.1 檔案佈局估算表完全沒列到六個新檔**：`CodexFailure.swift`（38 行）、`CodexObservation.swift`（32 行）、`CodexState+From.swift`（42 行）、`L10nCodex+Failures.swift`（75 行）、`OptionsMenuModel+Codex.swift`（38 行）、`OptionsSectionView.swift`（淨 +16 行），合計 241 行——這是 DoD#7 超標（377–407 行）裡佔比最大的單一成因，不是既有檔案膨脹，是拆檔產生的新檔完全沒被估算 | 記錄成因，供下次估算校正 | T12 新發現（DoD#7） |
| 24 | **DoD 帳本三處檔名／測試名與實際不符**：CX32 的指名測試帳本原記 `codexConnectRefusesBlockedBundlePath`（那是 MARK 註解分組名，實際函式是 `codexConnectRefusesTranslocated`／`codexConnectRefusesInDownloads`）；「額外必記」第 2 筆帳本原記 `AppDelegateCodexWiredTests.swift`（實際檔名 `AppDelegatePanelActionsWiredTests+Codex.swift`，commit `e6ef148`）。T12 已在對應行更正，供之後找檔案／測試時直接用實際名稱 | 帳本文字校正 | T12 新發現 |
| **25** | **spec §10 追加六條（17–22）**：`.unsupportedCharacter` 不再給 snippet 之後「完全沒有手動出路」（**有解鎖條件**：互動探針量到引號可行就開後續 change）· legend「Error」沒有面板內路徑（**明寫接受**）· 列標籤樣式（**明寫接受**）· **Options 展開＋snippet 的總高度不在 CX56 之內——T13i 已填數字：1056pt（rows 空，修後）／1047pt（rows=3，對照；修前分別 1849pt／1840pt）**· Claude 側 CTA 仍是泛稱「Connect」（**明寫接受**）· footer chip 可能截掉版本號（數字待 T13f 填） | 見 spec §10-17–22（20 已填） | T13／**20 由 T13i 填**（2026-09-21） |
| **26** | **DoD #7（`Sources/` 淨增）在 T13 之後會更糟**：T12 實測 +1527（門檻 1150，MISS 377），T13 估計再加約 **270**，合計約 **+1797**（MISS 約 647）。**門檻不往上調**（本專案已有兩次「如實記錄不調門檻」前例）。這 270 行買的是**兩條 S0 的關閉**，替代方案是「維持 NO-GO」，不是「省 270 行」。**是否重設基準是使用者的裁決** | 需使用者裁決 | T13 |
| **27** | **`TooltipText` 也讀 `install.healthLabel`，但刻意不在 CX52 的掃描範圍內**（CX52 只掃 `Sources/AgentAuraApp/`）。tooltip 是選單列的 hover 文字，不是面板的三處狀態字串——**這個邊界是刻意的，不是漏掉**。若日後判定 tooltip 也該雙 agent 感知，那是另一個 change | 邊界，明寫 | T13f |
| **28** | **兩個等價 mutant 是預期結果**：CX47② (`hasCodexRow` 改成 `agentLabel != nil`) 與 CX49③（把輸入的 `codexSnippet` 改成 nil）。前者守的是**未來的第三種 agent**、後者守的是**負向斷言的輸入品質**，兩者今天都打不紅。**要記進 mutation 帳並寫明理由**，不要為了「讓它紅」把 gate 改成另一件事 | 方法論，明寫 | T13 |
| **29** | **r13 review（2026-09-21，0 BLOCKING／3 MAJOR／5 minor）的處置**：M1 CX56 定義域補 `install`×`banner` ＋ snippet 下限 ＋「780 先量後定」· M2 CX51 改成三條可分辨斷言（r13 的寫法對自己宣告的三個 mutation 全部不紅）· M3 並行圖更正（`PanelModel*.swift` 上 T13b→T13f→T13g 序列）· m1 CX52 改名並補 AuraCore 具名檔案集合 · m2 `#expect(` 基準 2025→**2026** · m3 寬度量測擴到標題與 CTA 窄條 · m4 CX50 定義域逐字寫 `InstallStateAllCases.all()` · m5 T13l 補最壞高度組合 #14 · (c) §8.1 補「為何不放 `L10nPanel.swift`」。**九條決策無一被推翻** | 已折入 r14 | r13 review |
| **30** | **780pt 在 T13i 量完之前是「提案」**：最壞組合（`install` 非 connected ＋ `.occupiedByOther` 有 snippet ＋ `.codexConnected` banner 尚未退場）**從未被量過**。若在 snippet 下限（6 個視覺列）之下仍到不了 780，**要停下來回報三個選項**（調數字／整張卡片可捲／該組合下不同時顯示 banner 與 snippet 卡——第三個會動到 D-v，屬決策變更）。**不得自行砍別處內容讓它變綠**。**r2 review N2 追加**：這個最壞組合現在還要疊加 T13f 的 +16pt 標題換行（`install` 非 connected 時 34/58 格會換行，見 #33／spec §10-22／§4.10／CX56 gate 列）——T13i 量測時 `install` 代表值若剛好落在那 34/58 格裡，量到的高度本身就已經含換行，不必再另外加；但若代表值挑在未換行的 24/58 格，要記得補上這 +16pt 再跟 780 比 | 待 T13i 實測定案 | r13 review M1／r2 review N2 追加 |
| **31** | **r14 review（2026-09-21 第二輪，0 BLOCKING／1 MAJOR／3 minor）的處置**：r13 的 3 MAJOR＋5 minor＋(c) **全部 closed、零 regression**。N1 `T13i` 對 `T13b` 的**語意依賴**（`banner` 維在 `.codexConnected` 有自己的 kind 之前是惰性的）→ 鏈圖補跨鏈邊 ＋ CX56／T13i 各補前置條件 · n2 CX52 兩格 pattern 刻意不同（App 有前導點／AuraCore 無前導點才涵蓋宣告處），plan 實測行更正為無點 5 命中／4 檔 · n3 `install` 代表值改成 T13i 實測四種 affordance 取最高 · n4 snippet 下限由 CX56 在 App 層渲 6 行量，不進 AuraCore。**衝突檔表的已知盲區＝語意依賴**（它只比對檔案），排程時要另外問「這個子項量到／斷言到的東西有沒有依賴另一條鏈先改過的行為」 | 已折入 r15 | r14 review |
| **32** | **r15 review（2026-09-21 第三輪）APPROVED，0 BLOCKING／0 MAJOR／2 minor**：n5 型別名更正（`ConnectAffordance`，`InstallAffordance` 是**檔名**）· n6 `CodexSnippetSizing` 的行高常數補推導 gate `CodexSnippetSizingDerivationTests`（照 `SessionsCardSizingDerivationTests`，±0.5pt），上限與下限共用同一個量到的行高。**n5 是本 change 第三次「文件指名符號未實跑確認」**（r1 M4／r2 n2／r3 n5），處置寫進 plan T13 共同規則第 4 條與「開工前必讀」第 5 點 | 已折入 r16 | r15 review |
| **33** | **T13i 修前基準表（2026-09-21，`aab625e`）**：五維乘積（`CodexStateKind.allCases.flatMap(CodexState.samples)` 14 個代表值 × `Language.allCases` 2 × `rows ∈ {空,3列}` 2 × `install ∈ {.connected, .replaceExternal 代表值}` 2 × `banner ∈ {nil,.codexConnected}` 2 ＝ 224 格）。① STEP1：14 個 `CodexState` 代表值裡 `.occupiedByOther`（含真 snippet）最高（1317pt，install=connected／banner=nil／rows=0／en），次高僅 286pt。② STEP2：四種 `ConnectAffordance` 代表值（`.connect`→`.notConnected`、`.replaceExternal`→`.broken(.targetMissing,owner:.external)`、`.explainOnly`→`.claudeNotFound`、`.none`→`.connected`）在 rows=3 下分別 1444／**1450**／1402／1402pt——`.replaceExternal` 最高，釘成 `install` 非 connected 代表值。③ STEP3：全域最大值 **1473pt**（install=replaceExternal／banner=codexConnected／**rows 空**／en——不是原先猜測的 rows=3；NotConnectedView 整版 CTA＋未退場 banner＋有 snippet 卡片三塊疊加）。④ STEP8：`.occupiedByOther` 的 `codexSnippet` 清空後，全域結構性最壞組合 **538pt**（同一格）。⑤ STEP4：`optionsExpanded=true` 版本（修前）1849pt（rows 空）／1840pt（rows=3，對照）——記入 known gap 25／spec §10-20，修後已更新為 1056／1047pt（見 known gap 25）。⑥ STEP6：孤立渲染量出行高 **13pt／行**、padding 截距 **16pt**（1/6/12 行分別 29/94/172pt，`(94-29)/5 = (172-94)/6 = 13.0`）。⑦ 780pt 天花板扣掉結構高度（538-29=509pt）＝ 271pt 預算；選 12 行＝172pt，留 99pt 餘裕（給鏈 A T13f 標題換行等還沒落地的增量）；6 行下限 94pt，遠低於預算。**780pt 天花板可達，不調整**。⑧ mutation③ 額外量測：r13 窄域（install=.connected,banner=nil）結構性最壞僅 467pt（vs 全域 538pt，差 71pt）——證明窄域測試會低估真正的最壞情況 | 已落地，數字見 CX56 列與 `Sources/AuraCore/CodexSnippetSizing.swift` doc comment | T13i |
| **34** | **鏈 A phase-2 review r1（2026-09-21，0 BLOCKING／5 MAJOR／8 minor）的處置**：M1 六個 gate 函式名對齊 spec §6.3／DoD 帳本指名（`--filter <gate名>` 原本 `No matching test cases were run` 且 exit 0，照文件驗收會靜默假綠）· M3 CX51②③ 的 `labelCount == 4` 改成 `model.version` 命中數推導的「底噪 + 2」（不得寫死數字，多一個持有整份 `model` 的子 view 這個數字就會漂移）· M5 CX48「至少出現一次」在底噪已是 2 時不可能失敗，改成同一套底噪推導「底噪 + 1」· M4 `confirmDisconnectCodex` 拿掉預設值（同 `codexDependencies` review M3 的既有處置，第三次同型），`main.swift` 明傳、編譯器帶路更新 19 個檔 47 個 `AppDelegate(...)` 建構點 · M2 見下一條。minor m1（`healthLabel(` 字面本身會被單行掃描誤命中，doc 補記假陽性方向）／m6（CX47 主測試自我指涉、`hasCodexRowFalseForClaudeOnlyRows` 才是承重牆，doc 補記）／m8（`NotConnectedViewNoDuplicateHealthLabelSourceScanTests` 是 CX52①真子集，doc 互相點名）已隨對應 commit 修正；m2／m3／m4（commit 訊息文字錯誤：CX52 誤稱①格／CTA 窄條其實有 `lineLimit(1)`／`Text(verbatim:)` 像素不變引錯證人）已在完成報告更正，不追溯修改舊 commit；m7（行數餘裕記帳，2026-09-22 現況）：`PanelModel.swift` 194/200、`PanelView.swift` 190/200、`AppDelegate.swift` 133/200（M4 之後）、`AppDelegatePanelActionsWiredTests.swift` 298/300——四個檔都在上限附近，下一次動它們要先拆檔 | 已折入本輪 commit（1f5bffb／b2a048c） | r1 review |
| **35** | **r1 review M2（全域寬度量測）**：T13f 原始報告只量了 plan 指名的單一代表值（footer 313pt／可用 277pt、標題 326pt／可用 352pt 不換行、CTA 273pt），結論套用到整個定義域是 overclaim。**全域實測**（`codex == .connected` × 每個非 connected `InstallState`(29) × 兩語言 = 58 格，標題 13pt semibold vs 可用 352pt）：**34/58 超寬**，最寬 **510pt**（`"Codex connected · Claude Code: Can't connect: couldn't confirm the hook works"`）；`codex == .unavailable` 基準 **0/58 超寬**、最寬 300pt。換行對面板高度的實測影響（該最壞 install，真渲染 `PanelView`）：**250.0pt → 266.0pt（+16.0pt）**。**未改設計**（未加 `lineLimit`，加 `lineLimit` 屬設計變更需回 spec 決策）。數字已寫入 spec §10-22。**merge 後 T13i 的高度基準表與 780pt 天花板都要把這 +16pt 算進最壞組合重新對一次**（跨鏈語意依賴，同 T13b→T13i 那個形狀） | 數字已填，設計未變；待 T13i merge 後重量 | r1 review M2 |
| **36** | **T13i 重量（2026-09-22，鏈 A merge `9a16692` 之後，`change/codex-support-t13B` rebase 完成）**：rebase 後全量 `swift test` 657+312=969 tests／0 issues。重跑五維基準表（`CodexSnippetHeightRemeasurement.swift`，暫時檔，量完即刪）：**全域最大值仍是 680pt**（`codex=occupiedByOther，lang=english，rows=0，install=replaceExternal，banner=codexConnected`）——**與 T13f merge 前的數字逐位元組相同**（rebase 前用同一組合測過，也是 680.0pt），780pt 天花板 **0 violations**（224 格全數 ≤780）。**T13f 的 +16pt 換行代價對這個最壞組合不適用**：`statusLabel(install:codex:language:)` 的規則是 `guard codex == .connected else { return install.healthLabel(language) }`（`PanelModel+ConnectCTA.swift:31`，已讀原始碼**且**實測驗證：`REMEASURE-A` 逐一比對 install×language，`statusLabel` 與 `install.healthLabel` 逐位元組相等），而 CX56 的最壞態固定是 `codex=occupiedByOther`（恆非 `.connected`），標題／footer／CTA 三處都走 else 分支，跟 T13f 完全無關。實測交叉驗證：`codex=.connected` 那一整行（換行唯一可能觸發點，`CodexSectionView` 對它回 `EmptyView()`，D-j）在全域五維乘積裡最高只有 **328pt**，遠低於 680pt 的真正最壞組合。**780pt 天花板與 12 行（172pt）上限維持不變，不需調整**。量測檔已刪，`git status` 乾淨 | 已確認不受影響，不需調整 | T13i 重量（rebase 後） |

## T12 附錄一：位置索引斷言清查表

CLAUDE.md「這個 codebase 的 gate 哲學」第 5 條記過 T07 實測的平台限制：離屏渲染讀不到
SwiftUI 橋接出來的 `NSButton` 的 `.title`／`.accessibilityIdentifier`，新增按鈕時要檢查
既有的位置索引斷言有沒有被打亂。逐一檢查本 change 動到的離屏渲染測試檔：

| 檔案 | 測試 | 靠不靠位置索引 | 結論 |
|---|---|---|---|
| `FooterPositionStabilityTests.swift` | `footerButtonTop` 系列 | **不靠**——doc comment 明寫「量測手法必須用點擊辨識按鈕身份，不能用位置索引」，這是 T22 已經修過的既有教訓（collapsed 5 顆／expanded 15 顆，footer 在陣列裡的位置會變） | 安全，本 change 加 Codex 卡片不影響（找的是「觸發 `.toggleOptions` 的那一顆」，不論排第幾個） |
| `PanelPixelTests.swift` | `panelViewForwardsAction` | **不靠**——doc comment 明寫「E16／simplify 波次2：不數總數、不用位置索引」，改成點遍每顆真按鈕收集 `PanelAction` 集合跟型別推導的期望集合比對兩個方向 | 安全，新按鈕只要補進期望集合即可，不會因排列改變而誤報 |
| `NotConnectedRenderTests.swift` | `notConnectedViewAddsExactlyItsOwnButtons` | **用「數量差」**（`notConnectedButtonCount == connectedButtonCount + 2`），不是「陣列索引 N 一定是某顆按鈕」——兩個 model 的 `codex` 欄位都固定為 `.unavailable`／`nil`／`nil`，Codex 不會在這兩個 model 裡畫出任何按鈕，所以數量差不受 Codex 影響 | 安全，但屬於「總數比較」這個較弱的形狀（本 change 沒有觸發它的風險，先記下） |
| `BannerLifecycleRenderTests.swift` | `dismissButtonHitAreaIsAtLeast20pt` | **用 `.first`**（陣列裡唯一一顆按鈕）——`BannerView.swift`（`git grep -n "codex" Sources/AgentAuraApp/BannerView.swift` 零命中）本 change 完全沒有動過，`.first` 前提（該 view 只有一顆按鈕）沒被打破 | 安全，`BannerView` 不受 Codex 影響 |
| `CodexSectionViewTests.swift`／`CodexRowLabelRenderTests.swift`（Codex 自己的新測試） | 各自的斷言 | **不靠按鈕陣列索引**——`CodexOptionsRowTests.swift` 用 `.first { $0.action.kind == ... }`（依 action kind 找，不是位置）；`CodexRowLabelRenderTests.swift` 的 `.first!` 是對單一 session 建構出的單元素陣列（沒有「其他按鈕」可以混進來排擠它） | 安全 |

**結論**：本 change 新增的 Codex 卡片／按鈕沒有打破任何既有的位置索引假設——兩條最脆弱的既有測試
（`FooterPositionStabilityTests`／`PanelPixelTests`）都已經在更早的教訓裡改成不靠索引；新加的
Codex 測試也全部走「依身份找」而非「依位置找」的形狀。沒有發現需要修的既有斷言。

## T12 附錄二：measure-cpu.sh／verify-app.sh 收尾 pkill 的真實影響

跑 `./scripts/verify-app.sh` 時，其收尾的 `pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp"`
（第 97 行）把使用者當時在跑的正式安裝（`/Applications/AgentAura.app`，PID 2194）一併殺掉——
這支腳本自己只開了 `build/AgentAura.app` 那個副本，但 `pkill -f` 用路徑字串比對，兩個 bundle
的執行檔路徑都含 `AgentAura.app/Contents/MacOS/AgentAuraApp` 這個子字串，於是一併中彈。
已立即 `open /Applications/AgentAura.app` 復原（新 PID 47885）。這證實了 `measure-cpu.sh`
（同一種 pkill、且沒有結尾自動重開機制、且要跑 5 態 × 66 秒 ≈ 5.5 分鐘）在還沒先跟使用者
確認之前不該自動執行——DoD#14／#15 因此標記「未量到」，已記進 Known gaps #22。

## Known gaps 收口——進 release notes 的清單（T12b，去重＋分類）

spec §10 目前到第 23 條、本帳本 Known gaps 到 #36。以下是**去重後**的收斂清單，供直接貼進
release notes；性質標籤：**平台限制**（我們控制不了）／**設計代價**（權衡後的刻意選擇）／
**驗收缺口**（想驗但工具/環境不給）／**待使用者裁決**（需要人決定要不要接受）。

### 需要使用者裁決的四件事（列在最前）

1. **DoD#7 `Sources/` 淨增超標**——T13 之後（`c22fb12`）現場實測 **9713 行**，對分支點 `c131c30`
   +1867、對現 main `9ec85d0` +1837，門檻 1150，**MISS 約 687–717 行**。逐檔「估／實」對照見
   DoD#7 那一列；六個 spec §8.1 估算表完全沒列到的新檔（合計 241 行）是首輪超標的最大成因，
   T13 又疊加約 310 行換兩條 S0 關閉。**門檻本輪仍不調**——是否接受這個 known gap 進 release notes，
   或要求真的砍行數，是使用者的裁決（known gap 26）。
2. **DoD#11 執行檔增量超標**——T13 之後手動 lipo＋簽章量到 **3,815,328 bytes**，對 `c131c30`
   +644,640 bytes（+630 KB）、對現 main +645,136 bytes，**超標約 3.2 倍**（門檻 +200 KB）。
   T13 自己只貢獻約 +40 KB，主要膨脹發生在 T01–T12。是否接受這個 known gap，或投入時間找出
   哪些 Swift 元程式資料（witness table／泛型特化等）佔比最大並嘗試瘦身，是使用者的裁決。
3. **DoD#14／#15 RSS／動畫態 CPU 未量到**——`scripts/measure-cpu.sh` 開頭的 `pkill -f
   "AgentAura.app/Contents/MacOS/AgentAuraApp"` 會連帶殺掉使用者機器上正在跑的正式安裝
   （已用 `verify-app.sh` 的同款 pkill 實測證實這個風險是真的，見附錄二），且量測全程需要
   5 態 × 66 秒 ≈ 5.5 分鐘、腳本本身不會自動復原。integrator 判斷這超出可自行決定的範圍，
   兩輪都未執行。**需要使用者指定量測時機**（例如確認可以讓選單列消失 5–6 分鐘的時段），
   或接受這兩項留白進 release notes。
4. **兩個獨立的腳本 bug，建議另開一個 change 修**：
   - `build-app.sh`／`build-plugin.sh` 在 Xcode 27／Swift 6.4 的 `swiftbuild` 系統下，`lipo`
     撈到的是舊版 native build system 遺留的 stale 二進位（9/17 切換前的殘留），**完全靜默**、
     不反映目前程式碼——任何人在這台機器上跑 `build-app.sh` 都會拿到一份「看起來成功、實際是
     舊碼拼出來」的 bundle。
   - `measure-cpu.sh`／`verify-app.sh` 的收尾 `pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp"`
     用路徑字串比對，沒有分辨「自己剛開的那個」跟「使用者原本在跑的正式安裝」，會連帶殺掉後者。
   這兩個 bug 都獨立於本 change 的功能正確性，但會讓依賴這些腳本的所有未來驗收與量測失真或有
   破壞性副作用，建議合併成一個小 change 一次修掉。

### 平台限制（我們控制不了，明寫接受）

- Codex 沒有 `error` 訊號來源（F2／F4）→ 永遠不會亮紅燈；`docs/INSTALL.md` 已補交叉引用。
- 無法偵測 Codex 是否已信任 hook（F5）→ UI 只能講「下次會問你」，講不出「已生效」。
- Codex 的 hook 不寫 `async`（F14 未測）→ 每個事件同步等 ~7ms。
- F15 範圍限定：互動 TUI 的行程結構、`SessionEnd` 後 pid 是否結束、`comm` 辨識，皆未觀測
  （exec 模式量到的結論不能直接套用到互動模式）。
- `codex exec` 會寫使用者 `~/.codex/config.toml` 的 `trust_level`（F12）→ 端到端只能靠人（實機清單）。
- 兩個上游（Claude／Codex）的 session id 空間不交集是明寫的假設，不是我們控制的東西。

### 設計代價（權衡後的刻意選擇，不是缺陷）

- `timeout: 3` 是否真的觸發 Codex 的 clamping 警告未觀測——代價是失去「Codex 讀到了」這個最便宜
  的訊號（實機清單 ②③ 補）。
- 序列長度上限：CX37a 全部 ≤4（780 條全跑）、CX37b 生產路徑 ≤2（30 條）、CX42 憑證 ≤2（20 条）——
  更長的交錯序列未涵蓋，是成本與覆蓋的取捨。
- `.unsupportedCharacter` 不再給 snippet（D-w）——即使 snippet 產得出來也不畫，這是 P2「不給過期
  設定」優先於「給了但可能貼出壞路徑」的刻意選擇，有解鎖條件（互動探針量到引號可行就開後續 change）。
- Options 展開＋snippet 的總高度（1056／1047pt，修後）仍超過 780pt 天花板，**明寫接受**——
  780 是產品天花板不是量出來的自然高度，這個組合本來就在天花板管轄範圍外（spec §10-20）。
- Claude 側 CTA 仍是泛稱「Connect」不分 agent（明寫接受）；legend「Error」沒有面板內路徑通往
  「Codex 沒有 error 燈」的說明（明寫接受，help 文件裡有）；列標籤（「Codex」三個字）與權限文字
  同字級同色（明寫接受）。

### 驗收缺口（想驗但工具/環境不給，非本 change 造成）

- `Jargon.model` 的 Codex 分支只有 `gpt-5.5` 是實測值，其餘八列（含刻意變更的 `gpt-5`）是預期值。
- R-8 不變式 2（兩側同時真的在跑）自動化只驗到「同一顆二進位、兩邊 agent 各自正確」，「兩個上游
  同時真的觸發」只有實機 ⑧ 能驗。
- App 搬家後 `.connected` 永遠成立，偵測延遲到下一次 `reprobeCodex()`（啟動或開面板）。
- 內容比對與 `unlink` 之間的 TOCTOU 窄窗（CX31／CX17 已守 round-trip，但這個時間窗本身無法消除）。
- **DoD#3 的 46 條 gate 裡仍有約 34 條沒有逐條轉錄秒數進帳本**——mutation 本身都做過（commit
  訊息可查），只是彙整進這份帳本的動作本身耗時，兩輪 integrator 都優先做別的驗證，尚未補齊。

### 帳本/文件自身的品質問題（本輪新增修正，非產品缺陷）

- **CX1–CX57 裡 14 個「指名測試」欄的字面函式名與原始碼不符**（見上方新表），已建議把
  CX58（`everyNamedGateResolvesToAtLeastOneTest`）列為下一輪要落地的常設 gate。
- `Tests/AuraCoreTests/SnapshotIOTests.swift`／`Tests/AgentAuraAppTests/CodexEvidenceRenderer.swift`
  兩個檔已在 300/300 行零餘裕，`Sources/AgentAuraApp/StatusItemController.swift` 在 200/200——
  下一次動這三個檔要先拆，T13k 的驗收清單只記了 `AppDelegatePanelActionsWiredTests.swift`
  一個接近上限的 Tests 檔，漏了前兩個。
