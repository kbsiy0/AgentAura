# AgentAura

把 Claude Code 的運行狀態顯示在 macOS 選單列 —— 不用切視窗就看得出「有沒有 agent 在等你」。

## 這是什麼

多個 Claude Code session 併行時（多 agent、整夜跑 pipeline），你無法從畫面上看出
哪個 session 卡在權限請求、哪個掛了、哪個跑完了。AgentAura 用一顆選單列 icon
**聚合**全部 session 的狀態，點開面板列出每個 session 的細節。

核心視覺規則：**只有需要你行動的狀態才會動。**

| 狀態 | 呈現 | 動畫 |
|---|---|---|
| `idle` | 極暗，近乎不可見 | 無 |
| `working`（常態） | 低對比暗藍，4s 極慢呼吸 | 極微 |
| `done` | 恆亮綠 | **無** |
| `waiting`（需要你） | 橘色明顯呼吸 | 有 |
| `error`（需要你） | 紅色 double blink | 有 |

聚合優先序：`error > waiting > working > done > idle`，**與寫入順序無關**。

## 安裝

需要 macOS 13+、Swift 6 工具鏈（`xcode-select --install`）、Claude Code。

```bash
git clone https://github.com/kbsiy0/AgentAura.git && cd AgentAura
./scripts/build-plugin.sh                            # universal aura-hook（必要：binary 不進版控）
claude plugin validate --strict ./plugin             # 官方 validator
ln -sfn "$PWD/plugin" ~/.claude/skills/agentaura     # 掛載
./scripts/verify-install.sh                          # 驗證整條鏈路

./scripts/build-app.sh                               # 組出 build/AgentAura.app
open build/AgentAura.app
```

**下一個** Claude Code session 起生效（skills-dir 的 plugin 在 session 啟動時載入）。
要開機自動啟動：把 `build/AgentAura.app` 拖進「系統設定 → 一般 → 登入項目」。

移除是一行 `rm ~/.claude/skills/agentaura`（狀態目錄 `rm -rf ~/.agentaura`）。
細節與疑難排解見 [`docs/INSTALL.md`](docs/INSTALL.md)。

> **`~/.claude/settings.json` 全程零改動。** 不是「移除後清乾淨」，是從頭到尾沒被寫過 ——
> 所以不可能留下指向已刪除執行檔的死 hook。（`claude plugin marketplace add` 會寫
> `extraKnownMarketplaces`，因此不走那條路；`verify-install.sh` 掃**整個**檔案驗證這件事。）

## 架構

```
Claude Code plugin hooks（19 個事件，全部 async: true）
        ↓
aura-hook ──flock 下 read-merge-write──▶ ~/.agentaura/sessions/<id>.json（0600）
                                              │ FSEvents
                                              ▼
                                      PipelineGraph（composition root）
                                      ├─ NSStatusItem + 自繪動畫
                                      └─ SwiftUI 面板
```

四個 module：`AuraCore`（純邏輯，零 UI 依賴，由編譯器 gate 強制）、
`AuraHookFile`（檔案 + FSEvents）、`aura-hook`（CLI）、`AgentAuraApp`（AppKit）。

`aura-hook` **任何錯誤都靜默 `exit 0`、stdout/stderr 一律空** —— 觀測性程式絕不可干擾 agent。
代價是 exit code 無法用來驗收，所以所有驗收都看產物而非回傳值。

## 設計依據：實測，不是文件

契約照 **141 個真實 hook payload** 寫（三輪捕獲，見 [`docs/evidence/hook-payloads/`](docs/evidence/hook-payloads/)）。
實測推翻了多項文件層假設，並抓到三個讀文件讀不出來的 bug：

1. **subagent 的 tool 事件共用父 session 的 `session_id`** —— 實測一個 session 內主／subagent
   交錯 5 次、最密相鄰 20ms。單槽 last-write-wins 下，主 agent 的 `PermissionRequest`
   會在 20ms 內被 subagent 的 `PostToolUse` 覆寫成 `working`。
   **產品唯一最重要的訊號被靜默抹除。** 修法：主／副分槽、activity 取優先序 max。
