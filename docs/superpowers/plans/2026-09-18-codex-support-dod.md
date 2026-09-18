# DoD 帳本 · `change/codex-support`（T12）

spec `docs/superpowers/specs/2026-09-18-codex-support-design.md`（**r1**）§7 為門檻來源；
證據層 `docs/2026-09-18-codex-hook-probe.md`（F1–F13）。
基準取自 `change/codex-support` 分支點（`c131c30`，＝ `main` ＋ 探針文件），量測時用
`git worktree add <temp> <基準> --detach` 取乾淨副本，**不動共享工作目錄**（多 agent 併行中）。

**本檔在 T12 執行前寫好門檻與量法；「實測」「判定」兩欄由 T12 填。**
門檻不得在量完之後往下調——miss 就記 known gap（本專案已有兩次前例：
panel-legend-palette 的 +292 KB、app-shell 的 +746 KB，都是如實記錄不調門檻）。

## 基準值（2026-09-18 量）

| 項目 | 基準 |
|---|---|
| `Sources/` 總行數 | **7846**（104 個 `.swift`） |
| `Tests/` 的 `#expect` 總數 | **1652**（176 個 `.swift`） |
| `build/AgentAura.app/Contents/MacOS/AgentAuraApp` | **3,140,864 bytes**（universal） |
| `plugin/hooks/hooks.json` | 註冊 19 個事件（＝ `EventMapping.handledEvents`） |
| `~/.codex/config.toml` md5 | T12 開工當下現場量一次，全程比對 |

## DoD 全表

