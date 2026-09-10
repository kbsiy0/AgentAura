# DoD 量測 · `change/m4-icon-form`（T07）

量測時間 2026-09-09 20:00–20:2x · 機器 Darwin 25.6.0 · app 為 `717fc24` 的 `./scripts/build-app.sh` 產物（universal）。
spec §7 為門檻來源。（r2：基線與 persona 已補）

| 項目 | 門檻（spec §7） | 實測 | 判定 |
|---|---|---|---|
| A2 對比 | 四色靜態 ≥3:1；峰值 working 2.54±0.10、其餘 ≥3:1；底板背景無關 | `plateGuaranteesContrast` 綠；working 峰值 **2.5440**；四色靜態／峰值／谷值與 spec §3 表誤差 <0.005 | ✅ |
| palette 真的被畫 | view 取樣 = 非預設 palette（±2/255）；含 `color.a` | `renderersHonorPalette` 綠（LED × 5 activity ＋ idle a=0.5；T09 前另有 Halo core／ring 與 Halo idle 子斷言，隨輸家刪除） | ✅ |
| R4 顏色序 | working < error（靜態與峰值） | 5.04 < 5.40、2.55 < 5.40 | ✅ |
| 幀率 | 0 / ≤10 / ≥30 | 既有 R4 suite 綠 | ✅ |
| RSS | < 60 MB | A2 11–12 MB、B2 11 MB（`top`，五態） | ✅ |
| 執行檔增量 | < +150 KB vs 1,104,896 | T07（含兩形態）1,159,136 → +54,240；**T09 後 1,155,552 → +50,656 bytes（+49 KB）**（integrator 主目錄 build；reviewer 自建 1,156,736，差 1 KB 為簽章不可位元重現） | ✅ |
| `Sources/` 淨增 | ≤ 250（刪輸家後） | T07 +165（含兩形態）→ **T09 後 1790 − 1684 = +106** | ✅ |
| 行數 | Sources ≤200 / Tests ≤300 | 最長 `PanelViewModel.swift` 124；Tests 最長 `RendererPixelTests.swift` ~250 | ✅ |
| AuraCore 覆蓋率 | ≥ 90% | **97.16% regions / 99.28% lines**（`swift test --enable-code-coverage` + `llvm-cov report`，只計 `Sources/AuraCore`） | ✅ |
| **CPU（60s `top`，五態）** | idle／done <0.1% · working <0.3% · waiting／error <1.5% | **基線 main**：0.13／0.12／1.82／5.15／4.07%<br>**A2**：0.08／0.10／1.81／5.07／4.42%<br>**B2**：0.06／0.07／1.72／5.07／3.97% | ✅ idle／done 達標且不劣於基線；⚠️ working／waiting／error **與基線同值**（既有缺口：30 fps 全 view 重繪；`main` 同樣超標），M4 未劣化 |
| persona | 贏家 ≥6.0、無硬下限觸發、有 E1 | **GO A2**：6.66 vs B2 5.51（規則 1，未進 tie-break）；硬下限：餘光最低 7、P2 不辨色 7；E1 4 張最小集到位。`docs/2026-09-09-m4-ab-decision.md` | ✅（附條件：P3「常態安靜」4／「系統協調」3 <5 → spec §10 的 A2-light 微調 task 條件成立，另開 change） |
| 輸家已刪 | grep 零命中、`defaults` 無 key | `grep -rn "HaloView\|AgentAuraIconForm"` 於 **`Sources Tests plugin README.md CLAUDE.md`** 零命中（spec §7 字面寫「repo」但 `docs/` 的決策紀錄、r1 圖版、plan task 表**必須保留**輸家名——實際驗收範圍如左，review-t09 Minor 6）；`defaults read io.agentaura.app` 無 key | ✅ |

## CPU：第一輪量測被汙染，第二輪與基線比對

第一輪（20:01–20:13）A2/B2 的 done 量到 3.3–3.8%，`sample` 顯示活動在 UpdateCycle／draw——**但那是我的 Claude Code session
自己在聚合裡**（正在跑指令 → working／waiting 動畫 10–30 fps），不是 demo 的靜態。基線那輪（20:38）我的 session 已隔離
（狀態檔標 `terminated`），done 只有 0.12%。第二輪（20:46–20:58）A2/B2 同樣隔離後：

