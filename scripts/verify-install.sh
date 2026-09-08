#!/usr/bin/env bash
# 實機驗收：在真的 Claude Code 裡跑一輪，確認狀態檔真的被寫出來。
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$HOME/.agentaura/sessions"
FAIL=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }

echo "== 1. plugin 二進位 =="
[ -x plugin/bin/aura-hook ] && ok "plugin/bin/aura-hook 可執行" \
                            || bad "plugin/bin/aura-hook 不存在 —— 先跑 scripts/build-plugin.sh"
lipo -archs plugin/bin/aura-hook 2>/dev/null | grep -q arm64 \
  && ok "含 arm64" || bad "缺 arm64"

echo "== 2. plugin 已註冊 =="
claude plugin list 2>/dev/null | grep -q agentaura \
  && ok "agentaura plugin 已安裝" \
  || bad "未安裝 —— claude plugin marketplace add . && claude plugin install agentaura@agentaura -y"

echo "== 2b. 官方 validator 零 error 零警告 =="
# 只看 exit code 是空轉的：validator 對「unknown hook event」、「no type」、
# 「async 型別錯」都只給 **warning** 並仍然 exit 0，而每個 warning 都寫著
# **entry ignored at runtime** —— 也就是一個靜默的死 hook。
# 實測確認 exit code 在有 warning 時仍是 0，所以這裡必須看輸出文字。
for target in ./plugin .; do
  out=$(claude plugin validate "$target" 2>&1)
  if echo "$out" | grep -qi "warning\|✘"; then
    bad "validate $target 有 error/warning："
    echo "$out" | sed 's/^/      /'
  elif echo "$out" | grep -q "Validation passed"; then
    ok "validate $target 乾淨"
  else
    bad "validate $target 沒有印出通過：$out"
  fi
done

echo "== 3. settings.json 未被污染（R6）=="
python3 -c "
import json,pathlib,sys
p=pathlib.Path.home()/'.claude/settings.json'
d=json.loads(p.read_text()) if p.exists() else {}
h=json.dumps(d.get('hooks',{}))
sys.exit(1 if 'agentaura' in h.lower() or 'aura-hook' in h else 0)
" && ok "settings.json 沒有 AgentAura 引用" || bad "settings.json 被寫入了 —— 違反 D3/R6"

echo "== 4. 實機跑一輪 =="
BEFORE=$(ls "$ROOT" 2>/dev/null | wc -l | tr -d ' ')
echo "  執行：claude -p '請執行 echo agentaura-verify'"
claude -p "請執行 echo agentaura-verify" >/dev/null 2>&1
sleep 1
AFTER=$(ls "$ROOT" 2>/dev/null | wc -l | tr -d ' ')
[ "$AFTER" -gt "$BEFORE" ] && ok "狀態檔數量 $BEFORE → $AFTER" \
                           || bad "沒有新狀態檔 —— hook 沒被觸發或 aura-hook 沒寫成功"

echo "== 5. 狀態檔內容合理 =="
LATEST=$(ls -t "$ROOT"/*.json 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
  python3 -c "
import json,sys
d=json.load(open('$LATEST'))
checks=[('schema==1', d.get('schema')==1),
        ('有 session_id', bool(d.get('session_id'))),
        ('有 main_activity', d.get('main_activity') in ['idle','done','working','waiting','error']),
        ('有 pid', isinstance(d.get('pid'), int)),
        ('有 pid_started_at', isinstance(d.get('pid_started_at'), int))]
for name, passed in checks:
    print(('  \033[32m✓\033[0m ' if passed else '  \033[31m✗\033[0m ')+name)
sys.exit(0 if all(p for _,p in checks) else 1)
" || FAIL=1
  echo "  最新狀態檔：$LATEST"
else
  bad "找不到任何狀態檔"
fi

echo
[ "$FAIL" -eq 0 ] && echo "實機驗收 PASS" || echo "實機驗收 FAIL"
exit "$FAIL"
