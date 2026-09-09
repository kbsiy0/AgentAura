---
change: m4-icon-form
release_target: softlaunch
persona_impact: tier1
persona_impact_reason: 動 Sources/AgentAuraApp/** 與 AuraCore/IconAppearance.swift（專案 CLAUDE.md 列名的 Tier 1 路徑）；本 change 的核心產出就是一個由 persona 打分決定的視覺形態
revision: r7（2026-09-09，折入 review-t04-06 的 I-A/I-B/Minor 1、6；r6 = review-t01-0203；r5 = idle 子斷言襯底；r4 = r3 APPROVED）
---

# Change 1 · `m4-icon-form`：用證據決定 icon 形態

> 正典設計 `2026-09-08-agentaura-design.md` 的 M4 里程碑細化。衝突以正典為準，
> 但本文件對正典的**修訂**（§8.2 逐句列舉）在 Change 1 合併時回寫。
> 視覺輔助：`docs/2026-09-09-m4-icon-forms-mockup.html`（候選 mockup）、
> `docs/2026-09-09-m4-icon-form-design.html`（r1 圖版，使用者逐節核准；**本 .md 為權威**，
> r2 與圖版的差異列在 §11）。

## 0. 背景與裁決

2026-09-09 13:00 使用者對現行形態 A（8 顆裸 LED）做第一次人眼驗收
（`docs/2026-09-09-m4-round1-human-eye.md`）：error 紅 blink、waiting 橘呼吸、
done 綠恆亮三者清楚；**working 的 systemBlue 呼吸在藍桌布＋透明 menu bar 下幾乎看不到**。
根因是顏色編碼對背景敏感，不是 alpha 太低。

brainstorm 六題裁決（同日 13:14–13:40）：

| # | 問題 | 裁決 |
|---|---|---|
| 1 | 客製化範圍 | **只有顏色**；形態單選、R4 動畫規則不開放 |
| 2 | 快速上手 | **面板常駐圖例列**（四點＋標籤） |
| 3 | 改色入口 | **圖例點即設定**（`NSColorPanel`）＋「重設預設」 |
| 4 | working 看不見 | **LED 加底板 → 形態 A2** |
| 5 | 8 顆各自有意義？ | **否**，純造型、單一訊號 |
| 6 | 形態 B | **B2 光環點**（6pt 核心＋14pt 細環）；working 預設色兩形態一致，A/B 只比形狀 |

裁決 2、3 屬 **Change 2 `panel-legend-palette`**，不在本文範圍。

### 新增需求（使用者 13:10 口述，本 change 起生效）

| 編號 | 需求 | 本 change 的落點 |
|---|---|---|
| R7 | **快速上手**：裝好就知道四種燈是什麼 | Change 2（圖例列）。本 change 只保證兩形態的四態在視覺上可分（§4.4 打分維度） |
| R8 | **面板可客製化** | Change 2。本 change 鋪 `IconPalette` 讓顏色成為資料而非 view 內的 switch，**且有 gate 證明 view 真的吃它**（§6 `renderersHonorPalette`） |
| R9 | **極輕量、盡可能簡單** | 可量測落點：零新依賴（`Package.swift` diff）、零新 target（`dump-package`）、無使用者可見設定、執行檔增量 < 150 KB（基準 1,104,896 bytes universal，main `2b8cdbd`）、`Sources/` 淨增 ≤ 250 行（刪輸家後）、輸家不保留 |

## 1. 目標與範圍

**做**：`IconPalette`（純資料、預設色）· 形態 A2 · 形態 B2 · 兩 renderer 共用 `IconState → IconAppearance` ·
啟動時隱藏切換鍵（開發用）· persona A/B 打分協議與決策規則 · 刪輸家 · 正典逐句回寫 · CLAUDE.md／README 過時句修正。

**不做**：圖例列、改色 UI、持久化（Change 2）· 亮幾顆＝幾個 session（裁決 5）· 使用者切換形態（裁決 1）·
動畫規則調整（R4 的週期／alpha 範圍不動）· 淺色模式淺底板變體（§10 風險，等 persona 回饋）。

## 2. 架構總覽

A/B 的差異被壓到**最後一個 view 類別**。注意力預算（R4）、聚合（D1）、動畫排程、幀率 DoD 全在分岔前，
既有 `@Suite("注意力預算（R4）")` 與 `@Suite("動畫排程與省電")` 對兩形態同時成立（指名 suite，不寫數字——數字會 drift）。

```
IconState ──▶ AppearancePolicy.appearance(for:palette:reduceMotion:) ──▶ IconAppearance ──▶ AnimationDriver ──┬─▶ LEDStripView (A2)
                       ▲                                                   color·animation·fps    phase 0…1    └─▶ HaloView     (B2)
                 IconPalette.default                                       （形態無關）
```

| 單元 | 層 | 狀態 | 職責 | 依賴 |
|---|---|---|---|---|
| `RGBA` / `IconPalette` | AuraCore | 新 | 五個**非 optional 具名欄位**（`idle/working/done/waiting/error`）+ `subscript(Activity)` 純轉發；`.default` 為 §3 釘死的數字 | 無 |
| `AppearancePolicy` | AuraCore | 改 | `appearance(for: IconState, palette: IconPalette = .default, reduceMotion: Bool = false)`，把 `palette[activity]` 解析進 `IconAppearance.color` | IconPalette |
| `IconAppearance` | AuraCore | 改 | `+ color: RGBA` | RGBA |
| `AnimationCurve` | AuraCore | 新 | `alpha(for: IconAnimation, phase: Double) -> Double`（自 `LEDStripView` 搬入）與 `period(of: IconAnimation) -> Double?`（自 `AnimationDriver` 搬入）；**App 層不得再對 `IconAnimation` 做 switch**（§6 來源掃描） | IconAnimation |
| `IconDrawing` | App | 新 | `@MainActor protocol IconDrawing: AnyObject`（照 `IconRendering` 寫法）：`update(_: IconAppearance, phase: Double)`、`var preferredWidth: CGFloat { get }`（instance）；conformer 皆為 `NSView` 子類 | AppKit |
| `LEDStripView` | App | 改 | view bounds **含底板**；顏色吃 `appearance.color`、alpha 吃 `AnimationCurve`；conform `IconDrawing`；暴露幾何常數供測試推導取樣點 | IconDrawing |
| `HaloView` | App | 新 | B2 畫法；同樣暴露幾何常數 | IconDrawing |
| `IconForm` | App | 新→**評後刪** | `enum { ledStrip, halo }`；`static func resolve(from: UserDefaults) -> IconForm`（key `AgentAuraIconForm`，`led`／`halo`，其他一律 `.ledStrip`）；`@MainActor func makeView() -> any IconDrawing` | Foundation |
| `StatusItemController` | App | 改 | `init(defaults: UserDefaults = .standard)`；`internal let drawing: any IconDrawing`；`internal var statusItemLength: CGFloat { item.length }`；`@MainActor func removeFromStatusBar()`（測試 teardown 用；**不用 `deinit`**——nonisolated deinit 碰非 Sendable 的 `NSStatusItem` 在 Swift 6 編不過）；status item 長度 = `drawing.preferredWidth + 8`，view frame `x: 4, width: preferredWidth, height: NSStatusBar.system.thickness` | IconDrawing |
| `AnimationDriver` | App | 改（最小） | `period(of:)` 移到 `AnimationCurve`，`reschedule()` 改呼叫它；其餘不動 | AnimationCurve |
| `AppDelegate` / `AnimationSchedule` | — | 不動 | | |

**設計選擇**
1. 顏色解析放 `AppearancePolicy`（AuraCore）而非 view：兩 renderer 不各自查表、顏色邏輯可單元測試、Change 2 換調色盤時 view 一行不改。**消費端有 gate**（§6 `renderersHonorPalette`），否則「值被算出來、被轉發、然後被忽略」會讓 R8 的鋪路整段未驗證。
2. 預設色是**固定 RGBA**，不是 `NSColor.systemX` 的深淺自適應：A2 有不透明底板、背景已固定；B2 用深色 palette 值在淺 bar 上也夠亮。代價：放棄系統色自動翻轉**與高對比模式變體**——R9 換的；正典 §3.6「跟隨深淺色外觀」一句隨本 change 刪除（§8.2）。Change 2 的使用者自選色本來就是固定值，兩者一致。
3. `IconPalette` 用 5 個 stored property 而非 `[Activity: RGBA]`：字典無法在型別上保證完整，而缺值 fallback 到 idle 灰＝靜默退化成 round-1 那個 bug。型別層保證＋`Mirror` 對 `Activity.allCases` 驗欄位名（與 `SessionSnapshot` 既有做法一致）。

## 3. 資料模型

```swift
public struct RGBA: Equatable, Sendable, Codable { public let r, g, b, a: Double }   // sRGB 0…1
// `a` = 該狀態的**基礎 alpha**，繪製時再乘上 `AnimationCurve.alpha`。五個預設值只有 idle 不是 1（0.35）——
// idle 的低存在感因此編在 palette 裡，兩個 renderer 都沒有 per-state alpha 特例（spec-review-r3 I1）。
// Codable 為 Change 2 持久化預留；本 change 無消費者、不測 Codable 行為。

public struct IconPalette: Equatable, Sendable {
    public let idle, working, done, waiting, error: RGBA
    public subscript(_ a: Activity) -> RGBA          // 純轉發，不可能缺值
    public static let `default` = IconPalette(
        idle:    RGBA(r:  72/255, g:  72/255, b:  74/255, a: 0.35),// #48484a 極暗灰 × 0.35（兩形態 idle 同等存在感）
        working: RGBA(r:  10/255, g: 132/255, b: 255/255, a: 1),   // #0a84ff systemBlue(dark)（見下）
        done:    RGBA(r:  48/255, g: 209/255, b:  88/255, a: 1),   // #30d158 systemGreen(dark)
        waiting: RGBA(r: 255/255, g: 159/255, b:  10/255, a: 1),   // #ff9f0a systemOrange(dark)
        error:   RGBA(r: 255/255, g:  69/255, b:  58/255, a: 1))   // #ff453a systemRed(dark)
}

public struct IconAppearance { /* 既有欄位不動 */ public let color: RGBA }   // 由 AppearancePolicy 依 palette[activity] 解析
```

**working 為什麼維持 systemBlue `#0a84ff`、門檻為什麼是 2.5 而不是 3**（r2 曾改成 `#50a8ff`，r3 撤回；spec-review-r2 B1）：

