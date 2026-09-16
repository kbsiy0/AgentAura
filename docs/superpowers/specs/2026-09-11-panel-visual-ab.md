# 面板視覺 A/B（三個方向，真渲圖決定）

> **公開版註記（2026-09-16）**：`V1`／`V2`／`V3` 三個**原型**渲圖在 repo 轉為公開時移除——
> 它們是在去識別化之前渲的，圖裡燒著真實專案名稱，而產生它們的變體程式碼在決策完成後
> 就已經不在 codebase 裡，無法重渲。**決策結論與逐項評分不受影響**（都在本文），
> 且 `V1-landed-*.png`（落地後的實際樣子）仍在且已重新渲過。


> 2026-09-11 · 使用者：「目前的畫面還是很醜」、「口述容易造成偏差」
> 方法沿用 **M4 選 icon 形態**那一套：同時做多個原型、用**真渲圖**決定、**評後刪**。
> 生產碼在挑出贏家之前**一行不動**；原型活在測試目標的 renderer 裡。

## 0. 為什麼是「沒有目標」而不是「品味不好」

phase 2 修得動的每一條都是因為**真的去看了渲出來的圖**（CTA 的灰字、三行同句、開關看不到狀態）。
所以缺的不是渲圖迴圈，是**沒有人定過視覺目標**——一直在「批評 → 補丁」，不是「設計 → 實作」。
這份文件的唯一目的：**把三個互相衝突的方向做成可以看的東西**，讓人挑一個。

## 1. 現況的六個具體問題（不是口味）

| # | 問題 | 現況 | 影響 |
|---|---|---|---|
| 1 | **沒有材質** | 不透明白／深灰底 | 真正的選單列 popover 是 `NSVisualEffectView` 半透明；這是「看起來廉價」最大的單一原因 |
| 2 | 沒有字型層級 | 幾乎全部 11–12pt，只有標題 12 semibold | 眼睛沒有落點，所有資訊等重 |
| 3 | 沒有間距節奏 | 到處 12pt padding、列高一致 | 分組只靠分隔線，靠線不靠留白 |
| 4 | 圖例列很重 | 四色點＋標籤＋提示行＋自己的分隔線 | 夾在內容與 footer 之間，佔 3 行 |
| 5 | 空狀態是空洞 | 一句話置中 | 最常見的狀態最沒有設計 |
| 6 | 等寬字太多 | headline／meta 都 monospace | 「工程師感」的來源之一（D-c 只保了 tool 名） |

## 2. 三個方向（刻意互相衝突，不是三種深淺）

共同不變：寬 380pt · 八顆 LED 形態（A2 已定案）· 四燈語意與顏色 · 誠實性機制
（tooltip／banner／chip 文案全部沿用現狀，**這輪只動視覺**）。

### V1「macOS 原生感」——像 System Settings
| token | 值 |
|---|---|
| 底 | 半透明材質（渲圖用 88% 白／82% #1e1e1e 疊在代表性底色上，見 §4 的誠實限制） |
| 分組 | 圓角 10pt 的 inset 卡片、1pt hairline 邊、卡片間距 8pt |
| 字型 | 標題 13 semibold · 列標題 13 regular · 次要 11 · meta 11 |
| 列高 | 28pt，左側 20pt 圖示欄（SF Symbols：`questionmark.circle`／`power`／`arrow.triangle.2.circlepath`／`trash`／`info.circle`／`exclamationmark.bubble`／`xmark.circle`） |
| 圖例 | 單條 24pt：四個 8pt 點＋11pt 標籤，**提示行拿掉**（改 `ⓘ` 的 tooltip） |
| session 列 | 專案名 13 semibold · headline 12 **非等寬** · meta 11 次要 |
| footer | 24pt，chip＋版本在左，Options 是小按鈕在右 |

### V2「資訊密度」——像 OpenUsage
| token | 值 |
|---|---|
| 底 | 同 V1 材質 |
| 分組 | 不用卡片；列高 24pt，隔列淡填 `#00000006`（深色 `#ffffff08`） |
| 字型 | 標題 12 bold＋0.5 字距 · 專案 13 semibold · headline 12 · meta 10 **等寬只留給數字與時間** |
| 強調 | 每個 session 列左緣一條 3pt 狀態色條 |
| 圖例 | 四個膠囊：8pt 點＋11pt 標籤包在 16pt 圓角、底色是該狀態色的 12% |
| footer | 22pt，版本 10pt 等寬 |

### V3「極簡安靜」——R4 注意力預算的極致
| token | 值 |
|---|---|
| 底 | 同 V1 材質 |
| 分組 | **零分隔線**；段落之間 16pt 留白 |
| 字型 | 專案 14 medium · headline 12 regular 次要 · meta 10 三級 |
| 列高 | 32pt，水平 padding 16pt |
| 圖例 | 只剩四個 8pt 裸色點、間距 6pt，**標籤只在 tooltip**，提示行拿掉 |
| 色彩 | 除狀態色之外全單色 |
| footer | 只有 chip＋Options；**版本移進「關於」** |

## 3. 要渲的組合（12 張）

三個版本 × 兩種內容狀態 × 深淺：
- **狀態 A**「三個 session」：一個 waiting（等你批准）、一個 working（含 subagent 與本輪時長）、一個**已結束的 done**（測尾巴那列的視覺）
- **狀態 B**「沒接上」落地頁：`broken(.hookBlockedOrBroken)`，含處方文字與填色 CTA

