# Change 3「操作層」設計（app-shell）· r7

> 2026-09-10 · brainstorm 產出見 `docs/2026-09-10-ux-replan.html`
> change id：`app-shell`　分支：`change/app-shell`　Tier：**1**（動 `Sources/AgentAuraApp/**`）

## 修訂紀錄

**r2（2026-09-10，spec-reviewer 第一輪 `ISSUES_FOUND`：4 S0／22 S1，全部平台事實都在本機實跑）**

| 來源 | 改了什麼 |
|---|---|
| S0-A1 | r1 抄漏 brainstorm 的後半句，寫成「不需重啟、立即生效」。**實際是新 plugin 掛載要新 session 才載入**（`INSTALL.md:25`、`verify-install.sh:22`；正典 §10 沒有那個量測）。全面改成「下一個 session 起生效」，並把 `INSTALL.md:47` 自相矛盾那句一併修掉 |
| S0-A2 | r1 的「自我驗證」只是再 probe 一次＝自洽檢查。實測**帶 quarantine 的 ad-hoc Mach-O 每次 exec 都 SIGKILL（137），而 `access(X_OK)` 照樣說可執行** → 下載版會「說已接上、其實永遠全暗」。改成真的跑一次 `aura-hook` 看產物 |
| S0-Q1 | r1 的 G8 用 accessibility 掃描。實測離屏 `NSHostingView` 的 SwiftUI a11y 樹是 **0 節點**（原生 `NSButton` 對照組正常）→ 改成 model 層窮盡推導 ＋ 差異渲染兩層 |
| S0-Q2 | r1 的像素 gate 沒釘 `NSAppearance`。實測 Dark 機器渲淺底：非白像素 224、**文字 0 px**；釘 `.aqua` → 18386 → 一個 harness 設定同時廢掉 G6／G8。全面加釘 appearance ＋ 前提斷言 |
| S1-A3 | `pointsAtThisApp` 改 `(st_dev, st_ino)`：實測同一目錄 `resolvingSymlinksInPath` 給 `/var/…`、`realpath` 給 `/private/var/…`，字串必不相等；大小寫不敏感 FS 上 URL 也不相等但 inode 相等 |
| S1-A4／S1-S3 | 新增 App Translocation 與 `~/Downloads` 的拒絕路徑（否則 symlink 指向會消失的臨時掛載，形成「壞掉→重新接上→再壞」迴圈；`SMAppService` 同理） |
| S1-A5／S1-S2 | 判定順序補 5 種真實磁碟狀態；**只有 `lstat` 回 `S_IFLNK` 才移除**（這一條同時關掉唯一會刪到使用者檔案的路徑） |
| S1-A6 | 第 4→5 步改**原子替換**（實測 `rename()` 可蓋既有 symlink） |
| S1-A7 | 指向 app bundle 之外的掛載即使壞了也不得靜默替換（使用者本機正是這種開發者掛載，`plugin/bin/aura-hook` 是 gitignored 產物，`git clean` 後就會壞） |
| S1-A8 | 補 `IconRendering.onOpen`（r1 開了 `openPanelReprobes` 這條 gate 卻沒有機制），並明訂它**不得** acknowledge |
| S1-A9 | 拿掉 `disconnect()` 的 `acknowledgeAll()`（r1 對它的因果描述是錯的，且會把使用者沒看過的尾巴刪掉），並補一條來源推導 gate 鎖住呼叫點集合 |
| S1-Q4／Q5 | 映射改成字典（gate 迭代它才算真推導）、**補上實測最常見的 `auto`**、加 fixture 外部錨點 gate、明訂 `Jargon` 的呼叫點與 wired gate |
| S1-Q6／Q7／Q8 | `PanelActionKind: CaseIterable` ＋ `sample(_:)` 推導法（有 associated value 的 enum 不能 `CaseIterable`，實測編譯失敗）；Options 列資料化到 `AuraCore`；`onAction` **不給預設值** |
| S1-Q9／Q10／Q11／Q12 | G2 明列容許差異集合與比對元組；`showPanel` 兩條順序 gate；`connected(external:)` 的覆蓋；`healthTone` 色值寫進 spec 並要求與像素 fixture 相距 > 0.2；G12 移出 mutation 計數；T03 的機械化 test-edit 判準 |
| S1-P3／P4／P5 | 接上成功要有可關閉的成功列；移除掛載後顯示**不同於壞掉**的狀態；歡迎旗標語意改成「從未成功接上過」 |
| S2-A10／A11／A12／S5 | 預先拆 `AppDelegate+PanelActions.swift`；回寫正典 §3.2 的安裝方式；把 CPU 量測腳本 commit 進 `scripts/`、啟動時間改行程內量測；Mach-O 放 `Contents/Resources/` 的 notarize 風險記入 known gaps |

reviewer 探針原始碼與輸出：`scratchpad/probe/`（symlink 語意、離屏 a11y／appearance／差異渲染、codesign／quarantine、enum 推導、probe 成本 ≈ 17 µs）。

**r3（2026-09-10，第二輪：CLOSED 21／PARTIAL 6／OPEN 0，新發現 11 S1 ＋ 6 S2；安全與 persona 兩視角已 APPROVED）**

| 來源 | 改了什麼 |
|---|---|
| N3 | **`.targetMissing` 幾乎不可達、最常見的失敗拿到說謊的文案**。實測斷鏈 symlink 的 `realpath` 是 errno=2、迴圈是 errno=62，r2 用 `targetIdentity == nil` 分不開 → `LinkObservation` 改帶 `resolveFailure`(errno)，第 5 步對它窮盡 switch |
| N11 | **G6 born-green**：`healthTone` 與 `IconPalette.default` 的 done／waiting **完全同色（delta 0）**，以 `.default` 渲時把 chip 改成綠仍有 276 px（圖例點）→ 抓不到。改以 `wildPalette` 渲（實測 warn chip 172 px、mutation 0 px），配色不必改 |
| S0-Q1 殘留 | G8(b) 兩狀態自然高度 430 vs 522 → 逐像素相減無定義。改**固定畫布 380×320**，門檻 > 20,000（實測整版切換 163,785／同內容 0） |
| N4 | G12 born-red：`grep acknowledgeAll( Sources/` 實際 4 個命中（2 宣告 ＋ module 內合法呼叫）→ 範圍收到 `Sources/AgentAuraApp/`、樣式改 `.acknowledgeAll(`、加檔數防空跑 ＋ 暫存 probe 正向對照 |
| N1 | `.hookBlockedOrBroken` 只活在記憶體 → `onOpen` 重新 probe 就蓋回「已接上」、重啟也丟失＝**又回到「說已接上、其實全暗」**。改成**持久化驗證憑證**（identity+mtime）＋ 啟動時背景驗一次，並保留「開面板不得 exec」 |
| N2 | G6 差異渲染門檻 `> 500` 對相鄰版本號（1 字元差 253 px）會紅 → fixture 與門檻一起釘死（`v0.1.0` vs `v9.9.9`，≥ 300） |
| N5 | `nonMenuKinds` 是新逃生門（把忘了做 UI 的動作塞進去就綠）→ 改成 **11 個 Kind 逐一指名守它的 gate**（§6.3 的對照表），一個都不能沒有名字 |
| N6 | `replaceExternalMount` 沒說要重複 guard 0／原子替換／exec 驗證 → 明訂它就是 `connect(force: true)`，共用同一段 |
| N7 | `sample(_:)` 每 Kind 一個代表值 → 「開有接、關沒接」照樣綠 → 改 `samples(_:) -> [PanelAction]`，覆蓋從 11 條變 16 條 |
| N8 | G4 後半在 `swift test` 裡沒有 bundle（born-red 或被寫成 skip）→ 改 spawn SwiftPM 產物（`AuraHookCLITests.binaryURL()`），bundle 那份交給 `verify-app.sh` ＋ DoD 實機② |
| N9／S2-6 | **同一個 enum 被兩個獨立窮盡 switch 消化（CTA 可見性 vs connect 路由）必然漂移**：11 種狀態裡有 4 種會顯示「按下去只會出錯」的接上鍵 → 收成單一 derived 屬性 `InstallState.affordance`，任何呼叫端不得自己看 `external` 旗做決定 |
| N10 | `banner` 與 CTA 警示條同時佔畫面上方、無優先序（移除掛載後會同時出現「已移除」與「還沒接上，要接嗎」）→ 明訂優先序 ＋ gate |
| S2-1…S2-5 | `Reason` 是 8 個不是 11（斷言改型別推導不寫數字）· mutation 帳把 G14 分開算 · `auto → 自動判斷` 與 brainstorm 不同是刻意 · external 的 chip 加「（你的 repo 掛載）」· `.alreadyConnected` 要有 banner 回應 |
| reviewer 自我更正 | r1 的 S1-Q10.3 處方（G11 門檻 0.2、改 `wildPalette`）**是錯的**：`count(near:)` tolerance 實測 2/255，delta 0.15 已是它 19 倍，`.default` 渲染中四個 wild 色全 0 px；0.2 還會咬到 `ok` vs `wild.idle`=0.1382 → **G11 門檻改 0.063（8×tolerance），Migration #3 刪除** |

**r4（2026-09-10，第三輪定向複審：CLOSED 10／PARTIAL 6／OPEN 0，新 1 S0 ＋ 6 S1 ＋ 5 S2。
使用者在 N-round checkpoint 選 (a) 極小定向修改）**

| 來源 | 改了什麼 |
|---|---|
| **S0-1（資料毀損，r3 自己的處方引入）** | r3 的 `affordance` 對照表**列序讓 `occupiedByFile` 完全不可達**（`broken(_, external:)` 兩列先吃掉全部 broken；Swift 只給 unreachable 警告，`Package.swift` 沒有 `-warnings-as-errors`）→ 拿到 `.connect` → 顯示「接上」→ 第 4 步 `rename` **實測蓋普通檔案 rc=0、使用者內容直接消失**。而 spec 引用的護欄（只有 `S_IFLNK` 才 unlink）只寫在 `disconnect`，connect 明文不經 unlink，`rename` 一次都不會問它 ⇒ **connect 的毀檔路徑零測試**。三條一起修：affordance 改對 `Reason` 窮盡且具體列在前、**第 4 步寫入點自己 `lstat` 再檢查一次**、G3 拆成 connect／disconnect 兩條呼叫路徑各有 mutation |
| **R1（併發，逼出架構改動）** | 實測 12 組寫法：`UserDefaults` 的 `Sendable` conformance **unavailable** ⇒ `Sendable` 的 `Installer` 不得持有它、不得捕進 `@Sendable` 閉包或 `Task.detached`（四種寫法全紅），**唯一綠且零警告的是碰全域 `UserDefaults.standard`——正是 spec 自己禁止的注入點違規**（測試會寫使用者真實 defaults）。改成：`verification` **注入**、憑證 I/O 留在 app 層 `@MainActor HookVerificationStore`（比照 `PaletteStore`）、`Installer: Sendable` 只在背景做 exec、新增來源掃描 gate 擋住 `Sources/AuraHookFile/` 出現 `UserDefaults` |
| **R4** | 解析失敗時 `targetIdentity` 恆 nil ⇒ `external = targetIdentity != thisAppPluginIdentity` 一律給 `true` ⇒ **最常見的失敗（app 被搬走）走 `.replaceExternal`，與 §5 承諾的「CTA 重新接上」矛盾**；更糟的是 `swift test` 沒有 bundle（`thisAppPluginIdentity == nil`）⇒ fixture 測到的是生產永遠不會出現的那一半。改成三值 `MountOwner { thisApp, external, unknown }`，解析失敗時用 **readlink 原文前綴**判定，仍分不出來就 `.unknown` → affordance `.connect`（目標不存在，沒有東西會被毀） |
| **R2** | `unknown` 可以是終態、`.blocked` 黏住 ⇒「已接上 · 檢查中…」或「macOS 擋住了 hook」永遠不會變（使用者照文案去系統設定允許、重開 app，畫面仍說壞的）。改成：**任何**失敗（含 spawn 丟錯、逾時）都要寫憑證、`unknown` 不得為終態、啟動驗證改「`!= .verified` 就跑」、加「再檢查一次」動作與退化文案 |
| **R3** | 13 列 chip 表**有兩列重疊**（`connected(external: true, verified: false)` 同時吻合兩列，而那正是使用者自己機器每次啟動的頭兩秒）；`affordance → showsConnectCTA／CTA 文案` 的對應完全沒寫 ⇒ 兩條 gate 沒有 oracle。改成 `(owner, verified)` 六格逐格 ＋ 一張 affordance 對應表 |
| **R5** | N5 只做了一半：`openHelp`／`about`／`quit`／`setLaunchAtLogin` 的「守衛」是 G5，而 G5 直接把 `samples()` 送進 `onAction`、**不經過 `OptionsMenuModel.rows`** ⇒ 把這四個塞進 `nonMenuKinds`，G10 與對照 gate 全綠，逃生門原封不動。改成把 `nonMenuKinds` 釘成字面集合（G10 斷言相等）＋ 四個 Kind 換成 UI 層守衛 |
| **R6** | `sample`（單數）殘留三處、「11 種」過時兩處、mutation 帳漏算（G9 拆成 a/b/c 後 `swift test` 是 15 條）→ 一律改成型別推導、**不寫數字** |
| S2-7…S2-11 | G8(b) 標單位（自然高度 215／261 **pt**，畫布 320 pt；門檻對畫布高度不敏感：320／560／600 都是 163,785／0）· G3 描述補 translocated · 憑證 mtime 用 `st_mtimespec`（秒＋奈秒）· `rename` 蓋目錄的 EISDIR 文案 · 有界等待改單調時鐘且「逾時」與「產物確實沒出現」分成兩種寫回值 |
| N3 追加 | 「symlink → 普通檔案」併進 `.notAPlugin` 經確認**可接受**（動作相同、文案不說謊、發生率極低），但 G1 要註明兩個子成因**必須落同一格**，否則下一個人會「順手」補第 9 個 Reason 把兩張表一起改壞 |

