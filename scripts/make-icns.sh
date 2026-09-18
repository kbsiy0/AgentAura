#!/bin/bash
# Builds Resources/AgentAura.icns from scripts/app-icon.swift.
#
# Every size is **rendered at that size**, not resampled from one big image — below 64pt the
# renderer falls back to a simplified form, because eight LEDs at 16pt is under a point each.
# Resampling a 1024 icon down to 16 would throw that away and give you mush.
#
# The .icns is a build product (gitignored), same as plugin/bin/aura-hook: the source of truth
# is the code that draws it.

set -euo pipefail
cd "$(dirname "$0")/.."

VARIANT="${1:-strip}"
SET=$(mktemp -d)/AgentAura.iconset
mkdir -p "$SET"

# name                  point size   scale
render() { swift scripts/app-icon.swift "$VARIANT" "$2" "$SET/$1" "$3" >/dev/null; }

render icon_16x16.png        16 1
render icon_16x16@2x.png     16 2
render icon_32x32.png        32 1
render icon_32x32@2x.png     32 2
render icon_128x128.png     128 1
render icon_128x128@2x.png  128 2
render icon_256x256.png     256 1
render icon_256x256@2x.png  256 2
render icon_512x512.png     512 1
render icon_512x512@2x.png  512 2

mkdir -p Resources
iconutil -c icns "$SET" -o Resources/AgentAura.icns
rm -rf "$(dirname "$SET")"
echo "==> Resources/AgentAura.icns ($(du -h Resources/AgentAura.icns | cut -f1))"
