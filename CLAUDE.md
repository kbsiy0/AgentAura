# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

把 Claude Code 的運行狀態顯示在 macOS 選單列。plugin hook → 狀態檔 → FSEvents → 一顆聚合燈 + 面板。

> **狀態（2026-09-10）：M0–M5 完成；M4 形態決策完成選定 A2**（決策見 `docs/2026-09-09-m4-ab-decision.md`）；
> **Change 2 `panel-legend-palette`**（面板常駐圖例列、點色點改色、四色持久化）完成並通過 2026-09-10 實機驗收
> （DoD 帳本 `docs/superpowers/plans/2026-09-09-panel-legend-palette-dod.md` 的實測表）；驗收 ⑥ 證實 S1-3 為 S0，
> 已在 `change/ack-on-close` 修（acknowledge 改到面板關閉）。
> 下一步：A2-light 微調（淺色底板過重，F-02）、動畫態 CPU。
> PR／branch 的 merge 狀態屬易腐事實，**不記本檔**，用 `gh pr list --state all` 現場查。
> 重啟指標：`docs/superpowers/specs/2026-09-08-agentaura-design.md` §8 里程碑表。

## Tech Stack

Swift 6（`swift-tools-version: 6.0`，strict concurrency）· macOS 13+ · SwiftPM · **swift-testing（`import Testing` / `@Test` / `#expect`，不是 XCTest）** · FSEvents · `flock(2)` · `sysctl(KERN_PROC_PID)`。零第三方依賴。

## 結構

```
Sources/
  AuraCore/         純邏輯，零 AppKit/SwiftUI 依賴（由編譯器 gate 強制）
  AuraHookFile/     flock 讀寫、FSEvents、PipelineGraph（composition root）
  aura-hook/        被 hook 呼叫的 CLI，一律 exit 0
  AgentAuraApp/     AppKit：選單列、動畫、面板（`IconDrawing` 為 view 契約 protocol）
Tests/AuraCoreTests/
  Gate.swift            ★ 跨層 gate 的共用機制（問編譯器、問 dump-package）
  IsolationTests.swift  ★ module 白名單基準 + 行數上限
  PluginWiringTests.swift ★ plugin 設定 vs 平台契約
  EndToEndWiredGateTests.swift ★ 真的 spawn aura-hook，不 mock 任何一層
  Fixtures/*.ndjson     ★ 真實 hook payload，唯讀證據
Tests/AgentAuraAppTests/  composition-root smoke（spec §5.2）
plugin/                 Claude Code plugin（bin/ 是建置產物，gitignored）
docs/superpowers/specs/2026-09-08-agentaura-design.md  ★ 正典設計，衝突以它為準
docs/INSTALL.md         ★ 安裝／移除／疑難排解
Resources/help.html     ★ bundle 內離線說明（D-l，隨 build-app.sh 複製進 app）
scripts/                build-plugin · build-app · verify-install · verify-app · measure-cpu
```

## Commands

```bash
swift test                                   # 全量
swift test --filter <測試函式名>              # 單一測試（不是檔名，是函式名）
swift build --build-tests                    # 只編不跑
./scripts/build-plugin.sh                    # universal aura-hook → plugin/bin/
./scripts/build-app.sh                       # → build/AgentAura.app
./scripts/verify-install.sh                  # 實機驗收（會跑一個真的 claude -p session）
claude plugin validate --strict ./plugin     # 平台契約，warning 視為 error
```

**陷阱（都實際踩過）：**
- **乾淨 clone 先跑 `./scripts/build-plugin.sh`** —— `plugin/bin/aura-hook` 是建置產物且 gitignored，沒建就有 3 條 `InstallLayoutTests` 是紅的。
- **不要同時開多個 `swift test`** —— 搶 `.build` 的鎖，看起來像掛住。
- **只殺 `swift test` 父行程會留下 `swiftpm-testing-helper` 殭屍鎖住 `.build`**，之後每次跑都停在鎖上。清法：`pkill -9 -f swiftpm-testing-helper`。
- **macOS 沒有 `timeout` 命令**（那是 GNU coreutils）。要有界執行自己寫 `cmd & pid=$!; (sleep N; kill -9 $pid) & wait $pid`。
- **`swift package dump-package` 從 `swift test` 的子行程跑會死結** —— `swift test` 持有 package lock。必須加 `--scratch-path <temp>`（`Gate.packageTargets()` 已處理）。
- **中文 commit message 用 `git commit -F - <<'EOF'`**，不要 `-m` —— zsh 的 history expansion 會吃掉 `!`。

## Invariants

格式：禁令（出處 —— 根因）。

