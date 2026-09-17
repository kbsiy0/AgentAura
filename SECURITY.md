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

Three things are worth understanding before you install it.

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

**3. State files contain fragments of your work.** `~/.agentaura/sessions/<id>.json` holds the
working directory, the current tool name, and the first part of the assistant's last message.
Files are `0600` inside a `0700` directory, re-tightened on every write. They are deleted when
you uninstall.

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

## Known weaknesses

Found in an audit before this repository was made public. None of them are remotely
exploitable; all require local access or a choice you make yourself. They are listed here
because a security page that only lists strengths isn't useful.

| | |
|---|---|
| **Verification doesn't check mount identity** | The startup check un-quarantines and runs whatever the mount points at, without first confirming it is this app's own copy. It runs automatically with no confirmation. Only reachable if you mounted someone else's directory by hand — at which point Claude Code was already going to run it. |
| **`AGENTAURA_ROOT` is unvalidated** | The environment variable is used as-is, and the directory it names gets `chmod 0700` without asking. Requires the ability to set environment variables for your own Claude Code process. |
| **State file writes don't use `O_NOFOLLOW`** | If a state file were replaced with a symlink, the write would follow it. The directory is `0700`, so this needs your own account or root. |
| **Ad-hoc signed, not notarized** | The app has no verifiable publisher identity. You are trusting the source you built it from. |
| **Development scripts are not hardened** | `scripts/verify-install.sh` interpolates a filename into a Python string, and `scripts/demo-sessions.sh` uses a predictable temp path. They ship with the repository, not with the app. |

## Supported versions

Only the latest commit on `main`. There are no released versions yet, and no backports.
