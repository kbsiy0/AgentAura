#!/usr/bin/env bash
# 產生某個 task 的 brief，並在產生前確認 plan 的程式碼真的編得過。
#
# 存在理由：T04 的 brief 是批次產生的，之後我又改了 plan 四處，
# 於是 implementer 拿到 43 分鐘前的版本，重新發現了我已經修好的四個缺陷。
# brief 必須在 dispatch 的那一刻產生，不能提前批次產。
set -euo pipefail
cd "$(dirname "$0")/.."
N="${1:?用法: scripts/dispatch-brief.sh <task 編號，如 05>}"
PLAN=docs/superpowers/plans/2026-09-08-agentaura-pipeline.md
SK=/Users/you/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/skills/subagent-driven-development

echo "==> 1/3 確認 plan 沒有未 commit 的變更"
if ! git diff --quiet -- "$PLAN"; then
  echo "    ✗ $PLAN 有未 commit 的變更 —— 先 commit 再產 brief，否則 brief 會對不上 git 歷史"
  exit 1
fi
echo "    ✓ 乾淨"

echo "==> 2/3 把 plan 的程式碼組成 SwiftPM package 編譯"
TMP=$(mktemp -d)
python3 - "$TMP" <<'PY'
import re, sys, pathlib, shutil
tmp=pathlib.Path(sys.argv[1])
pl=pathlib.Path('docs/superpowers/plans/2026-09-08-agentaura-pipeline.md').read_text()
m=re.search(r'```swift\n// swift-tools-version[^\n]*\n(.*?)```', pl, re.S)
(tmp/'Package.swift').write_text('// swift-tools-version: 6.0\n'+m.group(1))
acc={}
for pat in (r'```swift\n(// (Sources/[^\n]+))\n(.*?)```',
            r'```swift\n(// (Tests/[^\n]+))\n(.*?)```',
            r'```swift\n(// 附加到 (Tests/[^\n]+))\n(.*?)```'):
    for mm in re.finditer(pat, pl, re.S): acc[mm.group(2)]=acc.get(mm.group(2),'')+mm.group(3)+'\n'
for path, body in acc.items():
    q=tmp/path; q.parent.mkdir(parents=True, exist_ok=True)
    if path.startswith('Sources') and 'import Foundation' not in body: body='import Foundation\n'+body
    q.write_text(body)
fx=tmp/'Tests/AuraCoreTests/Fixtures'; fx.mkdir(parents=True, exist_ok=True)
for f in ('round1.ndjson','round1b.ndjson','round2.ndjson'):
    s=pathlib.Path('Tests/AuraCoreTests/Fixtures')/f
    if s.exists(): shutil.copy(s, fx/f)
PY
if ! (cd "$TMP" && swift build --build-tests 2>&1 | grep -q "error:"); then
  echo "    ✓ 零 error"
else
  echo "    ✗ plan 的程式碼編不過："
  (cd "$TMP" && swift build --build-tests 2>&1 | grep "error:" | sort -u | head -10 | sed 's/^/      /')
  rm -rf "$TMP"; exit 1
fi
rm -rf "$TMP"

echo "==> 3/3 產生 brief"
"$SK/scripts/task-brief" "$PLAN" "$N"
