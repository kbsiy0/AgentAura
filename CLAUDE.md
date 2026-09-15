# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

把 Claude Code 的運行狀態顯示在 macOS 選單列。plugin hook → 狀態檔 → FSEvents → 一顆聚合燈 + 面板。

> **狀態（2026-09-13）**：M0–M5、Change 2、change `app-shell`（phase 2 UI/UX 完整化）、
> change `panel-interaction-fixes` 皆已完成並 merge 進 main。實機清單 13 條：8 條通過、
> ⑥ 右鍵**觀察中**（重現不出來）、①②④⑤ 改列 known gap（只有全新安裝才測得到，觸發條件見
> DoD 帳本）。
> change `subagent-state-priority` 亦已完成：背景具名 subagent 讓燈號說謊的三個落差已修
> （設計、實測證據與**燈號實機時間線**在 `docs/2026-09-11-subagent-state-priority-audit.html`）。
> 重啟指標：`docs/superpowers/specs/2026-09-08-agentaura-design.md` §8 里程碑表。
> PR／branch 的 merge 狀態屬易腐事實，**不記本檔**，用 `gh pr list --state all` 現場查。

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
  SubagentKnownGapTests.swift ★ subagent 優先序的契約（曾刻意釘住「今天的錯」，修好後已改寫成新契約）
  Fixtures/*.ndjson     ★ 真實 hook payload，唯讀證據（round3 是具名 subagent）
Tests/AgentAuraAppTests/  composition-root smoke（spec §5.2）+ 離屏渲染 gate
plugin/                 Claude Code plugin（bin/ 是建置產物，gitignored）
docs/superpowers/specs/2026-09-08-agentaura-design.md  ★ 正典設計，衝突以它為準
docs/2026-09-11-subagent-state-priority-audit.html     ★ subagent 優先序的設計與實測證據
docs/INSTALL.md         ★ 安裝／移除／疑難排解
Resources/help-*.html   ★ bundle 內離線說明，依語言分檔（D-l／T30，隨 build-app.sh 複製進 app）
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
- **乾淨 clone 先跑 `./scripts/build-plugin.sh`** —— `plugin/bin/aura-hook` 是建置產物且 gitignored，沒建就有 3 條 `InstallLayoutTests` 是紅的（開 worktree 做實驗時也會踩到）。
- **不要同時開多個 `swift test`** —— 搶 `.build` 的鎖，看起來像掛住。要並行就開 `git worktree`。
- **只殺 `swift test` 父行程會留下 `swiftpm-testing-helper` 殭屍鎖住 `.build`**。清法：`pkill -9 -f swiftpm-testing-helper`。
- **macOS 沒有 `timeout` 命令**。要有界執行自己寫 `cmd & pid=$!; (sleep N; kill -9 $pid) & wait $pid`。
- **`swift package dump-package` 從 `swift test` 的子行程跑會死結**。必須加 `--scratch-path <temp>`（`Gate.packageTargets()` 已處理）。
- **中文 commit message 用 `git commit -F - <<'EOF'`**，不要 `-m` —— zsh 的 history expansion 會吃掉 `!`。
- **診斷 app 行為時 `NSLog` 不進統一日誌**（`log show` 撈不到，加 `--info` 也一樣）。直接跑執行檔把 stderr 導進檔案：`nohup <app>/Contents/MacOS/AgentAuraApp > diag.log 2>&1 &`。
- **`FileManager.homeDirectoryForCurrentUser` 不吃 `$HOME`**（讀密碼資料庫），所以無法用假家目錄開隔離實例測安裝流程。

## Invariants

格式：禁令（出處 —— 根因）。

- **絕不修改 `~/.claude/settings.json`**（D3/R6 —— 安裝走 `~/.claude/skills/agentaura` symlink）。`verify-install.sh` 掃**整個**檔案而不只 `hooks` 鍵。
- **`waiting` 不得進入「已結束但未確認」的尾巴**（spec §2.4.1 / `e90931c` —— 實測按 Deny 不產生任何 hook 事件，否則早已回答過的 session 會讓 icon 一直亮橘燈）。
- **`Notification(idle_prompt)` 不得映射到 `waiting`**（spec §2.2.1 / `IdlePromptTests` —— 一輪結束 60s 後必送；歸 waiting 等於每個講完話的 session 都亮橘）。
- **acknowledge 只在面板關閉（`NSPopover.didClose`），開啟路徑不得 acknowledge**（spec §3.7 / `acknowledgeFiresOnCloseNotOpen` —— 舊順序讓已結束的列在畫出前就被移出 registry）。
- **主／副槽分開，activity 取優先序 max；內部 subagent（`agent_type` 空字串）的事件在主槽靜止時一律忽略**（spec §2.5／§2.5.1 / `efccc03` —— subagent 與父 session 共用 `session_id`，實測最密相鄰 20ms；內部 subagent 的 `SubagentStop` 實測在主 agent `Stop` 後 2.58s–186s 才到）。**具名** subagent 走獨立集合，見 subagent 審計文件。
- **`aura-hook` 一律 `exit 0`，stdout / stderr 一律空**（觀測性絕不可干擾 agent。代價：exit code 無法用來驗收，驗收必須看產物）。
- **解析失敗 ≠ 檔案不存在**（spec §3.3 / `dae435d` —— 損壞檔要保留上次已知狀態並重試）。
- **`PipelineGraph.registry` 是 `internal` 且未加鎖，對外只走上鎖的 `visibleSessions`**（`7f9d7b8` —— `onIconStateChange` 從 FSEvents 背景 queue 上來）。
- **`Sources/AuraCore/` 不得載入 Foundation 閉包以外的任何 module**（`58ea4b5` —— 白名單基準而非黑名單）。
- **單檔上限：`Sources/` 200 行、`Tests/` 300 行**（`IsolationTests.fileLengthLimit` 從磁碟推導）。
- **`Installer` 只准碰 `<claudeHome>/skills/agentaura`（必要時加 `<claudeHome>/skills/`），判定一律以 `realpath` 解析後為準；`~/.claude` 不存在時拒絕接上、不得建立它**（spec D-h —— `skills` 自己可能是 symlink；gate `installerTouchesOnlyAllowedPaths`）。

## Agent 在終端機裡的界線（2026-09-14 事故）

產品程式碼不准刪什麼，跟 **agent 自己在終端機裡可以跑什麼**，是兩條不同的界線。
事故發生在後者：一個 subagent 為了確認 `sfltool resetbtm` 是不是真的指令，**直接執行它
「順便看看說明」**——它不是查詢，是真的重置了整台機器的背景任務管理資料庫，
開發機上八個登入項目瞬間歸零（`sfltool dumpbtm` 1593 行 → 21 行，全機影響、非本專案專屬）。

- **不確定後果的系統指令，只准查文件，不准「執行一次看看」。** 想知道一個指令做什麼，
  用 `man` / `--help` / 官方文件，不要用執行它來查。**執行不是查詢。**
- **破壞性動詞一律先問人**：`reset`／`erase`／`purge`／`disable`／`reinstall`／`delete`
  出現在 `sfltool`、`launchctl`、`tccutil`、`diskutil`、`csrutil`、`defaults delete <別人的 domain>`
  這類**系統層級**工具上時，先停下來問，不要自己判斷「應該還好」。
- **破壞性指令不得寫進使用者文件**，即使附警告——`docs/INSTALL.md` 的草稿一度把
  `sfltool resetbtm` 放進可複製的程式碼區塊、警告放在區塊下方。人會複製區塊，不會先讀警告。
- **動任何全機狀態前先存基準**：這次能在三分鐘內確定損害範圍與清單，唯一原因是事故前
  剛好量過一次登入項目。`osascript -e 'tell application "System Events" to get the name of
  every login item'` 是 0 秒的快照，很便宜。

## 這個 codebase 的 gate 哲學

改動任何 gate 前先讀 `docs/2026-09-09-agentaura-audit.html`（八族「空轉的守衛」實證案例）。

1. **平台契約要問平台** —— 問編譯器（module trace）、`claude plugin validate --strict`、`swift package dump-package`。不要在它們外面再包一層自己的近似。
   **平台沒有 getter 時才退而問原始碼**（`RightClickSendActionGuardTests`：`sendAction(on:)` 的遮罩 AppKit 讀不回來，拿掉那行右鍵會安靜失效而全測試照綠）。
2. **「涵蓋每一個 X」與**每一個數字**都必須從型別／磁碟／真實 view 推導**，不能寫死也不能只寫在 doc-comment 裡。實證：`LEDStripView.preferredWidth` 把算術錯誤凍成常數（34 vs 正確的 38），gate 又退化成跟自己比對；`SessionsCardSizing.rowHeight` 用「沒有副行」的列量成 33pt，真實有副行是 49pt，會把唯一一列裁掉。兩次都是使用者實機才發現。
3. **每個 gate 都要有 mutation 紀錄** —— 生產碼改壞，指名測試必須**在指定秒數內**變紅（不是掛住）。用完整字串取代，且先確認編譯成功再看測試結果。
4. **守「宣告順序」不等於守「渲染結果」**（A4 vs T22）：A4 的 gate 斷言 Options 區塊宣告在 footer 之後，一直是綠的；實機上 footer 仍被推走 −257pt，因為外層畫布高度與理想高度不一致時 `ScrollView` 會吃滿提案、`VStack` 會把多餘空間置中。**位置類的 gate 要量渲染後的座標。**
5. **離屏渲染有兩個會咬人的平台限制**（T07 實測）：`.bordered`／`.borderedProminent` 會把真 `NSButton` 包進 `_FocusRingView`，沒有真 `NSWindow` 時走訪不到 —— 要能從測試觸發的按鈕**必須用 `.borderless`**；離屏讀不到 `.title` 也讀不到 `.accessibilityIdentifier`，定位只能用位置索引，所以**新增按鈕時要一併檢查既有的索引斷言**。
6. **量絕對時間的 gate 會被測試套件自己的負載打敗**（phase 2 實測撞穿三條）：swift-testing 預設跨 suite 並行，`.serialized` 只序列化 suite 內部。處置是**可注入的逾時**、**跨 suite 的 spawn 閘門**（顯式鎖，不是 actor 隱式序列化 —— actor 在懸掛點可重入）、**相對比值取代絕對毫秒**。**絕不**用「重跑取最小值」或 `.disabled` 把 flake 藏起來。
7. **先立基準再修**：改任何「使用者看不看得到」的東西之前，先寫診斷測試量出修之前的數字（A9 的 0 px、T22 的 −257 pt），mutation 才對得上基準。**斷言尺寸時單位寫進 doc comment** —— evidence 圖是 @2x，`preferredContentSize` 是 pt，混用已經害人誤判過一次。

## 與 user-level 的分工

SDD 流程框架（agent 職責、Tier 判定、Gate 分層、N-round checkpoint、git 工作流、mutation 標準程序）定義在 user-level CLAUDE.md，**本檔不重複**，只記專案特化。

**Tier 1 觸發（動到以下任一檔案即派 persona-tester）：**
`Sources/AgentAuraApp/**`、`Sources/AuraCore/` 的 `IconAppearance.swift`、`AnimationSchedule.swift`、
`PanelViewModel.swift`、`LegendModel.swift`、`InstallState.swift`、`PanelAction.swift`、
`OptionsMenuModel.swift`、`Jargon.swift`、`IconPalette.swift`、
`Sources/AuraHookFile/Installer.swift`、`plugin/hooks/hooks.json`

## 易腐事實

測試數、覆蓋率、目前安裝狀態、`~/.agentaura/sessions/` 內容、branch 是否已 merge、實機清單各條的最新結果 —— **不記本檔**，查 auto-memory、DoD 帳本或現場跑指令驗證。

## History

實測驅動：契約照 141 個真實 hook payload 寫，不照文件。實測推翻過多項文件層假設，並抓到三個只有實測才找得到的 bug（見 spec §10 與 `docs/03-measured-corrections.html`）。18 個 task + 10 輪修復批次的完整決策紀錄在 `.superpowers/sdd/2026-09-08-agentaura-pipeline/progress.md`（git-ignored）；審計總結見 `docs/2026-09-09-agentaura-audit.html`。
