<h1 align="center">AgentAura</h1>

<p align="center">
  <b>See what your Claude Code sessions are doing — from the menu bar.</b><br>
  One light for all of them. Only the states that need you ever move.
</p>

<p align="center">
  English · <a href="README.zh-TW.md">繁體中文</a>
</p>

<p align="center">
  <img src="docs/readme/icon-states.gif" alt="The menu bar icon in all five states: idle and done sit still, waiting and error pulse" width="620">
</p>

<p align="center">
  <sub>Real frames, rendered from the production views. <code>idle</code>, <code>working</code> and <code>done</code> hold still. Only <code>waiting</code> and <code>error</code> move.</sub>
</p>

---

## The problem

Run several Claude Code sessions at once — a few agents, an overnight pipeline — and your
screen stops telling you anything. Which one is blocked on a permission prompt? Which one
died twenty minutes ago? Which one finished while you were in another window?

You find out by cycling through terminal tabs.

AgentAura puts a single light in the menu bar that **aggregates every session**, and a panel
that lists them individually. You glance up instead of hunting.

## The one rule

**Only states that need you are allowed to move.**

A status indicator that animates constantly is just a second thing competing for your
attention. So motion is rationed, and it is spent only where it buys something:

| State | Look | Motion |
|---|---|---|
| `idle` | Nearly invisible | None |
| `working` (the common case) | Dim, low contrast | A 4-second breath, barely there |
| `done` | Steady green | **None** — you can look when you want |
| `waiting` (needs you) | Amber | Visible 1.1s pulse |
| `error` (needs you) | Red | Double blink |

The aggregate takes the highest-priority state across all sessions —
`error > waiting > working > done > idle` — **regardless of which session wrote last**.
A subagent finishing its tool call must never overwrite "the main agent is waiting for you".

## The panel

Click the icon for the full list: one row per session, with the project name, what it is
doing, and how long the current tool has been running.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/panel-dark.png">
    <img src="docs/readme/panel-light.png" alt="The AgentAura panel listing four sessions with their states" width="380">
  </picture>
</p>

The legend row at the bottom is permanent — and the four coloured dots are buttons. Click one
to open the system colour picker and recolour that state; the menu bar icon and the legend
update live as you drag. Colours persist.

<details>
<summary><b>Options menu</b> — everything else lives here (click to expand)</summary>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/panel-options-dark.png">
    <img src="docs/readme/panel-options-light.png" alt="The Options menu expanded, showing launch at login, reduce motion, icon shape, language and removal entries" width="380">
  </picture>
</p>

Launch at login · Reduce motion (OR-ed with the system setting) · Icon backdrop ·
Menu bar icon shape · Reset colours · Language (English / 繁體中文) · Reconnect ·
Remove mount · Completely remove AgentAura · About · Report an issue · Quit (⌘Q really works).

Right-clicking the menu bar icon opens the same menu directly.
</details>

## Menu bar icon shapes

Six shapes. The LED strip is the default; the other five are SF Symbols.

<p align="center">
  <img src="docs/readme/icon-shapes.png" alt="Six selectable menu bar icon shapes: LED strip, dot, ring, capsule, sparkle, half circle" width="620">
</p>

The picker shows a live thumbnail of each shape, animated at the current state — the
thumbnails are drawn by **the same renderer that draws the real icon**, so they cannot drift
away from what you will actually get.

## Install

Requires macOS 13+, Claude Code, and the Swift 6 toolchain (`xcode-select --install`).

```bash
git clone https://github.com/kbsiy0/AgentAura.git && cd AgentAura

./scripts/build-plugin.sh          # builds the universal aura-hook binary (not in version control)
./scripts/build-app.sh             # produces build/AgentAura.app
open build/AgentAura.app
```

Then in the panel press **Connect**, and **start a new Claude Code session**.

> **The next session, not the current one.** Claude Code loads plugins when a session starts;
> windows that are already open will not pick it up mid-flight. The app says so rather than
> claiming it works immediately.

Connecting creates exactly one symlink: `~/.claude/skills/agentaura` → the app.
**`~/.claude/settings.json` is never written to** — not "cleaned up afterwards", never touched
at all, so there is no way to leave behind a dead hook pointing at a deleted binary.

**Removing it:** Options → *Remove mount* unhooks it; Options → *Completely remove AgentAura*
returns the machine to the state it was in before installation. `./scripts/verify-uninstall.sh`
checks that claim item by item. Full details and troubleshooting in
[`docs/INSTALL.md`](docs/INSTALL.md).

## What it touches on your machine

Worth knowing before you install anything that watches your work:

