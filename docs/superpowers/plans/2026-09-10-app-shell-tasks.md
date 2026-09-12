# Change 3「操作層」實作計畫（app-shell）

> spec：`docs/superpowers/specs/2026-09-10-app-shell-design.md`（**r5**）
> 分支：`change/app-shell`　Tier：**1**（動 `Sources/AgentAuraApp/**` → integrator 綠後派 persona-tester）
> 節號引用一律指 r4 的 spec。

## 0. 給每個 implementer 的共同規則

- **一 task 一 commit**（必要時 refactor 拆第二個，但屬同一 task）。動工前 `git branch --show-current` 確認不在 `main`。
- **TDD**：先 RED（理由要正確——不是編譯錯，是斷言失敗），再 GREEN，再 refactor。
- **每條 gate 都要 mutation 紀錄**：把生產碼改壞（完整字串取代）→ 先確認**編譯成功** → 指名的測試必須在 **≤ 60s 內變紅（不是掛住）** → 還原。紀錄寫進 task 的完成報告：`mutation / 指名測試 / 秒數`。
- **單檔上限**：`Sources/` 200 行、`Tests/` 300 行（`IsolationTests` 從磁碟推導，新檔自動納入）。
- **離屏渲染一律用 T01 的 helper**：釘 `NSAppearance(named: .aqua)`（深色另渲一次）＋ 前提斷言（非白像素 > 2000）。實測依據：不釘 appearance 在 Dark 機器渲淺底，文字 0 px。
- **禁止**：`--amend` 已 push 的 commit、`--no-verify`、`git reset --hard|checkout .|clean -f` 清未 commit 變更、在測試裡碰真的 `~/.claude` 或真的 `SMAppService.register()`、`fatalError`（會殺掉 `swiftpm-testing-helper`）。
- **既有測試不得弱化**：`#expect` 淨數量不得下降；改寫既有斷言要在報告裡逐條列出「改前／改後／測的是不是同一件事」。

## 1. 任務與依賴

| # | Task | 產出 | 依賴 | gates |
|---|---|---|---|---|
| T01 | 測試底座（**零生產碼**） | 對抗式 double、composition-root smoke 骨架、離屏渲染 helper、`LinkObservation` fixture 全覆蓋 | — | 全部 RED 且理由正確 |
| T02 | `InstallState` ＋ `affordance`（AuraCore 純邏輯） | §3.1／§3.1.1 | T01 | G1 |
| T03 | `Installer`（AuraHookFile） | §4.1 probe／connect／disconnect | T02 | G2、G3、G4 |
| T04 | `PanelAction` 重構（**純重構**） | §3.2；`onPickColor`／`onResetColors` 併入 `onAction` | T01 | 既有測試改寫（不得弱化） |
| T05 | `Jargon` ＋ `meta`／`detail` 文案 | §3.4 | T01 | G9a、G9b、G9c |
| T06 | `PanelModel` 擴充 ＋ `OptionsMenuModel` | §3.3；banner 優先序 | T02、T04 | G8(a)、G10、G13 |
| T07 | View 層 ＋ `LoginItem` ＋ `HookVerificationStore` | footer／options／notConnected／banner | T06 | G6、G7、G8(b)(c)、G11 |
| T08 | `AppDelegate` 接線 | 窮盡 switch、首啟順序、背景驗證 | T03、T07 | G5、G12、§6.2 全部 |
| T09 | bundle ／ scripts ／ 文件 | `build-app.sh`／`verify-app.sh`／`help.html`／`INSTALL`／`README`／`CLAUDE.md`／正典回寫 | T01 | G14 |
| T10 | 整合 ＋ DoD 量測 | §8 全表 ＋ 使用者實機清單 | 全部 | — |

### 並行策略（有 agent 在跑時，主 session 不在共享目錄作業）

```
wave 1: T01                          （單獨，擋住所有人）
wave 2: T02 ∥ T05 ∥ T09              （三個不同 module／不同檔案，各自 worktree）
wave 3: T03（需 T02）∥ T04           （T04 動 app 層既有檔，與 T03 無交集）
wave 4: T06 → wave 5: T07 → wave 6: T08
wave 7: T10
```
衝突檔以 `git worktree add` 隔離，作業完 merge 回 `change/app-shell`。

