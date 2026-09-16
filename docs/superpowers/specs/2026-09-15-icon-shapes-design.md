# 選單列 icon 造型可選（change `icon-shapes`）

2026-09-15。使用者要求：內建幾組 icon 可選（原本還要一個彩虹貓 meme，見 D-4／D-5：已移除）。
參考 Amphetamine 的 Menu Bar Image 選單。

## 1. 讓這件事變簡單的架構事實

`LEDStripView.draw` 裡那八顆燈**全部用同一個顏色**（`iconAppearance.color`，聚合狀態色）。
八顆是造型，不是資訊——沒有「一顆代表一個 session」這回事。

**所以狀態訊號完全由「顏色 ＋ 呼吸動畫」承載，形狀是自由的。** 換任何圖形都不損失功能。

現有的狀態→動作對照（`AppearancePolicy.motion`，R4 注意力預算，**不改**）：

| 狀態 | 動畫 | FPS |
|---|---|---|
| idle／done | 靜止 | 0 |
| working | 呼吸 4.0s，0.35–0.60 | 10 |
| waiting | 呼吸 1.1s，0.20–1.00 | 30 |
| error | 雙閃 1.1s | 30 |

## 2. 決策

**D-1 內建造型用 SF Symbols，不自己畫。**
系統符號自動處理深淺模式、Retina、光學對齊；`isTemplate` 上色與 alpha 天生支援。
自己畫每一個都要寫繪製碼＋像素測試，換不到對等價值。
唯一的例外是既有的 `ledStrip`，它不是符號而是自繪燈條（見 D-4／D-5 的後記）。

**D-2 造型是純顯示選擇，不得影響狀態語意。**
`IconAppearance`（顏色／動畫／FPS）完全不動，`AppearancePolicy` 一行都不改。
造型只決定「畫什麼形狀」，不決定「什麼時候動、動多快」。
這條讓造型的測試與狀態的測試互不干擾，也保證加造型不會回頭弄壞 R4。

**D-3 造型存偏好、預設維持現有 LED 燈條。**
比照 `iconPlatePreference`／`LanguagePreference` 的既有搬運層形狀。
**預設不變**是為了不驚動既有使用者。

**D-4／D-5（彩虹貓）：2026-09-15 整個移除。**

原本規劃一個像素繪製的彩虹貓造型，並為它設計了「彩虹保留自己的顏色、狀態靠尾巴讓位」
的對照表（D-4）與「程式繪製像素格、不包圖檔」的畫法（D-5）。實作了四輪（Nyan Cat 還原 →
原創藍灰虎斑 → 放大 → 俄羅斯藍貓坐紙箱），使用者最終判定**造型做不好看**，
指示把選項從系統移除。

留下來的東西只有兩樣，都在本檔以外：
- `IconShape` 的 `rawValue` 是落盤格式，`"nyanCat"`／`"rainbowCat"` 兩個舊字面的降級規則
  住在 `AppDelegate.iconShapePreference` 的 `legacyAliases`。
- 「畫得出來 ≠ 好看」這個判斷只有真的畫出來給人看才做得到——四輪都是先出圖再決定。

**不要照 D-4／D-5 重做。** 要再加非 SF Symbol 的造型是新的設計決策，不是把這段接回去。

## 3. 造型清單（第一版）

| 值 | 來源 | 備註 |
|---|---|---|
| `ledStrip` | 現有 `LEDStripView` | **預設**，不動 |
| `dot` | `circle.fill` | 最小干擾 |
| `ring` | `circle` | 空心，呼吸時很明顯 |
| `capsule` | `capsule.fill` | 對應 Amphetamine 的 Pill |
| `sparkle` | `sparkle` | |
| `halfCircle` | `circle.lefthalf.filled` | |

不做第三方圖片匯入（Amphetamine 的 Custom image）——那是檔案讀取、縮放、單色化、
儲存位置另一個層級的工作，本輪 YAGNI。

## 4. Known gaps

1. 不支援自訂圖片匯入。
2. 造型與「燈條底板」開關的互動：底板是為 LED 燈條設計的幾何，
   SF Symbol 造型下是否仍該提供底板，**一律沿用同一個開關**。
   幾何本身收在 `IconPlate.rect(in:)`／`draw(in:)`，兩個 conformer 共用——
   初版各寫一份，在選單列的真實高度（22pt）下當場漂開（SF Symbol 的底板頂天立地、
   LED 的上下各留 2pt），由 `IconPlateGeometryTests` 在生產高度下逐造型守住。

## 5. 任務切分

| # | 範圍 |
|---|---|
| T32 | `IconShape` 模型 ＋ 偏好 ＋ Options 選單 ＋ SF Symbol 繪製 ＋ gates |
| T33／T36 | 彩虹貓（已移除，見 D-4／D-5 的後記） |
| T34／T35 | 選單每一項顯示縮圖、統一畫布寬度、選單開著時縮圖動起來 |
