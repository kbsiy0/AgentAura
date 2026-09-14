# DoD 量測 · `change/app-shell`（T10）

量測時間 2026-09-10 17:52–18:31 · 機器 Darwin 25.6.0 · HEAD `eaac16b`（T08 之後，T09 已在此之前併入）。
基準 `main`（`39984eb`，含 `change/ack-on-close` #6）用 `git worktree add <temp> main --detach` 取乾淨副本量測，
不動共享工作目錄。spec r7 §8 為門檻來源。integrator 純機器面，不模擬使用者、不改生產碼
（本輪唯一產物是三筆用完即刪的暫時量測測試，見下方「量測方法」，不進交付）。

## 摘要

**8 項 ✅、2 項 ❌、1 項 ⚠️（噪訊內、方向不一致）、4 項手動待使用者實測、1 項 persona 待派。**
兩項 miss 都不是回歸——是**新增能力的真實平台成本**（連 exec 驗證需要的 stat／realpath 開銷、
SwiftUI 新增五個 view 型別的程式碼體積），與上一個 change（panel-legend-palette）的 +292KB miss
同一個家族，**如實記錄，不調門檻**。

## DoD 全表

| 項目 | 門檻（spec §8） | 實測 | 判定 |
|---|---|---|---|
| 測試全綠 | 465+，連跑 3 次 0 flake | 465 tests / 76 suites。連跑 20 次：19 次 GREEN，**1 次 RED**（第 3 次，17:54:01 附近，2 issues）；因為那次我只擷取了 `tail -5` 沒有存全量 log，**指不出是哪一條測試**——這是我自己的量測疏失，誠實記下而非略過。之後改成每次存全量 log 又跑了 17 次（含最初 2 次），全部 GREEN，未能重現細節。已知這個 codebase 有 exec 驗證在全套件並行時搶資源的既有 flake 家族（T06b／T08 都修過一輪），這次的 1/20 大機率同源，但沒有實證可指認，不能斷言已經歸零 | ⚠️ 帶條件：門檻字面（3 次 0 flake）在**第一次**嘗試就沒過，擴大到 20 次後失敗率 5%；**沒有）具體測試名可回報**，這本身是缺口 |
| 新增測試數 | ≥ 40 | `main`（`39984eb`，build-plugin 後）293 tests / 37 suites → `change/app-shell`（`eaac16b`）465 tests / 76 suites。**新增 172 條測試、39 個 suite**；`#expect` 673 → 1039（+366） | ✅ |
| gate mutation | swift test 的 15 條（G1–G8、G9a/b/c、G10–G13，其中 G3 兩筆、G6 兩筆、G10 三筆）＋ G14 一筆 | 見下方「gate mutation 彙整表」。全部彙整自 T02–T09 commit 的逐筆記錄；**抽驗 3 筆現場重跑**（affordance 列序回歸、G3(a) 寫入點型別檢查、G12 唯一呼叫點）皆確認 RED 後乾淨還原，見下 | ✅（彙整 + 3 筆現場覆核） |
| probe 成本 | 100 次 ≤ 5 ms | **依狀態分岔**：`notConnected`（absent，無 realpath 解析）100 次 ≈ 2.6ms（≈26µs/次，貼近 reviewer 當初 ≈17µs 的參考值）；**`connected`（正常運作中的掛載，含 realpath／hookBinaryStamp 的額外 stat）100 次 ≈ 19–27ms（穩態每次 ≈220–350µs），3 次獨立量測一致重現**，約門檻的 4–5 倍。`connected` 才是產品實際大多數時間所在的狀態（正常接上後），也是面板開啟時 `probe()` 真的會被呼叫的那個狀態（§4.1：面板路徑只讀 probe，不 exec，但 probe 本身要跑）——這才是代表性的量測對象 | ❌ 當時超標 —— **門檻已於 2026-09-13 重新推導**（spec §8.1），本列保留當時的量測作為歷史紀錄 |
| 啟動時間增幅 | ≤ 10 ms，行程內量測 | `applicationDidFinishLaunching` 首尾時戳，各 3 輪 × 10 次取中位數：`main` 中位數 0.616／0.595／0.690 ms（均值 ≈0.634ms）；`app-shell` 中位數 0.640／0.712／0.716 ms（均值 ≈0.689ms）。**增幅 ≈ +0.055 ms** | ✅ |
| RSS 增幅 | ≤ 1 MB | `scripts/measure-cpu.sh`（隔離本 session 後量）：`main` 與 `app-shell` 五態 RSS 皆讀 **11M**（`main` 的 done 態讀到 `11+M`，同級），量測解析度看不出差異 | ✅ |
| 動畫態 CPU | 不得比 `main` 更差 | 兩輪獨立量測（12s／20s 取樣）：idle／done／working／waiting 四態 `app-shell` 與 `main` 同級或更低；**`error` 態兩輪方向不一致**——第一輪 app-shell 較差（avg 2.76 vs 2.37、max 4.20 vs 3.20），第二輪（20s，只測 error）app-shell avg 較差但 max 較好（avg 2.54 vs 2.31、max 3.00 vs 3.60）。差距都在個位數百分點內，判讀為 `top` 取樣噪訊而非系統性回歸，但**無法排除真的有小幅變差**，未做第三輪定奪 | ⚠️ 噪訊內，方向不一致 |
| 執行檔 | ≤ +80 KB（bundle 另 + 一顆 universal `aura-hook`，D-g 已知代價） | `Contents/MacOS/AgentAuraApp`：`main` 1,477,936 bytes → `app-shell` 2,242,608 bytes，**+764,672 bytes（+746.75 KB）**，約門檻的 9.3 倍。Bundle 總大小 1,452KB → 3,456KB（+2,004KB），扣掉已知代價的 `plugin/` 目錄（1,244KB，含 universal `aura-hook`）後仍有 **+760KB** 落在執行檔本身，與上述 746.75KB 大致吻合 | ❌ 當時超標 —— **門檻已於 2026-09-13 重新推導**（spec §8.1），本列保留當時的量測作為歷史紀錄 |
| 單檔行數 | `Sources/` ≤ 200、`Tests/` ≤ 300 | `IsolationTests.fileLengthLimit` 綠；手動複查最大檔：`Sources/AgentAuraApp/StatusItemController.swift` 195 行、`Sources/AuraCore/InstallState.swift` 179 行；`Tests/AuraCoreTests/MergeRulesTests.swift` 288 行、`AuraHookCLITests.swift` 288 行 | ✅ |
| `settings.json` 位元組變動 | 0（全程） | `md5` 與位元組數在「`claude plugin validate --strict`」→「`verify-install.sh`（含一次真的 `claude -p` session）」→「多次 app 啟動／關閉（CPU 量測）」全程前後一致：`c8892fce407280198e4a11ab8422b7bf`，1974 bytes | ✅ |
| plugin 契約 | 零 error 零 warning | `claude plugin validate --strict ./plugin` → `✔ Validation passed` | ✅ |
| 安裝鏈路 | PASS | `./scripts/verify-install.sh` 全項 PASS（二進位／註冊／validator／settings.json 零污染／實機 `claude -p` 一輪／狀態檔內容） | ✅ |
| bundle 佈局 | PASS，缺 bundle 時 FAIL 不 skip | `./scripts/verify-app.sh` PASS；**G14 mutation**：`rm -rf build/AgentAura.app/Contents/Resources/plugin` → 12s 內非零退出（`RC=1`），還原後 `build-app.sh` 重建、`verify-app.sh` 再次 PASS | ✅ |
| **實機 ①** 生效時機 | 互動 session 開著時掛上掛載 → 觸發一次 tool → 狀態檔不出現；開新 session → 出現 | 手動 | 待使用者實測 |
| **實機 ②** 下載路徑 | 打包 zip → 下載/解壓（帶 quarantine）→ 開起來 → 按接上 → 要嘛成功且真有狀態檔，要嘛明確報 `.hookBlockedOrBroken` | 手動 | 待使用者實測 |
| **實機 ③** 登入項目 | ad-hoc 簽章 bundle 上 `SMAppService` 的實際行為 | 手動 | 待使用者實測 |
| **實機 ④** 卡死檢查 | exec 驗證失敗 → 依文案處理 → 重開 app → chip 必須離開「接不上」；另測「再檢查一次」 | 手動 | 待使用者實測 |
| persona | 加權 ≥ 6.5；「非工程師能不能自己裝起來」≥ 6 | Tier 1，integrator 綠後派 | 待派 persona-tester |