實算（WCAG sRGB 相對亮度，LED 以動畫 alpha 疊在不透明底板 `#141416` 上）：

| | working `#0a84ff` | error `#ff453a` | waiting `#ff9f0a` | done `#30d158` | idle `#48484a` |
|---|---|---|---|---|---|
| 靜態 alpha 1.0（＝ reduceMotion 開啟時的真實渲染） | **5.04** | 5.40 | 8.95 | 9.10 | 2.02（不納 gate） |
| 各自動畫峰值（working 0.60、error/waiting 1.0） | **2.55** | 5.40 | 8.95 | — | — |
| 谷值（working 0.35、waiting 0.20、error 0.08） | 1.62 | 1.08 | 1.46 | — | — |

1. round-1 的根因是**顏色編碼對背景敏感**（§0），這一項已由**不透明底板**單獨解決，與藍色多亮無關。
2. 把 working 調亮到峰值 ≥ 3:1 會讓靜態對比超過 error（`#50a8ff` 靜態 7.35 > error 5.40；掃過整個色相，
   「峰值 ≥ 3 且靜態 ≤ 5.40」**解集為空**，因為兩者是同一亮度的單調函數）。結果是 reduceMotion 開啟時——動畫消失、
   只剩顏色——最醒目的變成「不需要理它」的 working。這違反 R4「常態最安靜」，也打到 §9 剛認領的那群人。