| # | 項目 | 門檻 | 量法 | 實測 | 判定 |
|---|---|---|---|---|---|
| 1 | 測試全綠 | 連跑 **3 次** 0 flake；每次存全量 log（app-shell 的教訓：只擷取 `tail -5` 會抓不出是哪一條紅） | `swift test` ×3 | | |
| 2 | 新增測試數 | `#expect` 淨增 **≥ 120**（基準 1652）；新增測試函式 **≥ 45** | 前後 `grep -rho '#expect' Tests \| wc -l`；`swift test` 的 tests 計數 | | |
| 3 | gate mutation 帳 | **29 條**（G1–G29）逐條有 `mutation / 指名測試 / 秒數`；**抽驗 3 筆現場重跑**（必含 G2、G14、G13） | 彙整 T02–T11 的完成報告 ＋ 現場重跑 | | |
| 4 | **Claude 側零回歸**（紅線） | `git diff <基準>..HEAD -- plugin/hooks/hooks.json` **完全為空**；`EventMapping.handledEvents` 的 19 個名字一字未動 | `git diff` ＋ `git diff -- Sources/AuraCore/EventMapping.swift` 逐行看 | | |
| 5 | **Claude 狀態檔位元組不變** | 用 round1／round1b／round2／round3 四份 fixture 跑完 merge 後序列化，**不含 `agent` 鍵** | G8（`claudeStateFileHasNoAgentKey`） | | |
| 6 | **`~/.codex/config.toml` 零變動** | 全程（`swift test` ×3 ＋ 實機 ①–⑥）md5 與位元組數完全一致 | 開工前後各 `md5 ~/.codex/config.toml` ＋ `stat -f %z` | | |
| 7 | `Sources/` 淨增 | **≤ 900 行**（基準 7846 → ≤ 8746）；逐檔估算加總 ≈ 830（spec §8.1），留 8% 餘裕。**超過就先砍 instrumentation 與非必要碼，不調門檻** | `find Sources -name '*.swift' \| xargs cat \| wc -l` | | |
| 8 | 單檔行數 | `Sources/` ≤ 200、`Tests/` ≤ 300，**零例外** | `IsolationTests.fileLengthLimit` ＋ 手動複查最大的 5 個檔 | | |
| 9 | 零新依賴／新 target | `Package.swift` diff 為空 | `git diff -- Package.swift` | | |
| 10 | module 基準 | `AuraCore` = Foundation、`AuraHookFile` = Foundation ＋ CoreServices（CryptoKit 不得出現在這兩層，D-h） | `IsolationTests.nonUITargetsLoadNoUIModules` | | |
| 11 | 執行檔增量 | **≤ +200 KB** universal（基準 3,140,864）。依據：既有兩次量到的「每新增一個 SwiftUI view ≈ 60–80 KB/arch」，本 change 新增 1 個 view（`CodexSectionView`） | `./scripts/build-app.sh` 後 `ls -l` | | |
| 12 | `CodexInstaller.probe()` 成本 | **100 次 ≤ 10 ms**（穩態；`.notConnected` 與 `.connected` **各量一次並分開記**——既有 `Installer.probe()` 的教訓正是兩個狀態差一個數量級） | 行程內暫時測試（`ContinuousClock`），跑完即刪、`git status` 確認乾淨 | | |
| 13 | 啟動時間增幅 | **≤ +2 ms**（多一次 `lstat` ＋ 最多讀 1 KiB）；行程內量測，各 3 輪 × 10 次取中位數 | `applicationDidFinishLaunching` 首尾時戳，基準側在 worktree 量 | | |
| 14 | RSS 增幅 | **≤ 1 MB** | `scripts/measure-cpu.sh`（先隔離量測者自己的 session） | | |
| 15 | 動畫態 CPU | 不得比基準更差（五態各量） | `scripts/measure-cpu.sh`，同一台機器連續兩輪 | | |
| 16 | plugin 契約 | 零 error 零 warning | `claude plugin validate --strict ./plugin` 與 `.` | | |
| 17 | 安裝鏈路（Claude） | 全項 PASS（含 `settings.json` 零污染、一輪真的 `claude -p`） | `./scripts/verify-install.sh` | | |
| 18 | 完整移除 | `verify-uninstall.sh` **7 項全 PASS**；第 7 項的兩個方向都驗過（我們的檔 → FAIL；別人的檔 → PASS） | G26 ＋ 實機 ⑥ | | |
| 19 | bundle 佈局 | PASS，缺 bundle 時 FAIL 不 skip | `./scripts/verify-app.sh` | | |
| 20 | 測試不得跑 `codex exec` | `Tests/`／`scripts/` 命中數 **= 0**（＋暫存目錄正向對照證明掃描沒壞） | G29 | | |
| 21 | 文件路徑一致 | `README.md`／`SECURITY.md` 都含 `.codex/hooks.json`（字面來自生產常數） | G28 | | |
| 22 | help 涵蓋 | 兩個語言的 `help-*.html` 都涵蓋新的 Options 列標題 | G27 | | |
| 23 | persona | 加權 **≥ 6.0**；硬下限三條（見下） | Tier 1，integrator 綠後派 persona-tester | | |

### persona 硬下限（低於門檻即 no-go，不得用平均分蓋過）

| 代號 | persona | 問題 | 下限 |
|---|---|---|---|
| P1 | 只用 Codex、不用 Claude Code 的人 | 第一次開面板，30 秒內知道該按哪裡（而不是被兩張「還沒接上」的卡片夾住） | **≥ 5** |
| P2 | 已有自己 `~/.codex/hooks.json` 的進階使用者 | 看完畫面後，相信我們**不會**動他的檔；snippet 可貼、貼了會動 | **≥ 6** |
| P3 | 不懂「信任」提示的 vibe coding 使用者 | 按下接上之後，知道「還要在 Codex 裡按一次同意」才會生效 | **≥ 5** |
| P4 | 兩個都用的人 | 同一個專案同時跑 Claude 與 Codex 時，兩列分得出來 | **≥ 5** |

## Gate mutation 帳（29 條；T12 彙整，✓現場 = 抽驗重跑）