## 量測方法（唯一新增的暫時測試，已刪除不進交付）

DoD 要求「probe 成本」與「啟動時間」都要**行程內**量測（不是用 `open` 這種行程外量測，雜訊在幾十 ms 量級會蓋掉訊號）。
`Installer.probe()`／`AppDelegate.applicationDidFinishLaunching(_:)` 都已是可從測試直接建構呼叫的注入型別
（`Installer(claudeHome:bundlePluginURL:...)`、`AppDelegate(root:livenessInterval:defaults:installer:makeLoginItem:makeRenderer:)`），
不必碰生產碼，寫了兩個暫時 `T10Temp*Benchmark.swift` 測試（`ContinuousClock` 計時、包 `#expect`/`print`），
`swift test --filter` 跑完立刻 `rm` 掉，`git status`／`git diff` 確認乾淨。`main` 側的等價測試寫在
`git worktree add` 出來的臨時目錄裡，同樣未提交、已隨 `git worktree remove` 一併清除。

## gate mutation 彙整表（15 條 + G14；彙整自 T02–T09 commit，✓現場 = 本輪抽驗重跑）

| Gate | 位置 | Mutation | 指名測試 | 秒數 | 來源 |
|---|---|---|---|---|---|
| G1 | `InstallStateTests` | `hookNotExecutable` 併入 `connected` | 指名斷言 | 1s | T02 (`02027f5`) |
| G1 附：`affordanceMatchesTable` | `InstallAffordanceTests` | affordance 改「r3 列序」`broken(_, owner:)` 排具體 Reason 之前 | `broken(Reason, owner:) 逐格比對` | ~1s | T02；**✓現場**：本輪重跑，24→27 格後仍精準紅 **6 格**（`occupiedByFile`／`occupiedByDirectory` × 三個 owner），還原後乾淨 |
| G2 | `InstallerPathScopeTests` | ① connect 順手寫 `settings.json.bak`；② `ClaudeHomeTreeSnapshot` 拿掉 `realpath(skills)` 那半 | 兩條 G2 測試；外部 symlink 測試 | 0.96s；1.0s | T03 (`5f5a8e1`) |
| G3(a) | `InstallerClobberTests` | ① 拿掉 disconnect 的 `S_IFLNK` 檢查（守 (b)）；② 拿掉第 4 步寫入點型別檢查（守 (a)） | (b) 兩條；`performConnectStepsGuardsWriteTargetDirectly` | 2.5s；2.6s | T03；**✓現場**：本輪重跑②，`performConnectSteps` 直測紅 3 個斷言（1.377s，經 `connect()` 整體呼叫的測試仍綠，證實這是唯一觀測點），還原後乾淨 |
| G4 | `InstallerExecVerificationTests` | 整段拿掉第 6 步 exec 驗證 | 全部 4 條 G4 測試 | 1.5s | T03 |
| G5 | `panelActionsAreWired` | 某 case 改 `break`；只接 `setLaunchAtLogin(true)` | 見任務報告 | — | T08 (`eaac16b`)，未逐筆秒數 |
| G6(a)(b)(c) | `FooterPixelTests`／`RendererPixelTests` | ① chip 色固定綠；② 版本不進 view | 見任務報告 | ≤4s（commit 摘要） | T07 (`0dd3079`) |
| G7 | `optionsExpandGrowsPanel` | `optionsExpanded` 不影響 view | 見任務報告 | — | T07 |
| G8(a)(b)(c) | `connectCTAIsModelDrivenAndVisible` | CTA 在 `connected` 也顯示 | 見任務報告 | — | T06 (`7764d24`)／T07 |
| G9a | `jargonMapsEveryKnownCode` | `effort()` 直接回傳 raw | G9a 指名斷言 | — | T05 (`e217d5e`) |
| G9b | `fixtureCodesAreAllMapped` | `permissionModeMap` 拿掉 `auto` | G9b 指名斷言 | — | T05 |
| G9c | `metaNeverEchoesKnownCode` | `meta` 改回不套 `Jargon` | G9c 指名斷言 | — | T05 |
| G10 | `optionsRowsCoverEveryAction` | ① rows 拿掉「離開」；② `resetColors` 搬家漏接；③ `quit` 塞進 `nonMenuKinds` | 見任務報告 | — | T06 |
| G11 | `healthTonesDontCollideWithPixelFixtures` | warn 改成與 wild waiting 相差 < 0.063 的黃 | 見任務報告 | — | T07 |
| G12 | `acknowledgeAllHasExactlyOneCallSite` | disconnect 加回 `.acknowledgeAll()` | 恰 1 命中斷言 | — | T08；**✓現場**：`disconnect` 路徑因 `graph` 是 `private var`（僅 `AppDelegate.swift` 可見）**無法編譯**加入該呼叫——多一層護欄是巧合的好消息。改在 `AppDelegate.swift` 內（`graph` 可見處）加第二個呼叫點，本輪重跑：2 命中 → 紅（<0.01s），還原後乾淨、恰 1 命中 |
| G13 | `panelModelMakeHasNoDefaults` | 給 `install` 一個預設值 | 來源掃描斷言 | — | T06 |
| G14 | `verify-app.sh` | 拿掉 `build-app.sh` 的複製步驟 | script 非零退出 | 12s（T09 原記）；**✓現場**：本輪重跑 `rm -rf .../Resources/plugin` → 12s 內 `RC=1`，還原後 `verify-app.sh` 再 PASS | T09 (`94aed7b`)；本輪覆核 |

