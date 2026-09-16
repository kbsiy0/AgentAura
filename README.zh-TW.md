<h1 align="center">AgentAura</h1>

<p align="center">
  <b>在選單列上看見你的 Claude Code session 正在做什麼。</b><br>
  全部 session 聚合成一顆燈，只有需要你的狀態才會動。
</p>

<p align="center">
  <a href="README.md">English</a> · 繁體中文
</p>

<p align="center">
  <img src="docs/readme/icon-states.gif" alt="選單列 icon 的五種狀態：idle 與 done 靜止不動，waiting 與 error 在呼吸" width="620">
</p>

<p align="center">
  <sub>真實逐格，由生產程式碼的 view 離屏渲染。<code>idle</code>、<code>working</code>、<code>done</code> 完全靜止，只有 <code>waiting</code> 與 <code>error</code> 會動。</sub>
</p>

---

## 問題

同時開好幾個 Claude Code session——多 agent、整夜跑 pipeline——之後，畫面就不再告訴你任何事。
哪一個卡在權限請求？哪一個二十分鐘前就掛了？哪一個在你切到別的視窗時跑完了？

你只能一個一個切終端機分頁去看。

AgentAura 在選單列放一顆**聚合全部 session** 的燈，點開面板則逐一列出。抬頭看一眼就好，不必翻。

## 唯一的規則

**只有需要你行動的狀態才准動。**

一個一直在動的狀態指示器，只是第二個跟你搶注意力的東西。所以動畫是配額制的，
只花在真的買得到東西的地方：

| 狀態 | 呈現 | 動畫 |
|---|---|---|
| `idle` | 極暗，近乎不可見 | 無 |
| `working`（常態） | 低對比、暗 | 4 秒一次的極慢呼吸，幾乎察覺不到 |
| `done` | 恆亮綠 | **無**——你想看的時候再看 |
| `waiting`（需要你） | 橘色 | 1.1 秒明顯脈動 |
| `error`（需要你） | 紅色 | 雙閃 |

聚合取全部 session 裡優先序最高的狀態——`error > waiting > working > done > idle`——
**與誰最後寫入無關**。subagent 結束一次工具呼叫，絕不可以覆蓋掉「主 agent 正在等你回答」。

## 面板

點一下 icon 展開完整列表：一列一個 session，顯示專案名稱、正在做什麼、當前工具跑了多久。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/panel-zh-dark.png">
    <img src="docs/readme/panel-zh-light.png" alt="AgentAura 面板，列出四個 session 與各自的狀態" width="380">
  </picture>
</p>

底部的圖例列是常駐的，而那四個色點是按鈕。點下去會開系統色板，拖色時選單列的燈與圖例即時跟著變，
顏色會被記住。

<details>
<summary><b>Options 選單</b>——其餘功能都在這裡（點開）</summary>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/panel-options-zh-dark.png">
    <img src="docs/readme/panel-options-zh-light.png" alt="展開的 Options 選單，含開機自動啟動、減少動態、icon 造型、語言與移除項目" width="380">
  </picture>
</p>

開機自動啟動 · 減少動態（與系統設定取 OR）· 燈條底板 · 選單列 icon 造型 · 重設顏色 ·
語言（English／繁體中文）· 重新接上 · 移除掛載 · 完整移除 AgentAura · 關於 · 回報問題 ·
離開（⌘Q 是真的能用的）。

**右鍵**點選單列 icon 會直接開同一個選單。
</details>

## 選單列 icon 造型

六種造型。LED 燈條是預設，其餘五種是 SF Symbol。

<p align="center">
  <img src="docs/readme/icon-shapes.png" alt="六種可選的選單列 icon 造型：LED 燈條、圓點、圓環、膠囊、閃亮、半圓" width="620">
</p>

選單裡每一項左邊都有縮圖，而且會照當前狀態動起來——縮圖是由**畫真正那顆 icon 的同一個繪製器**
畫出來的，所以不可能跟你實際會拿到的樣子漂開。

## 安裝

需要 macOS 13+、Claude Code，以及 Swift 6 工具鏈（`xcode-select --install`）。

```bash
git clone https://github.com/kbsiy0/AgentAura.git && cd AgentAura

./scripts/build-plugin.sh          # 建置 universal 的 aura-hook（建置產物，不進版控）
./scripts/build-app.sh             # 產出 build/AgentAura.app
open build/AgentAura.app
```

然後在面板上按**接上**，並**開一個新的 Claude Code session**。

> **是下一個 session，不是現在這個。** Claude Code 在 session 啟動時載入 plugin，
> 已經開著的視窗不會中途載入。App 會照實這樣說，不會騙你說立即生效。

接上只建立一條 symlink：`~/.claude/skills/agentaura` → App。
**`~/.claude/settings.json` 全程零改動**——不是「移除後清乾淨」，是從頭到尾沒被寫過，
所以不可能留下一條指向已刪除執行檔的死 hook。

**移除**：Options →「移除掛載」解除掛載；Options →「完整移除 AgentAura」讓機器回到安裝前的狀態。
`./scripts/verify-uninstall.sh` 會逐項驗證這個宣稱。細節與疑難排解見
[`docs/INSTALL.md`](docs/INSTALL.md)。

## 它會碰你機器上的什麼

裝一個會看著你工作的東西之前，這些值得先知道：