2. **使用者按 Deny 不產生任何 hook 事件** —— 序列是 `PermissionRequest` →（Deny）→ 什麼都沒有 →
   `SessionEnd`。所以 `waiting` 絕不能進入「已結束但未確認」的尾巴，否則一個你早就回答過的
   session 會讓 icon 一直亮橘燈說「有人在等你」。
3. **`PostToolUseFailure` 的錯誤欄位叫 `error`，不是 `tool_error`** —— 最初寫進 spec 的結論是
   「它沒有錯誤欄位」，那是因為透過一份自己寫的 key 過濾器去看 payload，
   而那份過濾器不含真正的欄位名。**用自己的假設去觀察，只會看到自己的假設。**

這個方法也會自我修正：第一輪的結論「任何 event 都不帶 `model`」被第二輪推翻
（`SessionStart` 確實帶 `"model":"claude-opus-5[1m]"`），spec §2.1.1 保留了兩輪的紀錄與判準。

## 文件

| 文件 | 內容 |
|---|---|
| [`docs/superpowers/specs/2026-09-08-agentaura-design.md`](docs/superpowers/specs/2026-09-08-agentaura-design.md) | **正典設計**（10 節）。與其他文件衝突時以它為準 |
| [`docs/2026-09-09-agentaura-audit.html`](docs/2026-09-09-agentaura-audit.html) | **建置審計報告** —— 八族「空轉的守衛」實證案例與修法 |
| [`docs/INSTALL.md`](docs/INSTALL.md) | 安裝、移除、疑難排解、從舊版升級 |
| [`CLAUDE.md`](CLAUDE.md) | 給 Claude Code 的專案指引（指令陷阱、invariants 與出處） |
| `docs/01-approach-comparison.html` · `02-design.html` · `03-measured-corrections.html` · `04-attention-budget.html` | **設計階段**的記錄（含拓撲圖、動畫原型）。內容停在設計當時，實作後的修正以 spec 為準 |

HTML 用瀏覽器直接開（`file://`），不綁任何帳號。

## 開發

```bash
swift test                          # 全量
swift test --filter <測試函式名>     # 單一測試
```

跨層 gate 的設計原則、指令陷阱（`swiftpm-testing-helper` 殭屍鎖、macOS 沒有 `timeout`…）
與所有 invariants 的出處寫在 [`CLAUDE.md`](CLAUDE.md)。

## 狀態

M0–M5 完成，[PR #2](https://github.com/kbsiy0/AgentAura/pull/2) 已 merge。**M4 icon 形態決策已完成**：
persona-tester 對兩個原型（8 顆 LED 燈條 A2、光環點 B2）打分，選定 **A2**（8 顆 LED ＋ 不透明底板）
——spec 的 R5「形態由證據決定而非預設」已滿足，決策細節見
[`docs/2026-09-09-m4-ab-decision.md`](docs/2026-09-09-m4-ab-decision.md)。
**Change 2 `panel-legend-palette` 開發與測試完成（待使用者實機驗收）**：面板底部常駐圖例列（錯誤·等你·執行中·已完成）、點色點以系統色板改色、四色持久化。
下一步：A2 淺色模式微調（決策報告 known gap F-02：底板在淺色模式偏重）。

## 改顏色

點選單列燈條開面板，底部圖例列的四個色點就是四種狀態的顏色。**點色點**會開系統色板，拖色時選單列的燈（若當前狀態就是那一態）
與面板圖例即時變；色板開著時面板設計為不自動關（此行為尚待實機驗收）。顏色存在 `UserDefaults`（`io.agentaura.app` 的 `AgentAuraColor.*` 四個 key），
「重設」一鍵回預設。idle 的極暗灰不可改。

## 授權

尚未決定（開源時確定）。