3. 3:1 是本 spec 自訂的文字級門檻，不是 R4／正典／WCAG 對「刻意安靜的常態指示燈」的要求。
   working 峰值門檻取 **2.5:1**（實算 2.55），靜態仍 ≥ 3:1；並新增 **顏色半邊的 R4 gate**：
   `contrast(working) < contrast(error)` 在靜態與峰值兩點都成立（5.04 < 5.40、2.55 < 5.40）。
   working 峰值到底夠不夠亮，交給 E1 與 persona 回答，不由自訂門檻預先決定。
4. **注意：working 的絕對對比沒有變好**（峰值 2.55、谷值 1.62，與 round-1 同一顏色）。本 change 修的是「藍疊在藍桌布上
   對比不可控」——不透明底板讓它固定；藍色本身沒變亮。夠不夠亮由使用者看 E1 判，不夠就走 Change 2 的自選色。
5. **可用窗口**（spec-review-r3 掃 b=255 的藍，353 組解）：要同時滿足 `plateGuaranteesContrast (c)` 與 `workingIsQuietestColor`，
   working 藍的峰值對比須落在 **2.50–2.71**、靜態 **4.83–5.40**。`#0a84ff` 落在峰值下界 +0.05、靜態上界 −0.36。
   未來動這個顏色，箱子就這麼大。

**護欄**：這五組數字是 gate 的輸入也是 persona 比較的對象。**實作者不得為了讓對比 gate 轉綠而調 palette 值**；
要調就回來改本節並在 commit message 記錄理由。

`IconState` 不變。無持久資料；`AgentAuraIconForm` 是開發期 `UserDefaults` key，評後連同 `defaults delete io.agentaura.app AgentAuraIconForm` 一起清除。

## 4. 核心技術

### 4.1 A2 底板

| 參數 | 值 | 理由 |
|---|---|---|
| view 尺寸 | `preferredWidth = 42`（8×3 + 7×2 = 34 燈條 + 左右各 4）；高 = bar thickness（22） | **view bounds 含底板**，離屏畫布與生產畫布一致；r1 的「bounds 外擴」會被裁掉 |
| 底板矩形 | `NSRect(x: 0, y: (h−18)/2, w: 42, h: 18)`，圓角 5pt；LED（3×12）在其中垂直置中、水平從 x=4 起 | LED 上下各 3pt、左右各 4pt 邊距 = mockup §2 比例 |
| 底板色 | **不透明** `#141416`（20,20,22，alpha 1.0），深淺模式一律 | 背景無關 → 離屏量測等於現實；淺模式更「重」是已知代價，交 persona 判（§10） |
| 底板描邊 | 0.5pt `rgba(255,255,255,0.10)`，路徑取 `plateRect.insetBy(dx: 0.25, dy: 0.25)`（否則外側 0.25pt 被 bounds 裁掉） | 淺 bar 上邊緣不糊 |
| LED 顏色／alpha | 顏色 `appearance.color`；alpha = `appearance.color.a × AnimationCurve.alpha(for:phase:)` | 不再自己 switch activity、不再自己算曲線、無 per-state alpha 特例 |
| idle | LED 用 palette idle 色 `#48484a × a 0.35`，底板照畫 | 底板恆在＝「app 活著」的錨點；idle 燈刻意近乎隱形（靜態 2.02:1 再乘 0.35），**不納入 3:1 gate**。r4 起 alpha 來自 palette 而非 view |
| status item | `item.length = drawing.preferredWidth + 8`；view frame `x: 4, width: 42` | 4pt 是 bar 外邊距（controller 一處），底板內 4pt 是 LED 邊距（view 一處）——不是雙重邊距 |
| 幾何常數 | `static let ledSize/ledGap/plateInset/plateHeight`，`func ledRect(at index:) -> NSRect` internal | 測試從幾何推導取樣點，不寫魔術數字 |

### 4.2 B2 光環

| 參數 | 值 | 理由 |
|---|---|---|
| view 尺寸 | `preferredWidth = 16`；高 = bar thickness | 環外緣 7.75 需要 ±7.75 → 16 才裝得下（r2 的 14 會裁掉左右各 0.75pt） |
| 幾何 | 環心 = `bounds` 中點；外環直徑 14pt、線寬 1.5pt（半徑 7，環帶 6.25–7.75）；核心直徑 6pt；同心 | 數字以本表為權威，mockup 只供參考 |
| 顏色 | 環與核心同色 = `appearance.color` | 單一訊號 |
| 動畫 | **只有環**套 `AnimationCurve.alpha`；核心 alpha 固定 1.0 | 餘光抓「環在動」，核心保住「有東西在」 |
| idle | 環與核心都用 idle 色；alpha 來自 `palette.idle.a`（0.35），view **無** per-state 特例 | 與 A2 idle 同等存在感；`renderersHonorPalette` 的預期值可直接由 palette 算出 |
| 無底板 | — | B 的假設是「像素少、像系統 icon」；要底板就沒有存在理由 |
| status item 寬度 | 16 + 8 | |
| 幾何常數 | `static let ringRadius/ringWidth/coreRadius` internal | 測試推導取樣點：環取 `(mid.x + ringRadius, mid.y)`（描邊中心線，@2x 像素 x=30 < 32）、核心取中心 |

