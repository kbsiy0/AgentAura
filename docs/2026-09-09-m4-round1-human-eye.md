# M4 形態 A 人眼驗收 — round 1（2026-09-09 13:00 起）

環境：Dark mode、menu bar 透明（ReduceTransparency 未開）、桌布偏藍。
app 從 main `2b8cdbd` 重建；demo session 為真 pid 的假檔（scripts/demo-sessions.sh（原 scratchpad/demo.sh，隨 Change 1 進版控））。

| 狀態 | 呈現 | 使用者 verdict | 備註 |
|---|---|---|---|
| error | 紅 double blink | ✅ 餘光可辨、夠明顯 | |
| waiting | 橘 1.1s 呼吸 | ✅ 清楚 | 紅→橘的「blink vs 呼吸」不辨色可分？（尚未問到答案） |
| working | systemBlue 4s 呼吸 α 0.35→0.6 | ❌ **幾乎看不到** | 藍桌布 + 透明 menu bar，藍色燈疊在藍背景上對比崩掉。**顏色編碼對背景敏感**——形態 A 的結構性弱點，不是調 alpha 就能解 |
| done | 綠恆亮 | ✅ 清楚 | 靜態綠在藍桌布上對比夠，問題只出在藍色 |

| 面板 | popover 380pt，排序 + meta + headline | ✅ 沒問題 | 兩個活著的 done session |

## 觀察到的非視覺項

- 刪檔後燈要 ~5s 才變：FSEvents 路徑讀不到檔就 `continue`，移除只靠 `refreshLiveness` timer。設計取捨，記一筆。
- 使用者自己這個 session 在 permission prompt 時亮橘，是真的訊號，會混進 demo。

## working 對比問題的候選方向（給 M4 A/B 設計用，未決）

1. LED 後面加固定底板（深色圓角矩形），讓 LED 顏色永遠疊在已知背景上，不受桌布影響
2. working 改用 `labelColor`（跟系統 template icon 一樣自動黑白），把「彩色」留給 attention 狀態——常態 = 單色，需行動 = 有色＋動
3. 形態 B（單一符號＋顏色＋動畫）若走 template image 路線，天然解掉這題——這是 A/B 要對照的點

## 使用者裁決（13:07）：working 藍色看不見的處理方向

> 要就是加上背景色，要就是讓使用者可以自己選擇顏色。

兩個方向都進 M4 A/B 的設計選項：
- **A2：LED 加底板**（深色圓角矩形，LED 疊在固定背景上，桌布不再影響）—— 零設定、行為確定，建議作為 A 的預設修正
- **可選色**：使用者自訂各狀態顏色 —— 需要設定 UI（新增介面面、持久化），建議列為後續選項而非 M4 必做
- 我提的 labelColor / template 路線：使用者未採納，記錄備查