- **絕不修改 `~/.claude/settings.json`**（D3/R6 —— 安裝走 `~/.claude/skills/agentaura` symlink；`claude plugin marketplace add` 會寫 `extraKnownMarketplaces`，那條路已從計畫移除）。`verify-install.sh` 掃**整個**檔案而不只 `hooks` 鍵。
- **`waiting` 不得進入「已結束但未確認」的尾巴**（spec §2.4.1 / `e90931c` —— 實測按 Deny 不產生任何 hook 事件，否則早已回答過的 session 會讓 icon 一直亮橘燈）。
- **`Notification(idle_prompt)` 不得映射到 `waiting`**（spec §2.2.1 / `IdlePromptTests` —— 一輪結束 60s 後 Claude Code 必送它；歸 waiting 等於每個講完話的 session 都亮橘、terminal 收掉後結果消失、聚合被拖成橘）。
- **acknowledge 只在面板關閉（`NSPopover.didClose`），開啟路徑不得 acknowledge**（spec §3.7 / `acknowledgeFiresOnCloseNotOpen` —— 舊順序先 acknowledge 再 `show`，已結束的 done/error 列在面板畫出前就被移出 registry，§2.4 的尾巴形同不存在；2026-09-10 實測證實）。
- **主／副槽分開，activity 取優先序 max；主槽靜止時完全忽略 subagent 事件**（spec §2.5 / §2.5.1 / `efccc03` —— subagent 與父 session 共用 `session_id`，實測最密相鄰 20ms）。
- **`aura-hook` 一律 `exit 0`，stdout / stderr 一律空**（觀測性絕不可干擾 agent。代價：exit code 無法用來驗收，所以驗收必須看產物）。
- **解析失敗 ≠ 檔案不存在**（spec §3.3 / §4 第 3 列 / `dae435d` —— 損壞檔要保留上次已知狀態並重試；只有檔案真的消失才移除 session）。
- **`PipelineGraph.registry` 是 `internal` 且未加鎖，對外只走上鎖的 `visibleSessions`**（`7f9d7b8` —— `onIconStateChange` 從 FSEvents 背景 queue 上來）。
- **`Sources/AuraCore/` 不得載入 Foundation 閉包以外的任何 module**（`58ea4b5` —— 白名單基準而非黑名單；黑名單漏掉 `CoreImage` 這類框架）。
- **單檔上限：`Sources/` 200 行、`Tests/` 300 行**（`IsolationTests.fileLengthLimit` 從磁碟推導，新增 module 不會漏網）。
- **`Installer` 只准碰 `<claudeHome>/skills/agentaura`（必要時加 `<claudeHome>/skills/`）這兩個路徑，判定一律以 `realpath` 解析後的位置為準；其餘 `~/.claude/` 唯讀；`~/.claude` 不存在時拒絕接上、不得建立它**（spec D-h —— `skills` 自己可能是指到別處的 symlink，用未解析的字串判定會誤殺合法的同步設定；gate `installerTouchesOnlyAllowedPaths`）。

## 這個 codebase 的 gate 哲學

改動任何 gate 前先讀 `docs/2026-09-09-agentaura-audit.html`（八族「空轉的守衛」實證案例）。三條規則：

1. **平台契約要問平台** —— 問編譯器（module trace）、問 `claude plugin validate --strict`、問 `swift package dump-package`。不要在它們外面再包一層自己的近似。
2. **「涵蓋每一個 X」必須從型別／磁碟推導**，不能只寫在 doc-comment 裡（既有做法：`Mirror` 掃 stored property、`swiftFiles(under:)` 掃磁碟）。**同族教訓（T16）**：數字也必須推導，寫死的數字會凍住錯誤——`LEDStripView.preferredWidth` 曾是 `8×3+7×2=34` 這個算術錯誤硬寫死成 42（正確是 38+3×2=44），`statusItemWidthFollowsRenderer` 又退化成「跟 `drawing.preferredWidth` 比對自己」，兩層一起把錯的數字凍住直到使用者實測才發現（見 spec §4.1 T16 一列、`LEDPlateSymmetryTests`）。
3. **每個 gate 都要有 mutation 紀錄** —— 把生產碼改壞，指名的測試必須**在指定秒數內**變紅（不是掛住）。mutation 用完整字串取代、且先確認編譯成功再看測試結果。
4. **離屏渲染裡的 SwiftUI／AppKit 橋接有兩個平台限制，會咬到任何新加的按鈕（T07 實測）**：
   - `.bordered`／`.borderedProminent` 在離屏渲染下把真正的 `NSButton` 包進 `_FocusRingView`，
     **沒有真 `NSWindow` 時該容器的 `subviews` 是空的**——遞迴走訪找不到、`performClick` 打不到。
     要能從測試觸發的按鈕**必須用 `.borderless`**（`LegendRowView`／`NotConnectedView`／
     `ConnectCTABannerView` 都因此改過或一開始就用它）。
   - 離屏渲染下 SwiftUI 橋接出的 `NSButton` **讀不到 `.title` 也讀不到 `.accessibilityIdentifier`**
     （連 `Button("重設"){}` 也一樣，實測皆為空）——測試定位按鈕只能用**位置索引**（`allButtons`
     深度優先走 `subviews`，與宣告順序一致），而位置索引會被「新增按鈕」擠掉，所以新增按鈕時
     要一併檢查既有索引斷言（例：`PanelPixelTests.panelViewForwardsAction` 加 `ConnectCTABannerView`
     的按鈕就會多推一位）。
