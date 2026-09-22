# Codex 面板離屏渲染證據圖（persona 用）

由 `Tests/AgentAuraAppTests/CodexEvidenceRenderer.swift` 產出（觸發方式：`AURA_RENDER_EVIDENCE=1 swift test --filter renderCodexEvidence`，同既有 `Phase2EvidenceRenderer`／`VisualLandedEvidenceRenderer` 的 env gate 慣例）。每張都是**完整面板**（`PanelView`），不是只有 `CodexSectionView`——讓 Claude 側說明與 Codex 列疊在同一畫面的真實比例可見（P1）。

**尺寸單位**：這批圖是 @2x（Retina）點陣圖，寬 760px（面板邏輯寬度 380pt × 2，高度依內容而定）。生產型別（`PanelModel`／`preferredContentSize` 等）內的高度數字單位是 pt，不是這批圖的 px——兩者混用會誤判（CLAUDE.md「這個 codebase 的 gate 哲學」第 7 條）。

**文字顏色不可信，版面與文案可信**：離屏渲染沒有真 `NSWindow`／key window，`.borderless` 按鈕與部分label 落在次要前景色，不代表真 app 裡的實際顏色（CLAUDE.md 第 5 條）；只用這批圖核對「有沒有畫出正確的字」「按鈕在不在」「版面有沒有被擠壓／裁切」，不要拿顏色深淺當證據。

**只有 `.aqua`（淺色）**：深淺色對比不是這批圖要驗的維度，版面與文案在深淺模式下走同一份 SwiftUI語意色（`.primary`／`.secondary`），需要深色對照時另外要求即可。

## persona r1 指出的視覺問題對照（T13l：全部補上「修後」欄）

- **S0-1（D-v）** ↔ 修前 `03-connected-banner-*`（rows 刻意留空才看得到兩句話）→**修後** `13-codexConnected-banner-persists-with-claude-row-*`（rows 有一列 **Claude**session，banner 仍然出現）＋ `13b-codexConnected-banner-retires-with-codex-row-*`（rows 有一列**Codex** session，banner 已退場，對照組）。退場條件從「rows 非空就退場」改成「出現 Codex 的列（`hasCodexRow`）才退場」。
- **S0-2（D-w）** ↔ 修前 `07-blocked-unsupported-character-*`（給 snippet＋「複製」）→**修後同檔名**（本次重渲）：`.unsupportedCharacter` 現在**不給 snippet**，只給指名字元的解釋＋出路句——即使餵進去的是真的含空白路徑產的 snippet 也沒有畫（`realSnippetWithSpace` 這條輸入常數繼續留著，證明的是「產得出來」與「畫不畫」是兩回事）。
- **S1-1（D-y）** ↔ 修前 `12-notConnected-claude-with-live-codex-session-*`（標題／footer chip／CTA 窄條三處逐字「還沒接上」）→ **修後同檔名**（本次重渲）：三處現在讀 `statusLabel`，寫成「Codex connected · Claude Code: Not connected yet」（Codex 子句在前）。
- **S1-3（D-aa）** ↔ 修前 `05-occupied-with-snippet-*`（只有說明＋snippet＋「複製」，沒有合併指示）→ **修後同檔名**（本次重渲）：多一行合併指示（「把這些 entry 併進你現有的 hooks 物件，不要整份取代」）＋一顆「教我怎麼做」按鈕（送出既有 `.openHelp`）。
- **S1-4（D-ab）** ↔ 修前 `05-occupied-with-snippet-*` ／ `07-blocked-unsupported-character-*`（面板高度約 944pt，「複製」按鈕落在約 848pt 處，皆為 pt，非這批圖的 px）→ **修後**`14-worst-height-combination-en`：snippet 區塊固定高度＋可捲，天花板 ≤780pt，「複製」鈕與 footer都在畫面內（實測數字見檔名列表那一行）。**這張用的是 CX56 同一個 `install` 代表值（`.broken(.targetMissing, owner: .external)`）與同一個天花板，不是另外挑的數字**。
- **S2-1（D-x）** ↔ 修前 `10-*` ／ `11-*`（persona r1 現場驗過兩張位元組完全相同）→**修後同檔名**（本次重渲）：兩張**不再相同**——中性開場句共用，但成因／出路依 rejection 分流（#10 講「移到『應用程式』」，#11 指名字元並講「移到不含該字元的位置」）。
- **S1-6（D-ad）** ↔ `07-blocked-unsupported-character-*`：證據渲染器本身的修正——snippet 輸入改用真的含空白的路徑（`493e0bf` 已修，本次無變動）。
- **S1-7（D-ad）** ↔ `12-notConnected-claude-with-live-codex-session-*`：新增證據圖本身（`493e0bf` 已加，本次重渲內容因 D-y 落地而更新，見上面 S1-1 那條）。

