# Codex 面板離屏渲染證據圖（persona 用）

由 `Tests/AgentAuraAppTests/CodexEvidenceRenderer.swift` 產出（觸發方式：`AURA_RENDER_EVIDENCE=1 swift test --filter renderCodexEvidence`，同既有 `Phase2EvidenceRenderer`／`VisualLandedEvidenceRenderer` 的 env gate 慣例）。每張都是**完整面板**（`PanelView`），不是只有 `CodexSectionView`——讓 Claude 側說明與 Codex 列疊在同一畫面的真實比例可見（P1）。

**尺寸單位**：這批圖是 @2x（Retina）點陣圖，寬 760px（面板邏輯寬度 380pt × 2，高度依內容而定）。生產型別（`PanelModel`／`preferredContentSize` 等）內的高度數字單位是 pt，不是這批圖的 px——兩者混用會誤判（CLAUDE.md「這個 codebase 的 gate 哲學」第 7 條）。

**文字顏色不可信，版面與文案可信**：離屏渲染沒有真 `NSWindow`／key window，`.borderless` 按鈕與部分label 落在次要前景色，不代表真 app 裡的實際顏色（CLAUDE.md 第 5 條）；只用這批圖核對「有沒有畫出正確的字」「按鈕在不在」「版面有沒有被擠壓／裁切」，不要拿顏色深淺當證據。

**只有 `.aqua`（淺色）**：深淺色對比不是這批圖要驗的維度，版面與文案在深淺模式下走同一份 SwiftUI語意色（`.primary`／`.secondary`），需要深色對照時另外要求即可。

## persona r1 指出的視覺問題對照（只標，不修）

- **S0-1** ↔ `03-connected-banner-*`：接上成功 banner 的兩句話要看得到，這張圖的 `sessions` 刻意留空（`.connected` kind banner 在有活著的 session 時會自動退場，見 #03 的情境註解）——不是遺漏 session，是唯一能讓兩句話同時留在畫面上的組合。
- **S1-4** ↔ `05-occupied-with-snippet-*` ／ `07-blocked-unsupported-character-*`：面板高度約 944pt，「複製」按鈕落在約 848pt 處（皆為 pt，非這批圖的 px——見上方尺寸單位附註）——snippet 區塊把卡片撐得很高，複製鈕在很下面才看得到。這裡先標記現況，不在這輪修版面。
- **S1-6** ↔ `07-blocked-unsupported-character-*`：已修——snippet 現在由真的含空白的路徑（`/Users/someone/My Apps/AgentAura.app/Contents/PlugIns/aura-hook`）產生，圖上看得到那條會壞的路徑就在snippet 裡。**r13 前的修前基準**：spec r13 之後這個情境會改成「不給 snippet」，T13 落地後要重渲這張。
- **S1-7** ↔ `12-notConnected-claude-with-live-codex-session-*`：新增。本 change 的頭號情境（Claude 未接上 ＋ 一列活著的 Codex session）先前完全沒有證據圖——這張如實呈現標題／footer chip／CTA窄條三處目前都只讀 `model.install`（不看 `model.codex`），完全沒提到正在跑的 Codex session。

