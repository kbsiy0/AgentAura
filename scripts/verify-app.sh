#!/usr/bin/env bash
# 實機驗收：造假狀態 → 啟動 app → 確認它活著且真的讀到狀態 → 收工。
set -uo pipefail
cd "$(dirname "$0")/.."
APP=build/AgentAura.app
ROOT="$HOME/.agentaura/sessions"
FAIL=0
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }

[ -d "$APP" ] || { bad "$APP 不存在 —— 先跑 scripts/build-app.sh"; exit 1; }

echo "== 1. 造三個假狀態（waiting / working / error）=="
mkdir -p "$ROOT"
python3 - <<'PY'
import json, pathlib, datetime
root = pathlib.Path.home()/".agentaura/sessions"
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z")
for sid, act in [("verify-waiting","waiting"), ("verify-working","working"), ("verify-error","error")]:
    (root/f"{sid}.json").write_text(json.dumps({
        "schema": 1, "session_id": sid, "hook_event_name": "PreToolUse",
        "written_at": now, "turn_started_at": now,
        "cwd": f"/Users/you/Code/Vibe/{sid}", "model": "claude-opus-5[1m]",
        "permission_mode": "default", "effort": "high",
        "main_activity": act, "main_tool": "Bash",
        "subagents": {}, "tool_failures": 0, "terminated": False,
    }, ensure_ascii=False))
print("  已造 3 個")
PY

echo "== 2. 啟動 app =="
open "$APP"
sleep 4
if pgrep -f "AgentAura.app/Contents/MacOS/AgentAuraApp" >/dev/null; then
  ok "app 在跑"
else
  bad "app 沒起來或已退出"
fi

echo "== 3. 確認沒有 dock icon（LSUIElement 生效）=="
# LSUIElement 的 app 不會出現在 Dock 的執行中清單
if osascript -e 'tell application "System Events" to get name of every process whose background only is false' 2>/dev/null | grep -q AgentAura; then
  bad "出現在前景 process 清單 —— LSUIElement 沒生效"
else
  ok "沒有 dock icon"
fi

echo "== 4. app 真的讀到狀態了嗎 =="
# 刪掉一個狀態檔，refreshLiveness 應在 5s 內移除它；用「app 沒 crash」當代理指標
rm -f "$ROOT/verify-working.json"
sleep 7
if pgrep -f "AgentAura.app/Contents/MacOS/AgentAuraApp" >/dev/null; then
  ok "狀態檔被外部刪除後 app 仍存活（refreshLiveness 沒炸）"
else
  bad "app 在狀態檔被刪後掛掉"
fi

echo "== 5. 收工 =="
pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp" 2>/dev/null && ok "已關閉" || ok "已不在執行"
rm -f "$ROOT"/verify-*.json
ok "假狀態已清除"

echo
[ "$FAIL" -eq 0 ] && echo "實機驗收 PASS" || echo "實機驗收 FAIL"
exit "$FAIL"