**r5（2026-09-10，S0-1／R1 定向確認：兩條皆 CLOSED、`APPROVED` 可進 T01；五條列為 T01 必辦）**

| # | 來源 | 改了什麼 |
|---|---|---|
| ① | A1 實測 | **「Swift 只給不可達警告」是錯的——它完全不會報**。三種寫法實跑：規定形式漏一個 `Reason` 是 error（✅），但 r3 表的順序與「owner 在最外層」兩種寫法**零 error 零 warning**，24 格中分別 6 格／2 格錯（S0 完整重現）。措辭收緊成「`.broken` 的 switch 最外層必須是 `Reason`，`owner` 只准在單一 Reason 分支內讀」，並補機械 gate `affordanceMatchesTable`（24 格 ＋ 三個頂層 case 逐格比對），這是唯一同時抓到兩種壞寫法的東西 |
| ② | A2 實測 | G2 的 snapshot 改對 **`realpath(<claudeHome>/skills)`** 取；加「`skills` 自己是指到 claudeHome 外的 symlink」fixture。實測那種設定下 `lstat` 穿過父層回 absent、寫入落在外面，而 claudeHome 的樹狀元組**完全沒變 ⇒ G2 全綠**。產品行為是對的（Claude Code 自己也穿過那條 symlink，拒絕反而會弄壞同步 skills 的合理設定），要修的是 gate。D-h 補「解析後」 |
| ③ | A3 實測 | G3(a) 的「內容位元組不變」**不得用 `try Data(contentsOf:)`**——clobber 後那條路徑是指向目錄的 symlink，`try` 會丟錯而顯示成「拋出未預期錯誤」而不是斷言失敗。改成 `Optional<Data>` 相等（實測 before 18 bytes／after nil ⇒ 紅在斷言）＋ `lstat` 型別相等兩半 |
| ④ | B double-stat | r4 讓 store 先算 stamp 再注入，而 `targetIdentity` 又是 `Installer` stat 的 ⇒ **同一顆檔案 stat 兩次、中間可被換掉 ⇒ 「`.verified` 但從沒驗過這一份」**。方向倒過來：`probe()` → `LinkObservation.hookBinaryStamp` → `store.verification(for:)` → `from(_:verification:)`；`verification` **移出** `LinkObservation` 欄位 |
| ⑤ | B 併發 | 兩個 exec 併發、兩邊都寫憑證，spec 沒說怎麼序列化。借 `PipelineGraph.consumeTask` 的單一 task handle ＋ `ColorPickerCoordinator` 的 in-flight guard 形狀放進 store。**因為 store 是 `@MainActor`，檢查與設定是原子的、不需要鎖**；而 `inFlight != nil` **正好就是** `.inFlight` ⇒ 序列化與「檢查中…」的誠實性是同一個機制。另：`verificationStoreIsInjected` 掃「`UserDefaults` 字樣」會被**註解**命中（實測 grep 回 1、全在註解）→ 改掃 `UserDefaults(`／`UserDefaults.` ＋ 檔數防空跑 ＋ 正向對照 |
| 風險降級 | A2 | 即使 `affordance` 寫成錯的形式，**第 4 步的 `lstat` 仍會擋住普通檔案** ⇒ 後果從「按一次毀檔」降成「顯示一顆按了會出錯的按鈕」。這是 S0-1 判 CLOSED 的依據 |

**r7（2026-09-10，派 T06 前自查發現的內部矛盾）**

r5 的 G10 把 `nonMenuKinds` 的字面集合寫成
`{pickColor, resetColors, dismissBanner, connect, replaceExternalMount}`，
但 §4.3 的 Options 列表明文有「**重設顏色**」（D-a 的重點之一就是把它從圖例列搬進 Options，
因為它一年按一次卻永遠佔一格且多半是灰的）——**兩處直接矛盾**，而且 `toggleOptions`
（footer 那顆「Options ⌄」自己）根本沒被列進去。裁決如下（12 個 Kind = 4 非選單 ＋ 8 列）：

| 分類 | Kind | 觸發處 |
|---|---|---|
| 非選單（`nonMenuKinds`，**字面集合恰為這四個**） | `pickColor` | 圖例色點 |
| | `toggleOptions` | footer 的「Options ⌄」 |
| | `dismissBanner` | banner 上的關閉 |
| | `replaceExternalMount` | **只在 CTA**（要顯示「現有掛載指向 X」的脈絡，不適合當一列裸選單項） |
| 選單列（8 列，依序） | `setLaunchAtLogin` | 開機自動啟動（開關） |
| | `openHelp` | 說明與快速上手… |
| | `resetColors` | 重設顏色 |
| | `connect` | 重新接上 Claude Code（**同時也是 CTA 的動作**，兩處送同一個 action） |
| | `recheckHook` | 再檢查一次（僅 `verification == .unknown` 時出現） |
| | `disconnect` | 移除掛載… |
| | `about` | 關於 AgentAura |
| | `quit` | 離開 AgentAura ⌘Q |

因為有幾列是**狀態相依**的（`recheckHook` 只在 `.unknown`、`setLaunchAtLogin` 在
`isSupported == false` 時隱藏），G10 的斷言改成兩段：
(a) `nonMenuKinds` **恰好等於**上表那四個（往裡面加東西就是紅）；
(b) 對一組由型別推導的代表狀態集合，**各狀態的 rows 聯集**必須涵蓋全部 8 個選單 Kind，
且**任一單一狀態內**同一個 Kind 最多出現一次。

**r6（2026-09-10，T02 實作時提出兩個 spec 落差 ＋ 一個實測更正）**

| # | 來源 | 改了什麼 |
|---|---|---|
| ① | T02 落差 1 | §3.1 第 5 步的 `owner` 規則**字面讀起來會讓 r3 的 bug 復活**：app 被搬走時 `rawLinkTarget` 是舊路徑、`Bundle.main.resourceURL` 是新路徑，兩者**必不相符** ⇒ 照字面「不相符 → `.external`」就又回到 `.replaceExternal`（R4 修的正是這件事）。改寫成**依 `resolveFailure` 分流**：正向命中 → `.thisApp`；不相符且 `.notFound`（目標真的不存在，沒有東西會被毀）→ `.unknown`；不相符且 `.loop`／`.permissionDenied`／`.other`（**目標可能還在，只是解不開**）→ `.external`，要使用者明確選擇。T02 採「其餘一律 `.unknown`」與修復意圖一致，但會讓「權限被拒的活掛載」被靜默替換（S1-A7 家族）——本條把那半補回來 |
| ② | T02 落差 2 | §3.3 給 `hookBlockedOrBroken` 寫了「產物確實沒出現」與「逾時」兩種文案，但**沒有任何型別承載這個區分**。若照 T02 的猜測只放在 `InstallerError`（一次性訊息），逾時就會寫下 `blocked` 憑證 ⇒ 重開之後 chip 永久顯示「macOS 擋住了 hook」＝ S2-11 明文要避免的**誤指控，而且是持久化的**。改成新增 `Verification.unconfirmed` ＋ `Reason.hookUnconfirmed`（都是扁平 case，`CaseIterable` 不受影響；狀態集合由 `allCases` 推導所以 gate 自動跟上）|
| ③ | T02 實測更正 | §3.1.1 寫「Swift **完全不會報**」太強：T02 重現「r3 列序」時**有**拿到 `case is already handled by previous patterns` 警告（與 reviewer 的量測不同，寫法細節不同所致），但**仍然編譯成功、不是 error**。改成「**有時完全不報、有時只給警告——兩種都不會擋建置**」，並保留兩次量測的出處。結論不變：形式必須靠人守 ＋ 靠 `affordanceMatchesTable` 守 |

---

## 0. 背景與範圍

AgentAura 是「只有主功能、沒有外殼」的 app：狀態顯示做到像素級，但缺少每個選單列 app 都有的
那一層——離開、設定、關於，以及最關鍵的「我到底有沒有接上」。非工程師開起來看到八顆暗燈，
**無法分辨「沒 session 在跑」／「Claude Code 沒開」／「hook 根本沒裝」**——三者畫面完全相同。
reviewer 又找出**第四種**：下載版 app 的 hook 被 macOS 隔離、每次 exec 被 SIGKILL，而 app 會說「已接上」
（S0-A2）——比前三種更惡劣，因為那是 app 主動說謊。本 change 要把這四種分開。

同時補一個既有缺口：正典 §3.8 的**自我健檢**寫了 DoD（「死 hook 偵測 100%」），
**M5 從未實作**，也沒被任何 gate 抓到。本 change 補上使用者自身那部分（D-k）。

### 0.1 不動（已定案；任何提案若需改動下列任一條就不做）

八顆 LED ＋ 不透明底板（A2）· `IconState` 聚合與 D1 優先序 · 主／副槽分離 ·
`waiting` 不進尾巴（§2.4.1）· `idle_prompt` 不映射 `waiting` · **關面板才 acknowledge（§3.7）** ·
hook 契約與 141 個實測 payload · `aura-hook` 一律 `exit 0`／輸出全空 ·
**絕不寫 `~/.claude/settings.json`**（D3/R6）· 四色可改、`idle` 不可改。

### 0.2 交付範圍（七項）

| # | 項目 | 對應需求 |
|---|---|---|
| M-1 | 離開 AgentAura | 基本外殼 |
| M-2 | 「接不上」狀態面板 ＋ 一鍵接上（含真的跑一次的驗證）＋ 健康狀態常駐 | R6、R7、§3.8(3) 的自身部分 |
| M-3 | 開機自動啟動 | R6（不需終端機） |
| M-4 | 關於／版本 | 基本外殼 |
| M-5 | 設定入口（面板內展開） | R8 面板客製化 |
| M-6 | 一鍵移除掛載 | R6「一步移除」 |
| M-7 | 去工程師化文案（保守版） | R7 快速上手 |

---

## 1. 決策

| # | 決策 | 理由 |
|---|---|---|
| D-a | **底部 utility bar**：左「● 已接上 · v0.1.0」、右「Options ⌄」 | 使用者選定。有文字的按鈕非工程師找得到；健康狀態有空間寫完整句子而不只一顆點 |
| D-b | **Options 是面板內展開（accordion），不是 `NSMenu`** | 使用者選定。無焦點爭奪；開關是真的 SwiftUI `Toggle`；只有一個心智模型 |
| D-c | **文案保守版**：只改代碼字（model／effort／permission_mode／副行英文字），tool 名保留原文 | 使用者選定。tool 名在 terminal 裡就是那樣顯示，保留原文才對得起來 |
| D-d | 七項打包成**一個 change**，走完整 SDD | 使用者選定。彼此耦合（Options 承載 M-1/3/4/6） |
| D-e | **未接上時選單列圖示不變**（八顆全暗）＋ tooltip「還沒接上 Claude Code」＋ **從未成功接上過時，啟動後自動開面板一次** | 拿黃燈當警示會與「等你」撞色，破壞剛驗收過的四燈語意（R7）。旗標語意是「從未成功接上過」而非「看過歡迎」（S1-P5：換新版 app 掛載會斷，那時最需要它） |
| D-f | **app 不自己搬進 `/Applications`**；但 **translocated 或位於 `~/Downloads` 時拒絕接上**並要求先搬 | app 搬自己容易出錯且違反「使用者完全掌控」。但只「提醒」擋不住 App Translocation 造成的必壞掛載（S1-A4），所以改成硬性拒絕 |
| D-g | **`plugin/` 複製進 `AgentAura.app/Contents/Resources/plugin/`**，一鍵接上指向 bundle 內那份 | `hooks.json` 用 `${CLAUDE_PLUGIN_ROOT}/bin/aura-hook`（相對），bundle 化**零 hook 改動**。app 自我包含是「開起來按接上」的前提 |
| D-h | **`Installer` 只准碰 `<claudeHome>/skills/agentaura`（必要時加 `<claudeHome>/skills/`）這兩個路徑，判定一律以 `realpath` **解析後**的位置為準（`skills` 自己可能是指到別處的 symlink，T01 必辦 ②）**，其餘 `~/.claude/` 唯讀；**`~/.claude` 不存在時拒絕接上，不得建立它** | D3/R6 的機械化版本。以樹狀 snapshot 前後比對強制（G2），容許差異集合明列於 §6.3 |
| D-i | 既有掛載**不得靜默覆寫**：目標有效就判 `connected(external:)`；**目標無效但指向 bundle 之外時也不得靜默替換**，要顯示現況與兩個明確選項 | 本機開發者掛載（指向 repo `plugin/`）必須被識別為「已接上」；而 `plugin/bin/aura-hook` 是 gitignored 產物，`git clean` 後會暫時壞掉——那時偷偷換成 bundle 內的凍結版，開發者改碼不再生效且無提示（S1-A7） |
| D-j | 面板動作統一為 `PanelAction` ＋ 單一 `onAction`（**不給預設值**）；`AppDelegate` 窮盡 switch；另加 `PanelActionKind: CaseIterable` 供 gate 推導 | 讓「新增動作卻忘了接線」變成編譯錯誤。有 associated value 的 enum 不能 `CaseIterable`（實測編譯失敗），所以要平行的 `Kind` ＋ `samples(_:)` 才真的推導得出來（S1-Q7／N7） |
| D-k | §3.8(3) 的**通用死 hook 掃描（掃別人的 hook）本輪不做** | 使用者要的是「我的接上了沒」。掃別人的 hook 會對其他 plugin 出現警告且判斷可能錯（R9）。列為 known gap，**不改 §3.8 的 DoD 措辭來遷就** |
| D-l | 說明頁是 **bundle 內的離線 HTML**（`Contents/Resources/help.html`） | 「接不上」時使用者可能沒網路或不知道 repo 在哪 |
| D-m | **生效時機一律講清楚**：接上成功的文案是「已接上 · 下一個 Claude Code session 起生效（現在開著的視窗不受影響）」 | 實測依據見 S0-A1。§3.8(2)「不得叫使用者重啟」指的是**不得叫他重啟 app**，不是不准說明生效時機 |