5. **量時間的 gate 會被測試套件自己的負載打敗（phase 2 實測，代價是三次來回）**：
   swift-testing 預設**跨 suite 並行**，`.serialized` 只序列化 suite **內部**。所以只要套件裡
   真的 spawn 行程的測試變多，任何「絕對毫秒數」的斷言都會開始說謊——實測撞穿的有三條：
   `Installer` 的 2 秒 exec 逾時（誤判成 `.hookUnconfirmed`）、`AuraHookCLITests` 的
   「中位數 < 50 ms」（量到 **204 ms**，那條 gate 比這個 change 還老）、以及我自己加的
   「100 次 probe ≤ 30 ms」（4/20 次紅）。三條的處置分別是：
   - **可注入的逾時**（生產預設不動，測試注入寬鬆值；逾時那條 gate 反過來注入極小值，
     不再依賴「機器夠慢」這個不可控前提）
   - **跨 suite 的 spawn 閘門**（`Tests/*/Support/SpawnGate.swift`，**顯式鎖不是 actor 隱式序列化**
     ——actor 在懸掛點可重入，只靠「呼叫 actor 方法」序列化不住跨 `await` 的臨界區），
     並有來源掃描 gate 守「有 spawn 就必須經閘門」（觸發字面**不能用裸 `Process(`**，
     那會連 `swiftc`／`lipo`／`claude` 一起誤判；要用只在 spawn `aura-hook` 時才設的環境變數鍵名）
   - **相對比值取代絕對時間**：同一次執行量一個「已知必要工作」的控制組，斷言
     `probe ≤ K × 控制組`。負載讓兩邊同時變慢、比值穩定；長出目錄列舉會讓比值爆掉
     （實測 1.5x 基準 vs 4x 上限，mutation 衝到 11.39x）。
   **絕不**用「重跑取最小值」或 `.disabled` 把 flake 藏起來——那會訓練出「再跑一次就好」，
   比慢更糟。
6. **先立基準再修**（A9 實測示範）：改任何「使用者看不看得到」的東西之前，**先寫一個診斷測試量出
   修之前的數字**。A9 量到「`Toggle` 的 on/off 在離屏渲染下差 **0 px**」——那個 0 既是 bug 的證據，
   也讓修完的 mutation（461 → 0）精準對得上基準。同一招在 A10（405pt）與 C2（411pt 的逐項分解）
   都用上了。
7. **單位要寫在 gate 的斷言旁**：evidence 圖是 @2x，`preferredContentSize` 是 pt。
   我（主 session）就把 56 @2x 像素讀成 56pt、誤判「列高 57pt 太高」，而 spec review
   早就抓過同一個錯（S2-7）。凡是斷言尺寸的地方，**單位寫進 doc comment**。

## 與 user-level 的分工

SDD 流程框架（agent 職責、Tier 判定、Gate 分層、N-round checkpoint、git 工作流、mutation 標準程序）定義在 user-level CLAUDE.md，**本檔不重複**，只記專案特化。

**Tier 1 觸發（動到以下任一檔案即派 persona-tester）：**
`Sources/AgentAuraApp/**`（含 `LegendRowView.swift`、`PaletteStore.swift`、`ColorPickerCoordinator.swift`、
`HookVerificationStore.swift` 及 change `app-shell` 新增的 view，如
`PanelFooterView`／`OptionsSectionView`／`NotConnectedView`／`BannerView`／`LoginItem`）、
`Sources/AuraCore/IconAppearance.swift`、`Sources/AuraCore/AnimationSchedule.swift`、
`Sources/AuraCore/PanelViewModel.swift`、`Sources/AuraCore/LegendModel.swift`、
`Sources/AuraCore/InstallState.swift`、`Sources/AuraCore/PanelAction.swift`、
`Sources/AuraCore/OptionsMenuModel.swift`、`Sources/AuraCore/Jargon.swift`、
`Sources/AuraHookFile/Installer.swift`、`plugin/hooks/hooks.json`

## 易腐事實

測試數、覆蓋率、目前安裝狀態、`~/.agentaura/sessions/` 內容、branch 是否已 merge —— **不記本檔**，現場跑指令驗證。

## History

實測驅動：契約照 141 個真實 hook payload 寫，不照文件。實測推翻過多項文件層假設，並抓到三個只有實測才找得到的 bug（見 spec §10 與 `docs/03-measured-corrections.html`）。18 個 task + 10 輪修復批次的完整決策紀錄在 `.superpowers/sdd/2026-09-08-agentaura-pipeline/progress.md`（git-ignored）；審計總結見 `docs/2026-09-09-agentaura-audit.html`。
