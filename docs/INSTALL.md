# 安裝 AgentAura

## 需求

- macOS 13 或以上
- Claude Code

（開發者路徑另外需要 Swift 6 工具鏈，見下方。）

## 安裝

大部分使用者不需要碰終端機：

1. 準備好 `AgentAura.app`（目前還沒有現成的下載版本，請先照下方「開發者路徑」建置一份；
   之後有 release 版本會直接提供下載）。
2. 把 `AgentAura.app` 拖進「應用程式」資料夾。**不要**留在「下載項目」或專案的
   `build/` 底下——那些位置的 App 隨時可能被搬走、或被系統當暫存清掉，接上之後
   容易莫名其妙又斷掉。
3. 打開 `AgentAura.app`。
4. 面板裡按「接上」。這一步只會建立一個指到這個 App 的掛載
   （`~/.claude/skills/agentaura`），**不會更動 Claude Code 既有的任何設定**。
5. **開一個新的 Claude Code session**（已經開著的視窗不會自動生效，見下一節）。

要開機自動啟動：在面板的 Options 裡打開「登入時啟動」。

不熟悉這些名詞的話，App 裡按「說明」會開一份離線的白話文件（`help.html`），
涵蓋燈號意思、hook 是什麼、常見問題。

## 找不到選單列圖示？

AgentAura 的圖示是一顆小小的 LED 燈點，不是有圖案的 icon。裝好之後如果選單列上看不到：

1. **先確認它真的在跑**：`pgrep -fl AgentAura.app`。有輸出就代表 App 正常，只是圖示看不見。
2. **按住 Command 鍵拖曳**選單列上的其他圖示，把空間挪出來，圖示就會出現。
3. 有瀏海的 MacBook（14"／16" Pro）特別容易遇到——選單列項目一多，新加入的圖示會被排到
   瀏海後面，完全看不到也點不到。

**已知情況（2026-09-14 實測）**：跑過「完整移除」之後再重裝，圖示的位置偏好
（`NSStatusItem Preferred Position`）也會一併被清掉——那是刻意的，完整移除就該不留東西——
所以 macOS 會重新決定位置，有可能就放到瀏海後面。這時照上面第 2 步拖一下即可。

## 什麼時候生效

按「接上」之後，**要從下一個新開的 Claude Code session 起才會生效**——skills-dir
的 plugin 在 session 啟動時載入，已在執行中的 session 不會中途載入新 plugin
（`INSTALL.md` 本節、`verify-install.sh` 的失敗訊息、正典 §10 皆以此為準）。

這裡有兩件容易混淆的事，分開講清楚：

- **新增一個 plugin 掛載**（第一次接上，或掛載被移除後重新接上）：
  **需要新 session 才會生效，已實測確認**。
- **已載入的 plugin 的 `hooks.json` 內容之後又被改動**（例如開發時改了 hook
  邏輯、重新跑 `build-plugin.sh`）：對已經在跑的 session 可能立即生效，
  但**這件事本身未經量測**，不要當作保證，也不要拿來反駁上一條。

接上完成不會、也不需要叫你重開 `AgentAura.app` 這個 App 本身。

## 安裝後 AgentAura 沒反應？先看 `/plugin`

在 Claude Code 裡輸入 `/plugin`，找 `agentaura` 那一項。如果看到
`Failed to load hooks from .../hooks.json`，那代表**整份 hook 設定被拒絕**，
不是某一條失效——AgentAura 會完全不運作，而選單列上看起來一切正常。

**成因是 Claude Code 版本落差**：我們註冊的某個 hook event 在你的版本裡不存在，
而平台對 `hooks.json` 是**全有全無**地解析——一個不認得的鍵就讓整份檔案失敗，
其餘合法的事件一起陪葬。

**處置：把 Claude Code 更新到最新版。** 錯誤訊息裡會列出你的版本認得的完整 event 清單，
拿它跟 `plugin/hooks/hooks.json` 註冊的清單比對，就知道差在哪一個。

> **給維護者的注意事項**：`claude plugin validate --strict` 在**你自己這台**通過，
> 不代表別人的 runtime 接受。實測（2026-09-15，Claude Code 2.1.271）：本機 validator
> 對未知 event 只給 warning 說「entry ignored at runtime」，但**別人的 runtime 是直接
> 拒絕整份檔案**。新增 hook event 時，這個寬容度差異要納入考量。

## 從別人給的 zip 安裝（ad-hoc 簽章）

目前沒有正式簽章與公證的版本，所以第一次開啟**一定**會被 Gatekeeper 擋。那是預期行為，
不是檔案壞掉。

1. 解壓後把 `AgentAura.app` 拖進「應用程式」。
2. 雙擊，會跳出 **「Apple 無法驗證『AgentAura.app』沒有惡意軟體」**。
   **按「完成」，不要按「移到垃圾桶」。**
3. 打開 **系統設定 → 隱私權與安全性**，往下捲到 **安全性** 區塊，
   會看到「已封鎖 AgentAura.app 以保護你的 Mac」與 **「強制打開」** 按鈕。
   按它，用 Touch ID 或密碼驗證。
