## What this changes

<!-- And why. If it fixes an issue, link it. -->

## How you know it works

- [ ] `swift test` is green
- [ ] `claude plugin validate --strict ./plugin` is clean (only if you touched `plugin/`)

**If you added or changed a test:** what did you break to make it fail, and what went red?
One line is enough. A test nobody has seen fail is decoration — see
[CONTRIBUTING.md](../CONTRIBUTING.md).

<!--
Worth knowing:
- Run ./scripts/build-plugin.sh before your first swift test, or three tests fail confusingly.
- Sources/ files are capped at 200 lines, Tests/ at 300. A test enforces it.
- Numbers in tests should be derived from types or measured, not typed in.
-->