---

## T01 測試底座（零生產碼）

**目標**：讓後面每一條 gate 都不可能生下來就是綠的。**這個 task 不寫任何生產碼**，
交付時全部測試是 RED，且每條 RED 的理由必須是「斷言失敗」或「型別還不存在」，
不能是「harness 自己壞了」。

1. **`LinkObservation` fixture 全覆蓋**（§6.1）。維度：
   - `entryType` 四值
   - `resolveFailure`：`nil` / `.notFound`(errno 2) / `.loop`(errno 62) / `.permissionDenied` / `.other`
     —— **斷鏈與迴圈必須分開**（r3 N3：r2 用「identity 是不是 nil」分不開，最常見的失敗因此拿到說謊的文案）
   - `targetIsDirectory`、`hooksJSONExists`、`hookBinaryExists`、`hookBinaryExecutable`
   - `hookBinaryStamp` 有／無 × 憑證相符／不符（identity 或 mtime 任一不同都算不符）
     —— **`verification` 不是 `LinkObservation` 的欄位**，是 `from(_:verification:)` 的第二個參數
     （T01 必辦 ④：一次 stat、一個所有者。r4 的兩次 stat 會生出「`.verified` 但從沒驗過這一份」）
   - `Verification` 四值（含 `.inFlight`）作為 `from` 的第二個參數逐一組合
   - **`skills` 自己是指到 claudeHome 外的 symlink**（T01 必辦 ②：實測寫入會落在外面，
     而 claudeHome 的樹完全沒變 ⇒ 舊寫法的 G2 全綠）
   - `thisAppPluginIdentity == nil`（bundle 不完整／`swift run`／**`swift test` 就是這一格**）× `rawLinkTarget` 有／無
     —— 驗 `MountOwner` 三值各自可達（r3 R4：`Bool` 公式在測試環境會給出與生產**反向**的值）
   - 二進位存在且有 x 位**但 exec 會被殺**（只有 exec 驗證抓得到）
2. **對抗式 double**：
   - `FakeLoginItem`：`isSupported == false`、`set` 丟 `.requiresApproval`、`isEnabled` 與剛設定的值**不一致**
   - `FakeInstaller`：① `connect()` 成功但 `probe()` 仍回 `notConnected`；② probe 說 `connected` 但 exec 驗證失敗；③ **spawn 本身丟錯**（`Process.run()` throw）
   - `FakeVerificationStore`：可設定憑證相符／不符／讀取丟錯
   - `FakeTerminator`（`quit` 用；**不得**真的呼叫 `NSApp.terminate`）
3. **離屏渲染 helper**（S0-Q2）：`renderPinned(_ view:, appearance:, canvas:)` —— 釘
   `NSAppearance(named:)`、固定畫布、回 `Bitmap`，並內建**前提斷言**（非白像素 > 2000）。
   G6／G8 一律經它，不准各測試自己決定 appearance。
4. **差異渲染 helper**：`differingPixels(a:b:)`，同尺寸才可比；附一條自我測試（同內容 → 0）。
5. **composition-root smoke 骨架**：`SpyRenderer` 擴充 `onAction`／`showPanel()`／呼叫順序記錄。

6. **`affordanceMatchesTable`**（T01 必辦 ①）：`Reason.allCases × MountOwner.allCases`
   **24 格** ＋ 三個頂層 case，逐格比對 spec §3.1.1 的表。定義域是這個**乘積**，
   不是「狀態機目前可達的那些」。實測依據：`Swift` 對「帶 payload 的 enum 互相覆蓋」
   **完全不會報**（零 error 零 warning），兩種壞寫法分別有 6 格／2 格錯，
   這條 gate 是唯一同時抓得到的東西。