檔名：`docs/evidence/design-ab/V{1,2,3}-{sessions,notConnected}-{light,dark}.png` ＋ `index.html`
（三欄並排、同狀態同列，方便左右比對）。

## 4. 誠實的限制（必須寫在 index.html 上）

- **真 vibrancy 渲不出來**：`NSVisualEffectView` 需要真視窗與後方內容才會有材質效果，
  離屏渲染只會得到一塊平色。所以三個版本的「材質」在圖上是**用半透明疊在代表性底色上模擬**的，
  真機上會不同（這正是最後要在真 app 上看一眼的理由）。
- 所有離屏渲染的**文字顏色**不可當真：沒有 key window 時 `.borderless` 的 label 一律拿系統次要
  前景色（persona r2 實測更正）。挑版本時**看版面、間距、層級、密度**，不要看字色。
- SF Symbols 在離屏渲染下會畫出來（不是 `NSButton` 那種橋接問題），可以看。

## 5. 落地規則（沿用 M4 §4.3「評後刪」）

挑出贏家之後：贏家的 token 寫進生產 view，**另外兩個原型與 renderer 一併刪除**，
不留開發期的形態切換開關（R9）。現有的 gate 一條都不准放寬——特別是
`PanelPixelTests` 的 wild 色 0 px、`OptionsDividerGroupingPixelTests`、`heightCeiling` 推導式：
換視覺要連帶更新這些 gate 的 oracle，**不是刪掉它們**。

## 6. 決策紀錄（T15，2026-09-11）

**使用者看過真渲圖後選 V1「macOS 原生感」整包**——三個方向裡最保守的那條。
`VisualVariantV2.swift`／`VisualVariantV3.swift`／`VisualABRenderer.swift`／
`VisualABRendererSmokeTests.swift` 已刪除；`VisualVariantV1.swift`／`VisualVariantSupport.swift`
內容已搬進生產碼（`Sources/AgentAuraApp/{PanelView,OptionsSectionView,LegendRowView,
NotConnectedView,PanelFooterView}.swift`），一併刪除，**不留任何形態切換開關**（R9）。

**沒有被採用、但留紀錄免得以後有人以為沒考慮過**：
- V2 的「每個 session 列左緣一條 3pt 狀態色條」——沒有實作。
- V3 的「零分隔線、段落之間 16pt 留白」的內容區留白做法——沒有實作
  （V1 落地版仍用卡片邊框＋列間細分隔線做分組，不是留白）。

**落地前修掉的三個毛病**（team-lead 看 T14 渲圖時發現，V1 原型本身沒有處理）：
1. **Options 圖示欄留空**（開機自動啟動／減少動態兩列先前沒有圖示，看起來像壞掉）——
   `OptionsSectionView.OptionsRowIconView.systemName(for:)` 現在對 `PanelActionKind` 全 case
   窮盡給圖示，Options 選單九列（`OptionsMenuModel.rows(...)` 可能產生的每一種）都有圖示。
2. **session 卡片三列擠成一團**——`PanelView.sessionsCard` 的列之間補了縮進到文字左緣的
   細分隔線（`.padding(.leading, 40)`）。
3. **資料沒有壓過設定**——`OptionsSectionView` 拿掉邊框、只留淡背景填色
   （`Color.primary.opacity(0.04)`）；`PanelView.sessionsCard`／`NotConnectedView` 保留
   1pt hairline 邊框，讓內容區維持視覺上的主角地位。

**材質實驗（誠實限制，見 §4）**：`PanelView.body` 的背景改成 `.background(Color.clear)`，
`StatusItemController.setPanel` 首次建立 `NSHostingController` 時把 `view.layer?.backgroundColor`
設成 `.clear`，讓 `NSPopover` 自己的原生材質有機會透出來。**這件事離屏渲染證明不了**（沒有真
`NSWindow`，SwiftUI `Material`／vibrancy 不會生效）——已在 T15 commit message 標記「需在真 app
上確認」；文字全走 `.primary`／`.secondary`／`.tertiary` 語意色，材質萬一沒生效，退回不透明底
時也還讀得清楚。

**`OptionsPanelSizing` 重新校準**：列高改成 V1 token 的 `.frame(minHeight: 28)` 之後，舊常數
（`perRowCeiling=30`／`chromeCeiling=160`，照 22pt 列高反推）讓 worst-case 直接紅
（實測 473pt > 舊門檻 460pt）。重新量得 `perRowCeiling=30`（實測 28pt＋2pt margin）、
`chromeCeiling=205`（實測固定 chrome 168pt＋subtitle 3pt＋external 行 22pt＋約 12pt margin），
新門檻 505pt 對實測 worst-case 473pt 留 32pt margin。完整分解見
`Sources/AuraCore/OptionsPanelSizing.swift` doc comment。

**證據圖**：`docs/evidence/phase2/*.png` 已用新版生產 `PanelView` 全部重渲（檔名沿用，diff
看得出視覺變化）；`docs/evidence/design-ab/V1-landed-{sessions,notConnected}-{light,dark}.png`
是落地後用生產 `PanelView` 渲的對照組，`index.html` 新增一節「V1 vs 落地」逐張比對原型與
落地結果。
