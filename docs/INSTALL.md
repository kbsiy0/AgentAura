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

一般使用者：面板 Options 裡「移除掛載」一鍵完成，會把上面第 4 步建立的掛載刪掉。

開發者路徑／手動移除：

```bash
pkill -f AgentAura.app            # 關掉 app
rm -rf build/AgentAura.app        # 刪掉 app（建置產物，隨時可重建）
rm ~/.claude/skills/agentaura     # 移除掛載（hooks 隨之失效）
rm -rf ~/.agentaura               # 狀態目錄，可安全刪除
```

> 沒有 `claude plugin uninstall` 這一步 —— 那是 marketplace 安裝的 plugin 才需要；
> skills-dir 掛載的移除就是刪掉上面那個 symlink。

一步安裝、一步移除（R6）。驗證移除乾淨：

```bash
claude plugin list | grep -c -i agentaura           # → 0
grep -c -i agentaura ~/.claude/settings.json        # → 0（**全程都是 0**）
ls ~/.agentaura 2>/dev/null | wc -l                 # → 0
```

第二行的重點是「**全程**都是 0」，不是「移除後變成 0」——
AgentAura 從頭到尾沒有寫過 `settings.json` 的任何一個位元組。

移除後 `~/.claude/settings.json` **不會留下任何 AgentAura 引用** ——
這是刻意的設計：AgentAura 從不修改 `settings.json`，全部靠 plugin 機制。

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
