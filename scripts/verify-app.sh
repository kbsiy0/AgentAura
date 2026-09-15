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

echo "== 1. bundle 內容（D-g／G14）=="
# 對真 bundle 斷言，不是對 repo checkout 斷言：這條就是 G14「缺 bundle 時 FAIL
# 而不是 skip」的定義。本專案有「env-gated suite 靜默 skip」的前例（S1-Q11），
# skipped 不是綠，所以每一項缺失都要各自 bad()，不能因為前一項缺了就跳過整段。
PLUGIN="$APP/Contents/Resources/plugin"
[ -f "$PLUGIN/.claude-plugin/plugin.json" ] \
  && ok "plugin.json 在 bundle 裡" \
  || bad "缺 $PLUGIN/.claude-plugin/plugin.json —— 先跑 scripts/build-app.sh"
[ -f "$PLUGIN/hooks/hooks.json" ] \
  && ok "hooks.json 在 bundle 裡" \
  || bad "缺 $PLUGIN/hooks/hooks.json —— 先跑 scripts/build-app.sh"
if [ -x "$PLUGIN/bin/aura-hook" ]; then
  ok "aura-hook 在 bundle 裡且可執行"
  archs=$(lipo -archs "$PLUGIN/bin/aura-hook" 2>/dev/null)
  if echo "$archs" | grep -q arm64 && echo "$archs" | grep -q x86_64; then
    ok "aura-hook 雙架構：$archs"
  else
    bad "aura-hook 架構不全（要 arm64 + x86_64）：$archs"
  fi
else
  bad "缺 $PLUGIN/bin/aura-hook 或不可執行 —— 先跑 scripts/build-app.sh（gitignored 建置產物）"
fi
# T30（i18n）：說明文件依語言拆成 help-*.html，逐一檢查每個 repo 裡的來源檔都有
# 被複製進 bundle（同 build-app.sh 的 glob，不手抄語言清單）。
shopt -s nullglob
help_docs=(Resources/help-*.html)
shopt -u nullglob
if [ ${#help_docs[@]} -eq 0 ]; then
  bad "repo 裡找不到任何 Resources/help-*.html"
else
  for f in "${help_docs[@]}"; do
    name=$(basename "$f")
    [ -f "$APP/Contents/Resources/$name" ] \
      && ok "$name 在 bundle 裡" \
      || bad "缺 $APP/Contents/Resources/$name —— 先跑 scripts/build-app.sh"
  done
fi

echo "== 2. 造三個假狀態（waiting / working / error）=="
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

echo "== 3. 啟動 app =="
open "$APP"
sleep 4
if pgrep -f "AgentAura.app/Contents/MacOS/AgentAuraApp" >/dev/null; then
  ok "app 在跑"
else
  bad "app 沒起來或已退出"
fi

echo "== 4. 確認沒有 dock icon（LSUIElement 生效）=="
# LSUIElement 的 app 不會出現在 Dock 的執行中清單
if osascript -e 'tell application "System Events" to get name of every process whose background only is false' 2>/dev/null | grep -q AgentAura; then
  bad "出現在前景 process 清單 —— LSUIElement 沒生效"
else
  ok "沒有 dock icon"
fi

echo "== 5. app 真的讀到狀態了嗎 =="
# 刪掉一個狀態檔，refreshLiveness 應在 5s 內移除它；用「app 沒 crash」當代理指標
rm -f "$ROOT/verify-working.json"
sleep 7
if pgrep -f "AgentAura.app/Contents/MacOS/AgentAuraApp" >/dev/null; then
  ok "狀態檔被外部刪除後 app 仍存活（refreshLiveness 沒炸）"
else
  bad "app 在狀態檔被刪後掛掉"
fi

echo "== 6. 收工 =="
pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp" 2>/dev/null && ok "已關閉" || ok "已不在執行"
rm -f "$ROOT"/verify-*.json
ok "假狀態已清除"

echo
[ "$FAIL" -eq 0 ] && echo "實機驗收 PASS" || echo "實機驗收 FAIL"
exit "$FAIL"