### 4.3 A/B 切換（開發期）

```bash
defaults write io.agentaura.app AgentAuraIconForm halo   # 或 led（預設）；domain 對過 Resources/Info.plist
pkill -f AgentAuraApp && open build/AgentAura.app
```
只在啟動時讀一次；無 UI；不進 INSTALL.md／README。決定後刪輸家 view 與其測試、刪 `IconForm`、`StatusItemController` 直接建贏家——這是 tasks 的最後一個 task（T09）。
DoD 除 repo grep 外還要機器側檢查：`defaults read io.agentaura.app 2>/dev/null | grep -c AgentAuraIconForm` = 0。

### 4.4 打分協議

**證據**（E1 為必要；E1′ 為補充；只有 E1′ 時 T08 **不得產生 go 決策**，只能出「待實機驗證的暫定排名」）

| # | 證據 | 產出者 | 覆蓋 | 必要性 |
|---|---|---|---|---|
| E1 | **實機截圖**（⌘⇧4，系統截圖 UI，不需 agent 端權限）：最小集 = 兩形態 × {深色＋藍桌布, 淺色} × **working** = 4 張（working 是爭點）；完整集 = 再加 done/waiting/error = 16 張。**只截 menu bar 右側最小範圍**，進 repo 前使用者確認無識別資訊 | 使用者 | 真實 menu bar 透明合成下的對比、鄰近系統 icon 的違和度 | **必要（最小 4 張）** |
| E1′ | **離屏合成圖**：真 view 離屏繪製 @2x（sRGB），疊在模擬 bar（深/淺）與模擬桌布（藍/暖/灰）上；同組另出 0.5× 縮圖模擬遠距 | `EvidenceRenderer`（測試 target 內，`AURA_RENDER_EVIDENCE=1` 啟用，輸出 `docs/evidence/m4/`） | 幾何、顏色、reduceMotion 樣貌（靜態圖恰是 reduceMotion 的樣子）；**模擬不了**真實 backdrop blur／vibrancy——這正是 round-1 根因，所以不能取代 E1 | 補充 |
| E2 | 10 秒螢幕錄影 × 2（waiting、error）× 兩形態（⌘⇧5） | 使用者 | 餘光、動畫形狀可分性——P1 兩個關鍵維度的唯一動態證據 | 建議；缺席時 P1 的「餘光辨識」「常態安靜」以 E3 打分並標「無錄影」 |
| E3 | `docs/2026-09-09-m4-icon-forms-mockup.html`（真實動畫時序；r3 已同步底板不透明，working 色本就是 `#0a84ff`；B2 寬度以 §4.2 為準） | 已有 | 補 E2；**只用於動畫時序與形狀**，對比／顏色維度以 E1/E1′ 為準 | 補充 |
| E4 | `docs/2026-09-09-m4-round1-human-eye.md` | 已有 | 基準線 | 補充 |

persona 報告**每個分數**標明依據（E1/E1′/E2/E3/E4）。

**Persona（3 個並行）**

| Persona | 權重 | 看重 |
|---|---|---|
| P1 整夜 pipeline 操作員（R1/R4 原型使用者） | 0.45 | 餘光辨識、遠距辨識、working 夠不夠安靜 |
| P2 色弱使用者（**兼代表開啟「減少動態效果」與「增加對比」的使用者**） | 0.30 | 不辨色能否分 waiting／error／done；reduceMotion 下（＝靜態圖）仍可分否；淺模式易讀性 |
| P3 極簡 menu bar 使用者 | 0.25 | 與系統 icon 列協調、佔寬、「像不像一個 macOS app」 |

**維度**（每 persona 對兩形態各打 0–10）：餘光辨識 · 遠距辨識 · 不辨色可分 · 常態安靜 · 系統協調 · 資訊清晰。
P2 另加一格「reduceMotion 仍可分」。加權信心指數 = Σ(persona 權重 × 該 persona 各維平均)。
報告必須附**六維原始分數矩陣**（3 persona × 2 形態 × 6 維），並對 B2 **單獨回答**一句：「B2 無底板，round-1 的背景敏感根因在 B2 上未修復——E1 藍桌布組的 working 看得見嗎？」若 B2 勝出，決策報告必須明寫「選擇 B2 等於接受 working 在特定桌布下對比不可控」。

**決策規則（寫死）**
1. 信心指數高者勝。
2. 差距 < 0.5 視為平手 → 取 **P1「餘光辨識」在最壞背景（淺色 bar）** 高者——這是本 change 的動機維度。
   （r1 用「不辨色可分」決勝；但兩形態刻意對齊顏色、動畫、單一訊號，該維度幾乎無鑑別力，會直接流到規則 3。）
3. 仍平手 → 取程式碼較少者（R9）。報告必須寫明「落到規則 3」。
4. **硬下限**：任一 persona 對贏家的「餘光辨識」< 5，或 P2 對贏家的「不辨色可分」< 5 → 視同不合格。
5. 贏家指數 < 6.0 或觸發規則 4 → **不選**，回 brainstorm（兩個都不夠好）。

## 5. 錯誤處理

本 change 沒有新的 I/O 路徑。

