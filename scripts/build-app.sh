#!/usr/bin/env bash
# 組出 AgentAura.app（universal），並驗證 bundle 結構與 LSUIElement。
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/AgentAura.app

echo "==> 建置 universal 執行檔"
swift build -c release --arch arm64   --product AgentAuraApp
swift build -c release --arch x86_64  --product AgentAuraApp

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/AgentAuraApp" \
  .build/arm64-apple-macosx/release/AgentAuraApp \
  .build/x86_64-apple-macosx/release/AgentAuraApp
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> 驗證"
lipo -archs "$APP/Contents/MacOS/AgentAuraApp"
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist"
test -x "$APP/Contents/MacOS/AgentAuraApp"

echo "==> ad-hoc 簽章（未簽章的 bundle 在部分系統設定下無法啟動）"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP" 2>&1 | tail -2

echo "==> $APP 就緒"
