# Installing AgentAura

English · [繁體中文](INSTALL.zh-TW.md)

## Requirements

- macOS 13 or later
- Claude Code
- The Swift 6 toolchain, to build the app: `xcode-select --install`

There is no prebuilt download yet. You build it once, then use it like any other app.

## Install

### The simple way: download the installer

[**Download AgentAura.dmg**](https://github.com/kbsiy0/AgentAura/releases/latest/download/AgentAura.dmg) · 1.4 MB · no terminal, no toolchain

1. Open the file you downloaded.
2. Drag **AgentAura** onto the **Applications** folder.
3. Open it from Applications. See [the first launch](#the-first-launch) below — macOS blocks
   it once, and the button you want is not the obvious one.
4. In the app: click **Connect**, then start a **new** Claude Code session.

### From the terminal

```bash
curl -fsSL https://raw.githubusercontent.com/kbsiy0/AgentAura/main/scripts/install.sh | bash
```

About five seconds, and no security prompt: the script verifies the download against its
published SHA-256 and clears the quarantine flag itself. Read [the script](../scripts/install.sh)
before you pipe it into your shell. If the download fails it builds from source instead
(needs the Swift toolchain); `--from-source` forces that.

The installer doesn't touch `~/.claude` — connecting is a button you press in the app,
deliberately.

### The first launch

The app is ad-hoc signed and **not notarized by Apple**, so the first launch is blocked. This
is expected, and it happens once.

1. Double-click the app. You'll get **"Apple could not verify AgentAura.app is free of
   malware."**
2. **Click Done. Do not click Move to Trash** — that's the prominent button, and it's the
   wrong one.
3. Open **System Settings ▸ Privacy & Security**, scroll to **Security**, and click
   **Open Anyway**. Authenticate.
4. Open the app again. It won't ask again.

> ### ⚠️ The right-click → Open trick no longer exists
>
> macOS 15 Sequoia removed it. Older articles still recommend it. On current macOS the dialog
> has only two buttons — **Move to Trash** and **Done** — and the prominent one is *Move to
> Trash*. Following the old instructions gets you stuck, or throws the app away.
> (Confirmed on macOS 26.6.2.)

Notarization would remove this step entirely. It needs the Apple Developer Program
($99/year), so it isn't done yet.

### Building it yourself

An app you built on your own machine isn't blocked by Gatekeeper at all. See
[Developer setup](#developer-setup) — it covers both building the app and mounting the
repository directly so rebuilds take effect without reinstalling.

## When it takes effect

**Connect affects the next Claude Code session you start, not the ones already open.**

Claude Code loads plugins when a session starts. A window that is already running will not
pick up a new plugin part-way through. The app tells you this instead of claiming it works
right away.

You do **not** need to restart AgentAura itself.

## Can't see the icon in the menu bar?

The icon is a small LED strip, not a picture. If you can't find it after installing:

1. **Check it's running:** `pgrep -fl AgentAura.app`. If that prints something, the app is
   fine and the icon is just hidden.
2. **Hold ⌘ and drag** other menu bar icons to make room. The icon will appear.
3. **MacBooks with a notch** (14" / 16" Pro) hit this often. Once you have enough menu bar
   items, new ones get placed behind the notch, where you can't see or click them.

This is also likely right after *Completely remove* followed by a reinstall. Removing clears
the icon's saved position along with everything else, so macOS picks a new spot — sometimes
behind the notch. Step 2 fixes it.

## Nothing happens after installing? Check `/plugin` first

Run `/plugin` inside Claude Code and look for `agentaura`. If you see:

```
Failed to load hooks from .../hooks.json
```

then **the whole hook file was rejected**, not just one entry. AgentAura will do nothing at
all, while the menu bar looks perfectly normal.

**Cause:** a version gap. One of the hook events we register doesn't exist in your version of
Claude Code, and the file is parsed all-or-nothing. A single unrecognised key takes the whole
file down with it.

**Fix: update Claude Code to the latest version.** The error message lists every event your
version knows about. Compare that list with `plugin/hooks/hooks.json` to see which one differs.

<details>
<summary>Note for maintainers</summary>

`claude plugin validate --strict` passing **on your machine** does not mean someone else's
runtime will accept the file. Measured on 2026-09-15 with Claude Code 2.1.271: the local
validator only warns about an unknown event ("entry ignored at runtime"), but another
machine's runtime rejected the entire file. Keep that difference in mind when adding a hook
event.
</details>

## Someone handed you a zip

Same as the download: unzip it, drag the app into Applications, and follow
[the first launch](#the-first-launch). The zip has no installer window, so nothing warns you
about the dialog — that's the only difference, and it's the part that matters.

<details>
<summary>Does the hook still work after you allow the app? Yes.</summary>

Measured 2026-09-15. Straight after unzipping, the `aura-hook` binary inherits the quarantine
attribute. Running it then gets it **SIGKILLed (exit 137)** and it writes no state file — while
`access(X_OK)` still cheerfully reports it as executable. That's why every check in this
project looks at the output file, never at a permission bit or exit code.

After you allow the app, the hook binary **still carries the quarantine attribute**, but it
runs fine (exit 0, state file written). macOS honours your approval of the app, not a per-file
flag.
</details>

## Developer setup

If you're changing the code, mount the repository directly instead of the built app. Then a
rebuild takes effect immediately, with no reinstall.

```bash
./scripts/build-plugin.sh                            # build aura-hook into plugin/bin/
claude plugin validate --strict ./plugin             # official validator; zero errors, zero warnings
ln -sfn "$PWD/plugin" ~/.claude/skills/agentaura     # mount it (settings.json is not touched)
./scripts/verify-install.sh                          # run a real session and check the hook fired

./scripts/build-app.sh                               # build build/AgentAura.app
./scripts/verify-app.sh                              # launch checks
open build/AgentAura.app
```

Use `cp -R` instead of `ln -sfn` if you want to freeze a version. That is what the app's
**Connect** button does: it points at the frozen copy inside the app bundle.

## Uninstalling

The Options menu has **two** removal choices with different scope:

**Remove mount** deletes only the link at `~/.claude/skills/agentaura`. The app, your colours,
your session history and the login item all stay. Use this to pause AgentAura and reconnect
later with the same settings.

**Completely remove AgentAura** returns the machine to how it was before you installed
anything. In order, it: turns off the login item, removes the mount, deletes session state in
`~/.agentaura`, clears preferences, moves `AgentAura.app` to the Trash, and quits. You get a
confirmation dialog listing all of it first. Everything is recoverable until you empty the
Trash.

<details>
<summary>The same thing by hand (developer path)</summary>

```bash
pkill -f AgentAura.app            # quit the app
rm ~/.claude/skills/agentaura     # remove the mount; hooks stop firing
rm -rf ~/.agentaura               # session state — safe to delete any time
defaults delete io.agentaura.app  # colours and toggles
rm -rf build/AgentAura.app        # the app itself (a build product; rebuild any time)
```

For the login item, open **System Settings → General → Login Items** and remove the AgentAura
row. There is deliberately no command for this step — see the warning below.

There is no `claude plugin uninstall` step. That applies to plugins installed from a
marketplace. A skills-dir mount is removed by deleting the symlink above.

> ### ⚠️ Never use `sfltool resetbtm` to remove a login item
>
> It does not remove AgentAura's login item. It **wipes the background-task database for the
> entire machine**. Every app you have set to start at login disappears at once, with no undo,
> and you add them back one by one.
>
> This project hit it for real on 2026-09-14: an agent ran the command just to check whether
> it existed, and eight login items on the development machine went to zero (`sfltool dumpbtm`
> went from 1593 lines to 21). To remove one app's login item, use System Settings.
</details>

### Checking that removal was clean

Run the script. Don't keep a hand-written checklist — those drift away from the code, which is
exactly what went wrong with an earlier version of this document.

```bash
./scripts/verify-uninstall.sh                       # checks /Applications/AgentAura.app
./scripts/verify-uninstall.sh build/AgentAura.app   # or wherever your app actually is
```

It checks five places — the mount, `~/.agentaura`, the `io.agentaura.app` preferences, the
login item, and the app bundle. If any of them still exists it exits non-zero and names it.

`~/.claude/settings.json` needs no cleanup, because AgentAura never writes to it. That's
verified separately, by check 3 of `verify-install.sh`.

## Troubleshooting

### The light never reacts

```bash
ls -la ~/.agentaura/sessions/                  # are there any state files?
claude plugin list | grep -A3 -i agentaura     # loaded? should show ✔ loaded
ls -la ~/.claude/skills/agentaura              # is the mount there, pointing at the right app?
claude plugin validate --strict ./plugin       # any errors or warnings in the manifest?
lipo -archs plugin/bin/aura-hook               # is the binary there, right architecture?
echo '{"hook_event_name":"Stop","session_id":"t1"}' | ./plugin/bin/aura-hook; echo $?
```

`aura-hook` **always exits 0 and never prints anything**, by design — an observability tool
must not interfere with the agent it observes. So "no error message" does not mean it worked.
Look at whether `~/.agentaura/sessions/` actually has files in it.

### The app says "Connected" but the light never comes on

macOS may have quarantined the hook binary. Every call gets blocked by the system and fails
silently, so the app looks connected while the hook has never once run.

Connect already tests for this: it runs `aura-hook` for real and checks whether a file appeared.
When it catches this, it says "macOS blocked the hook" rather than claiming success. To fix it,
move the app into Applications and open it again, or allow it under
**System Settings → Privacy & Security**.

### The app was moved or renamed

The mount points at where the app was when you connected. Move it or rename it and the light
stays dark. Put the app back, or click **Reconnect** in the panel from its new location.

## State directory

`~/.agentaura/sessions/<session_id>.json` — one file per Claude Code session, holding its
current state. Safe to delete at any time; the app rebuilds it on the next hook event.

## Upgrading from an older version

State files are `0600` and the directory is `0700`. They contain the working directory, tool
arguments, and the start of the assistant's last message.

Early versions created them as `0644`. Newer versions tighten the permissions **on every
write**, so any session still running fixes itself. Files for sessions that will never be
written again stay at `0644`. To fix them all at once:

```bash
chmod 600 ~/.agentaura/sessions/*.json
```

Or just `rm -rf ~/.agentaura`. It only holds transient state, and the app rebuilds it on the
next hook event.

<details>
<summary>Why the mount lives in <code>~/.claude/skills/</code> and not a marketplace</summary>

`claude plugin install` only installs from a marketplace. Installing locally means running
`claude plugin marketplace add <path>` first — and **that writes to
`~/.claude/settings.json`.** Measured: it adds an `extraKnownMarketplaces` entry pointing at
the repository directory. That breaks the project's rule that AgentAura never modifies
`settings.json`.

`~/.claude/skills/<name>/` is Claude Code's other plugin-loading path
(`claude plugin init --help`: "auto-loads next session as `<name>@skills-dir`"). Measured:

- Five existing skills-dir plugins appear nowhere in `settings.json`
- After symlinking, `claude plugin list` shows `agentaura@skills-dir ... ✔ loaded`
- A real `claude -p` session fires the hooks and writes complete state files
- The md5 of `settings.json` does not change at all

A symlink rather than a copy means rebuilding with `build-plugin.sh` takes effect immediately,
with no reinstall. Use `cp -R` instead if you want to freeze a version — that is what the app's
Connect button does, pointing at the frozen copy inside the app bundle.
</details>