4. 回去再開一次 app。
5. 面板裡按「接上」，然後**開一個新的 Claude Code session**。

> **⚠️ macOS 15 Sequoia 起，「右鍵 →打開」這個做法已經沒有了。**
> 舊文章教的那招在新系統上不存在——新版對話框只有「移到垃圾桶」與「完成」兩個按鈕，
> 而且**最顯眼的粉紅色按鈕是「移到垃圾桶」**。2026-09-15 在 macOS 26.6.2 上實機踩到：
> 照舊行為寫的說明會讓人卡死在第一步，甚至直接把 app 丟掉。

**為什麼會這樣**：這份 app 只有 ad-hoc 簽章，沒有 Apple Developer ID、沒有公證。
要讓使用者「下載解壓就能開、完全不跳警告」，需要 Apple Developer Program（年費 99 美元）
做 Developer ID 簽章與公證。

**授權之後 hook 能正常跑嗎？能。** 2026-09-15 實測：解壓後那顆 `aura-hook` 執行檔會繼承
quarantine 屬性，此時直接執行會被 **SIGKILL（exit 137）**、產不出狀態檔，
而 `access(X_OK)` 照樣回報「可執行」——所以驗收一律看產物、不看權限位元。
使用者授權 app 之後，那顆 hook **仍然帶著 quarantine 屬性**，但執行正常（exit 0、狀態檔產出）：
系統認的是使用者對這個 app 的授權，不是逐檔的標記。

## 開發者路徑

給要改程式碼、或目前還沒有現成下載版本可用的人：

```bash
git clone <repo> && cd AgentAura
./scripts/build-plugin.sh                            # 建置 universal aura-hook 到 plugin/bin/
claude plugin validate --strict ./plugin             # 官方 validator，零 error 零 warning
ln -sfn "$PWD/plugin" ~/.claude/skills/agentaura     # 掛載（settings.json 零改動）
./scripts/verify-install.sh                          # 驗證 hook 鏈路

./scripts/build-app.sh                               # 組出 build/AgentAura.app（含 plugin/ bundle 化）
./scripts/verify-app.sh                               # 實機啟動驗收
open build/AgentAura.app                             # 開始使用
```

> 這條路徑需要 Swift 6 工具鏈（`xcode-select --install` 或完整 Xcode）。

> 要開機自動啟動：把 `build/AgentAura.app` 拖進「系統設定 → 一般 → 登入項目」，
> 或用 App 內建的開關。

> **為什麼用 `~/.claude/skills/`，而不是 marketplace：**
>
> `claude plugin install` **只從 marketplace 安裝**（`--help`：「Install a plugin
> from available marketplaces」），本地安裝要先 `claude plugin marketplace add <path>`。
> **但那會寫 `~/.claude/settings.json`** —— 實測 `marketplace add` 在
> `extraKnownMarketplaces` 裡加一筆 `agentaura → directory /path/to/repo`，
> **直接違反 D3/R6「AgentAura 從不修改 settings.json」**。
>
> `~/.claude/skills/<name>/` 是 Claude Code 的另一條 plugin 載入路徑
> （`claude plugin init --help`：「auto-loads next session as `<name>@skills-dir`」）。
> 實測：
> - 現有 5 個 skills-dir plugin 在 `settings.json` 裡**零命中**
> - 掛上 symlink 後 `claude plugin list` 顯示 `agentaura@skills-dir ... ✔ loaded`
> - 跑一個真的 `claude -p` session，hook 觸發、狀態檔寫出、內容完整
> - **`settings.json` 的 md5 完全沒變**
>
> 用 **symlink** 而不是複製：改了程式碼重跑 `build-plugin.sh` 就生效，
> 不需要重新安裝。（要凍結版本的話把 `ln -sfn` 換成 `cp -R` 即可——app 內建的
> 一鍵接上走的就是這條，指向 bundle 內 `Contents/Resources/plugin/` 那份凍結版。）

## 完整移除

面板 Options 裡有**兩個**移除選項，處理的是不同範圍，選錯會留下不該留的東西：

- **「移除掛載」**——只刪 `~/.claude/skills/agentaura` 這個掛載。App 本身、你的顏色
  設定、session 紀錄、開機自動啟動的登入項目，全部原封不動留著。適合暫時停用、
  之後還想用同一份設定重新接上的情況。
- **「完整移除 AgentAura」**——依序：取消開機自動啟動的登入項目、移除上面那個掛載、
  刪除 `~/.agentaura` 底下所有 session 紀錄、清掉顏色與開關等偏好設定、最後把
  `AgentAura.app` 移到垃圾桶並結束這個 App。按下去之前會先跳出確認對話框，列出
  這幾件事。app 進垃圾桶前都可以還原；一旦清空垃圾桶就是真的刪除。這是讓機器回到
  「從未安裝過」狀態的唯一一鍵做法。

開發者路徑／手動移除（等同於「完整移除 AgentAura」做的五件事）：