| 情況 | 處理 |
|---|---|
| `AgentAuraIconForm` 值非 `led`／`halo`（含缺值、垃圾） | 視為 `led`，不 log、不 crash |
| `IconPalette` 缺某 activity 的色 | **型別上不可能**（5 個非 optional 欄位）；`Mirror` gate 守欄位名與 `Activity.allCases` 一致 |
| 離屏繪製失敗 | 只影響測試／evidence renderer；生產路徑不走離屏 |
| 測試行程建了 `NSStatusItem` 沒清 | 測試 `.serialized` 且 teardown 顯式呼叫 `controller.removeFromStatusBar()`（生產 controller 活到 app 結束，不需移除） |
| 離屏取樣點越界 | harness 對每個取樣點斷言 `0 ≤ x < width, 0 ≤ y < height`，越界 **throw**（大聲紅），不回一個看起來像顏色的值 |

## 6. 測試策略

T01 先行（無生產邏輯、只有 compile-only stub）：對抗式 double ＋ composition-root smoke。

**共用 harness**（`Tests/AgentAuraAppTests/OffscreenRender.swift`）：`render(_ view: NSView, over background: NSColor) -> sRGBBitmap`——
自建 **sRGB** `CGContext`（`CGColorSpace(name: .sRGB)`，8-bit，@2x），先填背景、再 `view.displayIgnoringOpacity(bounds, in:)`；
`pixel(atPoint: CGPoint) throws` 由 view 座標轉像素（×2、y 翻轉），**越界 throw**、**取到 α≠1 也 throw**（背景沒鋪滿或 premultiplied 未還原會讓數字靜默錯；r6），回 sRGB 分量；`contrast(_:_:)` 用 WCAG 相對亮度；
`peakPhase(of: IconAnimation)` 用 `AnimationCurve.alpha` 對 phase 掃 argmax（不在測試寫死 0.5／0——否則第二份曲線知識又在測試層長回來）；
`expected(_ c: RGBA, curveAlpha: Double, over bg:)` = `c × (c.a × curveAlpha)` 疊在 bg 上——像素 gate 的預期值一律由此算，palette 的 `a` 因此也被驗到。
`drawing.frame` 透過 `try #require(controller.drawing as? NSView).frame` 取得（protocol 不加 `frame`）。
靜態 appearance 一律經 `AppearancePolicy.appearance(for:palette:reduceMotion: true)` 取得（`IconAppearance` 的 memberwise init 是 internal，App 測試不 `@testable import AuraCore`）。
gate 訊息印出色彩空間名與取樣座標。**不用** `bitmapImageRepForCachingDisplay`——實測它回裝置色彩空間（本機 `SAMSUNG colorspace`），數字不可跨機重現。