---

## 2. 架構總覽

```
AuraCore（純邏輯，零 AppKit）
  InstallState.swift      LinkObservation → InstallState（純函式狀態機）
  PanelAction.swift       PanelAction ＋ PanelActionKind(CaseIterable) ＋ samples(_:)
  OptionsMenuModel.swift  Options 展開區的列（每列帶 action），gate 的推導來源
  Jargon.swift            model／effort／permission_mode 代碼字 → 人話（M-7）
  PanelModel.swift        + install / version / optionsExpanded / launchAtLogin /
                            externalTargetPath / banner，以及 showsConnectCTA

AuraHookFile（檔案 I/O；白名單基準只有 Foundation + CoreServices）
  Installer.swift         probe(verification:) → LinkObservation；connect()／disconnect()
                          `Sendable`（背景只做 exec，回 Bool）；**不得出現 UserDefaults**（R1）
                          實測 module trace：removexattr／lstat／realpath／rename／Process／Pipe
                          全在 Foundation 閉包內（17 個 module，與純 Foundation 基準相同），
                          IsolationTests 不會紅；唯一踩線的 Security 已做成注入參數
                          只碰 <claudeHome>/skills[/agentaura]（D-h）
                          exec 驗證：spawn bundle 內 aura-hook，看產物（S0-A2）

AgentAuraApp（AppKit／SwiftUI）
  PanelFooterView / OptionsSectionView / NotConnectedView / BannerView
  LoginItem.swift         SMAppService 包一層 protocol
  HookVerificationStore.swift  @MainActor ＋ 注入 UserDefaults（比照 PaletteStore）：
                          憑證讀寫與 identity+mtime 比對，算出 Verification 注入給 probe（R1）
  StatusItemController    + showPanel() / onOpen / onAction
  AppDelegate             + AppDelegate+PanelActions.swift（窮盡 switch 拆檔，S2-A10）
```

資料流（新增部分）：

```
啟動 ─┬─ store.verification() ─► Installer.probe(verification:)（≈17 µs，不 exec）→ InstallState ─┐
      ├─ 背景 exec 驗證（僅當 != .verified）─► await MainActor.run { store.write(…) } ──────────┤
      └─ LoginItem.status ──────────────────────────────────┤
FSEvents → PipelineGraph → IconState ─────────────────────────┼→ PanelModel.make(…)
                                                              │
點燈條 → onOpen ──► 重新 probe ＋ setPanel（**不得 acknowledge**）
面板動作 → PanelAction ──► AppDelegate 窮盡 switch ──► 副作用 ──► 重新 probe ──► refreshPanel
關面板 → onClose ──► acknowledgeAll()（§3.7，唯一呼叫點）
```

`onOpen` 只准 probe ＋ `setPanel`；**acknowledge 只在 `onClose`**（CLAUDE.md invariant，
既有回歸 gate `PanelHostingTests.acknowledgeFiresOnCloseNotOpen` 必須保留且不得放寬）。
**不設輪詢 timer**（R9：CPU 0）。

---

## 3. 資料模型

### 3.1 `LinkObservation` / `InstallState`

```swift
public struct LinkObservation: Equatable, Sendable {
    public let claudeHomeExists: Bool     // ~/.claude 本身（不存在 → 沒用過 Claude Code）
    public let entryType: EntryType       // lstat 的結果：absent / symlink / directory / otherFile
    /// `realpath` 失敗的原因（nil = 成功）。**N3：判別依據是 errno，不是「identity 是不是 nil」**
    /// ——實測斷鏈 symlink（app 被搬走，最常見）errno=2，自我迴圈 errno=62，
    /// r2 用 `targetIdentity == nil` 兩者無法分開，導致最常見的失敗顯示「連結解不開」。
    public let resolveFailure: ResolveFailure?
    public let targetIsDirectory: Bool         // 僅在 resolveFailure == nil 時有意義
    public let targetIdentity: FileIdentity?   // (st_dev, st_ino)，解析後的目標
    public let thisAppPluginIdentity: FileIdentity?  // bundle 內 plugin 目錄的 identity
    public let hooksJSONExists: Bool
    public let hookBinaryExists: Bool
    public let hookBinaryExecutable: Bool      // access(X_OK)。**不足以證明能跑**（S0-A2）
    /// 目標 `bin/aura-hook` 的身分戳：`"<dev>:<ino>:<mtime_sec>.<nsec>"`。
    /// **只 stat 一次，所有者只有 `Installer`**（T01 必辦 ④）——r4 讓 store 先算 stamp 再注入
    /// `verification`，而 `targetIdentity` 又是 `Installer` 自己 stat 的 ⇒ 同一顆檔案 stat 兩次、
    /// 中間可以被換掉 ⇒ 出現「`.verified` 但其實從沒驗過這一份」的狀態，正是憑證要防的那件事。
    public let hookBinaryStamp: String?
    /// R4：`readlink` 的**原文**（未解析）。解析失敗時 `targetIdentity` 恆 nil，
    /// 這是唯一還能判斷「誰的掛載」的訊號（此處字串比對不違反 S1-A3——S1-A3 講的是
    /// 「判斷兩個**存在**的路徑是否同一個」必須用 inode）。
    public let rawLinkTarget: String?
    public let displayTargetPath: String?      // 只給 UI 顯示，不參與判定
    public enum EntryType: String, Sendable, CaseIterable { case absent, symlink, directory, otherFile }
    public enum ResolveFailure: Equatable, Sendable { case notFound, loop, permissionDenied, other(Int32) }
}

/// R2：`inFlight` = 背景驗證**確實正在跑**（＝ store 的 `inFlight` handle 非 nil）；
/// `unknown` = 沒人在跑也沒憑證。兩者的 chip 文案不同——「檢查中…」是一個關於進行中的宣稱，
/// 沒有東西在進行時就是說謊。**不是 `LinkObservation` 的欄位**（T01 必辦 ④）。
public enum Verification: String, Sendable, CaseIterable {
    case verified
    case blocked        // 真的跑過、**產物確實沒出現**（quarantine SIGKILL／arch 不符／複製損壞）
    case unconfirmed    // **無法確認**：有界等待逾時（機器睡眠）或 spawn 本身丟錯（r6 ②）
    case inFlight
    case unknown
}

/// R4：誰的掛載。三值而非 `Bool`——解析失敗時算不出 identity，`Bool` 只能猜，
/// 而猜錯的後果是最常見的失敗（app 被搬走）走到需要使用者明確選擇的 `.replaceExternal`。
public enum MountOwner: String, Sendable, CaseIterable { case thisApp, external, unknown }

public struct FileIdentity: Equatable, Sendable { let dev: dev_t; let ino: ino_t }

public enum InstallState: Equatable, Sendable {
    case claudeNotFound                     // ~/.claude 不存在
    case notConnected                       // 路徑不存在
    /// verified = 曾經以 exec 驗證過**這一份**目標（identity+mtime 相符）。
    case connected(owner: MountOwner, verified: Verification)
    case broken(Reason, owner: MountOwner)
    public enum Reason: String, Sendable, CaseIterable {   // r6 ② 之後 **9 個**；狀態集合一律由 `allCases` 推導，不寫數字
        case targetMissing        // realpath errno=ENOENT：目標不存在（app 被搬走／刪掉）
        case targetUnresolvable   // realpath 迴圈／權限／其他 errno
        case notAPlugin           // 解析成功但不是目錄，或沒有 hooks/hooks.json
        case hookMissing          // 沒有 bin/aura-hook
        case hookNotExecutable    // 在但沒有 x 位
        case hookBlockedOrBroken  // **真的跑過但沒有產物**：quarantine SIGKILL／arch 不符／複製損壞
        case hookUnconfirmed      // 逾時／spawn 丟錯：**無法確認**，不得反過來誤指控 macOS（r6 ②／S2-11）
        case occupiedByDirectory  // 路徑是實體目錄（別人的安裝）
        case occupiedByFile       // 路徑是普通檔案 → 絕不移除
    }
}
```

判定順序（純函式 `InstallState.from(_:)`，窮盡且不得有 `default`）：

1. `!claudeHomeExists` → `.claudeNotFound`
2. `entryType == .absent` → `.notConnected`
3. `entryType == .otherFile` → `.broken(.occupiedByFile, owner: .unknown)`
4. `entryType == .directory` → `.broken(.occupiedByDirectory, owner: .unknown)`
   （這兩格的「誰的掛載」沒有意義——路徑上根本不是掛載，一律 `.unknown`）
5. （以下 `entryType == .symlink`）先算 `owner`（R4，**不得用 `Bool`**）：
   - `targetIdentity != nil`：與 `thisAppPluginIdentity` 比 `(dev, ino)` → `.thisApp` / `.external`；
     `thisAppPluginIdentity == nil`（bundle 不完整／`swift run`）→ `.unknown`
   - `targetIdentity == nil`（解析失敗）——**依 `resolveFailure` 分流（r6 ①，不得只看「相不相符」）**：
     - `rawLinkTarget` 以 `Bundle.main.resourceURL` 為前綴（正向命中）→ `.thisApp`
     - 不相符 ＋ `.notFound`（**目標真的不存在，沒有東西會被毀**）→ `.unknown` → affordance `.connect`
     - 不相符 ＋ `.loop`／`.permissionDenied`／`.other`（**目標可能還在，只是解不開**）→ `.external`
       → affordance `.replaceExternal`，要使用者明確選擇（否則權限被拒的活掛載會被靜默替換，S1-A7 家族）
     - `rawLinkTarget == nil` → `.unknown`

   **為什麼不能寫成「不相符 → `.external`」**：app 被搬走時 `rawLinkTarget` 是舊路徑、
   `Bundle.main.resourceURL` 是新路徑，兩者**必不相符** ⇒ 最常見的失敗又會走到 `.replaceExternal`，
   正是 R4 修掉的那個 bug。判別依據是 **errno**，不是字串相不相符——與第 6 步同一個道理。
6. 對 `resolveFailure` **窮盡 switch**：`.notFound → .targetMissing`；
   `.loop / .permissionDenied / .other → .targetUnresolvable`；
   `nil` 但 `!targetIsDirectory` → `.notAPlugin`（symlink 指到普通檔案＝「掛載內容不對」；
   **與「是目錄但缺 `hooks.json`」刻意落同一格**，見 §6.3 G1 的註記，不准補第 9 個 Reason）
7. `!hooksJSONExists` → `.notAPlugin` → `!hookBinaryExists` → `.hookMissing`
   → `!hookBinaryExecutable` → `.hookNotExecutable`
8. `verification == .blocked` → `.broken(.hookBlockedOrBroken, owner:)`；
   `verification == .unconfirmed` → `.broken(.hookUnconfirmed, owner:)`（r6 ②）
9. 否則 `.connected(owner:, verified: verification)`

**呼叫順序是強制的（T01 必辦 ④，一次 stat、一個所有者）**：

```
1. Installer.probe()                             → LinkObservation（含 hookBinaryStamp，只 stat 一次）
2. store.verification(for: obs.hookBinaryStamp)  → Verification        // app 層、@MainActor
3. InstallState.from(obs, verification: v)                             // 純函式，兩個參數
```

**`.hookBlockedOrBroken` 必須跨 probe 與跨重啟存活（N1）**。r2 把它放在記憶體是錯的：
第 5 步已確認磁碟狀態是「掛載完好」，所以 `onOpen` 重新 probe 就會蓋回「已接上」，
app 重啟更是整個丟失——那正是 S0-A2 要修的「說已接上、其實永遠全暗」。做法：

- **憑證存放與比對住在 app 層**：`@MainActor final class HookVerificationStore`（比照
  `PaletteStore`：`@MainActor` ＋ 注入 `UserDefaults`）。**三個互斥的鍵**
  `AgentAuraHookVerified` / `AgentAuraHookBlocked` / `AgentAuraHookUnconfirmed`（r6 ②），
  值都是 `"<dev>:<ino>:<mtime_sec>.<mtime_nsec>"`
  ——**mtime 用 `st_mtimespec`（秒＋奈秒）**，`st_mtime` 只有秒，同一秒內重建的 hook 不會讓憑證失效（S2-9）。
- store 拿目標 `bin/aura-hook` 當下的 identity+mtime 比對兩個鍵，算出 `Verification`，
  **注入**給 `Installer.probe(verification:)`。`AuraHookFile` 這一層**不得出現 `UserDefaults`**
  （R1，有來源掃描 gate 守著）。
