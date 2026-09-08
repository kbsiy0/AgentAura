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
[ -e "$HOME/.claude/skills/agentaura" ] \
  && ok "掛載存在：$(readlink "$HOME/.claude/skills/agentaura" 2>/dev/null || echo '（實體目錄）')" \
  || bad "未掛載 —— ln -sfn \"$PWD/plugin\" ~/.claude/skills/agentaura"
claude plugin list 2>/dev/null | grep -q "agentaura@skills-dir" \
  && ok "Claude Code 已載入 agentaura@skills-dir" \
  || bad "Claude Code 沒載入 —— 這是新 session 才會生效的，先開一個新 session 再跑"

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

echo "== 3. settings.json 全檔零污染（D3/R6）=="
# **掃整個檔案，不只掃 hooks 區塊。**
#
# 前一版只看 `d.get('hooks', {})`。實測 `claude plugin marketplace add .` 會在
# `extraKnownMarketplaces` 裡寫一筆 agentaura —— 那個位置**完全不在** hooks 底下，
# 舊檢查會給綠燈。一個只看自己想得到的那個角落的檢查，等於沒有檢查。
python3 -c "
import json, pathlib, sys
p = pathlib.Path.home()/'.claude/settings.json'
raw = p.read_text() if p.exists() else '{}'
hits = [k for k in ['agentaura', 'aura-hook', 'AgentAura'] if k.lower() in raw.lower()]
if hits:
    d = json.loads(raw)
    where = [key for key in d if any(h.lower() in json.dumps(d[key]).lower() for h in hits)]
    print('    污染位置：' + ', '.join(where))
    sys.exit(1)
sys.exit(0)
" && ok "settings.json 全檔零 AgentAura 引用" \
  || bad "settings.json 被寫入了 —— 違反 D3/R6。AgentAura 不該碰這個檔案的任何位元組"

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
