#!/usr/bin/env bash
# 完整移除驗收（T24；Codex 第 7 項見 T11／CX27）：逐一檢查六個殘留位置
# （掛載／狀態目錄／偏好設定／登入項目／App bundle／Codex hook）與上一次執行留下的
# 失敗紀錄，任何一項還在就 FAIL。
#
# 用法：scripts/verify-uninstall.sh [App 路徑] [--only <n>]
#   App 路徑：預設 /Applications/AgentAura.app
#   --only <n>：只跑第 n 項，**只印那一項**，其餘六項（含慢的 osascript／sfltool dumpbtm）
#     一律跳過。判準看那一項印出的那一行 ✓／✗，**不是整體 exit code**——第 1–6 項查的是
#     真實 $HOME，在任何一台開發機上本來就會 FAIL、整支腳本的 exit code 本來就非零，
#     拿它當判準的話，mutation（拿掉某一項）不會讓 exit code 有任何變化。
#
# CODEX_HOME：**不是給使用者的介面**，只給測試注入用（同 AGENTAURA_ROOT 的既有先例）——
# 一般使用者不需要，也不應該設這個環境變數。
set -uo pipefail
APP="/Applications/AgentAura.app"
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only)
      ONLY="${2:-}"
      shift 2
      ;;
    --only=*)
      ONLY="${1#--only=}"
      shift
      ;;
    *)
      APP="$1"
      shift
      ;;
  esac
done
should_run() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
# 從 Info.plist 推導，不手抄一份（手抄的清單自己會 drift——本專案的老教訓）。
PLIST="$(cd "$(dirname "$0")/.." && pwd)/Resources/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null || echo io.agentaura.app)"
FAIL=0
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }

if should_run 1; then
echo "== 1. ~/.claude/skills/agentaura 掛載 =="
[ -e "$HOME/.claude/skills/agentaura" ] \
  && bad "掛載仍在：$HOME/.claude/skills/agentaura" \
  || ok "掛載已移除"
fi

if should_run 2; then
echo "== 2. ~/.agentaura 狀態目錄 =="
[ -e "$HOME/.agentaura" ] \
  && bad "狀態目錄仍在：$HOME/.agentaura" \
  || ok "狀態目錄已移除"
fi

if should_run 3; then
echo "== 3. $BUNDLE_ID 偏好設定（persistent domain）=="
if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
  bad "persistent domain 仍在：$(defaults read "$BUNDLE_ID" 2>/dev/null | head -1)"
else
  ok "persistent domain 已清空"
fi
fi

if should_run 4; then
echo "== 4. 登入項目（SMAppService） =="
# **兩條獨立的查法，任一看到就算殘留**——單獨信任任何一條都有假陰性風險：
#   (a) System Events 的 login items：即時回答（實測 0 秒），但它是舊的 LSSharedFileList
#       視角，不保證涵蓋所有 SMAppService 註冊形式。
#   (b) sfltool dumpbtm：直接問背景任務管理資料庫，權威但**實測要 39 秒**，而且
#       兩個 dumpbtm 並行時第二個會回空——回空絕不可當成「乾淨」（第一版就是在這裡
#       假性通過的）。這裡給它有界等待（macOS 沒有 timeout 命令，自己寫）。
# 兩條都問不到答案 → FAIL。無法驗證不等於驗證通過。
LOGIN_SEEN=""; LOGIN_ASKED=0

LI="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || true)"
if [ -n "$LI" ]; then
  LOGIN_ASKED=1
  printf '%s' "$LI" | grep -qi "agentaura" && LOGIN_SEEN="System Events login items"
fi

if [ -z "$LOGIN_SEEN" ] && command -v sfltool >/dev/null 2>&1; then
  BTM_OUT="$(mktemp)"
  sfltool dumpbtm > "$BTM_OUT" 2>/dev/null & SFPID=$!
  ( sleep 90; kill -9 "$SFPID" 2>/dev/null ) & WPID=$!
  # `disown` 兩個背景工作——沒有這行，watchdog 把 sfltool 殺掉時 shell 的作業控制會印
  # 「[n]  Killed: 9  ...」這種雜訊到輸出上（功能沒錯，純粹難看，team-lead 實測抓到）。
  disown "$SFPID" "$WPID" 2>/dev/null
  wait "$SFPID" 2>/dev/null
  kill -9 "$WPID" 2>/dev/null
  wait "$WPID" 2>/dev/null
  if [ -s "$BTM_OUT" ]; then
    LOGIN_ASKED=1
    grep -qi "agentaura" "$BTM_OUT" && LOGIN_SEEN="sfltool dumpbtm"
  fi
  rm -f "$BTM_OUT"
fi

if [ -n "$LOGIN_SEEN" ]; then
  bad "登入項目仍在（來源：${LOGIN_SEEN}）"
elif [ "$LOGIN_ASKED" -eq 1 ]; then
  ok "登入項目已取消註冊"
else
  bad "兩條查法都問不到答案——無法驗證登入項目，不得當成通過"
fi
fi

if should_run 5; then
echo "== 5. App bundle（應已移到垃圾桶） =="
[ -d "$APP" ] \
  && bad "$APP 仍存在——應該已被移到垃圾桶" \
  || ok "$APP 不存在（已移除或已在垃圾桶）"
fi

if should_run 6; then
echo "== 6. 垃圾桶動作紀錄（T25：上一次執行留下的失敗線索） =="
# `Sources/AgentAuraApp/Uninstaller.swift` 的 `UninstallFailureLog` 只在垃圾桶動作真的
# 失敗時才寫這個檔——成功時完整移除不留下任何東西。看到它就代表上一次的垃圾桶動作
# 沒有真的落地，內容含來源路徑與錯誤描述，留給人判斷要不要刪。
UNINSTALL_FAILURE_LOG="$HOME/.agentaura-uninstall.log"
if [ -e "$UNINSTALL_FAILURE_LOG" ]; then
  bad "上一次垃圾桶動作失敗：$(cat "$UNINSTALL_FAILURE_LOG")"
else
  ok "沒有垃圾桶失敗紀錄"
fi
fi

if should_run 7; then
echo "== 7. \${CODEX_HOME:-\$HOME/.codex}/hooks.json（Codex hook，T11／CX27） =="
# D-o（spec §4.5）：內容判準，不是「存在就 FAIL」——使用者自己的 hooks.json（沒有
# `--agent codex` 這個字面）不算我們的殘留，`CodexInstaller.disconnect` 也不會動它。
CODEX_HOOKS_JSON="${CODEX_HOME:-$HOME/.codex}/hooks.json"
if [ -f "$CODEX_HOOKS_JSON" ] && grep -q -- "--agent codex" "$CODEX_HOOKS_JSON" 2>/dev/null; then
  bad "Codex hook 仍在：$CODEX_HOOKS_JSON"
else
  ok "Codex hook 已移除或從未接上"
fi
fi

echo
[ "$FAIL" -eq 0 ] && echo "完整移除驗收 PASS" || echo "完整移除驗收 FAIL"
exit "$FAIL"