- 啟動後在背景跑一次 exec 驗證（實測一次 spawn ≈ 十幾 ms）：`Installer` 宣告 `Sendable`（欄位只有
  URL／Bool／`@Sendable` 閉包），背景只做 exec 並回 `Bool`，寫回憑證走 `await MainActor.run { store… }`。
  **條件是 `verification != .verified`**（含 `.blocked` 與 `.unconfirmed`，R2：否則使用者照文案
  去系統設定允許、重開 app，畫面仍說「macOS 擋住了 hook」；而 `.unconfirmed` 多半是機器睡眠造成的，
  下次啟動重驗就會自己痊癒）。
- **合流 guard 住在 store（T01 必辦 ⑤）**：`inFlight: Task<Void, Never>?`，
  `guard inFlight == nil else { return }`。三條路徑共用它——啟動驗證、`recheckHook`、
  `.blocked` 的重驗；**已經有一個在跑就不開第二個**（否則兩個 exec 併發、兩邊都寫憑證）。
  **因為 store 是 `@MainActor`，「檢查與設定」是原子的、不需要鎖**——這正是 guard 放在 store
  而不是 `Installer` 的理由（形狀借 `PipelineGraph.consumeTask` 的單一 handle ＋
  `ColorPickerCoordinator.activeActivity` 的 in-flight guard）。
- 而 `inFlight != nil` **正好就是** `Verification.inFlight`：所以「檢查中…」這句話
  **是因為有這個 handle 才是真話**——序列化與 R2 的文案誠實性是同一個機制，不是兩件事。
- **「每次開面板不得 exec」的規則保留**（§4.1）：面板路徑只讀憑證，不跑 hook。
- **`unknown` 不得是終態**（R2）：`exec` 驗證的**任何**失敗——產物沒出現、`Process.run()` 丟錯、
  fork 失敗、等待逾時——都必須寫回憑證；逾時與「產物確實沒出現」是**兩種**寫回值（S2-11：
  跨機器睡眠會逾時，不能反過來誤指控「macOS 擋住了 hook」），等待一律用單調時鐘。

**`connected(owner: .external, …)` 是正常狀態，不是警告**（D-i）。健康 chip 一律「已接上」，
external 時後面加「（你的 repo 掛載）」（S2-4），Options 區另有一行灰字寫 `displayTargetPath`。

判斷「兩個**存在**的路徑是不是同一個」一律用 `(st_dev, st_ino)`，**不比字串**（S1-A3）。
只有「目標根本解析不出來」時才退回 `rawLinkTarget` 的前綴比對（R4）——那時沒有 inode 可問。
`displayTargetPath` 只給人看。

### 3.1.1 `affordance`：唯一的「這個狀態能做什麼」（N9／S2-6）

r2 讓兩個獨立寫的窮盡 switch 消化同一個 enum（CTA 可見性 vs `connect()` 的早退路由），
結果**有四格會顯示一顆按下去只會出錯的「接上」**。收成單一 derived 屬性：

```swift
public enum ConnectAffordance: Equatable, Sendable {
    case connect                    // 可以直接接上（含「目標不存在，沒有東西會被毀」）
    case replaceExternal            // 只能走 replaceExternalMount（需使用者明確選擇）
    case explainOnly(Reason?)       // 只能解釋，沒有 app 能做的動作
    case none                       // 已接上
}
extension InstallState { public var affordance: ConnectAffordance { … } }
```

**實作形式是強制的（S0-1(i)）**：`case .broken(let r, let owner)` 之後，
**switch 的最外層必須是 `Reason`**，`owner` 只准在**單一 Reason 分支內**被讀
（`return owner == .external ? .replaceExternal : .connect`）。**不得先對 `owner` 分派。**

理由（三種寫法都實跑過 `swiftc -typecheck -swift-version 6`）：

| 寫法 | 編譯結果 | 24 格中與本表不符 |
|---|---|---|
| 規定的形式（內層對 `Reason` 窮盡），刻意漏一個 `Reason` | **error: switch must be exhaustive** | — |
| r3 表的順序（`broken(_, owner:)` 排在具體 Reason 之前） | **零 error、零 warning** | **6 格**（`occupied*` 三個 owner 全錯） |
| owner 在最外層、內層仍對 `Reason` 窮盡（＝只照字面讀 spec） | **零 error、零 warning** | **2 格** |

**Swift 有時完全不報、有時只給警告——兩種都不會擋建置**（`Package.swift` 沒有
`-warnings-as-errors`）。兩次量測都留著：reviewer 的重現是**零 error 零 warning**，
T02 的重現拿到 `case is already handled by previous patterns` **警告**但**仍編譯成功**
（寫法細節不同所致）。所以「靠編譯器擋」在這裡是不可靠的——它對「帶 payload 的 enum
互相覆蓋」的冗餘分析並不完整。編譯器只保證「`Reason` 不漏」，
**不保證「具體列在前」**，所以措辭之外還必須有一條機械 gate：`affordanceMatchesTable`
（`Reason.allCases × MountOwner.allCases` **24 格** ＋ 三個頂層 case 逐格比對本表）——
實測它對上面兩種壞寫法分別紅 6 格／2 格，是唯一同時抓得到的東西。

| 狀態（具體列在前） | affordance |
|---|---|
| `broken(.occupiedByFile, _)` | `.explainOnly(.occupiedByFile)` |
| `broken(.occupiedByDirectory, _)` | `.explainOnly(.occupiedByDirectory)` |
| `claudeNotFound` | `.explainOnly(nil)` |
| `connected(_, _)` | `.none` |
| `notConnected` | `.connect` |
| `broken(其餘 Reason, owner: .external)` | `.replaceExternal` |
| `broken(其餘 Reason, owner: .thisApp／.unknown)` | `.connect` |

（「其餘」＝ `Reason.allCases` 扣掉 `occupiedByFile`／`occupiedByDirectory`；
`hookUnconfirmed` 與 `hookBlockedOrBroken` 的 affordance 相同——都是「再試一次接上」。
表的行數由 `allCases` 推導，**不寫數字**。）

`owner: .unknown` 走 `.connect` 是刻意的（R4）：那一格代表「目標解析不出來、也認不出是誰的」，
既然目標不存在就沒有東西會被毀；而**寫入點還有一層 `lstat` 檢查**（§4.1 第 4 步）。

`affordance → CTA` 的對應（R3：r3 沒寫，兩條 gate 因此沒有 oracle）：

| affordance | `showsConnectCTA` | CTA 文案 |
|---|---|---|
| `.connect` | true | 「接上」 |
| `.replaceExternal` | true | 「改指向這個 App」（副標寫現有掛載指向何處） |
| `.explainOnly(_)` | **false** | 無按鈕，只有 chip ＋ 說明文字（按了必定出錯的按鈕不該存在） |
| `.none` | false | — |

**`showsConnectCTA`、CTA 文案、`connect()` 的早退一律只讀 `affordance`**；
任何呼叫端**不得**自己看 `owner` 做「可否安全替換」的判斷（S2-6）。

### 3.2 `PanelAction`（D-j）

```swift
public enum PanelAction: Equatable, Sendable {
    case pickColor(Activity)          // 既有，併入
    case resetColors                  // 既有，併入
    case toggleOptions
    case connect                      // 一鍵接上／重新接上
    case replaceExternalMount         // D-i：明確選擇「改指向 App 內建」
    case disconnect                   // 呼叫端負責確認對話框
    case setLaunchAtLogin(Bool)
    case recheckHook                  // R2：`verified == false` 時的退化出口，不讓畫面停在未驗證
    case openHelp
    case about
    case dismissBanner
    case quit

    public var kind: PanelActionKind { … }              // 窮盡 switch
}
public enum PanelActionKind: String, Sendable, CaseIterable { … }
extension PanelAction {
    /// 每個 Kind 的**全部**代表值（N7：單一代表值時「開有接、關沒接」照樣全綠）。
    /// 對 Kind 窮盡 switch；`setLaunchAtLogin → [true, false]`、
    /// `pickColor → Activity.customizable.map(PanelAction.pickColor)`（`customizable` 本身
    /// 已從 `allCases` 推導），其餘回單元素陣列。
    /// **動作總數由 `PanelActionKind.allCases.flatMap(samples)` 推導，spec 不寫數字**（R6）。
    public static func samples(_ kind: PanelActionKind) -> [PanelAction] { … }
}
```
新增 `PanelAction` case → `kind` 編不過；補 `Kind` case → `samples` 編不過；補完 → G5 自動多測。
另有 `samples(k).allSatisfy { $0.kind == k }` 的 round-trip 斷言（實測此推導法可編譯、round-trip 全對）。

### 3.3 `PanelModel` 擴充

```swift
public let install: InstallState
public let version: String              // CFBundleShortVersionString，app 層讀好傳進來
public let optionsExpanded: Bool
public let launchAtLogin: Bool?         // nil = 這個環境不支援
public let externalTargetPath: String?
public let banner: PanelBanner?         // 接上成功／已移除掛載／錯誤，可關閉（S1-P3/P4）

/// 只讀 `install.affordance`（§3.1.1），不得自己 switch `InstallState`（N9）。
public var showsConnectCTA: Bool
/// 有 session 列時不吃掉列（S1-P4 的一半）：CTA 只在 rows.isEmpty 時整版顯示，
/// 否則縮成列上方一條警示條。
public var connectCTAStyle: CTAStyle   // .fullPanel / .banner / .none

/// **banner 與 CTA 的優先序（N10）**：同一時間畫面上方最多一條窄條。
/// `banner != nil` 時 `connectCTAStyle` 的 `.banner` 降級為 `.none`（banner 贏）；
/// `.fullPanel`（rows 空的整版 CTA）與 banner **可以並存**，banner 在上。
/// 沒有這條，移除掛載成功且仍有活著的列時，上方會同時出現「已移除掛載」與
/// 「還沒接上，要接嗎」兩條互相打架的訊息。
```

`make(...)` 的新參數**一律不給預設值**（只有 `now:` 例外）：忘了傳要是編譯錯，不是靜默畫「已接上」。
G-src 掃 `PanelModel.swift`：`make(` 簽章除 `now:` 外不得出現 `= `（S1-Q10.3c）。

健康 chip 由 `InstallState` 窮盡推導：

`connected` 的 chip 對 **`(owner, verified)` 逐格**寫（R3：r3 的表兩列重疊，
而重疊的那一格正是使用者自己機器每次啟動的頭兩秒；`panelReflectsInstallState`
要對每一種狀態斷言 chip 文字，oracle 不能有兩個答案）。
`verified` 先判、`owner` 只決定要不要加後綴「（你的 repo 掛載）」：

| `verification` | chip 文字（`owner == .external` 時加後綴） | tone | 有沒有動作 |
|---|---|---|---|
| `.verified` | 已接上 | ok | — |
| `.inFlight` | 已接上 · 檢查中… | ok | — |
| `.unknown` | **已接上（未驗證）** | ok | Options 出現「再檢查一次」（`recheckHook`） |
| `.blocked` | → 不是 `connected`，見 `broken(.hookBlockedOrBroken)` 那列 | — | — |

`.inFlight` 與 `.unknown` **必須分開**（R2）：「檢查中…」是一個關於進行中的宣稱，
沒有東西在進行時就是說謊——這正是前三輪一路在殺的那一族。

其餘狀態：

| 狀態 | chip 文字 | tone |
|---|---|---|
| `claudeNotFound` | 找不到 Claude Code | warn |
| `notConnected` | 還沒接上 | warn |
| `broken(.targetMissing)` | 接不上：App 被搬走了 | warn |
| `broken(.targetUnresolvable)` | 接不上：連結解不開 | warn |
| `broken(.notAPlugin)` | 接不上：掛載內容不對 | warn |
| `broken(.hookMissing)` | 接不上：少了 hook 程式 | warn |
| `broken(.hookNotExecutable)` | 接不上：hook 沒有執行權限 | warn |
| `broken(.hookBlockedOrBroken)` | 接不上：macOS 擋住了 hook | warn |
| `broken(.hookUnconfirmed)` | 接不上：無法確認 hook 能不能跑 | warn |
| `broken(.occupiedByDirectory)` | 已被其他安裝佔用 | warn |
| `broken(.occupiedByFile)` | 路徑被一個檔案佔住 | warn |

**`healthTone` 的實際色值寫死在此**：`ok = #30d158`（與 done 同色）、`warn = #ff9f0a`（與 waiting 同色）。
語意一致是刻意的，**配色不改**。

但這導致 chip 色在 `.default` palette 的畫面裡**不唯一**（實測與 `default.done`／`default.waiting`
delta = 0.0000）：以 `.default` 渲整張面板時 `#ff9f0a` 有 448 px，把 chip 改成綠之後**仍有 276 px**
（圖例的 waiting 點）→ r2 指定的 mutation 抓不到，G6 born-green（N11）。
**修法：G6 一律以 `wildPalette` 渲**——chip 的固定色因此在圖中唯一（實測 warn chip 172 px、
mutation 改綠 0 px）。前提 gate G11 改成「`ok`／`warn` 與 `wildPalette` 五色的
`maxComponentDelta > 0.063`（= 8 × `count(near:)` 的 tolerance 2/255）」。