7. **G3(a) 的斷言形狀**（T01 必辦 ③）：`Optional<Data>` 相等 ＋ `lstat` 型別相等；
   **不得用 `try Data(contentsOf:)`**（clobber 後路徑是指向目錄的 symlink，`try` 會丟錯
   而顯示成「拋出未預期錯誤」，不是斷言失敗）。
8. **`verificationStoreIsInjected` 的掃描形狀**（T01 必辦 ⑤）：掃 `UserDefaults(`／`UserDefaults.`
   （帶標點——掃「字樣」會被註解命中，實測 grep 回 1 而那一個全在註解裡）＋ 檔數防空跑
   ＋ 暫存目錄放一個真的用了 `UserDefaults.standard` 的 probe 當正向對照。

**驗收**：`swift test` 全跑得完（不掛住），新增測試全 RED，逐條說明 RED 的理由。

**T01 五條必辦（reviewer 定向確認的產出，動到簽章的兩條必須在寫 fixture 之前定案）**：
① `affordanceMatchesTable` 24 格 ② G2 改對 `realpath(skills)` 取 snapshot ＋ 該 fixture
③ G3(a) 用 `Optional<Data>` ④ `probe()` → `hookBinaryStamp` → `store.verification(for:)`
→ `from(_:verification:)` ⑤ store 的 `inFlight` 合流 guard ＋ 掃描形狀。

---

## T02 `InstallState` ＋ `affordance`

**目標**：§3.1 的判定順序（9 步）與 §3.1.1 的 `affordance`，純函式、零 I/O。

- `InstallState.from(_:)` 對 `resolveFailure` 與 `Reason` **窮盡 switch**，不得有 `default`。
- `affordance` **必須寫成對 `Reason` 窮盡**、具體列在前（§3.1.1）。
  漏掉一個 `Reason` 要是**編譯錯誤**，不是 unreachable 警告——`Package.swift` 沒有
  `-warnings-as-errors`，靠警告等於沒守（S0-1(i) 的根因）。
- `MountOwner` 三值；`.occupiedByFile`／`.occupiedByDirectory` 一律 `owner: .unknown`。
- chip 文字／tone 由 `InstallState` 窮盡推導；`connected` 的 chip 對 `(owner, verified)` **逐格**
  （§3.3；`.inFlight` 與 `.unknown` 必須不同文案）。

**gates**：G1（狀態集合由 `Reason.allCases × MountOwner.allCases` ＋ connected 的
`MountOwner × Verification` ＋ 兩個頂層 case 推導，**不寫數字**）。
G1 要註明「symlink → 普通檔案」與「是目錄但缺 `hooks.json`」**必須落同一個 `.notAPlugin`**。

**mutation**：把 `hookNotExecutable` 併進 `connected` → G1 紅。
額外一筆：把 `affordance` 的 `occupiedByFile` 那列排到 `broken(_, owner:)` 之後 → G1 的
affordance 斷言必須紅（這是 S0-1 的回歸 mutation，**必做**）。

---

## T03 `Installer`

**目標**：§4.1 全部，含三層護欄與 exec 驗證。

- `probe()` 回 `LinkObservation`（含 `hookBinaryStamp`，**只 stat 一次**）；
  `verification` 由 app 層的 store 算好，當 `InstallState.from(_:verification:)` 的第二個參數
  （T01 必辦 ④）。`Sources/AuraHookFile/` **不得出現 `UserDefaults(`／`UserDefaults.`**。
- `Installer` 宣告 **`Sendable`**（欄位只有 URL／Bool／`@Sendable` 閉包），背景只做 exec 回 `Bool`。
- `connect(force:translocated:inDownloads:)`：guard 0 → affordance 路由 → bundle 檢查 →
  `mkdir skills`（**只這一層**，`~/.claude` 不存在時拒絕）→ **第 4 步寫入點 `lstat` 只准
  absent／`S_IFLNK`** → 原子 `rename` → probe → **exec 驗證看產物** → 寫憑證。
