# Contributing

Thanks for looking. Bug reports and small fixes are very welcome.

This project has some unusual conventions. They exist because each one came from a specific
failure, and they're all written down — so nothing here should feel arbitrary once you know
where to look. If a rule seems wrong, say so in an issue; every rule in
[`CLAUDE.md`](CLAUDE.md) records the mistake that produced it, and that record is the thing to
argue with.

## Getting set up

```bash
git clone https://github.com/kbsiy0/AgentAura.git && cd AgentAura
./scripts/build-plugin.sh      # do this first — see below
swift test
```

**Run `build-plugin.sh` before your first `swift test`.** `plugin/bin/aura-hook` is a build
product and is not in version control. Three install-layout tests fail without it, and the
failure doesn't say "you forgot to build".

You need macOS 13+ and the Swift 6 toolchain (`xcode-select --install`).

## Before you open a pull request

- `swift test` is green.
- `claude plugin validate --strict ./plugin` is clean, if you touched anything under
  `plugin/`. Warnings count as errors here.
- Your branch is not `main`. Use `change/<short-name>`.

## Things that will surprise you

**Tests use [swift-testing](https://github.com/swiftlang/swift-testing), not XCTest.**
`@Test` and `#expect`, not `func testFoo` and `XCTAssert`.

**`--filter` takes a test function name, not a file name.**

**Files are size-limited.** 200 lines under `Sources/`, 300 under `Tests/`. A test reads the
limits off disk, so a new module can't quietly escape them. When a file gets close, that
usually means it is doing two jobs.

**`Sources/AuraCore/` must not import AppKit or SwiftUI.** This is enforced by asking the
compiler for the real module graph, not by grepping for import lines.

**Don't run more than one `swift test` at a time.** They fight over the `.build` lock and it
looks like a hang. Use `git worktree` if you need parallel work. If you kill a test run, check
for a leftover `swiftpm-testing-helper` holding the lock: `pkill -9 -f swiftpm-testing-helper`.

More traps, each with the incident behind it, are in [`CLAUDE.md`](CLAUDE.md).

## What a good change looks like here

**Numbers are derived, not written down.** If a test needs a width, a row height or a count,
it should compute it from the type or measure it from a real render. Constants freeze whatever
was true the day someone typed them — including mistakes. This project has frozen a wrong
number into a "passing" test three separate times, and a user found each one.

**A new test should be able to fail.** Before you trust a test you wrote, break the code it
guards and watch it go red. If it stays green, the test is decoration. Please mention what you
broke and what went red in the pull request — that one line is worth more than the test's
name.

**Prefer asking the platform over approximating it.** Ask the compiler, ask
`swift package dump-package`, ask the official validator. A hand-written approximation of one
of those drifts away from the real thing, silently.

**When you fix user-visible behaviour, measure it first.** Write the diagnostic that captures
the wrong number before you change anything. Then the fix has something to point at, and so
does the test.

## Reporting a bug

The troubleshooting section of [`docs/INSTALL.md`](docs/INSTALL.md) has the commands that
answer most questions about a broken setup. Pasting their output into the issue saves a round
trip.

One thing to know when diagnosing: **`aura-hook` always exits 0 and prints nothing, by
design.** An observability tool must never interfere with the agent it watches. So "no error
message" tells you nothing. Look at whether `~/.agentaura/sessions/` actually has files in it.

For anything security-related, please use the private route in [`SECURITY.md`](SECURITY.md)
rather than a public issue.

## Scope

Some things are deliberately not in this project:

- **Third-party dependencies.** There are none, and that's a feature.
- **Importing custom images for the menu bar icon.** File reading, scaling, monochroming and
  storage are a different scale of work.
- **Anything that writes to `~/.claude/settings.json`.** The tool has never written to it and
  never will. That's what makes a clean uninstall provable.
