#!/usr/bin/env bash
# DoD 量測：對每個狀態，用 top 取樣 N 秒的 CPU% 與 RSS，抓「動畫態的成本是不是可接受」。
#
# 用法：
#   ./scripts/measure-cpu.sh [標籤] [秒數]
#   標籤只用來當輸出檔名（例如 branch 名、形態名），不影響量測內容。
#   秒數預設 60。
#
# 覆蓋用環境變數：
#   STATES   要量哪些狀態，預設 "idle done working waiting error"
#   APP      app bundle 路徑，預設 build/AgentAura.app
#   OUT      輸出檔路徑，預設 build/cpu-<標籤>.txt
#
# 範例：
#   ./scripts/measure-cpu.sh main 60
#   STATES="waiting error" ./scripts/measure-cpu.sh quick-check 20
#
# !! 量之前必看：先隔離自己這個 Claude Code session !!
#   這支腳本本身是在一個 Claude Code session 裡執行的，而 AgentAura 會觀測
#   *所有* session（包含正在跑這支腳本的這一個）。如果它剛好處於動畫態
#   （working／waiting／…），量到的 CPU 會混進「自己」的成本，數字就不
#   代表 app 本身、也不代表你想量的那個假狀態。實測踩過這個坑。
#
#   量測前，先把這個 session 自己的狀態檔標成 terminated: true 隔離掉
#   （SessionReducer 會忽略 terminated 的 session，不再進聚合）：
#
#     ls -t ~/.agentaura/sessions/*.json | head -1   # 找出「這個」session 的檔案
#     python3 -c "
#     import json, pathlib
#     p = pathlib.Path('<上面找到的路徑>')
#     d = json.loads(p.read_text()); d['terminated'] = True
#     p.write_text(json.dumps(d))
#     "
#
#   隔離只影響量測的乾淨度，不影響這個 session 本身的行為。
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LABEL=${1:-run}; SECS=${2:-60}
DEMO="$HERE/scripts/demo-sessions.sh"
APP=${APP:-$HERE/build/AgentAura.app}
OUT=${OUT:-$HERE/build/cpu-$LABEL.txt}
mkdir -p "$(dirname "$OUT")"

pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp" 2>/dev/null; sleep 1
"$DEMO" clear >/dev/null 2>&1
open "$APP"; sleep 3
PID=$(pgrep -f "AgentAura.app/Contents/MacOS/AgentAuraApp" | head -1)
[ -n "$PID" ] || { echo "app 沒起來 —— 先跑 ./scripts/build-app.sh"; exit 1; }
echo "# label=$LABEL pid=$PID secs=$SECS date=$(date '+%m/%d %H:%M')" > "$OUT"
for STATE in ${STATES:-idle done working waiting error}; do
  "$DEMO" clear >/dev/null 2>&1
  [ "$STATE" = idle ] || "$DEMO" "$STATE" >/dev/null
  sleep 6   # 等 liveness timer / FSEvents 收斂
  # top -l N -s 1：每秒一筆，取該 pid 的 %CPU 與 MEM
  top -l "$SECS" -s 1 -pid "$PID" -stats pid,cpu,mem 2>/dev/null \
    | awk -v pid="$PID" '$1==pid {gsub(/M/,"",$3); cpu+=$2; if($2>mx)mx=$2; n++; rss=$3} END {if(n>0) printf "avg=%.2f%% max=%.2f%% rss=%sM n=%d", cpu/n, mx, rss, n}' \
    | sed "s/^/$STATE: /" | tee -a "$OUT"; echo | tee -a "$OUT"
done
"$DEMO" clear >/dev/null 2>&1
echo "done → $OUT"