| Gate | 位置 | Mutation | 指名測試 | 秒數 | 來源 task |
|---|---|---|---|---|---|
| G1 | `CodexEventSeamTests` | `codexEvents` 少一個事件 | `codexEventSetIsPinnedToProbe` | | T03 |
| **G2** | `CodexEventSeamTests` | 把 `Interrupt` 加進 `handledEvents` | `interruptNeverEntersHandledEvents`（**＋既有 `registeredEventsMatchHandledEvents` 也必須紅**，兩條都記） | | T03 · **抽驗必做** |
| G3 | `CodexEventSeamTests` | 從 `handledEvents` 拿掉 `PreCompact` | `codexSharedEventsReuseClaudeMapping` | | T03 |
| G4 | `CodexHooksJSONTests` | ① 產生器寫死 11 個事件 ② `command` 漏 `--agent codex` ③ 路徑不跳脫 | `codexHooksJSONRegistersExactlyCodexEvents` | | T04 |
| G5 | `CodexEventSeamTests` | 在 `plugin/hooks/hooks.json` 加 `Interrupt` | `claudeHooksJSONHasNoInterrupt` | | T03 |
| G6 | `AgentArgumentTests` | 未知值改成回 `.codex` | `agentArgumentParsing` | | T02 |
| G7 | `AuraHookCLITests`（E2E） | 解析失敗時寫 stderr | `auraHookStaysSilentForEveryAgentArgument` | | T05 |
| G8 | `AgentSnapshotCodableTests` | `storedRawValue` 對 `.claude` 回 `"claude"` | `claudeStateFileHasNoAgentKey` | | T05 |
| G9 | `EndToEndWiredGateTests` | `main.swift` 忘了把 agent 傳進 `merge` | `codexStateFileCarriesAgent` | | T05 |
| G10 | `AgentSnapshotCodableTests` | `agent` 改成非 Optional | `legacySnapshotWithoutAgentDecodes` | | T05 |
| G11 | `AgentSnapshotCodableTests` | `agent` 改成 `Agent?`（enum） | `unknownAgentFallsBackWithoutFailingDecode` | | T05 |
| G12 | `Round4FixtureTests` | `effect` 對 `Interrupt` 改回 `.noChange` | `round4FixtureParsesAndMatchesProbeTable` | | T05 |
| **G13** | `CodexPathScopeTests` | `connect` 順手寫 `hooks.json.bak` | `codexInstallerTouchesOnlyHooksJSON` | | T06 · **抽驗必做** |
| **G14** | `CodexInstallerClobberTests` | 拿掉 `O_EXCL`（改 `O_CREAT\|O_WRONLY\|O_TRUNC`） | `codexConnectRefusesEveryOccupiedShape`（**報告要寫明是哪一格紅的：symlink→`config.toml`**） | | T06 · **抽驗必做** |
| G15 | `CodexInstallerTests` | `connect` 少寫最後一個 byte | `codexConnectWritesGeneratorBytes` | | T06 |
| G16 | `CodexInstallerTests` | 拿掉 digest 比對 | `codexDisconnectOnlyRemovesOurBytes` | | T06 |
| G17 | `CodexPathScopeTests` | 快照改用字面路徑（不解 `realpath`） | `codexHomeSymlinkWritesInsideResolvedPath` | | T06 |
| G18 | `CodexStateTests` | 把 `symlink` 併進 `.notConnected` | `codexStateCoversEveryObservationShape` | | T07 |
| G19 | `OptionsMenuModelTests` | `.unavailable` 也給「接上 Codex」 | `codexRowsAppearOnlyWhenAvailable` | | T07 |
| G20 | `OptionsMenuModelTests` | 把 `.connectCodex` 塞進 `nonMenuKinds` | `optionsRowsCoverEveryAction` ＋ `nonMenuKindsIsExactlyThatLiteralSet` | | T07 |
| G21 | `PanelViewModelTests` ＋ `CodexRowLabelPixelTests` | `agentLabel` 對 `.claude` 也給值 | `agentLabelOnlyForNonClaude`（model ＋ 像素兩半） | | T08／T09 |
| **G22** | `CodexRowLabelPixelTests` | 標籤另起一行 | `codexLabelDoesNotChangeRowHeight` | | T09 |
| G23 | `CodexWiringSmokeTests` | ① `.connectCodex` 分支改 `break` ② banner 只留一句 | `codexConnectChainIsWired`（四段各自失敗訊息） | | T10 |
| G24 | `CodexWiringSmokeTests` ＋ 來源掃描 | `codexHome` 改成 `environment["HOME"]` | `productionCodexHomeIsRealHome` | | T10 |
| G25 | `UninstallerTests` | codex disconnect 與 `erasePersistentDomain` 對調 | `uninstallRemovesCodexBeforeErasingDefaults` | | T10 |
| G26 | script gate | 拿掉腳本第 7 項 | `verifyUninstallScriptDetectsOurCodexHooks` | | T11 |
| G27 | `HelpDocOptionsRowCoverageTests` | help 少寫「接上 Codex」 | 兩個語言各一條 | | T11 |
| G28 | 文件掃描 | 從 `SECURITY.md` 刪掉 `.codex/hooks.json` | `securityDocListsEveryPathWeWrite` | | T11 |
| G29 | 全 repo 掃描 | 在腳本裡加一行 `codex exec` | `noCodexExecInRepo` | | T11 |

