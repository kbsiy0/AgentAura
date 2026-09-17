#!/bin/bash
# One-command install for AgentAura.
#
#   ./scripts/install.sh                 # from a clone
#   curl -fsSL https://raw.githubusercontent.com/kbsiy0/AgentAura/main/scripts/install.sh | bash
#
# Installs AgentAura into /Applications and opens it.
#
# By default it downloads the published build (1.3 MB, checksum-verified) so you don't need
# the Swift toolchain. If there's no release, or the download fails, it builds from source
# instead. Pass --from-source to skip the download and always build.
#
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
RELEASE_BASE="https://github.com/kbsiy0/AgentAura/releases/latest/download"
FROM_SOURCE=0
[ "${1:-}" = "--from-source" ] && FROM_SOURCE=1

# ---------------------------------------------------------------- preflight

step "Checking requirements"

os_major=$(sw_vers -productVersion | cut -d. -f1)
[ "$os_major" -ge 13 ] || die "AgentAura needs macOS 13 or later. This Mac is on $(sw_vers -productVersion)."
info "macOS $(sw_vers -productVersion)"

HAVE_SWIFT=0
command -v swift >/dev/null 2>&1 && HAVE_SWIFT=1
if [ "$HAVE_SWIFT" = 1 ]; then
    info "$(swift --version 2>/dev/null | head -1)"
else
    info "no Swift toolchain — will use the published build"
fi

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

BUILT_APP=""

download_release() {
    local tmp; tmp=$(mktemp -d)
    curl -fsSL "$RELEASE_BASE/AgentAura.zip" -o "$tmp/AgentAura.zip" 2>/dev/null || return 1
    curl -fsSL "$RELEASE_BASE/AgentAura.zip.sha256" -o "$tmp/AgentAura.zip.sha256" 2>/dev/null || return 1

    # **A mismatch is fatal, not a reason to fall back.** Falling back would turn "someone
    # tampered with the download" into "we quietly did something else instead", which is
    # exactly the signal you want to hear about.
    ( cd "$tmp" && shasum -a 256 -c AgentAura.zip.sha256 >/dev/null 2>&1 ) \
        || die "The downloaded file doesn't match its published checksum. Stopping.
    Nothing was installed. Please open an issue — this should never happen."
    info "checksum verified"

    ditto -x -k "$tmp/AgentAura.zip" "$tmp/unpacked" || return 1
    [ -d "$tmp/unpacked/$APP_NAME" ] || return 1

    # The app is ad-hoc signed, so macOS would block the first launch and send you to
    # System Settings. Clearing the quarantine flag here is what makes this a one-step
    # install — and it is a real trade: you are trusting this script and the checksum above
    # instead of Gatekeeper. Build from source with --from-source if you'd rather not.
    xattr -dr com.apple.quarantine "$tmp/unpacked/$APP_NAME" 2>/dev/null || true
    info "quarantine flag cleared (see SECURITY.md for what that means)"

    BUILT_APP="$tmp/unpacked/$APP_NAME"
}

if [ "$FROM_SOURCE" = 0 ]; then
    step "Downloading the published build"
    if download_release; then
        info "1.3 MB, no toolchain needed"
    else
        info "no published build available — falling back to building from source"
    fi
fi

if [ -z "$BUILT_APP" ]; then
    [ "$HAVE_SWIFT" = 1 ] || die "Building from source needs the Swift toolchain.

    Run this, let it finish, then run this installer again:

        xcode-select --install

    That's Apple's Command Line Tools, about 1 GB, one time only."

    if [ -f "scripts/build-app.sh" ] && [ -f "Package.swift" ]; then
        SRC="$PWD"
        step "Building from this checkout (about 30 seconds)"
    else
        command -v git >/dev/null 2>&1 || die "git isn't available, so the source can't be downloaded."
        SRC=$(mktemp -d)/AgentAura
        step "Downloading the source"
        git clone -q --depth 1 "$REPO_URL" "$SRC" || die "Couldn't clone $REPO_URL"
        step "Building (about 30 seconds)"
    fi
    cd "$SRC"
    ./scripts/build-plugin.sh >/dev/null || die "Failed to build the hook binary. Run ./scripts/build-plugin.sh to see why."
    ./scripts/build-app.sh >/dev/null || die "Failed to build the app. Run ./scripts/build-app.sh to see why."
    info "built"
    BUILT_APP="$SRC/build/$APP_NAME"
fi

[ -d "$BUILT_APP" ] || die "Ended up with no app to install. This is a bug in the installer."

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
ditto "$BUILT_APP" "$DEST" || die "Couldn't copy the app into /Applications."
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
