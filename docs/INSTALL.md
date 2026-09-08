# 安裝 AgentAura

## 需求

- macOS 13 或以上
- Swift 6 工具鏈（`xcode-select --install` 或完整 Xcode）
- Claude Code

## 安裝

```bash
git clone <repo> && cd AgentAura
./scripts/build-plugin.sh                    # 建置 universal aura-hook 到 plugin/bin/
claude plugin validate ./plugin              # 官方 validator，必須零 error 零 warning
claude plugin marketplace add .              # 把這個 repo 註冊成本地 marketplace
claude plugin install agentaura@agentaura -y # 註冊 hooks（不會修改 ~/.claude/settings.json）
./scripts/verify-install.sh                  # 驗證整條鏈路
```

> **為什麼要先 `marketplace add`：** `claude plugin install` **只從 marketplace 安裝**
> （`claude plugin install --help`：「Install a plugin from available marketplaces」），
> **不吃本地目錄路徑** —— `claude plugin install ./plugin` 不會生效。
> 本地安裝的正確途徑是 `claude plugin marketplace add <path>`
> （`marketplace add` 明文支援 URL / **path** / GitHub repo），
> 這也是 repo 根目錄需要 `.claude-plugin/marketplace.json` 的原因。
>
> `-y` 是必要的：非 TTY 環境（腳本、CI）下 install 會等一個確認提示。

**不需要重啟 Claude Code** —— hook 設定變更會立即對執行中的 session 生效（已實測確認）。

## 完整移除

```bash
claude plugin uninstall agentaura             # 移除 plugin（hooks 隨之失效）
claude plugin marketplace remove agentaura    # 移除本地 marketplace 註冊
rm -rf ~/.agentaura                           # 狀態目錄，可安全刪除
```

驗證移除乾淨（三者都該是 0）：

```bash
claude plugin list | grep -c agentaura              # → 0
claude plugin marketplace list | grep -c agentaura  # → 0
grep -c -i agentaura ~/.claude/settings.json        # → 0
```

移除後 `~/.claude/settings.json` **不會留下任何 AgentAura 引用** ——
這是刻意的設計：AgentAura 從不修改 `settings.json`，全部靠 plugin 機制。

## 狀態目錄

`~/.agentaura/sessions/<session_id>.json` —— 每個 Claude Code session 一個檔，
內容是瞬時狀態，可隨時安全刪除（app 會在下一個 hook 事件時重建）。

## 疑難排解

**燈沒反應**

```bash
ls -la ~/.agentaura/sessions/                        # 有檔案嗎？
claude plugin list | grep agentaura                  # plugin 裝了嗎？
claude plugin validate ./plugin                      # manifest 有 error / warning 嗎？
lipo -archs plugin/bin/aura-hook                     # 二進位在嗎、架構對嗎？
echo '{"hook_event_name":"Stop","session_id":"t1"}' | ./plugin/bin/aura-hook; echo $?
```

`aura-hook` **永遠 exit 0 且不輸出任何訊息**（設計如此：觀測性程式絕不可干擾 agent）。
所以「沒有錯誤訊息」不代表成功 —— 請看 `~/.agentaura/sessions/` 是否真的有檔案。
