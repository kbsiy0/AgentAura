#!/usr/bin/env bash
# 建置 universal aura-hook 並放進 plugin/bin/，供 hooks.json 的
# ${CLAUDE_PLUGIN_ROOT}/bin/aura-hook 使用。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 建置 arm64"
swift build -c release --arch arm64 --product aura-hook
echo "==> 建置 x86_64"
swift build -c release --arch x86_64 --product aura-hook

mkdir -p plugin/bin
echo "==> 合併成 universal binary"
lipo -create -output plugin/bin/aura-hook \
  .build/arm64-apple-macosx/release/aura-hook \
  .build/x86_64-apple-macosx/release/aura-hook
chmod +x plugin/bin/aura-hook

echo "==> 驗證架構"
archs=$(lipo -archs plugin/bin/aura-hook)
echo "$archs"
for a in arm64 x86_64; do
  case "$archs" in *"$a"*) ;; *) echo "缺 $a"; exit 1 ;; esac
done

echo "==> 驗證真的跑得起來且 exit 0"
# 這裡刻意關掉 errexit 再自己判斷：
# 原本寫成 `cmd; echo "exit=$?  （必須是 0）"`，但在 `set -euo pipefail` 下，
# 非 0 會讓腳本在 echo 之前就死掉 —— 那行**永遠只印得出 exit=0**，
# 「必須是 0」這句話製造了一個不存在的檢查。實測確認（腳本直接 exit 1、零輸出）。
BENCHROOT="$(mktemp -d)/sessions"
set +e
echo '{"hook_event_name":"PreToolUse","session_id":"buildcheck","tool_name":"Bash"}' \
  | AGENTAURA_ROOT="$BENCHROOT" ./plugin/bin/aura-hook
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "aura-hook 回了 ${rc}，契約要求一律 0"; exit 1; }

# exit 0 不等於真的寫了檔 —— 契約是「靜默 exit 0」，所以 exit code 本身
# 無法區分「成功」與「內部炸掉但被吞掉」。必須驗產物。
[ -s "$BENCHROOT/buildcheck.json" ] || { echo "沒有寫出狀態檔 —— exit 0 是假的成功"; exit 1; }
grep -q '"main_activity":"working"' "$BENCHROOT/buildcheck.json" \
  || { echo "狀態檔內容不對：$(cat "$BENCHROOT/buildcheck.json")"; exit 1; }

echo "==> plugin/bin/aura-hook 就緒"
