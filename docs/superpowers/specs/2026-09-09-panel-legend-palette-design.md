---
change: panel-legend-palette
release_target: softlaunch
persona_impact: tier1
persona_impact_reason: 動 Sources/AgentAuraApp/**（面板 UI、選單列重繪路徑）與 AuraCore/IconAppearance 的消費端；R7 快速上手與 R8 客製化都是純人類面需求
revision: r5（2026-09-10，折入 phase-2 review-t0203 的 I1/I2/Minor 1–6；r4 = r3 APPROVED 折入編輯）
---

# Change 2 · `panel-legend-palette`：圖例列常駐、點圖例改色、四色持久化

> 承接 Change 1 `m4-icon-form`（形態定案 A2）。正典 `2026-09-08-agentaura-design.md` 為權威；本 change 對正典的修訂在 §8.2。
> 建立在 `change/m4-icon-form` 之上；PR #4 已於 2026-09-09 squash 進 `main`（`9df0456`），本分支在 T06 後 `rebase --onto origin/main`。

## 0. 背景與裁決

使用者 2026-09-09 13:10 口述三條需求（R7 快速上手／R8 面板客製化／R9 極輕量），brainstorm 裁決：

| # | 問題 | 裁決 |
|---|---|---|
| 1 | 客製化範圍 | **只有顏色**；形態單選、R4 動畫規則不開放 |
| 2 | 快速上手 | **面板常駐圖例列**（四點＋標籤，永遠顯示，不論有無 session） |
| 3 | 改色入口 | **圖例點即設定**：點圖例的色點 → 系統 `NSColorPanel`；另有「重設預設」 |

Change 1 交接（`docs/2026-09-09-m4-ab-decision.md`、m4 DoD 帳本）：**F-01**（reduceMotion＋色弱下 waiting 與 done 同亮度）——本 change 提供把兩者拉開的**能力**，不強制、不做 UI 檢查（見 §1 與 §8.2 對帳本的回寫）；**M9**（換 palette 必須觸發 `AnimationDriver` 重排）；**F-06**（8 顆同色 LED 被讀成 session 數）——圖例提示行明說「8 顆是一體」。

**本 change 自行決定的細節**（使用者授權「全部做完再講」，最終報告逐條標示）：

| 決定 | 內容 | 理由 |
|---|---|---|
| D-a | 可改色 **四態** `error / waiting / working / done`；`idle` 不進圖例、不可改 | 使用者說「四種燈號」 |
| D-b | 圖例順序 = D1 優先序高→低：**錯誤 · 等你 · 執行中 · 已完成**（釘死為具體序列） | 與面板排序、聚合同一套語言 |
| D-c | 標籤：`error`「錯誤」、`waiting`「等你」、`working`「執行中」、`done`「已完成」 | 面板既有用語 |
| D-d | 持久化：`UserDefaults.standard`（domain `io.agentaura.app`）key `AgentAuraColor.<activity.rawValue>`，值 `#rrggbb`；alpha 固定 1；寫入走 `PaletteCodec.encode`（只寫非預設、其餘 remove） | R9：四個字串，無設定檔 |
| D-e | 「重設」**常駐**，palette 為預設時 `disabled` | r1 的「才出現」會讓面板高度跳一次（review M10） |
| D-f | 面板列色點也吃 palette | 「顏色成為資料」貫徹 |
| D-g | `NSColorPanel` 關 alpha 滑桿、以 sRGB 讀色；**`rgba(from:)` 一律回 a = 1**（`showsAlpha = false` 只是藏滑桿，色板既有顏色的 alpha 不會被正規化——review-t0203 I1 實測 a=0.5 會一路進 palette，而 `hex()` 又丟 alpha → 這次半亮、重啟全亮）；轉不過就忽略那次變更；`activeActivity` 為 nil 時忽略 | 四色 a 恆 1 的不變式在 `rgba(from:)` **單一收口**強制，`changeColorGuards (e)` 守 |
| D-h | 提示行：「**燈固定 8 顆，與 session 數無關 · 點色點可改顏色**」，`.secondary` 11pt（persona S2-6/S2-4：原句少了「與 session 數無關」這關鍵半句、10pt 淺色 3.95:1） | 可發現性（裁決 3 的代價）＋ F-06 的機制而非宣稱 |
| D-i | **改色期間 popover 釘住**：`pick` 時 `popover.behavior = .semitransient` 且 `NSColorPanel.hidesOnDeactivate = false`（否則切到別的 app 走 `orderOut`、不發 `willClose`，釘住永不解除——review r2 N4 實測）；解除有**兩條**路徑：`willClose` → `onEnd`，以及 `togglePopover` 時無條件回 `.transient` | r1 假設「icon 是即時預覽」為偽（icon 只畫當前狀態；調色最常發生在 idle）——沒有面板就沒有回饋迴路。釘住狀態不可只有一條解除路徑（Lessons #8） |
| D-j | `setPanel` 只在**第一次**建 `NSHostingController`，之後只換 `rootView`，`PanelModel` 相同就跳過；`hostingController.sizingOptions = [.preferredContentSize]`（macOS 13+）讓 `preferredContentSize` 隨 `rootView` 自動同步且**會縮回**（review r3 I-b 實測 114→206→436→114；手動 `preferredContentSize = fittingSize` 會把面板凍在第一個高度，**不可用**） | `isContinuous` 拖曳每秒數十次 `onChange`，重建 controller 會閃 |
| D-k | 色點命中區 20×20pt（視覺 10pt 圓）；**整組「色點＋標籤」都可點**、hover 換游標、有 accessibility label/isButton（persona S2-5/S2-8） | 唯一入口不能太小 |

## 1. 目標與範圍

**做**：圖例列常駐 · 點圖例改色（即時：icon 立刻、面板釘住時圖例與列色點立刻）· 重設 · 四色持久化 · 面板列色點吃 palette · 換 palette 即重排 · popover 釘住／解除 · hosting controller 重用 · 正典回寫 · 全鏈接線 gate。

**不做**：改 idle 色 · 動畫規則 · 形態 · 匯入匯出／主題 · **F-01 的 UI 檢查或強制**（只給能力；m4 帳本那句「必須成為驗收條件」依 §8.2 回寫為「Change 2 提供能力、F-01 仍 known gap」）· 面板虛擬化／節流（另開）· 任何**自建**視窗（系統色板不算）。

## 2. 架構總覽

```
UserDefaults ──load(4 keys)────────▶ PaletteStore ──palette──▶ AnimationDriver.setPalette ──▶ AppearancePolicy(palette) ──▶ LEDStripView
   ▲                                  │   ▲
   └──persist = encode(palette)───────┘   │ set(color, for:) / reset()
NSColorPanel ──changeColor(Any?)──▶ ColorPickerCoordinator ──onPick──▶ AppDelegate.applyColor ──▶ store.set
   │ willClose ────────────────────▶ coordinator.onEnd ──▶ status.setPopoverPinned(false)
StatusItemController.setPanel(model) ◀── AppDelegate.refreshPanel ◀── store.onChange
PanelView(model, onPick, onReset) ─ LegendRowView ─ tap ──▶ controller.onPickColor(activity) ──▶ coordinator.pick + setPopoverPinned(true)
                                                    ─ 重設 ──▶ controller.onResetColors ──▶ store.reset()
```

| 單元 | 層 | 狀態 | 職責 | 依賴 |
|---|---|---|---|---|
| `PaletteCodec` | AuraCore | 新 | `hex(RGBA) -> String`；`rgba(hex:) -> RGBA?`（**先**驗長度 6／7 與字元集 `[0-9a-fA-F]`、**再**索引——用 `Array(utf8)`，不走 `String.Index` 位移；大小寫不拘、`#` 可選）；`decode(overrides: [Activity: String]) -> IconPalette`（逐 key 落回預設；**idle 永遠忽略**）；`encode(_:) -> [Activity: String]`（只含 customizable 且 ≠ 預設） | RGBA、IconPalette |
| `Activity` | AuraCore | 改（`Activity.swift`） | `+ static var customizable: [Activity]`（`allCases` 去 idle 依 priority 降序**推導**；另有 gate 釘具體序列） | — |
| `IconPalette` | AuraCore | 改 | `+ with(_:color:)`、`+ isDefault` | — |
| `LegendModel` | AuraCore | 新 | `LegendItem { activity, label, color }`；`items(for:)`（順序 = `Activity.customizable`）；`label(_:)` 窮盡 switch；`IconPalette.with/isDefault` 擴充也放本檔 | IconPalette |
| `PanelModel` | AuraCore | 新（獨立檔） | 傳給 view 的**值**：`title, rows, palette, legend, isDefaultPalette`；`make(icon:sessions:palette:now:)`。（`PanelViewModel` 是純函式集合，`PanelModel` 是它的產出打包） | PanelViewModel、LegendModel |
| `PaletteStore` | App | 新 | `@MainActor`；`init(defaults:)`：讀 `Activity.customizable` 四個 key → overrides → `decode`（**只讀四 key**；「idle 不可覆寫」是 `decode` 純函式層的防禦，由 AuraCore gate 守，store 層不另加儀器——review r2 I5 選 (b)）；`set`／`reset` → 更新記憶體 → **先** `onChange?` **再** `persist()`（`encode` 出來的寫、customizable 中不在其中的 remove） | PaletteCodec |
| `ColorPickerCoordinator` | App | 新 | `init` 時**註冊一次** `NSWindow.willCloseNotification`（**`object: nil` ＋ block 內過濾 `note.object is NSColorPanel`**——傳 `.shared` 當 object 會在 launch 同步區建出整個色板 UI，review-t0203 I2 實測 +120 ms、RSS +~17 MB；`[weak self]`，保存 token）→ `activeActivity = nil`、`onEnd?()`；`pick(_ activity:, current:, present: Bool = true)`：`showsAlpha = false`、`isContinuous = true`、**`hidesOnDeactivate = false`**、`color`、`setTarget/action`、`present` 才 `orderFront`；`@objc changeColor(_ sender: Any?)`：`sender as? NSColorPanel`、`activeActivity` 非 nil、`rgba(from:)` 非 nil 三關都過才 `onPick?(activity, rgba)`；`static rgba(from: NSColor) -> RGBA?`；`detach()` → `setTarget(nil)` + `setAction(nil)` + `activeActivity = nil` + `removeObserver(token)`（`applicationWillTerminate` 也呼叫）；internal `endCount`（gate 觀測） | AppKit |
| `AnimationDriver` | App | 改 | `+ setPalette(_:)` → 存 → `reschedule()`；`reschedule` 用 `appearance(for: icon, palette:, reduceMotion:)`（`onFrame` 是**同步**呼叫） | IconPalette |
| `IconRendering` | App | 改 | `setPanel(_ model: PanelModel)`；`+ onPickColor: ((Activity) -> Void)?`、`+ onResetColors: (() -> Void)?`、`+ setPopoverPinned(_ pinned: Bool)` | PanelModel |
| `StatusItemController` | App | 改 | 實作上述；`setPanel`：首次建 `NSHostingController`，之後**先比較** `model == lastModel`（相同跳過）→ `rootView = PanelView(...)` → `lastModel = model`；`hostingController.sizingOptions = [.preferredContentSize]` 於建立時設一次；`togglePopover`（**internal**，可被測試呼叫；離屏 `show` 靜默無效、`isShown` 恆 false，副作用照樣發生）開／關時皆 `setPopoverPinned(false)`（第二條解除路徑）；internal：`popoverBehavior`、`panelOnPick`／`panelOnReset`、`hostingController`、`rootViewAssignments: Int`（**instrumentation**，非產品需求，算進 LOC） | — |
| `PanelView` / `PanelRowView` | App | 改 | `PanelView(model:, onPick:, onReset:)`；底部掛 `LegendRowView`；列色點 `Color(rgba: model.palette[row.activity])` | PanelModel |
| `LegendRowView` | App | 新 | 四個 `LegendDot`（10pt 圓、`.frame(20×20).contentShape(Rectangle())`、`.onTapGesture`、`.onHover` push/pop `NSCursor.pointingHand`、`.help`）＋標籤；「重設」`Button`（`.borderless`，`disabled(isDefaultPalette)`）；提示行 | — |
| `ColorBridge` | App | 新（小） | `Color(rgba:)`、`NSColor(rgba:)`（`sRGB`） | — |
| `AppDelegate` | App | 改 | `init(root:, livenessInterval:, defaults: UserDefaults = .standard, makeRenderer:)`；建 `store`、`coordinator`（internal `colorCoordinator`、`paletteStore` 供 smoke 觀測）；**同步區內**（任何 icon 交付之前）`driver.setPalette(store.palette)`；`store.onChange → driver.setPalette + refreshPanel`；`status.onPickColor → coordinator.pick + status.setPopoverPinned(true)`；`coordinator.onPick → applyColor`；`coordinator.onEnd → status.setPopoverPinned(false)`；`status.onResetColors → resetColors()`；`internal func applyColor(_:for:)`／`resetColors()` | PaletteStore、ColorPickerCoordinator |

**設計選擇**
1. **編解碼在 AuraCore、I/O 在 App**：`decode/encode` 純函式可在 AuraCore 對抗式測試；`PaletteStore` 只做 `UserDefaults` 搬運。`PaletteStore` 只讀 `customizable` 四個 key；「idle 不可覆寫」是 `decode` 純函式層的防禦（AuraCore gate `decodeFallsBackPerKey`），store 層不加掃描與儀器（review r2 I5 選 (b)：零使用者可見差異，R9 先砍）。`persist()` 走 `encode`，讓 `encode` 有生產消費者（review r1 I7）。
2. **先通知再落盤**：`set()` 先 `onChange`（icon 與面板即時）再 `persist()`。
3. **`PanelModel` 取代多參數**：`IconRendering.setPanel` 從 `(title, rows)` 變一個值；`Equatable` 讓 controller 能跳過無變化的更新（D-j）。
4. **改色期間釘住 popover（D-i）**：沒有它 R8 的回饋迴路在 idle 時不存在（review B5）。`hidesOnDeactivate = false` 讓 `willClose` 成為可靠出口（review r2 N4 實測：`orderOut` 不發 `willClose`），`togglePopover` 是第二條解除路徑。**離屏測不到真實行為**，只釘 `popoverBehavior`／`hidesOnDeactivate` 的切換；真機驗證寫成 §7 的三步驗收清單。**退路順序**（review r2 I4）：① `attachPopover` 時就固定 `.semitransient`（不依賴 shown 後改 behavior 能否生效；代價：切別的 app 面板留著）；② 最後才回 `.transient` 並把 B5 記回 known gap。

## 3. 資料模型

```swift
public enum PaletteCodec {
    public static func hex(_ c: RGBA) -> String            // "#0a84ff"（round 到 0…255，永遠小寫）
    public static func rgba(hex: String) -> RGBA?          // 驗長度／字元集後解析；a = 1
    public static func decode(overrides: [Activity: String]) -> IconPalette
    public static func encode(_ p: IconPalette) -> [Activity: String]
}
extension Activity { public static var customizable: [Activity] }      // [.error, .waiting, .working, .done]
extension IconPalette { public func with(_ a: Activity, color: RGBA) -> IconPalette; public var isDefault: Bool }
public struct LegendItem: Equatable, Sendable, Identifiable { activity, label, color; id = activity }
public enum LegendModel { public static func items(for: IconPalette) -> [LegendItem]; static func label(_: Activity) -> String }
public struct PanelModel: Equatable, Sendable {
    public let title: String; public let rows: [PanelRow]; public let palette: IconPalette
    public let legend: [LegendItem]; public let isDefaultPalette: Bool
    public static func make(icon: IconState, sessions: [SessionState], palette: IconPalette, now: Date = Date()) -> PanelModel
}
```
`UserDefaults`（domain `io.agentaura.app`）：至多四個 key `AgentAuraColor.{error,waiting,working,done}` = `"#rrggbb"`；`reset()` 全部 remove。R9 量法：`dictionaryRepresentation()` 中前綴命中 ≤ 4（測試斷言），不用 grep。

## 4. 核心技術

### 4.1 圖例列（R7）
| 參數 | 值 |
|---|---|
| 位置／可見 | 面板最底部，**永遠顯示**（rows 空時在「沒有活著的 session」下方；rows 非空時在 `ScrollView` 之外） |
| 內容 | 四組 `● 標籤`，順序 錯誤·等你·執行中·已完成；色點 10pt 圓佔 20pt；**整組可點**；顏色 = `palette[activity]`（a 視為 1） |
| 第二行 | `.secondary` 11pt「燈固定 8 顆，與 session 數無關 · 點色點可改顏色」；右側 `Button("重設")`（`.borderless`，10pt，`disabled(isDefaultPalette)`） |
| 互動 | tap → `onPick(activity)`；hover → `NSCursor.pointingHand.push()`／`NSCursor.pop()`；`.help("改「\(label)」的顏色")` |
| 高度 | 約 44pt；面板寬 380 不變 |

### 4.2 改色（R8）
1. tap 色點 → `PanelView.onPick(a)` → `StatusItemController.onPickColor?(a)` → `AppDelegate`：`status.setPopoverPinned(true)`；`coordinator.pick(a, current: store.palette[a])`。
2. `pick`：`NSColorPanel.shared` 設定（§2，含 `hidesOnDeactivate = false`）並 `orderFront`；記 `activeActivity`（`willClose` 觀察在 `init` 已註冊一次）。
3. 拖色 → `changeColor(sender)` 三關（sender 是 `NSColorPanel`／`activeActivity` 非 nil／sRGB 轉換成功）→ `onPick(a, rgba)` → `applyColor` → `store.set` → `onChange`（`driver.setPalette` 立刻重畫 icon；`refreshPanel` 立刻換 `rootView`，popover 釘住所以看得到圖例與列色點變）→ `persist()`。
4. 關色板 → `willClose` → `activeActivity = nil`、`onEnd` → `setPopoverPinned(false)`。第二條解除：使用者點燈條 `togglePopover` → 無條件 `setPopoverPinned(false)`（切到別的 app 再回來，面板不會卡在釘住）。
5. 「重設」→ `store.reset()`：`palette = .default` → `onChange` → `persist()`（四 key remove）。

### 4.3 啟動載入
`applicationDidFinishLaunching` **同步區**：`store = PaletteStore(defaults:)` → `driver.setPalette(store.palette)` → 接 callbacks → `graph.start()`。bootstrap 的 `onIconStateChange` 走 `Task { @MainActor }`，一定落在後一個 turn，所以 requirement 是「**在第一次 icon 交付之前**（同步區內）」——不是「在 `start()` 之前」（後者不可觀測，review B4）。

## 5. 錯誤處理
| 情況 | 處理 |
|---|---|
| `UserDefaults` 值缺／非字串／非 6 位 hex／8 位／`rgb()`／空／尾空白／非 ASCII／數 KB 長 | 該 key 落回預設；先驗長度與字元集再索引，**無 crash 面**；其他 key 不受影響 |
| `AgentAuraColor.idle` 出現 | store **不讀**它（只讀 customizable 四 key）；`decode` 仍忽略 idle（純函式層防禦，`decodeFallsBackPerKey` 守）；`reset()` 只 remove 四 key；`PaletteStore.set(_, for: .idle)` 直接忽略（無生產呼叫端，API 層防呆） |
| `hex()` 收到非有限值（NaN） | clamp 為 0 而非 `Int(nan)` trap（無可達路徑，防禦性） |
| `changeColor` sender 不是 `NSColorPanel`／`activeActivity` 為 nil（色板已關或 `pick` 前被系統呼叫）／色轉 sRGB 失敗（pattern／catalog） | 忽略該次；palette 不變（各有 gate） |
| popover 在釘住期間被系統關掉（例如螢幕鎖） | 無害；`willClose` 仍會解除釘住 |
| `onChange` 兩個消費者 | 各自獨立呼叫、持久化在最後（保本先於觀測） |

## 6. 測試策略

T01 先行（測試＋compile-only stub；禁 `fatalError`）。

**Harness**：沿用 `OffscreenRender`（sRGB `CGContext` + `displayIgnoringOpacity`）。SwiftUI 面板用 **`NSHostingView(rootView:)`** 設 frame 後走同一條 `render`（**不用 `ImageRenderer`**：實測它不渲 `ScrollView` 內容，review B1）。新增 helper `Bitmap.count(near color: RGBA, tolerance: 2/255) -> Int`。像素錨點：10pt 圓（20pt 命中區內）@2x 在 2/255 容差下 ≈ **276 px**、8pt 圓 ≈ 172 px（review r2 實測 NSHostingView 路徑）；錨點隨版面／命中區變動，門檻 200／120 刻意留 ≥38% 餘裕。fixture 一律經 `PanelViewModel.rows(from: [SessionState])`／`PanelModel.make` 取得（`PanelRow`／`PanelModel` 的 memberwise init 跨模組是 internal——**不加 public init、不 `@testable import AuraCore`**）。`popover.contentSize` 未顯示時恆 `(0,0)`，**不可**當觀測點；用 `preferredContentSize`／`view.fittingSize`。語意色依機器外觀解析（`DarkAqua` 下 `.red = #ff383c` 等）——**任何斷言不得依賴語意色**；「預設色 0 px」的交叉檢查改為「wild 四色各 ≥ 門檻」＋「用預設 palette 渲時 wild 色 0 px」（兩個 palette 對照，不碰語意色）。

| Gate | 層 | 守什麼 | Mutation（→ 指名測試幾秒內紅） |
|---|---|---|---|
| `hexRoundTrip` | AuraCore | customizable 四色＋每通道 0…255 step 17 的決定性掃描：`rgba(hex: hex(c))` 分量差 ≤ 1/255；`rgba(hex: "#FF9F0A") == rgba(hex: "#ff9f0a")`；`rgba(hex: "ff9f0a") != nil` | 只收小寫／少一位 → <1s |
| `hexRejectsGarbage`（對抗式） | AuraCore | `""`、`"#"`、`"#12345"`、`"#1234567"`、`"#ff9f0a80"`、`"#GGGGGG"`、`"rgb(1,2,3)"`、`"0a84ff "`、`"#ff9få"`（非 ASCII 六字元）、10 KB 字串 → 全 nil、不 crash | 放寬長度／跳過字元集 → <1s |
| `decodeFallsBackPerKey`（對抗式） | AuraCore | `{error: 合法, waiting: 垃圾, idle: 合法}` → error 新色、waiting 預設、**idle 預設**、其餘預設 | 移除 idle guard → <1s |
| `encodeOnlyNonDefault` | AuraCore | `encode(.default)` 空；改一色只含那 key；`decode(encode(p)) == p` | — |
| `customizableOrder` | AuraCore | `Activity.customizable == [.error, .waiting, .working, .done]`（釘具體序列，D-b 可觀測）且無 idle | 改序／手寫少一個 → <1s |
| `legendItemsFollowOrderAndLabelsTotal` | AuraCore | `items(for:)` 順序 = `customizable`；label 非空互異；色 = palette | 順序改 → <1s |
| `withChangesOnlyThatField` | AuraCore | `Mirror` 逐欄位只有目標變 | 改錯欄位 → <1s |
| `panelModelCarriesPalette` | AuraCore | `model.palette == palette`；legend 色 = palette；`isDefaultPalette == palette.isDefault`；rows/title 與 `PanelViewModel` 相同 | make 忽略 palette → <1s |
| `storeLoadsDefaultWhenEmpty` / `storeRoundTripsThroughRealDefaults` | App | suite `io.agentaura.tests.palette`（固定名、`.serialized`、每測 `removePersistentDomain`）；set → **新建第二個 store** 同 suite → 同色；key 名與 `#rrggbb` 值 | 寫錯 key → <1s |
| `storeResetRemovesKeys` | App | reset 後四 key `object(forKey:) == nil`；`dictionaryRepresentation()` 前綴命中 = 0 | — |
| `storeToleratesGarbageDefaults`（對抗式） | App | 事先寫垃圾字串、`Int`、`Data` 到四 key → 載入 = 預設、不 crash（idle 不可覆寫由 AuraCore `decodeFallsBackPerKey` 守，store 層不重複斷言——證不到的話不寫） | 容錯路徑刪除 → <1s |
| `storeNotifiesBeforePersisting` | App | `onChange` 內 `defaults.string(forKey:)` 仍是舊值 | 順序反 → <1s |
| `storeKeyBudget`（R9） | App | 改四色後 `dictionaryRepresentation()` 前綴命中 ≤ 4 | — |
| `colorPanelConversion` | App | `rgba(from: NSColor(srgbRed:…))` ≤ 1/255；`NSColor(patternImage:)` → nil；`pick(…, present: false)` 後 `showsAlpha == false`、**`hidesOnDeactivate == false`**、`color` ≈ current。teardown：`detach()` + `NSColorPanel.shared.orderOut(nil)` | showsAlpha 沒關／hidesOnDeactivate 沒關 → <1s |
| `willCloseObservedOnce`（review r2 I1） | App | 連呼兩次 `pick(present: false)` 後 post 一次 `willClose`（object = shared panel）→ `endCount == 1`；`detach()` 後再 post → 不增 | 在 `pick` 裡重複註冊 → <1s |
| `changeColorGuards`（對抗式，review I4） | App | 設 `onPick` spy：(a) 不 `pick` 直接 `changeColor(NSColorPanel.shared)` → 不呼叫；(c) `pick`（合法色、target 已掛）後 `changeColor("not a panel")` → 不呼叫；(b) `color = NSColor(patternImage:)`（setter 自動觸發 action）＋顯式 `changeColor` → 不呼叫；(d) `pick` 後設合法色 → setter 自動觸發**恰好一次**且 activity／顏色對（`NSColorPanel.color` 的 setter 在 target 已掛時同步呼叫 action——實測）；(e) 設 alpha 0.5 的色 → `onPick` 的 `a == 1` | 刪任一 guard／`rgba(from:)` 不強制 a=1 → <1s |
| **`paletteChangeReachesIcon`**（smoke） | App（`PaletteWiringSmokeTests.swift` 新檔） | 真 `AppDelegate(root:, defaults: suite, makeRenderer: spy)`；bootstrap waiting session；`applyColor(wild, for: .waiting)` → **同步**：spy 最後 `apply` 的 `appearance.color == wild`；spy 最後 `setPanel` 的 `model.palette[.waiting] == wild`、`legend` 對應色 == wild、`isDefaultPalette == false` | 刪 `driver.setPalette` 呼叫 → <2s；刪 `refreshPanel` → <2s |
| **`pickerChainIsWired`**（smoke，review B2／r2 N1） | App | (1) `#expect(spy.onPickColor != nil)`；(2) `spy.onPickColor!(.waiting)` → `NSColorPanel.shared.color`（sRGB）≈ `store.palette[.waiting]` 且 spy 收到 `setPopoverPinned(true)`（證 delegate→coordinator 兩跳）；(3) **驅動 coordinator 真的產色**：`NSColorPanel.shared.color = NSColor(rgba: wild)` → `delegate.colorCoordinator.changeColor(NSColorPanel.shared)` → `delegate.paletteStore.palette[.waiting] == wild`（證 `coordinator.onPick → applyColor` 接上；icon 半句不寫——沒 bootstrap 時 icon 是 idle 色會紅在錯的理由，那條接縫已由 `paletteChangeReachesIcon` 證）；(4) post `willClose` → spy 收到 `setPopoverPinned(false)`。每段獨立失敗訊息 | 刪 `status.onPickColor =` → (1) 紅；刪 `coordinator.onPick =` → (3) 紅；刪 `onEnd` 接線 → (4) 紅；各 <2s |
| `resetReachesIconAndDefaults`（smoke，獨立） | App | `applyColor(wild)` 後 `spy.onResetColors!()` → spy 色回預設、`isDefaultPalette == true`、suite 四 key 皆 nil | 刪 `status.onResetColors =` → <2s |
| `controllerForwardsPanelCallbacks` | App | 真 `StatusItemController`：`attachPopover()` 後 `popoverBehavior == .transient`（初始值，避免 pinned(false) 只是巧合）；設 `onPickColor` spy → `controller.panelOnPick(.error)` → spy 收到 `.error`；`panelOnReset()` → `onResetColors` 被呼叫；`setPopoverPinned(true)` → `.semitransient`、`false` → `.transient`；**第二條解除路徑**：`setPopoverPinned(true)` → `controller.togglePopover()` → `popoverBehavior == .transient` | 轉發漏接／刪掉 toggle 內的解除 → <1s |
| **`persistedColorAppliesOnFirstFrame`**（smoke） | App | suite 預寫 `AgentAuraColor.error = wild`；啟動；bootstrap error session → spy **第一次**收到 error 的 appearance 就是 wild | `setPalette` 移進 `onIconStateChange` 的 `Task` 內／延到 `store.onChange` 才第一次呼叫 → <2s |
| `legendAlwaysPresent` | App smoke | rows 空與非空：每次 `setPanel` 的 `legend.count == 4`、順序 = customizable | rows 空時省略 legend → <2s |
| **`legendDotsUsePalette`**（像素，對抗式） | App | `NSHostingView(PanelView(model))` 380 寬，**rows 空與非空各渲一次**；wild 四色各 ≥ 200 px（10pt 圓 ≈ 276）；改用 `.default` palette 渲 → wild 四色 0 px | `LegendDot` 寫死色 → <2s |
| `rowDotsUsePalette`（像素） | App | 渲 **單列** `PanelRowView(row:, palette:)`（不含 legend）四態各一次：wild 色 ≥ 120 px（8pt 圓 ≈ 172）；`.default` 渲 → wild 0 px | `PanelRowView` 保留舊 switch → <2s |
| `hostingControllerIsReused`（review r2 N2/N3 補正向證人） | App | 真 controller：`setPanel(m1)`（1 列）→ `setPanel(m2)`（3 列）：同一 `hostingController` 實例、`rootViewAssignments` **+1**、`preferredContentSize.height` **變大**；再 `setPanel(m1)`（1 列）→ 高度**變小**（實測 `sizingOptions` 下 114→206→114）；`setPanel(m1)` 再一次 → `rootViewAssignments` 不增。「永遠跳過」在第二步紅；手動 `preferredContentSize = fittingSize` 的寫法在「變大」就紅（被第一個高度釘住）——**紅了修產品取值方式，不得把斷言改 `>=` 或刪除** | 每次重建 → 實例斷言紅；永遠跳過 → +1 紅；刪 `sizingOptions` → 高度恆 (0,0) 紅；各 <1s |
| `evidenceRenderer`（env gate） | App | `AURA_RENDER_EVIDENCE=1`：面板（預設 palette × {空, 三列}、自訂 palette × 三列）用 `NSHostingView` 路徑 @2x → `docs/evidence/change2/*.png` + `index.html`；冪等；註明產圖機器外觀 | — |
| 既有全部 gate | — | 繼續綠 | — |

**已知不可測（寫進 §10 與最終報告）**：SwiftUI tap → `onPick` 這最後一跳離屏無法觸發；`.semitransient` 與系統色板共存的真實行為離屏無法驗證；**popover 在測試行程無法顯示**（`show(...)` 後 `isShown` 恆 false）——所以 `togglePopover` 的 gate 只驗 `behavior`，不得寫依賴 `isShown` 的 gate。兩者由使用者實機測試（本 change 的交付就是「可測試版本」）。

**test-edit scrutiny 預告**：`IconRendering` 增三個成員、`setPanel` 簽章改 → `SpyRenderer` 對齊（`panels: [PanelModel]`、新增 `pinned: [Bool]`）；`grep -rn "panels" Tests/` 目前零斷言讀它（review I6 已確認），無弱化。`PanelRowView.color(_:)` 刪除——`Tests/` 零命中。

## 7. DoD（可量測）
| 項目 | 門檻 | 量法 |
|---|---|---|
| 圖例常駐 | 任何 `setPanel` 的 legend 都是 4 項；像素上 rows 空／非空都畫出四點 | `legendAlwaysPresent`、`legendDotsUsePalette` |
| 改色即時 | `applyColor` 後**同步**收到新色（icon 與 panel model） | `paletteChangeReachesIcon` |
| 入口接線 | 面板 tap 後的整條鏈到 `NSColorPanel` 為止有 gate | `pickerChainIsWired`、`controllerForwardsPanelCallbacks` |
| 持久化 | 真 suite 跨 store 實例 round trip；reset 清 key；首格用持久色 | `storeRoundTrips…`、`persistedColorAppliesOnFirstFrame` |
| 容錯 | 10 種垃圾值全落回預設、不 crash；三個 `changeColor` guard 各有測試 | `hexRejectsGarbage`、`storeToleratesGarbageDefaults`、`changeColorGuards` |
| 面板真的用 palette | 掃色兩個 palette 對照（wild ≥ 門檻、預設渲時 wild 0） | `legendDotsUsePalette`、`rowDotsUsePalette` |
| R9 | 零新依賴／target；**`Sources/` 淨增 ≤ 520 行**（基準 1806；§8.1 逐檔加總 **491** ＋ r3 補的 ~10 行生產碼＋儀器；組成 = 三個新 AuraCore 型別＋四個新 App 單元＋四檔接線——功能面積，不是膨脹；每檔 ≤ 200）。**若超過 520：先砍 instrumentation（`rootViewAssignments`）與非必要碼，不改門檻**；`UserDefaults` 前綴 key ≤ 4；無自建視窗／設定頁 | `dump-package`、`wc -l`、`storeKeyBudget`、code review |
| 執行檔 | < +150 KB vs 1,155,552 | `ls -l` |
| AuraCore 覆蓋率 | ≥ 90% | `llvm-cov` |
| CPU | idle／done ≤ 0.1%（隔離量測者 session） | `demo-sessions.sh` + `top` 60s |
| persona | 加權 ≥ 6.0；硬下限：P1 新手「30 秒內看懂四燈」≥ 5；P2「拖色時 icon 與（釘住的）面板即時一致」≥ 5——若 persona 判釘住不成立（無實機證據）→ 標「待使用者實測」而非 no-go | persona-tester：面板渲染圖 + 程式碼讀 + 使用者實測回饋（若有） |
| **使用者實測清單**（離屏不可驗的三件事，T06 交付、最終報告附） | 三步皆有「操作 → 預期 → 實際」欄位 | ① 有 session 在跑時開面板 → 點「等你」色點 → **預期**：系統色板出現、面板**仍在**；② 拖色 → **預期**：icon（若當前狀態就是 waiting）與面板圖例、列色點**同時**變；③ 關色板 → 點面板外 → **預期**：面板關閉；切到別的 app 再回來 → 面板不會卡住 |

## 8. 檔案佈局與回寫

### 8.1 檔案（估行）
```
Sources/AuraCore/PaletteCodec.swift               新  ~70
Sources/AuraCore/LegendModel.swift                新  ~55（LegendItem/LegendModel + IconPalette.with/isDefault）
Sources/AuraCore/Activity.swift                   改  +8（customizable）
Sources/AuraCore/PanelModel.swift                 新  ~40
Sources/AgentAuraApp/PaletteStore.swift           新  ~50（只讀四 key、persist=encode）
Sources/AgentAuraApp/ColorPickerCoordinator.swift 新  ~80（init 註冊 willClose、hidesOnDeactivate、endCount、detach）
Sources/AgentAuraApp/LegendRowView.swift          新  ~75
Sources/AgentAuraApp/ColorBridge.swift            新  ~15
Sources/AgentAuraApp/PanelView.swift              改  +8（吃 model、掛 legend、色點吃 palette、刪 color switch −9）
Sources/AgentAuraApp/StatusItemController.swift   改  +50（callbacks、hosting 重用＋preferredContentSize、pinned 雙路徑、rootViewAssignments 儀器）
Sources/AgentAuraApp/AnimationDriver.swift        改  +8
Sources/AgentAuraApp/AppDelegate.swift            改  +45
                                                  合計 ≈ +500（門檻 520）
Tests/AuraCoreTests/PaletteCodecTests.swift、LegendModelTests.swift              新
Tests/AgentAuraAppTests/PaletteStoreTests.swift、ColorPickerTests.swift、PanelPixelTests.swift、PaletteWiringSmokeTests.swift 新
Tests/AgentAuraAppTests/OffscreenRender.swift     改  + count(near:)、NSHostingView 便捷
Tests/AgentAuraAppTests/CompositionSmokeTests.swift 改  SpyRenderer 對齊（僅簽章）
Tests/AgentAuraAppTests/EvidenceRenderer.swift    改  加面板證據（若逼近 300 行拆 PanelEvidenceRenderer.swift）
docs/evidence/change2/                            新
```

### 8.2 回寫（逐句）
| 位置 | 現句 | 改為 |
|---|---|---|
| 正典 §3.7 首段末 | — | 加「**面板底部常駐圖例列**：四態色點＋標籤（錯誤·等你·執行中·已完成）與提示「燈固定 8 顆，與 session 數無關 · 點色點可改顏色」；點色點以系統色板改色、icon 即時生效、面板釘住期間圖例與列色點即時更新、持久化於 `UserDefaults`；「重設」常駐、預設時 disabled（Change 2）」 |
| 正典 §3.7 | 「打開面板即 acknowledge（D2）。語意明確定義為…」 | 前面加一句「面板內的圖例互動不影響 acknowledge 語意（開啟瞬間已確認）」（2026-09-10 S1-3 修正後，時點改為關閉，見正典 §3.7） |
| 正典 §0 D2 理由句 | 「scope 是只看，面板是唯一互動」 | 改「scope 是只看，面板是唯一互動面；Change 2 起面板內含改色入口，仍不觸碰 agent」 |
| 正典 §0 R7／R8 列 | 「Change 2 落地」 | 「已由 Change 2 `panel-legend-palette` 落地」 |
| 正典 §3.7 | 「每列顯示：專案名…」 | 加「列色點與圖例色點皆取自 `IconPalette`，與選單列同一份資料」 |
| m4 DoD 帳本 F-01 列 | 「Change 2 自選色的驗收條件：waiting 與 done 的亮度要拉開」 | 「Change 2 提供自選色**能力**（可把兩者拉開），不做 UI 檢查；F-01 仍為 known gap」 |
| CLAUDE.md | Project 狀態；Tier 1 清單 | 狀態更新；Tier 1 加 `Sources/AgentAuraApp/LegendRowView.swift`、`PaletteStore.swift`、`ColorPickerCoordinator.swift` |
| README | 狀態段 | 同步；加一段「改顏色」使用說明 |

## 9. Persona Impact
- **新手（R7）**：第一次開面板就看到四燈意思＋「8 顆是一體」；不用讀 README。
- **客製化使用者（R8）**：藍色不夠亮的人能自己調；色弱／reduceMotion 使用者能把 waiting 與 done 拉開（能力，非強制）；改色時面板釘住、icon 即時——但 icon 只顯示**當前聚合狀態**的顏色：沒有 session（idle）時改任何一色 icon 都不會變，釘住的面板圖例與列色點會變。
- **極簡使用者**：面板多兩行；選單列不變；沒有自建視窗、新選單；「重設」常駐但 disabled 時是灰字。
- **既有使用者**：無遷移；沒改過色的人看到的顏色與 Change 1 完全相同（`decode` 空 = `.default`，有 gate）。

## 10. 風險
| 風險 | 緩解 |
|---|---|
| `.semitransient` 釘住期間 popover 對其他互動的真實行為（離屏不可驗） | 只在色板開著時釘住，`willClose`＋`togglePopover` 兩條解除；`hidesOnDeactivate = false`；使用者實機三步清單（§7）。退路①：`attachPopover` 時固定 `.semitransient`（不依賴 shown 後改 behavior）；退路②：回 `.transient` 並把 B5 記回 known gap |
| SwiftUI tap → `onPick` 最後一跳無 gate | 前面每一跳都有 gate；使用者實機點一次 |
| 使用者選底板同色 `#141416` → 燈消失 | 不擋（R9）；「重設」一鍵救回；known gap |
| 語意色隨外觀變 → 像素 gate 不得依賴語意色 | 兩個 palette 對照法；evidence 註明產圖外觀 |
| PR #4 squash 後 rebase 衝突 | 已 rebase（基底樹相同，無衝突）；本 change 不動 `LEDStripView` |
| 拖色每秒數十次 `onChange` | hosting controller 重用＋`PanelModel` 相等跳過；`persist()` 每次寫四個字串（`UserDefaults` 是記憶體快取，寫盤延後）——可接受，記錄 |
| `LegendRowView` 標籤「等你」對新手是否直覺 | persona 打分；替代「等待批准」多 2 字，若 P1 < 5 改之 |
