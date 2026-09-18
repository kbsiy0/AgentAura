#!/bin/bash
# Builds dist/AgentAura.dmg — the double-click installer for people who don't use a terminal.
#
#   ./scripts/make-dmg.sh
#
# The window layout (icon positions, background) is set through Finder via AppleScript, which
# needs Automation permission. If that's refused or unavailable the DMG is still produced and
# still works — it just looks like a plain folder instead of a styled window. The script says
# which of the two happened rather than leaving you to guess.
#
# **This does not remove the Gatekeeper prompt.** The app is ad-hoc signed and not notarized,
# so the first launch is blocked no matter how it was delivered. All this can do is warn people
# before they meet a dialog whose most prominent button is "Move to Trash". That warning is
# drawn into the background image.

set -euo pipefail

BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; RESET=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
info() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }
die()  { printf '\n%s✗ %s%s\n\n' "$RED" "$1" "$RESET" >&2; exit 1; }

APP="build/AgentAura.app"
VOL="AgentAura"
OUT="dist/AgentAura.dmg"
STAGE=$(mktemp -d)/dmg
RW="$(mktemp -d)/rw.dmg"

[ -d "$APP" ] || die "$APP isn't there. Run ./scripts/build-app.sh first."

step "Staging"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/AgentAura.app"
ln -s /Applications "$STAGE/Applications"
swift scripts/dmg-background.swift "$STAGE/.background/background.png" >/dev/null
info "app, Applications alias, background"

step "Creating the disk image"
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
    -format UDRW -ov "$RW"
MOUNT=$(hdiutil attach "$RW" -nobrowse -noautoopen | grep -o '/Volumes/.*' | head -1)
[ -n "$MOUNT" ] || die "Couldn't mount the working image."
info "mounted at $MOUNT"

step "Setting the window layout"
# `|| true` on purpose: a missing Automation permission must not fail the build. The DMG is
# usable either way, and the next line reports which outcome you got.
osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 540}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 96
        set background picture of opts to file ".background:background.png"
        set position of item "AgentAura.app" of container window to {160, 195}
        set position of item "Applications" of container window to {480, 195}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

if [ -f "$MOUNT/.DS_Store" ]; then
    info "layout applied (background + icon positions)"
else
    info "layout NOT applied — Finder automation was unavailable."
    info "the DMG still works; it will just open as a plain window."
fi

step "Compressing"
sync
hdiutil detach "$MOUNT" -quiet
mkdir -p dist
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" -ov
rm -rf "$STAGE" "$RW"
( cd dist && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )

step "Done"
info "$OUT  ($(du -h "$OUT" | cut -f1))"
cat dist/AgentAura.dmg.sha256 | sed 's/^/    /'

cat <<EOF

${BOLD}What the person who downloads this will do:${RESET}
  1. Double-click the .dmg
  2. Drag AgentAura onto the Applications folder
  3. Open it from Applications. macOS blocks it the first time — the background
     image tells them to click Done (not Move to Trash) and then approve it in
     System Settings ▸ Privacy & Security.
  4. In the app: click Connect, then start a new Claude Code session.

Step 3 disappears only with Apple notarization (Developer Program, \$99/year).
Nothing else removes it.
EOF
