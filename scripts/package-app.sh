#!/usr/bin/env bash
# 把 build/AgentAura.app 打包成可以傳給別人的 zip（T31）。
#
# **為什麼用 ditto 不用 zip**：`zip` 不保留 macOS 的 bundle 結構與延伸屬性，
# 解壓後簽章會壞掉、Gatekeeper 直接拒絕。`ditto -c -k --sequesterRsrc --keepParent`
# 是 Apple 自己文件指定的做法。
#
# **這份 zip 是 ad-hoc 簽章**（沒有 Developer ID、沒有公證）。接收者第一次開會被
# Gatekeeper 擋，必須到「系統設定 → 隱私權與安全性」按「強制打開」授權一次。
#
# **不要教人用「右鍵 →打開」**：那招在 macOS 15 Sequoia 之後被 Apple 拿掉了，
# 新版對話框只有「移到垃圾桶」與「完成」兩個按鈕，沒有任何繞過入口。
# 2026-09-15 實機踩到（macOS 26.6.2）——照舊行為寫的說明會讓人卡死在第一步，
# 而最顯眼的那顆粉紅色按鈕是「移到垃圾桶」。
#
# 實測（2026-09-15）：授權之後巢狀的
# aura-hook 雖然**仍帶著 quarantine 屬性**，但執行正常（exit 0、狀態檔產出）——
# 系統認的是使用者對這個 app 的授權，不是逐檔的標記。
# 授權**之前**跑它會 SIGKILL（exit 137）而 `access(X_OK)` 照樣說可執行，
# 所以驗收一律看產物，不看權限位元。
set -uo pipefail
cd "$(dirname "$0")/.."

APP="build/AgentAura.app"
OUT="dist/AgentAura.zip"

[ -d "$APP" ] || { echo "!! $APP 不存在，先跑 ./scripts/build-app.sh"; exit 1; }

# 先驗簽章，壞掉的 bundle 不該被打包出去傳給別人
codesign --verify --deep --strict "$APP" 2>/dev/null \
  || { echo "!! $APP 簽章驗證失敗，不打包"; exit 1; }

mkdir -p dist
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

SIZE=$(ls -lh "$OUT" | awk '{print $5}')
SHA=$(shasum -a 256 "$OUT" | awk '{print $1}')

echo "==> $OUT 就緒（${SIZE}）"
echo "    sha256  $SHA"
echo
echo "    給接收者的說明（請一字不漏轉貼，第 2 步最容易卡死）："
echo "      1. 解壓後把 AgentAura.app 拖進「應用程式」"
echo "      2. 雙擊會跳出「Apple 無法驗證…」——**按「完成」，不要按「移到垃圾桶」**"
echo "         然後到「系統設定 → 隱私權與安全性」，往下捲到「安全性」，"
echo "         會看到「已封鎖 AgentAura.app」與「強制打開」按鈕，按它並驗證身分，"
echo "         再回去開一次 app。"
echo "         （macOS 15 之後「右鍵 →打開」這個做法已經沒有了，只能走系統設定）"
echo "      3. 面板裡按「接上」，然後開一個新的 Claude Code session"