| 檔名 | 情境（給 persona 看什麼） |
|---|---|
| `01-unavailable-en.png` | P1／D-j：~/.codex 不存在——完整面板（含活著的 Claude session）完全看不到任何 Codex 字樣 |
| `01-unavailable-zh.png` | P1／D-j：~/.codex 不存在——完整面板（含活著的 Claude session）完全看不到任何 Codex 字樣 |
| `02-notConnected-options-expanded-en.png` | P1：Claude 大版說明＋Codex 卡片單行提示＋Options「接上 Codex」列同時出現，30 秒內看得出兩顆按鈕分屬哪個 agent |
| `02-notConnected-options-expanded-zh.png` | P1：Claude 大版說明＋Codex 卡片單行提示＋Options「接上 Codex」列同時出現，30 秒內看得出兩顆按鈕分屬哪個 agent |
| `03-connected-banner-en.png` | P3：接上成功 banner——「下一個 Codex session 起生效」與「Codex 會問一次是否信任」兩句都在（rows 刻意留空——A7：.connected banner 有 session 時會自動退場，見 INDEX 附註） |
| `03-connected-banner-zh.png` | P3：接上成功 banner——「下一個 Codex session 起生效」與「Codex 會問一次是否信任」兩句都在（rows 刻意留空——A7：.connected banner 有 session 時會自動退場，見 INDEX 附註） |
| `04-connected-stale-path-en.png` | connectedStalePath，pathRejection==nil——「App 移動過」提示＋「重新接上 Codex」按鈕 |
| `04-connected-stale-path-zh.png` | connectedStalePath，pathRejection==nil——「App 移動過」提示＋「重新接上 Codex」按鈕 |
| `05-occupied-with-snippet-en.png` | P2：occupiedByOther，codexSnippet!=nil——說明＋可複製 snippet（與 CodexHooksJSON.snippet 同源）＋「複製」按鈕 |
| `05-occupied-with-snippet-zh.png` | P2：occupiedByOther，codexSnippet!=nil——說明＋可複製 snippet（與 CodexHooksJSON.snippet 同源）＋「複製」按鈕 |
| `06-occupied-must-move-no-snippet-en.png` | P2／R-10：occupiedByOther，pathRejection==.mustMoveToApplications——不給 snippet／複製鈕，改說先把 App 移到「應用程式」 |
| `06-occupied-must-move-no-snippet-zh.png` | P2／R-10：occupiedByOther，pathRejection==.mustMoveToApplications——不給 snippet／複製鈕，改說先把 App 移到「應用程式」 |
| `07-blocked-unsupported-character-en.png` | P2：blockedByBundlePath(.unsupportedCharacter(" "))——文案指名是空白字元＋snippet（同源，來源路徑真的含空白：/Users/someone/My Apps/…）＋「複製」按鈕。**r13 前的狀態**（r13 之後這格改成不給 snippet，T13 落地後要重渲） |
| `07-blocked-unsupported-character-zh.png` | P2：blockedByBundlePath(.unsupportedCharacter(" "))——文案指名是空白字元＋snippet（同源，來源路徑真的含空白：/Users/someone/My Apps/…）＋「複製」按鈕。**r13 前的狀態**（r13 之後這格改成不給 snippet，T13 落地後要重渲） |
| `08-disconnected-banner-en.png` | 斷開成功 banner（codexDisconnected，kind=.disconnected，不會像 #3 那樣因為有 session 而自動退場）＋斷開後 Codex 卡片回到 notConnected 的「接上 Codex」提示 |
| `08-disconnected-banner-zh.png` | 斷開成功 banner（codexDisconnected，kind=.disconnected，不會像 #3 那樣因為有 session 而自動退場）＋斷開後 Codex 卡片回到 notConnected 的「接上 Codex」提示 |
| `09-mixed-claude-codex-rows-en.png` | P4：同一份 sessions 列表裡 Claude 列與帶「Codex」標籤的列並存，分得出來、列高不變（見 CodexRowLabelRenderTests 的既有像素／高度守衛） |
| `09-mixed-claude-codex-rows-zh.png` | P4：同一份 sessions 列表裡 Claude 列與帶「Codex」標籤的列並存，分得出來、列高不變（見 CodexRowLabelRenderTests 的既有像素／高度守衛） |
| `10-stale-rejection-must-move-withholds-reconnect-en.png` | R-9：connectedStalePath，pathRejection==.mustMoveToApplications——不畫「重新接上」按鈕，換句解釋（與 #6 不同 state：這張是 connectedStalePath，#6 是 occupiedByOther） |
| `10-stale-rejection-must-move-withholds-reconnect-zh.png` | R-9：connectedStalePath，pathRejection==.mustMoveToApplications——不畫「重新接上」按鈕，換句解釋（與 #6 不同 state：這張是 connectedStalePath，#6 是 occupiedByOther） |
| `11-stale-rejection-unsupported-character-withholds-reconnect-en.png` | R-9：connectedStalePath，pathRejection==.unsupportedCharacter(" ")——同樣不畫「重新接上」按鈕，與 #10 同一句解釋（文案不預設成因）；與 #7 不同 state：這張是 connectedStalePath，#7 是 blockedByBundlePath |
| `11-stale-rejection-unsupported-character-withholds-reconnect-zh.png` | R-9：connectedStalePath，pathRejection==.unsupportedCharacter(" ")——同樣不畫「重新接上」按鈕，與 #10 同一句解釋（文案不預設成因）；與 #7 不同 state：這張是 connectedStalePath，#7 是 blockedByBundlePath |
| `12-notConnected-claude-with-live-codex-session-en.png` | S1-7：install=.notConnected（Claude 未接上）＋一列活著的 Codex session（working）＋Codex 卡片 .connected——看標題／footer chip／CTA 窄條三處在這個組合下寫什麼字（persona r1：三處都只反映 Claude，完全沒提到正在跑的 Codex session） |
| `12-notConnected-claude-with-live-codex-session-zh.png` | S1-7：install=.notConnected（Claude 未接上）＋一列活著的 Codex session（working）＋Codex 卡片 .connected——看標題／footer chip／CTA 窄條三處在這個組合下寫什麼字（persona r1：三處都只反映 Claude，完全沒提到正在跑的 Codex session） |