**誠實缺口**：G5／G6/G7/G8/G10/G11 的逐筆精確秒數只留在各 task 的 commit 摘要式描述裡（「見任務報告」／統稱「N 筆皆變紅」），
沒有像 G1–G4、G9、G12、G14 那樣的獨立可回溯時間戳。這些 task 的完成報告（若曾以檔案存在）本輪找不到路徑
（`.superpowers/sdd/` 下無 `app-shell` 子目錄），只能以 commit message 為準。抽驗涵蓋了最關鍵的三類
（affordance 路由回歸、TOCTOU 寫入護欄、唯一呼叫點來源掃描），三筆現場複現皆為真陽性，
但**不代表另外 12 筆逐一驗證過**——若要 100% 覆核需要重跑全部 20 筆，這超出本輪「抽驗 3 筆」的授權範圍。

## Known gaps（spec §9 沿用 9 條 ＋ 本輪新增 3 條）

沿用 spec §9 1–9 條（通用死 hook 掃描本輪不做、`SMAppService` 待實機、Mach-O 位置非 Apple 建議、
quarantine 遞迴清除未驗證、系統通知刻意不做、右鍵 Options 未做、S1-A 全表 acknowledge 沿用、
TOCTOU 真實視窗無法測、`InstallerFailure` 命名衝突），不重複列出，逐字見 spec r7 §9。

