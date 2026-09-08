# AgentAura

把 Claude Code 的運行狀態顯示在 macOS menu bar —— 不用切視窗就看得出「有沒有 agent 在等你」。

> **狀態：設計完成，實作未開始。** 目前 repo 內只有設計文件、實測證據與實作計畫。

## 這是什麼

多個 Claude Code session 併行時（多 agent、整夜跑 pipeline），你無法從畫面上看出
哪個 session 卡在權限請求、哪個掛了、哪個跑完了。AgentAura 用一個 menu bar icon
聚合全部 session 的狀態，並在下拉面板列出每個 session 的細節。

核心視覺規則：**只有需要你行動的狀態才會動。**

| 狀態 | 呈現 | 動畫 |
|---|---|---|
| `idle` | 極暗，近乎不可見 | 無 |
| `working`（常態） | 低對比暗藍，4s 極慢呼吸 | 極微 |
| `done` | 恆亮綠 | 無 |
| `waiting`（需要你） | 橘色明顯呼吸 | 有 |
| `error`（需要你） | 紅色 double blink | 有 |

聚合優先序：`error > waiting > working > done > idle`。

## 架構

```
Claude Code plugin hooks (全部 async)
        ↓
aura-hook  ──flock 下 merge-write──▶  ~/.agentaura/sessions/<session_id>.json
                                              │ FSEvents
                                              ▼
                                      AgentAura.app
                                      ├─ NSStatusItem 動畫
                                      └─ SwiftUI 面板
```

安裝走 Claude Code plugin（`/plugin install`），**不修改 `~/.claude/settings.json`** ——
天生可逆，不可能留下指向已刪除執行檔的死 hook。

## 文件

| 文件 | 內容 |
|---|---|
| [`docs/superpowers/specs/2026-09-08-agentaura-design.md`](docs/superpowers/specs/2026-09-08-agentaura-design.md) | **正典設計文件**（10 節） |
| [`docs/superpowers/plans/2026-09-08-agentaura-pipeline.md`](docs/superpowers/plans/2026-09-08-agentaura-pipeline.md) | 資料管線實作計畫（M0-M3，14 個 task） |
| `docs/01-approach-comparison.html` | 三個架構方案的比較（含拓撲圖） |
| `docs/02-design.html` | 設計呈現 |
| `docs/03-measured-corrections.html` | 依真實 payload 的 7 項校正 + 一個 critical bug |
| `docs/04-attention-budget.html` | 注意力預算與 icon 形態 A/B（含動畫原型） |
| [`docs/evidence/hook-payloads/`](docs/evidence/hook-payloads/) | 33 個真實 hook payload（唯讀證據） |

HTML 文件用瀏覽器直接開（`file://`）。

## 設計依據

契約不是照文件寫的，是**照實測的 33 個真實 hook payload 寫的**。實測推翻了 7 項文件層級的假設
（`model` 根本不存在、`effort` 是物件不是字串、`SessionEnd` 用 `reason` 而非 `end_reason`…），
並抓到一個 critical bug：

**subagent 的 tool 事件共用父 session 的 `session_id`**，實測一個 session 內主／subagent
交錯 5 次、最密相鄰間隔 20ms。在單槽 last-write-wins 下，主 agent 的 `PermissionRequest`
會在 20ms 內被 subagent 的 `PostToolUse` 覆寫成 `working` —— 產品唯一最重要的訊號被靜默抹除。
修法是 main/sub 分槽、activity 取優先序 max。

細節見 [`docs/03-measured-corrections.html`](docs/03-measured-corrections.html)。

## 授權

尚未決定（M6 開源時確定）。