- `replaceExternalMount` **就是 `connect(force: true, …)`**，同一段實作。
- `disconnect()`：只有 `lstat` 回 `S_IFLNK` 才 unlink；**不刪 `~/.agentaura/`、不呼叫 `acknowledgeAll()`**。
- exec 驗證：`AGENTAURA_ROOT=<temp>` ＋ 合成 payload ＋ **單調時鐘**有界等待；
  失敗分三種寫回值（產物沒出現／逾時／spawn 丟錯），**任何一種都要寫憑證**（`unknown` 不得為終態）。
- `removexattr` 只作用在 `<target>/bin/aura-hook` **這一顆**（實測：只清 binary 就夠，目錄仍帶隔離也能跑；
  **不要改成 `-r`**）；bundle 唯讀時會 EPERM，所以「看產物」那條路徑必須保留。

**gates**：
- **G2**（最重要）：connect＋disconnect 前後對 temp `claudeHome` **整棵樹**比對
  `(相對路徑, 型別, mode, size, md5 或 symlink 目標)` 元組集合；容許差異集合**恰為**
  `{skills（若原不存在）, skills/agentaura}`；另植入 `settings.json` 斷言元組完全不變。
- **G3**（兩條呼叫路徑，S0-1(iii)）：(a) `connect` 對普通檔案／實體目錄／有效掛載／external 且壞掉
  都必須 throw，**且普通檔案的內容位元組完全不變**；(b) `disconnect` 對普通檔案／實體目錄必須拒絕；
  (c) `replaceExternalMount` 在 translocated／`~/Downloads` 時也必須拒絕。
- **G4**：(a) `FakeInstaller` 讓 exec 不產生產物 → `connect` 必 throw；
  (b) 正常路徑真的 spawn **SwiftPM 產物**（`AuraHookCLITests.binaryURL()`）確認會產出
  —— bundle 內那份不在 `swift test` 環境裡，交給 G14 ＋ DoD 實機②。

**mutation**：G2 → 讓 `connect` 順手寫一個 `settings.json.bak`；
G3 → ① 拿掉 `disconnect` 的 `S_IFLNK` 檢查（必須紅在 (b)）② **拿掉第 4 步寫入點的型別檢查
（必須紅在 (a) 的內容比對）**；G4 → 刪掉第 6 步。

---

## T04 `PanelAction` 重構（純重構）

**目標**：§3.2。`IconRendering` 的 `onPickColor`／`onResetColors` 併入單一
`onAction: ((PanelAction) -> Void)`（**不給預設值**）；`PanelView` 的動作閉包同樣不給預設值。
加 `PanelActionKind: String, CaseIterable` ＋ `kind`（窮盡）＋ `samples(_:) -> [PanelAction]`（窮盡）。

**test-edit scrutiny（機械化判準，S1-Q12）**：
- 對 `Tests/` 只准改寫，**`#expect` 淨數量不得下降**；
- **本 task 前後跑同一組 mutation**（`panelOnPick` 改 no-op、`.resetColors` 分支改 `break`），
  兩次都必須紅、且紅的是**同一組測試名**；
- 必須保留：`PaletteWiringSmokeTests.controllerForwardsPanelCallbacks`（不得降級成 `onAction != nil`）、
  「重設後 `isDefaultPalette == true`」（該檔唯一從 true 側見證 `isDefault` 的地方）；
- 驅動點**不得**從 view 上移到直接呼叫 `AppDelegate`（會跳過 view→controller 那一跳）。

**新增 gate**：`panelViewForwardsAction`（建真的 `PanelView` → 觸發 → 斷言閉包收到）。

---

## T05 `Jargon` ＋ 文案

**目標**：§3.4。映射用**字典**（gate 迭代它當來源集合）；`model` 照規則表實作，**九列反例全綠**。
呼叫點是 `PanelViewModel.meta(for:)`。`detail` 的英文字改中文。圖例提示行改字。

**gates**：G9a（迭代字典本身，每個 key 的輸出 ≠ key；未知值原樣回傳）、
G9b（**外部錨點**：掃 `Tests/AuraCoreTests/Fixtures/*.ndjson` 抽出所有出現過的
`permission_mode`／`effort.level`／`model`，每一個都要有人話對應——**現在就會抓到 `auto`**）、
G9c（**wired**：用 fixture 真值建 `SessionState` → `rows.first!.meta` 不含任何原始代碼字）。

