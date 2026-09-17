#!/bin/bash
# One-command install for AgentAura.
#
#   ./scripts/install.sh                 # from a clone
#   curl -fsSL https://raw.githubusercontent.com/kbsiy0/AgentAura/main/scripts/install.sh | bash
#
# Builds the hook binary and the app, installs it into /Applications, and opens it.
# It does not touch ~/.claude — connecting is a button you press in the app, on purpose.
#
# You can read this whole file in about a minute. Please do, before running the curl form.

set -euo pipefail

BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
info() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }
die()  { printf '\n%s✗ %s%s\n\n' "$RED" "$1" "$RESET" >&2; exit 1; }

APP_NAME="AgentAura.app"
DEST="/Applications/$APP_NAME"
REPO_URL="https://github.com/kbsiy0/AgentAura.git"

# ---------------------------------------------------------------- preflight

step "Checking requirements"

os_major=$(sw_vers -productVersion | cut -d. -f1)
[ "$os_major" -ge 13 ] || die "AgentAura needs macOS 13 or later. This Mac is on $(sw_vers -productVersion)."
info "macOS $(sw_vers -productVersion)"

if ! command -v swift >/dev/null 2>&1; then
    die "The Swift toolchain isn't installed.

    Run this, let it finish, then run this installer again:

        xcode-select --install

    That downloads Apple's Command Line Tools (about 1 GB). It's a one-time cost;
    AgentAura itself builds in around 30 seconds."
fi
info "$(swift --version 2>/dev/null | head -1)"

# Claude Code is what AgentAura watches. Missing it isn't fatal — you may be installing
# ahead of time — so this warns rather than stops.
if command -v claude >/dev/null 2>&1; then
    info "claude CLI found"
else
    info "claude CLI not found — AgentAura will install fine, but it has nothing to watch yet"
fi

[ -w /Applications ] || die "/Applications isn't writable by your account, so this script can't install there.
    Build it yourself with ./scripts/build-app.sh and move the app wherever you like."

# ---------------------------------------------------------------- get source

if [ -f "scripts/build-app.sh" ] && [ -f "Package.swift" ]; then
    SRC="$PWD"
    step "Building from this checkout"
else
    command -v git >/dev/null 2>&1 || die "git isn't available, so the source can't be downloaded."
    SRC=$(mktemp -d)/AgentAura
    step "Downloading the source"
    info "$REPO_URL"
    git clone -q --depth 1 "$REPO_URL" "$SRC" || die "Couldn't clone $REPO_URL"
fi
cd "$SRC"

# ---------------------------------------------------------------- build

step "Building (about 30 seconds)"
./scripts/build-plugin.sh >/dev/null || die "Failed to build the hook binary. Run ./scripts/build-plugin.sh to see why."
info "hook binary built for both architectures"
./scripts/build-app.sh >/dev/null || die "Failed to build the app. Run ./scripts/build-app.sh to see why."
info "app built"

[ -d "build/$APP_NAME" ] || die "The build reported success but build/$APP_NAME isn't there."

# ---------------------------------------------------------------- install

step "Installing to /Applications"

if pgrep -f "$APP_NAME/Contents/MacOS" >/dev/null 2>&1; then
    info "quitting the running copy first"
    pkill -f "$APP_NAME/Contents/MacOS" || true
    sleep 2
fi

if [ -d "$DEST" ]; then
    info "replacing the existing install (your settings and colours are kept —"
    info "they live in your preferences, not in the app)"
    rm -rf "$DEST"
fi

# ditto rather than cp -R: it preserves the code signature and extended attributes.
ditto "build/$APP_NAME" "$DEST" || die "Couldn't copy the app into /Applications."
info "$DEST"

codesign --verify --strict "$DEST" 2>/dev/null || die "The installed app failed signature verification. Don't run it; please open an issue."
info "signature verified"

# ---------------------------------------------------------------- done

step "Opening AgentAura"
open "$DEST"

cat <<EOF

${GREEN}${BOLD}Installed.${RESET} Two things left, both in the app:

  ${BOLD}1.${RESET} Click ${BOLD}Connect${RESET} in the panel.
     This creates one symlink at ~/.claude/skills/agentaura and nothing else.
     Your ~/.claude/settings.json is never written to.

  ${BOLD}2.${RESET} Start a ${BOLD}new${RESET} Claude Code session.
     Claude Code loads plugins when a session starts, so windows you already
     have open won't pick it up.

Can't see the icon? It's a small LED strip, not a picture. Hold ⌘ and drag other
menu bar icons to make room — on MacBooks with a notch it often lands behind it.

To remove it later: Options → Completely remove AgentAura. That puts the machine
back the way it was, and ./scripts/verify-uninstall.sh checks that item by item.

EOF