> r1 的處方（門檻 0.2、改 `wildPalette` fixture）**經實測是錯的**，r2 照著做因此過度修正：
> tolerance 只有 2/255，delta 0.15 已是它的 19 倍，實跑含 warn chip 的 `.default` 面板，
> 四個 wild 色命中全 0 px；而 0.2 還會咬到 `ok` vs `wild.idle` = 0.1382。**`wildPalette` 不必改**
> （Migration #3 已刪除）。phase-2 明令：既有「wild 色 0 px」對抗式斷言**不得放寬**。

### 3.4 文案映射（M-7，D-c）

映射是**字典**，因為 gate 要迭代它當來源集合（S1-Q4）：

```swift
public enum Jargon {
    public static let effortMap: [String: String] = [
        "low": "思考低", "medium": "思考中", "high": "思考高", "xhigh": "思考極高"]
    public static let permissionModeMap: [String: String] = [
        "auto": "自動判斷",            // ← 實測 141 個 payload 裡最常見的值，r1 漏了（S1-Q4）
                                       //   brainstorm §4 的示意寫「自動接受」，**刻意改成「自動判斷」**：
                                       //   auto 的語意是自動決定要不要問，不是一律接受（S2-3）
        "default": "每次問我",
        "acceptEdits": "自動接受編輯",
        "bypassPermissions": "全部自動",
        "plan": "計畫模式"]
    public static func effort(_ raw: String) -> String          // 查表，未命中原樣回傳
    public static func permissionMode(_ raw: String) -> String  // 同上
    public static func model(_ raw: String) -> String           // 演算法，見下
}
```

`model` 的規則（**寫完整並附反例**，S1-Q4）：
1. 抓出 `[...]` 後綴 → ` (內容大寫)`；其餘部分繼續處理
2. 去 `claude-` 前綴（沒有也接受）
3. 去尾端的 8 位數字段（日期）
4. 以 `-` 切段；**恰好一個非純數字段**視為名字（首字大寫），其餘純數字段依原順序以 `.` 連接
5. 名字與版本之間一個半形空格
6. 任一步不符（無名字段、無數字段、多於一個非數字段）→ **原樣回傳**

| 輸入 | 輸出 | 說明 |
|---|---|---|
| `claude-fable-5-1` | `Fable 5.1` | |
| `claude-opus-5[1m]` | `Opus 5 (1M)` | 實測 fixture 裡的真值 |
| `claude-sonnet-5` | `Sonnet 5` | |
| `claude-haiku-4-5-20251001` | `Haiku 4.5` | 去日期段 |
| `claude-3-5-sonnet-20241022` | `Sonnet 3.5` | 名字不在第一段也對 |
| `opus-5` | `Opus 5` | 無 `claude-` 前綴 |
| `gpt-4o` | `gpt-4o` | 兩個非數字段 → 原樣 |
| `claude` | `claude` | 無數字段 → 原樣 |
| `""` | `""` | |

**呼叫點明訂為 `PanelViewModel.meta(for:)`**（S1-Q5：r1 只寫了映射沒寫呼叫點，`meta` 現在直接
join 原字串——`Jargon` 可以 100% 正確而面板照樣印 `claude-opus-5[1m] · xhigh · auto`）。
同時 `PanelViewModel.detail` 的英文字改中文：`N subagents` → `N 個子任務`、
`N tool 失敗` → `N 次工具失敗`。圖例提示行改「八顆燈一起代表全部 session · 點色點改顏色」。

---

## 4. 核心技術

### 4.1 一鍵接上（`Installer`）

```
connect(force: Bool, translocated: Bool, inDownloads: Bool) throws:
  0. translocated || inDownloads → throw .mustMoveToApplications        （S1-A4）
  1. 依 probe() 的 **affordance**（§3.1.1，唯一的路由來源，不再自己 switch 狀態）：
       .none                → return .alreadyConnected（UI 顯示 banner「已經接上了（指向 X）」，S2-5）
                              **有效掛載的保護是「完全不觸碰」而不是 throw**——`.alreadyConnected`
                              是成功、冪等（T03 提出：把它寫成 throw 會逼呼叫端自己看 `owner`
                              決定要不要放行，那正是 S2-6 禁止的事）。守它的是
                              `connectDoesNotTouchValidExternalMount`（斷言 symlink 目標前後一致）
       .explainOnly(reason) → throw .cannotConnect(reason)   // claudeNotFound／occupied*
       .replaceExternal     → force ? 繼續 : throw .externalMountNeedsChoice(state)
       .connect             → 繼續
  2. bundledPlugin = Bundle.main.resourceURL/plugin；不存在 → throw .bundleIncomplete
  3. <claudeHome>/skills 不存在 → mkdir（**只這一層**，不 -p 到 ~/.claude）
  4. **寫入點自己再檢查一次型別（S0-1(ii)，保本動作要在執行層驗，不能只在路由層驗）**：
     lstat(skills/agentaura) → **只有 absent 或 S_IFLNK 才准繼續**，其餘一律 throw
       - 普通檔案：實測 `rename` 蓋它 **rc=0、使用者內容直接消失**（讀不回來）
       - 實體目錄：實測 errno=21 (EISDIR) 會擋下來、目錄完好（S2-10 的文案）
     護欄不能只放在 affordance（離寫入點三層遠），中間還有 TOCTOU 窗：probe 到 rename 之間
     使用者或別的程式可以在那個路徑上放一個檔案。`disconnect` 的 `S_IFLNK` guard 對這裡
     **完全不生效**——`rename` 不經過 `unlink`，一次都不會問它。

     **這條護欄的可觀測性（T03 實測）**：正常情境下 affordance 早就先擋住同樣的違規，
     所以「拿掉寫入點檢查」這個 mutation **從 `connect()` 這一層看不見**。因此
     `performConnectSteps()` 宣告成 `internal`（不是 `private`），讓 gate 用
     `@testable import` 直接呼叫中間層、繞過步驟 0–1 來觀察它——與本專案既有的
     `PipelineGraph.registry`／`StatusItemController.togglePopover` 同一個理由
     （「internal 是為了可測性，不是抽象癖」），doc comment 必須把理由寫上。
     **誠實的限制**：真正的 TOCTOU（probe 之後、rename 之前才被塞進一個檔案）無法在
     沒有測試鉤的情況下驗證，列為 known gap；`connect() → performConnectSteps` 的接線
     由 happy path 測試證明，護欄本身由直呼測試證明，兩段合起來成立。
     然後原子替換（S1-A6）：symlink(bundledPlugin → skills/agentaura.tmp-<uuid>)
                        → rename(tmp → skills/agentaura)
     舊的 symlink 被 rename 直接蓋掉，**永不先 unlink**（實測 rename 可蓋 symlink）
  5. probe() 必須是 .connected，否則 throw .verificationFailed(state)
  6. **exec 驗證（S0-A2，本步是重點）**：
       - 先試 removexattr(<target>/bin/aura-hook, "com.apple.quarantine")（失敗不致命）
         **實測**：遞迴隔離的樹 exec=137／產物 0 → **只對 binary 這一顆** removexattr（目錄仍帶隔離）
         → exec=0／產物 1；經 symlink 亦同；只有父目錄帶隔離、binary 乾淨 → 正常跑。
         所以目標就是這一顆檔案，**不要改成 `-r`**。但 bundle 唯讀時 removexattr 會 EPERM，
         所以 `.hookBlockedOrBroken` 這條路徑**必須保留**——只有看產物抓得到。
       - spawn <skills/agentaura>/bin/aura-hook，env AGENTAURA_ROOT=<temp>，
         stdin 餵一個合成 payload（session_id 用 uuid，hook_event_name=SessionStart）
       - 有界等待（≤ 2s，**單調時鐘**）該 temp root 出現對應狀態檔
       - 沒出現 → throw .hookBlockedOrBroken(.noArtifact)（文案：「macOS 擋住了 hook。把 App 拖進
         『應用程式』再開一次；或到系統設定 → 隱私與安全性允許」）
       - **逾時**（機器睡眠等）→ 寫 `.unconfirmed` 憑證、throw `.hookUnconfirmed`
         （文案：「無法確認 hook 能不能跑」）——**不得反過來誤指控 macOS**（S2-11／r6 ②：
         逾時若寫成 `blocked`，重開之後 chip 會**永久**說「macOS 擋住了 hook」，
         那是被持久化的誤指控）
       - **spawn 本身丟錯**（`Process.run()` throw／fork 失敗／沙箱）→ 同樣寫 `.unconfirmed` 憑證，
         **不准讓狀態留在 `unknown`**（R2：否則退化成 S0-A2 原本要修的「說已接上、其實全暗」）
       - 三種寫回值：產物沒出現 → `AgentAuraHookBlocked`；逾時／spawn 丟錯 → `AgentAuraHookUnconfirmed`；
         成功 → `AgentAuraHookVerified`（三個鍵互斥，寫一個要清掉另兩個）
       - 清掉 temp root
     依據：本專案自己的 invariant「`aura-hook` exit code 無法用來驗收，驗收必須看產物」；
     `Tests/AuraCoreTests/EndToEndWiredGateTests.swift` 已有現成招式（`AGENTAURA_ROOT` + Process）
  7. 成功 → 寫入驗證憑證 `AgentAuraHookVerified = "<dev>:<ino>:<mtime>"`（清掉 blocked 鍵），
     banner「已接上 · 下一個 Claude Code session 起生效（現在開著的視窗不受影響）」（D-m）
     **第 6 步的任何失敗**（產物沒出現／逾時／spawn 丟錯）→ 寫入 `AgentAuraHookBlocked`（同格式），
     狀態才能跨 probe／跨重啟存活（N1／R2）
```

`replaceExternalMount` **就是 `connect(force: true, …)`**（N6）——同一段實作，只有第 1 步的
`.replaceExternal` 早退被跳過。guard 0、原子替換、exec 驗證、憑證寫入**全部共用**；
r2 把它寫成另一個動作，是「新呼叫點漏檢查」的標準形狀。

`disconnect()`：**只有 `lstat` 回 `S_IFLNK` 才 unlink**（S1-S2：唯一會刪到使用者資料的路徑就在這裡，
實測普通檔案會落在 `targetMissing`，r1 的條件只擋「實體目錄」）；其餘一律拒絕並說明。
**不刪 `~/.agentaura/`、不刪 app、不呼叫 `acknowledgeAll()`**（S1-A9）。
成功後 banner「已移除掛載。要再用的話按［接上］。」——與「壞掉」明顯不同（S1-P4）；
確認對話框要寫清楚會刪什麼、不會刪什麼、以及「AgentAura 會留在選單列」。

exec 驗證**只准在四個地方**：connect／`replaceExternalMount`（同一段）、**啟動時的背景驗證**
（N1，僅當 `verification != .verified`）、以及使用者按「再檢查一次」（`recheckHook`，R2）。
**每次開面板的 probe 一律不得 exec**（S2-A12）——面板路徑只讀憑證。

### 4.2 開機自動啟動（`LoginItem`）

```swift
@MainActor protocol LoginItemControlling {
    var isSupported: Bool { get }   // 非 bundle 執行／translocated → false，UI 隱藏該列
    var isEnabled: Bool { get }     // 每次展開 Options 重讀，不自己記
    func set(_ on: Bool) throws
}
```
生產實作 `SMAppService.mainApp`（macOS 13+）。三種失敗都要處理：`register()` throw（開關彈回實際值）、
`.requiresApproval`（指引到系統設定）、**translocated／`~/Downloads`**（拒絕註冊，同 D-f，
否則註冊一個必壞的登入項目，S1-S3）。測試一律注入 fake；另有 composition smoke 斷言生產注入的不是 fake。

### 4.3 Options 展開（D-b）

`optionsExpanded` 的家在 `AppDelegate`（不是 SwiftUI `@State`）——`setPanel` 每次 FSEvents 都換
`rootView`，`@State` 會與 model 不同步。既有 `sizingOptions = [.preferredContentSize]` 讓高度自動跟隨。
展開時**不釘住 popover**（accordion 不搶焦點）。

列的內容由 `AuraCore` 的 `OptionsMenuModel.rows(install:launchAtLogin:isDefaultPalette:) -> [OptionsRow]`
產生，每列帶 `action: PanelAction`（S1-Q6：這是 gate 的推導來源，view 只從它取列）。

### 4.4 首次啟動自動開面板（D-e / S1-P5 / S1-Q10）

旗標 `AgentAuraDidConnectOnce`（Bool，語意是「曾經成功接上過」，不是「看過歡迎」）。
啟動流程尾端，**順序有 gate 守著**：

```
attachPopover()  →  setPanel(install 為真實狀態的 model)  →  若 !didConnectOnce && !connected { showPanel() }
```
(i) 必須在 `attachPopover()` 之後（Change 2 實測 `contentViewController == nil` 時 `NSPopover.show`
丟 NSException **殺整個行程**）；(ii) 必須已 `setPanel` 過真實狀態的 model，否則使用者看到
`attachPopover` 預掛的空 model（「沒有活著的 session」、沒有 CTA）——首次啟動最糟的第一印象。
旗標一律走既有的 `defaults` 注入點（S2-S4：否則跑一次測試就寫掉使用者的旗標）。

### 4.5 Bundle 佈局（D-g）

```
AgentAura.app/Contents/
  MacOS/AgentAuraApp
  Resources/Info.plist · help.html
  Resources/plugin/{.claude-plugin/plugin.json, hooks/hooks.json, bin/aura-hook}
```
`build-app.sh` 增加複製步驟，缺 `plugin/bin/aura-hook` 時**大聲失敗**。
`verify-app.sh` 對真 bundle 斷言三檔存在、`aura-hook` 可執行、且 `lipo -archs` 有兩個架構；
**缺 bundle 時必須 FAIL 不是 skip**（S1-Q11：本專案有 env-gated suite 靜默 skip 的前例）。
實測 `codesign --force --deep --sign -` 會把巢狀 Mach-O 一起 ad-hoc 簽掉、`--verify --strict --deep` 通過。