**mutation**：G9a → 讓 `effort` 直接回傳 raw；G9b → 從字典拿掉 `auto`；G9c → `meta` 改回不套 `Jargon`。

---

## T06 `PanelModel` 擴充 ＋ `OptionsMenuModel`

**目標**：§3.3 六個新欄位 ＋ 兩個 computed；`make(...)` 新參數**一律不給預設值**（只有 `now:` 例外）。
`OptionsMenuModel.rows(...) -> [OptionsRow]`（每列帶 `action`）＋ `nonMenuKinds`
**字面集合** `{pickColor, resetColors, dismissBanner, connect, replaceExternalMount}`。
banner 與 CTA 的優先序照 §3.3（`banner != nil` 時 `.banner` 樣式降級為 `.none`）。

**gates**：G8(a)（model 層對每種狀態窮盡斷言 chip 文字／`showsConnectCTA`／CTA 文案／`connectCTAStyle`；
oracle 是 §3.1.1 的 affordance→CTA 表與 §3.3 的 chip 表）、
G10（**`nonMenuKinds` 必須恰好等於那個字面集合**；其餘 Kind 各恰好出現一次）、
G13（來源推導：`PanelModel.swift` 的 `make(` 簽章除 `now:` 外不得出現 `= `）、
`bannerBeatsCTABanner`。

**mutation**：G10 → ① rows 拿掉「離開」② `resetColors` 搬家時掉了 ③ 把 `quit` 塞進 `nonMenuKinds`；
G13 → 給 `install` 一個預設值；G8(a) → 讓 `showsConnectCTA` 在 `.explainOnly` 回 true。

---

## T07 View 層 ＋ `LoginItem` ＋ `HookVerificationStore`

**目標**：`PanelFooterView`（chip ＋ 版本 ＋ Options ⌄）、`OptionsSectionView`（只從
`OptionsMenuModel.rows` 取列）、`NotConnectedView`、`BannerView`；
`LoginItem`（`SMAppService`，三種失敗都處理，translocated／Downloads 拒絕註冊）；
`HookVerificationStore`（`@MainActor` ＋ 注入 `UserDefaults`，憑證用 `st_mtimespec`，
`verification(for: stamp)` ＋ `inFlight` 合流 guard——`@MainActor` 所以檢查與設定原子、不需要鎖；
`inFlight != nil` 就是 `.inFlight`，序列化與「檢查中…」的誠實性是同一個機制）。

**gates**：G6（**一律以 `wildPalette` 渲**；兩種狀態各 ≥ 100 px；版本差異渲染 fixture
固定 `v0.1.0` vs `v9.9.9`、門檻 ≥ 300、同內容 == 0）、G7（`preferredContentSize.height`
展開後變高，**快照比對**）、G8(b)（固定畫布 380×320 pt、門檻 > 20,000）、G8(c)（正向對照：
connected ＋ 有 session → 列真的畫得出來）、G11（`ok`／`warn` 與 `wildPalette` 五色 delta > 0.063）、
`verificationStoreIsInjected`（含掃 `Sources/AuraHookFile/` 不得出現 `UserDefaults`）。

**mutation**：G6 → ① chip 色固定綠 ② 版本不進 view；G7 → `optionsExpanded` 不影響 view；
G8(b) → CTA 在 `connected` 也顯示；G11 → warn 改成與 wild waiting 相差 < 0.063 的黃。

---

## T08 `AppDelegate` 接線

**目標**：`AppDelegate+PanelActions.swift`（**預先拆檔**，避免撞 200 行）消化 `PanelAction`
的窮盡 switch；`IconRendering` 加 `onOpen`（**只准 probe ＋ `setPanel`，不得 acknowledge**）
與 `showPanel()`；首次啟動順序 `attachPopover → setPanel(真實狀態) → showPanel`；
啟動後背景 exec 驗證（**僅當 `verification != .verified`**）→ `await MainActor.run { store.write }`。

