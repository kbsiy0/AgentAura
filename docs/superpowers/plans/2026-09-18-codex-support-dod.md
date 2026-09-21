# DoD 帳本 · `change/codex-support`（T12）

spec `docs/superpowers/specs/2026-09-18-codex-support-design.md`（**r12**）§7 為門檻來源；
證據層 `docs/2026-09-18-codex-hook-probe.md`（**F1–F15**，F15 以 `8fdce0b` 的版本為準）。
基準取自 `change/codex-support` 分支點（`c131c30`，＝ `main` ＋ 探針文件），量測時用
`git worktree add <temp> <基準> --detach` 取乾淨副本，**不動共享工作目錄**。

**本檔在 T12 執行前寫好門檻與量法；「實測」「判定」兩欄由 T12 填。**
門檻不得在量完之後往下調——miss 就記 known gap（本專案已有兩次前例：+292 KB、+746 KB，
都是如實記錄不調門檻）。

**gate 編號**：本 change 新增的一律 `CX<n>`（**46 條**；CX37 拆成 a／b）；既有 gate 一律寫測試函式名。

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
| 1 | 測試全綠 | 連跑 **3 次** 0 flake，**含修好 `everyFixtureModelIsMapped`**、**且 `AURA_CODEX_PENDING_T05`／`_T10` 兩個旗標都已解除**（T05／T10 各自的驗收要附解除前／後的 `#expect` 與測試函式數，**只准上升**）；每次存全量 log | `swift test` ×3 ＋ CX44 | 3 輪皆 **646＋291＝937 tests／0 issue**（log：`swift-test-run1/2/3.log`）；`everyFixtureModelIsMapped` 現為 GREEN（獨立重跑 0.006s）；`grep AURA_CODEX_PENDING Sources Tests` 兩處皆 0 命中 | **PASS** |
| 2 | 新增測試數 | `#expect(` 淨增 **≥ 180**（基準 **1649**）；新增測試函式 **≥ 65**。**量法一次定案**（T04 review m3）：指令固定 `grep -rho '#expect(' Tests \| wc -l`，**每個 task 的報告附該 commit 的絕對值**（不只增量）——只報增量時，兩個端點各差 3 也看不出來。r4 是 170／62，**r5 增量＝CX42 約 +5、Jargon 三列 +3、CX37 拆 a／b +2**（`grep -c '#expect'` 數的是**原始碼出現次數**，迴圈只算一次——20／780 條序列不會讓這個數字暴增） | 前後 **`grep -rho '#expect(' Tests \| wc -l`**；`swift test` 的 tests 計數 | HEAD `#expect(`=**2025**、`@Test`=**941**。對 `c131c30`（1649／768）：+376／+173。對現 main `9ec85d0`（1652／770，本 change 真實貢獻）：+373／+171。兩個基準都遠超門檻（≥180／≥65） | **PASS** |
| 3 | gate mutation 帳 | **46 條**（CX1–CX46，CX37 拆 a／b）逐條有 `mutation / 指名測試 / 秒數`；**抽驗 5 筆現場重跑**（必含 CX2、CX4、CX15、CX32、**CX39**） | 彙整 T02–T11 的完成報告 ＋ 現場重跑 | **5 筆抽驗全部現場重跑成功**（見下表秒數欄：CX2 0.001s、CX4 0.001s、CX15 0.008s、CX32 0.007s、CX39 0.180s，皆還原後 `git status` 乾淨）＋ **CX44 現場新做**（Sources 0.032s／Tests 0.056s）。另從 commit 訊息額外找到 7 條有秒數記載（CX7、CX8/CX10/CX38、CX9、CX37a、CX37b，已填入下表）。**其餘 ~34 條**：commit 訊息都記載了 mutation 與指名測試（來源 task 欄已由 plan 填好），但秒數未逐條轉錄進本帳本——彙整 73 個 commit 全文本超出本輪時間預算，標記「未記」而非編造 | **PARTIAL**（5 筆抽驗＋CX44 達標；46 條逐一秒數未全部彙整齊，缺口誠實列在下表） |
| 4 | **Claude 側零回歸**（紅線） | `git diff <基準>..HEAD -- plugin/hooks/hooks.json` **完全為空**；`handledEvents` 的 19 個名字一字未動 | `git diff` ＋ 逐行看 `EventMapping.swift` 的 diff | `git diff c131c30..HEAD -- plugin/hooks/hooks.json` 輸出為空。`EventMapping.swift` 的 diff 只有純新增（`codexEvents`／`codexOnlyEvents`／`case "Interrupt"`），`handledEvents` 陣列內文字一行未動（逐行核對過） | **PASS** |
| 5 | **Claude 狀態檔位元組不變** | round1／1b／2／3 跑 merge（用**生產的** `SnapshotIO.encoder`）序列化後**不含 `agent` 鍵**；**且**不帶 `--agent` 真 spawn 一次後，**原始檔案文字**不含 `"agent"` | CX9 **兩層**；**這一格的證據以生產層那半為準**（`agent == nil` ≠「檔案裡沒有這個鍵」——自訂 encode 可能寫出 `"agent":null`，解碼回來仍是 nil 而上游全綠） | `swift test --filter "claudeStateFileHasNoAgentKey\|codexStateFileCarriesAgent"`：3 tests 全綠（純函式層 0.017s；生產層真 spawn 0.022s；CX10 真 spawn 1.006s） | **PASS** |
| 6a | **`config.toml` 零變動（自動化側）** | `swift test` ×3 全程位元組完全不變 | 開工前存副本，跑完 `diff` | 開工前存 md5＝`74472e19f4985c5f6675df4ce20d3f7a`；3 輪 `swift test` 全跑完後 `diff`／`md5` 完全相符；`~/.codex/hooks.json` 全程未出現 | **PASS** |
| 6b | **`config.toml` 受控變動（實機側）** | 實機 ①–⑧ 跑完：**不得新增任何 `[hooks*]` 段**，diff **僅限** `[projects.*] trust_level`（F12） | `diff <副本> ~/.codex/config.toml` 逐行判讀 | 實機清單留給使用者跑，integrator 不執行互動式安裝流程 | **N/A（實機，留給使用者）** |
| 7 | `Sources/` 淨增 | **≤ 1150 行**（基準 7846 → ≤ 8996）；逐檔估算 ≈ 1060（spec §8.1），留 8% 餘裕。r3 是 975／門檻 1050；**r4 增量＝Jargon +30、RejectionKind +20、stale/snippet 兩種文案與分支 +35**。**若 R-5／R-6 日後被砍，門檻要跟著降回 900／啟動 +2 ms**，否則就變成「先加需求再放寬門檻」的通道。**超過就先砍 instrumentation 與非必要碼，不調門檻** | `find Sources -name '*.swift' \| xargs cat \| wc -l` | HEAD＝**9403**。對 `c131c30`（7846）：**+1557**。對現 main `9ec85d0`（7876，merge main 對 Sources 淨增實測是 **0**——見下方「merge main 對 Sources 無淨增」附註）：**+1527（本 change 真實貢獻）**。兩個基準都超門檻 1150。逐檔估／實對照與可砍候選見下方新增小節 | **MISS**（超標 377–407 行，逐檔對照見下） |
| 8 | 單檔行數 | `Sources/` ≤ 200、`Tests/` ≤ 300，**零例外**；三個預先拆檔各自是零行為變更的獨立 commit（`AppDelegate+Links.swift` **在 T07**——r9 從 T10 提前，理由見 plan T07 第一步 (b)；`CodexOptionsRowTests.swift` 在 T07；`AppDelegateCodexWiredTests.swift` 在 T10） | `IsolationTests.fileLengthLimit` ＋ 手動複查最大的 5 個檔 ＋ 三個搬移 commit 的 diff | `IsolationTests.fileLengthLimit` GREEN。三個搬移 commit 逐一核對：`04e873d`（`AppDelegate+Links.swift`）#expect 0增/0減、函式名逐字對應；`247edd8`（`CodexOptionsRowTests.swift`）14增/14減、函式名逐字對應；`e6ef148`（**實際檔名是 `AppDelegatePanelActionsWiredTests+Codex.swift`，非帳本寫的 `AppDelegateCodexWiredTests.swift`**）body 逐字搬移，換成一行委派呼叫，3增/3減皆為委派呼叫本身的行 | **PASS**（檔名有一處與帳本記載不同，已在報告點出） |
| 9 | 零新依賴／新 target | `Package.swift` diff 為空 | `git diff -- Package.swift` | `git diff c131c30..HEAD -- Package.swift` 輸出為空 | **PASS** |
| 10 | module 基準 | `AuraCore` = Foundation、`AuraHookFile` = Foundation ＋ CoreServices。**`AuraHookFile` 不得 import Security**（`RunningBundle` 是 App 層唯一計算點） | `IsolationTests.nonUITargetsLoadNoUIModules` | 測試 GREEN（17.05s）；`grep -rn "import Security" Sources/AuraHookFile/` 0 命中；全 repo 只有 `Sources/AgentAuraApp/RunningBundle.swift` import Security | **PASS** |
| 11 | 執行檔增量 | **≤ +200 KB** universal（基準 3,140,864）。依據：既有兩次量到的「每新增一個 SwiftUI view ≈ 60–80 KB/arch」，本 change 新增 1 個 view | `./scripts/build-app.sh` 後 `ls -l` | **發現環境 bug**：Xcode 27／Swift 6.4 的 `swiftbuild` 系統把每次 `--arch` 建置輸出寫到同一個共用路徑 `.build/out/Products/Release/`（互相覆寫），但 `build-app.sh` 的 `lipo` 硬寫舊版路徑 `.build/<arch>-apple-macosx/release/`——那兩份是 9/17 切換 Xcode 前的殘留，導致 `build-app.sh` 組出的 bundle **不反映目前程式碼**。改用手動 lipo（各 arch 建置後立即複製再合併，ad-hoc 簽章比照 `build-app.sh` 手法）取得真數字：簽章後 HEAD＝**3,774,704**、`c131c30`＝**3,170,688**、`9ec85d0`＝**3,170,192**。增量對 `c131c30`：**+604,016 bytes（+590 KB）**；對現 main（真實貢獻）：**+604,512 bytes（+590 KB）** | **MISS**（超標約 3 倍；且揭露 `build-app.sh` 在新 toolchain 下的靜默失真，建議另立 change 修） |
| 12 | **面板路徑成本** | **`reprobeCodex()` 100 次 ≤ 10 ms**（穩態；`.notConnected` 與 `.connected` **各量一次並分開記**）。**量 `reprobeCodex()` 端到端，不是只量 `probe()`**——那才是 `onOpen` 實際跑的東西（r3 m3）。可並列 `CodexInstaller.probe()` 的數字供分解 | 行程內暫時測試（`ContinuousClock`），跑完即刪、`git status` 確認乾淨 | 暫時測試檔 3 輪：`.notConnected` 100 次 = 0.0714–0.0814 ms；`.connected` 100 次 = 0.1173–0.1276 ms。分解：`CodexInstaller.probe()` 純 I/O 100 次 = 1.326–1.358 ms。量完已刪 `_T12TempPerfTests.swift`，`git status` 乾淨 | **PASS**（遠低於 10 ms，餘裕 ＞98%） |
| 13 | 啟動時間增幅 | **≤ +3 ms**（多一次 `lstat`、最多讀 64 KiB、一次 `SecTranslocateIsTranslocatedURL`、一次產生器呼叫——**四個行程常數搬到啟動時算**，D-t） | `applicationDidFinishLaunching` 首尾時戳，各 3 輪 × 10 次取中位數；基準側在 worktree 量 | HEAD（`CodexDependencies.production()`＋`init`＋`launch`＋`terminate`，真實生產路徑）3 輪中位數：1.127／1.210／1.293 ms。基準（`c131c30`，同範圍：`init`＋`launch`＋`terminate`，無 Codex）3 輪中位數：2.052／2.092／2.112 ms。**增量為負**（HEAD 比基準快約 0.8–0.9 ms），落在量測噪訊範圍內（每輪都有 1 個 ~130ms 離群樣本，已用中位數濾除）；四個新增計算（`SecTranslocateIsTranslocatedURL`／路徑字串檢查／JSON 產生／lstat）皆為微秒級純記憶體操作，量不出正增量合理 | **PASS**（未偵測到回歸；跨 worktree 比較有量測噪訊，方向性證據為主，非精確到 0.1ms 的差值） |
| 14 | RSS 增幅 | **≤ 1 MB** | `scripts/measure-cpu.sh`（先隔離量測者自己的 session） | **未量到**——`measure-cpu.sh` 第一步 `pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp"` 會連帶殺掉使用者機器上正在跑的正式安裝（實測跑 DoD#19 時已證實此風險：見下方 known gap），且腳本結尾不會自動重開使用者原本的 `/Applications/AgentAura.app`，全程 5 態 × (6s+60s) ≈ 5.5 分鐘期間使用者選單列會被換成本地測試 build。這超出 integrator 可自行決定的風險等級，未執行 | **未量到（環境風險，需使用者裁決量測時機/方式）** |
| 15 | 動畫態 CPU | 不得比基準更差（五態各量） | `scripts/measure-cpu.sh`，連續兩輪 | 同 #14，同一支腳本、同一個風險，未執行 | **未量到（同 #14 原因）** |
| 16 | plugin 契約 | 零 error 零 warning。**這也是 `Interrupt` 接縫的第四道防線、且是唯一一道不依賴我們自己寫的斷言的**（T03 review 實測：註冊 `Interrupt` → `unknown hook event; entry ignored at runtime` ＋ `--strict` 視 warning 為 error → 失敗）。**注意**：本機 validator 只給 warning，**整份拒載是 2026-09-15 在同事機器上量到的**（`distribution-and-hook-compat`）——本機通過不構成「全有全無」的反證 | `claude plugin validate --strict ./plugin` 與 `.` | 兩者皆輸出「✔ Validation passed」，零 error 零 warning | **PASS** |
| 17 | 安裝鏈路（Claude） | 全項 PASS（含 `settings.json` 零污染、一輪真的 `claude -p`） | `./scripts/verify-install.sh` | 全 5 大項全部 ✓（plugin 二進位／已註冊／validator 乾淨／settings.json 零污染／實機跑一輪 4→5 狀態檔／狀態檔內容合理）。跑前後安裝狀態（symlink 指向 `/Applications/AgentAura.app`、settings.json 零污染）未被腳本改動 | **PASS** |
| 18 | 完整移除 | `verify-uninstall.sh` **7 項全 PASS**；第 7 項兩個方向都驗過；`--only 7` 可單獨執行且**不觸發** `osascript`／`sfltool` | CX27 ＋ 實機 ⑥ | `./scripts/verify-uninstall.sh --only 7` → 「✓ Codex hook 已移除或從未接上」，未觸發 `osascript`／`sfltool`（讀腳本原始碼確認 `should_run` 分派邏輯會整段跳過）。CX27 相關測試在全量 `swift test` 中已綠 | **PASS**（`--only 7` 這一項；兩個方向的實機驗證與 ⑥ 留給使用者實機清單） |
| 19 | bundle 佈局 | PASS，缺 bundle 時 FAIL 不 skip | `./scripts/verify-app.sh` | 全 6 大項全部 ✓。**副作用**：腳本收尾 `pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp"` 誤殺了使用者當時在跑的正式安裝（PID 2194），已立即 `open /Applications/AgentAura.app` 重開恢復（新 PID 47885）。這證實了 #14/#15 未執行的顧慮是真實風險，不是過度謹慎 | **PASS**（功能面；連帶殺掉使用者正式安裝的風險已記錄並復原，建議腳本改成只 kill 自己剛開的那個 PID） |
| 20 | 測試不得跑 `codex exec` | `Tests/`／`scripts/` 命中數 **= 0**（＋正向對照） | CX30 | `grep -rn "codex exec" Tests/ scripts/ .github/` 只命中 `NoCodexExecInRepoTests.swift`／`CodexEventsTests.swift` 的 doc comment（`///` 開頭，非可執行行）。CX30 測試套件全綠 | **PASS** |
| 21 | 文件路徑一致 | `README.md`／`SECURITY.md` 都含 `.codex/hooks.json` | CX29 | `grep -l ".codex/hooks.json" README.md README.zh-TW.md SECURITY.md` 三份全部命中 | **PASS** |
| 22 | help 涵蓋 | 兩個語言都涵蓋**每一個**新的 Options 列標題（含「重新接上 Codex」） | CX28 | `HelpDocOptionsRowCoverageTests` 全綠（含 CX28 mutation②正向對照，6 test case） | **PASS** |
| 23 | **CX37a／CX37b 的成本** | CX37a **780 條全跑、零 spawn**（毫秒級，**不縮減**）；CX37b **30 條、11 次真 spawn**、走 `SpawnGate`。兩條的 doc comment 要互相點名（a 的等價理由／b 的長度上限理由）。**實測秒數寫進報告** | T06 的完成報告 ＋ 現場重跑 | 現場重跑：CX37a 780 test cases，gate 內部計時 **2.315s**；CX37b 30 test cases，gate 內部計時 **2.291s**。commit 訊息記載的原始數字：CX37a 1.9s／2930 次操作；CX37b 4.2–8.4s（視全套件負載）／11 次 `installer.connect(` 呼叫 | **PASS** |
| 24 | persona | 加權 **≥ 6.0**；硬下限四條（見下） | Tier 1，integrator 綠後派 persona-tester | 由主 session 在 integrator 綠燈後另派，不屬本輪範圍 | **N/A（persona-tester 另派）** |

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