| # | 內容 | 性質 | 落點 |
|---|---|---|---|
| T10-1 | **`probe()` 在 `connected` 狀態下的成本比 DoD 參考值（17µs）高一個數量級**（實測穩態 ≈220–350µs/次，100 次落在 19–27ms，超門檻 4–5 倍）；`notConnected` 狀態則與參考值吻合 | 效能 DoD miss | 待查：`hookBinaryStamp`／`thisAppPluginIdentity` 是否有可省的重複 `stat`／`realpath`；下一個 change 或效能 spike 處理，不在本輪修 |
| T10-2 | **執行檔本體（不含 bundle 內 `plugin/`）增量 +746.75KB，超門檻 9.3 倍**——與 panel-legend-palette 的 +292KB miss 同源（SwiftUI 新 view 型別的 release 展開成本），本 change 新增 `PanelFooterView`／`OptionsSectionView`／`NotConnectedView`／`BannerView`／`ConnectCTABannerView` 五個 view，外加 `Security` framework 的 `@_silgen_name` 綁定與 `SMAppService` 連結 | DoD miss，判定不調門檻 | 沿用上一輪建議：(a) 面板改回純 AppKit（代價大）；(b) 門檻改成「每新增 SwiftUI view ≤ 60–80KB/arch」這種有平台依據的數字，留給使用者裁決 |
| T10-3 | 20 次連跑中出現 1 次紅（2 issues），因量測疏失沒能存下具體測試名；後續 17 次全綠、未能重現 | 量測缺口，非已確認回歸 | 若要坐實「連跑 3 次 0 flake」的字面門檻，需要使用者或下次 agent 再多跑幾十次、每次都存全量 log，抓到後再指名 |

## Phase 2（UI/UX 完整化）追加量測 —— 2026-09-11

使用者定的 phase 2 目標：底層／機器面暫時不動，把 UI/UX 與「兩個成熟 app 該有的功能」做完＋測完。

| 項目 | T10 收工時 | phase 2 收工時 | 備註 |
|---|---|---|---|
| 測試數／suite | 466／77 | **544／94** | +78 條，全部有 gate ＋ mutation |
| `#expect` | ~1050 | **1180** | 只增不減（每個 task 逐檔核對） |
| 全量連跑 | 17/20 | **多輪；唯一紅是既有 flake** | 見下 |
| 已知 flake | `acknowledgeDeletesFiles` 3/20（15%） | 同一條，**7–25%**（各 agent 報 1/14、2/8、2/8） | Change 2 就在待辦、`main` 上本來就有；屬 FSEvents 底層，依「底層暫時不動」保持 known gap |
| 新增負載型 flake | — | **0** | T10b 的三個處置（可注入逾時／跨 suite `SpawnGate`／相對比值取代絕對時間）之後沒再出現 |

### A 波（persona NO-GO 的 8 條 ＋ 我從它的截圖另抓 3 條 ＋ 1 條 S2）

| # | 項目 | gate | 修前基準 → 修後 |
|---|---|---|---|
| A1 | **S0** 主 CTA 不像按鈕 | `CTAAffordanceRenderTests` | 填色像素 0 → 660；對比 4.00:1 → **5.62:1** |
| A2 | **S0** tooltip／標題說謊 | `TooltipAndTitleConsistencyTests`（窮盡 `InstallState`） | 「還沒接上 Claude Code」repo 0 命中 → 每種狀態各有專屬字串 |
| A3 | `explainOnly` 無說明文字 | 定義域**從 `affordance` 推導** | 手寫清單第一版被自己的新測試否證 |
| A4 | accordion 誤觸 | rows 第一列不得為 toggle | — |
| A5 | `.banner` CTA 無副標／換掛載無確認框 | confirm gate | — |
| A6 | 術語三個名字 | 來源掃描（help.html ＋ app 層） | 捷徑／連結 → 一律「掛載」 |
| A7 | banner 無生命週期、✕ 10pt | model 層自動退場 | ✕ 命中區 10 → **20pt** |
| A8 | 「重設」在圖例列與 Options 重複 | `LegendRowView` 不得出現 `.resetColors` | — |
| A9 | 開機自動啟動看不到狀態 | `OptionsToggleStateRenderTests` | on/off 兩張圖差 **0 px → 461 px** |
| A10 | Options 列高 | 高度上限（**C2 後改推導**） | 405pt → 357pt |
| A11 | 標題與本體撞字 | 三者（標題／本體／tooltip）互不相同 | — |
| S2 | chip 雙層括號 | 既有兩條窮盡 gate 的 oracle | `已接上（未驗證）（你的 repo 掛載）` → `已接上 · 你的 repo 掛載 · 未驗證` |

### B 波（成熟 app 該有而我們還缺的）＋ C 收尾