| | |
|---|---|
| **Network** | The app opens no connections of its own — no telemetry, no update check, no crash reporting. There is no HTTP client in the codebase at all. The only two URLs in the source are the repository and *Report an issue*, which are handed to your browser when you click them. |
| **Writes** | `~/.agentaura/sessions/<id>.json` (mode `0600`) and its own `UserDefaults` domain `io.agentaura.app`. That is all. |
| **Reads** | Its own state files. It does not read your transcripts, your prompts, or your code. |
| **The one symlink** | `~/.claude/skills/agentaura`. The installer is restricted to that path (and creating `~/.claude/skills/` if missing), verified by `realpath` after resolution. |
| **Permissions** | None requested. No screen recording, no accessibility, no full disk access. "Launch at login" uses `SMAppService` and is opt-in. |
| **Dependencies** | Zero third-party packages. Everything is Foundation / AppKit / SwiftUI. |

What Claude Code sends to the hook is metadata — session id, project directory name, event
type, tool name, timing. AgentAura keeps a reduced form of that on disk so the panel can be
redrawn, and deletes it on uninstall.

## How it works

```
Claude Code plugin hooks (19 events, all async: true)
        │
        ▼
aura-hook ──read-merge-write under flock──▶ ~/.agentaura/sessions/<id>.json (0600)
                                                  │ FSEvents
                                                  ▼
                                          PipelineGraph (composition root)
                                          ├─ NSStatusItem + custom-drawn animation
                                          └─ SwiftUI panel
```

Four modules: `AuraCore` (pure logic, zero UI imports — enforced by a compiler-driven test),
`AuraHookFile` (files + FSEvents), `aura-hook` (the CLI), `AgentAuraApp` (AppKit).

`aura-hook` **always exits 0, with empty stdout and stderr, whatever happens.** Observability
must never interfere with the thing it observes. The cost is that exit codes are useless for
verification, so every check looks at the artefact instead of the return value.

## Built from measurement, not documentation

The event contract was written against **141 real hook payloads** captured over three rounds,
not from the documentation. Measurement overturned several documented assumptions and caught
three bugs that reading could not have:

1. **Subagent tool events share the parent's `session_id`.** Measured: main and subagent
   events interleaved five times in one session, 20 ms apart at the closest. Under
   last-write-wins, a subagent's `PostToolUse` overwrites the main agent's `PermissionRequest`
   within 20 ms — *silently erasing the single most important signal the product has.*
   Fixed by giving main and subagent separate slots and taking the priority max.

2. **Denying a permission prompt produces no hook event at all.** The sequence is
   `PermissionRequest` → (you press Deny) → nothing → `SessionEnd`. So `waiting` must never
   survive into the "ended but unacknowledged" tail, or a session you already answered keeps
   the icon amber forever.

3. **`PostToolUseFailure`'s error field is called `error`, not `tool_error`.** The first
   conclusion written into the spec was "it has no error field" — because the payloads were
   being inspected through a hand-written key filter that did not contain the real field name.
   *Looking at data through your own assumptions only ever shows you your assumptions.*

> The payload fixtures in `Tests/AuraCoreTests/Fixtures/` are **de-identified**: paths, prompts,
> assistant messages and file contents were replaced before this repository was made public.
> The event structure — which is what the contract and its tests actually depend on — is
> untouched, and the raw captures are not published.

The method corrects itself, too: round one concluded "no event carries `model`", and round two
disproved it. Both rounds are kept in the spec, with the reasoning for the reversal.

## Documentation

| Document | Contents |
|---|---|
| [`docs/superpowers/specs/2026-09-08-agentaura-design.md`](docs/superpowers/specs/2026-09-08-agentaura-design.md) | **The canonical design.** Where documents conflict, this one wins |
| [`docs/INSTALL.md`](docs/INSTALL.md) | Install, uninstall, troubleshooting, upgrading |
| [`docs/2026-09-09-agentaura-audit.html`](docs/2026-09-09-agentaura-audit.html) | Build audit — eight families of *tests that guard nothing*, with the fixes |
| [`docs/2026-09-11-subagent-state-priority-audit.html`](docs/2026-09-11-subagent-state-priority-audit.html) | How background subagents made the light lie, and the measured timeline |
| [`CLAUDE.md`](CLAUDE.md) | Project instructions for Claude Code: invariants with their provenance, and the traps |

HTML documents open straight from disk (`file://`). Nothing is account-gated.

## Development

```bash
swift test                         # full suite
swift test --filter <test name>    # one test (the function name, not the file)
```

760 tests across 144 suites. Swift 6 with strict concurrency; tests use
[swift-testing](https://github.com/swiftlang/swift-testing) (`@Test` / `#expect`), not XCTest.

A clean clone needs `./scripts/build-plugin.sh` first — `plugin/bin/aura-hook` is a build
product and is not in version control, and three install-layout tests are red without it.

The testing philosophy — ask the platform rather than approximating it, derive every number
from types or disk rather than freezing it as a constant, and require a mutation record for
every gate — is written up in [`CLAUDE.md`](CLAUDE.md), along with the failures that produced
each rule.

The README's images are generated, not screenshotted:

```bash
AURA_RENDER_README=1 swift test --filter ReadmeAssetRenderer
```

They render the real production views offscreen, which keeps them reproducible and keeps real
project names and paths out of a public repository.

## License

[MIT](LICENSE).
