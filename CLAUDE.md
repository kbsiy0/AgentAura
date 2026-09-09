# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

把 Claude Code 的運行狀態顯示在 macOS 選單列。plugin hook → 狀態檔 → FSEvents → 一顆聚合燈 + 面板。

> **狀態（2026-09-09）：M0–M5 的最小可用版完成，`change/agentaura-pipeline` 已開 PR #2 待 merge。**
> 下一個里程碑 **M4**：icon 形態 A/B 原型 + persona-tester 打分（R5 尚未滿足）。
> 重啟指標：`docs/superpowers/specs/2026-09-08-agentaura-design.md` §8 里程碑表。

## Tech Stack

Swift 6（`swift-tools-version: 6.0`，strict concurrency）· macOS 13+ · SwiftPM · **swift-testing（`import Testing` / `@Test` / `#expect`，不是 XCTest）** · FSEvents · `flock(2)` · `sysctl(KERN_PROC_PID)`。零第三方依賴。

## 結構

```
Sources/
  AuraCore/         純邏輯，零 AppKit/SwiftUI 依賴（由編譯器 gate 強制）
  AuraHookFile/     flock 讀寫、FSEvents、PipelineGraph（composition root）
  aura-hook/        被 hook 呼叫的 CLI，一律 exit 0
  AgentAuraApp/     AppKit：選單列、動畫、面板
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
scripts/                build-plugin · build-app · verify-install · verify-app
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
- **主／副槽分開，activity 取優先序 max；主槽靜止時完全忽略 subagent 事件**（spec §2.5 / §2.5.1 / `efccc03` —— subagent 與父 session 共用 `session_id`，實測最密相鄰 20ms）。
- **`aura-hook` 一律 `exit 0`，stdout / stderr 一律空**（觀測性絕不可干擾 agent。代價：exit code 無法用來驗收，所以驗收必須看產物）。
- **解析失敗 ≠ 檔案不存在**（spec §3.3 / §4 第 3 列 / `dae435d` —— 損壞檔要保留上次已知狀態並重試；只有檔案真的消失才移除 session）。
- **`PipelineGraph.registry` 是 `internal` 且未加鎖，對外只走上鎖的 `visibleSessions`**（`7f9d7b8` —— `onIconStateChange` 從 FSEvents 背景 queue 上來）。
- **`Sources/AuraCore/` 不得載入 Foundation 閉包以外的任何 module**（`58ea4b5` —— 白名單基準而非黑名單；黑名單漏掉 `CoreImage` 這類框架）。
- **單檔上限：`Sources/` 200 行、`Tests/` 300 行**（`IsolationTests.fileLengthLimit` 從磁碟推導，新增 module 不會漏網）。

## 這個 codebase 的 gate 哲學

改動任何 gate 前先讀 `docs/2026-09-09-agentaura-audit.html`（八族「空轉的守衛」實證案例）。三條規則：

1. **平台契約要問平台** —— 問編譯器（module trace）、問 `claude plugin validate --strict`、問 `swift package dump-package`。不要在它們外面再包一層自己的近似。
2. **「涵蓋每一個 X」必須從型別／磁碟推導**，不能只寫在 doc-comment 裡（既有做法：`Mirror` 掃 stored property、`swiftFiles(under:)` 掃磁碟）。
3. **每個 gate 都要有 mutation 紀錄** —— 把生產碼改壞，指名的測試必須**在指定秒數內**變紅（不是掛住）。mutation 用完整字串取代、且先確認編譯成功再看測試結果。

## 與 user-level 的分工

SDD 流程框架（agent 職責、Tier 判定、Gate 分層、N-round checkpoint、git 工作流、mutation 標準程序）定義在 user-level CLAUDE.md，**本檔不重複**，只記專案特化。

**Tier 1 觸發（動到以下任一檔案即派 persona-tester）：**
`Sources/AgentAuraApp/**`、`Sources/AuraCore/IconAppearance.swift`、`Sources/AuraCore/AnimationSchedule.swift`、`Sources/AuraCore/PanelViewModel.swift`、`plugin/hooks/hooks.json`

## 易腐事實

測試數、覆蓋率、目前安裝狀態、`~/.agentaura/sessions/` 內容、branch 是否已 merge —— **不記本檔**，現場跑指令驗證。

## History

實測驅動：契約照 141 個真實 hook payload 寫，不照文件。實測推翻過多項文件層假設，並抓到三個只有實測才找得到的 bug（見 spec §10 與 `docs/03-measured-corrections.html`）。18 個 task + 10 輪修復批次的完整決策紀錄在 `.superpowers/sdd/2026-09-08-agentaura-pipeline/progress.md`（git-ignored）；審計總結見 `docs/2026-09-09-agentaura-audit.html`。