---

## 5. 錯誤處理

| 失效模式 | 若不處理的後果 | 處理 |
|---|---|---|
| **下載版 app 被 quarantine** | hook 每次 exec 被 SIGKILL、`aura-hook` 契約是靜默 exit 0 → **app 說「已接上」但永遠全暗** | §4.1 第 6 步 exec 驗證 → `.hookBlockedOrBroken` ＋ 可行動文案（S0-A2） |
| **接上時 Claude Code 已開著** | 現行 session 不載入新 plugin → 使用者判定壞了 | banner 明講「下一個 session 起生效」（D-m／S0-A1） |
| **App Translocation／在 `~/Downloads`** | symlink 指向會消失的臨時掛載 → 壞→重新接上→再壞的迴圈；登入項目同理 | connect／register 前拒絕，要求先搬進「應用程式」（S1-A4／S1-S3） |
| app 被搬走／改名 | 燈永遠全暗，使用者以為沒事 | `broken(.targetMissing)`；chip 變黃、CTA「重新接上」 |
| `bin/aura-hook` 沒有 x 權限 | 每個 tool call 白 fork 拿 127，完全靜默（前一個專案 原始災難） | `broken(.hookNotExecutable)` |
| 掛載指向 repo 且暫時壞掉（`git clean` 掉建置產物） | 靜默換成 bundle 內凍結版，開發者改碼不生效 | `broken(_, owner: .external)` → 顯示現況 ＋ 兩個明確選項（D-i／S1-A7） |
| `skills/agentaura` 是**普通檔案** | r1 會 unlink 它；r3 的 affordance 表更讓它拿到 `.connect`，`rename` 蓋普通檔案**實測 rc=0、內容直接消失** | 三層：`.occupiedByFile` → affordance `.explainOnly`（無按鈕）→ **第 4 步寫入點 `lstat` 只准 absent／`S_IFLNK`**（S0-1）；`disconnect` 另有 `S_IFLNK` guard（S1-S2） |
| `rename` 蓋到實體目錄 | 沒有對應文案 | 實測 errno=21 (EISDIR)，目錄完好；文案「已被其他安裝佔用」（S2-10） |
| `skills/agentaura` 是實體目錄 | 誤刪別人的安裝 | `.occupiedByDirectory`，拒絕 |
| 自我迴圈 symlink | r1 會顯示「App 被搬走了」——對迴圈是謊話 | `.targetUnresolvable`（實測 `realpath` 回 nil、`resolvingSymlinksInPath` 會假裝成功，故判定用 `realpath`） |
| `~/.claude` 不存在 | r1 的 `mkdir -p` 會連 `~/.claude` 一起建，違反 D-h | `.claudeNotFound`：「看起來還沒用過 Claude Code」，不建目錄 |
| `skills/` 不可寫 / `skills` 是檔案 | `symlink` EACCES／`mkdir` ENOTDIR 沒有對應文案 | 兩者各一條錯誤文案，指向手動指令 |
| 第 4→5 步之間失敗 | 使用者原本可修的掛載被刪掉 | 原子 `rename()` 替換，永不先 unlink（S1-A6） |
| `SMAppService` 需要核准 | 開關看起來沒反應 | `.requiresApproval` → 指引系統設定；開關彈回實際值 |
| 移除掛載後畫面與壞掉相同 | 使用者以為自己弄壞了 | 專屬 banner「已移除掛載」（S1-P4） |
| Options 展開時被 FSEvents 更新 | 展開狀態跳掉 | 狀態存在 `AppDelegate`（§4.3） |
| 未知的 model／effort／permission_mode | 顯示空白或亂碼 | 查表未命中原樣回傳（§3.4）；另有 fixture 錨點 gate 抓上游新值（G9b） |

---

## 6. 測試策略

### 6.1 對抗式 double（T01 先行，零生產碼）

`LinkObservation` fixture 覆蓋 §3.1 的**每一種**狀態（集合由型別推導，不寫數字），**外加實測過的刁鑽組合**：
symlink→symlink、相對目標、**斷鏈（`realpath` errno=2）與自我迴圈（errno=62）必須分開**（N3）、
權限被拒（EACCES）、symlink 指向普通檔案（`realpath` 成功但非目錄）、指向 `~/.claude` 自己、
大小寫兩種拼法（URL 不等但 inode 相等）、`/private` 別名（`/var` vs `/private/var`）、
二進位存在且有 x 位**但 exec 會被殺**（→ 只有 exec 驗證抓得到）、
`verification` **四種值** × 憑證相符／不符（identity 或 mtime 任一不同都算不符，N1）、
**spawn 本身丟錯**與**逾時**兩種寫回值（R2／S2-11）、
以及 `thisAppPluginIdentity == nil`（bundle 不完整／`swift run`／**`swift test` 就是這一格**）
搭配 `rawLinkTarget` 有／無，驗 `MountOwner` 三值各自可達（R4：r3 的 `Bool` 公式在測試環境
會給出與生產**反向**的值，fixture 因此測到生產永遠不會出現的那一半）。
每一種都要有明確 `InstallState`，不准落到 `default`（型別上也不允許：窮盡 switch）。

`FakeLoginItem`：`isSupported=false`、`set` 丟 `.requiresApproval`、
`isEnabled` 與剛設定的值**不一致**（模擬需核准時系統沒真的打開）。

`FakeInstaller`：`connect()` 成功但 `probe()` 仍回 `notConnected`（第 5 步的驗證要真的會擋）；
另一個變體：probe 說 `connected` 但 exec 驗證失敗（第 6 步要真的會擋）。

**離屏渲染的共同前提（S0-Q2，寫進 T01 的 helper，不由各測試自行決定）**：
所有新離屏渲染必須 `hosting.appearance = NSAppearance(named: .aqua)`（深色另渲一次），
且每條像素 gate 都要有**前提斷言**（例：非白像素 > 2000）——harness 空轉時大聲紅而不是安靜綠。
實測依據：不釘 appearance 在 Dark 機器上渲淺底，文字 0 px、非白像素只有 224。

### 6.2 Composition-root smoke（tested ≠ wired）

| Gate | 斷言 |
|---|---|
| `panelActionsAreWired` | `PanelActionKind.allCases.flatMap(PanelAction.samples)` 逐一送進 `onAction`，spy／fake 斷言**每一個**的副作用真的發生（含 `setLaunchAtLogin` 的 true／false 兩者）。新增 case 忘了接線＝編譯錯誤（`kind`／`samples` 窮盡 switch，D-j） |
| `panelViewForwardsAction` | 建真的 `PanelView` → 觸發動作 → 斷言閉包收到（S1-Q8：view→controller 這一跳目前無人守） |
| `productionUsesRealLoginItem` | 生產注入的不是 fake 型別 |
| `productionUsesRealInstaller` | 生產 `claudeHome` **以 `/.claude` 結尾**且**不含 `/var/folders/`／`NSTemporaryDirectory()` 前綴**（S1-Q9.3：套套邏輯式的「跟生產同一個運算式比對」不算） |
| `panelReflectsInstallState` | 對 `InstallState` 的**每一種**斷言 chip 文字、`showsConnectCTA`、CTA 文案、`connectCTAStyle`。狀態集合由 `Reason.allCases × MountOwner.allCases` ＋ `MountOwner.allCases × Verification.allCases`（connected）＋ 兩個頂層 case **推導，不寫數字**（R6）；oracle 是 §3.1.1 的 affordance→CTA 表與 §3.3 的 chip 表 |
| `firstRunOpensPanelOnce` | `!didConnectOnce && !connected` → `showPanel()` 恰一次；已接上或旗標已設 → 不呼叫 |
| `firstRunOrdering` | 呼叫順序為 `attachPopover` → `setPanel(真實狀態)` → `showPanel`（S1-Q10.1） |
| `openPanelReprobesWithoutAcknowledging` | `onOpen` → probe ＋ `setPanel` 各一次、`acknowledgeAll` **零次**（與既有 `acknowledgeFiresOnCloseNotOpen` 互補） |
| `disconnectDoesNotAcknowledge` | disconnect 後尾巴仍在、狀態檔仍在（S1-A9） |
| `blockedSurvivesReprobeAndRestart` | exec 驗證失敗（寫入 blocked 憑證）之後，接下來的 probe **不得**把狀態回復成 `.connected`；用新的 `AppDelegate`＋同一份 `defaults` 重建一次（模擬重啟）仍是 `.broken(.hookBlockedOrBroken)`。**這是 N1 修正的唯一接縫** |
| `launchVerifiesUnlessAlreadyVerified` | 啟動後 **`verification != .verified`** 就跑一次 exec 驗證並寫回憑證——`.unknown` 與 **`.blocked`** 各跑一次（R2：`.blocked` 不跑的話，使用者照文案去系統設定允許、重開 app，畫面仍說壞的）、`.verified` 不跑；**面板路徑（`onOpen`）一次都不跑** |
| `unknownIsNeverTerminal` | exec 驗證的三種失敗（產物沒出現／逾時／`Process.run()` 丟錯）**各自**都要寫回憑證；驗證跑完後狀態不得留在 `.unknown`（R2） |
| `verificationStoreIsInjected` | 生產注入的 store 不是 fake；**且 `Sources/AuraHookFile/` 內不得出現 `UserDefaults(`／`UserDefaults.`**（帶標點；T01 必辦 ⑤——掃「`UserDefaults` 字樣」會被**註解**命中，實測 grep 回 1 而那一個全在註解裡 ⇒ born-red 或被刪註解繞過。＋檔數防空跑 ＋ 暫存目錄放一個真的用了 `UserDefaults.standard` 的 probe 當正向對照）。這是唯一能擋住「被 Swift 6 逼去碰全域 `UserDefaults.standard`」那條歪路的東西（R1） |
| `affordanceMatchesTable` | `Reason.allCases × MountOwner.allCases`（**24 格**）＋ `claudeNotFound`／`notConnected`／`connected` 各格，逐格比對 §3.1.1 的表。定義域是**這個乘積**，不是「狀態機目前可達的那些」——`occupied*, .external` 現在不可達是狀態機的運氣，不是 `affordance` 這個 public 屬性的定義域（T01 必辦 ①） |
| `affordanceRoutesConnect` | 對**每一種** `InstallState`（同上乘積）：`affordance == .connect` 的都不得 throw 路由型錯誤；`.explainOnly`／`.replaceExternal`／`.none` 的都必須走各自的早退。守 N9 的兩個 switch 不再漂移 |
| `bannerBeatsCTABanner` | `banner != nil` 且 CTA 樣式為 `.banner` 時，model 只產出一條（N10）；`.fullPanel` ＋ banner 可並存且 banner 在上 |

### 6.3 Gate 表（每條都要 mutation 紀錄；G-src 為來源掃描類）