| Gate | 層 | 守什麼 | Mutation（改壞 → 指名測試幾秒內紅） |
|---|---|---|---|
| `paletteSubscriptIsTotal` | AuraCore | 用五色彼此差異極大的 palette，`for a in Activity.allCases { palette[a] == 對應欄位 }`（守 subscript 接錯欄位——型別已守住完整性，這條守正確性）；次要斷言：`Mirror` stored property 名集合 == `Activity.allCases.map(\.rawValue)` | subscript 的 `.waiting` case 改回傳 `idle` 欄位 → <1s（編得過、必紅） |
| `appearanceCarriesPaletteColor` | AuraCore | 用**非預設、五色彼此差異極大**的 palette，對每個 activity 斷言 `appearance.color == palette[activity]`（不可用預設 palette——stub 常數會讓 `==` 恆真） | policy 寫死回 default → <1s |
| `animationCurveBoundaries` | AuraCore | phase 0／0.5／1 的 alpha；double blink 四窗口 0.14/0.28/0.42 兩側；breathe 對稱 | 0.14 → 0.15 → <1s |
| `periodIsExtracted`（r6，review I1） | AuraCore | `period(of:)`：breathe 4.0、doubleBlink 1.1、none nil——原本零 gate，兩 case 回 nil 全套件零反應而 `reschedule()` 的 `?? 1.0` 會讓 working 4s 變 1s | 任一 case 回 nil → <1s |
| `appLayerNeverSwitchesOnIconAnimation` | 來源掃描 | 掃描函式**參數化** `scanForAnimationSwitches(under:) throws -> (scanned, hits)`：**讀不到檔就 throw**（不是當乾淨）、檔數由同一個 reader 回報；正式斷言傳 `Sources/AgentAuraApp`，不得出現 `case .breathe` 或 `case .doubleBlink`，掃到 ≥ 5 個 .swift；正向對照 (i) 暫存目錄 probe（`Gate.withTemporaryDirectory`）→ 必回報；(ii) **同語料同 reader**：掃 `Sources/AuraCore` 必須**恰好**回報 `AnimationCurve.swift`（r6，review I2：純 ASCII probe 抓得到不代表含中文註解的真實碼抓得到）。**絕不往 `Sources/` 寫 probe** | view 或 driver 保留任何一份 switch → <1s；reader encoding 改 `.ascii` → (ii) 紅 |
| `renderersDrawEveryActivityWithoutCrash` | App | 兩 view × 5 activity × phase {0, .5} 離屏繪製無 crash、有非透明像素。**分工說明**：對 A2 這條由底板本身滿足，「只少畫 LED」由 `plateGuaranteesContrast` 交叉補——T09 刪輸家時不得把交叉覆蓋一起刪 | draw 提早 return → <2s |
| **`renderersHonorPalette`（對抗式，兩 view 各一）** | App | 以非預設、五色差異極大、**五色 a 皆 1** 的 palette，**五個 activity 逐一（含 idle）**靜態繪製；取樣點由幾何常數推導（A2：`ledRect(at: 3).center`；B2：核心中心＋`(mid.x + ringRadius, mid.y)`）；斷言取樣 sRGB 與 `expected` 差 ≤ 2/255。另一子斷言：同 palette 但 idle `a = 0.5`，取樣 ≈ 0.5 × idle 色 + 0.5 × **LED 實際的襯底**——A2 是底板色 `#141416`（字面值 pin、不從 view 讀），B2 是背景（證 view 真的乘了 `color.a`；r5：T05 實測「疊純黑」對 A2 任何實作都紅，因為 LED 疊在不透明底板上） | view 改回讀自己的 switch → <2s；view 忽略 `color.a` → <2s |
| **`plateGuaranteesContrast`（對抗式）** | App | A2 疊在**純白**與**純黑**兩背景各渲一次：(a) 底板像素兩次差 ≤ 1/255（證背景無關）；(b) working/done/waiting/error 四色，**靜態 alpha 1.0（＝ reduceMotion 的真實渲染）** 對底板 ≥ 3:1；(c) 四色在**各自動畫峰值**（phase 由 `peakPhase` 掃出）：**working 雙向 pin `2.54 ± 0.10`**（單邊 ≥2.5 只剩 0.63% 餘裕，8-bit 捨入就會紅在數值上；pin 同時擋過暗過亮）、其餘 ≥ 3:1；(d) 印出谷值供報告，不設門檻；(b′)(c′)（r6，review I3；r7 修正）：**LED 取樣點**在白／黑背景下也必須相同（≤1/255）——(a) 只證底板那一個像素，一塊沒鋪到 LED 底下的「底板」能讓 (a) 過而 LED 其實疊在背景上。**證人必須是半透明的格**：靜態分支 LED 全不透明、白黑恆同（review-t04-06 I-B：r6 的 (b′) 恆真），所以 (b′) 取**谷值**（working 0.35／waiting 0.20／error 0.08）、(c′) 取 working 峰值 0.60。若日後動畫 min/max 被調成全 1.0，這個性質就失去觀測——那時要另找證人。取樣點 `ledRect(at: 3).center` 與底板 `(2, h/2)`——底板取樣須 ≥1pt 遠離描邊與第一顆 LED（x∈[1.5, 3.5] 皆可；沾到描邊會讓 working 峰值掉到 1.95） | 底板 alpha → 0.82 → (a) 紅；working 改 `#48484a` → (c) 紅；各 <2s |
| **`workingIsQuietestColor`（R4 的顏色半邊）** | App | 同一 harness、**以 `IconPalette.default` 繪製**（不是那個五色差異極大的測試 palette——否則變成拿隨機顏色比大小）：`contrast(working)` 在靜態與峰值兩點都 **< `contrast(error)`**（5.04 < 5.40、2.55 < 5.40）。既有 R4 suite 只守 alpha 與週期；本 change 動了顏色，這是顏色那半邊的 gate | working 改 `#50a8ff`（靜態 7.35）→ <2s |
| `haloRingAnimatesCoreDoesNot` | App | B2 waiting 在 phase 0 與 0.5：核心像素相同、環像素不同；預期 alpha 由 `AnimationCurve` 算 | 核心也套 alpha → <2s |
| `iconFormSelectionIsWired` | App smoke | `UserDefaults(suiteName: "io.agentaura.tests.<UUID>")`（**絕不可**是 `io.agentaura.app`），三案例在**同一個** `@Test` 內：`halo` → `controller.drawing is HaloView`；`led` → `is LEDStripView`；垃圾值 → `is LEDStripView`。走真的 `StatusItemController.init(defaults:)`，`@MainActor` + `.serialized`，teardown `removePersistentDomain` + `removeStatusItem` | `IconForm` 讀完不用 → <2s |
| `statusItemWidthFollowsRenderer` | App | 兩形態下 `controller.statusItemLength == drawing.preferredWidth + 8`，且安裝的 frame：`drawing.frame.width == drawing.preferredWidth`、`origin.x == 4`、`frame.height == NSStatusBar.system.thickness`（bounds 含底板後 frame 是承重值） | 寬度或 frame 寫死 34 → <2s。**T09 後**：只剩一個 conformer，寫死成贏家的正確數字（50／42）不再紅——「derived」結構性不可觀測，gate 退化為「等於固定值」（review-t09 I-1） |
| `updateRequestsRedraw`（r7，review-t04-06 I-A） | App | 兩 view 掛進**自建 NSWindow**（裸 view 與 status-item-hosted view 的 `needsDisplay` 恆 false、不可觀測），`update` 後 `needsDisplay == true`。刪掉 `needsDisplay = true` 全套件仍綠、而 driver 每格 apply 之後沒人要求重繪、icon 停在上一格 | 刪 `needsDisplay = true` → <1s |
| `applyReachesDrawing`（r6，review I4） | App smoke | 真 `StatusItemController`：`apply(error 靜態)` 後離屏渲 `drawing`，LED 像素 = `.default.error` 疊底板（±2/255）。既有像素 gate 全部直呼 `view.update`、smoke 用 SpyRenderer 取代 controller——刪掉 `apply` 裡的 `drawing.update` 全套件仍綠、產品是永不更新的 icon（tested ≠ wired） | 刪 `drawing.update(...)` → <2s |
| 既有 `@Suite("注意力預算（R4）")`、`@Suite("動畫排程與省電")` | AuraCore | 不動、繼續綠 | — |
| 既有 isolation gate | — | `RGBA`／`IconPalette`／`AnimationCurve` 不得載入 AppKit——編譯器 gate 自動涵蓋新檔（reviewer 實測 `CGFloat` 不會多載 module，但本 spec 仍用 `Double`） | 已有 |

**T01 stub 規則**：每一條新測試都必須 RED（`paletteSubscriptIsTotal` 的 Mirror 次要斷言可能因欄位名對而綠，主斷言必紅）；等式型 gate 一律用非預設 palette；`iconFormSelectionIsWired` 三案例同一 `@Test`（否則「永遠回 led」的 stub 會讓兩例綠）；**禁 `fatalError`**（會殺掉 `swiftpm-testing-helper`）。