## Gate mutation 帳（46 條；T12 彙整，✓現場 = 抽驗重跑）

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
| **CX24** | `CodexWiringSmokeTests` | ① 分支改 `break` ② banner 只留一句 ③ 拿掉 `onOpen` 的 `reprobeCodex()` | `codexConnectChainIsWired`（五段；③ 紅在第五段；第③段比對**位元組**） | | T10 |
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
| **CX36** | `CodexSectionRenderTests` | ① 錯誤文案不插字元（籠統句） ② **被拒時仍畫「重新接上」按鈕** ③ **把 `.mustMoveToApplications` 分支改成會畫 snippet → 必須紅**（T09 review M1：輸入改成真 snippet 之前，這個 mutation 紅 0 條） | `codexSectionRendersEveryState`（六態 ＋ 兩種 Rejection；`.mustMoveToApplications` 那格**必須餵真的 `codexSnippet`**） | | T09 |
| **CX37a** | `CodexCoexistenceSequenceTests` | `CodexInstaller.connect` 順手 touch `<claudeHome>/skills/agentaura` 的 mtime（**CX37a 與 CX37b 都必須紅**，兩條都記） | `bothSidesNeverDisturbEachOthersFiles`（**780 條全跑**，`connectClaude` 走 `guardWriteTarget()` ＋ `atomicReplace()`，零 spawn） | commit 訊息：**1.9s**／780 條／2930 次操作。T12 現場（正常路徑，非 mutation）：gate 內部計時 2.315s | T06 |
| **CX37b** | `CodexCoexistenceSequenceTests` | 同 CX37a | `bothSidesNeverDisturbEachOthersFilesOnProductionPath`（長度 ≤ 2 共 30 條，完整 `connect`，11 次真 spawn） | commit 訊息：**4.2–8.4s**（視全套件負載）／11 次 `installer.connect(`。T12 現場（正常路徑，非 mutation）：gate 內部計時 2.291s | T06 |
| **CX38** | `EndToEndWiredGateTests`（或拆出的 `EndToEndDualAgentTests`） | `--agent` 解析改成一律回 `.claude` | `oneBinaryServesBothAgentsInOneRoot`（兩個方向各跑一次） | commit 訊息：**1.6s**（8 個斷言，4 個 codex session × 正序／反序各一次） | T05 |
| **CX39** | `CodexWiringSmokeTests` | **把 R-9 的 guard 移到 `disconnect` 之後** | `codexReconnectNeverDisconnectsWhenPathIsRejected`（`disconnect` 次數 0、檔案仍在） | **0.180s**（T12 現場重跑，`fakeInstaller.disconnectCallCount` 從預期 0 變成 1） | T10 · **抽驗必做 ✓現場** |
| **CX40** | `CodexStateTests` ＋ `CodexWiringSmokeTests` | **讓 `reprobeCodex` 在 `.mustMoveToApplications` 時仍然給 snippet**（＝拿掉 `codexSnippet` 的條件） | `codexSnippetIsWithheldWhenPathWillVanish`（**乘積表**，`.mustMoveToApplications` 整行 nil）。**與 CX36③ 是同一條不變式的兩層**（決策層／view 層），**D-s 在兩者落地前零強制力** | | T10 |
| **CX41** | `JargonCodexModelTests` | ① Codex 分支回傳 raw（**既有 `everyFixtureModelIsMapped` 也必須紅**，兩條都記） ② 把 `o3` 改成 `O3` ③ **把 Codex 分支移到既有演算法之後 → `gpt-5` 那列必須紅** | `jargonModelCoversCodexNaming`（釘死的輸入→輸出表**九列**，含 `gpt-5`／`gpt-4.1-mini`／`gpt-5.5[high]`；既有九列輸出完全不變） | | T05 |
| **CX42** | `CodexCredentialSequenceTests` | `performDisconnect()` 順手 `defaults.removeObject(forKey: CodexHookStore.key)` | `bothSidesNeverDisturbEachOthersCredentials`（**20 條**長度 ≤ 2 序列，fake ＋ 注入 suite、零 spawn；另一側鍵位元組不變 ＋ 鍵集合**差集**斷言） | | T10 |
| **CX44** | `NoPendingFlagRemainsTests` | 在 **`Sources/` 與 `Tests/` 各留一個** `AURA_CODEX_PENDING_T08`（**兩處都要紅**） | `sourcesHasNoPendingFlag`／`testsHasNoPendingFlag`（**`Sources/` ＋ `Tests/`** 都不得殘留 pending 標記；**含暫存目錄正向對照** `scanCatchesRealPendingFlag`） | **Sources 0.032s／Tests 0.056s**（T12 新做，兩處各放一個探針檔，兩處都紅；還原後乾淨） | T12 · **✓現場** |
| **CX45** | `SessionState` 來源掃描 | 在 `Sources/` 加第二個 `SessionState(` 建構點且不傳 `agent:` | `sessionStateProductionConstructionSitesPassAgent`（`Sources/` 的 `SessionState(` 恰 1 處且含 `agent:`） | | T05d |
| **CX46** | `OptionsMenuModel` 呼叫點來源掃描 | 把 view 那一行改回 `codex: .unavailable, codexPathRejection: nil` | `optionsRowsCallSitePassesRealCodexState`（`Sources/` 不得出現那兩個字面）。**已知假陰性**：跨行寫法掃不到、註解過濾兩個缺口——主守衛是 T10 的**行為斷言**，本條是便宜的第二道 | | T08 |

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