**gates**：G5（`allCases.flatMap(samples)` 逐一送，含 `setLaunchAtLogin` 的 true／false）、
G12（來源推導：`Sources/AgentAuraApp/` 內 `.acknowledgeAll(` 恰 1 個命中且在 `AppDelegate.swift`，
＋ 檔數防空跑 ＋ 暫存 probe 正向對照）、
`panelActionsAreWired`／`panelViewForwardsAction`／`productionUsesRealLoginItem`／
`productionUsesRealInstaller`／`panelReflectsInstallState`／`firstRunOpensPanelOnce`／
`firstRunOrdering`／`openPanelReprobesWithoutAcknowledging`／`disconnectDoesNotAcknowledge`／
`blockedSurvivesReprobeAndRestart`／`launchVerifiesUnlessAlreadyVerified`／`unknownIsNeverTerminal`／
`affordanceRoutesConnect`。

**mutation**：G5 → 某個 case 改 `break`；只接 `setLaunchAtLogin(true)`；
G12 → 在 disconnect 加回 `.acknowledgeAll()`；
`firstRunOrdering` → 把 `showPanel()` 移到 `attachPopover()` 之前（Change 2 實測會 NSException 殺行程）。

---

## T09 bundle ／ scripts ／ 文件

- `build-app.sh`：複製 `plugin/` 進 `Contents/Resources/plugin/`，缺 `plugin/bin/aura-hook` **大聲失敗**。
- `verify-app.sh`：對真 bundle 斷言三檔存在、`aura-hook` 可執行、`lipo -archs` 雙架構；
  **缺 bundle 時 FAIL 不是 skip**。
- `Resources/help.html`：四燈意思／八顆燈／改色／hook 是什麼／生效時機／移除／常見問題
  （含「App 在 Downloads 或 build/ 下請先搬進『應用程式』」）。
- `scripts/measure-cpu.sh`：從 scratchpad 升進 repo。
- 文件：`INSTALL.md` 主路徑改「下載 → 開起來 → 按接上 → **開一個新的 Claude Code session**」，
  終端機流程降級為「開發者路徑」；**修掉 `INSTALL.md:47` 那句自我矛盾的「立即生效（已實測確認）」**；
  `README`；`CLAUDE.md` 新 invariant（只准碰 `~/.claude/skills/agentaura`）；
  **正典 §3.2**（安裝方式已由 skills-dir 掛載取代）與 **§3.8(2)** 措辭（不得叫使用者重啟 **app**，
  但必須說明生效時機）。

**gate**：G14（`verify-app.sh` 非零退出為紅）。**mutation**：拿掉 `build-app.sh` 的複製步驟。

---

## T10 整合 ＋ DoD

跑 §8 全表：`swift test` 全綠、15 條 `swift test` gate 的 mutation 帳（G3 兩筆、G6 兩筆、G10 三筆）
＋ G14 一筆、probe 成本（100 次 ≤ 5 ms）、啟動時間**行程內**量測（≤ 10 ms）、RSS（≤ 1 MB）、
動畫態 CPU 不得比 `main` 差、執行檔 ≤ +80 KB、`verify-install.sh`、`claude plugin validate --strict`。
產出使用者實機清單①–④（生效時機／下載路徑 quarantine／`SMAppService`／卡死檢查）。
Tier 1 → integrator 綠後派 persona-tester。

## 2. 已知風險（開工前就知道，不是驚喜）

1. `SMAppService` 在 ad-hoc 簽章 bundle 上的行為未驗（DoD 實機③）。
2. Gatekeeper「允許」之後巢狀資源的 quarantine 是否遞迴清除——未驗證（正是「看產物」必須保留的理由）。
3. `Contents/Resources/plugin/bin/aura-hook` 不是 Apple 建議的可執行檔位置，將來 notarize 會變硬錯誤。
4. §3.8(3) 通用死 hook 掃描本輪不做（D-k），正典 §3.8 的 DoD 仍未完全滿足——**不改 DoD 措辭來遷就**。
