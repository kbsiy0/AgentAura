#!/usr/bin/env bash
# 組出 AgentAura.app（universal），並驗證 bundle 結構與 LSUIElement。
# D-g：把 plugin/ 整包複製進 Contents/Resources/plugin/，讓 app 自我包含
#      （一鍵接上時把 symlink 指向 bundle 內這份，而不是 repo checkout）。
#      hooks.json 用 ${CLAUDE_PLUGIN_ROOT} 相對路徑，所以複製零 hook 改動。
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/AgentAura.app

echo "==> 建置 universal 執行檔"
swift build -c release --arch arm64   --product AgentAuraApp
swift build -c release --arch x86_64  --product AgentAuraApp

echo "==> 確認 plugin/bin/aura-hook 存在（bundle 化的前提）"
if [ ! -x plugin/bin/aura-hook ]; then
  echo "!! plugin/bin/aura-hook 不存在或不可執行。" >&2
  echo "!! 這是 gitignored 建置產物，乾淨 clone 上不會自動出現。" >&2
  echo "!! 請先跑：./scripts/build-plugin.sh" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/AgentAuraApp" \
  .build/arm64-apple-macosx/release/AgentAuraApp \
  .build/x86_64-apple-macosx/release/AgentAuraApp
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> 複製說明文件（依語言，T30／i18n）"
# 不手抄「有哪些語言」：glob 出 Resources/help-*.html 全部複製，命名規則跟
# `AppDelegate+PanelActions.helpResourceName(for:)`（help-<Language.rawValue>.html）
# 是同一條，哪天 Language 真的加第三個 case，這裡不用改，只要多放一個對應檔名的資源檔。
shopt -s nullglob
help_docs=(Resources/help-*.html)
shopt -u nullglob
if [ ${#help_docs[@]} -eq 0 ]; then
  echo "!! 找不到任何 Resources/help-*.html" >&2
  exit 1
fi
cp "${help_docs[@]}" "$APP/Contents/Resources/"

# App icon。**每次建置都重新產生**，不從版控拿：真相是 scripts/app-icon.swift 那段程式碼，
# 而不是某次有人手動匯出的檔案。每個尺寸都在該尺寸原生繪製（16pt 用簡化版，不是把 1024
# 縮下來），理由見 scripts/make-icns.sh。
./scripts/make-icns.sh >/dev/null
cp Resources/AgentAura.icns "$APP/Contents/Resources/AgentAura.icns"

echo "==> 複製 plugin/ 進 bundle（D-g）"
cp -R plugin "$APP/Contents/Resources/plugin"

echo "==> 驗證"
lipo -archs "$APP/Contents/MacOS/AgentAuraApp"
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist"

# icon 接線：宣告的檔名必須真的存在於 bundle 裡。少了這一條，Info.plist 指向一個不存在的
# 檔案時 Finder 只會安靜地顯示預設圖示——看起來像「icon 沒做」，不像「接線斷了」。
icon_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist")
test -f "$APP/Contents/Resources/$icon_name.icns" \
  || { echo "!! Info.plist 指定 icon 為 $icon_name，但 $APP/Contents/Resources/$icon_name.icns 不存在" >&2; exit 1; }
test -x "$APP/Contents/MacOS/AgentAuraApp"
# cp -R 在 macOS 上會保留權限位元，但這裡實測確認而非假設：
# 複製之後的可執行位元若掉了，這一行必須讓腳本非零退出，而不是留下一個
# 「看起來裝好了、按接上其實壞掉」的 bundle。
test -x "$APP/Contents/Resources/plugin/bin/aura-hook" \
  || { echo "!! 複製後 aura-hook 掉了可執行位元" >&2; exit 1; }
for f in "${help_docs[@]}"; do
  test -f "$APP/Contents/Resources/$(basename "$f")" \
    || { echo "!! 複製後缺 $(basename "$f")" >&2; exit 1; }
done

echo "==> ad-hoc 簽章（未簽章的 bundle 在部分系統設定下無法啟動；巢狀 Mach-O 一併簽）"
# 順序重要：codesign 必須在複製 plugin/ 之後跑，這樣 --deep 才會把
# Contents/Resources/plugin/bin/aura-hook 這個巢狀 Mach-O 一起 ad-hoc 簽掉
# （實測 --verify --strict --deep 通過）。
codesign --force --deep --sign - "$APP"
codesign --verify --verbose --strict --deep "$APP" 2>&1 | tail -2

echo "==> $APP 就緒"