**去相關化**：`plateGuaranteesContrast`、`renderersHonorPalette`、`workingIsQuietestColor` 是本 change「語意不同於樂於配合 fixture」的三道關卡——問「看得見嗎」「顏色是你給的嗎」「常態真的最安靜嗎」，數字取代肉眼。

**Evidence renderer**（`Tests/AgentAuraAppTests/EvidenceRenderer.swift`，獨立檔——避免 gate 檔撞 300 行）：`.enabled(if: env["AURA_RENDER_EVIDENCE"] == "1")`，輸出路徑由 `#filePath` 推導到 repo root 的 `docs/evidence/m4/`，拒絕寫到 repo 外。

## 7. DoD（可量測）

| 項目 | 門檻 | 量法 |
|---|---|---|
| A2 對比 | 四色靜態 ≥ 3:1；峰值 working 2.54 ± 0.10、其餘 ≥ 3:1；底板背景無關 | `plateGuaranteesContrast` |
| R4 顏色序 | working 對比 < error 對比（靜態與峰值） | `workingIsQuietestColor` |
| palette 真的被畫 | 兩 view 取樣 = 非預設 palette 色（±2/255） | `renderersHonorPalette` |
| CPU（兩形態各量） | idle／done <0.1% · working <0.3% · waiting／error <1.5% | `top -pid` 60s，`scripts/demo-sessions.sh` 造狀態 |
| 幀率 | 0 / ≤10 / ≥30（不變） | 既有 suite |
| RSS | < 60 MB | `ps -o rss` |
| 執行檔增量 | < +150 KB vs 基準 **1,104,896 bytes**（universal，main `2b8cdbd`） | `ls -l` |
| `Sources/` 淨增 | ≤ 250 行（刪輸家後；基準 1,684 行；T03 後已用 142，T04–T06 進來後由 T09 刪輸家收斂） | `find Sources -name '*.swift' \| xargs wc -l` |
| persona | 贏家 ≥ 6.0 且未觸發硬下限，決策依 §4.4 規則；有 E1 才可 go | persona-tester 報告 |
| 行數 | Sources 每檔 ≤ 200、Tests ≤ 300 | 既有 gate |
| AuraCore 覆蓋率 | ≥ 90% | `--enable-code-coverage` |
| 輸家已刪 | repo `grep -r` 不到輸家類名與 `AgentAuraIconForm`；`defaults read io.agentaura.app` 不含該 key | T09 驗收 |

## 8. 檔案佈局、回寫、migration

### 8.1 檔案

```
Sources/AuraCore/IconPalette.swift              新   RGBA + IconPalette(5 欄位) + .default（~55 行）
Sources/AuraCore/AnimationCurve.swift           新   alpha(for:phase:)（~25 行）
Sources/AuraCore/IconAppearance.swift           改   + color；appearance(for:palette:reduceMotion:)
Sources/AgentAuraApp/IconDrawing.swift          新   protocol + IconForm（IconForm 評後刪）
Sources/AgentAuraApp/LEDStripView.swift         改   bounds 含底板、吃 color/curve、conform、幾何常數
Sources/AgentAuraApp/HaloView.swift             新   B2（~70 行）
Sources/AgentAuraApp/StatusItemController.swift 改   init(defaults:)、drawing、statusItemLength、removeFromStatusBar()、frame/寬度問 view
Sources/AgentAuraApp/AnimationDriver.swift      改   period(of:) 移出，改呼叫 AnimationCurve.period(of:)
Tests/AuraCoreTests/IconPaletteTests.swift      新
Tests/AuraCoreTests/AnimationCurveTests.swift   新
Tests/AuraCoreTests/AppLayerSourceScanTests.swift 新  appLayerNeverSwitchesOnIconAnimation + 正向對照（或併入 IsolationTests 若不超 300 行）
Tests/AgentAuraAppTests/OffscreenRender.swift   新   sRGB 離屏 harness
Tests/AgentAuraAppTests/RendererPixelTests.swift 新  五條像素 gate（含 workingIsQuietestColor）
Tests/AgentAuraAppTests/EvidenceRenderer.swift  新   E1′ 產生器（env gate）
Tests/AgentAuraAppTests/CompositionSmokeTests.swift 改  + iconFormSelectionIsWired、statusItemWidthFollowsRenderer
scripts/demo-sessions.sh                        新   造活的假 session；固定前綴 demo-*、不覆寫既有檔、只清自己建的
docs/evidence/m4/                               新   E1（使用者截圖，最小範圍）＋ E1′
```

### 8.2 正典回寫（逐句，T09 驗收用 grep）

| 正典位置 | 現句 | 改為 |
|---|---|---|
| §0 表 | （無 R7–R9） | 加 R7 快速上手 / R8 面板客製化 / R9 極輕量三列，註明 R7/R8 由 Change 2 落地 |
| §3.6 首行 | 「`NSStatusItem` + 自繪 `NSView`（`LEDStripView`，8 顆 LED）」 | 依贏家改寫（A2：「8 顆 LED ＋ 不透明底板」；B2：「`HaloView` 光環點」） |
| §3.6 表 idle 列 | 「極暗單點，近乎不可見」 | A2 贏：「極暗 LED 疊在恆在的底板上」；B2 贏：維持 |
| §3.6 尾句 | 「跟隨深淺色外觀。」 | **刪除**，改為「顏色為固定 RGBA（`IconPalette.default`），不隨深淺色翻轉；理由見 Change 1 §2 選擇 2」 |
| §6 檔案佈局 | 「`LEDStripView.swift  8 顆 LED 繪製`」 | 依贏家改名／改描述 |
| §8 M4 列 | 「只換 `IconRenderer` 實作」「兩形態截圖」 | `IconRenderer` → `IconDrawing`（view 層；`IconRendering` 是 controller 層）；出場條件補「E1 實機截圖為必要」；狀態改「已完成，選定 X，決策見 `docs/2026-09-09-m4-ab-decision.md`」 |
| CLAUDE.md / README | 「PR #2 待 merge」 | 已 merge（2026-09-09）；M4 狀態更新 |