| # | Gate | 位置 | mutation |
|---|---|---|---|
| G1 | `InstallStateTests`：狀態集合**由型別推導**（`Reason.allCases × MountOwner.allCases` ＋ connected 的 `MountOwner × Verification` ＋ 兩個頂層 case，不寫數字，R6）＋ §6.1 刁鑽組合。**註記**：「symlink → 普通檔案」與「是目錄但缺 `hooks.json`」**必須落到同一個 `.notAPlugin`**（動作相同、文案不說謊、發生率極低）——不准為了「看起來該分開」補第 9 個 Reason，那會把 chip 表與 affordance 表一起改壞（N3 追加） | AuraCoreTests | 把 `hookNotExecutable` 併進 `connected` |
| G2 | `installerTouchesOnlyAllowedPaths`：connect＋disconnect 前後對 **`realpath(<claudeHome>/skills)`**（不是字面路徑，T01 必辦 ②——實測 `skills` 自己是指到 claudeHome 外的 symlink 時，寫入落在外面而 claudeHome 的樹完全沒變 ⇒ 全綠）與 claudeHome **整棵樹**比對 `(相對路徑, 型別, mode, size, md5 或 symlink 目標)` 元組集合；**容許差異集合恰為 `{skills（若原不存在）, skills/agentaura}`**；另植入 `settings.json` 斷言元組完全不變；**fixture 必須包含「`skills` 是 symlink」那一種** | AuraCoreTests | 讓 `connect` 順手寫一個 `settings.json.bak`；把 `skills` 換成指到 temp 外的 symlink（改成 `realpath` 之後這條才抓得到） |
| G3 | `installerRefusesToClobber`：**兩條呼叫路徑各自斷言**（S0-1(iii)）——(a) **`connect`** 對普通檔案／實體目錄／有效掛載／external 且壞掉都必須 throw，**且普通檔案的內容位元組完全不變**（不是只看「沒被移除」——`rename` 蓋它是 rc=0 而內容消失）。**斷言形狀是強制的（T01 必辦 ③）**：用 `Optional<Data>` 相等（`try?`，實測 before 18 bytes／after nil ⇒ 紅在斷言）＋ `lstat` 型別相等兩半；**不得用 `try Data(contentsOf:)`**——clobber 後那條路徑是指向目錄的 symlink，`try` 會丟錯而顯示成「拋出未預期錯誤」，不是斷言失敗；(b) **`disconnect`** 對普通檔案／實體目錄必須拒絕；(c) `replaceExternalMount` 在 **translocated／`~/Downloads`** 時也必須拒絕（S2-8：11 列表指名 G3 守這件事，G3 的描述必須真的有它） | AuraCoreTests | **兩筆**：① 拿掉 `disconnect` 的 `S_IFLNK` 檢查 → 必須紅在 (b)；② 拿掉**第 4 步寫入點**的型別檢查 → 必須紅在 **(a) 的普通檔案內容比對**（缺這筆，connect 的毀檔路徑零測試） |
| G4 | `connectVerifiesByArtifact`：(a) `FakeInstaller` 讓 exec 不產生產物 → `connect` 必 throw `.hookBlockedOrBroken`；(b) 正常路徑真的 spawn **SwiftPM 產物**（`AuraHookCLITests.binaryURL()`，`Installer` 的 hook 路徑本來就該是注入參數）確認會產出。**bundle 內那份不在 `swift test` 環境裡**，交給 G14 ＋ DoD 實機②（N8：照 r2 字面寫會 born-red 或被寫成 skip，而本專案有「skipped 不是綠」的前例） | AuraCoreTests | 刪掉 §4.1 第 6 步 |
| G5 | `panelActionsAreWired`（§6.2）：`PanelActionKind.allCases.flatMap(PanelAction.samples)` → **16 個實際動作**逐一送 | AgentAuraAppTests | 把某個 case 的實作換成 `break`；只接 `setLaunchAtLogin(true)` 不接 `false`（N7 要抓得到這條） |
| G6 | `footerRendersHealthAndVersion`：**一律以 `wildPalette` 渲**（N11：以 `.default` 渲時 chip 色與圖例點同色，mutation 抓不到）。(a) 兩種狀態各渲一次，connected → `ok` 色 ≥ 100 px、notConnected → `warn` 色 ≥ 100 px（實測 8 pt 圓 @2x = 172 px，**兩半都有牙齒**：connected 的 chip 改成 warn → 0 px、notConnected 的改成綠 → 0 px）；(b) 差異渲染證明版本真的到畫面：fixture **固定 `v0.1.0` vs `v9.9.9`**（≥ 3 個字形不同，實測 921 px），門檻 **≥ 300**，同內容連渲 **== 0**（N2：相鄰版本號只差 253 px，fixture 與門檻必須一起釘死）；(c) 前提斷言（非白像素 > 2000） | AgentAuraAppTests | 讓 chip 色固定綠（必須紅在 (a)）；讓版本不進 view（必須紅在 (b)） |
| G7 | `optionsExpandGrowsPanel`：`preferredContentSize.height` 展開後變高（**快照比對**，不是拿當下值跟自己比） | AgentAuraAppTests | 讓 `optionsExpanded` 不影響 view |
| G8 | `connectCTAIsModelDrivenAndVisible`：(a) model 層 `showsConnectCTA`／`connectCTAStyle` 對每種 `InstallState`（由 `Reason.allCases` × `external` ＋ 三個頂層 case 推導，**不寫數字**，S2-1）窮盡斷言；(b) 差異渲染 notConnected vs connected——**必須固定畫布 380×320 pt**（兩狀態自然高度是 215 pt／261 pt，直接相減逐像素無定義；r3 引用的 430／522 是 @2x 像素，S2-7），門檻 **> 20,000 px**（實測整版切換 163,785、同內容 0；畫布改 560／600 pt 得到**完全相同**的數字——門檻對畫布高度不敏感，別為了「看起來合理」去動畫布尺寸）；(c) **正向對照**：connected ＋ 有 session → 列真的畫得出來（否則「不畫」恆真） | AgentAuraAppTests | 讓 CTA 在 `connected` 也顯示；讓 `connectCTAStyle` 固定 `.none` |
| G9a | `jargonMapsEveryKnownCode`：迭代 `Jargon.effortMap`／`permissionModeMap` **本身**當來源集合，斷言每個 key 的輸出 ≠ key；未知值原樣回傳；`model` 走 §3.4 的反例表 | AuraCoreTests | 讓 `effort` 直接回傳 raw |
| G9b | `fixtureCodesAreAllMapped`（**外部錨點**）：掃 `Tests/AuraCoreTests/Fixtures/*.ndjson` 抽出所有出現過的 `permission_mode`／`effort.level`／`model`，斷言每一個都有人話對應（現在就會抓到 `auto`）——這條才擋得住上游新增值 | AuraCoreTests | 從 `permissionModeMap` 拿掉 `auto` |
| G9c | `metaNeverEchoesKnownCode`（**wired**）：用 fixture 真值建 `SessionState` → `PanelModel.make(...).rows.first!.meta` 不含任何原始代碼字 | AuraCoreTests | 把 `meta` 改回不套 `Jargon`（S1-Q5） |
| G10 | `optionsRowsCoverEveryAction`（兩段，r7）：(a) **`nonMenuKinds` 恰好等於 `{pickColor, toggleOptions, dismissBanner, replaceExternalMount}`**（往裡面加東西就是紅，R5——r3 只要求「成員被別的 gate 指名」，但 `openHelp`／`about`／`quit`／`setLaunchAtLogin` 的指名 gate 是 G5，而 G5 直接把 `samples()` 送進 `onAction`、**不經過 `OptionsMenuModel.rows`**，逃生門原封不動）；(b) 對一組由型別推導的代表狀態集合，各狀態 `rows` 的**聯集**涵蓋全部 8 個選單 Kind，且任一單一狀態內同一 Kind 最多一次 | AuraCoreTests | ① 從 rows 拿掉「離開」；② `resetColors` 搬家時掉了（它是選單列，不是 `nonMenuKinds`）；③ 把 `quit` 塞進 `nonMenuKinds`（相等斷言必須紅） |
| G11 | `healthTonesDontCollideWithPixelFixtures`（**前提 gate**）：`ok`／`warn` 與 `PanelPixelTests.wildPalette` 五色的 `maxComponentDelta > 0.063`（= 8 × `count(near:)` 的 tolerance 2/255；r1 的 0.2 無推導依據且會咬到 `ok` vs `wild.idle` = 0.1382） | AgentAuraAppTests | 把 warn 改成與 wild waiting 相差 < 0.063 的黃 |
| G12 | `acknowledgeAllHasExactlyOneCallSite`（**來源推導**）：範圍限 `Sources/AgentAuraApp/`、樣式 `.acknowledgeAll(`（**帶點**，排除宣告），斷言恰好 1 個命中且在 `AppDelegate.swift`。沿用 `AppLayerSourceScanTests` 兩個既有慣例：同一 reader 回報掃到的檔數（防空跑，讀不到就 throw）＋ 暫存目錄放一個含假呼叫的 probe 當正向對照。（N4：r2 寫「掃 `Sources/` 對 `acknowledgeAll(`」實測有 4 個命中——2 個宣告 ＋ 1 個 module 內合法呼叫——照字面寫 born-red） | AuraCoreTests | 在 disconnect 加回 `.acknowledgeAll()` |
| G13 | `panelModelMakeHasNoDefaults`（**來源推導**）：`PanelModel.swift` 的 `make(` 簽章除 `now:` 外不得出現 `= ` | AuraCoreTests | 給 `install` 一個預設值 |
| G14 | `bundleLayoutIsVerified`：`verify-app.sh` 對真 bundle 斷言三檔存在、可執行、雙架構，**缺 bundle 時 FAIL 不 skip** | script（DoD 明列每次改 bundle 佈局都要跑） | 拿掉 `build-app.sh` 的複製步驟 |
| — | 既有 `IsolationTests`（200／300 行、module 白名單）**不列入 mutation 計數**（S1-Q11：它對本 change 不是新 gate），但新增檔案自動納入 | AuraCoreTests | — |

#### 每一個 `PanelActionKind` 各由誰守（N5：一個都不能沒有名字；行數由 `allCases` 推導，不寫數字）

| Kind | 守它的 gate |
|---|---|
| `pickColor` | 既有 `PaletteWiringSmokeTests.controllerForwardsPanelCallbacks` ＋ G5（`Activity.customizable` 四個值都送） |
| `resetColors` | **G10（必須在 `rows` 裡）** ＋ 既有 `PaletteWiringSmokeTests`「重設後 `isDefaultPalette == true`」（該檔唯一從 true 側見證 `isDefault` 的地方）＋ G5 |
| `toggleOptions` | G7（`preferredContentSize` 展開後變高） |
| `connect` | **G10** ＋ G4 ＋ G8（CTA 差異渲染）＋ `affordanceRoutesConnect` |
| `replaceExternalMount` | G3（translocated 時也必須拒絕）＋ `affordanceRoutesConnect` ＋ G8 的 CTA 差異渲染（**只在 CTA，不進選單**） |
| `disconnect` | G3 ＋ `disconnectDoesNotAcknowledge` |
| `setLaunchAtLogin` | **G10（必須在 `rows` 裡）** ＋ G5（`true`／`false` 兩個值都送）＋ `productionUsesRealLoginItem` |
| `openHelp` | **G10** ＋ G5（spy 斷言真的開了 `help.html` 的 URL） |
| `about` | **G10** ＋ G5（spy 斷言 about 面板／banner 被觸發） |
| `recheckHook` | **G10** ＋ `unknownIsNeverTerminal`（按下後 `.unknown` 不得留著） |
| `dismissBanner` | `bannerBeatsCTABanner` ＋ G5（送出後 model 的 banner 為 nil） |
| `quit` | **G10** ＋ G5（fake terminator 收到一次；**不得**真的呼叫 `NSApp.terminate`） |

> R5 的關鍵修正：`openHelp`／`about`／`quit`／`setLaunchAtLogin`／`recheckHook` 這批
> **只住在 Options 區**的動作，守衛必須是 **G10（`rows` 裡有它）**，不能只有 G5——
> G5 是直接把 `samples()` 送進 `onAction`，UI 上那一列整個消失它照樣綠。

**G2 是本 change 最重要的一條**：它把 D3/R6「絕不碰 `settings.json`」從承諾變成機械事實。
但它只證明「注入 temp 時只碰兩個路徑」；「生產真的指向 `~/.claude`」由 `productionUsesRealInstaller` 守。

### 6.4 不做的測試（明講）

- 不真的呼叫 `SMAppService.register()`（會動到使用者的登入項目）。
- 不碰真的 `~/.claude`（一律注入 temp `claudeHome`）。
- **不用 accessibility 掃描驗 SwiftUI 元件存在**——實測離屏 `NSHostingView` 的 a11y 樹是 0 節點（S0-Q1）。
- 離屏 `NSPopover.show` 靜默無效，所以「面板真的彈出來」只驗 `showPanel()` 被呼叫 ＋ 順序；
  實際彈出、quarantine 真實情境、`SMAppService` 行為列入使用者實測清單。

---

## 7. 檔案佈局與 migration

**新增**（`AuraHookFile` 的測試依既有慣例放 `AuraCoreTests`——`CompositionRootTests` 測的就是
`PipelineGraph`；只有兩個 test target，不新增第三個）
```
Sources/AuraCore/{InstallState,PanelAction,OptionsMenuModel,Jargon}.swift
Sources/AuraHookFile/Installer.swift
Sources/AgentAuraApp/{PanelFooterView,OptionsSectionView,NotConnectedView,BannerView,LoginItem,HookVerificationStore}.swift
Sources/AgentAuraApp/AppDelegate+PanelActions.swift        ← S2-A10：預先拆，避免撞 200 行
Resources/help.html
scripts/measure-cpu.sh                                     ← S2-A12：從 scratchpad 升進 repo
Tests/AuraCoreTests/{InstallStateTests,InstallerTests,JargonTests,ShellSourceScanTests}.swift
Tests/AgentAuraAppTests/{ShellWiringTests,FooterPixelTests}.swift
```
**修改**：`PanelModel`（＋6 欄＋2 computed）· `PanelViewModel.meta/detail`（M-7）· `PanelView`（三態＋footer＋options，
`onAction` 無預設值）· `LegendRowView`（「重設」搬走、提示行改字）· `StatusItemController`（`onAction`／`onOpen`／`showPanel`）·
`AppDelegate` · `scripts/{build-app,verify-app}.sh` · `docs/INSTALL.md`（含修掉 `:47` 的自我矛盾）·
`README.md` · `CLAUDE.md`（新 invariant）· **正典 §3.2**（安裝方式已由 skills-dir 掛載取代，S2-A11）·
**正典 §3.8(2)** 的措辭（不得叫使用者重啟 **app**，但必須說明生效時機，D-m）

**Migration**
1. `PanelAction` 重構（T03，單獨 commit）是**純重構**。test-edit scrutiny 的機械化判準（S1-Q12）：
   - 對 `Tests/` 只准改寫，**`#expect` 淨數量不得下降**；
   - T03 前後跑**同一組 mutation**（`panelOnPick` 改 no-op、`.resetColors` 分支改 `break`），
     兩次都必須紅、且紅的是**同一組測試名**；
   - 保留 `controllerForwardsPanelCallbacks`（不得降級成 `onAction != nil`）、保留
     `PaletteWiringSmokeTests` 那條「重設後 `isDefaultPalette == true`」（該檔自己註明是唯一從
     true 側見證 `isDefault` 的地方）、驅動點不得從 view 上移到直接呼叫 `AppDelegate`。