| # | 項目 | gate | 備註 |
|---|---|---|---|
| B1 | 右鍵開 Options | `RightClickOpensOptionsTests` | 左鍵行為不變、footer 主入口保留 |
| B2 | 「回報問題…」 | G5 的 `.reportIssue` | 走既有注入 opener |
| B3 | **⌘Q 真的能用** | `QuitKeyMonitorTests` | 原本字樣印在列上但**零接線**——與 tooltip 說謊同族 |
| B4 | 「關於」有實際內容 | `AboutContentTests` | 版本＋專案連結＋誠實寫「授權：尚未決定」 |
| B5 | 「減少動態」開關 | `ReduceMotionTests` ＋ `OptionsMenuModelTests` | 與系統設定取 **OR**；系統強制時該列 disabled ＋ 說明 |
| C1 | 分隔線只在群組交界 | `OptionsDividerGroupingPixelTests` ＋ rows 依 group 連續 | 九列每列一條 → 五群四條 |
| C2 | 高度門檻改推導 | `heightCeiling(forRowCount:) = 列數×30+160` | 不再是魔術數字；某列變胖 → 603pt vs 460pt 門檻，紅 |

**明確不做並記理由**：重設全部設定（只有兩個設定，已有重設顏色）· 統計／歷史／成本（刻意不存歷史）·
系統通知（把產品從餘光可見變成主動打擾，撞 R4，需自己的 brainstorm）· 熱鍵（唯讀無動作可觸發）。

**證據圖**：`docs/evidence/phase2/` 共 43 個檔（A1–A11／B1·B2·B4／B5 兩態／C1 前後，多為 light/dark 各一）。

### 兩項 T10 的 DoD miss 現況

| 項目 | 門檻 | 現況 | 判斷 |
|---|---|---|---|
| probe 成本 | **單次 ≤ 0.5 ms**（2026-09-13 重新推導） | **0.07 ms／次** | ✅ **通過**。舊門檻量錯對象：生產路徑不存在「連續 100 次 probe」。裁決理由見 spec §8.1 |
| app bundle 總量 | **≤ 6 MB**（2026-09-13 重新推導） | **3.8 MB** | ✅ **通過**。舊的 `+80 KB` 沒有平台依據、會被正常工作穩定超過 14 倍。裁決理由與代價見 spec §8.1 |

### persona 重測（Tier 1）與 T13 收尾

| 輪 | 加權 | 門檻 | S0 | 判定 |
|---|---|---|---|---|
| r1（修之前） | 6.30 | 6.5 | 2 | **NO-GO** |
| r2（A/B/C 波之後） | **7.55** | 6.5 | **0** | **GO** |

各項（r1 → r2）：P1 非工程師 6.0 → **7.5**（w .5）· P2 重度 7.0 → **8.0**（w .3）· P3 夜間 6.0 → **7.0**（w .2）；
「非工程師能不能自己裝起來」6 → **7**（過門檻）· 四種原因分得開 6 → **8** ·
Options 可發現性 7 → **8** · 文案 6 → **7** · **誠實性 6 → 8.5**（進步最大——tooltip 說謊、
banner 不退場、`⌘Q` 假字樣三個「宣稱它無法保證的事」同時關掉）。

**r2 順帶更正了 r1 自己的一條量測**（重要，因為它會誤導修復方向）：離屏渲染在沒有 key window 時，
**所有 `.borderless` 的 label 一律拿到系統次要前景色**。所以 r1 說的「圖例 19:1 vs CTA 4.00:1、
差別在 initializer」是 harness 產物；A1 之所以有效是因為 `CTAButtonStyle` 把白色**寫死**
——那是唯一 harness-independent 的顏色結論。**任何文字顏色的判斷都必須在真 app 上做**，
本輪因此一律不動字色（已寫進 CLAUDE.md gate 哲學第 5 條的同一族教訓）。

r2 的 4 條新 S1 ＋ 2 條 PARTIAL 由 **T13** 收掉（`2018870`／`1c09c77`）：

| # | 項目 | 修法 | gate ／ mutation |
|---|---|---|---|
| S1-1 | 同一句 healthLabel 在每個非 connected 面板印**三次**，而真正的處方只在按下「接上」失敗**之後**才出現 | 本體去重（單一 oracle `notConnectedDetailText`）＋ `explanationDetail` 放寬到全部 broken reason | 來源掃描 2.5s 紅；窮盡斷言 15 issues／2.8s 紅 |
| S1-2 | 「說明與快速上手…」承諾了 `help.html` 沒有的章節（快速上手／減少動態／回報問題／關於／⌘Q **全部 0 命中**） | 補章節 ＋ **清單從 `OptionsMenuModel` 的 rows 推導**的覆蓋 gate | 2.3s 紅 |
| S1-3 | 「系統設定已開啟」中文讀成「系統設定（那個 App）已經被打開了」 | 改「已在系統設定開啟」 | 2.3s 紅 |
| S1-4 | 術語殘留兩處（`INSTALL.md` 的「捷徑」、`InstallAffordance` 的「連結解不開」）；A6 的掃描沒蓋到這兩個檔 | 統一「掛載」＋**掃描範圍補上** `docs/INSTALL.md` 與 `Sources/AuraCore/` | 兩處各 2.3s 紅 |
| S1-4' | 「減少動態」把 spec 自己寫的「不必辨色也能區分」拿掉（waiting／error 亮度只差 **1.66:1**）——非迴歸，但變成一顆**沒有提示的勾選框** | 用**既有的 `subtitle` 欄位**補可及性提醒（不動動畫曲線） | 2.3s 紅 |
| S1-5 | 背景驗證**成功之後**舊的錯誤 banner 還留著 | `.verified` 時清 error banner（沿用 A7 的退場機制） | 5.1s 紅 |
| — | `Info.plist` 缺 `NSHumanReadableCopyright`（關於面板沒有版權行） | 補鍵 | 0.7s 紅 |

