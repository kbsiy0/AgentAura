---
change: codex-support
release_target: softlaunch
persona_impact: tier1
persona_impact_reason: 動 Sources/AgentAuraApp/**（面板列標籤、Codex 區塊、Options 新列）與 AuraCore 的 PanelAction／PanelModel／面板文案；「接上 Codex」是使用者第一次見到的第二種安裝動作，而我們**無法偵測 Codex 是否已信任這個 hook**（F5），生效與否完全靠畫面把話講清楚——這是純人類面的風險，不是機器面的
revision: r15（2026-09-21，折入 r14 review 的 1 MAJOR／3 minor：T13b→T13i 跨鏈語意依賴、CX52 兩格 pattern 不同、install 代表值改成實測最高、snippet 下限的推導層；送審）
---

# Change · `codex-support`：讓同一顆燈也照到 Codex

> 正典 `2026-09-08-agentaura-design.md` 為權威；本 change 對正典的修訂在 §8.2。
> 證據層是 `docs/2026-09-18-codex-hook-probe.md`（**F1–F15**，F15 以 `8fdce0b` 的版本為準）。
> **任何關於 Codex 行為的斷言都標了 F 編號；沒有 F 編號的一律寫成「待驗」，不得當事實用。**
> gate 編號慣例：**本 change 新增的 gate 一律 `CX<n>`**（共 **57** 條；CX37 拆成 a／b，CX43 未使用，
> CX47–CX57 是 r13 的 persona 修復批次）；提到**既有** gate 一律寫
> 測試函式名（例如 `installerTouchesOnlyAllowedPaths`），**不寫 `G<n>`**。

## 0. 背景與裁決

Codex CLI 0.155.0 讀 `~/.codex/hooks.json`，結構與 Claude Code 相同（F1、F14），事件名有 12 個、
其中 11 個與 Claude Code **同名同形**（F2、F3）。所以這個 change 不是「再做一套」，
是「把既有的那一套多接一條進水管」。

### 0.1 使用者 2026-09-18 拍板（鎖定，不重開）

| # | 決策 |
|---|---|
| L1 | **同一顆 `aura-hook` 二進位**，加 `--agent codex` 參數；預設（無參數）＝ claude。Claude 那側的 `plugin/hooks/hooks.json` **不改**（本 change 對它的 git diff 必須為空） |
| L2 | `SessionSnapshot` 加 `agent` 欄位；面板列顯示「Codex」標籤；**聚合燈不分 agent**，還是一顆 |
| L3 | 事件映射沿用既有 `EventMapping.effect`；新事件 **`Interrupt` → `.setActivity(.idle)`**；`waiting` 來自 `PermissionRequest`（形狀待驗）；**Codex 沒有 `error` 狀態的來源**（F2、F4）——列 known gap，不硬推 |
| L4 | 安裝模型：「接上 Codex」**只在 `~/.codex/` 存在時顯示**；按下去**只在 `~/.codex/hooks.json` 不存在時寫入**（12 個事件、`command` 用 bundle 內 `aura-hook` 的**絕對路徑** ＋ `--agent codex`，F9）；寫入時記下內容；斷開**只在內容相符時刪除**。檔案已存在（別人的）→ 不動它，顯示可複製的 snippet。**絕不碰 `~/.codex/config.toml`**。UI 必須明講「Codex 會在下次啟動時問你一次是否信任這個 hook」（F5） |
| L5 | 「完整移除」**必須一併移除我們寫的 `~/.codex/hooks.json`**（內容相符時） |
| L6 | 文件（README × 2、INSTALL × 2、`Resources/help-*.html`、SECURITY、CLAUDE.md）都要更新；**英文為主**，中文同步 |

### 0.2 review r1／r2／r3 之後的裁決（主 session 2026-09-18，已鎖定）

| # | 裁決 | 取代 |
|---|---|---|
| R-1 | 產生器**逐字**輸出 F14 已驗證的形狀：`matcher: ""`、`type: "command"`、`command`，最外層 `hooks` 物件；**不加 `async`** | r1 §4.3 省略 `matcher` 的變體 |
| R-2 | **不算 hash**：把寫入的完整內容存進 `UserDefaults`，刪除前逐位元組比對 | r1 的 D-h |
| R-3 | `.notConnected` 的 Codex 卡片**一律單行提示＋按鈕**，不依 Claude 的安裝狀態降級 | r1 §4.6／§9／T09 的矛盾敘述 |
| R-4 | **`timeout: 3`**（全部 12 個事件同一個值），對 F14 **唯一的數值偏離**，理由與代價見 §4.3 | r2 的 `timeout: 5` |
| R-5 | 「這個 bundle 路徑能不能寫進 hooks.json」收斂成**單一純函式判定** `CodexHookPathCheck`；輸出餵**路由層**（`CodexState` 的 explain-only 分支）與**執行層**（`connect` 的 guard），**r4 再加第三個消費者**：`performConnectCodex()` 的前置 guard（R-9） | r2 完全沒有 translocation／路徑字元護欄 |
| R-6 | app 搬家導致絕對路徑失效 → `CodexState.from` 多吃 `currentExpectedContents`，新增 **`.connectedStalePath`**，UI 給「App 移動過，要重新接上」＋一鍵重接 | r2 的 `.connected` 在搬家後永遠成立 |
| R-7 | 含空白路徑的**探索性量測**移到互動探針工具包；DoD 實機 ⑦ 只驗「拒絕 ＋ 訊息指名字元 ＋ 有出路」 | r2 實機 ⑦「按接上 → 燈會動」 |
| **R-8** | **兩側互不干擾、最終都要成功**（使用者 2026-09-18 口述）：對任一側做 connect／disconnect／reconnect／完整移除的**任意操作序列**，另一側的檔案位元組與 `InstallState`／`CodexState` 不變；兩側都接上時，兩側都**真的能運作**。寫成不變式 ＋ 三條 gate（CX37a／CX37b 檔案、CX42 憑證、CX38 端到端）＋ 實機一格，見 §4.8 | r3 完全沒有把「兩側共存」寫成契約 |
| **R-9** | **「重新接上」在路徑被拒時不得先刪檔**：`performConnectCodex()` 第一行先看 `pathRejection`，非 nil 就顯示 banner／explain-only 並在**任何 `disconnect` 之前 return**；`.connectedStalePath` 的文案依 `pathRejection` 分兩種（非 nil 那種**不給按鈕**）。判定表列序**不動** | r3 的「stale → 先 disconnect 再 connect」在 translocated 下會刪掉使用者還在運作的檔（r3 B1） |
| **R-10**（**r13 擴大，見 D-w**） | **snippet 也要穿過 `CodexHookPathCheck`**：~~`pathRejection == .mustMoveToApplications`~~ → **`pathRejection != nil`** 時 `codexSnippet = nil`，snippet 區塊換成**依 rejection 分流**的出路句（`.mustMoveToApplications`：先把 App 移到『應用程式』；`.unsupportedCharacter`：先把 App 移到路徑不含該字元的位置）。條件從「等於某一個 rejection」變成「有 rejection」，**乘積表 CX40 的期望值因此整欄翻轉**，不是加一格 | r3 的 `.occupiedByOther` 無條件給 snippet，繞過 D-s（r3 M1）。r13：`.unsupportedCharacter` 仍照給，等於把一份含著我們自己剛說可能會壞的路徑的設定檔遞給最會照著貼的 persona（persona r1 S0-2） |

### 0.3 本 change 自行決定的細節（最終報告逐條標示）

| 決定 | 內容 | 理由 |
|---|---|---|
| D-a | 磁碟上的 `agent` 是 **`String?`**（不是 enum），enum 只在 AuraCore 的邊界解析 | `Codable` 對「未知 rawValue 的 enum」是**整包解碼失敗**——未來多一種 agent，舊版 app 讀到的是**那個 session 從面板整個消失**。同 `outstandingSubagents` 的既有理由 |
| D-b | `Agent` 只有 `claude`／`codex`；未知值與 nil 一律落回 `.claude`，**且 `.claude` 不顯示標籤** | 保守失敗：寧可少一個標籤，不可把 Codex 的列標成 Claude 的 |
| D-c | `.claude` **不寫** `agent` 這個 JSON 鍵 | Claude 路徑的狀態檔位元組與改動前**完全相同**（CX9） |
| D-d | `--agent` 支援 `--agent codex` 與 `--agent=codex`；未知值／缺值一律 `.claude`，**全程靜默、exit 0** | 只支援一種寫法時，手寫成另一種會**靜默標成 claude** |
| D-e | Codex 的事件集合是**獨立常數** `codexEvents`，**不併進 `handledEvents`** | `handledEvents` 是 Claude 側 hooks.json 雙向等式 gate 的來源，而 Claude Code 對 hooks.json 是**全有全無**解析。**最容易踩的接縫**，見 §4.2 |
| D-f | `handledEvents` **不改名**，只補 doc comment | 三個既有測試檔用字面 `handledEvents` 釘住它 |
| D-g | hooks.json 產生器是**純函式**住 AuraCore | `Sources/AuraCore/` 只准 import Foundation |
| D-h | **（作廢，見 R-2）** 原為「digest 計算住 App 層＋注入縫」 | 保留來龍去脈給下一個讀到「為什麼不算 hash」的人 |
| D-i | 寫入用 `open(path, O_CREAT\|O_EXCL\|O_WRONLY\|O_CLOEXEC, 0o644)` | 「只在不存在時寫」必須是**一個**原子動作。四種佔用形狀實測**一律回 `EEXIST`** |
| D-j | `~/.codex` 不存在（或不是目錄）時，面板與 Options **完全沒有任何 Codex 元素** | 沒裝 Codex 的人畫面零 diff |
| D-k | 新增三個 `PanelAction`；**R-6 的「重新接上」重用 `.connectCodex`，不開第四個** | 重用讓 94 個呼叫點的 fan-out 不再長大 |
| D-l | 「Codex」標籤放在列的**第一行**，不另起一行 | 列高 43／59pt 由 `RowHeightDerivationTests` 從真實 view 推導 |
| D-m | 接上成功的 banner **必須**同時說「下一個 Codex session 起生效」與「Codex 會問你一次是否信任」。**r13 補（D-v）**：這條的強制力包含**退場條件**——banner 走自己的 `.codexConnected` kind，只在出現 **Codex 的列**時才自動退場。**「文案裡有那兩句」與「那兩句真的被畫出來」是兩件事**，前者由 CX24④（儲存值）守、後者由 CX48（渲染後的 view）守 | F5 讓「已生效」在 Codex 上比在 Claude 上更不可宣稱。r13：persona r1 的 S0-1 證明只守儲存值不夠——面板上有任何一列（哪怕是 Claude 的）時，`effectiveBanner` 就把它抹掉，而 CX24④ 斷言的是 `delegate.banner?.text` 且那個 smoke 的 session graph 是空的，所以全綠 |
| D-n | 完整移除時，codex disconnect 必須排在 `erasePersistentDomain()` **之前** | 比對用的內容住在 persistent domain 裡 |
| D-o | `verify-uninstall.sh` 第 7 項用**內容判準** | 腳本跑的時候 persistent domain 已清空 |
| D-p | `~/.codex` 自己是 symlink 時**不拒絕**，但寫入必須落在 `realpath` 底下 | 同既有 `ClaudeHomeSkillsSymlinkFixture` 的形狀 |
| D-q | 只在 `regularFile` **且 ≤ 64 KiB** 時才讀內容 | 我們的檔 ~2 KB；超過的不可能是我們寫的 |
| D-r | `CodexState` 帶 associated value 故**不能 `CaseIterable`**；配平行的 `CodexStateKind` ＋ `samples(_:)`。**r4 再往下一層**：`Rejection` 也配 `RejectionKind: CaseIterable` ＋ `Rejection.samples(_:)`，`CodexState.samples(.blockedByBundlePath)` 由它推導（r3 m1）。**兩層的 `switch` 都不得有 `default`**（r3 m2） | 既有 `PanelActionKind` 的 doc comment 逐字寫著這個理由。`default: []` 是一個看起來很無害的「防禦性」寫法，卻能讓整條推導鏈靜默失效——所以要寫成禁令，不是慣例 |
| D-s（**強制力註記**：這條在 T09 review M1 的修正（view 層負向斷言改餵真 snippet）**與** T10 的 CX40 落地**之前，在整個 codebase 裡零強制力**——兩層都實作了、兩層都沒有 gate） | **r13 起（D-w）：`.blockedByBundlePath` 的兩種 Rejection 出路不同，但「給不給 snippet」的答案相同——兩種都不給**。`.mustMoveToApplications` → 「把 App 移到『應用程式』」；`.unsupportedCharacter` → 「把 App 移到路徑不含該字元的位置」。**R-10 讓這條適用於 `.occupiedByOther`**，D-w 讓它也適用於 `.unsupportedCharacter`。~~r12 以前：`.unsupportedCharacter` 給 snippet ＋「複製」~~ | translocated 的路徑是隨機臨時掛載點、下次開機就消失，把它交給使用者複製貼上等於發一張明天就過期的票。**r13 追加**：含不支援字元的路徑不會消失，但 `command` 是**裸路徑不加引號**（§10-10 明列「裸路徑遇到空白未測」），遞出去的是一份**我們自己剛說可能會壞**的設定檔，而 Codex 對壞掉的 hook 靜默跳過——**兩種 rejection 的共同點不是「路徑會消失」，是「我們不敢替他寫這一份」** |
| **D-t** | `translocated`／`inDownloads`／`pathRejection`／`currentExpectedContents` 四個**行程常數**在 `applicationDidFinishLaunching` 算一次存成欄位；`reprobeCodex()` 只重做檔案系統那一段 | 四者都是 `Bundle.main.bundleURL` 的純函式，在行程生命週期內不會變。r3 讓每次 `onOpen` 都重算一次 `SecTranslocateIsTranslocatedURL`（Security 框架呼叫）＋ 兩次 `resolvingSymlinksInPath` ＋ 產 12 個事件的 JSON——面板開啟延遲是這個專案量過、在意過的東西（`Installer.probe()` 的 128 µs 分解寫在生產碼註解裡）（r3 m3） |
| **D-u** | `Jargon.model` 要認得 Codex 的模型命名；**保留既有 Claude 家族演算法不動**，新分支排在它之前，判不出來一律沿用既有的「原樣回傳」 | fixture 進 repo 之後，既有 gate `FixtureCodeAnchorTests.everyFixtureModelIsMapped` **已經紅**（`Jargon.model("gpt-5.5")` 原字回傳）。那是本 change 必須修好的既有 gate，不是弱化對象。見 §4.9 |

### 0.4 persona-tester r1（NO-GO）之後的裁決（主 session 2026-09-21 拍板，D-v–D-ad）

persona r1 判 **NO-GO**（加權 5.68／門檻 6.0；兩條 S0；P2 = 5.2 低於自己的 ≥6 硬下限）。
報告的關鍵觀察值得逐字保留：**四個 persona 裡三個的失分不是來自 Codex 功能做錯，
而是來自既有的 Claude-only 表面沒有跟著這個新訊號一起更新**（S0-1 是 A7 的退場條件、
S1-1 是三個狀態字串、S1-2 是空狀態句）。那些表面在 diff 裡幾乎沒被動到，所以四道機器關卡
全綠是合理的——**它們守的是被改動的碼**。這正是 CLAUDE.md Lessons #4（整合接縫）的另一種形狀：
**A 新增了一個訊號，而 B 是一段沒有人想到要改的既有推導**。

**編號從 D-v 起**：`D-u` 已被 `Jargon` 的 Codex 命名用掉（§0.3），不重複使用。

**r14 折入 r13 review（0 BLOCKING／3 MAJOR／5 minor）**——**九條決策本身一條都沒有被推翻**，
改的全是「定義域少了維度」與「方法與自己的 mutation 相衝突」：
- **M1** → §4.10 契約 2 的乘積補上 `install` 與 `banner` 兩個維度 ＋ snippet 高度下限 ＋
  「780 在量完之前是提案」的先量後定程序；CX56 補兩格 mutation（含「把域縮回 r13 → 重現假綠」）。
- **M2** → CX51 從「三處都 `contains(statusLabel)`」改成**三條可分辨的斷言**
  （複合字面／裸葉節點恰 2／`healthLabel` 不得單獨出現），標題那一處下推到 CX50④ 的純函式層。
- **M3** → plan 的並行圖更正（`PanelModel*.swift` 上 T13b→T13f→T13g 必須序列）。
- **m1–m5／(c)** → CX52 改名並補 AuraCore 那一格、`#expect(` 基準改 2026、寬度量測擴到三處、
  CX50 定義域逐字寫 `InstallStateAllCases.all()`、T13l 補最壞高度組合一張圖、
  §8.1 補「為什麼不放 `L10nPanel.swift`」。

**r15 折入 r14 review（0 BLOCKING／1 MAJOR／3 minor）**——r13 的九條全部 closed、零 regression；
新開的四條都不是決策問題，是**前置條件與 pattern 的精確度**：
- **N1** → `T13i` 對 `T13b` 有**語意依賴**（`banner` 那一維在 `.codexConnected` 有自己的 kind 之前是惰性的），
  鏈圖補一條跨鏈邊，CX56 與 T13i 各補一句前置條件。**衝突檔表看不到語意依賴，這是它的已知盲區。**
- **n2** → CX52 兩格的 pattern 刻意不同（App 層有前導點抓讀取點／AuraCore 無前導點才涵蓋宣告處），
  並把 plan 的實測行更正為無點 5 命中／4 檔。
- **n3** → `install` 代表值改成「T13i 在最高的 `CodexState` 下實測四種 affordance，把最高的釘死」，
  不是挑 `.connect`。
- **n4** → snippet 上限住 AuraCore 純算術、**下限 6 列由 CX56 在 App 層用真實渲染量**，不進 AuraCore。

| 決定 | 內容 | 理由 | 被推翻的替代方案 | persona 反推（可驗證陳述） |
|---|---|---|---|---|
| **D-v**（S0-1） | `PanelBanner.Kind` 新增 **`.codexConnected`**；`PanelBanner.codexConnected(language:)` 改用它。`effectiveBanner` 的自動退場**依 kind 各自判**：`.connected`（Claude）維持「出現任何一列就退場」；**`.codexConnected` 只在出現 `agentLabel == Agent.codex.label` 的列時退場**（新增 `PanelModel.hasCodexRow`）。`.connected` 以外的 kind 仍無退場條件 | A7 的退場條件是**為 Claude banner 推導的**：那裡「出現一個 session」確實兌現了「下一個 session 起生效」。搬給 Codex 時條件沒有重新推導——出現一個 **Claude** 列對 Codex 什麼都沒兌現，而 D-m 強制的兩句話（下一個 session 起生效／Codex 會問你信任）是 F5 之下唯一的補償手段，被靜默抑制等於那條補償不存在 | ①「把 A7 整個拿掉，讓 `.connected` banner 也永遠留著」——那會退回 A7 修掉的毛病（banner 在條件兌現後還佔著頂端 40pt），而且是**弱化既有 gate 所守的行為**，不是修 bug；②「Codex 卡片在 `.connected` 也畫一張『已接上』卡」——與 D-j（零像素）和 §4.6 的「`.connected` 不畫說明卡」衝突，且卡片不是 banner，不會講那兩句話 | P3 按下「接上 Codex」之後，**不論面板上有沒有其他 agent 的列**，都會在同一次 refresh 看到「Codex 會問你一次是否信任」，因此知道下一步是去 Codex 按同意 |
| **D-w**（S0-2） | `.unsupportedCharacter` **也扣住 snippet**：`CodexHooksJSON.withheldSnippet(...)` 的條件從 `pathRejection == .mustMoveToApplications` 改成 **`pathRejection != nil`**。文案改成**問題＋解法兩句**（既有的「指名字元」那句 ＋ 新的出路句）。**「路徑被拒的說明與出路」只有一組文案，`.blockedByBundlePath`／`.occupiedByOther`／`.connectedStalePath` 三張卡片共用**，由 `pathRejection` 路由 | 與 R-5 一字不差的理由：**產品不賭裸路徑遇到空白**（§10-10 自陳未測），那就不能把一份含那條路徑的設定檔遞給使用者。現況是同一張卡片先說「這條路徑可能讓 Codex 讀到的設定檔壞掉」，下一段就給一份**內含同一條路徑**的 snippet ＋「複製」，而 Codex 對壞掉的 hook 是完全靜默跳過——**唯一被提供的出路，是同一張卡片剛剛宣告會壞的那條，且失敗無聲** | ①「在 snippet 裡把路徑加引號」——`command` 的解析方式未測（§10-10），加引號同樣是賭，只是換一邊賭；先扣住、等互動探針量到再開後續 change 恢復（§10-17 的解鎖條件）；②「照給但加警語」——P2 是**最會真的照著貼**的那個 persona，警語擋不住一顆「複製」按鈕 | P2 讀完 `.unsupportedCharacter` 卡片會知道下一步是「把 App 移到不含該字元的位置再回來」，而不是「貼上這段然後不知道為什麼沒動」 |
| **D-x**（S2-1） | `staleOtherCopyMessage` **拆成「中性開場」＋「依 rejection 的成因／出路」**：開場句只講可觀測的事實（這份設定指向另一個位置的 AgentAura），**刪掉「下次開機就會消失」子句**；成因與出路重用 D-w 那組（`.mustMoveToApplications` 用既有的兩句、`.unsupportedCharacter` 用指名字元＋新的出路句） | 那句話對 `.unsupportedCharacter` 是**可查證為假**——`~/My Apps/…` 不會消失。P2 是會去查證的人，**一句可查證為假的話比一句含糊的話更傷信任**。選「拆兩句」而不是「只刪子句」：刪掉子句之後兩個分支共用一句更含糊的話，而出路本來就不同（搬去『應用程式』／搬到不含該字元的位置）；拆開之後**零新增 L10n case**（成因／出路兩句 D-w 已經要寫），只是把既有那句改短 | 「只把『會消失』子句拿掉」——省一點行數，但兩個分支的出路仍然只有一種說法，而其中一種對 `.unsupportedCharacter` 是錯的指示（叫他搬去『應用程式』，可是他的問題是字元不是位置） | P2 在 #10／#11 兩張圖看到的**不再是位元組相同的兩張圖**：#11 指名那個字元並給對應的出路 |
| **D-y**（S1-1） | 面板三處狀態字串（**標題**／**footer chip**／**CTA 窄條 label**）改讀**同一個**新的推導字串 `PanelModel.statusLabel(_:)`：`codex == .connected` 時 = `L10nCodex.codexConnectedStatus(claudeHalf: install.healthLabel(l), language: l)`，否則**逐位元組等於** `install.healthLabel(l)`。**Codex 在前、Claude 在後**（見 §3.1）。**不新增 view**、不改 `install.healthLabel` 本身 | 三處目前都只反映 Claude，Codex 已接上且正在跑時全部寫「Not connected yet」——即本 codebase 自己在 `PanelModel.swift:154` 判過必修的 **S0-2 家族（同一張畫面兩句互相打架）**。組合（而不是另寫一套雙 agent 文案）是因為 `install.healthLabel` 有十五種變體（含 broken 的診斷字），另寫一份等於養第二份會 drift 的清單，而且會**弄丟 broken 狀態的診斷資訊** | ①「只在 chip 加一顆第二色點」——顏色不是字，離屏與真機都難斷言，且 P1 的問題是「沒有任何字承認 Codex 接上了」；②「Codex 已接上時不畫 Claude 的 CTA 窄條」——那會讓只用 Codex 的人**永遠看不到接上 Claude 的入口**，把一個文案問題換成一個功能問題 | P1 只接 Codex 時，面板頂端與 footer 都寫著「Codex connected」，因此知道**不必**再去按那顆「Connect」也能看到自己的 session；要接 Claude 才按它 |
| **D-z**（S1-2） | `PanelModel.emptyRowsMessage` 依 `codex` 分兩句：`codex == .connected` → 同時點名兩個 agent；否則**逐位元組等於**既有那句 | 「Connected to Codex…」banner 正下方一行寫「Once **Claude Code** starts running, each session will show up here.」——使用者剛接上的是 Codex，畫面卻只講 Claude。只在 `.connected` 分岔是為了守 D-j：沒裝 Codex 的人這句話位元組不變 | 「一律改成中性句（Once a session starts running…）」——那會讓**只用 Claude、沒裝 Codex** 的既有使用者也吃到一句更模糊的話，違反 D-j 的零 diff 精神 | P1／P3 接上 Codex 之後，空面板那句話點名了 Codex，因此知道「面板是空的」不代表接錯了 |
| **D-aa**（S1-3） | `.occupiedByOther` 且有 snippet 時，卡片多一行**合併指示**（把這些 entry 併進你現有的 hooks 物件，不要整份取代）＋一顆通往 help 的按鈕，**重用既有 `.openHelp` action**（不開第四個 `PanelAction`） | 卡片前一句才說「我們不會動你的檔」，下一句就遞出一份 **root `{"hooks": …}` 的完整替換檔**，中間沒有合併說明——這是整個流程裡唯一一個「手滑貼上就毀掉自己 hooks」的位置。合併指示存在於 `INSTALL.md:91-92` 與 `help-english.html:204`，但**都不在畫面上**。重用 `.openHelp`：新增第四個 action 會拖動 `PanelActionKind`／`samples`／`nonMenuKinds`／`panelActionsAreWired`／CX28 五條既有 gate 的定義域，換來的只是同一個目的地 | 「只在卡片上寫合併指示，不給 help 入口」——合併細節（要併哪幾個鍵、既有 hooks 物件長什麼樣）一行寫不完，而 help 兩份文件已經有那段 | P2 讀完卡片會知道下一步是「開啟說明、照著把 entry 併進去」，而不是「整份覆蓋掉自己的檔」 |
| **D-ab**（S1-4） | snippet 區塊**固定高度 ＋ 可捲**（`ScrollView` 吃一個**算好的固定值**，不是 `maxHeight`）；產品天花板：**Options 收合時，面板 `preferredContentSize.height ≤ 780pt`**，且「複製」按鈕與 footer 的渲染後 y 都落在天花板內 | 13 吋機顯示 Dock 時選單列下可用高度約 850pt，而 `05`／`07` 兩態的面板是 **944pt**：「複製」約在 848pt、footer 約在 919pt——**唯一的控制項連同整個 footer 都在畫面外，而且沒有捲軸可以救**（`PanelView` 只有 `sessionsCard` 有高度上限）。用固定值而不是 `maxHeight`：T22 已實測 `ScrollView` 垂直方向天生貪婪，只設上限會讓它吃滿外層提案高度，footer 位置又會變成「依畫布而定」 | 「把『複製』鈕移到 snippet 上方」——只救了按鈕，救不了 footer 與圖例列；面板總高度仍然超出螢幕，而超出的部分**不可捲** | P2 在 13 吋機上打開面板，不必捲整個 popover（也捲不動）就看得到「複製」與 footer；要讀完整 snippet 則在 snippet 區塊內捲 |
| **D-ac**（S1-5） | 「移除 Codex 掛載…」走**確認框**，比照 Claude 側 `confirmDisconnect` 的注入縫新增第四個 `confirmDisconnectCodex`；文案**點名 agent**（同 `L10nConfirmationAlerts.disconnectTitle` 已經點名 Claude Code 的既有形狀）。刪節號保留 | 目前 `.disconnectCodex` 直接進 `performDisconnectCodex()`，**一下點擊直接刪 `~/.codex/hooks.json`**，而列標題結尾有刪節號——macOS 慣例裡刪節號的意思是「按下去會先問你」。同一個 `.mount` 群組裡，相鄰的 Claude 那列會問、Codex 這列不問，**兩列不對稱**且不對稱的方向是「破壞性的那一邊比較沒有保護」 | 「拿掉刪節號」——省下一個注入縫，但留下「相鄰兩列一個問一個不問」的不對稱，而且刪除的是使用者機器上的真檔案（強 gate 情境） | P4 誤按「移除 Codex 掛載…」時會看到一個點名 Codex 的確認框，因此知道自己按到的是哪一側 |
| **D-ad**（S1-6／S1-7） | 證據渲染器：**#07 的 snippet 輸入維持真的含空白的路徑**（新政策下它會是「不給 snippet」的圖——**負向斷言必須餵正向輸入**，plan §0），並在 r13 落地後**重渲**；新增情境 **#12「`install: .notConnected` ＋ 一列活著的 Codex session」**兩語言 | 渲染器先前餵 `.unsupportedCharacter(" ")` 卻用不含空白的路徑產 snippet，**只看圖的人看不到 S0-2**；而本 change 的頭號情境（S1-1 的矛盾）在 11 張圖裡完全沒有證據。證據圖的失真與 gate 的失真是同一族問題：**輸入不對，結論就不是關於生產行為的** | 「等 r13 實作完再一次補圖」——那會讓 persona r2 在沒有修前基準的情況下評分，無法判斷「改好了」還是「換了個樣子」 | persona r2 可以直接對照 #07／#12 的修前修後兩版，判斷 S0-2／S1-1 是不是真的關掉了 |

**這批決策共同的邊界**：**不新增任何 SwiftUI view 型別**（DoD #11 執行檔已超標約 3 倍、#7 已超 377 行）。
所有修法都落在「`PanelModel` 的推導字串」「`L10nCodex` 的文案」「既有 view 內的分支與修飾子」
「一個注入縫」四類，`Sources/` 預估淨增見 §8.1 的 r13 段。

## 1. 目標與範圍

**做**：`--agent` 參數 · Codex 事件集合與 `Interrupt` 映射 · hooks.json 產生器（逐字 F14，唯一偏離 `timeout`）·
`CodexHookPathCheck`（三個消費者）· `CodexInstaller`（probe／connect／disconnect）·
`agent` 欄位貫穿 payload → 檔案 → state → UI 四段 · **`Jargon.model` 的 Codex 命名** ·
面板列標籤 · Codex 區塊與 Options 列 · snippet 複製（穿過路徑判定）· 內容憑證 ＋ round-trip 保證 ·
搬家偵測與一鍵重接 · **兩側互不干擾的不變式（R-8）** · 完整移除納入 · 文件與正典回寫 · 全鏈接線 gate。

**不做**：Codex 的 `error` 狀態（F2／F4）· 互動 TUI 探針（`PermissionRequest`／`Interrupt`／`Subagent*`
的形狀、hook 父行程的 `comm` 與 TUI 行程結構、含空白路徑＋引號的實測，全部在探針工具包待跑）·
分 agent 的聚合燈或分頁 · 動 `~/.codex/config.toml` · 動 Claude 側 `plugin/hooks/hooks.json` ·
自動偵測 Codex 是否已信任（F5）· 第三種 agent 的擴充機制（YAGNI）。

## 2. 架構總覽

```
Codex CLI ──(12 events, F2)──▶ ~/.codex/hooks.json ──▶ <abs>/aura-hook --agent codex  （逐字 F14，timeout 3）
Claude Code ─(19 events)────▶ ~/.claude/skills/agentaura → bundle plugin → aura-hook   （無參數＝claude）
                                                              │ stdin: hook JSON (F3)
                                                              ▼  兩側共用同一顆二進位、同一個狀態目錄（R-8）
                             AgentArgument.agent(argv) ──▶ Agent(.claude / .codex)
        HookPayload(data:) ──▶ MergeRules.merge(payload, agent:) ──▶ SessionSnapshot(agent:)
                                                              ▼ ~/.agentaura/sessions/<id>.json
        PipelineGraph ──▶ SessionReducer ──▶ SessionState(agent:) ──▶ PanelRow(agentLabel:) ──▶ PanelRowView
                                                                         └─ meta 走 Jargon.model（§4.9）

啟動時算一次（D-t）：RunningBundle.isTranslocated()/isInDownloads()
        └──▶ pathRejection = CodexHookPathCheck.rejection(...)      三個消費者：
             currentExpectedContents = CodexHooksJSON.json(...)     ① 路由層 CodexState
                                                                    ② performConnectCodex() 前置 guard（R-9）
                                                                    ③ 執行層 CodexInstaller.connect
             codexSnippet = (rejection == .mustMoveToApplications) ? nil : snippet(...)（R-10）

reprobeCodex()：只重做 installer.probe() ──▶ CodexState.from(obs, recorded, currentExpected, pathRejection)
   ▲ connect(json:translocated:inDownloads:) / disconnect(ifContentsEqual:)
   └── 六態 → §4.6 表
```

| 單元 | 層 | 狀態 | 職責 |
|---|---|---|---|
| `Agent` | AuraCore | 新 | `enum Agent: String, CaseIterable, Sendable { case claude, codex }`；`storedRawValue`（`.claude` → nil）；`init(stored:)`；`label`（`.claude` → nil） |
| `AgentArgument` | AuraCore | 新（同檔） | `agent(from argv:) -> Agent`：純函式，兩種寫法，未知一律 `.claude` |
| `EventMapping` | AuraCore | 改 | `+ codexEvents`（12 個，F2）、`+ codexOnlyEvents = ["Interrupt"]`；`effect` 加 `case "Interrupt"`。**`handledEvents` 一個字都不動** |
| `CodexHooksJSON` | AuraCore | 新 | `agentFlag`、`hookTimeoutSeconds = 3`（**單一常數**）；`json(hookBinaryPath:) -> Data`；`snippet(hookBinaryPath:) -> String` |
| `CodexHookPathCheck` | AuraCore | 新 | `enum Rejection { mustMoveToApplications, unsupportedCharacter(Character) }` ＋ **`RejectionKind: String, CaseIterable`** ＋ `Rejection.samples(_:)`（窮盡 switch，**不得有 `default`**）；`unsupportedCharacters: Set<Character>`；`rejection(translocated:inDownloads:hookBinaryPath:) -> Rejection?`。**零 I/O、零平台 API** |
| `CodexObservation` | AuraCore | 新 | `codexHomeIsDirectory`、`entryType`、`contents: Data?`（D-q）、`displayPath: String?` |
| `CodexState` | AuraCore | 新 | 六態（§3）；`CodexStateKind` ＋ `samples(_:)`（兩層都不得有 `default`，D-r）；`from(_:recordedContents:currentExpectedContents:pathRejection:)` 窮盡、零 I/O |
| `CodexFailure` | AuraCore | 新 | 七個 case：`codexHomeMissing`／`alreadyExists`／`writeFailed(Int32)`／`notOurs`／`unreadable(Int32)`／`mustMoveToApplications`／`unsupportedPathCharacter(Character)` |
| **`Jargon`** | AuraCore | **改** | `model(_:)` 前面加 Codex 家族分支（§4.9）。既有 Claude 家族演算法**一行不動** |
| `CodexInstaller` | AuraHookFile | 新 | `Sendable`；兩個 `URL`；`probe()`／`connect(json:translocated:inDownloads:) throws -> Data`／`disconnect(ifContentsEqual:) throws`。**只碰 `<codexHome>/hooks.json`** |
| `CodexHookStore` | App | 新 | `@MainActor` ＋ 注入 `UserDefaults`；key `AgentAuraCodexHookContents`；`Data` 進、`Data` 出，round-trip 有 gate（CX31） |
| `PanelAction` / `PanelActionKind` | AuraCore | 改 | `+ .connectCodex`／`.disconnectCodex`／`.copyCodexSnippet`。**不新增第四個**。`samples` 的 doc comment 補「**不得有 `default`**」（r3 m2 順手補既有註解） |
| `OptionsMenuModel` | AuraCore | 改 | `rows(...)` 多吃**兩個**參數 `codex: CodexState` ＋ **`codexPathRejection: Rejection?`**（後者不進 case 的 payload，理由見 §3）；列數依 §4.6；`nonMenuKinds` 加 `.copyCodexSnippet` |
| `PanelModel` | AuraCore | 改 | **三個**新欄位：`+ codex: CodexState`、`+ codexSnippet: String?`、**`+ codexPathRejection: CodexHookPathCheck.Rejection?`**；`make(...)` 新參數**不給預設值** |
| `PanelRow` | AuraCore | 改 | `+ agentLabel: String?` |
| `SessionSnapshot` / `MergeRules` / `SessionReducer` / `SessionState` | AuraCore | 改 | `agent: String?` 一路帶到 `SessionState.agent: Agent`；`merge(...)` 多一個 `agent:`（無預設值） |
| `CodexSectionView` | App | 新 | 六態 ＋ 兩種 Rejection 的分支（§4.6 表）。**不吃 `InstallState`** |
| `PanelRowView` | App | 改 | 第一行 `HStack` 內加標籤 |
| `AppDelegate+Codex.swift` | App | 新 | **四個行程常數欄位（D-t）** ＋ `reprobeCodex()`／`performConnectCodex()`（**第一行 guard**，R-9）／`performDisconnectCodex()`／`performCopyCodexSnippet()` |
| `Uninstaller` | App | 改 | `run()` 在 `erasePersistentDomain()` 前多一步 codex disconnect |

**設計選擇**
1. **一條資料流，兩個入口**：Codex 與 Claude 共用 `~/.agentaura/sessions/`、共用 `MergeRules`、共用聚合。
2. **兩份 hooks.json 各自的來源集合分離**（§4.2），都是 source-derived。
3. **保本動作全部在執行層**，不靠上層路由先擋（S0-1(ii)）。
4. **憑證存的就是它要比的東西**（R-2）；文字鍵的 round-trip 由 CX31 專守。
5. **「路徑能不能用」是一個判定、三個消費者**（R-5 ＋ R-9）：路由層決定畫按鈕還是畫解釋，
   `performConnectCodex()` 決定要不要動手，執行層是最後一道。**按了才失敗的按鈕比沒有按鈕更糟；
   而「按了會先刪檔再失敗」比兩者都糟**——這正是 r3 B1 的形狀（§4.6）。
6. **兩側互不干擾是契約不是巧合**（R-8）：共用二進位、共用狀態目錄，但兩側的安裝物件
   （`~/.claude/skills/agentaura` 的 symlink vs `~/.codex/hooks.json` 的檔案）互不重疊，
   §4.8 把它寫成不變式並配兩層 gate。

## 3. 資料模型

```swift
public enum Agent: String, Sendable, Equatable, CaseIterable {
    case claude, codex
    public init(stored: String?)            // nil／未知 → .claude
    public var storedRawValue: String?      // .claude → nil
    public var label: String?               // .claude → nil；.codex → "Codex"（產品名不進 L10n）
}
public enum AgentArgument { public static func agent(from argv: [String]) -> Agent }

extension EventMapping {
    public static let codexEvents: Set<String>      // 12 個（F2）
    public static let codexOnlyEvents: Set<String>  // ["Interrupt"]
}

public enum CodexHooksJSON {
    public static let agentFlag: String                         // "--agent codex"
    public static let hookTimeoutSeconds: Int                   // 3（R-4；12 個事件唯一來源）
    public static func json(hookBinaryPath: String) -> Data     // 逐字 F14，唯一數值偏離是 timeout
    public static func snippet(hookBinaryPath: String) -> String
}

public enum CodexHookPathCheck {
    public enum RejectionKind: String, Sendable, CaseIterable {  // r4／r3 m1
        case mustMoveToApplications, unsupportedCharacter
    }
    public enum Rejection: Equatable, Sendable {
        case mustMoveToApplications
        case unsupportedCharacter(Character)
        public var kind: RejectionKind                           // 窮盡 switch，不得有 default
        public static func samples(_ k: RejectionKind) -> [Rejection]   // 同上
    }
    public static let unsupportedCharacters: Set<Character>      // 八個：空白 ' " $ ` \ \n \t（見 §4.4）
    public static func rejection(translocated: Bool, inDownloads: Bool,
                                 hookBinaryPath: String) -> Rejection?
}

public struct CodexObservation: Equatable, Sendable {
    public enum EntryType: Equatable, Sendable, CaseIterable { case absent, regularFile, directory, symlink, other }
    public let codexHomeIsDirectory: Bool
    public let entryType: EntryType
    public let contents: Data?          // 只有 regularFile 且 ≤ 64 KiB 才填（D-q）
    public let displayPath: String?
}

public enum CodexState: Equatable, Sendable {                   // 帶 payload → 不能 CaseIterable（D-r）
    case unavailable, notConnected, connected, connectedStalePath, occupiedByOther
    case blockedByBundlePath(CodexHookPathCheck.Rejection)
    public var kind: CodexStateKind                             // 窮盡 switch，不得有 default
    public static func samples(_ kind: CodexStateKind) -> [CodexState]
        // .blockedByBundlePath 那一格 = RejectionKind.allCases.flatMap(Rejection.samples)
        //                                 .map(CodexState.blockedByBundlePath)
    public static func from(_ o: CodexObservation, recordedContents: Data?,
                            currentExpectedContents: Data,
                            pathRejection: CodexHookPathCheck.Rejection?) -> CodexState
}
public enum CodexStateKind: String, Sendable, CaseIterable {
    case unavailable, notConnected, connected, connectedStalePath, occupiedByOther, blockedByBundlePath
}
```

**`pathRejection` 不進任何 case 的 payload**（T07 review 的主管問題 4 裁決）——它是**橫跨**
`.connectedStalePath` 與 `.occupiedByOther` 的 **UI 輸入**：`rows(codex:codexPathRejection:)` 另傳一個參數，
`PanelModel` 也因此有**三個**新欄位（`codex`／`codexSnippet`／`codexPathRejection`）。
**區分原則**：只有 **`.blockedByBundlePath(Rejection)` 的 payload 是構成性的**——判定表第 6 列的
成立條件**就是**它非 nil；`pathRejection` 對第 2／3 列是**附帶的**（判定表寫「任意」，`from(...)`
走到 `.connectedStalePath` 根本不看它）。把附帶資料塞進 payload 有三個具體代價：
① `Equatable` 被污染——`.connectedStalePath(nil) != .connectedStalePath(.mustMoveToApplications)`，
但那是**同一個世界狀態**（磁碟==憑證≠現在預期），而 CX19／CX34 都靠 `Equatable` 比對；
② `samples` 膨脹成 `[nil] + 全部 Rejection`，把每一條聯集 gate 的定義域放大，其中多數在行為上相同；
③ **R-10 要求 `.occupiedByOther` 在 `pathRejection == .mustMoveToApplications` 時不給 snippet**，
若只放進 `.connectedStalePath` 的 payload，`.occupiedByOther` 仍得另外拿一次 → 兩套機制並存。

**兩層 `samples` 的 `switch` 都不得有 `default`**（D-r／r3 m2）——那正是這兩個平行 Kind 型別
存在的**唯一**理由：新增一個 case 時編譯器會擋下來。加一個 `default: []` 看起來像防禦性寫法，
實際是把整條定義域推導鏈靜默關掉。這句話要**逐字**寫進兩個 `samples` 的 doc comment，
並順手補進既有的 `PanelAction.samples`（一行，零風險）。

判定表（`CodexState.from`，窮盡、零 I/O；**由上而下第一個命中者勝**；**r4 不動這個列序**）：

| # | `codexHomeIsDirectory` | `entryType` | 磁碟 vs `recordedContents` | 磁碟 vs `currentExpectedContents` | `pathRejection` | → |
|---|---|---|---|---|---|---|
| 1 | false | 任意 | — | — | 任意 | `.unavailable` |
| 2 | true | `regularFile` | 兩者非 nil 且**逐位元組相等** | **相等** | 任意 | `.connected` |
| 3 | true | `regularFile` | 兩者非 nil 且**逐位元組相等** | **不等** | 任意 | `.connectedStalePath` |
| 4 | true | `regularFile` | 其餘（任一 nil／不等／> 64 KiB 沒讀） | — | 任意 | `.occupiedByOther` |
| 5 | true | `directory`／`symlink`／`other` | — | — | 任意 | `.occupiedByOther` |
| 6 | true | `absent` | — | — | **非 nil** | `.blockedByBundlePath(r)` |
| 7 | true | `absent` | — | — | nil | `.notConnected` |

**第 2／3 列排在第 6 列之前是刻意的**：磁碟上已經有我們的檔時，該講的是那個檔的狀態。
**但那條「正確的引導」在 r3 是錯的**——r3 讓使用者按下「重新接上」後先 `disconnect`，
於是一個只是打開了 DMG 副本的人，會把他指向 `/Applications` 真本、**還在運作**的
`~/.codex/hooks.json` 弄丟。R-9 的處置是**不動列序**，改在 UI 與 `performConnectCodex()`
兩處讓那個按鈕在 `pathRejection != nil` 時**根本不存在**（§4.6）。

`SessionSnapshot` 加 `public var agent: String? = nil`（CodingKey `agent`）。**必須是 Optional**。
`UserDefaults`（domain `io.agentaura.app`）新增**一個** key：`AgentAuraCodexHookContents`。

### 3.1 雙 agent 狀態字串（r13／D-y、D-v、D-z）

r13 新增的型別面變動（**零新 view 型別**）：

```swift
extension PanelBanner {
    public enum Kind { case connected, alreadyConnected, disconnected, error, codexConnected }   // D-v：+1 case
}

extension PanelModel {
    /// D-v：面板上有沒有任何一列是 Codex 的——`.codexConnected` banner 的退場條件。
    /// 用 `agentLabel == Agent.codex.label`（不是 `agentLabel != nil`）：第三種 agent
    /// 進來時這個判斷仍然只認 Codex，不會靜默把別人的列當成 Codex 的列。
    public var hasCodexRow: Bool

    /// D-y：三處狀態字串（標題／footer chip／CTA 窄條 label）的唯一 oracle。
    /// `codex == .connected` → 加上 Codex 子句；否則**逐位元組等於** `install.healthLabel(l)`。
    public func statusLabel(_ language: Language) -> String

    /// D-z：空列訊息依 `codex` 分兩句（`.connected` 才點名 Codex）。
    public var emptyRowsMessage: String    // 既有欄位，行為改變
}

extension L10nCodex {
    /// D-y：`"<Codex 子句> · <Claude 名字>：<claudeHalf>"` 的雙語模板（帶參數的 static func，
    /// 同 `unsupportedCharacterExplanation(_:language:)` 的既有形狀，不新增 enum case）。
    public static func codexConnectedStatus(claudeHalf: String, language: Language) -> String
}
```

**`statusLabel` 的規則只有一條**：

```
statusLabel(l) = (codex == .connected)
               ? L10nCodex.codexConnectedStatus(claudeHalf: install.healthLabel(l), language: l)
               : install.healthLabel(l)
```

三個刻意的選擇，各自有理由：

1. **只有 `.connected` 算「Codex 已接上」**。`.connectedStalePath` 的檔案雖然在，但它指向另一個位置的
   AgentAura——說「Codex connected」會是**下一個謊**，而這批修復的主題正是「畫面不得宣稱它無法證實的事」。
2. **Codex 子句在前、Claude 半在後**。footer chip 是 `"\(label) · v\(version)"`、`lineLimit(1)`、
   `truncationMode(.tail)`：**被截掉的一定是尾巴**。新增的資訊擺在頭，截斷時先犧牲版本號，不會犧牲
   「Codex 已接上」這件剛剛才被 persona 判為 S0 的事。
3. **Claude 半原封不動組合 `install.healthLabel`，不另寫一套雙 agent 文案**。`healthLabel` 有十五種變體
   （含 `broken` 的診斷字），另寫一份等於養第二份會 drift 的清單，而且會**弄丟 broken 狀態的診斷資訊**
   ——使用者的 Claude hook 壞了、Codex 好著，chip 仍必須講得出是哪一種壞。

**完整矩陣（每一格都有字；`v1.4.2` 為示意版本號，英文示例）**：

| Claude（`install`） | Codex（`CodexState`） | 標題（`PanelView` 頂端） | footer chip | CTA 窄條 label |
|---|---|---|---|---|
| 未接上（`.notConnected`／`.broken`／`.claudeNotFound`） | `.unavailable` | `Not connected yet` | `Not connected yet · v1.4.2` | `Not connected yet` |
| 未接上 | `.notConnected`／`.occupiedByOther`／`.blockedByBundlePath`／`.connectedStalePath` | `Not connected yet` | `Not connected yet · v1.4.2` | `Not connected yet` |
| 未接上 | **`.connected`** | **`Codex connected · Claude Code: Not connected yet`** | **`Codex connected · Claude Code: Not connected yet · v1.4.2`** | **`Codex connected · Claude Code: Not connected yet`** |
| 已接上（`.connected`） | `.unavailable` | （session 計數句，例 `2 sessions running`） | `Connected · v1.4.2` | （不畫——`.connected` 沒有 CTA） |
| 已接上 | `.notConnected`／`.occupiedByOther`／`.blockedByBundlePath`／`.connectedStalePath` | （session 計數句） | `Connected · v1.4.2` | （不畫） |
| 已接上 | **`.connected`** | （session 計數句） | **`Codex connected · Claude Code: Connected`**＋` · v1.4.2` | （不畫） |

**三處各自由哪一層守**（r14／review M2）：**標題**住在 AuraCore（`PanelModel.title(for:install:language:)`），
所以由 **CX50④** 在純函式層逐位元組比對；**footer chip** 與 **CTA 窄條** 住在 App 層，
由 **CX51** 用三條可分辨的斷言守（三處渲染的是同一個字串，單純 `contains` 分辨不出是哪一處壞了）。
**站點集合**由 **CX52** 兩格掃描（App 層命中 0 ＋ AuraCore 具名檔案集合）。

**標題那一欄的不對稱是刻意的**：Claude 已接上時標題走的是 `PanelViewModel.title`（session 計數句），
那句話本來就**不分 agent**、而且是真的（它數的是所有 agent 的列），沒有要修的謊。
只有「非 connected 時改用 `install.healthLabel`」那條既有分支（`PanelModel.title(for:install:language:)`，
T11 commit2 為了修 S0-2 而加的）需要換成 `statusLabel`——**修的是同一族毛病的下一個實例**。

**`.unavailable` 那兩列是 D-j 的零 diff 保證**：沒裝 Codex 的人，三處字串**逐位元組**與 r12 相同。
這也是 CX50 的第一條斷言（不是「看起來一樣」，是 `==`）。

**`emptyRowsMessage`（D-z）的矩陣更小**，因為它只在「Claude 已接上（或無 CTA）且 rows 空」時被畫到：

| Codex | 英文 | 中文 |
|---|---|---|
| 非 `.connected`（含 `.unavailable`） | `Once Claude Code starts running, each session will show up here.`（**與 r12 逐位元組相同**） | 「Claude Code 開起來、開始跑之後，這裡會列出每個 session。」（同上） |
| **`.connected`** | **`Once Claude Code or Codex starts running, each session will show up here.`** | **「Claude Code 或 Codex 開起來、開始跑之後，這裡會列出每個 session。」** |

## 4. 核心技術

### 4.1 `--agent` 參數（D-d）
`aura-hook/main.swift` 新增一行 `let agent = AgentArgument.agent(from: CommandLine.arguments)`
往下傳給 `MergeRules.merge`。由左至右找第一個 `--agent <值>` 或 `--agent=<值>`；大小寫敏感；
任何不匹配一律 `.claude`。**永不 `exit(非零)`、永不寫 stdout／stderr**。

### 4.2 事件集合與 `Interrupt` 接縫（本 change 最容易踩的地方）

- **Claude Code 對 hooks.json 是全有全無解析——這是跨機器實測，不是本機驗證器說的**（T03 review M1）：
  2026-09-15 在**同事的機器**上，一個平台不認得的 `PostModelSwitch` 讓**整個 plugin 不運作**，
  其餘合法 event 一起陪葬（專案記憶 `distribution-and-hook-compat`）。
  **本機 `claude plugin validate --strict` 對未知 event 只給 warning「entry ignored at runtime」**，
  看起來像是只有那一條被忽略——**本機通過不構成反證**，這與 Claude Code 的版本有關。
  沒有這句限定語，下一個維護者讀到「整份拒載」、順手跑一次本機 validator 看到只是 warning，
  最合理的推論就是「這段誇大了」，然後把 CX2／CX5 當成過度防禦而放寬。
  `registeredEventsMatchHandledEvents` 是雙向等式，所以 **`Interrupt` 一旦進 `handledEvents`**，
  那條 gate 會要求 Claude 的 hooks.json 也註冊它 → Claude 側整份 hooks 失效。
  **一個「把對照表補齊」的善意動作，後果是產品對 Claude 使用者完全停止運作。**
- `codexEvents`（12 個）獨立常數，`codexOnlyEvents = ["Interrupt"]`；`Interrupt` 只進 `effect` 的 switch。
  **前提**：F2 沒有回答「Claude Code 自己認不認得 `Interrupt`」；我們據以行動的是既有事實
  （`handledEvents` 19 個名字裡沒有它、Claude 側 hooks.json 從未註冊過它）。CX5 守的是「沒有註冊」。
- **`Interrupt` 事件 ≠ `is_interrupt` 欄位**：後者是 `HookPayload.isInterrupt`（使用者 Ctrl+C
  中斷了一個 **tool**，刻意不計入 `tool_failures`）。兩者 doc comment 互相點名。
- 四條 gate（CX2／CX3／CX4／CX5）**加上第四道平台自己的防線**：**`claude plugin validate --strict`**
  （DoD #16 要求零 warning）對註冊 `Interrupt` 會**直接失敗**（reviewer 實測：`unknown hook event;
  entry ignored at runtime` ＋ `--strict` 視 warning 為 error）。**它是唯一一道不依賴我們自己寫的斷言的防線**
  ——問的是平台，不是我們對平台的理解（gate 哲學第 1 條）。**CX4 是必要的**：`round4-codex.ndjson` **零筆 `Interrupt`**
  （`SessionStart` 4／`UserPromptSubmit` 4／`Stop` 4／`SessionEnd` 4／`PreToolUse` 1／`PostToolUse` 1），
  沒有它，刪掉 `case "Interrupt"` 整行全部 gate 維持綠。
- **後果**：Codex 沒有 `PostToolUseFailure` 也沒有 `StopFailure`（F2），`tool_response` 只是字串（F4）
  → **Codex 的 session 永遠不會讓燈變紅**（§10-2）。

### 4.3 hooks.json 產生器：逐字照 F14，唯一偏離是 `timeout`（R-1 ＋ R-4）

```
{ "hooks": { "<event>": [ { "matcher": "", "hooks": [ { "type": "command",
             "command": "<abs>/aura-hook --agent codex", "timeout": 3 } ] } ], ...（12 個，事件名排序） } }
```
- 事件清單從 `codexEvents` 排序推導，**不寫第二份**；CX6 驗鍵集合恰等於它，
  **並把 12 個事件的 entry 逐一逐字對 F14 比對**（抽樣有 11/12 的機率看不到特例）。
- **`matcher: ""` 不可省**：F14 的「未測」欄第一項就是它。**不能拿 Claude 側當佐證**——
  Claude 的 19 個 entry 裡只有 `Notification` 帶 `matcher`，而且 Codex 與 Claude 是**兩個解析器**，
  F7 已證明它們寬容度相反（Codex 忽略不認得的事件名，Claude 整份拒載）。
- **`timeout: 3`（R-4）——對 F14 唯一的數值偏離**：目的是避免 F13 的 clamping 警告落在使用者的
  stderr；**「3 不觸發警告」是推論不是事實**（從沒量過 ≤ 3 的值）；三種結果都可承受；
  12 個統一是因為**產生器從單一常數推導**，逐事件不同值等於養第二份清單。
  代價是失去 F1 賴以斷言「Codex 讀到了」的唯一便宜訊號，補償寫進 INSTALL troubleshooting。
  CX6 為這個刻意偏離配一格自己的 mutation（**改回 5 → 必紅**）。
- **不寫 `async`**（F14 未測欄第二項）；`command` **不加引號**（F14 是裸路徑）。
- `snippet(hookBinaryPath:)` **就是 `json(...)` 的文字形式**（同一個產生器）。

### 4.4 路徑判定（R-5）與 `CodexInstaller` 的三個動作

`CodexHookPathCheck.rejection(...)`：① `translocated || inDownloads` → `.mustMoveToApplications`
（`RunningBundle` 的 doc comment 實測記載：Gatekeeper 把「從下載的 zip／DMG 直接雙擊」的 app
跑在**唯讀、隨機命名的臨時掛載點，那個路徑下次啟動就消失**；本 repo 上一個 change 才剛做了
雙擊安裝的 `.dmg`）；② 否則掃路徑，**第一個**命中 `unsupportedCharacters` 的字元 →
`.unsupportedCharacter(那個字元)`；③ 否則 nil。

**`unsupportedCharacters` 目前是八個**：空白、`'`、`"`、`$`、`` ` ``、`\`、**換行、tab**（T04 review M3）。
**這是啟發式，不是完備集合**——它的定位是「**已知最可能出問題、且不會過度拒絕的最小集合**」，
不是「所有會出問題的字元」。刻意**未擋**的包括 `(`／`)`（「AgentAura (beta)」「Projects (2026)」
這類資料夾名很常見）、`;`／`&`／`|`／`>`／`<`／`*`／`?`。理由：擋它們的前提是「Codex 把 `command`
交給 shell」，而**我們並不知道它是不是**（§10-10：`command` 的解析方式未測，R-7 已把量測移到互動探針）；
在不知道的情況下擴到二十幾個字元會過度拒絕。換行與 tab 是例外——**兩種解析假設下都危險**
（就算只是「用空白切分參數」也會裂開），零過度拒絕風險，所以納入。
完整集合**待互動探針量到 Codex 的實際解析方式再決定**。
下一個人看到 `(` 沒擋時，要知道那是**已知的取捨**，不是漏寫。
**CX33 的逐字元格從這個生產常數推導**，所以集合改大改小，gate 的定義域自動跟上（現在是 8 格）。

**注意**：既有 `Installer.connect` 的 `mustMoveToApplications` 擋的**只有** translocated 與
`~/Downloads`，**沒有**「必須在 `/Applications`」。所以 `~/Applications/`、`~/My Apps/` 這類
合法位置**可以含空白**——「幾乎永遠不觸發」不成立。

**三個消費者，一個判定**（R-5 ＋ R-9）：路由層（`CodexState.from` 的 `pathRejection`）／
`performConnectCodex()` 的前置 guard／執行層 `CodexInstaller.connect` 的第一行。

**三個動作**：
- **`probe()`**：`lstat(codexHome)` → `lstat(hooks.json)` → 只有 `regularFile` **且 ≤ 64 KiB**（D-q）
  才 `open(..., O_RDONLY | O_NOFOLLOW)` 讀內容。
- **`connect(json:translocated:inDownloads:)`**：路徑 guard → `open(path,
  O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC, 0o644)`（D-i）→ 寫 → close → 回傳寫出去的 `Data`。
  `codexHome` 不是目錄時 throw `.codexHomeMissing`（**不建立它**）。
  **`EEXIST` 一律 → `.alreadyExists`**（四種佔用形狀實測全部 `EEXIST`，沒有 `EISDIR`）。
- **`disconnect(ifContentsEqual:)`**：`O_RDONLY|O_NOFOLLOW` → `fstat` 確認 `S_IFREG` → 讀 →
  **逐位元組比對** → 不符 throw `.notOurs`（**不刪**）→ 相符 → **`unlink` 前再 `lstat` 一次路徑，
  比對 `fstat` 拿到的 `(dev, ino)`，不同就放棄** → `unlink`。absent 冪等成功。

**TOCTOU**：POSIX 沒有「內容相符才 unlink」的原子原語（macOS 也沒有 `funlinkat`），
窄窗已用同 fd 連續操作 ＋ `(dev, ino)` 二次確認縮到最小（§10-6）。寫入那一側沒有這個問題。

**保本動作擋不住「在錯誤的時機正確地執行」**（r3 B1 的教訓）：`disconnect` 的兩道保護
（逐位元組比對、`(dev,ino)` 複查）在那個情境下**全部生效**，檔案確實是我們的，所以刪得理直氣壯。
要擋的是**呼叫它的時機**，那是 R-9。

### 4.5 內容憑證、round-trip 與完整移除（R-2 ＋ r2 M6）
- `connect` 成功 → `CodexHookStore.write(bytes)`；`disconnect` 成功 → `clear()`。
- **round-trip 是獨立的失敗面**：`connect` 回 `Data`、`disconnect` 比對 `Data`，中間經過一個
  **文字**鍵。任何編碼不對等 → `disconnect` 永遠比不中 → `.notOurs` → **永遠刪不掉自己寫的檔**
  → 完整移除留殘留 → `verify-uninstall.sh` 第 7 項 FAIL。CLAUDE.md 逐字寫著
  「移除乾淨是測試能力的前提」，所以由 **CX31** 專守（輸入用**真正的產生器輸出**）。
- `Uninstaller.run()`：`loginItem.set(false)` → `installer.disconnect()` →
  **`codexInstaller.disconnect(ifContentsEqual: store.contents)`（`try?`）** → `StateDirectoryEraser.erase` →
  `erasePersistentDomain()` → `recycleBundleAndTerminate()`。codex 那步**必須在清 domain 之前**（D-n）。
- `verify-uninstall.sh` 第 7 項用內容判準（D-o），且**必須可以單獨執行**（`--only 7`）：
  第 1–6 項查**真實** `$HOME`，開發機上本來就會 FAIL、整支本來就非零退出——
  用整體 exit code 當判準的 gate 對 mutation 不會紅；整支還會跑 `osascript` 與 `sfltool dumpbtm`。

### 4.6 面板、Options 與「重新接上」的時機（R-9 ＋ R-10）

**這張表吃兩個輸入**：`CodexState` **與** `pathRejection`（後者不是 state 的 payload，見 §3 的區分原則）。

| `CodexState` ＋ `pathRejection` | 面板 | snippet | Options（`.mount` 群組） |
|---|---|---|---|
| `.unavailable` | **什麼都不畫**（D-j） | — | 零列 |
| `.notConnected` | 單行提示 ＋ 按鈕（R-3，一律如此） | — | 恰一列「接上 Codex」（`.connectCodex`） |
| `.connected` | 不畫說明卡。**r13（D-v）**：剛接上時的 `.codexConnected` banner **不因為畫面上有別的 agent 的列而消失**——只有出現 `agentLabel == Agent.codex.label` 的列才退場 | — | 恰一列「移除 Codex 掛載…」，**r13（D-ac）：走確認框**（點名 Codex），不是一下點擊直接刪檔 |
| `.connectedStalePath`，`pathRejection == nil` | 「App 移動過，要重新接上」**＋ 按鈕** | — | 恰**兩**列：「重新接上 Codex」（`.connectCodex`）＋「移除 Codex 掛載…」 |
| **`.connectedStalePath`，`pathRejection != nil`** | **r13（D-x）：拆成「中性開場」＋「依 rejection 的成因／出路」兩段**。開場＝「這份設定指向另一個位置的 AgentAura」（只講可觀測的事實，**不預設成因**，r4 m2：使用者同時有正本與一份 DMG／備份副本時，從副本啟動就會落進這一列，而 App 其實**沒有**移動過）；第二段**重用 `.blockedByBundlePath` 那組**：`.mustMoveToApplications` → 「這個副本跑在一個下次開機就會消失的位置」＋移到『應用程式』；`.unsupportedCharacter(c)` → 指名字元 ＋ 移到不含該字元的位置。**不給按鈕**（R-9）。~~r12：兩種 rejection 共用一句，其中「下次開機就會消失」對 `.unsupportedCharacter` **可查證為假**~~ | — | **恰一列**「移除 Codex 掛載…」（不給「重新接上」；r13 起該列走確認框，D-ac） |
| `.occupiedByOther`，`codexSnippet != nil`（⇔ `pathRejection == nil`） | 「你已經有自己的 `~/.codex/hooks.json`，我們不會動它」＋ **r13（D-aa）：一行合併指示（把這些 entry 併進你現有的 hooks 物件，不要整份取代）** ＋ 可選取 snippet（**r13／D-ab：固定高度＋可捲**）＋「複製」＋ **通往說明的按鈕（重用 `.openHelp`）** | 有 | 零列 |
| **`.occupiedByOther`，`codexSnippet == nil`** | 同上的開場句，但 snippet 區塊換成**依 rejection 分流**的出路句（r13／D-w：`.mustMoveToApplications` → 先把 App 移到『應用程式』，我們才給得出一份不會過期的設定；`.unsupportedCharacter(c)` → 指名字元 ＋ 先把 App 移到路徑不含該字元的位置）。**合併指示與 help 按鈕在這一格不畫**——沒有東西可併 | 無 | 零列 |
| `.blockedByBundlePath(.mustMoveToApplications)` | 解釋 ＋ 出路＝把 App 移到「應用程式」。**不給 snippet**（D-s） | 無 | 零列 |
| `.blockedByBundlePath(.unsupportedCharacter(c))` | **r13（D-w）**：解釋（**指名是哪個字元**）＋ 出路＝**把 App 移到路徑不含該字元的位置（例如『應用程式』），再回來重新接上**。**不給 snippet**——條件已經是「有 rejection 就扣住」。~~r12：給 snippet ＋「複製」~~ | **無** | 零列 |

**`codexSnippet` 的產生穿過路徑判定**（R-10；**r13／D-w 擴大條件**）：
`codexSnippet = (pathRejection != nil) ? nil : CodexHooksJSON.snippet(...)`
（~~r12：`pathRejection == .mustMoveToApplications`~~）。
**只有一個判定式，沒有第二處重算**——`CodexHooksJSON.withheldSnippet(hookBinaryPath:pathRejection:)`
是唯一實作點，`CodexRuntime` 是唯一生產呼叫點。
理由與 D-s 一字不差：那個路徑是隨機臨時掛載點，**P2 是最會真的照著貼的那個 persona**，
而失效是靜默的（F5）。r3 把這扇門留著沒關——`.occupiedByOther`（第 4／5 列）優先於
`.blockedByBundlePath`（第 6 列），所以「有自己的 hooks.json ＋ 從 DMG 開」會拿到一份
`command` 指向 `/private/var/folders/.../AppTranslocation/<uuid>/...` 的 snippet。

**`performConnectCodex()` 的第一行是 guard**（R-9）：
```
guard pathRejection == nil else { banner = .error(對應文案); refreshPanel(); return }   // 在任何 disconnect 之前
if codexState == .connectedStalePath { try? installer.disconnect(ifContentsEqual: store.contents) }
try installer.connect(json:..., translocated:..., inDownloads:...)
```
**這個 guard 不是為了「少一次失敗」，是為了「不要先刪檔」**：r3 的順序在 translocated 下會
`disconnect` 成功（內容確實相符）→ 檔案被刪、`store.clear()` → 然後 `connect` 才撞上執行層 guard。
淨結果是「使用者只是打開了一次 DMG 裡的副本，他那份還在運作的 hook 就沒了」，而按鈕上寫「重新接上」。

**`reprobeCodex()` 的內容與時機**：
- **行程常數在啟動時算一次**（D-t）：`translocated`／`inDownloads`／`pathRejection`／
  `currentExpectedContents`／`codexSnippet` 五者都是 `Bundle.main.bundleURL` 的純函式，
  在 `applicationDidFinishLaunching` 算一次存成欄位。
- `reprobeCodex()` **只重做檔案系統那一段**：`installer.probe()` →
  `CodexState.from(obs, recordedContents: store.contents, currentExpectedContents: 欄位, pathRejection: 欄位)`。
- **四個時機**：① `applicationDidFinishLaunching` 同步區（第一次 `refreshPanel()` **之前**）
  ② popover `onOpen` ③ `performConnectCodex()` 之後 ④ `performDisconnectCodex()` 之後。
  漏接的後果：使用者裝了 Codex、開面板、什麼都沒有，重開 app 才出現——而全套測試綠（CX24⑤ 守）。

接上成功的 banner（D-m）：**「已接上 Codex · 下一個 Codex session 起生效；
Codex 啟動時會問你一次是否信任這個 hook，要按同意才會生效。」**

**r13（D-v）：那句話什麼時候會從畫面上消失**——`effectiveBanner` 的退場條件依 kind 分流：

| banner kind | 退場條件 | 理由 |
|---|---|---|
| `.connected`（Claude） | `!rows.isEmpty`（**任何**一列） | A7：Claude banner 宣稱「下一個 session 起生效」，出現任何一個 session 就是兌現了 |
| **`.codexConnected`（新）** | **`hasCodexRow`**（出現 `agentLabel == Agent.codex.label` 的列） | 出現一個 **Claude** 列並未兌現 Codex 的任何承諾。r12 兩者共用 `.connected` kind，所以 Codex banner 被 Claude 的列抹掉 |
| `.alreadyConnected`／`.disconnected`／`.error` | 無自動退場（使用者按 ✕ 或被下一個 banner 蓋掉） | 它們沒有「宣稱某件事將會發生」，沒有對應的「條件被滿足」 |

**`.codexConnected` 沿用 `.connected` 的視覺樣式**（`BannerView` 只用 `kind == .error` 分岔顏色），
所以這個新 case 是**零像素變更**、零既有窮盡 `switch` 受影響（全 repo 對 `PanelBanner.Kind` 只有 `==` 比較，
沒有窮盡 switch，T13b 開工前要重跑一次這個掃描確認）。

**`Kind` 是 `CaseIterable` 但目前沒有任何消費者**——CX47 的定義域走 `PanelBanner.Kind.allCases`，
會是**第一個真正的消費者**（同 CX36 對兩層 `samples` 鏈的位置）。在它落地之前，新增一個 kind
不會讓任何既有 gate 變紅。

### 4.7 liveness 與 hook 的父行程（F15）

**已證實（F15）**：五個 session、24 筆事件，每個 session 內所有事件的 `$PPID` 完全相同 →
(i) 呼叫 hook 的**不是每個事件開一次的短命 shell**；(ii) 那個行程至少活過第一個到最後一個事件。
**結論：`getppid()` 判活的前提（pid 在 session 期間穩定）對 Codex 成立。**

**範圍限定（F15，不是細節）**：那五個 session **全部跑在 `codex exec`**。產品要服務的是**互動 TUI**
（F10）。exec 模式的行程結構不等於 TUI 模式的——TUI 完全可能由常駐 app 行程 fork 出 session。
**實機 ③ 要順帶記 `ps -o ppid=,comm=`。**

**未觀測（F15）**：(a) `SessionEnd` **之後**那個 pid 是否結束（「隨 session 結束」是推論；
實務後果有限，`resolveLiveness` 第一個 guard 就是 `!s.terminated`）；(b) 那個 pid 是 `codex`
原生二進位還是 node 啟動器。

**預寫的 fallback 決策點**（若實機 ③ 發現父行程跨 session 常駐）：`--agent codex` 時**不寫 pid**，
改由 `SessionEnd` 的 `terminated` 單獨判死。**這條現在不做。**

### 4.8 兩側互不干擾、最終都要成功（R-8）

**不變式（寫成契約，不是巧合）**：
1. **隔離**：對任一側做 connect／disconnect／reconnect／完整移除的**任意操作序列**，
   另一側的檔案位元組不變、另一側的 `InstallState`／`CodexState` 不變。
2. **共存**：兩側都接上時，兩側都**真的能運作**——同一顆 `aura-hook` 同時服務兩個上游，
   兩邊的事件各自寫到 `~/.agentaura/sessions/` 且**互不覆蓋**、`agent` 各自正確。

不變式成立的結構理由（要寫進 doc comment，讓下一個人知道它靠什麼）：
兩側的安裝物件**不重疊**——Claude 側只碰 `<claudeHome>/skills[/agentaura]`
（既有 `installerTouchesOnlyAllowedPaths` 守），Codex 側只碰 `<codexHome>/hooks.json`（CX14 守）；
狀態檔以 `session_id` 分檔，兩個上游的 id 空間不交集（Claude 的 UUID 與 Codex 的 UUIDv7）。
**但「不重疊」是兩條獨立 gate 各自的結論，沒有人驗過「交錯操作」本身**——R-8 補的就是那個。

**不變式 1 由兩條 gate 共同守，缺一不可**（r4 M3）：`InstallState` = `LinkObservation`（檔案）
＋ `verification`（App 層三個 `AgentAuraHook*` 鍵）；`CodexState` = `CodexObservation`（檔案）
＋ `recordedContents`（App 層 `AgentAuraCodexHookContents`）。**CX37a／CX37b 住 AuraHookFile，
只看得到檔案那一半**；憑證那一半（真實 App 層有沒有把兩邊的鍵搞混）由 **CX42** 守。
三條 gate（CX37a／CX37b／CX42）的 doc comment 要互相點名，否則下一個人讀到檔案那兩條會以為整條不變式都守住了。

**CX37a／CX37b 序列 gate**（AuraHookFile 層，fixture home，見 §6.3）：對
`{connectClaude, connectCodex, disconnectClaude, disconnectCodex, reconnectCodex(stale)}`
**程式推導**出序列（不手列），每一步之後對「另一側」整棵樹取 `DirectoryTreeSnapshot`
斷言零差異；序列結束時若兩側皆 connected，兩側 `probe()` 推導出的狀態皆為 connected。
**拆成兩條，覆蓋不減、spawn 從 586 次降到 11 次**（r4 M2）：

- **CX37a（檔案不變式，全部 780 條序列）**：`connectClaude` 這一步**直接呼叫
  `installer.guardWriteTarget()` ＋ `installer.atomicReplace()`**，零 spawn。
  **這不是抄近路，是等價**：那兩步就是 `claudeHome` 底下唯一會被碰到的動作，
  `verifyByExecuting` 對 `claudeHome` 的樹**沒有任何貢獻**（它只寫 `verificationRootOverride`
  指定的位置，`removexattr` 作用在 bundle 內的二進位）。先例：
  `InstallerClobberTests.performConnectStepsGuardsWriteTargetDirectly` 就是直接呼叫內部步驟，
  doc comment 逐字寫著理由；`@testable import AuraHookFile` 在 `Tests/AuraCoreTests/` 已有十個檔在用。
  序列數 5＋25＋125＋625 = **780**，總操作數 2930，毫秒級，**全跑，不縮減**。
- **CX37b（生產路徑，長度 ≤ 2 共 30 條）**：走完整的
  `installer.connect(force:translocated:inDownloads:)`，**含 spawn**，注入小的 `verificationTimeout`。
  `connectClaude` 出現次數 = 1（長度 1）＋ 10（25 條 × 2 步 ÷ 5）= **11 次真 spawn**，走 `SpawnGate`。
  守的是「完整流程也不碰另一側」，接住 CX37a 跳過那一步可能漏掉的東西。

兩條的 doc comment 要**互相點名**：a 要寫「為什麼跳過 spawn 是等價的」，b 要寫「為什麼只到長度 2」。
（**注意**：`verificationRootOverride`／`verificationTimeout` **都不能免 spawn**——前者只改驗證
session 的寫入位置，後者只改等待上限；`verifyByExecuting` 是 `performConnectSteps()` 的無條件最後一步。）

**CX38 雙 agent 端到端 wired gate**（沿用 `EndToEndWiredGateTests` 的真 spawn，見 §6.3）：
同一顆 `aura-hook`，先以 Claude payload（round1 fixture）**無參數**呼叫、再以 Codex payload
（round4 fixture）`--agent codex` 呼叫，寫到**同一個** `AGENTAURA_ROOT`；斷言兩個 snapshot
各自 `agent` 正確、activity 對；接著**反序再跑一次**。
**「互不覆蓋」是結構性結論，不是被測性質**（r4 m1）：`SnapshotIO` 以 `<session_id>.json` 分檔，
而兩份 fixture 的 session id 本來就不同，所以那個斷言在任何實作下都會通過（包括完全壞掉的實作）。
CX38 真正有牙齒的是另外兩半（同一顆二進位服務兩個上游、兩邊 `agent` 各自正確），
mutation（`--agent` 一律回 `.claude`）打的也是那兩半。gate 的 doc comment 要把這件事標明。
**明寫的假設**：兩個上游的 session id 空間不交集（Claude 的 UUID 與 Codex 的 UUIDv7）——
實務上不碰撞，但那是假設、不是我們控制的東西，列進 §10-16。

### 4.9 Codex 的模型命名：`Jargon.model`（D-u）

**這是一個既有 gate 正在紅的缺口，不是新需求。** fixture 進 repo 之後，
`FixtureCodeAnchorTests.everyFixtureModelIsMapped`（「fixture 裡出現過的每一個 model 值經
`Jargon.model` 後不再是原始代碼字」）**已經紅**：fixture 的唯一 model 值是 `gpt-5.5`，
而 `Jargon.model` 的六條規則以 `claude-` 家族的命名為前提——`gpt-5.5` 切成 `["gpt", "5.5"]`，
兩段都不是純數字（`5.5` 含 `.`），命中規則 6「多於一個非數字段 → 原樣回傳」。

**處置**：在既有演算法**之前**加一個 Codex 家族分支；**既有六條規則一行不動**，
判不出來一律落回既有的「原樣回傳」。

**Codex 家族分支的規則（四步，讓下表每一列都可推導）**：
1. 先抓 `[...]` 尾綴 → ` (內容大寫)`，其餘部分繼續處理（**與既有規則 1 同形**，不是另一套）。
2. 第一段（以 `-` 切）若是 `o` ＋ 數字開頭（`o3`、`o4`）→ **整串原樣回傳**（OpenAI 的 `o` 系列
   品牌寫法是小寫，**不得**改成 `O3`）。
3. 否則前綴必須是 `gpt-`，去前綴後名字部分固定為 `GPT`；**第一個剩餘段以連字號接上**
   （`GPT-<第一段>`，不論它是不是純數字——`4o` 也走這條，所以是 `GPT-4o` 不是 `GPT 4o`）。
4. 之後每一段**首字大寫、以空白連接**。任一步不符（沒有 `gpt-` 前綴、去前綴後為空）→ 落回既有演算法。

期望值**寫死在表裡**（`!= raw` 這種弱斷言不足以定義行為——把每個輸入都回傳 `"x"`
也能讓既有 gate 變綠）：

| 輸入 | 輸出 | 證據強度 |
|---|---|---|
| `gpt-5.5` | `GPT-5.5` | **實測**（`round4-codex.ndjson` 的唯一 model 值） |
| `gpt-5.5-codex` | `GPT-5.5 Codex` | 預期；**未在任何 payload 觀測過** |
| `gpt-4o` | `GPT-4o` | 既有測試表裡的字面（見下方 test-edit scrutiny） |
| **`gpt-5`** | **`GPT-5`** | 預期；**現行輸出是 `Gpt 5`（不是原樣回傳），本 change 刻意變更**。`["gpt","5"]` 的 `5` 是純數字 → 既有演算法**成功**並回傳 `Gpt 5`。它不在任何 fixture（層一看不到）也不在原本的釘死表（層二看不到），**正好掉在兩層守衛之間**——必須釘住，否則是一個使用者看得到的字串靜默改變（r4 M1） |
| **`gpt-4.1-mini`** | **`GPT-4.1 Mini`** | 預期；用來釘住規則 3／4 的分工（第一段連字號、其餘空白＋首字大寫） |
| **`gpt-5.5[high]`** | **`GPT-5.5 (HIGH)`** | 預期；用來釘住規則 1（Codex 分支**先**處理 `[...]` 尾綴，與既有規則同形，不是各寫一套） |
| `o3` | `o3` | 預期；規則 2 |
| `o4-mini` | `o4-mini` | 同上 |
| **`o3[high]`** | **`o3[high]`** | 預期；**兩個家族對 `[...]` 尾綴刻意不對稱**——`gpt-5.5[high]` 走規則 1 重組成 `GPT-5.5 (HIGH)`，`o` 系列則是規則 2「整串原樣回傳」，**不套用已剝除的 bracket 重組**，所以中括號原樣留著。`o` 系列有沒有 bracket 尾綴完全沒有證據，這個不對稱是刻意的；補這一列是為了讓它**被釘住**而不是只活在註解裡（T05 review m3） |
| `claude-fable-5-1` 等既有九列 | 與現在**完全相同** | 既有 `JargonTests` 釘死 |

**test-edit scrutiny（必須逐條寫進報告）**：既有 `JargonTests.modelTwoNonNumericSegmentsPassesThrough`
逐字釘死 **`Jargon.model("gpt-4o") == "gpt-4o"`**。D-u 必然會改到它。判準：
- 那條測試的**原意**是「兩個非數字段 → 原樣回傳」（Claude 家族演算法的一條性質），
  不是「gpt-4o 必須原樣回傳」。
- 所以**性質要保住**：把輸入換成不屬於 Codex 家族的例子（例如 `foo-bar-5`），
  原斷言形狀不變；**另外新增**一列釘死 `gpt-4o` 的新期望值。
- **換掉的輸入必須真的落在既有演算法的規則 6**（`foo-bar-5` → 兩個非數字段 `foo`／`bar`
  ＋ 一個數字段 → 命中規則 6，形狀成立）。換一個其實走別條規則的輸入，等於把那條測試
  換成測別的東西。
- 報告要附**「改前／改後／測的還是不是同一件事」三欄**。
- 這是**對齊新契約**不是弱化（測試名不變、被測性質不變、斷言數**增加**一條）。
  若實作者選擇直接刪掉那條測試，那就是弱化，要退回。

**守衛分兩層**：既有 `everyFixtureModelIsMapped`（fixture 推導的跨層錨點，只驗 `!= raw`）
＋ 新的 CX41（釘死的輸入→輸出表）。前者保證「fixture 裡真的出現過的值有被處理」，
後者保證「處理的方式是我們講好的那個」。**兩條都要**，缺前者會漏掉未來新增的 fixture 值，
缺後者會讓任何胡亂的映射通過。

### 4.10 面板高度天花板與 snippet 區塊（r13／D-ab）

**現況量到的數字**（persona r1，證據圖 `05`／`07`，Options 收合）：面板內容高 **944pt**，
「複製」按鈕約在 **848pt**、圖例約 900pt、footer 約 **919pt**。13 吋 MacBook Air 選單列下
可用高度約 **930pt**（隱藏 Dock）／約 **850pt**（顯示 Dock）。
`PanelView` 只有 `sessionsCard` 有高度上限（`SessionsCardSizing.cardHeight(for:)`），
Codex 卡片直接掛在最外層 `VStack`、**沒有上限也沒有 `ScrollView`**，而
`NSHostingController.sizingOptions = [.preferredContentSize]` ＋ `.frame(maxHeight: .infinity, alignment: .top)`
的組合是**內容釘在頂端、底部被裁掉，不是捲動**。

**944pt 這個數字本身沒有涵蓋最壞情況**（r13 review M1）：`CodexEvidenceRenderer.swift:115,131`
兩張圖都是 `install: connected`，所以量到的是「Claude 已接上 ＋ 沒有 banner」那一格。
會再往上加高度的還有**兩個維度**：
- **`install` 非 connected**：`rows` 空 → 整版 `NotConnectedView`；`rows` 非空 → 多一條 CTA 窄條
  （`PanelModel+ConnectCTA.swift` 的 `connectCTAStyle`）。
- **`banner != nil`**：`.codexConnected` 是三行、約佔頂端 40pt，而且**在使用者跑出第一個 Codex session
  之前不會退場**（D-v 的退場條件就是「出現 Codex 的列」）——**「剛接上 Codex、還沒跑過」正是最常見的那一刻**。
- **`codex == .connected` 時標題可能換行**（r2 review N2，T13f 的量測）：`PanelView.swift` 的標題
  （13pt semibold）沒有 `lineLimit`，全域（29 個非 connected `InstallState` × 兩語言）實測
  **34/58 格會換行**，最壞情境（`.broken(.hookUnconfirmed, owner: .thisApp)`）真渲染面板高度
  **250.0pt → 266.0pt（+16.0pt）**——這個 +16pt 要算進下面的最壞組合，不是只有 `install`／`banner`
  兩個維度會加高度。

**最壞組合是 `install` 非 connected（整版 CTA，標題可能已經換行）＋ `.occupiedByOther` 有 snippet
＋ `.codexConnected` banner**，
**它從來沒有被量過**。照 r13 的域，T13i 會用一個非最壞情況去挑 snippet 上限，CX56 全綠而那個使用者的
「複製」鈕仍在畫面外——**S1-4 沒有真的關掉**。

**契約**：
1. snippet 區塊吃一個**算好的固定高度**（`ScrollView` 內容超過時在區塊內捲），
   **不用 `.frame(maxHeight:)`**——T22 已實測 `ScrollView` 垂直方向貪婪，只設上限會讓它吃滿外層提案高度，
   footer 位置又會變回「依畫布而定」。形狀照抄既有 `SessionsCardSizing.cardHeight(for:)`
   （從真實內容推導 ＋ 夾到上限），不發明第二種寫法。
2. **產品天花板**：`optionsExpanded == false` 時，對**下列五個維度的乘積**，
   `NSHostingController.preferredContentSize.height ≤ **780pt**`：

   | 維度 | 取值 | 為什麼在域裡 |
   |---|---|---|
   | `CodexState` | `CodexStateKind.allCases.flatMap(CodexState.samples)` | 卡片內容是主要變因 |
   | `language` | 兩種 | 中英文行數不同 |
   | `rows` | 空／3 列 | 空→整版 CTA；非空→窄條＋列表 |
   | **`install`**（r14 新增；**r15 改成實測選代表值**） | `.connected` ＋ **一個非 connected 的代表值，由 T13i 實測選出**（見下方「代表值怎麼選」） | 非 connected 會多畫整版 `NotConnectedView` 或 CTA 窄條 |
   | **`banner`**（r14 新增） | `nil` ／ `.codexConnected` | 三行、約 40pt，且在跑出第一個 Codex session 前不退場 |

3. **「複製」按鈕與 footer 的渲染後 y 都必須落在天花板內**（CLAUDE.md gate 哲學第 4 條：
   位置類的 gate 要量渲染後的座標，不是宣告順序）。按鈕身份**用點擊辨識、不得用陣列索引**
   （`FooterPositionStabilityTests` 的既有手法與踩過的坑）。
4. **snippet 區塊有高度下限**：至少要能同時顯示 **6 個視覺列**。
   沒有這條，「讓 CX56 變綠」最省事的動作就是把 snippet 壓成一條縫——那不是修好 S1-4，是換一種壞法。
   **上限與下限住在不同層，這一點要寫清楚否則會被實作成寫死常數**（r15／r14 review n4）：
   - **上限**（夾住用的那個固定高度）住 `CodexSnippetSizing`（**AuraCore，純算術**：行數估計 × 行高，
     形狀同 `SessionsCardSizing`）。
   - **下限（6 個視覺列）由 CX56 在 App 層用真實渲染量**——渲一段 6 行的等寬文字取它的高度當基準，
     再斷言 snippet 區塊不低於它。**不得進 AuraCore**：那一層只准 import Foundation、**量不了文字**，
     寫進去就只能是一個寫死的行高 pt 常數，正是 `LEDStripView.preferredWidth`
     把算術錯誤凍成常數那次的形狀（CLAUDE.md gate 哲學第 2 條）。

**`install` 的代表值怎麼選**（r15／r14 review n3）：r14 寫的是「一個 `affordance == .connect` 的代表值」，
但**沒有論證它是畫得最多的那個**——`connectCTAStyle`／`showsExplanationPanel` 讀的是 `affordance`，
而另外兩種會畫得更多：`.replaceExternal` 的 CTA 窄條**多一行副標**（`connectCTASubtitle` → `mountTargetNote`，
`.connect` 那格是 nil）；`.explainOnly` ＋ rows 空會走 `showsExplanationPanel` → `NotConnectedView` ＋
`explanationDetail`。**挑 `.connect` 等於又挑了一個方便的代表值**，只是幅度比 r13 小很多。
處置**不是把域擴成四倍**（離屏渲染很貴），而是照 §4.10 自己建立的「先量後定」紀律：
**T13i 的基準表在最高的那個 `CodexState` 下，把四種 `InstallAffordance` 各量一次，
把實測最高的那個釘成 CX56 的 `install` 代表值，四個數字都寫進報告**。
這樣代表值是**量出來的**，不是挑出來的。

**780 這個數字在 T13i 量完之前是「提案」不是「已驗證可達」**（r14 明確化）。
處理順序是**先量後定**：T13i 先把上表整個乘積的修前高度量出來（那是本子項的第一個交付物），
再挑 snippet 上限。**若在下限（6 列）之下仍然到不了 780**，**停下來**把量到的數字與選項交回主 session／使用者，
**不要自己降低別處的內容**。當時的選項至少有三個，要一起列：
① 調整天花板數字（並說明它對 13 吋顯示 Dock 的實際後果）；
② 把整張 Codex 卡片（不只 snippet 區塊）納入可捲範圍；
③ 在這個組合下不同時顯示 banner 與 snippet 卡（**這會動到 D-v，屬於決策變更，必須回到 spec**）。

**780 這個數字是什麼、以及它紅掉時該問什麼**：它是**產品天花板提案**（850pt 可用高度扣掉餘裕），
不是量出來的自然高度。CLAUDE.md gate 哲學第 2 條記過 `FooterPositionStabilityTests` 的教訓
——一個寫死的畫布常數在面板長大之後**換了題目**，而有人照著它把使用者要的留白砍到 2pt。
所以這條 gate 的 doc comment 要逐字寫：**它紅掉時的第一個問題是「面板是不是又長高了」**，
正確的處置是回頭看 snippet 上限與卡片內容，**不是**刪掉斷言、也**不是**把別的地方的留白砍掉。
T13i 要先量出**修前基準**（每個組合的實際高度）寫進報告，mutation 才對得上基準。

**明確不在這條之內的**：`optionsExpanded == true` ＋ snippet 卡片同時存在時的總高度。
Options 展開本身在 Claude-only 的既有面板就已經是 599pt（2026-09-15 實測），
那是**這個 change 之前就存在的條件**；把它綁進本條 gate 會讓一條新 gate 去回答一個舊問題
（同樣是「換題目」的形狀）。量到的數字記進 §10-20，不在本批處理。

### 4.11 Codex 移除的確認框（r13／D-ac）

`.disconnectCodex` 改走 `AppDelegate` 的**第四個**確認注入縫 `confirmDisconnectCodex`
（前三個：`confirmDisconnect`／`confirmReplaceExternalMount`／`confirmUninstall`），
生產預設值是 `CodexDisconnectConfirmation.present(language:onConfirm:)`（`AppEnvironment.swift`，
照既有 `DisconnectConfirmation` 的形狀，共用 `ConfirmationAlert.present`）。
文案**點名 agent**：標題「移除 Codex 掛載？」／"Remove the Codex mount?"（對照既有
`L10nConfirmationAlerts.disconnectTitle` 已經點名 Claude Code），內文要講清楚**只刪我們自己寫的那份**
（逐位元組比對過才刪，別人的 `hooks.json` 不會被碰）。

**這會讓 `AppDelegate.swift` 從 196 行越過 200 行上限**（多一個 stored property ＋ init 參數 ＋
預設值 ＋ 指派）。處置照 §8.1 既有規則：**先做一次零行為變更的純搬移 commit**
（`applicationDidFinishLaunching` → `AppDelegate+Lifecycle.swift`，該檔目前 23 行、
且 `applicationWillTerminate` 已經住在那裡，證明 `NSApplicationDelegate` 的方法放在 extension
在本 repo 可行），**不准刪註解或空行擠**。

## 5. 錯誤處理

| 情況 | 處理 |
|---|---|
| `--agent` 未知值／缺值／重複 | 落回 `.claude`；靜默、exit 0、零輸出 |
| 磁碟上 `agent` 是未知字串／非字串／`null` | `Agent(stored:)` 落回 `.claude`；**整包仍解得開**；那一列沒有標籤 |
| 舊版狀態檔沒有 `agent` 鍵 | `decodeIfPresent` → nil → `.claude`（CX11） |
| `~/.codex` 不存在／是普通檔／是斷鏈 symlink | `.unavailable`；**不建立它**；面板零 Codex 元素 |
| App 是 translocated 或在 `~/Downloads` | 路由層 → `.blockedByBundlePath(.mustMoveToApplications)`；`performConnectCodex()` 前置 guard → banner，**不動任何檔**；執行層 → `CodexFailure.mustMoveToApplications`。snippet 一律 nil（R-10） |
| hook 路徑含空白／`'`／`"`／`$`／`` ` ``／`\` | 三層同上，訊息**指名那個字元**＋**給出路**（把 App 移到路徑不含該字元的位置）；**r13（D-w）：snippet 一律 nil**（~~r12：照給~~）。那個路徑不會消失，但 `command` 是裸路徑、行為未測——**不敢替他寫，就不能遞給他一份**。解鎖條件見 §10-17 |
| **已接上、但 App 現在跑在被拒的位置** | `.connectedStalePath` ＋ `pathRejection != nil` → 面板**不給「重新接上」按鈕**，只說「先把 App 移回去」；即使有別的路徑送出 `.connectCodex`，`performConnectCodex()` 的第一行 guard 也會在**任何 `disconnect` 之前** return（R-9） |
| `~/.codex/hooks.json` 已存在（普通檔／目錄／symlink／斷鏈 symlink） | `connect` 一律 throw `.alreadyExists`；**那個路徑（含 symlink 指向的目標）位元組與型別完全不變**（CX15，含「symlink 指向 `config.toml`」那一格） |
| `hooks.json` 存在但內容對不上（或 > 64 KiB 沒讀） | `.occupiedByOther`；不提供刪除按鈕；`disconnect` 若被呼叫一律 throw `.notOurs` |
| 磁碟內容 == 憑證但 != 現在路徑的預期內容 | `.connectedStalePath`（兩種文案見上） |
| 憑證遺失（使用者清過偏好設定） | `.occupiedByOther`（保守：認不得就不碰） |
| `connect` 寫入失敗（權限、磁碟滿） | throw `.writeFailed(errno)` → banner；**不重試、不 fallback 到非原子寫法** |
| 讀 `hooks.json` 失敗（權限） | `.occupiedByOther`（讀不到不等於不存在） |
| Codex 未信任 hook（F5） | **偵測不到**。UI 不得宣稱已生效；help／INSTALL 寫明 |
| **對任一側的操作影響到另一側** | 不得發生（R-8 §4.8 的不變式）；檔案半由 CX37a／CX37b 守、**憑證半由 CX42 守**、端到端由 CX38 守 |
| 收尾步驟（codex disconnect）在完整移除中失敗 | `try?` 吞掉，後面步驟照跑（Lessons #8）；`verify-uninstall.sh` 第 7 項會把殘留說出來 |

## 6. 測試策略

T01 先行（測試＋compile-only stub，零生產碼，禁 `fatalError`）。swift-testing。
**測試中絕不跑 `codex exec`**（F12）、**絕不碰真的 `~/.codex`／`~/.claude`**。

### 6.1 對抗式 double（Lessons #1；T01 必含）
1. **payload**：缺 `permission_mode`／缺 `model`／`tool_response` 是 200 KB 字串／
   `hook_event_name: "Interrupt"` **帶** `agent_id`／`session_id` 是 UUIDv7。
2. **argv（8 格表）**：`[]`、`["--agent"]`、`["--agent","gemini"]`、`["--agent","CODEX"]`、
   `["--agent=codex"]`、`["--agent","codex","--agent","claude"]`、`["--agent","codex","--agent"]`、
   **`["--agent","gemini","--agent","codex"] → `claude`**（T02 review M1）。
   **第 8 格釘住的是「第一個*出現*者勝」而不是「第一個*有效*者勝」**——前七格兩種語意給的答案完全相同，
   reviewer 用一個「未知值不回傳、繼續往後掃」的替代實作實跑，七格**全綠**。而「第一個有效者勝」等於
   **讓使用者手寫錯的第一個旗標被後面的悄悄蓋過去**，正是 D-d 那段理由要防的事。
   **CX7 與 CX8 共用的唯一來源**——盲點會原封不動傳給另一條（Lessons #1 的形狀）。
3. **檔案系統**：`hooks.json` 是目錄／symlink 指向 `config.toml`／斷鏈 symlink／別人的合法 JSON／
   5 MB 垃圾（> 64 KiB，驗 D-q）；`~/.codex` 自己是外部 symlink／是普通檔／不存在。
4. **路徑**：`translocated: true`／`inDownloads: true`／六個不支援字元各一／**同時 translocated
   ＋ 含空白**（驗優先序）／乾淨路徑（負對照）。
5. **兩側交錯（R-8）**：同一個 fixture home 下同時有 `claudeHome` 與 `codexHome`，供 CX37a／CX37b 推導序列；
   App 層另備 fake installer／fake store ＋ 注入 suite，供 CX42 的 20 條序列使用（零 spawn）。
6. **`FakeCodexStore`**：可設定「寫進去與讀回來不一致」。
7. **`FakeCodexInstaller`**：① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
   ② `disconnect()` 宣稱成功但檔案還在；③ `probe()` 丟錯；
   ④ **記錄 `connect`／`disconnect`／`probe` 的呼叫順序與次數**（CX24⑤、CX35、CX39 要用）。

### 6.2 composition-root smoke
- `codexInstallerIsInjected`；`productionCodexHomeIsRealHome`（行為 ＋ 來源掃描不得用
  `environment["HOME"]`）；`codexConnectChainIsWired`（五段，CX24）；
  `codexRowsReachTheView`（`.unavailable` 時 `preferredContentSize` 與零 Codex 狀態完全相同）。
- **r13 追加的兩條「畫出來了沒有」**：`codexTrustWarningIsDrawnWithClaudeRowsPresent`（CX48）與
  `dualAgentStatusLabelReachesAllThreeSites`（CX51）。兩者都用 `leafStrings(_:)` 掃**整個
  `PanelView(model:).body`** 的值型別樹，不是斷言 `delegate` 上的儲存值——persona r1 的 S0-1
  正是「儲存值對、畫面沒有」那一格，而當時唯一相關的 gate（CX24④）斷言的就是儲存值。
  **這是 Lessons #5（tested ≠ wired）在 view 層的形狀**：`PanelModel` 有那個欄位，
  不代表 `PanelView` 會把它畫出來。

### 6.3 Gate 表（新增一律 `CX<n>`，共 **57** 條；CX37 拆成 a／b，CX43 未使用，**CX47–CX57 是 r13 的 persona 修復批次**；既有 gate 寫測試函式名）

| Gate | 層 | 守什麼 | Mutation（→ 指名測試 ≤60s 變紅） |
|---|---|---|---|
| CX1 `codexEventSetIsPinnedToProbe` | AuraCore | `codexEvents` 恰等於 F2 的 12 個字面名；doc comment **分標兩種證據強度**（六個有真實 payload／六個只有二進位字串列舉） | 加一個／少一個 |
| **CX2 `interruptNeverEntersHandledEvents`** | AuraCore | `handledEvents.isDisjoint(with: codexOnlyEvents)`；**失敗訊息必須寫出後果**（Claude 側整份 hooks 失效、產品對 Claude 使用者完全停止運作），**並帶 §4.2 的 runtime 限定語**（本機 validator 只給 warning，整份拒載是跨機器實測）。**不要求逐字某四個字**——寫得更完整的訊息不該被改回更短的（T03 review m3） | 把 `Interrupt` 加進 `handledEvents` |
| CX3 `codexSharedEventsReuseClaudeMapping` | AuraCore | `codexEvents − codexOnlyEvents ⊆ handledEvents`，每個 `effect` 非 `.noChange` | 從 `handledEvents` 拿掉 `PreCompact` |
| **CX4 `codexOnlyEventsMapToIdle`** | AuraCore | 定義域**從 `codexOnlyEvents` 推導**；`Interrupt → idle` 的唯一守衛 | 刪掉 `case "Interrupt"` 整行 |
| CX5 `claudeHooksJSONHasNoInterrupt` | AuraCore | `plugin/hooks/hooks.json` 不含 `Interrupt`（獨立於既有雙向等式）；**加定義域非空守衛**——`hooks` 物件若解析成**空字典**，`try #require` 會通過、`registered` 為空集合、交集為空而靜默全綠（T03 review m1；CX1／CX3／CX4 三條姊妹 gate 都有這個守衛，只有它沒有） | 在 Claude hooks.json 加 `Interrupt` |
| **CX6 `codexHooksJSONMatchesF14Verbatim`** | AuraCore | ① 鍵集合 == `codexEvents`；② **12 個 entry 逐一逐字等於 F14**（`matcher: ""`、無 `async`），唯一數值偏離 `timeout` 5→3，失敗訊息帶 F13 引文。**`command` 與 `agentFlag` 的期望值一律寫死字面**（`== "<path> --agent codex"`），**不得引用 `CodexHooksJSON.agentFlag`**——拿產生器的輸出跟產生器自己的常數比，常數被改壞時兩邊一起變、斷言恆真（T04 review M1 實測：把 `agentFlag` 改成 `"--agent codexx"`，全量 808 條測試**零新紅**）；③ **對抗式路徑 round-trip**：含**空白／`"`／`\`** 的路徑產出仍是合法 JSON 且 `command` 解析回原路徑（不是理論情境——D-s／R-10 明訂 `.unsupportedCharacter` **仍要給 snippet**，所以生產必然會用含這些字元的路徑呼叫 `snippet(...)`；跳脫壞了，使用者複製到的是壞掉的 JSON，而他正是只剩手動貼上這條路的人）；④ **跨 module round-trip `generatedFlagIsUnderstoodByTheParser`**：把產生出來的旗標拆成 argv 餵進**真的** `AgentArgument.agent(from:)`，斷言回 `.codex`——這是 T02↔T04 的接縫（`CodexHooksJSON` 寫出去的字面與 `Agent.codex.rawValue` 是兩份各自維護的字串），**兩個方向都擋**（改壞產生器、或改壞解析規則） | ① 寫死 11 個 ② 拿掉 `matcher` ③ 加 `async: true` ④ 漏 `--agent codex` ⑤ **`timeout` 改回 5** ⑥ **`agentFlag` 改成 `"--agent codexx"` → ②與④必須紅** |
| CX7 `agentArgumentParsing` | AuraCore | §6.1(2) 的 **8 格**表逐格；**開頭加定義域非空守衛**（`cases.count == 8`，本 repo 既有慣例是把非空守衛寫進 gate 自己，否則 `--filter` 單獨跑時表變空會靜默全綠） | ① 未知值改成回 `.codex` ② **改成「第一個*有效*者勝」（未知值不回傳、繼續往後掃）→ 第 8 格必須紅** |
| CX8 `auraHookStaysSilentForEveryAgentArgument` | E2E（真 spawn） | 同一張 **8 格**表，`SpawnGate` 內序列跑：exit 0、stdout 空、stderr 空 | 解析失敗時寫 stderr |
| CX9 `claudeStateFileHasNoAgentKey` | AuraCore ＋ **E2E** | **兩層，缺一不可**（T05 review M1）：① **純函式層**——round1／1b／2／3 跑 merge，用**生產的 `SnapshotIO.encoder`**（不是測試自建的 `JSONEncoder`：gate 哲學第 1 條，不要在生產機制外面再包一層自己的近似）序列化後**不含** `agent` 鍵，涵蓋四份 fixture 的每一筆；② **生產層**——**不帶 `--agent` 真 spawn 一次**，讀**原始檔案文字**斷言 `!raw.contains("\"agent\"")`（CX10 那條位元組斷言的鏡像，走完整 `main.swift` → `SnapshotIO.encoder` → 檔案）。理由：**`agent == nil` 與「檔案裡沒有這個鍵」不是同一件事**——哪天有人寫自訂 `encode(to:)`，檔案可能出現 `"agent":null`，解碼回來仍是 nil、上游 gate 全綠，而 DoD #5 宣稱的「位元組完全相同」已經破了。兩條的 doc comment 互相點名（一條驗鍵不存在、跑得快；一條驗真檔案位元組、只跑一次） | ① `.claude` 也寫 `"claude"` ② **`agent` 改成非 Optional 帶預設 `""`（或加一個會寫 null 的自訂 encode）→ 生產層那半必須紅** |
| CX10 `codexStateFileCarriesAgent` | E2E（真 spawn） | `--agent codex` 真跑 → 檔案含 `"agent":"codex"` | `main.swift` 忘了傳 agent |
| CX11 `legacySnapshotWithoutAgentDecodes` | AuraCore | 無 `agent` 鍵的舊 JSON 解得開且 `.claude` | `agent` 改成非 Optional |
| CX12 `unknownAgentFallsBackWithoutFailingDecode` | AuraCore | `"agent":"gemini"` → 整包解得開、`.claude`、無標籤 | `agent` 改成 `Agent?`（enum） |
| CX13 `round4FixtureParsesAndMatchesProbeTable` | AuraCore | 18 筆全解析；`effect` 與欄位表一致；`isSafeSessionID` 全過；**外加欄位層反向斷言：探針表列出的每個欄位，在該事件的樣本裡至少出現一次**（T01 review M3：事件層的反向斷言擋不住「把 fixture 裡每一筆的 `model` 欄位拿掉」——那會讓跨層錨點 `everyFixtureModelIsMapped` 從紅變綠，**用縮小證據來消滅一條紅燈**；欄位層是唯一看得到它的東西，與那條錨點是同一條防線） | ① **`Stop` 改成 `.noChange`** ② **從 fixture 抽掉某個事件的一個欄位**（例如 `SessionStart` 的 `model`）→ 欄位層那半必須紅 |
| **CX14 `codexInstallerTouchesOnlyHooksJSON`** | AuraHookFile | 整棵樹差異**恰為** `{hooks.json}`；`config.toml` 位元組不變 | connect 順手寫 `hooks.json.bak` |
| **CX15 `codexConnectRefusesEveryOccupiedShape`** | AuraHookFile | 佔用形狀各 throw `.alreadyExists`，且該路徑（含 symlink 目標）位元組與型別不變 | 拿掉 `O_EXCL`（symlink→`config.toml` 那格必須紅） |
| CX16 `codexConnectWritesGeneratorBytes` | AuraHookFile | 檔案內容 == 產生器位元組；回傳值 == 那些位元組 | 少寫最後一個 byte |
| CX17 `codexDisconnectOnlyRemovesOurBytes` | AuraHookFile | 逐位元組相符才刪；改一 byte → 不刪＋throw；nil → 不刪；`(dev,ino)` 被換 → 不刪 | ① 拿掉內容比對 ② 拿掉 `(dev,ino)` 複查 |
| CX18 `codexHomeSymlinkWritesInsideResolvedPath` | AuraHookFile | 字面樹不變、`realpath` 樹差異恰為 `{hooks.json}` | 快照改用字面路徑 |
| CX19 `codexStateCoversEveryObservationShape` | AuraCore | 判定表逐格；定義域由五個維度的乘積**推導**，不寫格數 | ① `symlink` 併進 `.notConnected` ② 第 2／3 列對調 |
| CX20 `codexRowsAppearOnlyWhenAvailable` | AuraCore | 逐 `CodexStateKind`（含兩種 Rejection）斷言列數與 action：`.unavailable`／`.occupiedByOther`／`.blockedByBundlePath` 零列；`.notConnected`／`.connected` 恰一列；**`.connectedStalePath` 依 `pathRejection` 分兩列／一列**（R-9） | ① `.unavailable` 也給「接上 Codex」 ② 被拒時仍給「重新接上」 |
| CX21 既有 `optionsRowsCoverEveryAction` ＋ `nonMenuKindsIsExactlyThatLiteralSet` 擴充 | AuraCore | 代表狀態集合由 `CodexStateKind.allCases.flatMap(CodexState.samples)` 推導；`nonMenuKinds` 四個 → 五個 | 把 `.connectCodex` 塞進 `nonMenuKinds` |
| CX22 `agentLabelOnlyForNonClaude` | AuraCore ＋ 像素 | model：claude → nil、codex → "Codex"；像素：同一列兩者 `differingPixels > 0` | 標籤對 claude 也給值 |
| **CX23 `codexLabelDoesNotChangeRowHeight`** | App（離屏） | 帶標籤的列高仍是 43／59pt（±0.5） | 標籤另起一行 |
| **CX24 `codexConnectChainIsWired`** | App | 五段：① 接線 ② fake 收到 `connect` ③ **憑證取回是同一串位元組** ④ banner 含兩個關鍵詞（從 `L10nCodex` 鍵推導）⑤ spy 記 `probe()` 次數，`onOpen` 後 ≥ 1。**r13 註記**：④ 斷言的是 `delegate.banner?.text`（**儲存值**），而且這個 smoke 的 session graph 是空的——**它證明不了那兩句話被畫出來**（persona r1 S0-1 就活在這個縫裡）。渲染那一半由 **CX48** 守，兩條的 doc comment 要互相點名 | ① 分支改 `break` ② banner 只留一句 ③ 拿掉 `onOpen` 的 `reprobeCodex()` |
| CX25 `productionCodexHomeIsRealHome` | App ＋ 掃描 | §6.2 第二條 | 改成 `environment["HOME"]` |
| CX26 `uninstallRemovesCodexBeforeErasingDefaults` | App | codex disconnect **早於** `removePersistentDomain` | 兩步對調 |
| CX27 `verifyUninstallScriptDetectsOurCodexHooks` | script | 暫存 `CODEX_HOME` ＋ `--only 7`；**判準是那一行的 PASS/FAIL**。**外加兩格參數驗證**（T11 review M1 實測）：① **`--only`（缺值）在有界時間內以非零退出**（實測會**無限迴圈且零輸出**——`--only)` 分支無條件 `shift 2`，而 bash 在 `$# < 2` 時 `shift 2` 不改 `$#` 也不中止，腳本只有 `set -uo pipefail` 沒有 `-e`）；② **`--only 77` 以非零退出，且輸出不得含「PASS」**（實測 `--only 77`／`--only 0`／`--only seven` 都是**一項都沒跑、然後印「完整移除驗收 PASS」**）。理由：腳本**第 4 項自己**為了不把「問不到」誤當「通過」特地多寫了 `LOGIN_ASKED`，而 `--only` 這條路徑把同一個錯犯在**整支腳本的總結論**上——而它正是「移除乾淨是測試能力的前提」那條 invariant 的驗收工具 | ① 拿掉腳本第 7 項 ② **拿掉 `--only` 的值域檢查（`[1-7]`）→ ②那格必須紅** |
| CX28 `helpDocsCoverCodexRows` | 文件 | `allRows` 對 `CodexStateKind.allCases` 取**聯集**，兩語言各守 | **只刪其中一個標題**也必須紅 |
| CX29 `securityDocListsEveryPathWeWrite` | 文件 | **三份文件都要含** `.codex/hooks.json`（字面來自生產常數）：`SECURITY.md`、`README.md`、**`README.zh-TW.md`**，寫成 `@Test(arguments: [...])` **參數化**而不是三條各寫一遍。T11 review m1 實測：把路徑從 SECURITY.md 與 README.md **兩邊都刪掉**，當時只紅 **1** 條——內容是有的，缺的是守衛 | 從**任一份**刪掉那一行都必須紅（三份各試一次） |
| CX30 `noCodexExecInRepo` | 全 repo | **roots = `Tests/` ＋ `scripts/` ＋ `.github/`** 不得出現 `codex exec`（＋暫存目錄正向對照）。`.github/` 是新加的：repo 有 CI（`ci.yml`），**那裡的指令會真的被執行**，而 F12 的代價（改使用者的 `config.toml`）在 CI 上同樣成立。**`docs/` 刻意不納入**——F12 的證據文件必須**逐字**寫出那個指令名，掃它等於要求證據文件自我審查。**新增任何可執行面時 roots 要跟著加，而沒有測試會提醒你**（這是這條 gate 已知的人工維護點） | 在 `scripts/` 或 `.github/` 加一行 `codex exec` |
| **CX31 `codexHookStoreRoundTripsBytes`** | App | `write(bytes)` → `contents == bytes` **逐位元組**；輸入用**真正的產生器輸出** | 在 `write` 裡加 `trimmingCharacters` |
| **CX32 `codexConnectRefusesBlockedBundlePath`** | AuraHookFile | translocated／inDownloads／含空白各一 → throw 對應 `CodexFailure`，**且整棵樹零差異** | 拿掉 `connect` 第一行的 guard |
| **CX33 `codexPathCheckNamesTheOffendingCharacter`** | AuraCore | 六個字元逐格（定義域從集合推導）；帶**第一個**命中的字元；translocated 優先；乾淨路徑 nil | ① 一律回 `.unsupportedCharacter(" ")` ② 優先序對調 |
| **CX34 `codexStalePathIsDetectedAndOffersReconnect`** | AuraCore | 磁碟 == 憑證 != 現在預期 → `.connectedStalePath`（三份內容都用真產生器輸出、兩個不同路徑）。**fixture 的兩條路徑都不得含 `unsupportedCharacters` 的字元**（例如 `/Applications/AgentAura-2.app`，不要 `AgentAura (2).app`——含空白的路徑在生產中會先落到 `.blockedByBundlePath`，那是一個不可能發生的搬家情境，T07 review m4） | `from` 忽略 `currentExpectedContents` |
| **CX35 `stalePathReconnectDisconnectsBeforeConnecting`** | App | **（前提：`pathRejection == nil`）** `.connectedStalePath` 下送 `.connectCodex` → 呼叫順序是 `disconnect` → `connect`；`.notConnected` 下只有 `connect` | 直接 `connect`（不先 disconnect） |
| **CX36 `codexSectionRendersEveryState`**（**r13 擴充**） | App（離屏） | 六態 ＋ 兩種 Rejection 各渲一次：預期元素在（按鈕／snippet 區塊／指名字元的文案）；`.unavailable` 不畫任何東西。**`.mustMoveToApplications` 那格的輸入必須帶真的 `codexSnippet`**（不是 nil）——否則「不得畫 snippet」在任何實作下都成立（T09 review M1；見 plan §0「負向斷言必須餵正向輸入」）。**r13（D-w）：`.unsupportedCharacter` 那格加入同一條規則**——輸入餵真 snippet、斷言**不得**畫出來，並且**必須**畫出出路句 | ① 錯誤文案不插字元（籠統句） ② 被拒時仍畫「重新接上」按鈕 ③ **把 `.mustMoveToApplications` 分支改成會畫 snippet → 必須紅**（T09 review 實測：在輸入改成真 snippet 之前，這個 mutation 紅 0 條） ④ **r13：把 `.unsupportedCharacter` 分支改回會畫 snippet → 必須紅** ⑤ **r13：拿掉 `.unsupportedCharacter` 的出路句 → 必須紅** |
| **CX37a `bothSidesNeverDisturbEachOthersFiles`** | AuraHookFile | R-8 不變式 1（檔案半）：**程式推導**全部長度 ≤ 4 的操作序列（**780 條，全跑**），`connectClaude` 走 `guardWriteTarget()` ＋ `atomicReplace()`（零 spawn，等價理由見 §4.8）；每步之後「另一側」整棵樹零差異；結束時若兩側皆 connected，兩側 `probe()` 皆 connected | `CodexInstaller.connect` 順手 touch `<claudeHome>/skills/agentaura` 的 mtime |
| **CX37b `bothSidesNeverDisturbEachOthersFilesOnProductionPath`** | AuraHookFile | 同上不變式，但 `connectClaude` 走**完整** `connect(force:translocated:inDownloads:)`（含 spawn，注入小 `verificationTimeout`）；長度 ≤ 2 共 **30 條**、**11 次真 spawn**、走 `SpawnGate`。接住 CX37a 跳過 exec 驗證可能漏掉的東西 | 同 CX37a（兩條都必須紅） |
| **CX38 `oneBinaryServesBothAgentsInOneRoot`** | E2E（真 spawn） | R-8 不變式 2：同一顆 `aura-hook`，Claude payload（round1，無參數）與 Codex payload（round4，`--agent codex`）寫進**同一個** `AGENTAURA_ROOT`；兩個 snapshot 的 `agent`／activity 各自正確；**反序再跑一次**。**「互不覆蓋」在 doc comment 標成結構性結論**（id 空間不交集），不是被測性質 | `--agent` 解析改成一律回 `.claude` |
| **CX39 `codexReconnectNeverDisconnectsWhenPathIsRejected`** | App | 注入 `.connectedStalePath` ＋ `translocated: true` → 送 `.connectCodex` → **`disconnect` 呼叫次數 0**、檔案仍在、banner 是 `.mustMoveToApplications` 那句 | 把 guard 移到 `disconnect` 之後 |
| **CX40 `codexSnippetIsWithheldForEveryPathRejection`**（**r13 改名＋期望值翻轉**，原 `...WhenPathWillVanish`） | AuraCore ＋ App | **乘積表**：定義域 `CodexStateKind.allCases × [nil, .mustMoveToApplications, .unsupportedCharacter(" ")]`。**r13（D-w）**：`.mustMoveToApplications` **與** `.unsupportedCharacter` **兩整行**都 `codexSnippet == nil`（含 `.occupiedByOther`）；**只有 `pathRejection == nil` 整行非 nil**。改名理由：「會消失」不再是判準，判準是「有沒有被拒」——**名字留著會變成一句謊，而下一個人會照名字推回舊條件**。這是契約變更不是弱化：斷言變強（多一整行變成 nil），格數不變 | ① 拿掉 `codexSnippet` 的條件（無條件給） ② **改回 `pathRejection == .mustMoveToApplications`（只扣一種）→ `.unsupportedCharacter` 整行必須紅**（這是 r13 的新守衛，r12 的實作在這個 mutation 下是綠的） |
| **CX41 `jargonModelCoversCodexNaming`** | AuraCore | §4.9 的**釘死輸入→輸出表九列**（含 `gpt-5`／`gpt-4.1-mini`／`gpt-5.5[high]` 與 `o` 系列維持小寫）；既有九列反例輸出**完全不變** | ① Codex 分支回傳 raw ② 把 `o3` 改成 `O3` ③ **把 Codex 分支從既有演算法之前移到之後 → `gpt-5` 那列必須紅**（那是唯一能區分前置／後置的輸入） |
| **CX42 `bothSidesNeverDisturbEachOthersCredentials`** | App | R-8 不變式 1（憑證半，r4 M3）：定義域 `{performConnect, performDisconnect, performConnectCodex, performDisconnectCodex}` 的**全部長度 ≤ 2 序列＝20 條**（程式推導，不手列）；fake installer／fake store ＋ 注入的 `UserDefaults` suite，全記憶體、**零 spawn**。每步之後斷言**另一側的鍵位元組完全不變**（Claude 側三個 `AgentAuraHook*` vs Codex 側 `AgentAuraCodexHookContents`），且該 suite **沒有其他鍵被新增或刪除**（用鍵集合的**差集**斷言，不逐鍵列舉——鍵清單會 drift） | `performDisconnect()` 順手 `defaults.removeObject(forKey: CodexHookStore.key)` |
| **CX44 `noPendingFlagRemains`** | 全 repo 掃描 | **`Sources/` ＋ `Tests/`** 都不得殘留 `AURA_CODEX_PENDING`（T07 review M1：本 change 有**四個**「等下一個 task 替換」的 stub，分屬三種機制——`#if` 旗標會 `Issue.record` 而紅、`switch` 的 `break` 靠既有 gate 誠實紅、窮盡 switch 的暫定值靠「動 view 時一定看到」、而 `OptionsSectionView` 硬編 `.unavailable` **既不紅也不在必經路徑上**。**只有可 grep 的標記能一次全包**，所以四處一律貼 `AURA_CODEX_PENDING_T<nn>` 註解，掃描範圍含 `Sources/`）。**＋暫存目錄正向對照**證明掃描沒壞（比照 CX30 的形狀） | 在 `Sources/` 與 `Tests/` 各留一個 `AURA_CODEX_PENDING_T08`（兩處都要紅） |
| **CX46 `optionsRowsCallSitePassesRealCodexState`** | AuraCore（來源掃描） | `Sources/` 不得出現字面 `codex: .unavailable` 或 `codexPathRejection: nil`——生產呼叫點必須傳**真的值**。比照既有 `L10nProductionCallSitesPassLanguageTests`（那條 gate 存在的理由與這裡一模一樣）。**為什麼需要它**：T07 在 `OptionsSectionView` 的生產渲染路徑硬編 `.unavailable`／`nil` 當 stub，而**那個 stub 的失效是靜默的**——`.unavailable` 正是目前所有測試期待的值，T08 忘了替換也沒有任何一條會紅，後果正是本 spec 花四輪在防的那類：使用者裝了 Codex、面板開了、Options 裡什麼都沒有，而全套測試綠（T07 review M1） **已知假陰性（寫進 gate 的 doc comment）**：① **跨行寫法掃不到**——`OptionsMenuModel` 換行再接 `.rows(` 時，單行比對看不見（T08 review m1 實測）；② 註解過濾有兩個缺口（block comment、行尾註解），**兩個缺口方向相反**（一個漏抓、一個誤抓），而誤抓那側**失敗得很大聲**（gate 紅在一個其實沒問題的地方，有人會去看）。CX24／CX35 的**行為斷言**才是這條路徑的主守衛，本條是便宜的第二道 | 把 view 那一行改回 `codex: .unavailable, codexPathRejection: nil` |
| **CX45 `sessionStateProductionConstructionSitesPassAgent`** | AuraCore（來源掃描） | `Sources/` 底下 `SessionState(` 的出現次數**恰為 1**，且那一處包含 `agent:`。失敗訊息寫明「新增生產建構點時必須明傳 `agent`，**預設值只服務測試**」。（T05 review m1：預設值本身是對齊既有慣例、不是 tested≠wired——生產建構點恰一個且明傳，刪掉明傳會讓既有 gate 立刻紅；殘餘缺口只有「未來新增第二個生產建構點」這個方向，本 repo 已有同型 gate 可抄：`L10nProductionCallSitesPassLanguageTests`、`HookVerificationStoreSourceScanTests`） | 在 `Sources/` 加第二個 `SessionState(` 建構點且不傳 `agent:` |
| **CX47 `codexConnectedBannerOnlyRetiresOnCodexRow`** | AuraCore | **D-v**。定義域 = `PanelBanner.Kind.allCases` ×「列組合」{空／只有 Claude 列／只有 Codex 列／兩者都有}，**程式推導、不手列**（本 gate 是 `Kind.allCases` 的**第一個消費者**）。斷言：`.connected` 只在 rows 非空時退場；**`.codexConnected` 只在 `hasCodexRow` 時退場**；其餘 kind 在**每一種**列組合下都不退場。**另加一格**：`hasCodexRow` 對「只有 Claude 列」必須是 `false`（否則整條退場條件仍舊等價於 `!rows.isEmpty`，這條 gate 會在一個壞掉的實作上全綠） | ① **`.codexConnected` 改用 `!rows.isEmpty`（＝ r12 的行為）→ 必須紅** ② `hasCodexRow` 改成 `rows.contains { $0.agentLabel != nil }`（**等價 mutant，預期綠**——目前只有兩種 agent；記進報告，說明它守的是未來的第三種 agent，不是今天的行為） |
| **CX48 `codexTrustWarningIsDrawnWithClaudeRowsPresent`** | App（view 值樹） | **D-v／D-m 的渲染那一半**。用既有的 `leafStrings(_:)`（`Mirror` 遞迴收 SwiftUI 值型別樹的 `String` 葉節點，`CodexSectionViewTests` 已在用）掃**整個 `PanelView(model:).body`**：`banner = .codexConnected` ＋ `rows = [一列 Claude 的活 session]` 時，葉節點必須同時含 `L10nCodex.nextSessionTakesEffectKeyword` 與 `codexWillAskToTrustKeyword`。**這條與 CX24④ 是同一件事的兩層**（儲存值／畫面），doc comment 互相點名。**負向對照**：`rows = [一列 Codex 的活 session]` 時兩個關鍵詞**都不得**出現（承諾已兌現，banner 該退場）——沒有這格，「永遠不退場」也會全綠 | ① **`codexConnected` 改回 `kind: .connected` → 必須紅**（這就是 persona r1 抓到的那行） ② `effectiveBanner` 的 `.codexConnected` 分支刪掉 → 必須紅 ③ 拿掉負向對照那格會讓「永遠不退場」變成綠——**報告要實跑一次確認負向那格真的有牙齒** |
| **CX49 `blockedCharacterCardWithholdsSnippetAndOffersAWayOut`** | App（view 值樹） | **D-w 的 view 層**。`.blockedByBundlePath(.unsupportedCharacter(" "))`，**輸入餵真的 `codexSnippet`**（`CodexHooksJSON.snippet(...)` 的實際輸出，路徑含空白）：葉節點必須含①那個字元（`unsupportedCharacterExplanation` 的產出）②出路句；**不得**含 snippet 的任何一段（用 snippet 的前 40 個字元當 needle，不是整串——`leafStrings` 比對的是真 `String` 值，但 needle 太長時失敗訊息不可讀）；**不得**有 `.copyCodexSnippet` 按鈕。**負向斷言餵正向輸入**（plan §0） | ① 改回會畫 snippet → 必須紅 ② 拿掉出路句 → 必須紅 ③ **把輸入的 `codexSnippet` 改成 nil → 這條 gate 會全綠**（等價 mutant；報告要寫出來，那正是 T09 review M1 抓到的形狀） |
| **CX50 `panelStatusLabelIsDualAgentAware`**（**r14 定義域釘死＋第四條斷言**） | AuraCore | **D-y 的純函式層**。定義域 = **`InstallStateAllCases.all()`**（test target 既有，由 `Reason.allCases × MountOwner.allCases` 推導，`Tests/AuraCoreTests/` 六處在用——**逐字寫這個符號，不得寫「代表值」**：手列會漏掉 `broken(reason, owner:)` 的變體，而斷言②正是為那些變體存在的）× `CodexStateKind.allCases` × 兩語言。**四條**斷言：① **`codex != .connected` → `statusLabel(l)` 逐位元組 `==` `install.healthLabel(l)`**（D-j 零 diff）；② `codex == .connected` → 含 `Agent.codex.label!` **且** `install.healthLabel(l)` 是它的**逐字子字串**（診斷資訊不得被吃掉）；③ **Codex 子句在最前面**（`hasPrefix`）——截斷時先犧牲版本號；④ **r14（解 M2③／m1）：`PanelModel.make(...)` 產出的 `title` 在 `install` 非 connected 時逐位元組 `==` `statusLabel(l)`**——把三處裡**住在 AuraCore 的標題那一處**下推到純函式層守，view 層的 CX51 因此只需要分辨另外兩處 | ① `statusLabel` 忽略 `codex`（直接回 `healthLabel`）→ ②③ 紅 ② 無條件加子句 → ① 紅 ③ **把 Codex 子句改到尾端 → ③ 紅** ④ 把 `.connectedStalePath` 也算成「已接上」→ ① 紅 ⑤ **r14：`title` 的非 connected 分支改回 `install.healthLabel` → 第④條必須紅** |
| **CX51 `dualAgentStatusLabelReachesAllThreeSites`**（**r14 改方法**） | App（view 值樹） | **D-y 的接線層**。`install = .notConnected` ＋ `codex = .connected` ＋ `rows = [一列 Codex 的活 session]`（＝ persona r1 的頭號情境，證據圖 #12）。**r13 的寫法（「三處都 `contains(statusLabel)`」）對它自己宣告的三個 mutation 全部不紅**：三處渲染的是**同一個字串**，而 `leafStrings` 回的是**扁平陣列**，任一處改回 `install.healthLabel` 之後另外兩處還在，`contains` 仍然成立——**這是本批最容易 vacuously green 的一條**。r14 改成**三條可分辨的斷言**：① **footer 比對複合字面** `"\(statusLabel) · v\(version)"`（版本後綴讓它唯一）；② **裸 `statusLabel` 葉節點出現次數恰為 2**（標題＋CTA 窄條；任一處被改回就變 1）；③ **`install.healthLabel(l)` 不得以裸葉節點單獨出現**（改回去的那一處會產生這個葉節點）。標題那一處另由 **CX50④** 在純函式層守，兩條互相點名 | 逐處各一，**三個都要跑、報告逐處記**：① footer 改回 `install.healthLabel` → 斷言①紅；② 標題改回 → 斷言②（2→1）＋③紅，**且 CX50④ 也必須紅**；③ CTA 窄條改回 → 斷言②（2→1）＋③紅 |
| **CX52 `healthLabelReadersAreTheNamedSet`**（**r14 改名＋補 AuraCore root**） | 來源掃描（兩個 root） | **D-y 的來源推導半**，**兩格**：① `Sources/AgentAuraApp/` 底下 `.healthLabel(` 命中數**恰為 0**；② `Sources/AuraCore/` 底下含有 `healthLabel(`（**無前導點**）的**檔案集合恰等於一個具名清單**——`InstallAffordance.swift`（宣告處）、`TooltipText.swift`、`PanelBanner+InstallerFailure.swift`、`PanelModel+ConnectCTA.swift`（`statusLabel` 唯一讀取點）。**兩格的 pattern 刻意不同**（r15／r14 review n2，已實跑確認）：①格用 **`.healthLabel(`（有前導點）**，因為 App 層要抓的是**讀取點**（`x.healthLabel(...)` 這種呼叫式），宣告不在那一層；②格用 **`healthLabel(`（無前導點）**，因為具名集合**必須包含宣告處** `InstallAffordance.swift`，而宣告寫的是 `public func healthLabel(`，有點的 pattern 抓不到它。2026-09-21 實跑：AuraCore 無點 **5 命中／4 檔**、有點 **4 命中／3 檔**，差的正是宣告處。**pattern 寫錯會在 T13f 落地當天就紅（3 檔 vs 清單 4 檔），而最省事的「修法」是把宣告處從清單刪掉——那會讓基準少守一個檔。** **用具名檔案集合、不用命中數**（數字會被無關的增刪推著走，集合不會）。**r14 為什麼要第二格**（r13 review m1）：三處顯示點裡**標題住在 AuraCore**（`PanelModel.swift:157`），只掃 App 層等於只守到 2/3，而 r13 的風險表卻寫「站點集合 source-derived」——那是 overclaim。第二格讓 AuraCore 側也 source-derived：**把讀取點加回 `PanelModel.swift` 會讓集合多一個元素而紅**。標題那一處的**行為**由 CX50④ 守。**已知假陰性**（寫進 doc comment）：跨行寫法與 block comment 兩個缺口，同 CX46 | ① 在任一 view 加回一行 `model.install.healthLabel(model.language)` → 第①格紅 ② **r14：把 `title` 的讀取點改回 `PanelModel.swift` → 第②格紅**（集合多一個檔） |
| **CX53 `emptyRowsMessageIsAgentAware`** | AuraCore | **D-z**。定義域 = `CodexStateKind.allCases` × 兩語言。`codex == .connected` → 含 `Agent.codex.label!`；其餘**逐位元組等於** r12 的那句（期望值**寫死字面**，不引用 `L10nPanel.emptyRowsMessage`——拿產生器跟自己比的老陷阱，本 change 已踩過兩次） | ① 一律回舊句 → `.connected` 那格紅 ② 一律回新句 → 其餘五格紅 |
| **CX54 `occupiedCardTellsYouToMergeAndOffersHelp`** | App（view 值樹） | **D-aa**。`.occupiedByOther` ＋ 真 snippet：葉節點必須含合併指示那句；且卡片內**存在**一顆送出 `.openHelp` 的按鈕（走既有「點遍每顆按鈕收集 `PanelAction`」的手法，**不用陣列索引**）。**負向對照**：`.occupiedByOther` ＋ `codexSnippet == nil` 時**不得**有合併指示與 help 按鈕（沒有東西可併） | ① 拿掉合併指示 → 必須紅 ② 把 help 按鈕改送別的 action → 必須紅 ③ 讓 `codexSnippet == nil` 那格也畫合併指示 → 負向那格必須紅 |
| **CX55 `helpDocsExplainMergingIntoExistingHooks`** | 文件 | **D-aa 的落點**：`Resources/help-english.html` 與 `help-traditionalChinese.html` **兩份都**必須有「併進既有 hooks 物件、不要整份取代」的說明（`@Test(arguments:)` 參數化兩份，**不是兩條各寫一遍**——CX29 的既有教訓：內容有、守衛沒有，刪掉兩邊只紅一條）。UI 把使用者指過去，那邊就必須有東西 | 從**任一份**刪掉那段 → 必須紅（兩份各試一次） |
| **CX56 `snippetCardFitsOnA13InchScreen`**（**r14 補兩個維度**） | App（渲染後座標） | **D-ab**。`optionsExpanded == false`，定義域 = `CodexStateKind.allCases.flatMap(CodexState.samples)` × 兩語言 × {rows 空, 3 列} × **`install ∈ {.connected, 一個由 T13i 實測選出的非 connected 代表值}`** × **`banner ∈ {nil, .codexConnected}`**（**全部程式推導**，五個維度的乘積）：`preferredContentSize.height ≤ 780pt`；且在 snippet 那些態，「複製」按鈕與 footer 按鈕**轉換到 hosting 座標後**的 `minY` 都 `< 780`。按鈕身份**用點擊辨識**（`FooterPositionStabilityTests` 的既有手法），**不得用陣列索引**。**另加一格**：snippet 區塊高度**不得低於 6 個視覺列**（下限，防止「把 snippet 壓成一條縫」變成讓這條 gate 變綠的最省事動作）——**這一格的基準由本 gate 在 App 層渲一段 6 行等寬文字量出來**，不是 AuraCore 的常數（r15／n4）。**`install` 的代表值由 T13i 實測四種 affordance 之後釘死**（r15／n3），不是挑 `.connect`。**語意前置條件（r15／N1）**：`banner` 那一維**要求 `PanelBanner.Kind.codexConnected` 已經存在且 `effectiveBanner` 已依 kind 分流**（T13b）——在那之前 `.codexConnected` 仍是 `kind: .connected`，`effectiveBanner` 在 rows 非空時把它吃掉，那些格會與 `banner: nil` 量到**完全相同**的高度，**整維惰性**。doc comment 要寫「紅掉時的第一個問題是面板是不是又長高了」（§4.10）。**r14 理由**：r13 的域沒有 `install` 也沒有 `banner`，而最壞組合（整版 CTA ＋ 有 snippet 的卡片 ＋ 尚未退場的 `.codexConnected` banner）**從未被量過**——證據圖 `05`／`07` 兩張都是 `install: connected`。**另一個前置條件（r2 review N2，T13f→T13i）**：標題（`PanelView.swift` 的 `Text(model.title)`）在 `codex == .connected` 時**沒有 `lineLimit`**，全域（29 個非 connected `InstallState` × 兩語言 = 58 格）實測 **34/58 格會換行**，最壞情境（`.broken(.hookUnconfirmed, owner: .thisApp)`、英文）真渲染面板高度 **250.0pt → 266.0pt（+16.0pt）**——T13i 的基準表與 780pt 天花板都要把這個換行代價算進最壞組合，不能只用未換行的標題高度推算（數字見 §10-22 與 DoD #33） | ① 拿掉 snippet 的固定高度（改回無上限）→ 必須紅 ② **改成 `.frame(maxHeight:)` 而不是固定高度 → `FooterPositionStabilityTests` 必須紅**（T22 的既有教訓，兩條一起看） ③ **r14：把域縮回「只有 `install: .connected` ＋ `banner: nil`」→ 必須能重現 r13 的假綠**（T13i 報告要附這一格的實跑輸出：同一個 snippet 上限下，窄域全綠、全域紅） ④ **r14：把 snippet 下限拿掉並把上限壓到 1 列 → 下限那格必須紅** |
| **CX57 `codexDisconnectGoesThroughConfirmation`** | App（接線） | **D-ac**。注入一個**不呼叫** `onConfirm` 的 `confirmDisconnectCodex` → 送 `.disconnectCodex` → `fakeInstaller.disconnectCallCount == 0`、憑證鍵位元組不變；換成**會呼叫**的 → `== 1`。**另加**：確認框文案必須含 `Agent.codex.label!`（點名 agent，對照既有 `L10nConfirmationAlerts.disconnectTitle` 已經點名 Claude Code） | ① 把 `case .disconnectCodex` 改回直接呼叫 `performDisconnectCodex()` → **第一格必須紅** ② 確認框文案拿掉 agent 名 → 第三格紅 |
| 既有全部 gate | — | 繼續綠（尤其 `registeredEventsMatchHandledEvents`、`installerTouchesOnlyAllowedPaths`、`everyFixtureModelIsMapped`（**目前紅，本 change 必須修好**）、`fileLengthLimit`、`nonUITargetsLoadNoUIModules`、`noStrayLiteralOutsideAllowlist`、`panelModelMakeHasNoDefaults`、`RowHeightDerivationTests`、`FooterPositionStabilityTests`） | — |

### 6.4 test-edit scrutiny 預告（Lessons #3）
1. `nonMenuKindsIsExactlyThatLiteralSet`：四個 → 五個（契約變更不是弱化）；
   **連帶**改 `OptionsMenuModel.swift` 逐字寫著「字面集合恰為這四個」的 doc comment。
2. `PanelModel.make` 新增無預設值參數 → **63 個呼叫點（27 個檔）**（T08 實測；以括號配對量，`grep 'PanelModel\.make('` **抓不到隱式成員寫法** `spy.setPanel(.make(icon: …))`）。
3. `MergeRules.merge` 新增 `agent:` → **7 個呼叫點**。
4. `OptionsMenuModel.rows` 新增 `codex:` → **26 個呼叫點（10 個檔）**。
4b. **`SessionState.init` 的 20 個測試建構點（19 個檔）——第四條 fan-out**（T05 review m4）。
   **本條以預設值 `.claude` 吸收**，不是 94 個呼叫點那種逐點改：`SessionState.init` 本來就有
   `toolDescription`／`notificationMessage` 兩個預設值，不是為了這次方便而發明的慣例；
   **生產建構點恰好一個**（`SessionReducer`）且明傳 `agent:`。理由與守衛見 `SessionState.agent`
   的 doc comment 與 **CX45**（來源掃描，防的是「未來新增第二個生產建構點時忘了傳」）。
   **這條要記在帳上**——T08 做 `PanelModel.make` 那 61 處時，帳上三條與實際四條對不起來，
   而「有幾條 fan-out」正是 test-edit scrutiny 用來判斷「這批機械改動有沒有夾帶弱化」的基準。
5. **無預設值參數的呼叫點計數不再是驗收條件**（T08 裁決 1）——**編譯器已經代答了**：
   三個新參數都沒有預設值，所以「有沒有漏」由編譯通過證明，grep 的數字對它零貢獻。
   而那個數字**已經連錯五次**（T02 差 3、T03 差 3、T04 差 1、T05d 差 51、T08 的隱式成員寫法漏抓）。
   計數**只作報告資訊**，不作驗收。真正需要數字的是 `#expect(` 淨增（編譯器代答不了），
   而它一律用**合併後 head 的絕對值**。
5b. 上面 2／3／4 合計 96 個呼叫點（**4b 不計入**，它以預設值吸收）：**`#expect(` 淨數量不得下降**
   （基準 **1649**，量法見 DoD #2 的更正）。
6. `HelpDocOptionsRowCoverageTests.allRows` 改成對 `CodexStateKind.allCases` 取聯集。
7. `ClaudeHomeTreeSnapshot` 抽成共用 `DirectoryTreeSnapshot`（CX14／CX32／CX37a／CX37b 共用）——**純重構**，
   既有 `installerTouchesOnlyAllowedPaths` 全綠且 **mutation 當場重跑**確認仍精準紅。
8. **`JargonTests.modelTwoNonNumericSegmentsPassesThrough`**（§4.9）：輸入從 `gpt-4o` 換成
   非 Codex 家族的例子以保住原性質，**另外新增**一列釘死 `gpt-4o` 的新期望值。
   直接刪掉那條測試＝弱化，要退回。
9. **`PanelAction.samples` 的 doc comment** 補「`switch` 不得有 `default`」一句（r3 m2，順手，零風險）。
10. **r13：`CX40` 改名 `codexSnippetIsWithheldWhenPathWillVanish` → `codexSnippetIsWithheldForEveryPathRejection`
   ＋ 期望值整欄翻轉**。判準三欄：改前「`.unsupportedCharacter` 整行非 nil」／改後「整行 nil」／
   **測的還是同一件事嗎：是**——被測性質仍是「snippet 有沒有穿過路徑判定」，**斷言變強**（多一整行從
   「非 nil」變成「nil」），格數不變，定義域不變。**名字必須跟著改**：「會消失」不再是判準，
   留著舊名會讓下一個人照名字推回舊條件。這是契約變更，不是弱化。
11. **r13：`CX36` 的 `.unsupportedCharacter` 那格輸入從 nil 改成真 snippet ＋ 新增兩條斷言**
   （不得畫 snippet／必須畫出路句）——同 T09 review M1 對 `.mustMoveToApplications` 那格做過的事，
   **斷言數增加、沒有任何既有斷言被移除或放寬**。
12. **r13：`PanelModel.emptyRowsMessage` 的既有斷言**（若有測試釘死那句字面）改成**依 `codex` 分兩格**：
   舊字面留在「非 `.connected`」那格（逐位元組不變），新字面另加一格。**直接把舊斷言改成新字面＝弱化**
   （會讓「一律改成新句」這個 mutation 全綠），要退回。
13. **r13：`AppDelegatePanelActionsWiredTests+Codex.swift` 的 `.disconnectCodex` 那格**必須改成
   「經確認框才有副作用」——**注入的 `confirmDisconnectCodex` 預設不得是「直接呼叫 onConfirm」的假身**，
   否則 CX57 的第一格（不確認 → 零副作用）在任何實作下都成立。改前／改後／原意三欄照列。

### 6.5 已知不可測（寫進 §10 與最終報告）
- Codex 是否真的載入並執行我們寫的 hooks.json（F12）→ 實機 ②③。
- 信任提示的 UX 與「拒絕信任」的行為（F5）→ 實機 ④。
- `PermissionRequest`／`Interrupt`／`Subagent*` 的實際 payload 形狀（F10）→ 互動探針。
- hook 父行程的 `comm` 與**互動 TUI 的行程結構**（F15 範圍限定）→ 互動探針 ＋ 實機 ③。
- 含空白路徑＋引號的 `command` 是否可行（R-7）→ 互動探針工具包。
- **兩側同時真的在跑**（R-8 不變式 2 的人類面）→ 實機 ⑧（CX38 只驗到同一顆二進位與兩邊 `agent` 各自正確，
  沒有驗到兩個上游**同時**真的觸發它）。

## 7. DoD

門檻與量法見 `docs/superpowers/plans/2026-09-18-codex-support-dod.md`（每條有數字）。

## 8. 檔案佈局與回寫

### 8.1 檔案（估行；`Sources/` 基準 7846 行）
```
Sources/AuraCore/Agent.swift                       新  ~60
Sources/AuraCore/EventMapping.swift                改  +25
Sources/AuraCore/CodexHooksJSON.swift              新  ~80
Sources/AuraCore/CodexHookPathCheck.swift          新  ~75（＋RejectionKind／Rejection.samples，r4）
Sources/AuraCore/CodexState.swift                  新  ~115（逼近 200 就把 CodexFailure 拆檔）
Sources/AuraCore/Jargon.swift                      改  +30（Codex 家族分支；既有六條規則一行不動）
Sources/AuraCore/SessionSnapshot.swift             改  +10
Sources/AuraCore/MergeRules.swift                  改  +6
Sources/AuraCore/SessionReducer.swift              改  +2
Sources/AuraCore/SessionState.swift                改  +5
Sources/AuraCore/PanelViewModel.swift              改  +6
Sources/AuraCore/PanelAction.swift                 改  +27（三個 case × kind × samples ＋ default 禁令註解）
Sources/AuraCore/OptionsMenuModel.swift            改  +26（六態＋stale 兩種列數 ＋ 註解修正）
Sources/AuraCore/PanelModel.swift                  改  +14
Sources/AuraCore/L10nCodex.swift                   新  ~145（含兩種 Rejection、stale 兩句、snippet withheld 一句、七個 CodexFailure）
Sources/AuraHookFile/CodexInstaller.swift          新  ~125
Sources/AuraHookFile/CodexInstaller+Probe.swift    新  ~70
Sources/aura-hook/main.swift                       改  +3
Sources/AgentAuraApp/CodexHookStore.swift          新  ~45
Sources/AgentAuraApp/CodexSectionView.swift        新  ~130（六態＋兩種 Rejection＋snippet 有無）
Sources/AgentAuraApp/AppDelegate+Codex.swift       新  ~120（五個行程常數欄位＋前置 guard＋四個 perform）
Sources/AgentAuraApp/AppDelegate+Links.swift       新  ~45（**純搬移，r9 起落在 T07**）
Sources/AgentAuraApp/AppDelegate+PanelActions.swift 改 −45 +8
Sources/AgentAuraApp/PanelView.swift               改  +8
Sources/AgentAuraApp/Uninstaller.swift             改  +8
Sources/AgentAuraApp/AppDelegate.swift             改  +10
                                                   合計 ≈ +1060（門檻 1150，§7；r3 是 975／門檻 1050，
                                                   r4 增量＝Jargon +30、RejectionKind +20、
                                                   stale/snippet 兩種文案與分支 +35）
Tests/AuraCoreTests/Fixtures/round4-codex.ndjson   已就位（18 筆／4 個 session，唯讀證據）
Tests/AuraCoreTests/*（新）：AgentArgumentTests、CodexEventSeamTests、CodexHooksJSONTests、
  CodexHookPathCheckTests、CodexStateTests、CodexOptionsRowTests、CodexInstallerTests、
  CodexInstallerClobberTests、CodexPathScopeTests、CodexCoexistenceSequenceTests（CX37a／CX37b）、
  Round4FixtureTests、AgentSnapshotCodableTests、JargonCodexModelTests（CX41）
Tests/AuraCoreTests/Support/DirectoryTreeSnapshot.swift  新（從 ClaudeHomeTreeSnapshot 抽出，純重構）
Tests/AgentAuraAppTests/*（新）：CodexWiringSmokeTests、AppDelegateCodexWiredTests、
  CodexHookStoreTests、CodexRowLabelPixelTests、CodexSectionRenderTests（CX36）、
  CodexCredentialSequenceTests（CX42）、
  Support/FakeCodexInstaller、Support/FakeCodexStore
Tests/AuraCoreTests/EndToEndWiredGateTests.swift   改（CX38 兩個方向；注意 300 行上限，必要時拆
                                                   EndToEndDualAgentTests.swift）
scripts/verify-uninstall.sh                        改（第 7 項 ＋ CODEX_HOME ＋ --only ＋ 第 2 行註解）
```

**r13（persona r1 修復批次，T13）的增量估算**——`Sources/` 起點是 **HEAD 的 9403 行**（不是 7846）：

| 檔案 | 估 | 內容 | 上限餘裕 |
|---|---|---|---|
| `Sources/AuraCore/PanelModel+ConnectCTA.swift` | 改 +30 | `hasCodexRow`／`statusLabel(_:)`／`effectiveBanner` 依 kind 分流（D-v／D-y） | 81 → 111 |
| `Sources/AuraCore/PanelModel.swift` | 改 +8 | `PanelBanner.Kind.codexConnected`／`emptyRowsMessage` 分兩句（D-z） | 172 → 180（**餘裕 20**） |
| `Sources/AuraCore/L10nCodexCards.swift` | **新 ~70** | 卡片新文案獨立一個 `L10nCatalog`：出路句（`.unsupportedCharacter`）、合併指示、help 按鈕字樣、stale 中性開場（D-w／D-x／D-aa）。**不塞進 `L10nCodex.swift`**：那個檔 158/200，三個新 case 連 doc 會撞上限，而 `text(_:)` 的窮盡 `switch` 無法跨檔拆（同 `L10nUninstallConfirmation` 從 `L10nConfirmationAlerts` 分出去的既有理由）。**也不塞進 `L10nPanel.swift`**（r13 review (c) 問過）：那個檔 **55/200**、行數確實塞得下，省下的是約 25–30 行檔頭／enum 骨架／registry 登記——但 `L10nPanel` 的既有語意是**面板本體的通用字串**（空列訊息、CTA 按鈕、求助按鈕），把 Codex 卡片的四句塞進去會讓「哪個 catalog 管什麼」這條線消失，而本 change 已經為了同一個理由把 `L10nCodex+Failures` 拆出去過。**DoD #7 早已是宣告的 MISS，30 行不改變結論**；可 grep 的獨立 catalog 對下一個維護者更值錢。**必須登記進 `L10nRegistry.allEntries`**，否則 `L10nRegistryCoverageSourceScanTests` 紅 | 新檔 |
| `Sources/AuraCore/L10nCodex+Failures.swift` | 改 +12 | `codexConnectedStatus(claudeHalf:language:)` 帶參數模板（D-y），同 `unsupportedCharacterExplanation` 的既有形狀 | 75 → 87 |
| `Sources/AuraCore/L10nPanel.swift` | 改 +10 | `emptyRowsMessageWithCodex`（D-z） | 55 → 65 |
| `Sources/AuraCore/L10nConfirmationAlerts.swift` | 改 +40 | Codex 移除確認框的三句（D-ac） | 115 → 155 |
| `Sources/AuraCore/CodexHooksJSON.swift` | 改 +4 | `withheldSnippet` 條件 `== .mustMoveToApplications` → `!= nil` ＋ 理由（D-w） | 79 → 83 |
| `Sources/AuraCore/CodexSnippetSizing.swift` | **新 ~40** | snippet 區塊的固定高度推導（D-ab），形狀照抄 `SessionsCardSizing` | 新檔 |
| `Sources/AgentAuraApp/CodexSectionView.swift` | 改 +35 | 合併指示＋help 按鈕、snippet 包 `ScrollView` 吃固定高度、withheld 理由依 rejection 分流、stale 拆兩段、`.unsupportedCharacter` 改成不給 snippet | 117 → 152 |
| `Sources/AgentAuraApp/PanelFooterView.swift` | 改 +1 | chip 改讀 `statusLabel` | 37 → 38 |
| `Sources/AgentAuraApp/PanelView.swift` | 改 +1 | CTA 窄條 label 改讀 `statusLabel` | 189 → 190（**餘裕 10，最緊**） |
| `Sources/AgentAuraApp/AppDelegate.swift` | 改 **−78 +8** | 純搬移 `applicationDidFinishLaunching` 出去（T13a）＋ 第四個確認注入縫（D-ac） | 196 → **≈ 126** |
| `Sources/AgentAuraApp/AppDelegate+Lifecycle.swift` | 改 **+78** | 接收純搬移（`applicationWillTerminate` 已住在這裡） | 23 → ≈ 101 |
| `Sources/AgentAuraApp/AppDelegate+PanelActions.swift` | 改 +2 | `.disconnectCodex` 包確認框 | 175 → 177 |
| `Sources/AgentAuraApp/AppEnvironment.swift` | 改 +16 | `CodexDisconnectConfirmation`（照 `DisconnectConfirmation` 的形狀，共用 `ConfirmationAlert.present`） | 133 → 149 |
| | **≈ +270** | 純搬移淨 0；新檔兩個共 110 行是最大單項 | |

**DoD #7 的處置（誠實記錄，不調門檻）**：`Sources/` 淨增門檻是 **1150**，T12 實測已經是 **+1527**（MISS 377）。
r13 再加約 **270**，合計約 **+1797**（MISS 約 647）。**門檻不往上調**——本專案已有兩次「如實記錄不調門檻」
的前例（+292 KB、+746 KB）。要說清楚的是：這 270 行買的是**兩條 S0 的關閉**，
而 S0 的替代方案是「維持 NO-GO」，不是「省 270 行」。是否重設基準是**使用者的裁決**，
不是 spec 或 implementer 可以自己做的（同 §7 那句「若 R-5／R-6 日後被砍，門檻要跟著降回」的對稱處置）。

**單檔上限的八個風險點**：

| 檔案 | 現況行數 | 上限 | 要加什麼 | 處置 |
|---|---|---|---|---|
| `Sources/AgentAuraApp/AppDelegate+PanelActions.swift` | **200** | 200 | 三個新 case（**T07**，它的 `switch action` 窮盡無 `default`）＋ `refreshPanel` 帶 codex（T10） | **T07 第一步 (b)** 預先搬移到 `AppDelegate+Links.swift`（r9：原排 T10，但加 case 與讓它編得過必須在同一個 task） |
| `Tests/AuraCoreTests/OptionsMenuModelTests.swift` | **300** | 300 | CX20／CX21 ＋ `rows(` 新參數 | T07 第一步拆 `CodexOptionsRowTests.swift` |
| `Tests/AgentAuraAppTests/AppDelegatePanelActionsWiredTests.swift` | **300** | 300 | `panelActionsAreWired` 涵蓋 3 個新 kind | T10 第一步拆 `AppDelegateCodexWiredTests.swift` |
| `Tests/AuraCoreTests/MergeRulesTests.swift` | 294 | 300 | `merge(` 新參數（1 處） | 餘裕 6 行 |
| `Tests/AuraCoreTests/PanelViewModelTests.swift` | 288 | 300 | CX22 的 model 半 | 餘裕 12 行；寫不下放 `CodexRowLabelPixelTests` |
| `Tests/AuraCoreTests/EndToEndWiredGateTests.swift` | 149 | 300 | CX38 兩個方向 | 餘裕充足；超了就拆 `EndToEndDualAgentTests.swift` |
| `Sources/AuraCore/CodexState.swift`（新） | — | 200 | 六態 ＋ Kind ＋ samples ＋ `CodexFailure` | 估 ~115；逼近 200 就把 `CodexFailure` 拆檔 |
| **`Sources/AgentAuraApp/StatusItemController.swift`** | **200** | 200 | **本 change 預期不動它**——它的佔位 model 永遠是 `.unavailable`，不隨 Codex 狀態變（那是 popover 掛載前的必要佔位：`contentViewController == nil` 時 `NSPopover.show` 會丟 NSException 殺行程），`AppDelegate` 首次 `refreshPanel()` 就會覆蓋 | **寫觸發條件，不做預防性搬移**（T08 裁決 6）：**若** T09／T10 發現必須在這個檔加任何一行，**先停下來**做一次零行為變更的純搬移 commit（照 T07 `AppDelegate+Links.swift` 的形狀：`#expect(` 前後不變、被搬函式名一字不改），**不准刪註解或空行擠**。為沒人要碰的檔做預防性搬移是 churn，而純搬移本身也有風險（T07 兩次都撞到別的 gate） |

### 8.2 回寫（逐句）
| 位置 | 改為 |
|---|---|
| 正典 §2.2 對照表 | 加 `Interrupt → idle`（Codex only，**不得**進 `handledEvents`）；點名它與 `is_interrupt` 是兩件事 |
| 正典 §2.1 檔案契約 | 加 `agent`（Optional，nil = claude）與 D-a／D-c 的理由 |
| 正典 §3.2 安裝機制 | 加「第二個入口：Codex 讀 `~/.codex/hooks.json`（F1、F14），只在不存在時寫、只在內容相符時刪、絕不碰 `config.toml`；bundle 路徑不合法時不寫、改畫解釋」**＋ R-8 的兩側互不干擾不變式** |
| **app-shell spec（`2026-09-10-app-shell-design.md`）§3.4 文案映射（M-7，D-c）** | 加「`Jargon.model` 同時認得 Claude 家族與 Codex 家族的命名；判不出來一律原樣回傳」。**不是正典的 §3.4**（T11 review m3／問題 6）：兩份 spec 撞章節號——正典的 §3.4 是別的主題，而 `Jargon.swift` 第 3 行的麵包屑指的是 app-shell 那一份。回寫要落在被指名的那份文件上，否則下一個人照麵包屑找過去會看不到 |
| 正典 §3.5 pid liveness | 加「Codex 的 hook 父行程在 session 內 pid 穩定（F15，**exec 模式實測**），判活前提成立；互動 TUI 的行程結構與 `comm` 未辨識」 |
| 正典 §3.7 面板內容 | 加「非 Claude 的 session 在列的第一行帶 agent 標籤；聚合燈不分 agent」 |
| 正典 §9 開放風險 | 加「Codex 無 error 來源」「無法偵測信任狀態」兩條 |
| `CLAUDE.md` Invariants | 加「`CodexInstaller` 只准碰 `<codexHome>/hooks.json`；`config.toml` 位元組不得變動」「`Interrupt` 不得進 `handledEvents`」**「對任一側的安裝操作不得改動另一側的任何位元組」** |
| `CLAUDE.md` Tier 1 清單 | 加 `CodexSectionView.swift`、`AppDelegate+Codex.swift`、`Sources/AuraCore/CodexState.swift` |
| `CLAUDE.md` Project 狀態 | 加 codex-support 一行 |
| `README.md` ＋ `.zh-TW` §「What it does to your Mac」 | 加 `~/.codex/hooks.json` |
| `SECURITY.md` §「What this tool can do on your machine」＋「Boundaries that are enforced by tests」 | 加 `~/.codex/hooks.json` 與「`config.toml` 位元組不變」**「兩側互不干擾」**。**注意**：`SECURITY.md` 沒有叫「What it does to your Mac」的段落，那是 `README.md:160` |
| `docs/INSTALL.md` ＋ `.zh-TW` | 新增「Using it with Codex」；troubleshooting 加兩條（信任提示／暫時把 `timeout` 改 5 看 clamping 警告） |
| `Resources/help-*.html` 兩份 | 新增「Codex」段（CX28 強制涵蓋**每一個**新的 Options 列標題，含「重新接上 Codex」）。**r13（D-aa／CX55）**：兩份都要有「把 entry **併進**你現有的 hooks 物件、**不要整份取代**」的說明——面板把使用者指過去，那邊就必須有東西。現況兩份只說「shows a snippet to add by hand instead」／「只會顯示一段可以手動貼上的設定」，**沒有講「不要整份取代」** |
| **`CLAUDE.md` Invariants（r13）** | 加「**面板的三處狀態字串（標題／footer chip／CTA 窄條）在 Codex 已接上時不得只反映 Claude**」（D-y；gate `panelStatusLabelIsDualAgentAware`／`dualAgentStatusLabelReachesAllThreeSites`／`healthLabelReadersAreTheNamedSet`）與「**`.codexConnected` banner 只在出現 Codex 的列時退場**」（D-v；gate `codexConnectedBannerOnlyRetiresOnCodexRow`／`codexTrustWarningIsDrawnWithClaudeRowsPresent`）。**只列已經存在的 gate 名**（T11 review m2 的既有規則：不提前列入還不存在的名字） |
| **`docs/INSTALL.md` ＋ `.zh-TW`（r13）** | 「State directory」那節仍寫「one file per **Claude Code** session」，但 Codex 的 session 也落在同一個目錄（persona r1 S2-6）——這是本 change 造成的事實錯誤，一行改掉 |

## 9. Persona Impact

### 9.0 persona-tester 開工前必看的三件事（T09 review 附）

1. **同一張畫面上可能出現兩張「還沒接上」的卡片，而 translocated 時兩張會講逐字相同的一句話。**
   T09 的自主判斷 (c) 重用了 `InstallerFailure.mustMoveToApplicationsMessage`（泛用「App」措辭）——
   那是對的（成因與出路本來就跟 Codex 無關，另寫一句只會讓同一件事有兩種說法），
   但 translocated 時 Claude 卡與 Codex 卡**同時**顯示，使用者會在同一張畫面上看到逐字相同的句子兩次。
   **P1 要判的是「30 秒內知道該按哪個」，外加「讀起來像不像重複印刷的 bug」**——這是 spec 沒有預見的一格。
2. **有兩句話是產品的誠實底線，不是文案偏好，改不得。** D-m 的 banner 必須**同時**講「下一個 Codex
   session 起生效」與「Codex 會問你一次是否信任」（F5：偵測不到信任狀態，所以不能寫「已生效」）；
   `.blockedByBundlePath(.mustMoveToApplications)` 必須**不給** snippet（D-s）。
   persona 若覺得囉唆而建議精簡，**請先讀 §10-3 與 D-s**——它們是被四輪 review 推出來的。
3. **r13 追加：這一輪的修法都落在「既有的 Claude-only 表面」上**。r1 的失分集中在三個沒被 diff 動到的
   推導（A7 的退場條件、三處狀態字串、空列句），r13 把它們改成 agent 感知。
   **請特別重打那三個地方**：① 接上 Codex 之後、面板上**有別的 agent 的列**時，那兩句信任警語還在不在；
   ② 只接 Codex 時，標題與 footer chip 寫什麼；③ `.unsupportedCharacter` 的卡片**現在不給 snippet 了**，
   要判的是「它有沒有給我一條真的能走的出路」，不是「為什麼不給我 snippet」（不給的理由見 D-w／§10-17，
   那是四輪 review ＋ 一輪 persona 推出來的，不是遺漏）。
4. **Codex 的燈永遠不會變紅，這是平台限制不是 bug**（F2／F4，§10-2）。兩個語言的 help 都有明講，
   但 `docs/INSTALL.md` 的「Codex: the light never moves」那一節只講了信任提示（T11 review m4，T12 補）。
   **扣分要分清楚是「產品做不到」（已知、不可改）還是「畫面沒講清楚」（可改，而且 INSTALL 那節正是該補的地方）。**

### 9.1 persona-tester r1 結果與本批修復的對應（2026-09-21，NO-GO）

**加權 5.68／門檻 6.0 → NO-GO**。三條規則各自獨立成立（兩條 S0 硬否決／P2 低於自己的下限／加權不足）。

| persona | 權重 | 得分（×2） | 下限 | 判定 | 主要失分點 → r13 的處置 |
|---|---|---|---|---|---|
| P1 只用 Codex | 0.85 | **6.0** | ≥5 | PASS | 三處狀態字串只反映 Claude（S1-1）→ **D-y**；空列句只講 Claude（S1-2）→ **D-z**；`.connected` 零常駐確認（S2-3）→ **D-y 順帶關閉**（只接 Codex 時 chip 與標題都寫著「Codex connected」） |
| P2 已有自己 hooks.json | 1.00 | **5.2** | **≥6** | **FAIL** | 遞出含壞路徑的 snippet（S0-2）→ **D-w**；零合併指示（S1-3）→ **D-aa**；面板被裁、不可捲（S1-4）→ **D-ab**；stale 那句可查證為假（S2-1）→ **D-x**；證據圖失真（S1-6）→ **D-ad** |
| P3 不懂信任提示 | 1.00 | **5.2** | ≥5 | PASS（**內含 S0**） | 信任警語在常見路徑上根本不顯示（S0-1）→ **D-v**；legend 的「Error」沒有通往「Codex 沒有 error 燈」的路徑（S2-4）→ **§10-18，本批不做** |
| P4 兩個都用 | 0.95 | **6.4** | ≥5 | PASS | Codex 移除無確認框、刪節號說謊（S1-5）→ **D-ac**；列上的「Codex」標籤與權限文字同字級同色（S2-2）→ **§10-19，本批不做** |

**r2 retest 的通過條件**（同步寫進 DoD 帳本）：兩條 S0 全關 · 七條 S1 全關**或**在 spec 明寫接受並附理由 ·
四條硬下限全過 · 加權 ≥ 6.0。

**r13 刻意不做的三件事（persona 若再扣分，請扣在「已知且明寫接受」那一欄）**：
1. **legend 的「Error」→「Codex 沒有 error 燈」的面板內路徑**（S2-4）。legend 是**兩側共用**的元件、
   ⓘ 是 tooltip 不是按鈕（`LegendRowView.swift:53-54`），改它的影響面大於本 change；兩份 help 都已明講。§10-18。
2. **列上「Codex」標籤改成膠囊／不同色調**（S2-2）。會動到 `CodexRowLabelRenderTests` 從真實 view 推導的
   43／59pt 列高守衛，而 P4 已經 PASS（「分得出來」這一題達成）。§10-19。
3. **Claude 側 CTA 按鈕從「Connect」改成「Connect Claude Code」**（P1 提到的「泛稱那顆看起來才像主要動作」）。
   那是 **Claude-only 表面的文案變更**，會動到 `L10nPanel.connectCTAConnect` 與兩份 help 的既有字面，
   而 P1 自己把它評為「只是小摩擦」且該題 PASS。§10-21。

- **只用 Codex 的人**：Claude 側是 `.notConnected`（大版說明），Codex 的提示在它下面（R-3 單行）。
  persona 要回答「兩個東西疊在同一張畫面上時，第一次看得懂要按哪個嗎」。
- **兩個都用的人（P4）**：列上只有 Codex 有標籤；同一專案同時跑兩邊時兩列 `projectName` 一樣，
  **只靠標籤區分**。R-8 之後還要回答：兩側都接上時，**兩邊的燈都真的會動嗎**（實機 ⑧）。
- **已有自己 `~/.codex/hooks.json` 的進階使用者（P2）**：最在意「會不會蓋掉我的」。
  **R-5／R-10 之後 P2 有三條具體要求**（不另開硬下限）：① 被拒時文案**指名是哪個字元**；
  ② 拒絕必須給**出路**；③ **從 DMG／下載資料夾打開時，我們寧可不給 snippet 也不給一份會過期的**
  （R-10 關掉的那扇側門：P2 是最會真的照著貼的那個 persona，而失效是靜默的）。
- **從 DMG 直接雙擊的新使用者**：R-5 讓他在按下去之前就看到解釋與出路；
  **R-9 讓他即使已經接上過，也不會因為打開一次 DMG 副本就把還在運作的 hook 弄丟**。
- **不懂「信任」提示的 vibe coding 使用者**：F5 讓我們偵測不到，畫面與 help 必須把
  「下次啟動 Codex 會問你一次」講在**按下去之前與之後各一次**。

## 10. Known gaps

| # | 內容 | 性質 |
|---|---|---|
| 1 | `PermissionRequest`／`Interrupt`／`Subagent*` 的 Codex payload 形狀**未量**（F10）——`waiting` 目前是**推論** | 待驗；互動探針 |
| 2 | **Codex 沒有 `error` 來源**（F2、F4）→ 永遠不會亮紅燈 | 設計代價 |
| 3 | **無法偵測 Codex 是否已信任**（F5）→ UI 只能講 | 平台限制 |
| 4 | 不寫 `async`（F14 未測）→ 每個事件同步等 ~7 ms | 保守選擇 |
| 5 | ~~hooks.json 頂層形狀未知~~ **已由 F14 關閉** | **已關閉** |
| 6 | 內容比對與 `unlink` 之間的 TOCTOU 窄窗 | 接受 |
| 7 | `codex exec` 會寫 `config.toml`（F12）→ 端到端只能靠人 | 驗收缺口 |
| 8 | F15 的範圍限定：(a) 五個 session 全在 `exec`，互動 TUI 行程結構未量；(b) `SessionEnd` 之後 pid 是否結束**未觀測**；(c) `comm` 未辨識 | 範圍限定 ＋ 待驗；實機 ③ |
| 9 | **`timeout: 3` 是否真的不觸發 clamping 未觀測**；代價是失去最便宜的「Codex 讀到了」訊號 | 推論；實機 ②③ |
| 10 | `command` 是裸路徑；**含空白／引號的路徑行為未測**（R-5 讓產品不賭它） | 待驗；互動探針 |
| 11 | 兩個 agent 共用 `~/.agentaura/sessions/`；同專案同時跑時兩列只靠標籤區分 | persona |
| 12 | **App 被搬走或改名**：R-6 偵測得到，但偵測發生在**下一次 `reprobeCodex()`**（啟動或開面板）；在那之前 Codex 那側已經不動而我們還沒機會講 | 設計代價 |
| 13 | **R-8 的不變式 2（兩側同時真的在跑）自動化只驗到「同一顆二進位、兩邊 `agent` 各自正確」**（CX38）；「兩個上游**同時**真的觸發它」只有實機 ⑧ | 驗收缺口 |
| 14 | **序列長度上限**：CX37a **全部 ≤ 4**（780 條全跑）、CX37b **生產路徑 ≤ 2**（30 條）、CX42 **憑證 ≤ 2**（20 條）。更長的交錯序列未涵蓋——那是成本與覆蓋的取捨，不是「N 步之後就安全了」的論證 | 覆蓋缺口，明寫 |
| 15 | **`Jargon.model` 的 Codex 分支只有 `gpt-5.5` 是實測**；其餘八列（含 `gpt-5` 的**刻意變更**）是預期值，任何一個實際出現時要回頭對照（既有 `everyFixtureModelIsMapped` 會在新 fixture 進來時把沒處理到的值變紅） | 待驗；有守衛 |
| 16 | **兩個上游的 session id 空間不交集是明寫的假設，不是我們控制的東西**（Claude 的 UUID vs Codex 的 UUIDv7）。`SnapshotIO` 以 `<session_id>.json` 分檔，所以「互不覆蓋」在結構上必然成立——CX38 的那個斷言在任何實作下都會通過，**它是結構性結論不是被測性質**（r4 m1） | 假設，明寫 |
| **17** | **`.unsupportedCharacter` 不再給 snippet（D-w）＝ 含不支援字元路徑的使用者「完全沒有手動出路」**，只剩「把 App 搬走」一條。**這是一個有解鎖條件的 gap**：互動探針（R-7 工具包，argv `--agent codex-quoted`）量到「`command` 加引號＋路徑含空白」可行之後，開後續 change 把 `CodexHooksJSON` 的 `command` 加引號並**恢復** `.unsupportedCharacter` 的 snippet。在那之前，給一份我們自己剛說可能會壞的設定檔，比不給更糟（失效是靜默的，F5／`INSTALL.md` 的「completely silently」） | **有解鎖條件的設計取捨**；解鎖＝互動探針 |
| **18** | **面板內沒有從 legend 的「Error」通往「Codex 沒有 error 燈」的路徑**（persona r1 S2-4）：那顆紅點對純 Codex session 永遠不會亮，而 legend 右邊的 ⓘ 是 tooltip 不是按鈕（`LegendRowView.swift:53-54`）。兩份 help 與 `INSTALL.md` 都已明講（T12 已補交叉引用）。**不修的理由**：legend 是兩側共用元件，改動面大於本 change | 文件有、面板沒有；**明寫接受** |
| **19** | **列上的「Codex」標籤與相鄰的權限文字字級／顏色完全相同**（persona r1 S2-2），Claude 那列靠「沒有標籤」辨識。**不修的理由**：改樣式會動到 `CodexRowLabelRenderTests` 從真實 view 推導的 43／59pt 列高守衛，而 P4 已 PASS | **明寫接受**；六列以上跨兩個 agent 時值得重評 |
| **20** | **`optionsExpanded == true` ＋ snippet 卡片同時存在時的總高度不在 CX56 的天花板之內**（§4.10）。Options 展開在 Claude-only 的既有面板就已經 599pt（2026-09-15 實測），是本 change 之前就存在的條件。T13i 要量出這個組合的實際數字記在這裡 | 覆蓋缺口，明寫（數字待 T13i 填） |
| **21** | **Claude 側 CTA 按鈕仍是泛稱「Connect」**，與具名的「Connect Codex」並排時，泛稱那顆看起來像主要動作（persona r1 P1，自評「小摩擦」）。**不修的理由**：那是 Claude-only 表面的文案變更，會動到 `L10nPanel.connectCTAConnect` 與兩份 help 的既有字面 | **明寫接受** |
| **22** | **`statusLabel` 變長之後三個顯示點各自的後果**（r14 擴大：r13 只寫了 footer chip）：① **footer chip**（11pt、`lineLimit(1)`、`truncationMode(.tail)`）可能截掉版本號——子句順序刻意讓 Codex 在前，**被犧牲的是尾巴的版本號，不是剛被判為 S0 的那句話**（§3.1 第 2 點）；② **標題**（`PanelView.swift:20`，13pt semibold、**沒有 `lineLimit`**）在 380pt 寬的面板裡**很可能換行**，而換行**直接增加面板高度**、回饋進 §4.10 的天花板；③ **CTA 窄條 label** 同樣沒有寬度保護。T13f 要把**三處**的渲染寬度與可用寬度都量出來寫進報告；**標題若換行，把高度增量交給 T13i 的基準表**。若量到連 agent 名都被截掉，才改用更短的子句 | 設計取捨，附量測。**數字已填（T13f，2026-09-22，phase-2 review r1 M2 追加：原始 T13f 報告只量了 plan 指名的單一代表值，這裡補上全域數字）**：①②③ 逐字例（單一代表值）見 T13f 原始 commit（footer 313pt／可用 277pt、標題 326pt／可用 352pt 不換行、CTA 273pt）皆真，**但只是 58 格定義域裡的一格**。**全域實測**（`codex == .connected` × 每個非 connected `InstallState`(29) × 兩語言 = 58 格，13pt semibold vs 可用 352pt＝380−14×2）：**34/58 超寬**，最寬 **510pt**（英文，`"Codex connected · Claude Code: Can't connect: couldn't confirm the hook works"`，對應 `.broken(.hookUnconfirmed, owner: .thisApp)`）；`codex == .unavailable` 基準（55 逐位元組不變情境）**0/58 超寬**、最寬 300pt。換行對面板高度的實測影響（該最壞 install，`NSHostingView(rootView: PanelView(...))` 的 `fittingSize.height`）：**250.0pt → 266.0pt（+16.0pt）**。**未改設計**（未加 `lineLimit`／未縮短子句）——是否要接受換行或改短句是 spec 層決策，**已回饋 T13i**：鏈 B 的 §4.10／CX56 高度基準表是在沒有 T13f 的樹上量的，merge 後這 +16pt 換行代價要算進最壞組合重新對一次天花板 | 設計取捨，附量測（**三處單一代表值已填，T13f 原始交付**；**全域 34/58 超寬與 +16pt 換行已填，phase-2 review r1 M2 追加**；merge 後併入 T13i 天花板重量） |

## 11. 風險

| 風險 | 緩解 |
|---|---|
| **`Interrupt` 進 `handledEvents` → Claude 側整份 hooks 靜默失效** | CX2 ＋ CX5 兩個獨立觀測點；`plugin/hooks/hooks.json` 的 git diff 必須為空 |
| **`Interrupt → idle` 沒有 fixture 證人** | CX4（定義域從 `codexOnlyEvents` 推導）；CX13 的 mutation 換成 `Stop` |
| 「只在不存在時寫」寫成兩步 → symlink 指向 `config.toml` 時覆蓋使用者設定 | `O_EXCL` ＋ CX15 那一格 fixture |
| 產生器偏離 F14 → Codex 根本不載入，而自動化抓不到 | CX6 的 12 格逐字比對；唯一刻意偏離自己配一格 mutation |
| **寫進一個下次開機就消失的絕對路徑，而 UI 永遠說「已接上」** | R-5 三層 guard ＋ CX32／CX33 |
| **「重新接上」先刪掉使用者還在運作的檔** | R-9 的前置 guard ＋ 面板不給按鈕 ＋ CX39；CX35 加「無 rejection 時」前提 |
| **把一份會過期的 snippet 交給最會照著貼的 persona** | R-10 ＋ CX40 的乘積表（`CodexState` 與 `Rejection` 是兩個獨立維度，只驗一維會漏掉交會格） |
| **App 搬家後 `.connected` 永遠成立** | R-6 ＋ CX34／CX35 |
| **憑證 round-trip 壞掉 → 永遠刪不掉自己的檔 → 完整移除留殘留** | CX31 ＋ CX24③ |
| **`reprobeCodex()` 沒被呼叫 → 裝了 Codex 卻要重開 app 才看得到** | §4.6 四個時機 ＋ CX24⑤ |
| **兩側互相干擾**（新需求 R-8） | CX37a／CX37b（檔案序列）＋ **CX42（憑證序列）** ＋ CX38（端到端）＋ 實機 ⑧；結構理由寫進 §4.8 |
| **既有 `everyFixtureModelIsMapped` 目前是紅的** | D-u／§4.9；CX41 的釘死表 ＋ 既有 gate 當跨層錨點。DoD 起點寫明「這一條紅是本 change 必須修好的既有 gate，不是弱化對象」 |
| **94 個呼叫點的機械改動**中夾帶弱化 | §6.4(2)(3)(4)(5)；`#expect` 淨數量不得下降 |
| `CodexState` 六態 ＋ 兩種 Rejection，四條聯集 gate 的定義域 | 全部從 `CodexStateKind.allCases` ＋ `RejectionKind.allCases` 推導（D-r 兩層都不得有 `default`） |
| **CX37 的 780 條序列會跑 586 次真 spawn**（r4 M2 算出來的數字） | 拆成 CX37a（零 spawn、780 條全跑）＋ CX37b（生產路徑、30 條、11 次 spawn）；覆蓋不減、spawn 降約 53 倍，**不必縮減序列** |
| Codex 端到端無法自動驗收（F12） | 實機清單 ①–⑧ |
| **r13：修 Claude-only 表面時弄壞 Claude-only 的行為**（沒裝 Codex 的人看到字串變了） | 三條「Codex 不在時逐位元組不變」的斷言：CX50①、CX53、以及 `.unavailable` 既有的零像素守衛。**不是「看起來一樣」，是 `==`** |
| **r13：`.codexConnected` 這個新 kind 被當成 `.connected` 的同義詞** | CX47 的定義域走 `Kind.allCases`（新 kind 自動進表）；CX48 的 mutation① 就是「改回 `.connected`」 |
| **r13：`statusLabel` 又長出第四個顯示點而沒人記得改** | CX52 **兩格**：App 層命中數恰 0 ＋ **AuraCore 層含 `.healthLabel(` 的檔案集合恰等於具名清單**。**r14 更正 r13 的 overclaim**：r13 只掃 App 層，而三處裡的標題住在 AuraCore，站點集合當時只有 2/3 是 source-derived。標題那一處的行為由 CX50④ 守 |
| **r13：780pt 天花板變成「換了題目」的 gate**（面板長高後有人去砍別處的留白） | doc comment 逐字寫「紅掉時的第一個問題是面板是不是又長高了」；T13i 先量修前基準；Options 展開的組合**刻意排除**並記進 §10-20 |
| **r13：確認框的假身直接呼叫 `onConfirm`，讓 CX57 第一格恆真** | §6.4(13)：注入的預設假身**不得**是「直接呼叫 onConfirm」；CX57 兩格（不確認→0／確認→1）一起看 |

**待確認（不自行決定，列給主 session）**：見最終報告的「裁決有問題之處」四點。