```bash
pkill -f AgentAura.app            # 關掉 app（連帶讓 SMAppService 的登入項目失去對應的執行檔）
# 登入項目：到「系統設定 → 一般 → 登入項目」把 AgentAura 那一列移除。
# 這一步刻意沒有對應的指令，理由見下方警告。
rm ~/.claude/skills/agentaura     # 移除掛載（hooks 隨之失效）
rm -rf ~/.agentaura               # 狀態目錄，可安全刪除
defaults delete io.agentaura.app  # 清掉顏色／開關等偏好設定（persistent domain）
rm -rf build/AgentAura.app        # 刪掉 app 本身（建置產物，隨時可重建；正式安裝則拖進垃圾桶）
```

> 沒有 `claude plugin uninstall` 這一步 —— 那是 marketplace 安裝的 plugin 才需要；
> skills-dir 掛載的移除就是刪掉上面那個 symlink。
>
> **⚠️ 絕對不要用 `sfltool resetbtm` 來移除登入項目。** 它不是「移除 AgentAura 的登入項目」，
> 而是**清空整台機器**所有 app 的背景任務登記——你裝的每一個會開機自動啟動的軟體都會
> 一起消失，而且沒有還原鍵，只能一個一個手動加回去。
> 本專案在 2026-09-14 實際踩過這一顆：一個 agent 為了確認這個指令存不存在而執行了它，
> 開發機上八個登入項目瞬間歸零（`sfltool dumpbtm` 從 1593 行剩 21 行）。
> 移除單一 app 的登入項目，正確做法就是上面那句：到系統設定裡把那一列移掉。

驗證移除乾淨——**一律跑 `./scripts/verify-uninstall.sh`**，不要在這裡另外手抄一份檢查
清單（手抄的清單會跟實作 drift，這正是這份文件先前的問題所在）：

```bash
./scripts/verify-uninstall.sh                       # 預設檢查 /Applications/AgentAura.app
./scripts/verify-uninstall.sh build/AgentAura.app   # 開發者路徑另外指定 app 實際位置
```

它會逐一檢查掛載、`~/.agentaura` 狀態目錄、`io.agentaura.app` 偏好設定、登入項目、
app bundle 本身這五個位置，任何一項還在就非零退出並印出是哪一項。

移除後 `~/.claude/settings.json` **不會留下任何 AgentAura 引用** ——
這是刻意的設計：AgentAura 從不修改 `settings.json`，全部靠 plugin 機制；
這一項單獨驗（`verify-install.sh` 的第 3 項），不屬於上面的移除檢查。

## 狀態目錄

`~/.agentaura/sessions/<session_id>.json` —— 每個 Claude Code session 一個檔，
內容是瞬時狀態，可隨時安全刪除（app 會在下一個 hook 事件時重建）。

## 從舊版升級

`~/.agentaura/sessions/` 裡的狀態檔權限是 **0600**（目錄 0700）—— 那些檔含 `cwd`、
tool 參數與助理輸出的開頭。

早期版本建的檔是 0644。新版會在**每次寫入該檔時**收緊它，所以還活著的 session
會自動修好；但**再也不會被寫入的舊 session 檔會停在 0644**。要一次收乾淨：

```bash
chmod 600 ~/.agentaura/sessions/*.json
```

（或直接 `rm -rf ~/.agentaura` —— 那裡面是瞬時狀態，刪掉即可，app 會在下一個
hook 事件時重建。）

## 疑難排解

App 裡按「說明」開的離線文件（`help.html`）用白話講了同一批問題；這裡是給看
終端機比較快的人：

**燈沒反應**

```bash
ls -la ~/.agentaura/sessions/                        # 有檔案嗎？
claude plugin list | grep -A3 -i agentaura           # 載入了嗎？應顯示 ✔ loaded
ls -la ~/.claude/skills/agentaura                    # 掛載還在嗎？指向對的地方嗎？
claude plugin validate --strict ./plugin             # manifest 有 error / warning 嗎？
lipo -archs plugin/bin/aura-hook                     # 二進位在嗎、架構對嗎？
echo '{"hook_event_name":"Stop","session_id":"t1"}' | ./plugin/bin/aura-hook; echo $?
```

`aura-hook` **永遠 exit 0 且不輸出任何訊息**（設計如此：觀測性程式絕不可干擾 agent）。
所以「沒有錯誤訊息」不代表成功 —— 請看 `~/.agentaura/sessions/` 是否真的有檔案。

**App 說「已接上」但燈永遠不會亮（macOS 擋住了 hook）**

下載版 App 的執行檔可能被 macOS 隔離（quarantine），每次被呼叫都直接被系統擋下、
靜默失敗——外表看起來像「已接上」，其實 hook 從來沒真的跑成功過。App 內建的
接上流程會實際跑一次 `aura-hook` 並檢查有沒有產物，抓到這種情況會顯示
「macOS 擋住了 hook」而不是謊稱成功；遇到時把 App 拖進「應用程式」重開一次，
或到「系統設定 → 隱私權與安全性」找相關的允許選項。

**App 被搬走了 / 改了名字**

接上的掛載指向當時那個 App 檔案的實際位置，搬動或改名後燈會停在暗的。
把 App 放回原位，或移到新位置後在面板按「重新接上」。