T13 的一個判斷我接受並記在此：`explanationDetail` 的 7 個 broken reason 裡，只有
`hookBlockedOrBroken`／`hookUnconfirmed` 沿用既有的處方字串；其餘 5 個「按接上就會重建修好」的
結構性 reason **共用一句事實陳述**，而不是硬編 5 句客製文案——機制完全相同時共用一句更誠實，
逐句客製反而增加寫錯的風險。

**最終數字**：556 tests / 98 suites 全綠 · `#expect` 淨 +19 call site · 證據圖 47 個檔。

### 實機測試期間的修正（T14–T19，2026-09-11）

使用者實際用起來之後回報的四件，都是離屏渲染驗不到、只有真 app 看得到的：

| # | 回報 | 根因 | 修法 ／ gate |
|---|---|---|---|
| T14–T15 | 「畫面還是很醜」 | **沒有人定過視覺目標**——一直在「批評→補丁」不是「設計→實作」 | 三個方向的真渲圖 A/B（沿用 M4 的方法）→ 使用者選 **V1 macOS 原生感**整包 → 落地、另兩個原型評後刪。同時修掉我看圖抓到的三個毛病（圖示欄留空格／session 卡片擠成一團／資料沒壓過設定） |
| T16 | 「底板有點跑版」 | **spec 自己的算術錯誤**：§4.1 寫「8×3+7×2 = 34」，實際是 **38** ⇒ 左邊距 4pt、**右邊距 0pt**。而 `statusItemWidthFollowsRenderer` 在 T09 退化成「等於固定值 50／42」，**把 bug 凍在原地** | 寬度改從 `ledSpan + plateInset×2` 推導（44pt，四邊各 3pt）＋ 新增**對稱性 gate**（左＝右＝上＝下）＋ 把那條 gate 改回 derived。mutation 寫死回 42 → 4 筆斷言 < 0.1s 全紅 |
| T16 | 「讓使用者決定要不要底板」 | — | `AgentAuraIconPlate`（預設**開**，M4 是用證據選的 A2）＋ Options 設定群一列，關閉時寬度與 LED 位置不變（圖示不跳動） |
| T17→T18 | 「挑色盤預設在左下角」→ 改了之後「**被面板完全擋住**」 | T17 我把它放在「錨點正下方」——**面板本來就掛在那裡**，而 `NSPopover` 的視窗層級在一般面板之上 | 不跟 z-order 打架，改成**不重疊**：放面板旁邊、上緣對齊、優先左側。`iconScreenFrame` → `avoidScreenFrame`（面板已顯示就回面板的 frame）。gate `plannedFrameAvoidsThePanel` 直接斷言 `!frame.intersects(panel)` |
| T19 | 「白色其實比較好，設成預設」 | — | 見下 |

### T19：working 預設色改白，以及它推翻的一條設計代理指標

使用者自己把 working 拖成白色之後說：「不搶眼，但是我特意去看它的話，其實看得出來它就是安靜的」。
量測支持他（WCAG 對比，sRGB）：

| working | 底板上 | 深色選單列（底板關） | 淺色選單列（底板關） | 面板白卡片上的色點 |
|---|---|---|---|---|
| 藍 `#0a84ff`（舊預設） | 5.04:1 | 4.66:1 | 3.27:1 | 3.65:1 |
| **白 `#ffffff`** | **18.40:1** | **17.01:1** | 1.12:1 ⚠️ | 1.00:1 ⚠️ |

所以白色**不能只改一個常數**，配套兩件：
1. **面板色點加細邊**（`DotRing`）——否則淺色模式下白點在白卡片上完全消失（1.00:1）。
   gate 用「有邊線 vs 無邊線」差異渲染，mutation 拿掉邊線必紅。
2. **底板預設維持「開」**（出廠就是 18.40:1 那一格）＋ 底板關且顏色在淺色選單列上對比過低時，
   用既有的 subtitle 機制顯示一行提醒（`ContrastCheck`，參照背景取**純白＝最壞情況**）。

**它推翻了一條守了很久的代理指標**：`RendererPixelTests.workingIsQuietestColor` 斷言
「working 對底板的亮度對比**最低**」。白色之後數學上不可能成立（18.40 vs error 5.40）。
裁決：**錯的是量法不是設計承諾**——R4 要的是「不搶注意力」，而在用顏色警示的系統裡，
搶眼來自**色度**不是亮度（紅橘是**有色**警示，白是**無彩**的）。改成
`workingIsQuietestByMotionAndChroma`：動態半邊不變，顏色半邊斷言 **working 的色度在 `.default`
四色中最低**。實測 working 0.0000（理論最小）／done 0.6314／error 0.7725／waiting 0.9608；
mutation 改回飽和藍 → 三條斷言全紅。

> 留給以後的一句：**量錯的東西守了很久也還是量錯。** 代理指標要定期回頭問「它代理的是什麼」。

