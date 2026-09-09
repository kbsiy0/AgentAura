#!/usr/bin/env bash
# 人眼驗收／DoD 量測用：造「活著的」假 session（真 pid + 真啟動時戳，過得了 Liveness）。
#   demo-sessions.sh error|waiting|working|done   加一個該狀態的 session（可疊加）
#   demo-sessions.sh all                          四種各一個
#   demo-sessions.sh clear                        殺掉假 process、刪掉 demo-*.json
set -uo pipefail
ROOT="$HOME/.agentaura/sessions"
HERE="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="${TMPDIR:-/tmp}/agentaura-demo.pids"
mkdir -p "$ROOT"; chmod 700 "$ROOT"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
ago() { date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ; }

# 產生一個會活 2 小時的 process，印出 "pid started_epoch"
spawn() {
  nohup sleep 7200 >/dev/null 2>&1 &
  local pid=$!
  echo "$pid" >> "$PIDFILE"
  local l; l=$(ps -p "$pid" -o lstart= | tr -s ' ' | sed 's/^ //; s/ $//')
  echo "$pid $(date -j -f '%a %b %d %H:%M:%S %Y' "$l" +%s)"
}

write() { # write <state>
  local f="$ROOT/demo-$1.json"
  # 絕不覆寫既有檔（含上一次沒 clear 的 demo 檔）——先 clear 再造。
  if [ -e "$f" ]; then echo "  ! $f 已存在，先跑 $(basename "$0") clear" >&2; return 1; fi
  read -r pid started < <(spawn)
  case "$1" in
    waiting) cat > "$f" <<EOF
{"schema":1,"session_id":"demo-waiting","hook_event_name":"PermissionRequest","written_at":"$(now)","turn_started_at":"$(ago 42)","pid":$pid,"pid_started_at":$started,"cwd":"/Users/you/Code/Vibe/fitness-tracker","model":"claude-opus-5","permission_mode":"default","effort":"high","main_activity":"waiting","main_tool":"Bash","tool_description":"刪除 build/ 底下的舊產物","subagents":{},"tool_failures":0,"terminated":false}
EOF
    ;;
    working) cat > "$f" <<EOF
{"schema":1,"session_id":"demo-working","hook_event_name":"PreToolUse","written_at":"$(now)","turn_started_at":"$(ago 380)","pid":$pid,"pid_started_at":$started,"cwd":"/Users/you/Code/Vibe/payments-api","model":"claude-sonnet-5","permission_mode":"acceptEdits","effort":"medium","main_activity":"working","main_tool":"Edit","sub_activity":"working","sub_agent_type":"Explore","sub_tool":"Grep","subagents":{"Explore":2},"tool_failures":1,"terminated":false}
EOF
    ;;
    error) cat > "$f" <<EOF
{"schema":1,"session_id":"demo-error","hook_event_name":"StopFailure","written_at":"$(now)","turn_started_at":"$(ago 1500)","pid":$pid,"pid_started_at":$started,"cwd":"/Users/you/Code/Vibe/Nightly","model":"claude-opus-5","permission_mode":"bypassPermissions","effort":"xhigh","main_activity":"error","reason":"overloaded_error","subagents":{},"tool_failures":3,"terminated":false}
EOF
    ;;
    done) cat > "$f" <<EOF
{"schema":1,"session_id":"demo-done","hook_event_name":"Stop","written_at":"$(now)","turn_started_at":"$(ago 900)","pid":$pid,"pid_started_at":$started,"cwd":"/Users/you/Code/Vibe/Notes","model":"claude-haiku-4-5-20251001","permission_mode":"acceptEdits","effort":"low","main_activity":"done","last_message":"235 tests / 23 suites 全綠，18.3 秒。已 commit 到 change/notes-cleanup。","subagents":{},"tool_failures":0,"terminated":false}
EOF
    ;;
    *) echo "unknown state: $1" >&2; return 1 ;;
  esac
  chmod 600 "$f"
  echo "  + demo-$1  (pid $pid)"
}

case "${1:-}" in
  error|waiting|working|done) write "$1" ;;
  all) for s in working waiting error done; do write "$s"; done ;;
  clear)
    [ -f "$PIDFILE" ] && { xargs kill 2>/dev/null < "$PIDFILE"; rm -f "$PIDFILE"; }
    rm -f "$ROOT"/demo-*.json
    echo "  cleared"
    ;;
  *) sed -n 2,6p "$0"; exit 1 ;;
esac