| 檔名 | 情境（給 persona 看什麼） |
|---|---|
| `01-unavailable-en.png` | P1／D-j：~/.codex 不存在——完整面板（含活著的 Claude session）完全看不到任何 Codex 字樣 |
| `01-unavailable-zh.png` | P1／D-j：~/.codex 不存在——完整面板（含活著的 Claude session）完全看不到任何 Codex 字樣 |
| `02-notConnected-options-expanded-en.png` | P1：Claude 大版說明＋Codex 卡片單行提示＋Options「接上 Codex」列同時出現，30 秒內看得出兩顆按鈕分屬哪個 agent |
| `02-notConnected-options-expanded-zh.png` | P1：Claude 大版說明＋Codex 卡片單行提示＋Options「接上 Codex」列同時出現，30 秒內看得出兩顆按鈕分屬哪個 agent |
| `03-connected-banner-en.png` | P3：接上成功 banner——「下一個 Codex session 起生效」與「Codex 會問一次是否信任」兩句都在。這裡的 rows 留空只是這張圖選的最簡形式，**不是必要條件**（persona r2）：D-v 之後 `.codexConnected` banner 只在出現 **Codex** 的列時才退場，有一列 Claude session 一樣看得到兩句話（見 #13）；只有真的出現 Codex 的列才會像 #13b 那樣退場 |
| `03-connected-banner-zh.png` | P3：接上成功 banner——「下一個 Codex session 起生效」與「Codex 會問一次是否信任」兩句都在。這裡的 rows 留空只是這張圖選的最簡形式，**不是必要條件**（persona r2）：D-v 之後 `.codexConnected` banner 只在出現 **Codex** 的列時才退場，有一列 Claude session 一樣看得到兩句話（見 #13）；只有真的出現 Codex 的列才會像 #13b 那樣退場 |
| `04-connected-stale-path-en.png` | connectedStalePath，pathRejection==nil——「App 移動過」提示＋「重新接上 Codex」按鈕 |
| `04-connected-stale-path-zh.png` | connectedStalePath，pathRejection==nil——「App 移動過」提示＋「重新接上 Codex」按鈕 |
| `05-occupied-with-snippet-en.png` | P2：occupiedByOther，codexSnippet!=nil——說明＋**合併指示**（「把這些 entry 併進你現有的 hooks 物件，不要整份取代」，D-aa／T13h）＋可複製 snippet（與 CodexHooksJSON.snippet 同源，固定高度＋可捲）＋「複製」按鈕＋**「教我怎麼做」按鈕**（送出既有 `.openHelp`） |
| `05-occupied-with-snippet-zh.png` | P2：occupiedByOther，codexSnippet!=nil——說明＋**合併指示**（「把這些 entry 併進你現有的 hooks 物件，不要整份取代」，D-aa／T13h）＋可複製 snippet（與 CodexHooksJSON.snippet 同源，固定高度＋可捲）＋「複製」按鈕＋**「教我怎麼做」按鈕**（送出既有 `.openHelp`） |
| `06-occupied-must-move-no-snippet-en.png` | P2／R-10：occupiedByOther，pathRejection==.mustMoveToApplications——不給 snippet／複製鈕，改說先把 App 移到「應用程式」 |
| `06-occupied-must-move-no-snippet-zh.png` | P2／R-10：occupiedByOther，pathRejection==.mustMoveToApplications——不給 snippet／複製鈕，改說先把 App 移到「應用程式」 |
| `07-blocked-unsupported-character-en.png` | P2／S0-2 修後（D-w）：blockedByBundlePath(.unsupportedCharacter(" "))——文案指名是空白字元＋出路句（把 App 移到不含該字元的位置）。**不給 snippet／複製鈕**——即使餵進去的是真的含空白路徑產生的 snippet（`realSnippetWithSpace`）也不畫，修前（`493e0bf`）這格會畫出那條會壞的路徑並給「複製」 |
| `07-blocked-unsupported-character-zh.png` | P2／S0-2 修後（D-w）：blockedByBundlePath(.unsupportedCharacter(" "))——文案指名是空白字元＋出路句（把 App 移到不含該字元的位置）。**不給 snippet／複製鈕**——即使餵進去的是真的含空白路徑產生的 snippet（`realSnippetWithSpace`）也不畫，修前（`493e0bf`）這格會畫出那條會壞的路徑並給「複製」 |
| `08-disconnected-banner-en.png` | 斷開成功 banner（codexDisconnected，kind=.disconnected，不會像 #3 那樣因為有 session 而自動退場）＋斷開後 Codex 卡片回到 notConnected 的「接上 Codex」提示 |
| `08-disconnected-banner-zh.png` | 斷開成功 banner（codexDisconnected，kind=.disconnected，不會像 #3 那樣因為有 session 而自動退場）＋斷開後 Codex 卡片回到 notConnected 的「接上 Codex」提示 |
| `09-mixed-claude-codex-rows-en.png` | P4：同一份 sessions 列表裡 Claude 列與帶「Codex」標籤的列並存，分得出來、列高不變（見 CodexRowLabelRenderTests 的既有像素／高度守衛） |
| `09-mixed-claude-codex-rows-zh.png` | P4：同一份 sessions 列表裡 Claude 列與帶「Codex」標籤的列並存，分得出來、列高不變（見 CodexRowLabelRenderTests 的既有像素／高度守衛） |
| `10-stale-rejection-must-move-withholds-reconnect-en.png` | R-9／S2-1 修後（D-x）：connectedStalePath，pathRejection==.mustMoveToApplications——不畫「重新接上」按鈕；開場句改成中性事實（只講「這份設定指向另一個位置」，不再宣稱「下次開機就會消失」），成因／出路沿用「把 App 移到『應用程式』」（與 #6 不同 state：這張是 connectedStalePath，#6 是 occupiedByOther） |
| `10-stale-rejection-must-move-withholds-reconnect-zh.png` | R-9／S2-1 修後（D-x）：connectedStalePath，pathRejection==.mustMoveToApplications——不畫「重新接上」按鈕；開場句改成中性事實（只講「這份設定指向另一個位置」，不再宣稱「下次開機就會消失」），成因／出路沿用「把 App 移到『應用程式』」（與 #6 不同 state：這張是 connectedStalePath，#6 是 occupiedByOther） |
| `11-stale-rejection-unsupported-character-withholds-reconnect-en.png` | R-9／S2-1 修後（D-x）：connectedStalePath，pathRejection==.unsupportedCharacter(" ")——同樣不畫「重新接上」按鈕，但**不再與 #10 位元組相同**：同一句中性開場之後接的是指名空白字元＋「把 App 移到不含該字元的位置」，不是 #10 的「移到『應用程式』」（修前 `493e0bf` 這兩張是同一張圖，可查證為假的「會消失」子句已拿掉；與 #7 不同 state：這張是 connectedStalePath，#7 是 blockedByBundlePath） |
| `11-stale-rejection-unsupported-character-withholds-reconnect-zh.png` | R-9／S2-1 修後（D-x）：connectedStalePath，pathRejection==.unsupportedCharacter(" ")——同樣不畫「重新接上」按鈕，但**不再與 #10 位元組相同**：同一句中性開場之後接的是指名空白字元＋「把 App 移到不含該字元的位置」，不是 #10 的「移到『應用程式』」（修前 `493e0bf` 這兩張是同一張圖，可查證為假的「會消失」子句已拿掉；與 #7 不同 state：這張是 connectedStalePath，#7 是 blockedByBundlePath） |
| `12-notConnected-claude-with-live-codex-session-en.png` | S1-1 修後（D-y）：install=.notConnected（Claude 未接上）＋一列活著的 Codex session（working）＋Codex 卡片 .connected——標題／footer chip／CTA 窄條三處現在都讀 `statusLabel`，寫成「Codex connected · Claude Code: Not connected yet」（Codex 子句在前，見 §3.1），不再是修前（`493e0bf`）三處逐字「還沒接上」 |
| `12-notConnected-claude-with-live-codex-session-zh.png` | S1-1 修後（D-y）：install=.notConnected（Claude 未接上）＋一列活著的 Codex session（working）＋Codex 卡片 .connected——標題／footer chip／CTA 窄條三處現在都讀 `statusLabel`，寫成「Codex connected · Claude Code: Not connected yet」（Codex 子句在前，見 §3.1），不再是修前（`493e0bf`）三處逐字「還沒接上」 |
| `13-codexConnected-banner-persists-with-claude-row-en.png` | S0-1 修後（D-v）：.codexConnected banner ＋ rows 含一列 Claude session——banner 仍然出現（兩句話都在）。這是 #03（修前要 rows 留空才看得到兩句話）的直接對照：同一顆 banner 現在能與一列 Claude session 共存，因為退場條件改成看 hasCodexRow，不是看 rows.isEmpty |
| `13-codexConnected-banner-persists-with-claude-row-zh.png` | S0-1 修後（D-v）：.codexConnected banner ＋ rows 含一列 Claude session——banner 仍然出現（兩句話都在）。這是 #03（修前要 rows 留空才看得到兩句話）的直接對照：同一顆 banner 現在能與一列 Claude session 共存，因為退場條件改成看 hasCodexRow，不是看 rows.isEmpty |
| `13b-codexConnected-banner-retires-with-codex-row-en.png` | 對照（D-v）：.codexConnected banner ＋ rows 含一列 Codex session——banner 已退場（hasCodexRow==true，承諾已兌現）。與 #13 一起看：#13 有 Claude 列仍顯示 banner，這張有 Codex 列就不顯示，證明退場條件是「有沒有 Codex 的列」不是「rows 是否非空」 |
| `13b-codexConnected-banner-retires-with-codex-row-zh.png` | 對照（D-v）：.codexConnected banner ＋ rows 含一列 Codex session——banner 已退場（hasCodexRow==true，承諾已兌現）。與 #13 一起看：#13 有 Claude 列仍顯示 banner，這張有 Codex 列就不顯示，證明退場條件是「有沒有 Codex 的列」不是「rows 是否非空」 |
| `14-worst-height-combination-en.png` | S1-4／CX56 最壞高度組合（D-ab）：install=.broken(.targetMissing, owner:.external)（CX56 的 `.replaceExternal` 代表值）＋ .occupiedByOther 有 snippet ＋ banner=.codexConnected ＋ rows 空 ＋ 英文——固定高度＋可捲的 snippet 區塊落地後，天花板應 ≤780pt（@2x 1560px），「複製」鈕與 footer 都在畫面內。**只有這張圖是英文單張**（CX56 量到的最壞語言，中文版無新增資訊）。**注意（persona r2）**：畫面上半「Connected to Codex」banner 配下半「你已經有自己的 hooks.json」卡片是**生產不可達的組合**——`hooks.json` 用 `O_CREAT\|O_EXCL` 寫，我們自己寫成功（banner 因此出現）就代表寫之前檔案不存在，之後不會突然變成「別人的檔」（`.occupiedByOther`），除非在極窄的 TOCTOU 窗口內被別的行程搶先寫入（spec known gap #20，未關閉）。渲染器刻意疊上這個不可達組合只是為了湊出**結構上的最壞高度**；不可達但量到的高度更高，只讓 780pt 天花板的界更保守，對這張圖驗證的「複製鈕與 footer 是否在畫面內」這個主張無害——不要把這格誤判成生產路徑會出現的畫面 |