**最終數字**：578 tests / 105 suites 全綠 · 證據圖 `docs/evidence/phase2/`（含 T13／T16／T19）
＋ `docs/evidence/design-ab/`（三方向 12 張 ＋ V1 落地對照）。

## 使用者實機清單（離屏不可驗的四件事；spec §8）

| # | 操作 | 預期 | 實際（請填） |
|---|---|---|---|
| ① | 互動 session 開著時掛上掛載 → 觸發一次 tool call → 檢查 `~/.agentaura/sessions/` 狀態檔**不**出現；開一個新的 Claude Code session 後再觸發一次 → 出現 | 生效時機符合「下一個 session 起生效」的文案（D-m） | |
| ② | 把 `AgentAura.app` 打包成 zip → 下載/解壓（帶 quarantine，例如透過瀏覽器或 AirDrop）→ 開起來 → 按「接上」 | 要嘛成功且 `~/.agentaura/sessions/` 真有狀態檔可觀察，要嘛 chip 明確顯示「接不上：macOS 擋住了 hook」，**不得**顯示「已接上」卻永遠沒有狀態檔 | |
| ③ | Options 展開 → 開「開機自動啟動」開關 | 記錄 ad-hoc 簽章 bundle 上 `SMAppService` 的實際行為：成功／`.requiresApproval` 指引系統設定／其他錯誤 | ✅ **通過**（2026-09-12）：**ad-hoc 簽章 bundle 上直接成功**，開關切到「開」並維持，沒有 `.requiresApproval`、沒有錯誤。spec §9 第 2 條的未知數就此解除 |
| ④ | 讓 exec 驗證失敗（例如手動對 `bin/aura-hook` 加回 `xattr -w com.apple.quarantine ...`）→ 依 chip 文案處理 → **重開 app** → 檢查 chip 是否離開「接不上」；另測「再檢查一次」按鈕 | app 叫使用者做的事做完之後，chip 不得繼續卡在舊的錯誤文案 | |

### Phase 2 追加（⑤–⑩，全部是離屏渲染驗不到的互動）

| # | 操作 | 預期 | 實際（請填） |
|---|---|---|---|
| ⑤ | **刪掉 `AgentAuraDidConnectOnce`**（`defaults delete io.agentaura.app AgentAuraDidConnectOnce`）→ 重開 app | 面板**自動打開一次**。persona 兩輪都指這條風險最高：`showPanel()` 在 `applicationDidFinishLaunching` 尾端、離屏不可驗，**不彈的話 P1 的整個入口就消失了** | |
| ⑥ | **右鍵**點選單列圖示 | 面板打開且 Options **已展開**；左鍵仍是原本行為（開面板、Options 收合） | ⚠️ **首次回報不通過，但重現不出來**（2026-09-12）。真機診斷建置量了三輪全部正常：事件原始值恆為 4（`.rightMouseUp`）· 命中 view 是 `LEDStripView`（LED 自訂 view **不吃**右鍵）· 點文字與點燈點結果一致 · `onRightClick` 每次觸發、使用者確認面板展開。順帶推翻一個假設：換 rootView 後 `preferredContentSize` **立刻**更新（250→542pt，不需 layout pass），所以「用舊尺寸顯示、展開區被裁掉」不成立。<br>**追查的真正產出**是補了 `RightClickSendActionGuardTests`：`sendAction(on:)` 的遮罩 AppKit 沒有 getter，離屏斷言不到，拿掉它右鍵會**安靜地**停止抵達 action 而全部測試照樣綠。改問原始碼，mutation 0.001s 紅。<br>狀態改列**觀察中**——若再次出現請記下當下面板是開是關 |
| ⑦ | 面板打開時按 **⌘Q** | App 真的離開（這個字樣在 phase 2 之前是假的）。另確認：**面板關閉後**按 ⌘Q 不應該再被我們攔截（monitor 要在關閉時移除，否則會攔到全 app 的鍵盤事件） | ✅ **通過**（2026-09-12，面板開啟時 ⌘Q 真的離開，無異狀） |
| ⑧ | Options → **減少動態**。系統「減少動態」關閉時切開 → 看燈；再去系統設定打開「減少動態」→ 回來看那一列 | 使用者自開 → 動畫停止；系統強制時該列**鎖住並顯示「系統設定已開啟」**（不得出現「開關說關、動畫卻不動」） | ✅ **使用者自開該半通過**（2026-09-12，動畫確實停止）。系統強制那半未測（需要去系統設定切換），留待下次 |
| ⑨ | Options → **回報問題…** 與 **關於 AgentAura** | 前者開 GitHub issues；後者顯示版本＋可點的專案連結＋「授權：尚未決定」 | ✅ **通過**（2026-09-12，兩項都正常） |
| ⑩ | Options 展開後**滑鼠不要移動、直接再點一下** | 不得誤觸任何會改變狀態的控制項 | ✅ **通過**（2026-09-12 二測，T22 修復後）：遊標仍停在「Options ⌃」那一列，再點一下正常收合。**連動畫進行中點擊也通過**——實作者事先誠實標記「畫布被提案比兩邊自然高度都小時 `NSHostingView` 會置中塞入、SwiftUI 層覆寫不掉」的那個邊界，實機上沒有造成可見問題。<br>一測時的現象與根因見下方 T22 紀錄；A4 原本的假設（遊標落在展開區第一列）本身就是錯的 |