**額外必記的一筆（不是 gate，是回歸證人）**：T01 的 `DirectoryTreeSnapshot` 抽取之後，
**當場重跑既有 G2 的 mutation**（`connect` 順手寫 `settings.json.bak`）確認 `InstallerPathScopeTests`
仍然精準紅——抽取沒有讓既有 gate 變鈍。

## 使用者實機清單（自動化做不到的六件事；T12 交付，最終報告附）

`codex exec` 會寫 `[projects."<cwd>"] trust_level` 進使用者的 `config.toml`（F12），
所以**這六項一律由人跑，不進任何腳本**。每項都要有「操作 → 預期 → 實際」。

| # | 操作 | 預期 | 實際（請填） |
|---|---|---|---|
| ① | 在**有** `~/.codex` 的機器開面板；再在**沒有**的機器開一次 | 有：看得到「接上 Codex」；沒有：面板**完全看不到任何 Codex 字樣**，版面與改動前一致 | |
| ② | 按「接上 Codex」 | `~/.codex/hooks.json` 出現；內容是 12 個事件、絕對路徑、`--agent codex`；`config.toml` 的 md5 **前後相同** | |
| ③ | 開一個**新的** Codex session（互動 TUI，不是 `codex exec`）→ Codex 問信任 → 按同意 → 讓它跑一個工具 | 燈真的動（working → done）；面板出現一列帶「Codex」標籤 | |
| ④ | 再開一個 session，信任提示**按拒絕** | 燈不動；**App 不得宣稱已生效**（畫面上找不到任何說「已生效」的字） | |
| ⑤ | 先手動放一份自己的 `~/.codex/hooks.json`（內容不含 `--agent codex`）→ 開面板 | 顯示 snippet、**沒有**一鍵接上按鈕；該檔 md5 前後相同；複製鈕真的把 snippet 放進剪貼簿 | |
| ⑥ | 在 ② 的狀態下執行「完整移除」→ 跑 `scripts/verify-uninstall.sh` | 7 項全 PASS；接著重做 ⑤ 的情境再移除一次 → **別人的 hooks.json 仍在** | |

## Known gaps（spec §10 沿用 8 條；T12 若有新增在此追加）

沿用 spec r1 §10 第 1–8 條（Codex 互動事件形狀待驗、無 error 來源、無法偵測信任、
不寫 `async`、hooks.json 頂層形狀只有間接證據、disconnect 的 TOCTOU 窄窗、
`codex exec` 不可用於自動驗收、兩個 agent 共用狀態目錄），逐字見 spec §10，此處不重複。

| # | 內容 | 性質 | 落點 |
|---|---|---|---|
| | （T12 量測後追加） | | |