| | |
|---|---|
| **網路** | App 自己不開任何連線——沒有遙測、沒有更新檢查、沒有當機回報，整個 codebase 裡沒有任何 HTTP client。原始碼裡只有兩個 URL：專案位址與「回報問題」，點下去時交給你的瀏覽器開。 |
| **寫入** | `~/.agentaura/sessions/<id>.json`（權限 `0600`），以及自己的 `UserDefaults` domain `io.agentaura.app`。就這些。 |
| **讀取** | 只讀自己的狀態檔。不讀你的 transcript、不讀你的 prompt、不讀你的程式碼。 |
| **那一條 symlink** | `~/.claude/skills/agentaura`。安裝器被限制只能碰這個路徑（必要時加上建立 `~/.claude/skills/`），且一律以 `realpath` 解析後的位置判定。 |
| **權限** | 一個都不要。不需要螢幕錄製、不需要輔助使用、不需要完整磁碟取用。「開機自動啟動」走 `SMAppService`，且預設關閉。 |
| **相依** | 零第三方套件，全部是 Foundation／AppKit／SwiftUI。 |

Claude Code 送進 hook 的是中繼資料——session id、專案目錄名、事件類型、工具名稱、時間。
AgentAura 把其中一份精簡版存到磁碟好讓面板能重畫，移除時一併刪掉。

## 運作方式

```
Claude Code plugin hooks（19 個事件，全部 async: true）
        │
        ▼
aura-hook ──flock 下 read-merge-write──▶ ~/.agentaura/sessions/<id>.json（0600）
                                                │ FSEvents
                                                ▼
                                        PipelineGraph（composition root）
                                        ├─ NSStatusItem ＋ 自繪動畫
                                        └─ SwiftUI 面板
```

四個 module：`AuraCore`（純邏輯，零 UI 相依，由編譯器驅動的測試強制）、
`AuraHookFile`（檔案 ＋ FSEvents）、`aura-hook`（CLI）、`AgentAuraApp`（AppKit）。

`aura-hook` **不論發生什麼都 `exit 0`，stdout 與 stderr 一律空。**
觀測性程式絕不可以干擾它觀測的對象。代價是 exit code 完全不能拿來驗收，
所以每一項驗證都看產物，不看回傳值。

## 設計依據是實測，不是文件

事件契約是照 **141 個真實 hook payload** 寫的（分三輪捕獲），不是照文件。
實測推翻了多項文件層假設，也抓到三個純讀文件抓不到的 bug：

1. **subagent 的工具事件與父 session 共用 `session_id`。** 實測：一個 session 裡主／subagent
   事件交錯五次，最密的相鄰只差 20 毫秒。在 last-write-wins 之下，subagent 的 `PostToolUse`
   會在 20 毫秒內覆寫掉主 agent 的 `PermissionRequest`——
   *把這個產品唯一最重要的訊號靜默抹除。* 修法是主／副分槽、取優先序 max。

2. **按下 Deny 不會產生任何 hook 事件。** 序列是 `PermissionRequest` →（你按 Deny）→ 什麼都沒有
   → `SessionEnd`。所以 `waiting` 絕不能存活到「已結束但未確認」的尾巴裡，
   否則一個你早就回答過的 session 會讓 icon 一直亮著橘燈。

3. **`PostToolUseFailure` 的錯誤欄位叫 `error`，不叫 `tool_error`。** 最初寫進 spec 的結論是
   「它沒有錯誤欄位」——因為當時是透過一份自己寫的 key 過濾器去看 payload，
   而那份過濾器裡沒有真正的欄位名。*用自己的假設去觀察，只會看到自己的假設。*

> `Tests/AuraCoreTests/Fixtures/` 裡的 payload 已經**去識別化**：路徑、prompt、assistant 訊息與
> 檔案內容在 repo 公開前都被換掉了。事件的結構——也就是契約與它的測試真正依賴的東西——原封不動，
> 原始捕獲則不公開。

這個方法也會自我修正：第一輪的結論「任何事件都不帶 `model`」被第二輪推翻，
兩輪的紀錄與翻案的判準都留在 spec 裡。

## 文件

| 文件 | 內容 |
|---|---|
| [`docs/superpowers/specs/2026-09-08-agentaura-design.md`](docs/superpowers/specs/2026-09-08-agentaura-design.md) | **正典設計**。與其他文件衝突時以它為準 |
| [`docs/INSTALL.md`](docs/INSTALL.md) | 安裝、移除、疑難排解、升級 |
| [`docs/2026-09-09-agentaura-audit.html`](docs/2026-09-09-agentaura-audit.html) | 建置審計——八族「空轉的守衛」實證案例與修法 |
| [`docs/2026-09-11-subagent-state-priority-audit.html`](docs/2026-09-11-subagent-state-priority-audit.html) | 背景 subagent 怎麼讓燈號說謊，以及實測的時間線 |
| [`CLAUDE.md`](CLAUDE.md) | 給 Claude Code 的專案指引：每條 invariant 與它的出處，以及踩過的陷阱 |

HTML 用瀏覽器直接開（`file://`），不綁任何帳號。

## 開發

```bash
swift test                          # 全量
swift test --filter <測試函式名>      # 單一測試（是函式名，不是檔名）
```

760 個測試、144 個 suite。Swift 6 strict concurrency；測試用
[swift-testing](https://github.com/swiftlang/swift-testing)（`@Test`／`#expect`），不是 XCTest。

**乾淨 clone 要先跑 `./scripts/build-plugin.sh`**——`plugin/bin/aura-hook` 是建置產物且不進版控，
沒建的話有三條 install-layout 測試是紅的。

測試哲學——問平台而不是在它外面包一層近似、每一個數字都從型別或磁碟推導而不是凍成常數、
每個 gate 都要有 mutation 紀錄——寫在 [`CLAUDE.md`](CLAUDE.md) 裡，連同催生每一條規則的那次失敗。

README 的圖是**產生**出來的，不是螢幕截圖：

```bash
AURA_RENDER_README=1 swift test --filter ReadmeAssetRenderer
```

它離屏渲染真正的生產 view，因此可重現，也不會把真實專案名稱與路徑帶進一個公開的 repo。

## 授權

[MIT](LICENSE)。