| 狀態 | 門檻 | main 基線 | A2 | B2 | 判定 |
|---|---|---|---|---|---|
| idle | <0.1% | 0.13 | **0.08** | **0.06** | ✅ |
| done | <0.1% | 0.12 | **0.10** | **0.07** | ✅（A2 邊界值） |
| working | <0.3% | 1.82 | 1.81 | 1.72 | ⚠️ 既有缺口，不劣於基線 |
| waiting | <1.5% | 5.15 | 5.07 | 5.07 | ⚠️ 既有缺口，不劣於基線 |
| error | <1.5% | 4.07 | 4.42 | 3.97 | ⚠️ 既有缺口，不劣於基線（A2 +0.35 在取樣雜訊內） |

結論：**M4 沒有 CPU 迴歸**；兩形態靜態零成本、動態成本相同（動畫由共用的 `AnimationDriver` 驅動，與形狀無關）。
動畫態的絕對門檻（<0.3／<1.5%）`main` 本來就不達標——30 fps 呼吸走的是整個 `NSView` 重繪；要達標得改成
CALayer `opacity` 動畫（GPU 合成、零 draw），那是獨立的效能 change，不在 M4 範圍。**記為 known gap，另開 issue。**

量測教訓（進 Lessons）：量 menu bar app 的 CPU 時，**量測者自己的 Claude Code session 也是資料來源**——不隔離就是在量自己。

## 證據

- E1′：`docs/evidence/m4/index.html`（產生器現只產 A2 12 張；B2 12 張保留在磁碟並由 index 列為出局證據；每張 10 格；**只有 working 的靜態／峰值兩格不同**，其餘四態靜態＝峰值；
  谷值未入圖——persona 用 E1′ 判「常態安靜／餘光」時要知道這個限制，見 review-t04-06 Minor 5）
- E1：`docs/evidence/m4/E1-A2-dark-blue-working.png`、`E1-A2-light-working.png`、`E1-B2-dark-blue-working.png`、`E1-B2-light-working.png`（最小 4 張）＋ `E1-A2-dark-blue-waiting.png`；使用者 20:29–20:36 ⌘⇧4 最小範圍裁切
- E2：（未提供則 P1 的餘光／常態安靜以 E3 打分並標註）
- E3：`docs/2026-09-09-m4-icon-forms-mockup.html`（底板已同步不透明；只用於動畫時序與形狀）
- E4：`docs/2026-09-09-m4-round1-human-eye.md`

## Persona 照出來的 known gaps（進 PR／release notes）

| # | 內容 | 性質 | 落點 |
|---|---|---|---|
| F-01 | reduceMotion＋色弱：`waiting`（8.95:1）與 `done`（9.10:1）亮度差 1.7%，不辨色時是同一顆燈；working 5.04 vs error 5.40 亦近 | 兩形態共有，本 change 未引入亦未修；spec §9 已列代價 | Change 2 提供自選色**能力**（可把兩者拉開，證據圖 `docs/evidence/change2/` 的 custom palette 示範黃色 waiting），不做 UI 檢查；**F-01 仍為 known gap** |
| F-02 | A2 淺色外觀底板 vs bar 10–12:1，idle 亦然；P3 兩項 <5 | spec §10 預授權 | **A2-light 微調 change**：淺色底板落在 4–6:1，且 LED/底板對比深淺差 ≤0.1（不准把 round-1 買回來） |
| F-03 | A2 深色模式：亮 glyph 列中一塊比 bar 更暗的板（極性反轉），像 widget | 新發現、只有 E1′ 支撐 | 補一張含鄰近系統 icon 的 E1 再確認，併入 A2-light |
| F-05 | working 絕對位準 1.62–2.55:1 未變 | spec §3 註 4 已揭露 | Change 2 自選色 |
| F-06 | 8 顆同色 LED 誘導「8 = session 數」 | 裁決 5 | Change 2 圖例列（R7） |
| CPU | working／waiting／error 與 `main` 同值超標（1.8／5.1／4.0%） | 既有：30 fps 整 view 重繪 | 獨立效能 change（CALayer opacity 動畫） |