### T20 追加（⑪–⑬，色板重疊二修與面板自主 dismiss；commit `8c09e7d`）

離屏渲染下 `popover.isShown` 恆 false、真實視窗編號全是 nil，所以「判定該關 → 真的關」這條
端到端行為**完全無法**在 `swift test` 內斷言。三點都只能實機看。
測試前我已把使用者回報的壞座標寫回 `defaults`（`NSWindow Frame AgentAuraColorPanel` =
`1138 832 250 298 0 0 1800 1130`），所以 ⑪ 走的就是修復路徑而不是全新路徑。

| # | 操作 | 預期 | 實際（請填） |
|---|---|---|---|
| ⑪ | 開面板 → 點任一圖例色點開色板 | 色板出現在面板**旁邊**、不與面板重疊（存檔位置若擋住面板就重新擺位；不擋住則尊重使用者搬過的位置） | ✅ **通過**（2026-09-12，從舊的重疊存檔座標 `1138 832` 出發，走的是重新擺位路徑） |
| ⑫ | 改色期間**拖曳色板**、點色板內部 | 面板**不**收起 | ✅ **通過**（2026-09-12，拖曳與點內部皆不關，調色即時反映） |
| ⑬ | 改色期間點桌面／其他視窗 | 面板**收起**，且色板一併結束；另確認點選單列圖示不會「閃一下又彈開」 | ✅ **通過**（2026-09-12 二測，T21 修復後）：面板收起，**系統色板也跟著關掉**，不再留下孤兒視窗。一測時面板會收但色板留著 |

## 實機 ① ② ④ ⑤：改列 known gap（2026-09-13 裁決）

這四條測的都是**全新安裝的第一次體驗**。目前唯一的測試機器是一台永久掛著開發者 symlink
的開發機，四條都必須先把那個掛載拆掉或把 hook 弄壞才測得到——實際嘗試 ① 的時候就把
使用者的選單列打停了一分半（已復原，狀態檔凍在 19:54:56、復原後 21:49:04 恢復寫入）。

**價值判斷**：它們守的是「非工程師能不能自己裝起來」，那正是 phase 2 的核心目的，所以
不是不重要；但它們守的是**別人的**第一次，不是這台機器的日常。在乾淨環境出現之前，
把開發機拆掉重裝一輪的風險大於得到的資訊。

**觸發條件（下次滿足任一就跑）**：有第二台機器或乾淨使用者帳號可用 · 有人回報安裝失敗 ·
準備對外發佈（那時 ② 的 quarantine 路徑是強 gate，不可繞）。

| # | 未測的部分 | 已知的部分 |
|---|---|---|
| ① | 「掛載裝回去之後，**新** session 才出現狀態檔」這一半 | **另一半已實測**（2026-09-13）：掛載一移走，既有 session 的 hook 立刻停止寫入；裝回去後恢復。這證明 hook 路徑是**執行當下**才解析的。因此「下一個 session 起生效」這句文案成立的機制**不是**路徑解析，而是「session 啟動時才讀 hooks 設定、沒讀到就整個不註冊」——文案剛好站在後者上，所以文案是對的 |
| ② | 帶 quarantine 的下載路徑 | 對應的失敗模式已有單元覆蓋（`connectThrowsBlockedWhenBinaryProducesNoArtifact`），未驗的是真實 Gatekeeper 行為 |
| ④ | 卡死檢查（弄壞 hook → 依文案處理 → 重開 app → chip 必須離開錯誤態） | 「再檢查一次」按鈕的接線有 gate；未驗的是真實 quarantine 復原後的狀態轉換 |
| ⑤ | 首啟自動開面板 | 條件是 `!didConnectOnce && !isConnected`。這台機器**永遠是 connected**，所以光刪 defaults 鍵不會觸發，必須先拆掛載。persona 兩輪都說這條風險最高 |

**另一項平台事實（本輪實測）**：`FileManager.homeDirectoryForCurrentUser` **不吃 `$HOME`**
（它讀密碼資料庫），所以無法用假家目錄開一個隔離實例來測這四條。要做到隔離必須在
`Installer` 開一個注入點，那是給測試開的後門，目前不值得。

## 附：main baseline 量測環境

`git worktree add <scratch>/main-baseline main --detach`（`39984eb`）→ 乾淨副本上先跑
`./scripts/build-plugin.sh`（否則 `InstallLayoutTests` 3 條因缺 `plugin/bin/aura-hook` 而紅，
即 CLAUDE.md 記錄的「乾淨 clone 陷阱」，本輪親自踩中一次並確認是已知模式非新問題）→
`swift test`（293/37 全綠）→ `./scripts/build-app.sh`（無 D-g 複製步驟，符合「改動前」基準）→
臨時複製 `measure-cpu.sh`／新增 `T10TempStartupBenchmark.swift` 跑完即棄，`git worktree remove --force` 收尾。