驗收：正典內 `grep -c "跟隨深淺色外觀"` = 0、`grep -c "IconRenderer"` = 0、輸家類名 = 0。

### 8.3 Migration 與交接

Migration：無。

**交接給 Change 2 的已知 caveat**：`AnimationDriver.reschedule()` 只在 icon／環境變化時重算 `appearance`，之後每格重用同一值——
執行期換 palette 後**不會自動重繪**，Change 2 的改色 UI 必須觸發一次 `setIcon`／`reschedule`。本 change 無執行期換色，不受影響。

## 9. Persona Impact

- **P1 pipeline 操作員**：直接受益——working 在任何桌布下可見（A2 不透明底板）或形狀更有身份（B2）；餘光規則「動＝需要你」不變。
- **P2 色弱使用者**：本 change 第一次把「不辨色可分」寫成打分維度與硬下限。
- **開啟「減少動態效果」的使用者**：reduceMotion 下動畫全 `.none`，狀態編碼只剩顏色；疊上裁決 5（形狀不帶狀態訊號）與色弱 → icon 可能什麼都傳達不了。**已知代價**，由 P2 的「reduceMotion 仍可分」維度量化；Change 2 的自訂色是解法路徑。
- **開啟「增加對比」的使用者**：固定 RGBA 放棄系統高對比變體；淺模式的問題是易讀性不只是美感（r1 review 實算 2.99:1）。A2 不透明底板使之背景無關；B2 無此保護——這會反映在 P2 的淺模式分數。
- **P3 極簡使用者**：A2 的不透明深底板在淺色模式會「重」；這是 A2 必須在打分裡付的代價，不預先修飾。
- **既有使用者**：無設定遷移；重新 build 即生效；輸家不留、無殘餘開關（含 `defaults delete`）。

## 10. 風險

| 風險 | 緩解 |
|---|---|
| 淺色模式不透明深底板太重，P3 打低分 | 先接受；若 A2 因此輸給 B2，決策仍成立。若 A2 贏但 P3 單項 < 5，開 A2-light 微調 task |
| B2 14pt 在 22pt bar 內偏大 | 截圖階段若明顯，環直徑改 12pt、`preferredWidth` 同步改 14，重截一次，不算另一輪 |
| **B2 無底板 → round-1 的背景敏感根因在 B2 上未修復**（A/B 結構性不對稱） | 守門：E1 藍桌布組（working）、tie-break 的最壞背景餘光辨識、硬下限。persona 對 B2 單獨回答 §4.4 那句；若 B2 勝出，決策報告明寫「選擇 B2 等於接受 working 在特定桌布下對比不可控」 |
| 兩個都不到 6.0 或觸發硬下限 | §4.4 規則 5：不選、回 brainstorm |
| 使用者未提供 E1 | T08 只出暫定排名，不 go；T09 不執行；PR 標 blocked-on-evidence |
| E2 缺席 | P1 的餘光／常態安靜以 E3 + E4 打分並標註，報告可信度降級寫明 |
| 執行環境無 Screen Recording 權限 | 不影響：E1/E2 產出者是使用者的系統截圖 UI |
| 實機截圖帶入桌面內容進開源 repo | E1 只截 menu bar 右側最小範圍；使用者確認後才進 `docs/evidence/` |

## 11. r2/r3/r4 對 r1 圖版的差異（供使用者知悉）

-1. **r4（編輯層級，r3 APPROVED 後折入）**：idle 的 0.35 從 view 特例改成 `palette.idle.a`（A2 的 idle 因此也變 0.35，更隱形，與「刻意近乎隱形」一致）；working 峰值門檻改雙向 pin 2.54 ± 0.10；§3 寫入可用窗口與「absolute 對比沒變好、只是不再隨桌布浮動」；§10 加 B2 無底板的結構性不對稱。

0. **r3**：working 色**撤回** r2 的 `#50a8ff`、維持使用者在 mockup 看過的 systemBlue `#0a84ff`；working 峰值門檻 3:1 → 2.5:1；
   新增 `workingIsQuietestColor`（顏色半邊的 R4 gate）。理由：調亮會讓 reduceMotion 下 error 變成四色最暗（§3）。
   另：`StatusItemController` 不用 `deinit`（Swift 6 編不過）改 `removeFromStatusBar()`；`period(of:)` 一併搬進 `AnimationCurve`；
   B2 寬 14 → 16；Mirror gate 換成 subscript-totality gate；frame 三斷言；取樣越界必 throw。
1. 底板改**不透明**（r1 為 alpha 0.82）——原因：半透明底板讓對比隨 bar 深淺變（2.99 vs 5.20），gate 會自己挑背景（§3、§6）。
2. E1 實機截圖從「可選」改回**必要（最小 4 張）**；E1′ 降為補充；只有 E1′ 不得 go。
3. 決策規則 tie-break 改為「最壞背景下的餘光辨識」，新增單項硬下限。
4. `IconPalette` 改 5 欄位 struct；新增 `renderersHonorPalette`、`noSecondAlphaCurveInAppLayer`、`statusItemWidthFollowsRenderer`、`haloRingAnimatesCoreDoesNot` 四條 gate。
5. 正典回寫改逐句列舉（§8.2）。