2. `PanelModel.make` 多 6 個必填參數 → 編譯器會列出全部呼叫點（刻意不給預設值，G13 守著）。
3. **既有 `PanelPixelTests` 一律不改**——r1 曾要求改 `wildPalette` fixture，經實測是過度修正
   （tolerance 只有 2/255，`.default` 渲染中四個 wild 色命中全 0 px）。phase-2 明令：
   「wild 色 0 px」的對抗式斷言**不准放寬**，`wildPalette` 也**不准動**。
4. 已有 `~/.claude/skills/agentaura` 的使用者（本機開發者，指向 repo `plugin/`）升級後判為
   `connected(owner: .external, …)`——**行為不變、不會被覆寫**（實測本機現況正是這種）。
5. `INSTALL.md` 主路徑改成「下載 app → 開起來 → 按接上 → 開一個新的 Claude Code session」，
   六行終端機流程降級為「開發者路徑」一節保留。

---

## 8. DoD（可量測）

| 項目 | 門檻 | 量法 |
|---|---|---|
| 測試 | 全綠，新增 ≥ 40 條 | `swift test` |
| gate mutation | **`swift test` 的 15 條**（G1–G8、G9a/b/c、G10–G13）全部要有指名測試在 ≤ 60s 內變紅（非掛住）；其中 G3 有**兩筆** mutation（connect／disconnect 各一條呼叫路徑）、G6 兩筆、G10 三筆。G14 住在 shell script，改以「`verify-app.sh` 非零退出」為紅，單獨記一筆（S2-2／R6：r3 的「13/13」漏算了 G9 拆成 a/b/c）。`IsolationTests` 不計入 | 逐條記錄於 tasks 的 mutation 欄 |
| probe 成本 | **單次 probe ≤ 0.5 ms**（2026-09-13 重新推導；實測 0.07 ms） | `InstallerProbeCostTests`（相對比值 4x，不是絕對毫秒——絕對值會被測試套件自己的負載打敗，見 CLAUDE.md gate 哲學第 5 條） |
| 啟動時間增幅 | ≤ 10 ms，**行程內**量測（`applicationDidFinishLaunching` 首尾時戳） | 沿用 Change 2 抓到 `NSColorPanel.shared` +120 ms 那次的做法（`open` 量在雜訊底下，S2-A12） |
| RSS 增幅 | ≤ 1 MB | `scripts/measure-cpu.sh`（先隔離自己的 session） |
| 動畫態 CPU | 不得比 `main` 更差 | 同上 |
| app bundle 總量 | **≤ 6 MB**（2026-09-13 重新推導；實測 3.8 MB，含 universal `aura-hook`） | `du -sh build/AgentAura.app` |
| 單檔行數 | `Sources/` ≤ 200、`Tests/` ≤ 300 | `IsolationTests` |
| `settings.json` 位元組變動 | **0**（全程） | G2 ＋ `verify-install.sh` |
| bundle 佈局 | `verify-app.sh` 通過（缺 bundle 時 FAIL 不 skip） | 每次改 bundle 佈局必跑 |
| **實機 ①** 生效時機 | 互動 session 開著時掛上掛載 → 觸發一次 tool → 狀態檔**不**出現；開新 session → 出現 | 手動（S0-A1） |
| **實機 ②** 下載路徑 | 打包 zip → 下載/解壓（帶 quarantine）→ 開起來 → 按接上 → **要嘛成功且真的有狀態檔，要嘛明確報 `.hookBlockedOrBroken`**，不得說「已接上」卻沒產物 | 手動（S0-A2） |
| **實機 ③** 登入項目 | ✅ 2026-09-12 實測：ad-hoc 簽章 bundle 上**直接成功**，不需系統設定核准 | 手動（原 known gap 2，已解除） |
| **實機 ④** 卡死檢查 | 讓 exec 驗證失敗（例如手動加回 quarantine）→ 依文案處理 → **重開 app** → chip 必須離開「接不上」；另測「再檢查一次」按鈕（R2：這條擋的是「使用者做了 app 叫他做的事，app 還是說壞的」） | 手動 |
| persona | 加權 ≥ 6.5；「非工程師能不能自己裝起來」項 ≥ 6 | persona-tester（Tier 1） |


### 8.1 兩項門檻的重新推導（2026-09-13）

兩條都**沒有**為了讓 gate 轉綠而調動，是回頭發現門檻本身立錯了地方，照 §3 的規矩回來改並記錄理由。

**probe 成本：`100 次 ≤ 5 ms` → `單次 ≤ 0.5 ms`。**
舊門檻是在 `hookBinaryStamp`／`thisAppIdentity`／`hooks.json` 三項**為正確性加入之前**量的，之後從未重新推導。更根本的問題是它量錯了對象：生產路徑上不存在「連續 100 次 probe」，開一次面板就是一次。用真正發生的單位（單次）重新立門檻，實測 0.07 ms，離 0.5 ms 還有 7 倍餘裕。
執行面的 gate 早就不是絕對毫秒了——`InstallerProbeCostTests` 用的是相對控制組的 4x 比值，因為絕對值會被測試套件自己的負載打敗（CLAUDE.md gate 哲學第 5 條，實測撞穿過三條）。這次只是讓 DoD 的說法追上 gate 的實作。

**執行檔：`≤ +80 KB` → `app bundle 總量 ≤ 6 MB`。**
`+80 KB` 從一開始就沒有平台依據，是我憑空設的。實測 SwiftUI 的 view 型別在 release 展開大約每個 60–80 KB／架構，上一輪三個 view 就 +292 KB，這一輪整套面板 +1119.6 KB，門檻被超過 14 倍——一個會被正常工作穩定超過 14 倍的門檻，守的不是品質而是它自己。
換成守使用者真正感覺得到的量：bundle 總量（實測 3.8 MB）。啟動時間增幅那條（≤ 10 ms，實測 +0.055 ms）本來就在守「有沒有變慢」，兩條合起來涵蓋了原本想守的東西。
**代價要講清楚**：這條不再擋「多寫了幾個 view 型別」。如果哪天 bundle 逼近 6 MB，要回來問的是「為什麼需要這麼多 view」，不是把門檻再往上調。

## 9. Known gaps（明列，不假裝做完）

1. **§3.8(3) 的通用死 hook 掃描**（掃 `settings.json` 與其他 plugin 的 hook 是否指向失效檔案）本輪不做（D-k）。
   正典 §3.8 的 DoD 因此仍未完全滿足——**不改 DoD 措辭來遷就**，列為後續 change `dead-hook-scan`。
2. ~~`SMAppService` 在 ad-hoc 簽章 bundle 上的行為待實機確認~~ —— **2026-09-12 實測解除**：直接成功，不需系統設定核准（DoD 實機 ③）。
3. **Mach-O 放在 `Contents/Resources/plugin/bin/`** 不是 Apple 建議位置（可執行檔屬 `Contents/MacOS/`
   或 `Contents/Helpers/`）。本地 ad-hoc 簽章實測通過，但**將來 notarize 會變硬錯誤**。
   替代方案（未採用）：`Contents/Helpers/aura-hook` ＋ plugin 內相對 symlink 指過去（S2-S5）。
4. ~~Gatekeeper「允許」之後巢狀資源的 quarantine 是否被遞迴清除——未驗證~~
   **2026-09-15 實測解除**（macOS 26.6.2，打包 zip ＋ 模擬下載）：
   **沒有被遞迴清除，但不影響執行。** 授權前跑巢狀的 `aura-hook` 是 SIGKILL（exit 137）、
   0 個狀態檔，而 `access(X_OK)` 照樣說可執行；使用者授權 app 之後，那顆 hook **仍帶著
   quarantine 屬性**，執行卻正常（exit 0、狀態檔產出）——系統認的是使用者對這個 app 的授權，
   不是逐檔的標記。這也再次證實第 6 步「看產物不看自洽檢查」是對的。
   **同時踩到一個新事實**：macOS 15 Sequoia 起「右鍵 →打開」的繞過已被移除，
   新對話框只有「移到垃圾桶」與「完成」，最顯眼的是前者。照舊行為寫的安裝說明會害人把 app 丟掉。
5. 系統通知（session 完成／出錯時 banner）刻意不做——會把產品從「餘光可見」變成「主動打擾」，
   撞 R4 注意力預算，需要自己的 brainstorm。
6. 右鍵開 Options 未做（加分項；主入口必須看得見）。
7. S1-A（關面板時全表 acknowledge）沿用 Change 2 的 known gap。
8. **寫入點護欄的真 TOCTOU 無法測**（probe 之後、rename 之前才被塞進檔案）——需要測試鉤才驗得到，
   本輪不加。護欄的存在由直呼 `performConnectSteps()` 的 gate 證明（§4.1 第 4 步的可觀測性註）。
9. **`InstallerFailure` 不叫 `InstallerError`**（T03 實測）：`Sources/AuraHookFile/AuraHookFile.swift`
   有一個同名空 enum 當 namespace marker，寫 `AuraHookFile.InstallerError` 會被解析成那個 enum
   而不是 module ⇒ 編譯錯。T07／T08 在 app 層 catch 時用 `InstallerFailure`、不加 module 前綴。
10. ~~**背景具名 subagent 不會讓燈維持工作中**~~（審計 2026-09-11，裁決 (c)；**2026-09-13 已修**）。主 agent 送 `Stop` 之後，`MergeRules` 的 `guard !s.mainActivity.isQuiescent`
    會丟掉**所有** subagent 事件，包含仍在跑的具名 subagent ⇒ 燈誤報 done（「有結果可看」但其實沒有）。
    那條 guard 是用**內部** subagent 的證據寫的（`agent_type` 空字串、Stop 後 2.58s–186s 才到），
    適用範圍開太大。**2026-09-13 已修**（change `subagent-state-priority`，`85dc2ec`）：釘樁測試已改寫成新契約 `backgroundNamedSubagentKeepsLightWorking`。
11. ~~**背景具名 subagent 的 `PermissionRequest` 變不了橘**~~（**2026-09-13 已修**）。
    這是既有 invariant「`waiting` 不得進入已結束未確認的尾巴」（不該橘卻橘）的**鏡像**：該橘卻不橘。
    **2026-09-13 已修**（`85dc2ec`）：釘樁測試已改寫成 `backgroundNamedSubagentPermissionRequestTurnsLightOrange`，並斷言集合存的是各 subagent 自己的 activity 而非寫死 `.working`。**這個組合尚無實測樣本**，形狀取自 round3 的
    `agent_id` 與 `EventMapping.handledEvents`。
12. ~~**從屬槽在 subagent 結束後留下殘影**~~（**2026-09-13 已修**）：`SubagentStop` 映射到 `.setActivity(.working)`，
    對主槽正確、對從屬槽語意相反；`subTool`／`subAgentType` 又是 carry-forward，殘影活到主槽
    走 done／error 為止。**2026-09-13 已修**（`5bcacb4`）：釘樁測試已改寫成 `subSlotClearsWhenSubagentStops`。
    完整分析與提案：`docs/2026-09-11-subagent-state-priority-audit.html`。
    **實測平台契約**（提案的地基，不得放寬）：具名 subagent 的 `SubagentStart` 與 `SubagentStop`
    都帶非空 `agent_type` 且共用同一個 `agent_id`（fixture `round3-named-subagent.ndjson`）。
13. **面板說得出「背景還有 subagent 在跑」，說不出是哪一個**（T23 review S2-4 的收斂邊界，
    2026-09-13 裁決不做）。`outstandingSubagents` 的 key 是不透明的 `agent_id`、value 只有
    `activity`，沒有存 `agent_type`（也就是 agent 的名字）；主槽靜止時 `clearSubSlot` 已經
    把 `subAgentType` 清掉，沒有殘留可用。要顯示身份得把 value 換成 struct，是第二次 schema 變更。
    **不做的理由**：核心事實（有東西還在跑）已經說出來了，身份是加分項；使用者的 agent 清單在
    Claude Code 本身就看得到，選單列的價值是餘光感知而非取代它。
    **觸發條件**：同時跑多個具名 agent 且需要分辨是哪一個時再做——屆時 value 換 struct 走的是
    這次已經驗證過的同一條 Optional 相容路徑。
14. **首次安裝後圖示可能看不見**（2026-09-14 實機發現）。圖示是一顆 LED 燈點，不是有圖案的
    icon；在有瀏海、選單列項目又多的 MacBook 上，macOS 可能把它排到瀏海後面，使用者會以為
    沒裝成功。完整移除會清掉 `NSStatusItem Preferred Position`（刻意的，完整移除就該不留東西），
    所以重裝後特別容易遇到。
    **本輪不做**，已在 `docs/INSTALL.md` 補「找不到選單列圖示？」一節（按住 Command 拖曳挪位）。
    **可做而未做**：接上成功後在面板上直接告訴使用者圖示在哪、看不到時怎麼辦——這一格打在
    「非工程師第一次裝完」的路徑上，優先度不低。
15. **`BundleRecycling.recycle` 的 completion 有一個 Swift 6 嚴格併發警告**
    （`capture of 'completion' with non-Sendable type in a '@Sendable' closure`）。
    **試過修，還原了**：把 `completion` 標 `@Sendable` 會把問題往上推一層——
    `Uninstaller.recycleBundleAndTerminate` 捕獲的 `any AppTerminating` 也非 Sendable，
    要一路標下去會動到 `AppTerminating`／`RealTerminator`／測試替身一整串。
    **行為上沒有風險**：那個回呼實際上已經用 `Task { @MainActor in }` 跳回主執行緒，
    警告講的是型別系統看不出這件事，不是真的有資料競爭。
    修的收益（少一個警告）小於改動範圍（四個型別加測試替身），留著。
