# DoD 量測 · `change/panel-legend-palette`（T06）

量測時間 2026-09-10 00:3x–00:5x · 機器 Darwin 25.6.0 · app 為 `667ef99` 的 `./scripts/build-app.sh` 產物（universal；CPU/RSS 量於 `254979f`，其後只動 SwiftUI 修飾子與 tooltip 字串）。spec r4 §7 為門檻來源。

| 項目 | 門檻（spec §7） | 實測 | 判定 |
|---|---|---|---|
| 圖例常駐 | 任何 `setPanel` 的 legend 都是 4 項；像素上 rows 空／非空都畫出四點 | `legendAlwaysPresent`（`allSatisfy`）、`legendDotsUsePalette`（空＋非空）綠 | ✅ |
| 改色即時 | `applyColor` 後**同步**收到新色 | `paletteChangeReachesIcon` 綠（不用 wait） | ✅ |
| 入口接線 | 面板 tap 後整條鏈到 `NSColorPanel` 有 gate | `pickerChainIsWired` 四段、`controllerForwardsPanelCallbacks`（含第二條解除路徑）、`attachPopoverPreparesHosting`、`tooltipNeverNegative` 綠 | ✅（SwiftUI tap → `PanelView.onPick` → controller 這**最後兩跳**離屏不可測 → 使用者實測項） |
| 持久化 | 真 suite 跨 store 實例 round trip；reset 清 key；首格用持久色 | `storeRoundTripsThroughRealDefaults`（含寫入端 key/`#rrggbb` 斷言）、`storeResetRemovesKeys`、`persistedColorAppliesOnFirstFrame` 綠 | ✅ |
| 容錯 | 10 種垃圾值全落回預設、不 crash；三個 `changeColor` guard 各有測試 | `hexRejectsGarbage`（10 種含非 ASCII／10 KB）、`storeToleratesGarbageDefaults`、`changeColorGuards`（四案例）綠 | ✅ |
| 面板真的用 palette | wild ≥ 200／120 px；`.default` 渲時 wild 0 px | `legendDotsUsePalette`、`rowDotsUsePalette` 綠 | ✅ |
| 面板重用與尺寸 | 同一 hosting controller；高度隨列數增減 | `hostingControllerIsReused`（+1／變大／變小／不增）綠 | ✅ |
| R9：依賴／target | 零新依賴、零新 target | `Package.swift` 零 diff | ✅ |
| R9：`Sources/` 淨增 | ≤ 520（基準 1806） | 最終 2281 − 1806 = **+475**（review 折入後；T05 時 +449） | ✅ |
| R9：單檔 | ≤ 200 | 最大 `StatusItemController.swift` 150 | ✅ |
| R9：key 預算 | `UserDefaults` 前綴 key ≤ 4 | `storeKeyBudget` 綠 | ✅ |
| R9：無自建視窗 | 只有系統 `NSColorPanel` | code review | ✅ |
| **執行檔增量** | < +150 KB vs 1,155,552 | 最終 build（rebase 後 HEAD）：**1,454,272 → +298,720 bytes（+292 KB）**（persona／review 折入的 accessibility、整組命中區、tooltip guard 再 +39 KB） | ❌ **超標**（見下） |
| AuraCore 覆蓋率 | ≥ 90% | **96.45% regions / 99.09% lines**（HEAD；NaN clamp 加了 1 個刻意不可達 region） | ✅ |
| 測試 | 全綠 | **286 tests / 37 suites**（3 條 env-gated evidence 測試 skip；integrator ×3 全綠） | ✅ |
| CPU／RSS | idle／done ≤ 0.1%；RSS < 60 MB（隔離量測者 session，`top` 60s） | 第一輪（`NSColorPanel.shared` 在 launch 建構）：idle 0.06／done 0.12％、**RSS 28 MB**；修 review-t0203 I2 後第二輪：idle **0.06**／done **0.07**％、**RSS 11 MB**（回到 Change 1 水準）；working 1.34／waiting 3.04／error 2.49％（與 main／Change 1 同量級的既有缺口） | ✅ |
| persona | 加權 ≥ 6.0；P1「30 秒看懂四燈」≥ 5；P2「拖色即時一致」≥ 5（無實機證據 → 標待實測） | **GO-with-conditions 6.84**（P1 可理解性 7 ✅；P2 即時一致 6 暫定、待實測 ①②③）；無 S0；報告 `.superpowers/sdd/2026-09-09-panel-legend-palette/persona-report.md`，已折入 S2-4/5/6/8 與 S1-1（`667ef99`） | ✅（附條件） |

## 執行檔增量超標的說明（不調門檻）

