# Security

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Use GitHub's private reporting instead:
[**Report a vulnerability**](https://github.com/kbsiy0/AgentAura/security/advisories/new).
If that is unavailable, open an issue titled "security contact request" with no details in it,
and I'll follow up privately.

This is a personal project, not a funded one. I'll acknowledge reports as quickly as I can,
but I can't promise a response time.

## What this tool can do on your machine

AgentAura is a local menu bar app plus a Claude Code plugin. It makes no network connections.
Its privileges are the ones your user account already has — it is **not sandboxed** and ships
no entitlements, because it has to write inside `~/.claude` and `~/.agentaura`.

Four things are worth understanding before you install it.

**1. Installing the plugin means Claude Code will execute `aura-hook`.** It runs on 19 hook
events, for the lifetime of the mount. That is how the tool works; there is no version of it
that watches your sessions without running code.

**2. The app runs that binary itself, and clears its quarantine flag first.** To check the
hook actually works, the app executes `~/.claude/skills/agentaura/bin/aura-hook` once and
looks for the file it should have written. Before doing so it removes the binary's
`com.apple.quarantine` attribute, because a quarantined binary is SIGKILLed rather than
failing in a way we could report.

Clicking **Connect** in the app always mounts the copy inside the app bundle, which is the
binary you built. Running `ln -sfn` yourself to point the mount at some other directory is a
different decision: it authorises that code, and the verification step will clear its
quarantine flag too. Only mount directories you would be willing to run.

**2b. The one-command installer clears the quarantine flag for you.** If you install with
`scripts/install.sh` and it finds a published build, it downloads the zip, verifies it against
the published SHA-256, and then removes `com.apple.quarantine` before installing. That is what
makes it a single step rather than a detour through System Settings, and it means you are
relying on the checksum and on this repository rather than on Gatekeeper. A checksum mismatch
aborts the install rather than falling back to anything. `--from-source` skips the download
entirely and builds from the code you just cloned.

**3. State files contain fragments of your work.** `~/.agentaura/sessions/<id>.json` holds the
working directory, the current tool name, and the first part of the assistant's last message.
Files are `0600` inside a `0700` directory, re-tightened on every write. They are deleted when
you uninstall.

**4. If you also use Codex, the same "Connect" model applies to `.codex/hooks.json`.** Clicking
**Connect Codex** writes `~/.codex/hooks.json` — but only if that file doesn't already exist.
It never touches `~/.codex/config.toml`. If you already have your own `hooks.json`, AgentAura
leaves it untouched and shows a snippet to add by hand instead. Removing the mount only deletes
the entry it wrote itself, verified byte-for-byte before deletion — never a file that turned out
to be someone else's.

## Boundaries that are enforced by tests

These are not just intentions. Each has a test, and each test has a recorded mutation showing
it fails when the behaviour is removed.

- **`~/.claude/settings.json` is never written.** A test asserts the file is byte-identical
  before and after connecting, and that the only change anywhere under `~/.claude` is
  `{skills, skills/agentaura}`.
- **Session ids can't escape the state directory.** They are checked against an allowlist
  (`[A-Za-z0-9-_.]`, 1–128 characters, with `.` and `..` rejected) *before* any path is
  built. An end-to-end test feeds `../escaped` to the real binary and asserts nothing appears
  outside the directory.
- **Uninstall can't delete anything else.** Every path is derived in code, never read from
  configuration. Removal only unlinks something `lstat` reports as a symlink, and only erases
  a directory that is named `.agentaura`, sits directly in your home directory, and is a real
  directory rather than a symlink.
- **`aura-hook` always exits 0 and prints nothing.** An observability tool must not interfere
  with the agent it observes.
- **`~/.codex/config.toml` is never touched.** A test drives every connect/disconnect/reconnect
  sequence against `~/.codex` and asserts the file's bytes never change; the only path that ever
  differs is `.codex/hooks.json`.
- **Connecting to Claude Code and to Codex never disturb each other.** Every short sequence of
  operations on one side — connect, disconnect, reconnect, full removal — is driven against the
  other side's files and stored credentials, and both are asserted unchanged afterward.

## Known weaknesses

Found in an audit before this repository was made public. None of them are remotely
exploitable; all require local access or a choice you make yourself. They are listed here
because a security page that only lists strengths isn't useful.

| | |
|---|---|
| **Ad-hoc signed, not notarized** | The app has no verifiable publisher identity. You are trusting the source you built it from. |
| **Development scripts are not hardened** | `scripts/verify-install.sh` interpolates a filename into a Python string, and `scripts/demo-sessions.sh` uses a predictable temp path. They ship with the repository, not with the app. |
| **Some state fields have no length cap** | Only the last assistant message is truncated. A very large tool error would be carried on disk and re-read on every change. Not a vulnerability; a waste. |
| **`codesign --deep` is deprecated, and hardened runtime is off** | Ad-hoc signing has no verifiable identity anyway, so this matters mainly as a prerequisite for notarization later. |

### Fixed before release

| | |
|---|---|
| **Verification ran whatever the mount pointed at** | The startup check un-quarantined and executed the mount target without first confirming it was this app's own copy, automatically and with no confirmation. Now it compares `(dev, ino)` against the app's own bundled plugin and refuses otherwise. Verifying an external mount is left to *Replace mount*, which asks you first. |
| **`AGENTAURA_ROOT` was tightened without validation** | The directory named by the environment variable was `chmod 0700`ed unconditionally, so pointing it at your home directory would silently change its permissions. Now only a path whose last component is `sessions` is touched. |
| **State file writes followed symlinks** | `open()` now uses `O_NOFOLLOW`, so a state file replaced with a symlink makes the write fail rather than follow it. `delete` uses `lstat` for the same reason. |

Each of those three has a test, and each test was verified to fail when the fix is removed.

## Supported versions

Only the latest commit on `main`. There are no released versions yet, and no backports.