+292 KB（universal；每架構約 +146 KB）。門檻 150 KB 是在 Change 1（純 AppKit 繪圖）的經驗上訂的；本 change 新增的是 **SwiftUI view**
（`LegendRowView`、`PanelView` 改吃 `PanelModel`、`ForEach`／`Button`／`onHover`／`help` 等修飾子）——SwiftUI 的泛型特化與 view body
展開在 release 下每個 view 型別都會產出可觀的程式碼，這是平台成本，不是本 change 的膨脹（`Sources/` 只 +475 行）。
**判定為 DoD miss，記 known gap，不事後改門檻**；R9 的意圖（極輕量）在絕對值上仍成立：整個 app 1.41 MB universal、RSS 11 MB。
若要收斂：(a) 面板改回純 AppKit 繪製（放棄 SwiftUI，代價大）；(b) 接受並把下一個 change 的門檻改成「每新增 SwiftUI view ≤ 60 KB/arch」這種
有平台依據的數字。建議 (b)，留給使用者裁決。

## 附帶發現

`NSColorPanel.shared` 若在 launch 同步區被建構（第一版把它當 `willClose` 觀察的 `object`），啟動多 **120 ms**、RSS **11 → 28 MB**——
reviewer 實測抓到，改成 `object: nil` ＋ block 內過濾後回到 11 MB。這是「一行程式碼的平台成本」的教材：R9 的量測要含 RSS 與啟動時間。

## 使用者實測清單（離屏不可驗的三件事；spec §7）

| # | 操作 | 預期 | 實際（請填） |
|---|---|---|---|
| ① | 有 session 在跑時開面板 → 點「等你」色點 | 系統色板出現；**面板仍在**（釘住） | |
| ② | 拖色 | icon（若當前聚合狀態就是 waiting）與面板圖例、列色點**同時**變 | |
| ③ | 關色板 → 點面板外 | 面板關閉；切到別的 app 再回來 → 面板不會卡在釘住 | |
| ④（順帶） | 「重設」 | 四色回預設、按鈕變灰 | |
| ⑤ | 游標停在圖例上時點面板外讓面板消失 | 指標**不會**卡在手形（`NSCursor.set()` 而非 push/pop） | |
| ⑥ | 讓一個 session 跑完、關掉那個 terminal、等綠燈 → 點開面板 | 面板裡有沒有那一列？persona 讀碼推論**沒有**（既有的 acknowledge 順序，S1-3）——證實即開獨立 change | |

## 證據
- 面板渲染圖：`docs/evidence/change2/index.html`（預設 palette × {空, 三列}、自訂 palette × 三列；淺／深底各一；淺底 `.aqua`、深底 `.darkAqua` 明確指定）
- 選單列：Change 1 的 E1（`docs/evidence/m4/E1-A2-*.png`）——本 change 不改 icon 形態

## Persona 照出來的 known gaps／後續

| # | 內容 | 性質 | 落點 |
|---|---|---|---|
| S1-2 | 預覽面 ≠ 被客製化的面：拖色時看的是 10pt 圓點疊面板底色，真正被改的是 8pt LED 疊 `#141416`；idle 時 icon 不會變 | 本 change 設計代價（spec §9 已揭露） | 下一個 change：圖例旁迷你 LED×底板預覽（~20 行），或色板開著時 icon 跑 demo 迴圈 |
| **S1-3** | `togglePopover` 先 `acknowledgeAll()` 再 `show` → 已結束的 done/error 列在面板出現前就被移除，使用者永遠看不到「哪個專案完成了」 | **既有**（M5 的 D2 語意），圖例的「已完成」讓它顯眼 | 使用者實測 ⑤ 證實後**立即開獨立 change**（最小修：`onOpen` 移到 `show` 之後，或 acknowledge 延到面板關閉） |
| S2-7 | 「重設」無確認、無 undo | 復原成本分鐘級 | 記錄；若使用者反映再加二次確認 |
| S2-9 | 色弱：能力有效（黃色 waiting 讓 deutan ΔE 9.7→15.3）但零導引；預設 palette deutan 最小 ΔE 7.9（錯誤 vs 已完成） | F-01 家族 | Change 3 候選：亮度差／ΔE 提示 |
| S3-10/11/12 | 空面板重複句、版面偏左、提示行永久教學 | 打磨 | 記錄 |
| 執行檔 | +253 KB（SwiftUI 平台成本） | DoD miss | 使用者裁決門檻（建議：每新增 SwiftUI view ≤ 60 KB/arch） |

## review closure 順手量到的（給 A2-light change 的輸入）

淺色面板（白底、`.aqua`）上四態列色點對白的對比：`.error` 2.22:1、`.working` 2.10:1、`.done` 1.50:1、`.waiting` 1.48:1；修過的 `.idle`（忽略 alpha）**3.15:1**
——淺色面板上最清楚的那顆點是 idle。成因是 palette 用 systemXxx 的**深色**變體（m4 §3 釘死；F-01/F-05 known gap），與本 change 無關；
是 F-02「A2 淺色微調」該一起處理的數字。
