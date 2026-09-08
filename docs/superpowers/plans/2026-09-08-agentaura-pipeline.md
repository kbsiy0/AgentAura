# AgentAura 資料管線 實作計畫（M0-M3）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 Claude Code hook → 狀態檔 → `IconState` 的完整資料管線，以 headless renderer 端到端驗證，不含任何 UI。

**Architecture:** Claude Code plugin 註冊全部 async hook → `aura-hook` CLI 在 `flock` 下 merge-write `~/.agentaura/sessions/<session_id>.json` → `HookFileSource` 以 FSEvents 監看 → `SessionReducer` 產 `SessionState` → `AggregatePolicy` 產 `IconState`。核心邏輯（`AuraCore`）為純函數且零 AppKit 依賴。

**Tech Stack:** Swift 6（swift-testing）、SwiftPM、FSEvents、`flock(2)`、`sysctl(KERN_PROC_PID)`、Claude Code plugin hooks

**Spec:** `docs/superpowers/specs/2026-09-08-agentaura-design.md`

**範圍說明：** 本計畫涵蓋 spec 的 M0-M3。M4（menu bar 形態 A/B）與 M5（面板 + 自我健檢）另出一份計畫 —— T01 的實測結果可能改變那部分的設計（例如 `getppid()` 若不等於 claude 本體，liveness 需重做）。

## Global Constraints

- 單檔 **≤ 200 行**（超過代表責任不清，拆小單位）
- `AuraCore` **不得 import AppKit / SwiftUI**，此約束由測試強制
- `aura-hook` **任何錯誤都必須靜默 `exit 0`** —— 觀測性絕不可干擾 agent
- 全部 hook 皆 `"async": true`
- 平台floor：**macOS 13+**
- `AuraCore` 覆蓋率 **≥ 90%**
- 聚合優先序（D1）：**`error > waiting > working > done > idle`**
- 未知 `hook_event_name`、未知 `notification_type` → **不改變 activity**
- 狀態檔 `"schema": 1`
- 狀態檔路徑：`~/.agentaura/sessions/<session_id>.json`
- 已在 branch `change/agentaura-design`；動工前 `git branch --show-current` 確認不在 `main`

---

## 檔案結構

| 檔案 | 責任 |
|---|---|
| `Package.swift` | SwiftPM 定義：4 個 target |
| `Sources/AuraCore/Activity.swift` | `Activity` 列舉 + `priority`（D1 優先序的唯一來源） |
| `Sources/AuraCore/EventMapping.swift` | hook event（+ `notification_type`）→ `EventEffect` |
| `Sources/AuraCore/HookPayload.swift` | 容錯解析 Claude Code 的 hook JSON |
| `Sources/AuraCore/SessionSnapshot.swift` | 我方狀態檔 schema（Codable） |
| `Sources/AuraCore/SessionState.swift` | reduce 後的記憶體模型 + `IconState` |
| `Sources/AuraCore/SessionReducer.swift` | `SessionSnapshot` → `SessionState`（main/sub 取 max） |
| `Sources/AuraCore/SessionRegistry.swift` | 現存 session + unacked 尾巴 + acknowledge |
| `Sources/AuraCore/AggregatePolicy.swift` | `[SessionState]` → `IconState` |
| `Sources/AuraCore/Liveness.swift` | pid + 啟動時戳驗證（防 pid 回收） |
| `Sources/AuraCore/EventSource.swift` | `EventSource` protocol（方案 3 的未來接點） |
| `Sources/AuraCore/MergeRules.swift` | 累積欄位合併（`aura-hook` 與測試共用） |
| `Sources/AuraHookFile/SnapshotIO.swift` | `flock` 讀寫 + 原子 rename + 檔名安全 |
| `Sources/AuraHookFile/HookFileSource.swift` | FSEvents 監看 + `bootstrap()` |
| `Sources/aura-hook/main.swift` | stdin → merge → write，任何錯誤 exit 0 |
| `plugin/.claude-plugin/plugin.json` | Claude Code plugin manifest |
| `plugin/hooks/hooks.json` | hook 註冊，全部 `async: true` |
| `Tests/AuraCoreTests/*` | 對抗式 double + composition-root smoke + 端到端 wired-gate |
| `Tests/AuraCoreTests/Fixtures/` | 由 `docs/evidence/hook-payloads/` 衍生的真實 payload |

---

### Task 01: 補錄未捕獲的 hook payload 與驗證 3 個機制

**無任何程式碼。** 產出是證據檔與 3 個機制的明確結論。spec §10 已有 33 個真實 payload，
但缺 5 類 event，且 3 個機制問題未驗證。若跳過此 task，後續 fixture 會建在猜測的 schema 上。

**Files:**
- Create: `docs/evidence/hook-payloads/round2/probe.sh`
- Create: `docs/evidence/hook-payloads/round2/log.ndjson`（探針產出）
- Create: `docs/evidence/hook-payloads/round2/mechanisms.md`（3 個機制的結論）
- Create: `docs/evidence/hook-payloads/round2/testplugin/`（驗證 plugin async 用的最小 plugin）
- Modify（暫時，必還原）: `~/.claude/settings.json`

**Interfaces:**
- Consumes: 無
- Produces: `round2/log.ndjson` 與 `mechanisms.md` —— Task 02 的 fixture 來源；
  `mechanisms.md` 的三個結論決定 Task 06（liveness）與 Task 12（plugin）能否照計畫實作

- [ ] **Step 1: 備份 settings.json 並記錄 checksum**

```bash
cd ~/.claude
TS=$(date +%Y%m%dT%H%M%S)
cp settings.json "settings.json.probe-backup-$TS"
shasum -a 256 settings.json | tee /tmp/aura-probe-baseline.sha
echo "$TS" > /tmp/aura-probe-ts
```

- [ ] **Step 2: 寫探針腳本**

同時記錄 payload、`getppid()` 與父行程名稱（機制 2）、以及 `CLAUDE_PLUGIN_ROOT`（機制 3）。

```bash
mkdir -p /Users/you/Code/Vibe/AgentAura/docs/evidence/hook-payloads/round2
cat > /Users/you/Code/Vibe/AgentAura/docs/evidence/hook-payloads/round2/probe.sh <<'EOF'
#!/usr/bin/env bash
# AgentAura T01 探針：記錄 hook payload + 父行程 + plugin root
LOG=/tmp/aura-probe/log.ndjson
mkdir -p "$(dirname "$LOG")"
PAYLOAD=$(cat)
PPID_NAME=$(ps -o comm= -p "$PPID" 2>/dev/null | tr -d ' ')
printf '{"_t":%s,"_ppid":%s,"_ppid_name":"%s","_plugin_root":"%s","_payload":%s}\n' \
  "$(date +%s.%N)" "$PPID" "${PPID_NAME:-unknown}" "${CLAUDE_PLUGIN_ROOT:-}" "${PAYLOAD:-null}" >> "$LOG"
exit 0
EOF
chmod +x /Users/you/Code/Vibe/AgentAura/docs/evidence/hook-payloads/round2/probe.sh
```

- [ ] **Step 3: 把探針裝到全部相關 event 上**

```bash
python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home()/".claude/settings.json"
d = json.loads(p.read_text())
assert "hooks" not in d or not d["hooks"], f"已有 hooks，先確認：{list(d.get('hooks',{}))}"
probe = "/Users/you/Code/Vibe/AgentAura/docs/evidence/hook-payloads/round2/probe.sh"
events = ["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure",
          "PostToolBatch","PermissionRequest","PermissionDenied","Notification",
          "SubagentStart","SubagentStop","Stop","StopFailure","PreCompact","PostCompact","SessionEnd"]
d["hooks"] = {e: [{"hooks":[{"type":"command","command":probe,"async":True}]}] for e in events}
p.write_text(json.dumps(d, ensure_ascii=False, indent=2, sort_keys=True)+"\n")
print("已裝探針到", len(events), "個 event")
PY
```

- [ ] **Step 4: 使用者在新 terminal 跑互動 session 觸發缺少的 event**

`PermissionRequest` 與 `Notification` **必須互動 session** 才會觸發（headless `-p` 不會出現權限提示）。
請使用者依序做這些動作，每項做完在 checklist 打勾：

| 目標 event | 動作 |
|---|---|
| `PermissionRequest` + `Notification(permission_prompt)` | 在 **default** 權限模式開 session，叫它跑一個未在 allowlist 的指令，**等提示出現再按 Allow** |
| `PermissionDenied` | 同上但按 Deny |
| `PostToolUseFailure` | 叫它跑 `ls /definitely-does-not-exist-xyz` |
| `PostToolBatch` | 叫它「同時 read 三個檔案」（並行 tool 批次） |
| `SubagentStart` / `SubagentStop` | 叫它派一個 Explore subagent |
| `Notification(idle_prompt)` | session 開著不動 ≥ 60 秒 |
| `Notification(agent_completed)` | 讓一個較長的任務跑完 |
| `StopFailure` | **best-effort** —— 需 API 錯誤，無法可靠觸發。若捕不到，在 `mechanisms.md` 標為未驗證，fixture 依文件合成並標註 |
| `PreCompact` / `PostCompact` | **best-effort** —— 需填滿 context |

- [ ] **Step 5: 驗證機制 1 —— plugin hooks 是否支援 `async: true`**

```bash
mkdir -p /Users/you/Code/Vibe/AgentAura/docs/evidence/hook-payloads/round2/testplugin/.claude-plugin \
         /Users/you/Code/Vibe/AgentAura/docs/evidence/hook-payloads/round2/testplugin/hooks
cd /Users/you/Code/Vibe/AgentAura/docs/evidence/hook-payloads/round2/testplugin
cat > .claude-plugin/plugin.json <<'EOF'
{ "name": "aura-probe", "version": "0.0.1", "description": "AgentAura T01 mechanism probe" }
EOF
cat > hooks/hooks.json <<'EOF'
{
  "PreToolUse": [
    { "hooks": [ { "type": "command",
                   "command": "${CLAUDE_PLUGIN_ROOT}/../probe.sh",
                   "async": true } ] }
  ]
}
EOF
```

然後 `claude plugin install ./testplugin`（或 `/plugin` 選單裝本地路徑），在新 session 跑一個 tool call，
檢查 `/tmp/aura-probe/log.ndjson` 是否出現 `_plugin_root` 非空的紀錄。

- [ ] **Step 6: 收斂三個機制的結論**

```bash
python3 - <<'PY'
import json, collections, pathlib
lines=[json.loads(l) for l in pathlib.Path("/tmp/aura-probe/log.ndjson").read_text().splitlines() if l.strip()]
print("=== 機制 2：getppid() 的父行程名稱分佈 ===")
for k,v in collections.Counter(l["_ppid_name"] for l in lines).most_common(): print(f"  {k:20} {v}")
print("\n=== 機制 3：CLAUDE_PLUGIN_ROOT 展開值 ===")
for k,v in collections.Counter(l["_plugin_root"] for l in lines).most_common(): print(f"  {k or '(空)':60} {v}")
print("\n=== 本輪捕獲的 event ===")
for k,v in collections.Counter(l["_payload"].get("hook_event_name") for l in lines).most_common(): print(f"  {k:22} {v}")
print("\n=== notification_type 實際值（關鍵！）===")
for k,v in collections.Counter(l["_payload"].get("notification_type") for l in lines
                               if l["_payload"].get("hook_event_name")=="Notification").most_common():
    print(f"  {k}  ×{v}")
PY
```

把結論寫進 `mechanisms.md`，每項必須是明確的「成立／不成立」加上實測依據：

1. **plugin hooks 支援 `async: true`** — 成立/不成立 + 依據
2. **`getppid()` 等於 claude 本體** — 若父行程名不是 `claude`（例如是 `sh`/`bash`），
   則 **Task 06 的 liveness 設計必須改為 session 心跳 TTL**，並在此註明
3. **`${CLAUDE_PLUGIN_ROOT}` 的展開值** — 記錄實際字串

- [ ] **Step 7: 還原 settings.json 並驗證 byte-identical**

```bash
cd ~/.claude
TS=$(cat /tmp/aura-probe-ts)
cp "settings.json.probe-backup-$TS" settings.json
shasum -a 256 -c /tmp/aura-probe-baseline.sha
python3 -c "import json,pathlib;d=json.loads((pathlib.Path.home()/'.claude/settings.json').read_text());assert 'hooks' not in d or not d['hooks'], d.get('hooks');print('hooks 已清除 ✓')"
claude plugin uninstall aura-probe 2>/dev/null || echo "（若用選單安裝，請用 /plugin 移除 aura-probe）"
```

Expected: `shasum -c` 輸出 `settings.json: OK`

- [ ] **Step 8: 把探針產出複製進 repo 並 commit**

```bash
cd /Users/you/Code/Vibe/AgentAura
cp /tmp/aura-probe/log.ndjson docs/evidence/hook-payloads/round2/log.ndjson
git add docs/evidence/hook-payloads/round2
git commit -m "docs(evidence): 補錄第二輪 hook payload 與 3 個機制驗證結論"
```

**驗收條件：** `mechanisms.md` 三項皆有明確結論；`Notification` 至少捕獲 1 筆真實 payload
（確認 `notification_type` 欄位名與實際值域）；`PermissionRequest`、`PostToolUseFailure`、
`SubagentStart`、`SubagentStop` 各至少 1 筆；`settings.json` 還原為 byte-identical。

---

### Task 02: SwiftPM 骨架 + fixture 載入器 + AppKit 隔離 gate

**Files:**
- Create: `Package.swift`
- Create: `Sources/AuraCore/AuraCore.swift`
- Create: `Tests/AuraCoreTests/FixtureLoader.swift`
- Create: `Tests/AuraCoreTests/IsolationTests.swift`
- Create: `Tests/AuraCoreTests/Fixtures/round1.ndjson`（由 `docs/evidence/` 複製）

**Interfaces:**
- Consumes: Task 01 的 `docs/evidence/hook-payloads/round2/log.ndjson`
- Produces: `Fixtures.rawEvents(named:)` → `[[String: Any]]`，供所有後續 task 載入真實 payload；
  `Fixtures.events(named:kind:)` → 依 `hook_event_name` 過濾

- [ ] **Step 1: 建立 Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentAura",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AuraCore"),
        .target(name: "AuraHookFile", dependencies: ["AuraCore"]),
        .executableTarget(name: "aura-hook", dependencies: ["AuraCore", "AuraHookFile"]),
        .testTarget(
            name: "AuraCoreTests",
            dependencies: ["AuraCore", "AuraHookFile"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: 為每個宣告的 target 建立佔位檔**

**SwiftPM 對「宣告了但沒有 sources 目錄」的 target 會直接報錯**，所以四個 target
都要有至少一個檔案。後續 task 會取代這些佔位內容。

```swift
// Sources/AuraCore/AuraCore.swift
/// AgentAura 核心邏輯。此 module 不得依賴 AppKit / SwiftUI —— 由 IsolationTests 強制。
///
/// 註：此註解刻意避開「import + 框架名」的字面組合 —— IsolationTests 用原始碼
/// 字串比對，寫成那樣會讓這個檔案誤觸自己的 gate。
public enum AuraCore {
    public static let schemaVersion = 1
}
```

```swift
// Sources/AuraHookFile/AuraHookFile.swift
/// 狀態檔的讀寫與 FSEvents 監看。Task 10 與 Task 12 填入實際內容。
public enum AuraHookFile {}
```

```swift
// Sources/aura-hook/main.swift
// 佔位：Task 11 填入實際內容。
// 現在就必須存在，否則 Package.swift 宣告的 executableTarget 會讓 build 失敗。
```

驗證四個 target 都能編譯：

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete`（不得出現 "Source files for target ... should be located under"）

- [ ] **Step 3: 把真實 payload 複製成 fixture**

```bash
mkdir -p Tests/AuraCoreTests/Fixtures
cp docs/evidence/hook-payloads/log.ndjson            Tests/AuraCoreTests/Fixtures/round1.ndjson
cp docs/evidence/hook-payloads/log-mysession.ndjson  Tests/AuraCoreTests/Fixtures/round1b.ndjson
cp docs/evidence/hook-payloads/round2/log.ndjson     Tests/AuraCoreTests/Fixtures/round2.ndjson
```

- [ ] **Step 4: 寫 fixture 載入器**

`_payload` 是探針包了一層的實際 hook JSON；載入器負責剝開。

```swift
// Tests/AuraCoreTests/FixtureLoader.swift
import Foundation

enum Fixtures {
    /// 讀取探針 ndjson，回傳剝開 `_payload` 後的原始 hook JSON 字典陣列。
    static func rawEvents(named name: String) throws -> [[String: Any]] {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "ndjson"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").compactMap { line -> [String: Any]? in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return obj["_payload"] as? [String: Any] ?? obj
        }
    }

    /// 只回傳指定 hook_event_name 的事件。
    static func events(named name: String, kind: String) throws -> [[String: Any]] {
        try rawEvents(named: name).filter { $0["hook_event_name"] as? String == kind }
    }

    /// 把字典重新序列化成 hook 會從 stdin 送進來的 JSON bytes。
    static func jsonData(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }
}
```

> 註：`#require` 來自 swift-testing。若在非測試情境需要，改用 `guard let ... else { throw }`。

- [ ] **Step 5: 寫 AppKit 隔離 gate 測試**

Global Constraint「`AuraCore` 不得 import AppKit」必須由測試強制，不靠自律。
用原始碼掃描實作 —— 這是唯一能在編譯期外抓到的方式。

```swift
// Tests/AuraCoreTests/IsolationTests.swift
import Testing
import Foundation

@Suite("AuraCore 隔離約束")
struct IsolationTests {

    /// 從測試檔位置往上找 repo 根目錄。
    static func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        fatalError("找不到 Package.swift")
    }

    static func swiftFiles(under relative: String) -> [URL] {
        let root = repoRoot().appendingPathComponent(relative)
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// 禁止 `AuraCore` 依賴 AppKit / SwiftUI / Cocoa。
    ///
    /// 必須涵蓋 Swift 完整的 import 語法，而不只是 `import AppKit` 這一種形狀：
    /// `import` **之前**可以有任意數量的 attribute（`@testable`、`@preconcurrency`、
    /// `@_exported`、`@_spi(...)` …）與 access-level modifier（Swift 6 的
    /// `internal import` / `public import` / `package import` …）；**之後**可以有一個
    /// 宣告關鍵字（scoped import，如 `import class AppKit.NSWindow`）。
    /// 錨定在行首，所以散文註解與字串字面值不會誤觸。
    static let bannedImportPattern: String = {
        let modifiers = #"(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)\n]*\))?|public|package|internal|fileprivate|private)[ \t]+)*"#
        let kind = #"(?:(?:class|struct|enum|protocol|typealias|func|var|let|actor|inout)[ \t]+)?"#
        return #"(?m)^[ \t]*"# + modifiers + #"import[ \t]+"# + kind + #"(?:AppKit|SwiftUI|Cocoa)\b"#
    }()

    @Test("AuraCore 不得依賴 AppKit / SwiftUI / Cocoa（含 scoped import）")
    func coreHasNoUIImports() throws {
        for file in Self.swiftFiles(under: "Sources/AuraCore") {
            let src = try String(contentsOf: file, encoding: .utf8)
            let hit = src.range(of: Self.bannedImportPattern, options: .regularExpression)
            #expect(hit == nil,
                    "\(file.lastPathComponent) 出現禁止的 import：\(hit.map { String(src[$0]) } ?? "")")
        }
    }

    @Test("regex gate 涵蓋 Swift 完整的 import 語法")
    func importPatternCoverage() {
        let shouldMatch = [
            "import AppKit",
            "  import AppKit",
            "\timport SwiftUI",
            "import Cocoa",
            "@testable import AppKit",
            "import class AppKit.NSWindow",            // scoped
            "import struct SwiftUI.Color",
            "import AppKit.NSWindow",                  // submodule，無宣告關鍵字
            "@preconcurrency import AppKit",           // Swift 6 常見
            "@_exported import AppKit",
            "@_implementationOnly import AppKit",
            "@_spi(Private) import AppKit",
            "internal import AppKit",                  // Swift 6 access-level import
            "public import AppKit",
            "package import AppKit",
            "fileprivate import SwiftUI",
            "private import Cocoa",
            "@preconcurrency internal import AppKit",  // 兩者疊加
            "internal import struct AppKit.NSView",    // modifier + scoped
        ]
        let shouldNotMatch = [
            "/// 此 module 不得依賴 AppKit",
            "// 不要 import AppKit 進來",
            "/// internal import AppKit 是禁止的",
            "    // import AppKit",
            "import Foundation",
            "internal import Foundation",
            "let s = \"import AppKit\"",
            "importAppKit",
            "public func importAppKitThing() {}",
            "#if canImport(AppKit)",
        ]
        for line in shouldMatch {
            #expect(line.range(of: Self.bannedImportPattern, options: .regularExpression) != nil,
                    "應攔下：\(line)")
        }
        for line in shouldNotMatch {
            #expect(line.range(of: Self.bannedImportPattern, options: .regularExpression) == nil,
                    "不該攔：\(line)")
        }
    }

    /// 正確算行數。
    ///
    /// `split(separator: "\n", omittingEmptySubsequences: false).count` 對結尾有換行的
    /// 檔案會多算 1（`"a\nb\n"` → 3），使「≤200」實際擋在 199 —— 恰好 200 行的合法檔案
    /// 會被誤判成 201 行。改成數換行字元。
    static func lineCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let newlines = text.reduce(into: 0) { acc, ch in if ch == "\n" { acc += 1 } }
        return text.hasSuffix("\n") ? newlines : newlines + 1
    }

    @Test("lineCount 對結尾有／無換行都正確")
    func lineCountIsExact() {
        #expect(Self.lineCount(of: "") == 0)
        #expect(Self.lineCount(of: "a") == 1)
        #expect(Self.lineCount(of: "a\n") == 1)
        #expect(Self.lineCount(of: "a\nb") == 2)
        #expect(Self.lineCount(of: "a\nb\n") == 2, "結尾換行不得多算一行")
        #expect(Self.lineCount(of: String(repeating: "x\n", count: 200)) == 200)
    }

    @Test("每個原始檔不得超過 200 行")
    func fileLengthLimit() throws {
        for dir in ["Sources/AuraCore", "Sources/AuraHookFile", "Sources/aura-hook"] {
            for file in Self.swiftFiles(under: dir) {
                let lines = Self.lineCount(of: try String(contentsOf: file, encoding: .utf8))
                #expect(lines <= 200, "\(file.lastPathComponent) 有 \(lines) 行，超過 200 行上限")
            }
        }
    }
}
```

- [ ] **Step 6: 寫 fixture 完整性測試（確認真實資料真的載進來了）**

```swift
// 附加到 Tests/AuraCoreTests/IsolationTests.swift
@Suite("Fixture 完整性")
struct FixtureIntegrityTests {

    @Test("round1 含 15 個 PreToolUse 與 14 個 PostToolUse")
    func round1Counts() throws {
        let all = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        let counts = Dictionary(grouping: all) { $0["hook_event_name"] as? String ?? "?" }
            .mapValues(\.count)
        #expect(counts["PreToolUse"] == 15)
        #expect(counts["PostToolUse"] == 14)
        #expect(counts["SessionStart"] == 1)
        #expect(counts["Stop"] == 1)
        #expect(counts["SessionEnd"] == 1)
    }

    @Test("round1 的 effort 是物件形狀，不是字串")
    func effortIsObject() throws {
        let pre = try Fixtures.events(named: "round1", kind: "PreToolUse")
        let effort = try #require(pre.first?["effort"])
        #expect(effort is [String: Any], "實測 effort 是 {\"level\":…} 物件（spec §2.1.1）")
    }

    @Test("round1 沒有任何 event 帶 model，round2 的 SessionStart 有")
    func modelFieldOnlyOnSessionStart() throws {
        let r1 = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        #expect(r1.allSatisfy { $0["model"] == nil }, "第一輪：無 model")

        let starts = try Fixtures.events(named: "round2", kind: "SessionStart")
        #expect(!starts.isEmpty)
        #expect(starts.allSatisfy { $0["model"] is String },
                "第二輪實測：SessionStart 帶 model（spec §2.1.1，第二輪為準）")
        // 其他 event 仍然不帶 —— 故 model 必須由 MergeRules 帶過來
        let others = try Fixtures.rawEvents(named: "round2")
            .filter { $0["hook_event_name"] as? String != "SessionStart" }
        #expect(others.allSatisfy { $0["model"] == nil })
    }

    @Test("round2 有捕獲 Notification，notification_type 與 message 皆經量測確認")
    func round2HasNotification() throws {
        let notifs = try Fixtures.events(named: "round2", kind: "Notification")
        #expect(!notifs.isEmpty, "Task 01 必須捕獲至少 1 筆 Notification")
        #expect(notifs.allSatisfy { $0["notification_type"] is String },
                "欄位名必須經實測確認，不能只靠文件")
        #expect(notifs.allSatisfy { $0["message"] is String },
                "實測發現的額外欄位（spec §2.1.2）")
    }

    @Test("round2 的 SubagentStop 有 agent_type 為空字串的內部 subagent")
    func round2HasInternalSubagent() throws {
        let stops = try Fixtures.events(named: "round2", kind: "SubagentStop")
        #expect(!stops.isEmpty)
        #expect(stops.contains { ($0["agent_type"] as? String) == "" },
                "內部 subagent 的 agent_type 是空字串而非 null —— §2.5.1 critical bug 的來源")
        #expect(stops.allSatisfy { ($0["agent_id"] as? String)?.isEmpty == false })
    }

    @Test("round2 裡 SubagentStop 出現在主 agent Stop 之後（§2.5.1 的時序證據）")
    func round2SubagentStopAfterStop() throws {
        // 探針的外層有 _t 時戳，rawEvents 已剝掉；這裡直接讀原始行。
        let url = try #require(Bundle.module.url(forResource: "Fixtures/round2", withExtension: "ndjson"))
        struct Row { let t: Double; let sid: String; let event: String; let isSub: Bool }
        let rows: [Row] = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").compactMap { line in
                guard let d = line.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let t = o["_t"] as? Double,
                      let p = o["_payload"] as? [String: Any],
                      let sid = p["session_id"] as? String,
                      let ev = p["hook_event_name"] as? String else { return nil }
                return Row(t: t, sid: sid, event: ev,
                           isSub: (p["agent_id"] as? String)?.isEmpty == false)
            }
        var found = false
        for sid in Set(rows.map(\.sid)) {
            let mine = rows.filter { $0.sid == sid }
            guard let stop = mine.first(where: { $0.event == "Stop" && !$0.isSub })?.t,
                  let subStop = mine.first(where: { $0.event == "SubagentStop" })?.t
            else { continue }
            if subStop > stop { found = true }
        }
        #expect(found, "至少一個 session 的 SubagentStop 晚於 Stop —— 這是 §2.5.1 的實測依據")
    }
}
```

- [ ] **Step 7: 執行測試**

Run: `swift test 2>&1 | tail -30`
Expected: `IsolationTests` 全 PASS；`FixtureIntegrityTests` 的 round1 測試 PASS，
round2 測試依 Task 01 實際捕獲結果 PASS（若 Task 01 未捕到 `Notification`，此測試 FAIL 即為正確的紅燈，
必須回到 Task 01 補錄，不得放寬斷言）

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/AuraCore Tests/AuraCoreTests
git commit -m "test: SwiftPM 骨架 + fixture 載入器 + AppKit 隔離與行數 gate"
```

---

### Task 03: Activity 與 event → activity 對照

D1 優先序的**唯一來源**。`Activity.priority` 是後續 mutation 驗證的靶。

**Files:**
- Create: `Sources/AuraCore/Activity.swift`
- Create: `Sources/AuraCore/EventMapping.swift`
- Test: `Tests/AuraCoreTests/ActivityTests.swift`
- Test: `Tests/AuraCoreTests/EventMappingTests.swift`

**Interfaces:**
- Consumes: `Fixtures`（Task 02）
- Produces:
  - `public enum Activity: String, Codable, Sendable, CaseIterable, Comparable { case idle, done, working, waiting, error }`，`var priority: Int`
  - `public enum EventEffect: Equatable, Sendable { case setActivity(Activity), noChange, sessionEnded }`
  - `public enum EventMapping { public static func effect(forEvent: String, notificationType: String?) -> EventEffect }`

- [ ] **Step 1: 寫失敗測試 —— 優先序與比較**

```swift
// Tests/AuraCoreTests/ActivityTests.swift
import Testing
@testable import AuraCore

@Suite("Activity 優先序（D1）")
struct ActivityTests {

    @Test("優先序為 error > waiting > working > done > idle")
    func priorityOrder() {
        #expect(Activity.error > Activity.waiting)
        #expect(Activity.waiting > Activity.working)
        #expect(Activity.working > Activity.done)
        #expect(Activity.done > Activity.idle)
    }

    @Test("max 保住 waiting 不被 working 蓋掉（§2.5 的基石）")
    func maxPreservesWaiting() {
        #expect(max(Activity.waiting, Activity.working) == .waiting)
        #expect(max(Activity.working, Activity.waiting) == .waiting)
        #expect(max(Activity.error, Activity.waiting) == .error)
    }

    @Test("rawValue 是可讀字串，供狀態檔 JSON 使用")
    func rawValuesAreStrings() {
        #expect(Activity.waiting.rawValue == "waiting")
        #expect(Activity(rawValue: "error") == .error)
        #expect(Activity(rawValue: "bogus") == nil)
    }

    @Test("priority 值兩兩不同且涵蓋全部 case")
    func prioritiesAreDistinct() {
        let ps = Activity.allCases.map(\.priority)
        #expect(Set(ps).count == Activity.allCases.count)
        #expect(ps.sorted() == [0, 1, 2, 3, 4])
    }

    @Test("isQuiescent 僅 waiting / done / error 為真")
    func quiescence() {
        #expect(Activity.waiting.isQuiescent)
        #expect(Activity.done.isQuiescent)
        #expect(Activity.error.isQuiescent)
        #expect(!Activity.working.isQuiescent)
        #expect(!Activity.idle.isQuiescent)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter ActivityTests 2>&1 | tail -10`
Expected: FAIL — `cannot find 'Activity' in scope`

- [ ] **Step 3: 實作 Activity**

```swift
// Sources/AuraCore/Activity.swift

/// Session 的活動狀態。
///
/// `priority` 是 D1 聚合優先序的**唯一來源**：`error > waiting > working > done > idle`。
/// 改動此處會同時改變 icon 聚合結果與面板排序 —— 兩者都有對應的 mutation 驗證。
public enum Activity: String, Codable, Sendable, CaseIterable {
    case idle
    case done
    case working
    case waiting
    case error

    /// 數字越大越優先。
    public var priority: Int {
        switch self {
        case .idle:    0
        case .done:    1
        case .working: 2
        case .waiting: 3
        case .error:   4
        }
    }

    /// 靜止態：使用者行動前不會再有新事件覆寫。
    ///
    /// `MergeRules` 用它決定是否忽略 subagent 事件 —— 主 agent 靜止時，
    /// 殘留的 subagent 活動（含 Claude Code 的內部 subagent）不得改變 activity（§2.5.1）。
    public var isQuiescent: Bool {
        self == .waiting || self == .done || self == .error
    }
}

extension Activity: Comparable {
    public static func < (lhs: Activity, rhs: Activity) -> Bool {
        lhs.priority < rhs.priority
    }
}
```

- [ ] **Step 4: 執行確認通過**

Run: `swift test --filter ActivityTests 2>&1 | tail -10`
Expected: PASS（4 個測試）

- [ ] **Step 5: 寫失敗測試 —— event 對照（含真實 fixture 回歸）**

```swift
// Tests/AuraCoreTests/EventMappingTests.swift
import Testing
@testable import AuraCore

@Suite("event → activity 對照（§2.2）")
struct EventMappingTests {

    func effect(_ e: String, _ t: String? = nil) -> EventEffect {
        EventMapping.effect(forEvent: e, notificationType: t)
    }

    @Test("工作中的事件全部映射到 working")
    func workingEvents() {
        for e in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolBatch",
                  "SubagentStart", "SubagentStop", "PreCompact", "PostCompact",
                  "PermissionDenied", "ElicitationResult"] {
            #expect(effect(e) == .setActivity(.working), "\(e) 應為 working")
        }
    }

    @Test("PostToolUseFailure 是 working 而非 error（前一版的 bug）")
    func toolFailureIsNotError() {
        #expect(effect("PostToolUseFailure") == .setActivity(.working),
                "tool 中途失敗是 agent 工作的正常組成；紅色只保留給 StopFailure")
    }

    @Test("等待與終止事件")
    func waitingAndTerminal() {
        #expect(effect("SessionStart")      == .setActivity(.idle))
        #expect(effect("PermissionRequest") == .setActivity(.waiting))
        #expect(effect("Elicitation")       == .setActivity(.waiting))
        #expect(effect("Stop")              == .setActivity(.done))
        #expect(effect("StopFailure")       == .setActivity(.error))
        #expect(effect("SessionEnd")        == .sessionEnded)
    }

    @Test("未知 event 不改變 activity（上游新增 event 不得爆掉）")
    func unknownEventIsNoChange() {
        #expect(effect("SomeFutureEventFromClaudeCode2027") == .noChange)
        #expect(effect("") == .noChange)
    }

    // ---- Notification 的 12 種型別（§2.2.1）----

    @Test("需要使用者的 notification 型別 → waiting", arguments: [
        "permission_prompt", "idle_prompt", "agent_needs_input",
        "elicitation_dialog", "elicitation_url_dialog",
    ])
    func notificationNeedsUser(_ type: String) {
        #expect(effect("Notification", type) == .setActivity(.waiting))
    }

    @Test("agent_completed 是 done 而不是 waiting")
    func agentCompletedIsDone() {
        #expect(effect("Notification", "agent_completed") == .setActivity(.done),
                "背景 agent 跑完應顯示 done，不該讓 icon 亮成「需要你」")
    }

    @Test("雜訊型別不改變 activity（不得無故亮橘燈）", arguments: [
        "auth_success", "elicitation_complete", "elicitation_response",
        "quota_auto_resume_fired", "quota_auto_resume_stale", "quota_auto_resume_disabled",
    ])
    func notificationNoise(_ type: String) {
        #expect(effect("Notification", type) == .noChange)
    }

    @Test("未知或缺失的 notification_type 不改變 activity")
    func notificationUnknown() {
        #expect(effect("Notification", "brand_new_type_2027") == .noChange)
        #expect(effect("Notification", nil) == .noChange)
        #expect(effect("Notification", "") == .noChange)
    }

    // ---- handledEvents 與 switch 必須一致（防兩者 drift）----

    @Test("handledEvents 裡除了刻意不改 activity 的，其餘都必須有映射")
    func handledEventsAllMapped() {
        for e in EventMapping.handledEvents
            where !EventMapping.registeredButNoActivityChange.contains(e) {
            let r = EventMapping.effect(forEvent: e,
                                        notificationType: e == "Notification" ? "idle_prompt" : nil)
            #expect(r != .noChange, "\(e) 在 handledEvents 裡卻落到 default")
        }
    }

    @Test("registeredButNoActivityChange 必須是 handledEvents 的子集")
    func noChangeSetIsSubset() {
        #expect(EventMapping.registeredButNoActivityChange
                    .isSubset(of: EventMapping.handledEvents))
    }

    @Test("PostModelSwitch 不改 activity 但仍在 handledEvents 裡（因為帶 to_model）")
    func postModelSwitchIsRegisteredButInert() {
        #expect(EventMapping.handledEvents.contains("PostModelSwitch"))
        #expect(EventMapping.effect(forEvent: "PostModelSwitch") == .noChange)
    }

    // ---- 真實 fixture 回歸：每一筆實測 event 都必須被明確處理 ----

    @Test("round1 的每個真實 event 都不落到 noChange")
    func realEventsAreAllMapped() throws {
        let all = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        for ev in all {
            let name = try #require(ev["hook_event_name"] as? String)
            let e = EventMapping.effect(forEvent: name,
                                       notificationType: ev["notification_type"] as? String)
            #expect(e != .noChange, "實測捕獲的 \(name) 竟然沒有對照規則")
        }
    }
}
```

- [ ] **Step 6: 執行確認失敗**

Run: `swift test --filter EventMappingTests 2>&1 | tail -10`
Expected: FAIL — `cannot find 'EventMapping' in scope`

- [ ] **Step 7: 實作 EventMapping**

```swift
// Sources/AuraCore/EventMapping.swift

/// 一個 hook event 對 session 狀態的效果。
public enum EventEffect: Equatable, Sendable {
    /// 設定 activity。
    case setActivity(Activity)
    /// 不改變 activity（未知 event、雜訊 notification）—— 只更新時戳。
    case noChange
    /// session 已終止。
    case sessionEnded
}

public enum EventMapping {

    /// 本模組明確處理的 event —— **`plugin/hooks/hooks.json` 必須註冊且僅註冊這些**。
    ///
    /// 跨層一致性 gate（Task 13）從這個集合推導，不用手維護第二份清單。
    /// 手維護的清單會 drift：本專案已實際發生過 —— `Elicitation`（映射到 `waiting`，
    /// 代表「MCP server 在等你輸入」）有映射卻沒註冊，那個狀態永遠收不到，
    /// 而單元測試照樣全綠。
    public static let handledEvents: Set<String> = [
        "SessionStart", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure", "PostToolBatch",
        "SubagentStart", "SubagentStop",
        "PreCompact", "PostCompact",
        "PermissionRequest", "PermissionDenied",
        "Elicitation", "ElicitationResult",
        "Notification",
        "Stop", "StopFailure", "SessionEnd",
        "PostModelSwitch",
    ]

    /// `handledEvents` 中刻意不改變 activity 的 event。
    ///
    /// 它們仍必須註冊，因為帶了別的必要資訊：`PostModelSwitch` 帶 `to_model`
    /// （使用者中途 `/model` 換模型後，面板不得顯示舊模型）。
    public static let registeredButNoActivityChange: Set<String> = [
        "PostModelSwitch",
    ]

    /// hook event（必要時加上 `notification_type`）→ 效果。
    ///
    /// 設計不變量：`waiting` / `done` / `error` 皆為**靜止態** —— 在使用者行動前
    /// 不會有新事件覆寫它們。這是「單檔覆寫、最後寫的贏」不會弄丟資訊的前提。
    public static func effect(forEvent event: String,
                              notificationType: String? = nil) -> EventEffect {
        switch event {
        case "SessionStart":
            return .setActivity(.idle)

        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
             "PostToolBatch", "SubagentStart", "SubagentStop",
             "PreCompact", "PostCompact", "PermissionDenied", "ElicitationResult":
            // PostToolUseFailure 刻意映射到 working：tool 中途失敗是 agent 工作的
            // 正常組成（grep 沒命中、測試紅燈），不該把燈變紅。
            return .setActivity(.working)

        case "PermissionRequest", "Elicitation":
            return .setActivity(.waiting)

        case "Stop":
            return .setActivity(.done)

        case "StopFailure":
            return .setActivity(.error)

        case "SessionEnd":
            return .sessionEnded

        case "Notification":
            return notificationEffect(notificationType)

        default:
            // 上游新增 event 時必須靜默忽略，不得改變 activity 也不得爆掉。
            return .noChange
        }
    }

    /// `Notification` 中代表「需要使用者」的型別 —— **`hooks.json` 的 matcher
    /// 必須等於這個集合**（加上 `agent_completed`，它是 `done` 不是 waiting）。
    ///
    /// 與 `handledEvents` 同理：跨層 gate 從生產碼推導，不留第二份手寫清單。
    public static let notificationTypesNeedingUser: Set<String> = [
        "permission_prompt", "idle_prompt", "agent_needs_input",
        "elicitation_dialog", "elicitation_url_dialog",
    ]

    /// `Notification` 中代表「有結果可看」的型別。
    public static let notificationTypesMeaningDone: Set<String> = [
        "agent_completed",
    ]

    /// `hooks.json` 的 `Notification` matcher 應涵蓋的全部型別。
    public static var notificationMatcherTypes: Set<String> {
        notificationTypesNeedingUser.union(notificationTypesMeaningDone)
    }

    /// `Notification` 的型別分流（§2.2.1）。
    ///
    /// 未知型別一律 `.noChange`。理由：未知空間裡佔多數的是雜訊（auth、quota），
    /// 誤報會讓 icon 無故亮橘；而「有人在等你」已由獨立的 `PermissionRequest`
    /// event 直接覆蓋，不需要靠 `Notification` 兜底。
    static func notificationEffect(_ type: String?) -> EventEffect {
        guard let type else { return .noChange }
        if notificationTypesNeedingUser.contains(type) { return .setActivity(.waiting) }
        if notificationTypesMeaningDone.contains(type) { return .setActivity(.done) }
        return .noChange
    }
}
```

- [ ] **Step 8: 執行全部測試**

Run: `swift test 2>&1 | tail -15`
Expected: 全 PASS

- [ ] **Step 9: Mutation 驗證（關鍵 gate 必做）**

三個驗證都用同一個節奏：**改一處 → 看到指定測試 RED → `git checkout` 還原 → 再跑確認全綠**。
「相信它會紅」不算通過，必須實際看到 FAIL 輸出。

```bash
# 驗證 1：撤掉 D1 優先序
sed -i '' 's/case .waiting: 3/case .waiting: 1/' Sources/AuraCore/Activity.swift
swift test --filter ActivityTests 2>&1 | tail -6
#   Expected: priorityOrder 與 maxPreservesWaiting FAIL
git checkout Sources/AuraCore/Activity.swift

# 驗證 2：PostToolUseFailure 改回 error
sed -i '' 's/case "PostToolUseFailure",$//; s/case "StopFailure":/case "StopFailure", "PostToolUseFailure":/' \
    Sources/AuraCore/EventMapping.swift
swift test --filter EventMappingTests 2>&1 | tail -6
#   Expected: toolFailureIsNotError FAIL
git checkout Sources/AuraCore/EventMapping.swift

# 驗證 3：Notification 未知型別改回 waiting
sed -i '' 's|^        default:$|        default: return .setActivity(.waiting)\n        case "__never":|' \
    Sources/AuraCore/EventMapping.swift
swift test --filter EventMappingTests 2>&1 | tail -6
#   Expected: notificationNoise 與 notificationUnknown FAIL
git checkout Sources/AuraCore/EventMapping.swift

swift test 2>&1 | tail -5   # 還原後必須全綠
```

> 驗證 2 的 `sed` 若因換行位置對不上而無效（先用 `git diff` 確認真的改到了），
> 改成手動編輯：把 `"PostToolUseFailure"` 從 working 那組移進 `case "StopFailure":`。
> **關鍵是要看到 RED，不是要 sed 漂亮。**

- [ ] **Step 10: Commit**

```bash
git add Sources/AuraCore/Activity.swift Sources/AuraCore/EventMapping.swift \
        Tests/AuraCoreTests/ActivityTests.swift Tests/AuraCoreTests/EventMappingTests.swift
git commit -m "feat(core): Activity 優先序與 event→activity 對照，含 Notification 12 型別分流"
```

---

### Task 04: HookPayload 容錯解析

解析 Claude Code 送進 stdin 的 hook JSON。**刻意不用 `Codable`** —— 改用字典讀取，
因為上游 schema 會變（實測已發現文件與現實有 4 處落差），字典讀取對未知/缺失/改型欄位天生容忍。

**Files:**
- Create: `Sources/AuraCore/HookPayload.swift`
- Test: `Tests/AuraCoreTests/HookPayloadTests.swift`

**Interfaces:**
- Consumes: `Activity`、`EventMapping`（Task 03）、`Fixtures`（Task 02）
- Produces:
  ```swift
  public struct HookPayload: Sendable, Equatable {
      public let hookEventName: String
      public let sessionID: String
      public let cwd: String?
      public let permissionMode: String?
      public let effortLevel: String?
      public let source: String?
      public let reason: String?
      public let toolName: String?
      public let toolDescription: String?   // tool_input.description，面板顯示「在等你批准什麼」
      public let toolDurationMs: Int?
      public let model: String?
      public let notificationType: String?
      public let notificationMessage: String?
      public let model: String?
      public let lastMessage: String?
      public let agentID: String?
      public let agentType: String?    // 空字串正規化為 nil
      public var isSubagent: Bool { agentID != nil }
      public var effect: EventEffect { ... }
      public init?(json: [String: Any])
      public init?(data: Data)
  }
  ```

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/AuraCoreTests/HookPayloadTests.swift
import Testing
import Foundation
@testable import AuraCore

@Suite("HookPayload 容錯解析（§2.1.1）")
struct HookPayloadTests {

    // ---- 真實 payload ----

    @Test("解析全部 33 個真實 payload 都不回 nil")
    func parsesAllRealPayloads() throws {
        let all = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        #expect(all.count == 33)
        for json in all {
            #expect(HookPayload(json: json) != nil,
                    "真實 payload 解析失敗：\(json["hook_event_name"] ?? "?")")
        }
    }

    @Test("effort 物件形狀 {\"level\":\"xhigh\"} 攤平成字串")
    func effortObjectFlattened() throws {
        let pre = try #require(try Fixtures.events(named: "round1", kind: "PreToolUse").first)
        let p = try #require(HookPayload(json: pre))
        #expect(p.effortLevel == "xhigh")
    }

    @Test("effort 也接受字串形狀（防上游改格式）")
    func effortStringAccepted() throws {
        let p = try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1", "effort": "high",
        ]))
        #expect(p.effortLevel == "high")
    }

    @Test("effort 是意外型別時回 nil，不得 crash")
    func effortWeirdType() throws {
        for weird: Any in [42, [1, 2, 3], ["nope": "x"], NSNull()] {
            let p = try #require(HookPayload(json: [
                "hook_event_name": "PreToolUse", "session_id": "s1", "effort": weird,
            ]))
            #expect(p.effortLevel == nil)
        }
    }

    @Test("SessionEnd 的結束原因讀 reason，也向後容忍 end_reason")
    func reasonFieldTolerance() throws {
        let a = try #require(HookPayload(json: [
            "hook_event_name": "SessionEnd", "session_id": "s1", "reason": "clear",
        ]))
        #expect(a.reason == "clear")

        let b = try #require(HookPayload(json: [
            "hook_event_name": "SessionEnd", "session_id": "s1", "end_reason": "exit",
        ]))
        #expect(b.reason == "exit", "文件寫 end_reason、實測是 reason —— 兩者都要能讀")
    }

    // ---- 主 agent vs subagent（§2.5 的判別依據）----

    @Test("agent_id 為 null 是主 agent，非 null 是 subagent")
    func subagentDetection() throws {
        let all = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        let payloads = all.compactMap { HookPayload(json: $0) }
        let subs = payloads.filter(\.isSubagent)
        let mains = payloads.filter { !$0.isSubagent }
        #expect(subs.count == 18, "實測 18 個 subagent 事件")
        #expect(mains.count == 15, "實測 15 個主 agent 事件")
        #expect(subs.allSatisfy { $0.agentType == "implementer" })
    }

    @Test("subagent 與主 agent 共用同一個 session_id（覆蓋 bug 的根源）")
    func subagentSharesSessionID() throws {
        let all = try Fixtures.rawEvents(named: "round1b")
        let payloads = all.compactMap { HookPayload(json: $0) }
        let ids = Set(payloads.map(\.sessionID))
        #expect(ids.count == 1, "同一 session 內主/subagent 共用 session_id")
        #expect(payloads.contains(where: \.isSubagent))
        #expect(payloads.contains { !$0.isSubagent })
    }

    // ---- 對抗式：畸形輸入 ----

    @Test("缺少 hook_event_name 或 session_id 時回 nil")
    func missingRequiredFields() {
        #expect(HookPayload(json: ["session_id": "s1"]) == nil)
        #expect(HookPayload(json: ["hook_event_name": "Stop"]) == nil)
        #expect(HookPayload(json: [:]) == nil)
    }

    @Test("session_id 型別錯誤時回 nil")
    func sessionIDWrongType() {
        #expect(HookPayload(json: ["hook_event_name": "Stop", "session_id": 12345]) == nil)
        #expect(HookPayload(json: ["hook_event_name": "Stop", "session_id": NSNull()]) == nil)
    }

    @Test("多出未知欄位不影響解析")
    func unknownFieldsIgnored() throws {
        let p = try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1",
            "brand_new_field_2027": ["nested": [1, 2, 3]],
            "another": true,
        ]))
        #expect(p.sessionID == "s1")
    }

    @Test("截斷的 JSON bytes 回 nil，不得 crash")
    func truncatedJSON() throws {
        let full = try Fixtures.jsonData(try #require(try Fixtures.rawEvents(named: "round1").first))
        for cut in [0, 1, full.count / 3, full.count / 2, full.count - 1] {
            #expect(HookPayload(data: full.prefix(cut)) == nil)
        }
    }

    @Test("非 JSON 或非物件的 bytes 回 nil")
    func nonObjectJSON() {
        for s in ["", "   ", "null", "[]", "[1,2,3]", "\"hello\"", "42", "{", "}{", "not json at all"] {
            #expect(HookPayload(data: Data(s.utf8)) == nil, "輸入 \(s.debugDescription) 應回 nil")
        }
    }

    @Test("unicode / emoji / 超長 cwd 都能解析")
    func exoticStrings() throws {
        let long = String(repeating: "深/", count: 600)
        let p = try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1",
            "cwd": "/Users/you/專案 🚀/\(long)", "tool_name": "Bash",
        ]))
        #expect(p.cwd?.contains("🚀") == true)
        #expect((p.cwd?.count ?? 0) > 1000)
    }

    @Test("agent_type 空字串正規化為 nil（內部 subagent，§2.5.1）")
    func emptyAgentTypeNormalized() throws {
        let p = try #require(HookPayload(json: [
            "hook_event_name": "SubagentStop", "session_id": "s1",
            "agent_id": "a8c360a1fe475f199", "agent_type": "",
        ]))
        #expect(p.isSubagent, "agent_id 有值 → 仍是 subagent 事件")
        #expect(p.agentType == nil, "空字串不得成為 subagents 的鍵")
    }

    @Test("round2 的真實內部 subagent payload 解析後 agentType 為 nil")
    func realInternalSubagentParsed() throws {
        let stops = try Fixtures.events(named: "round2", kind: "SubagentStop")
        let internals = stops.compactMap { HookPayload(json: $0) }
            .filter { $0.agentType == nil && $0.isSubagent }
        #expect(!internals.isEmpty, "實測確實有 agent_type 為空字串的 subagent")
    }

    @Test("PostModelSwitch 的 to_model 被當成 model 讀出來")
    func modelFromPostModelSwitch() throws {
        let p = try #require(HookPayload(json: [
            "hook_event_name": "PostModelSwitch", "session_id": "s1",
            "from_model": "claude-sonnet-5", "to_model": "claude-opus-5",
        ]))
        #expect(p.model == "claude-opus-5", "使用者中途 /model 換模型，面板不得顯示舊模型")
        #expect(p.effect == .noChange, "換模型不改變 activity")
    }

    @Test("SessionStart 的 model 被讀出來，其他 event 沒有")
    func modelFromSessionStart() throws {
        let starts = try Fixtures.events(named: "round2", kind: "SessionStart")
        let p = try #require(HookPayload(json: try #require(starts.first)))
        #expect(p.model?.hasPrefix("claude") == true, "實測值形如 claude-opus-5[1m]")
        let pre = try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1",
        ]))
        #expect(pre.model == nil)
    }

    @Test("Notification 的 message 欄位被讀出來，且缺 permission_mode/effort 也能解析")
    func notificationFields() throws {
        let notifs = try Fixtures.events(named: "round2", kind: "Notification")
        let json = try #require(notifs.first)
        #expect(json["permission_mode"] == nil, "實測：Notification 不帶此欄位")
        #expect(json["effort"] == nil)
        let p = try #require(HookPayload(json: json))
        #expect(p.notificationType == "idle_prompt")
        #expect(p.notificationMessage?.isEmpty == false)
        #expect(p.permissionMode == nil)
        #expect(p.effortLevel == nil)
    }

    @Test("tool_input.description 被讀出來，缺少或型別錯時回 nil")
    func toolDescriptionExtraction() throws {
        let reqs = try Fixtures.events(named: "round2", kind: "PermissionRequest")
        let p = try #require(HookPayload(json: try #require(reqs.first)))
        #expect(p.toolDescription?.isEmpty == false,
                "實測 PermissionRequest 的 tool_input 帶 description")

        // tool_input 缺失、非物件、description 缺失、description 非字串 —— 都不得 crash
        for weird: Any in [NSNull(), "not a dict", 42, [1, 2], ["other": "x"], ["description": 7]] {
            let q = try #require(HookPayload(json: [
                "hook_event_name": "PreToolUse", "session_id": "s1", "tool_input": weird,
            ]))
            #expect(q.toolDescription == nil)
        }
        let r = try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1",
        ]))
        #expect(r.toolDescription == nil, "完全沒有 tool_input")
    }

    @Test("PermissionRequest 的實測欄位（含 permission_suggestions）")
    func permissionRequestFields() throws {
        let reqs = try Fixtures.events(named: "round2", kind: "PermissionRequest")
        #expect(!reqs.isEmpty, "Task 01 第三輪必須捕獲")
        let json = try #require(reqs.first)
        #expect(json["permission_mode"] as? String == "default",
                "CLI 的 --permission-mode manual 在 payload 裡是 default")
        #expect(json["permission_suggestions"] != nil, "實測發現的額外欄位")
        let p = try #require(HookPayload(json: json))
        #expect(p.effect == .setActivity(.waiting))
        #expect(p.toolName == "Bash")
    }

    @Test("SessionEnd 的實測 reason 值")
    func sessionEndReason() throws {
        let ends = try Fixtures.events(named: "round2", kind: "SessionEnd")
        #expect(!ends.isEmpty)
        let p = try #require(HookPayload(json: try #require(ends.first)))
        #expect(p.reason == "prompt_input_exit", "實測值")
        #expect(p.effect == .sessionEnded)
    }

    @Test("effect 直接委派給 EventMapping，含 notification_type")
    func effectDelegation() throws {
        let a = try #require(HookPayload(json: [
            "hook_event_name": "Notification", "session_id": "s1",
            "notification_type": "agent_completed",
        ]))
        #expect(a.effect == .setActivity(.done))

        let b = try #require(HookPayload(json: [
            "hook_event_name": "Notification", "session_id": "s1",
            "notification_type": "auth_success",
        ]))
        #expect(b.effect == .noChange)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter HookPayloadTests 2>&1 | tail -10`
Expected: FAIL — `cannot find 'HookPayload' in scope`

- [ ] **Step 3: 實作 HookPayload**

```swift
// Sources/AuraCore/HookPayload.swift
import Foundation

/// Claude Code 送進 hook stdin 的 payload。
///
/// 刻意用字典讀取而非 `Codable`：上游 schema 會變（實測已發現 4 處與文件不符），
/// 字典讀取對未知欄位、缺失欄位、改型欄位天生容忍。
public struct HookPayload: Sendable, Equatable {
    public let hookEventName: String
    public let sessionID: String
    public let cwd: String?
    public let permissionMode: String?
    public let effortLevel: String?
    public let source: String?
    public let reason: String?
    public let toolName: String?
    public let toolDurationMs: Int?
    public let notificationType: String?
    public let lastMessage: String?
    public let agentID: String?
    public let agentType: String?

    /// `agent_id` 非 nil 即為 subagent 的事件。主 agent 的事件此欄為 `null`。
    public var isSubagent: Bool { agentID != nil }

    public var effect: EventEffect {
        EventMapping.effect(forEvent: hookEventName, notificationType: notificationType)
    }

    public init?(json: [String: Any]) {
        guard let event = json["hook_event_name"] as? String, !event.isEmpty,
              let sid = Self.string(json["session_id"]), !sid.isEmpty
        else { return nil }

        hookEventName    = event
        sessionID        = sid
        cwd              = Self.string(json["cwd"])
        permissionMode   = Self.string(json["permission_mode"])
        effortLevel      = Self.effortLevel(json["effort"])
        source           = Self.string(json["source"])
        // 文件寫 end_reason，實測是 reason —— 兩者都讀。
        reason           = Self.string(json["reason"]) ?? Self.string(json["end_reason"])
        toolName         = Self.string(json["tool_name"])
        // tool_input.description —— Claude Code 為 Bash 等 tool 產生的人可讀說明。
        // 面板在 waiting 那一列要顯示「在等你批准什麼」，只有 tool_name 不夠
        //（「等待權限：Bash」看不出在等什麼，而那正是最需要資訊的一列）。
        toolDescription  = Self.nonEmpty((json["tool_input"] as? [String: Any])?["description"])
        toolDurationMs   = json["duration_ms"] as? Int
        notificationType = Self.nonEmpty(json["notification_type"])
        notificationMessage = Self.nonEmpty(json["message"])
        // model 只有 SessionStart 提供；PostModelSwitch 用 to_model 帶新模型。
        // 少了後者，使用者中途 /model 換模型後面板會顯示過時的模型。
        model            = Self.nonEmpty(json["model"]) ?? Self.nonEmpty(json["to_model"])
        lastMessage      = Self.string(json["last_assistant_message"])
        agentID          = Self.nonEmpty(json["agent_id"])
        // 內部 subagent 的 agent_type 是**空字串**而非 null —— 正規化，
        // 否則 subagents 會出現 "": N 這種無意義鍵（§2.5.1）。
        agentType        = Self.nonEmpty(json["agent_type"])
    }

    public init?(data: Data) {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any]
        else { return nil }
        self.init(json: dict)
    }

    /// 只接受真正的 String；`NSNull`、數字、容器都轉不成 String，自然回 nil。
    static func string(_ any: Any?) -> String? { any as? String }

    /// 同 `string`，但空字串也視為缺值。
    static func nonEmpty(_ any: Any?) -> String? {
        guard let s = any as? String, !s.isEmpty else { return nil }
        return s
    }

    /// `effort` 實測是 `{"level":"xhigh"}`，但也容忍字串形狀。
    static func effortLevel(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let d = any as? [String: Any] { return string(d["level"]) }
        return nil
    }
}
```

- [ ] **Step 4: 執行確認通過**

Run: `swift test --filter HookPayloadTests 2>&1 | tail -12`
Expected: 全部 PASS（14 個測試）

- [ ] **Step 5: 檢查行數上限**

Run: `wc -l Sources/AuraCore/HookPayload.swift`
Expected: ≤ 200

- [ ] **Step 6: Commit**

```bash
git add Sources/AuraCore/HookPayload.swift Tests/AuraCoreTests/HookPayloadTests.swift
git commit -m "feat(core): HookPayload 容錯解析，含 effort/reason 型別容忍與 subagent 判別"
```

---

### Task 05: SessionSnapshot 狀態檔 schema + MergeRules

我方的狀態檔格式（與 `HookPayload` 分開 —— 前者是我們的契約，後者是上游的）。
`MergeRules` 是 §2.5 分槽與累積欄位的核心，`aura-hook` 與測試共用。

**Files:**
- Create: `Sources/AuraCore/SessionSnapshot.swift`
- Create: `Sources/AuraCore/MergeRules.swift`
- Test: `Tests/AuraCoreTests/MergeRulesTests.swift`

**Interfaces:**
- Consumes: `Activity`、`EventEffect`、`HookPayload`
- Produces:
  ```swift
  public struct SessionSnapshot: Codable, Sendable, Equatable {
      public var schema: Int, sessionID: String, hookEventName: String
      public var writtenAt: Date, pid: Int32?, pidStartedAt: Int64?
      public var cwd: String?, permissionMode: String?, effort: String?, model: String?
      public var source: String?, reason: String?
      public var mainActivity: Activity, mainTool: String?
      public var subActivity: Activity?, subTool: String?, subAgentType: String?
      public var notificationType: String?, lastMessage: String?, toolDurationMs: Int?
      public var turnStartedAt: Date?, subagents: [String: Int], toolFailures: Int
      public var terminated: Bool
      public init(sessionID: String)                      // 空白初始狀態
  }
  public enum MergeRules {
      public static func merge(_ payload: HookPayload, into existing: SessionSnapshot?,
                              pid: Int32?, pidStartedAt: Int64?, now: Date) -> SessionSnapshot
  }
  ```

- [ ] **Step 1: 寫失敗測試 —— 分槽與累積**

```swift
// Tests/AuraCoreTests/MergeRulesTests.swift
import Testing
import Foundation
@testable import AuraCore

@Suite("MergeRules 分槽與累積（§2.5）")
struct MergeRulesTests {

    let t0 = Date(timeIntervalSince1970: 1_788_628_000)

    func payload(_ event: String, tool: String? = nil, agent: String? = nil,
                 agentType: String? = nil, notif: String? = nil) -> HookPayload {
        var json: [String: Any] = ["hook_event_name": event, "session_id": "s1"]
        if let tool { json["tool_name"] = tool }
        if let agent { json["agent_id"] = agent; json["agent_type"] = agentType ?? "implementer" }
        if let notif { json["notification_type"] = notif }
        return HookPayload(json: json)!
    }

    func merge(_ p: HookPayload, into s: SessionSnapshot?, at t: Date? = nil) -> SessionSnapshot {
        MergeRules.merge(p, into: s, pid: 4242, pidStartedAt: 111, now: t ?? t0)
    }

    // ---- 核心：subagent 不得蓋掉主 agent 的 waiting ----

    @Test("subagent 的 PostToolUse 不得蓋掉主 agent 的 waiting")
    func subagentCannotMaskWaiting() {
        var s = merge(payload("PermissionRequest", tool: "Bash"), into: nil)
        #expect(s.mainActivity == .waiting)

        // 20ms 後 subagent 插入事件 —— 實測的真實間隔
        s = merge(payload("PostToolUse", tool: "Write", agent: "sub1"),
                  into: s, at: t0.addingTimeInterval(0.02))

        #expect(s.mainActivity == .waiting, "主槽必須維持 waiting")
        #expect(s.subActivity == .working, "subagent 寫進自己的槽")
        #expect(max(s.mainActivity, s.subActivity ?? .idle) == .waiting,
                "取 max 後仍是 waiting —— 橘燈不會消失")
    }

    @Test("主 agent 的長 tool 名不被 subagent 覆蓋")
    func mainToolNotOverwritten() {
        var s = merge(payload("PreToolUse", tool: "Bash"), into: nil)
        for i in 0..<8 {
            s = merge(payload(i.isMultiple(of: 2) ? "PreToolUse" : "PostToolUse",
                              tool: "Write", agent: "sub1"),
                      into: s, at: t0.addingTimeInterval(Double(i) + 5))
        }
        #expect(s.mainTool == "Bash", "實測情境：主 agent Bash 跑 19.5s，期間 subagent 插 8 個事件")
        #expect(s.subTool == "Write")
        #expect(s.subAgentType == "implementer")
    }

    @Test("主 agent 的 Stop 會清空 subagent 槽")
    func stopClearsSubSlot() {
        var s = merge(payload("PreToolUse", tool: "Bash"), into: nil)
        s = merge(payload("PostToolUse", tool: "Write", agent: "sub1"), into: s)
        #expect(s.subActivity == .working)

        s = merge(payload("Stop"), into: s)
        #expect(s.mainActivity == .done)
        #expect(s.subActivity == nil, "該輪的 subagent 都已結束")
        #expect(s.subTool == nil)
    }

    // ---- §2.5.1：主 agent 靜止後必須忽略 subagent 事件 ----

    @Test("Stop 之後 2.6s 抵達的內部 SubagentStop 不得把 done 變成 working")
    func internalSubagentStopAfterStopIsIgnored() {
        var s = merge(payload("Stop"), into: nil)
        #expect(s.mainActivity == .done)

        // 實測時序：agent_type 空字串的內部 subagent，Stop 後 +2.58s
        let internalSub = HookPayload(json: [
            "hook_event_name": "SubagentStop", "session_id": "s1",
            "agent_id": "a8c360a1fe475f199", "agent_type": "",
        ])!
        s = merge(internalSub, into: s, at: t0.addingTimeInterval(2.58))

        #expect(s.mainActivity == .done)
        #expect(s.subActivity == nil, "主 agent 靜止 → 不得寫 sub 槽")
        #expect(max(s.mainActivity, s.subActivity ?? .idle) == .done,
                "綠燈必須維持綠燈 —— 此 bug 會影響每一個跑完的 session")
        #expect(s.writtenAt == t0.addingTimeInterval(2.58), "但時戳仍要更新")
    }

    @Test("StopFailure 之後的 SubagentStop 不得把 error 變成 working")
    func subagentStopAfterStopFailureIsIgnored() {
        var s = merge(payload("StopFailure"), into: nil)
        s = merge(payload("SubagentStop", agent: "a1"), into: s, at: t0.addingTimeInterval(3))
        #expect(s.mainActivity == .error)
        #expect(s.subActivity == nil)
    }

    @Test("PermissionRequest 之後的 subagent 事件不得寫 sub 槽")
    func subagentIgnoredWhileWaiting() {
        var s = merge(payload("PermissionRequest", tool: "Bash"), into: nil)
        s = merge(payload("PostToolUse", tool: "Write", agent: "a1"),
                  into: s, at: t0.addingTimeInterval(0.02))
        #expect(s.mainActivity == .waiting)
        #expect(s.subActivity == nil, "比單靠 max 更直接地保護 waiting")
    }

    @Test("主 agent 仍在 working 時，subagent 事件正常寫入 sub 槽")
    func subagentRecordedWhileWorking() {
        var s = merge(payload("PreToolUse", tool: "Bash"), into: nil)
        s = merge(payload("PostToolUse", tool: "Grep", agent: "a1", agentType: "Explore"), into: s)
        #expect(s.subActivity == .working)
        #expect(s.subTool == "Grep")
        #expect(s.subAgentType == "Explore")
    }

    @Test("agent_type 空字串的 subagent 不計入 subagents")
    func internalSubagentNotCounted() {
        let start = HookPayload(json: [
            "hook_event_name": "SubagentStart", "session_id": "s1",
            "agent_id": "a1", "agent_type": "",
        ])!
        let s = merge(start, into: nil)
        #expect(s.subagents.isEmpty, "不得出現空字串鍵")
    }

    @Test("model 只由 SessionStart 提供，後續事件必須帶過來")
    func modelCarriedForward() {
        let start = HookPayload(json: [
            "hook_event_name": "SessionStart", "session_id": "s1",
            "source": "startup", "model": "claude-opus-5[1m]",
        ])!
        var s = merge(start, into: nil)
        #expect(s.model == "claude-opus-5[1m]")
        s = merge(payload("UserPromptSubmit"), into: s, at: t0.addingTimeInterval(5))
        #expect(s.model == "claude-opus-5[1m]", "PreToolUse 等事件不帶 model，不得被清掉")
    }

    @Test("主 agent 的 StopFailure 同樣清空 subagent 槽")
    func stopFailureClearsSubSlot() {
        var s = merge(payload("PostToolUse", tool: "Write", agent: "sub1"), into: nil)
        s = merge(payload("StopFailure"), into: s)
        #expect(s.mainActivity == .error)
        #expect(s.subActivity == nil)
    }

    // ---- 累積欄位 ----

    @Test("UserPromptSubmit 設定 turnStartedAt，後續事件沿用")
    func turnStartTracking() {
        var s = merge(payload("UserPromptSubmit"), into: nil)
        #expect(s.turnStartedAt == t0)

        s = merge(payload("PreToolUse", tool: "Bash"), into: s, at: t0.addingTimeInterval(30))
        #expect(s.turnStartedAt == t0, "同一輪內不得被重設")

        s = merge(payload("UserPromptSubmit"), into: s, at: t0.addingTimeInterval(90))
        #expect(s.turnStartedAt == t0.addingTimeInterval(90), "新一輪重設")
    }

    @Test("subagents 依 agent_type 累加，SubagentStart 才計數")
    func subagentCounting() {
        var s: SessionSnapshot? = nil
        s = merge(payload("SubagentStart", agent: "a1", agentType: "Explore"), into: s)
        s = merge(payload("SubagentStart", agent: "a2", agentType: "Explore"), into: s)
        s = merge(payload("SubagentStart", agent: "a3", agentType: "implementer"), into: s)
        #expect(s?.subagents == ["Explore": 2, "implementer": 1])

        // 一般 tool 事件不得重複計數
        s = merge(payload("PostToolUse", tool: "Write", agent: "a1", agentType: "Explore"), into: s)
        #expect(s?.subagents == ["Explore": 2, "implementer": 1])
    }

    @Test("toolFailures 累加，新一輪歸零")
    func toolFailureCounting() {
        var s: SessionSnapshot? = nil
        for _ in 0..<3 { s = merge(payload("PostToolUseFailure", tool: "Bash"), into: s) }
        #expect(s?.toolFailures == 3)
        #expect(s?.mainActivity == .working, "tool 失敗不改變 activity")

        s = merge(payload("UserPromptSubmit"), into: s, at: t0.addingTimeInterval(60))
        #expect(s?.toolFailures == 0, "新一輪重新計算")
    }

    // ---- 終止與復活 ----

    @Test("SessionEnd 標記 terminated 並保留最後的 activity")
    func sessionEndMarksTerminated() {
        var s = merge(payload("Stop"), into: nil)
        s = merge(payload("SessionEnd"), into: s)
        #expect(s.terminated)
        #expect(s.mainActivity == .done, "終止不得抹掉未確認的結果")
    }

    @Test("SessionStart 會清除 terminated（resume 情境）")
    func sessionStartClearsTerminated() {
        var s = merge(payload("SessionEnd"), into: nil)
        #expect(s.terminated)
        s = merge(payload("SessionStart"), into: s)
        #expect(!s.terminated)
        #expect(s.mainActivity == .idle)
    }

    @Test("noChange 事件只更新 writtenAt，不動 activity")
    func noChangePreservesActivity() {
        var s = merge(payload("PermissionRequest", tool: "Bash"), into: nil)
        s = merge(payload("Notification", notif: "auth_success"),
                  into: s, at: t0.addingTimeInterval(5))
        #expect(s.mainActivity == .waiting, "auth_success 不得改變 activity")
        #expect(s.writtenAt == t0.addingTimeInterval(5), "但時戳要更新")
    }

    @Test("未知 event 也只更新 writtenAt")
    func unknownEventPreservesActivity() {
        var s = merge(payload("PermissionRequest"), into: nil)
        s = merge(payload("FutureEvent2027"), into: s, at: t0.addingTimeInterval(3))
        #expect(s.mainActivity == .waiting)
        #expect(s.writtenAt == t0.addingTimeInterval(3))
    }

    // ---- Codable round-trip ----

    @Test("JSON round-trip 保留全部欄位")
    func codableRoundTrip() throws {
        var s = merge(payload("UserPromptSubmit"), into: nil)
        s = merge(payload("PermissionRequest", tool: "Bash"), into: s)
        s = merge(payload("PostToolUse", tool: "Write", agent: "a1", agentType: "Explore"), into: s)

        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(SessionSnapshot.self, from: try enc.encode(s))
        #expect(back == s)
    }

    @Test("schema 欄位固定為 1")
    func schemaVersion() {
        #expect(merge(payload("Stop"), into: nil).schema == 1)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter MergeRulesTests 2>&1 | tail -10`
Expected: FAIL — `cannot find 'SessionSnapshot' in scope`

- [ ] **Step 3: 實作 SessionSnapshot**

```swift
// Sources/AuraCore/SessionSnapshot.swift
import Foundation

/// `~/.agentaura/sessions/<session_id>.json` 的內容。
///
/// 分成三類欄位：
/// 1. 當次事件直接覆寫的（`hookEventName`、`writtenAt`、`cwd` …）
/// 2. **分槽**欄位（`main*` / `sub*`）—— subagent 不得覆蓋主 agent，見 §2.5
/// 3. **累積**欄位（`turnStartedAt`、`subagents`、`toolFailures`）—— 由 `MergeRules` 帶過來
public struct SessionSnapshot: Codable, Sendable, Equatable {
    public var schema: Int = 1
    public var sessionID: String
    public var hookEventName: String = ""
    public var writtenAt: Date = .distantPast

    public var pid: Int32?
    public var pidStartedAt: Int64?

    public var cwd: String?
    public var permissionMode: String?
    public var effort: String?
    public var model: String?
    public var source: String?
    public var reason: String?

    public var mainActivity: Activity = .idle
    public var mainTool: String?
    public var subActivity: Activity?
    public var subTool: String?
    public var subAgentType: String?

    public var notificationType: String?
    public var notificationMessage: String?
    public var lastMessage: String?
    public var toolDescription: String?
    public var toolDurationMs: Int?

    public var turnStartedAt: Date?
    public var subagents: [String: Int] = [:]
    public var toolFailures: Int = 0
    public var terminated: Bool = false

    public init(sessionID: String) { self.sessionID = sessionID }

    /// 取兩槽的優先序最大值 —— `waiting`(3) > `working`(2)，故 subagent 蓋不掉 waiting。
    public var effectiveActivity: Activity { max(mainActivity, subActivity ?? .idle) }

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID       = "session_id"
        case hookEventName   = "hook_event_name"
        case writtenAt       = "written_at"
        case pid
        case pidStartedAt    = "pid_started_at"
        case cwd, permissionMode = "permission_mode", effort, model, source, reason
        case mainActivity    = "main_activity"
        case mainTool        = "main_tool"
        case subActivity     = "sub_activity"
        case subTool         = "sub_tool"
        case subAgentType    = "sub_agent_type"
        case notificationType    = "notification_type"
        case notificationMessage = "notification_message"
        case lastMessage         = "last_message"
        case toolDescription     = "tool_description"
        case toolDurationMs      = "tool_duration_ms"
        case turnStartedAt   = "turn_started_at"
        case subagents, toolFailures = "tool_failures", terminated
    }
}
```

> 注意：`CodingKeys` 中 `case cwd, permissionMode = "permission_mode", effort, source, reason`
> 這種混合寫法在 Swift 合法。若編譯器抱怨，改成每個 case 各自一行。

- [ ] **Step 4: 實作 MergeRules**

```swift
// Sources/AuraCore/MergeRules.swift
import Foundation

/// 把一個 hook event 併進既有狀態。`aura-hook` 與測試共用同一份規則。
public enum MergeRules {

    public static func merge(_ p: HookPayload,
                             into existing: SessionSnapshot?,
                             pid: Int32?,
                             pidStartedAt: Int64?,
                             now: Date) -> SessionSnapshot {
        var s = existing ?? SessionSnapshot(sessionID: p.sessionID)

        s.hookEventName = p.hookEventName
        s.writtenAt     = now
        s.pid           = pid ?? s.pid
        s.pidStartedAt  = pidStartedAt ?? s.pidStartedAt
        s.cwd            = p.cwd ?? s.cwd
        s.permissionMode = p.permissionMode ?? s.permissionMode
        s.effort         = p.effortLevel ?? s.effort
        // model 只有 SessionStart 提供，必須帶過來（§2.1.1 第二輪校正）。
        s.model          = p.model ?? s.model
        if let src = p.source   { s.source = src }
        if let r   = p.reason   { s.reason = r }
        if let n   = p.notificationType { s.notificationType = n }
        if let nm  = p.notificationMessage { s.notificationMessage = nm }
        if let td  = p.toolDescription  { s.toolDescription = td }
        if let m   = p.lastMessage      { s.lastMessage = m }
        if let d   = p.toolDurationMs   { s.toolDurationMs = d }

        applyCounters(p, to: &s, now: now)

        switch p.effect {
        case .setActivity(let a):
            if p.isSubagent {
                // §2.5.1 —— 主 agent 靜止時完全忽略 subagent 事件。
                // 實測：Claude Code 的內部 subagent（agent_type 空字串、只送
                // SubagentStop）會在主 agent Stop 之後 2.6s ~ 184s 才抵達。
                // 若寫進 sub 槽，max(done, working) = working，綠燈變藍燈且回不去。
                guard !s.mainActivity.isQuiescent else { break }
                s.subActivity  = a
                s.subTool      = p.toolName ?? s.subTool
                s.subAgentType = p.agentType ?? s.subAgentType
            } else {
                s.mainActivity = a
                if let t = p.toolName { s.mainTool = t }
                if p.hookEventName == "SessionStart" { s.terminated = false }
                // 一輪結束 → 該輪的 subagent 都已結束，清空從屬槽。
                if a == .done || a == .error { clearSubSlot(&s) }
            }
        case .sessionEnded:
            s.terminated = true            // 刻意保留 mainActivity：未確認的結果不得被抹掉
        case .noChange:
            break                          // 只更新了時戳
        }
        return s
    }

    static func applyCounters(_ p: HookPayload, to s: inout SessionSnapshot, now: Date) {
        if !p.isSubagent, p.hookEventName == "UserPromptSubmit" {
            s.turnStartedAt = now          // 新一輪：重設時戳與計數
            s.toolFailures  = 0
            s.subagents     = [:]
        }
        if p.hookEventName == "PostToolUseFailure" { s.toolFailures += 1 }
        // agentType 已在 HookPayload 把空字串正規化為 nil，故內部 subagent 不計入。
        if p.hookEventName == "SubagentStart", let type = p.agentType {
            s.subagents[type, default: 0] += 1
        }
    }

    static func clearSubSlot(_ s: inout SessionSnapshot) {
        s.subActivity = nil
        s.subTool = nil
        s.subAgentType = nil
    }
}
```

- [ ] **Step 5: 執行確認通過**

Run: `swift test --filter MergeRulesTests 2>&1 | tail -12`
Expected: 全部 PASS（14 個測試）

- [ ] **Step 6: Mutation 驗證 —— 分槽是否真的有牙齒**

手動把 `merge` 裡的 `if p.isSubagent` 分支改成一律寫 `s.mainActivity = a`（即回到單槽 last-write-wins），
執行 `swift test --filter MergeRulesTests`。

Expected: `subagentCannotMaskWaiting` 與 `mainToolNotOverwritten` **必須 FAIL**。
確認 RED 後 `git checkout Sources/AuraCore/MergeRules.swift` 還原，再跑一次確認全綠。

- [ ] **Step 7: 檢查行數**

Run: `wc -l Sources/AuraCore/SessionSnapshot.swift Sources/AuraCore/MergeRules.swift`
Expected: 兩者皆 ≤ 200

- [ ] **Step 8: Commit**

```bash
git add Sources/AuraCore/SessionSnapshot.swift Sources/AuraCore/MergeRules.swift \
        Tests/AuraCoreTests/MergeRulesTests.swift
git commit -m "feat(core): SessionSnapshot schema 與 MergeRules 分槽合併

subagent 事件寫入獨立槽位，activity 取兩槽 max —— 修 subagent 在 20ms 內
蓋掉主 agent waiting 的 critical bug（spec §2.5）。"
```

---

### Task 06: Liveness —— pid + 啟動時戳（防 pid 回收）

`kill(pid, 0)` 只證明「某個 process 存在」，不證明是原本那個。用 `sysctl(KERN_PROC_PID)`
取啟動時戳一併比對。

> **前置條件：** 若 Task 01 的 `mechanisms.md` 判定 `getppid()` **不等於** claude 本體
> （父行程是 `sh`/`bash` 等），則本 task 改為實作 **session 心跳 TTL**：
> `HookFileSource` 判定 `now - writtenAt > 120s` 且非靜止態即視為已死。
> 兩種實作共用同一個 `LivenessProbing` protocol 與同一組測試意圖，只換實作。

**Files:**
- Create: `Sources/AuraCore/Liveness.swift`
- Test: `Tests/AuraCoreTests/LivenessTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum Liveness: Equatable, Sendable { case alive(pid: Int32), ended }
  public protocol LivenessProbing: Sendable {
      func startTime(ofPID pid: Int32) -> Int64?
      func isAlive(pid: Int32, startedAt: Int64) -> Bool
  }
  public struct SysctlLiveness: LivenessProbing { public init() }
  public struct StubLiveness: LivenessProbing {          // 測試與對抗式 double 用
      public init(table: [Int32: Int64])
  }
  ```

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/AuraCoreTests/LivenessTests.swift
import Testing
import Foundation
@testable import AuraCore

@Suite("Liveness 與 pid 回收（§3.5）")
struct LivenessTests {

    @Test("能取得自己這個 process 的啟動時戳")
    func ownStartTime() {
        let probe = SysctlLiveness()
        let t = probe.startTime(ofPID: getpid())
        #expect(t != nil)
        #expect(t! > 1_600_000_000, "應是合理的 unix 秒數")
        #expect(t! <= Int64(Date().timeIntervalSince1970) + 1)
    }

    @Test("自己這個 process 用正確時戳查詢為活著")
    func selfIsAlive() {
        let probe = SysctlLiveness()
        let pid = getpid()
        let t = probe.startTime(ofPID: pid)!
        #expect(probe.isAlive(pid: pid, startedAt: t))
    }

    @Test("時戳不符即視為已死 —— 這就是 pid 回收的防線")
    func mismatchedStartTimeIsDead() {
        let probe = SysctlLiveness()
        let pid = getpid()
        let real = probe.startTime(ofPID: pid)!
        #expect(!probe.isAlive(pid: pid, startedAt: real + 1),
                "pid 相同但啟動時戳不同 → 是被回收後的另一個 process")
        #expect(!probe.isAlive(pid: pid, startedAt: 0))
    }

    @Test("不存在的 pid 回 nil / 已死")
    func nonexistentPID() {
        let probe = SysctlLiveness()
        // PID_MAX 之上必然不存在
        #expect(probe.startTime(ofPID: 999_999) == nil)
        #expect(!probe.isAlive(pid: 999_999, startedAt: 12345))
    }

    @Test("非法 pid 不得 crash")
    func invalidPIDs() {
        let probe = SysctlLiveness()
        for pid: Int32 in [0, -1, -999, Int32.max, Int32.min] {
            _ = probe.startTime(ofPID: pid)
            _ = probe.isAlive(pid: pid, startedAt: 1)
        }
    }

    @Test("真實子行程結束後即判定為死")
    func realChildProcessDies() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try p.run()
        let pid = p.processIdentifier
        let probe = SysctlLiveness()
        let t = try #require(probe.startTime(ofPID: pid))
        #expect(probe.isAlive(pid: pid, startedAt: t))

        p.terminate()
        p.waitUntilExit()
        // 收屍後 sysctl 應查不到
        #expect(!probe.isAlive(pid: pid, startedAt: t))
    }

    @Test("StubLiveness 可完全控制回答，供其他 suite 使用")
    func stubBehaviour() {
        let stub = StubLiveness(table: [100: 555])
        #expect(stub.isAlive(pid: 100, startedAt: 555))
        #expect(!stub.isAlive(pid: 100, startedAt: 556), "時戳不符 → 死")
        #expect(!stub.isAlive(pid: 101, startedAt: 555), "pid 不在表中 → 死")
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter LivenessTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'SysctlLiveness' in scope`

- [ ] **Step 3: 實作**

```swift
// Sources/AuraCore/Liveness.swift
import Foundation

public enum Liveness: Equatable, Sendable {
    case alive(pid: Int32)
    case ended
}

public protocol LivenessProbing: Sendable {
    /// 回傳該 pid 的啟動時戳（unix 秒）；查不到回 nil。
    func startTime(ofPID pid: Int32) -> Int64?
    /// pid **與**啟動時戳皆相符才算活著。
    func isAlive(pid: Int32, startedAt: Int64) -> Bool
}

extension LivenessProbing {
    public func isAlive(pid: Int32, startedAt: Int64) -> Bool {
        guard let t = startTime(ofPID: pid) else { return false }
        return t == startedAt
    }
}

/// 用 `sysctl(KERN_PROC_PID)` 取 `kinfo_proc.kp_proc.p_starttime`。
///
/// 只比 pid 不足以判定同一個 process —— pid 會被系統回收。時戳是識別碼的另一半。
public struct SysctlLiveness: LivenessProbing {
    public init() {}

    public func startTime(ofPID pid: Int32) -> Int64? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let rc = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        // process 不存在時 rc 可能是 0 但 size 歸零，必須一併檢查。
        guard rc == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return Int64(info.kp_proc.p_starttime.tv_sec)
    }
}

/// 測試與對抗式 double 用：完全可控的 liveness 回答。
public struct StubLiveness: LivenessProbing {
    let table: [Int32: Int64]
    public init(table: [Int32: Int64]) { self.table = table }
    public func startTime(ofPID pid: Int32) -> Int64? { table[pid] }
}
```

- [ ] **Step 4: 執行確認通過**

Run: `swift test --filter LivenessTests 2>&1 | tail -10`
Expected: 全部 PASS（7 個測試）

- [ ] **Step 5: Mutation 驗證**

手動把 `isAlive` 的 default 實作改成 `startTime(ofPID: pid) != nil`（即只比 pid、不比時戳），
執行 `swift test --filter LivenessTests`。

Expected: `mismatchedStartTimeIsDead` 與 `stubBehaviour` **必須 FAIL**。還原後全綠。

- [ ] **Step 6: Commit**

```bash
git add Sources/AuraCore/Liveness.swift Tests/AuraCoreTests/LivenessTests.swift
git commit -m "feat(core): Liveness 以 pid + 啟動時戳雙重驗證，防 pid 回收誤判"
```

---

### Task 07: SessionState、IconState 與 SessionReducer

**Files:**
- Create: `Sources/AuraCore/SessionState.swift`
- Create: `Sources/AuraCore/SessionReducer.swift`
- Test: `Tests/AuraCoreTests/SessionReducerTests.swift`

**Interfaces:**
- Consumes: `SessionSnapshot`、`Activity`、`LivenessProbing`
- Produces:
  ```swift
  public struct SessionState: Sendable, Equatable, Identifiable {
      public let id: String                  // == sessionID
      public let projectName: String          // cwd 的 basename，nil cwd → "(unknown)"
      public let projectPath: String?
      public let permissionMode: String?, effort: String?
      public let activity: Activity           // max(main, sub)
      public let mainActivity: Activity, subActivity: Activity?
      public let currentTool: String?, subagentTool: String?   // subagentTool 形如 "Explore → Grep"
      public let toolDurationMs: Int?
      public let turnStartedAt: Date?
      public let subagents: [String: Int], toolFailures: Int
      public let lastMessage: String?, errorType: String?
      public let liveness: Liveness
      public let updatedAt: Date
  }
  public struct IconState: Sendable, Equatable {
      public let activity: Activity
      public let counts: [Activity: Int]
      public let liveCount: Int
      public var attentionCount: Int          // counts[.error] + counts[.waiting]
  }
  public enum SessionReducer {
      public static func state(from s: SessionSnapshot, liveness probe: LivenessProbing) -> SessionState
  }
  ```

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/AuraCoreTests/SessionReducerTests.swift
import Testing
import Foundation
@testable import AuraCore

@Suite("SessionReducer")
struct SessionReducerTests {

    let probe = StubLiveness(table: [4242: 111])

    func snapshot(_ mutate: (inout SessionSnapshot) -> Void) -> SessionSnapshot {
        var s = SessionSnapshot(sessionID: "s1")
        s.pid = 4242; s.pidStartedAt = 111
        s.cwd = "/Users/you/Code/Vibe/payments-api"
        s.writtenAt = Date(timeIntervalSince1970: 1_788_628_000)
        mutate(&s)
        return s
    }

    @Test("activity 取兩槽 max —— waiting 不被 working 蓋掉")
    func activityTakesMax() {
        let s = snapshot { $0.mainActivity = .waiting; $0.subActivity = .working }
        let st = SessionReducer.state(from: s, liveness: probe)
        #expect(st.activity == .waiting)
        #expect(st.mainActivity == .waiting)
        #expect(st.subActivity == .working)
    }

    @Test("error 勝過 waiting（D1）")
    func errorBeatsWaiting() {
        let s = snapshot { $0.mainActivity = .error; $0.subActivity = .waiting }
        #expect(SessionReducer.state(from: s, liveness: probe).activity == .error)
    }

    @Test("專案名取 cwd 的 basename")
    func projectName() {
        #expect(SessionReducer.state(from: snapshot { _ in }, liveness: probe).projectName == "payments-api")
    }

    @Test("cwd 為 nil 或空時給可讀的替代名，不得 crash")
    func projectNameFallback() {
        for cwd in [nil, "", "/"] {
            let s = snapshot { $0.cwd = cwd }
            let name = SessionReducer.state(from: s, liveness: probe).projectName
            #expect(!name.isEmpty)
        }
    }

    @Test("unicode / emoji 專案名保留完整")
    func projectNameUnicode() {
        let s = snapshot { $0.cwd = "/Users/you/專案 🚀/fitness-tracker-測試" }
        #expect(SessionReducer.state(from: s, liveness: probe).projectName == "fitness-tracker-測試")
    }

    @Test("subagentTool 組成 「型別 → tool」 形式")
    func subagentToolLabel() {
        let s = snapshot { $0.subAgentType = "Explore"; $0.subTool = "Grep"; $0.subActivity = .working }
        #expect(SessionReducer.state(from: s, liveness: probe).subagentTool == "Explore → Grep")
    }

    @Test("subagent 槽為空時 subagentTool 為 nil")
    func subagentToolNilWhenEmpty() {
        #expect(SessionReducer.state(from: snapshot { _ in }, liveness: probe).subagentTool == nil)
    }

    @Test("pid 活著 → liveness 為 alive")
    func aliveWhenPIDMatches() {
        #expect(SessionReducer.state(from: snapshot { _ in }, liveness: probe).liveness == .alive(pid: 4242))
    }

    @Test("啟動時戳不符 → ended（pid 回收）")
    func endedWhenStartTimeMismatch() {
        let s = snapshot { $0.pidStartedAt = 999 }
        #expect(SessionReducer.state(from: s, liveness: probe).liveness == .ended)
    }

    @Test("terminated 旗標直接判 ended，不查 pid")
    func terminatedIsEnded() {
        let s = snapshot { $0.terminated = true }
        #expect(SessionReducer.state(from: s, liveness: probe).liveness == .ended)
    }

    @Test("pid 或 pidStartedAt 缺失時視為 ended")
    func missingPIDInfoIsEnded() {
        #expect(SessionReducer.state(from: snapshot { $0.pid = nil }, liveness: probe).liveness == .ended)
        #expect(SessionReducer.state(from: snapshot { $0.pidStartedAt = nil }, liveness: probe).liveness == .ended)
    }

    @Test("errorType 取自 reason 欄位")
    func errorTypeFromReason() {
        let s = snapshot { $0.mainActivity = .error; $0.reason = "overloaded_error" }
        #expect(SessionReducer.state(from: s, liveness: probe).errorType == "overloaded_error")
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter SessionReducerTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'SessionReducer' in scope`

- [ ] **Step 3: 實作 SessionState / IconState**

```swift
// Sources/AuraCore/SessionState.swift
import Foundation

public struct SessionState: Sendable, Equatable, Identifiable {
    public let id: String
    public let projectName: String
    public let projectPath: String?
    public let permissionMode: String?
    public let effort: String?
    public let activity: Activity
    public let mainActivity: Activity
    public let subActivity: Activity?
    public let currentTool: String?
    public let subagentTool: String?
    public let toolDurationMs: Int?
    public let turnStartedAt: Date?
    public let subagents: [String: Int]
    public let toolFailures: Int
    public let lastMessage: String?
    public let errorType: String?
    public let liveness: Liveness
    public let updatedAt: Date
}

// 註：刻意不提供 `SessionState.isQuiescent`。
// Ruling 10 之後 `SessionRegistry.visible` 改用明確的 `.done || .error`
// （`waiting` 不算「結果」），使 `SessionState` 層級的 isQuiescent 沒有生產消費者，
// 且會與 `Activity.isQuiescent` 邏輯重複。需要時寫 `state.activity.isQuiescent`。

public struct IconState: Sendable, Equatable {
    public let activity: Activity
    public let counts: [Activity: Int]
    public let liveCount: Int

    public init(activity: Activity, counts: [Activity: Int], liveCount: Int) {
        self.activity = activity; self.counts = counts; self.liveCount = liveCount
    }

    /// 「需要你」的定義：error + waiting。
    /// `done` 不計入 —— 它是「你可以去看了」，不是「你被擋著」。
    public var attentionCount: Int {
        (counts[.error] ?? 0) + (counts[.waiting] ?? 0)
    }

    public static let empty = IconState(activity: .idle, counts: [:], liveCount: 0)
}
```

- [ ] **Step 4: 實作 SessionReducer**

```swift
// Sources/AuraCore/SessionReducer.swift
import Foundation

public enum SessionReducer {

    public static func state(from s: SessionSnapshot,
                             liveness probe: LivenessProbing) -> SessionState {
        SessionState(
            id: s.sessionID,
            projectName: projectName(fromPath: s.cwd),
            projectPath: s.cwd,
            permissionMode: s.permissionMode,
            effort: s.effort,
            activity: s.effectiveActivity,
            mainActivity: s.mainActivity,
            subActivity: s.subActivity,
            currentTool: s.mainTool,
            subagentTool: subagentLabel(type: s.subAgentType, tool: s.subTool),
            toolDurationMs: s.toolDurationMs,
            turnStartedAt: s.turnStartedAt,
            subagents: s.subagents,
            toolFailures: s.toolFailures,
            lastMessage: s.lastMessage,
            errorType: s.mainActivity == .error ? s.reason : nil,
            liveness: Self.resolveLiveness(of: s, probe: probe),
            updatedAt: s.writtenAt
        )
    }

    /// 刻意不叫 `liveness` —— 那會被 `state(from:liveness:)` 的同名參數遮蔽。
    static func resolveLiveness(of s: SessionSnapshot, probe: LivenessProbing) -> Liveness {
        guard !s.terminated,
              let pid = s.pid, let started = s.pidStartedAt,
              probe.isAlive(pid: pid, startedAt: started)
        else { return .ended }
        return .alive(pid: pid)
    }

    static func projectName(fromPath path: String?) -> String {
        guard let path, !path.isEmpty else { return "(unknown)" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? "(root)" : name
    }

    static func subagentLabel(type: String?, tool: String?) -> String? {
        switch (type, tool) {
        case let (t?, u?): return "\(t) → \(u)"
        case let (t?, nil): return t
        case let (nil, u?): return u
        default: return nil
        }
    }
}
```

- [ ] **Step 5: 執行確認通過**

Run: `swift test --filter SessionReducerTests 2>&1 | tail -10`
Expected: 全部 PASS（13 個測試）

- [ ] **Step 6: Commit**

```bash
git add Sources/AuraCore/SessionState.swift Sources/AuraCore/SessionReducer.swift \
        Tests/AuraCoreTests/SessionReducerTests.swift
git commit -m "feat(core): SessionState / IconState 與 SessionReducer"
```

---

### Task 08: SessionRegistry —— unacked 尾巴與 acknowledge

產品最大價值所在：整夜跑 pipeline、terminal 自己收掉，早上回來仍看得出發生了什麼。

**Files:**
- Create: `Sources/AuraCore/SessionRegistry.swift`
- Test: `Tests/AuraCoreTests/SessionRegistryTests.swift`

**Interfaces:**
- Consumes: `SessionState`、`Activity`
- Produces:
  ```swift
  public struct SessionRegistry: Sendable {
      public init()
      public private(set) var states: [String: SessionState]
      public private(set) var acknowledged: Set<String>
      public mutating func upsert(_ s: SessionState)
      /// 打開面板：所有未確認一律標為已確認，已結束且已確認者移出並回傳其 id（供刪檔）
      public mutating func acknowledgeAll() -> [String]
      /// 參與 icon 聚合的 session：活著的，加上已結束但未確認**結果**（done/error）的
      public var visible: [SessionState]
      public func isAcknowledged(_ id: String) -> Bool
  }
  ```

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/AuraCoreTests/SessionRegistryTests.swift
import Testing
import Foundation
@testable import AuraCore

@Suite("SessionRegistry unacked 尾巴（§2.4）")
struct SessionRegistryTests {

    func state(_ id: String, _ a: Activity, live: Bool = true) -> SessionState {
        SessionState(id: id, projectName: id, projectPath: "/x/\(id)",
                     permissionMode: nil, effort: nil,
                     activity: a, mainActivity: a, subActivity: nil,
                     currentTool: nil, subagentTool: nil, toolDurationMs: nil,
                     turnStartedAt: nil, subagents: [:], toolFailures: 0,
                     lastMessage: nil, errorType: nil,
                     liveness: live ? .alive(pid: 1) : .ended,
                     updatedAt: Date(timeIntervalSince1970: 1_788_628_000))
    }

    @Test("活著的 session 都可見")
    func aliveSessionsVisible() {
        var r = SessionRegistry()
        r.upsert(state("a", .working))
        r.upsert(state("b", .waiting))
        #expect(Set(r.visible.map(\.id)) == ["a", "b"])
    }

    @Test("已結束但未確認的 error 仍參與聚合 —— 核心價值")
    func endedUnackedErrorStillVisible() {
        var r = SessionRegistry()
        r.upsert(state("a", .error, live: false))
        #expect(r.visible.map(\.id) == ["a"], "整夜 pipeline 掛掉、terminal 收掉，早上仍看得到")
    }

    @Test("已結束但未確認的 done 仍參與聚合")
    func endedUnackedDoneStillVisible() {
        var r = SessionRegistry()
        r.upsert(state("a", .done, live: false))
        #expect(r.visible.map(\.id) == ["a"])
    }

    @Test("PermissionRequest 後直接 SessionEnd（按 Deny 的實測序列）→ 不得留在尾巴")
    func endedWhileWaitingIsDropped() {
        var r = SessionRegistry()
        r.upsert(state("denied", .waiting, live: false))
        #expect(r.visible.isEmpty,
                "已結束、使用者早就按過 Deny 的 session 不得亮橘燈說「有人在等你」（§2.4.1）")
    }

    @Test("pid 死亡且卡在 waiting → 同樣丟棄")
    func deadWhileWaitingIsDropped() {
        var r = SessionRegistry()
        r.upsert(state("crashed", .waiting, live: false))
        r.upsert(state("alive", .working))
        #expect(r.visible.map(\.id) == ["alive"])
    }

    @Test("還活著的 waiting 仍然可見（那是真的在等你）")
    func aliveWaitingStaysVisible() {
        var r = SessionRegistry()
        r.upsert(state("w", .waiting))
        #expect(r.visible.map(\.id) == ["w"])
    }

    @Test("已結束且非靜止態（working/idle）直接不可見")
    func endedNonQuiescentDropped() {
        var r = SessionRegistry()
        r.upsert(state("a", .working, live: false))
        r.upsert(state("b", .idle, live: false))
        #expect(r.visible.isEmpty, "跑到一半被砍掉、沒有結果可看 → 不需要佔用注意力")
    }

    @Test("acknowledgeAll 一次確認全部未確認的，不論是否可見")
    func acknowledgeAllMarksEverything() {
        var r = SessionRegistry()
        r.upsert(state("a", .error, live: false))
        r.upsert(state("b", .done, live: false))
        r.upsert(state("c", .waiting))
        _ = r.acknowledgeAll()
        #expect(r.isAcknowledged("a"))
        #expect(r.isAcknowledged("b"))
        #expect(r.isAcknowledged("c"))
    }

    @Test("acknowledgeAll 回傳「已結束且已確認」的 id，供刪檔")
    func acknowledgeAllReturnsRemovable() {
        var r = SessionRegistry()
        r.upsert(state("ended1", .error, live: false))
        r.upsert(state("ended2", .done,  live: false))
        r.upsert(state("alive1", .waiting))
        #expect(Set(r.acknowledgeAll()) == ["ended1", "ended2"],
                "還活著的不刪 —— 它還會繼續寫入")
    }

    @Test("已確認且已結束者移出 registry，不再可見")
    func ackedEndedRemoved() {
        var r = SessionRegistry()
        r.upsert(state("a", .error, live: false))
        _ = r.acknowledgeAll()
        #expect(r.visible.isEmpty)
        #expect(r.states["a"] == nil)
    }

    @Test("已確認但還活著的 session 仍可見（它會繼續更新）")
    func ackedButAliveStaysVisible() {
        var r = SessionRegistry()
        r.upsert(state("a", .waiting))
        _ = r.acknowledgeAll()
        #expect(r.visible.map(\.id) == ["a"])
    }

    @Test("已確認的 session 再有新活動 → 重新變成未確認")
    func newActivityResetsAcknowledgement() {
        var r = SessionRegistry()
        r.upsert(state("a", .done))
        _ = r.acknowledgeAll()
        #expect(r.isAcknowledged("a"))

        r.upsert(state("a", .working))      // 使用者又下了新 prompt
        #expect(!r.isAcknowledged("a"), "新一輪的結果需要重新被看過")
    }

    @Test("同一 session 重複 upsert 只保留最新")
    func upsertReplaces() {
        var r = SessionRegistry()
        r.upsert(state("a", .working))
        r.upsert(state("a", .waiting))
        #expect(r.states.count == 1)
        #expect(r.states["a"]?.activity == .waiting)
    }

    @Test("50 個 session 併存不出錯")
    func fiftySessions() {
        var r = SessionRegistry()
        for i in 0..<50 { r.upsert(state("s\(i)", i.isMultiple(of: 3) ? .waiting : .working)) }
        #expect(r.visible.count == 50)
        #expect(r.acknowledgeAll().isEmpty, "全部活著 → 沒有可刪的")
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter SessionRegistryTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'SessionRegistry' in scope`

- [ ] **Step 3: 實作**

```swift
// Sources/AuraCore/SessionRegistry.swift
import Foundation

/// 現存 session 與「已結束但未確認」的尾巴。
///
/// 尾巴的存在理由：整夜跑 pipeline、terminal 自己收掉的情境下，若 session 一結束就消失，
/// 使用者早上回來看到的是暗燈，產品最大價值被抵銷。
public struct SessionRegistry: Sendable {
    public private(set) var states: [String: SessionState] = [:]
    public private(set) var acknowledged: Set<String> = []

    public init() {}

    public func isAcknowledged(_ id: String) -> Bool { acknowledged.contains(id) }

    public mutating func upsert(_ s: SessionState) {
        // 新活動代表有新結果要被看過 —— 撤銷先前的確認。
        if let old = states[s.id], old.activity != s.activity || old.updatedAt < s.updatedAt {
            acknowledged.remove(s.id)
        }
        states[s.id] = s
        if s.liveness == .ended, acknowledged.contains(s.id) {
            states[s.id] = nil                  // 已看過又已結束 → 直接清掉
        }
    }

    /// 面板開啟：所有未確認一律標為已確認（不論是否捲動到、是否可見）。
    /// 回傳「已結束且已確認」的 id —— 呼叫端據此刪除狀態檔。
    public mutating func acknowledgeAll() -> [String] {
        acknowledged.formUnion(states.keys)
        let removable = states.values.filter { $0.liveness == .ended }.map(\.id)
        for id in removable { states[id] = nil }
        return removable
    }

    /// 參與 icon 聚合的 session：活著的，加上已結束但仍有未確認**結果**的。
    ///
    /// `waiting` 刻意不算結果（§2.4.1）。實測：使用者按 Deny 不產生任何 hook 事件，
    /// session 的最後事件停在 `PermissionRequest`，之後直接 `SessionEnd`。
    /// 若 `waiting` 也能進尾巴，一個已結束、使用者早就回答過的 session 會讓 icon
    /// 一直亮橘燈說「有人在等你」—— 本產品最不該犯的錯。
    public var visible: [SessionState] {
        states.values.filter { s in
            if s.liveness != .ended { return true }
            let isResult = s.activity == .done || s.activity == .error
            return isResult && !acknowledged.contains(s.id)
        }
    }
}
```

- [ ] **Step 4: 執行確認通過**

Run: `swift test --filter SessionRegistryTests 2>&1 | tail -10`
Expected: 全部 PASS（11 個測試）

- [ ] **Step 5: Mutation 驗證**

手動把 `visible` 的 ended 分支改成 `return false`（即 session 結束就消失），
執行 `swift test --filter SessionRegistryTests`。

Expected: `endedUnackedErrorStillVisible` 與 `endedUnackedDoneStillVisible` **必須 FAIL**。還原後全綠。

- [ ] **Step 6: Commit**

```bash
git add Sources/AuraCore/SessionRegistry.swift Tests/AuraCoreTests/SessionRegistryTests.swift
git commit -m "feat(core): SessionRegistry 與 unacked 尾巴，session 結束後未確認結果仍計入"
```

---

### Task 09: AggregatePolicy —— D1 優先序

**Files:**
- Create: `Sources/AuraCore/AggregatePolicy.swift`
- Test: `Tests/AuraCoreTests/AggregatePolicyTests.swift`

**Interfaces:**
- Consumes: `SessionState`、`IconState`、`Activity`
- Produces:
  ```swift
  public protocol AggregatePolicy: Sendable { func aggregate(_ s: [SessionState]) -> IconState }
  public struct PriorityAggregatePolicy: AggregatePolicy { public init() }
  ```

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/AuraCoreTests/AggregatePolicyTests.swift
import Testing
import Foundation
@testable import AuraCore

@Suite("AggregatePolicy 優先序（D1）")
struct AggregatePolicyTests {

    let policy = PriorityAggregatePolicy()

    func state(_ id: String, _ a: Activity, live: Bool = true) -> SessionState {
        SessionState(id: id, projectName: id, projectPath: nil,
                     permissionMode: nil, effort: nil,
                     activity: a, mainActivity: a, subActivity: nil,
                     currentTool: nil, subagentTool: nil, toolDurationMs: nil,
                     turnStartedAt: nil, subagents: [:], toolFailures: 0,
                     lastMessage: nil, errorType: nil,
                     liveness: live ? .alive(pid: 1) : .ended,
                     updatedAt: Date(timeIntervalSince1970: 1_788_628_000))
    }

    @Test("2 個 working + 1 個 error → error（使用者原始舉例）")
    func twoWorkingOneErrorIsError() {
        let r = policy.aggregate([state("a", .working), state("b", .working), state("c", .error)])
        #expect(r.activity == .error)
    }

    @Test("順序無關 —— 任何排列結果都相同")
    func orderIndependent() {
        let s = [state("a", .working), state("b", .error), state("c", .waiting), state("d", .done)]
        let expected = policy.aggregate(s).activity
        #expect(expected == .error)
        for _ in 0..<40 {
            #expect(policy.aggregate(s.shuffled()).activity == expected)
        }
    }

    @Test("error 勝過 waiting（D1：紅色絕對優先）")
    func errorBeatsWaiting() {
        #expect(policy.aggregate([state("a", .waiting), state("b", .error)]).activity == .error)
    }

    @Test("waiting 勝過 working")
    func waitingBeatsWorking() {
        #expect(policy.aggregate([state("a", .working), state("b", .waiting)]).activity == .waiting)
    }

    @Test("working 勝過 done")
    func workingBeatsDone() {
        #expect(policy.aggregate([state("a", .done), state("b", .working)]).activity == .working)
    }

    @Test("done 勝過 idle")
    func doneBeatsIdle() {
        #expect(policy.aggregate([state("a", .idle), state("b", .done)]).activity == .done)
    }

    @Test("空清單 → idle")
    func emptyIsIdle() {
        let r = policy.aggregate([])
        #expect(r.activity == .idle)
        #expect(r.liveCount == 0)
        #expect(r.attentionCount == 0)
    }

    @Test("counts 逐 activity 計數正確")
    func countsPerActivity() {
        let r = policy.aggregate([
            state("a", .working), state("b", .working), state("c", .working),
            state("d", .waiting), state("e", .error), state("f", .done),
        ])
        #expect(r.counts[.working] == 3)
        #expect(r.counts[.waiting] == 1)
        #expect(r.counts[.error] == 1)
        #expect(r.counts[.done] == 1)
        #expect(r.counts[.idle] == nil)
    }

    @Test("liveCount 只算活著的")
    func liveCountExcludesEnded() {
        let r = policy.aggregate([
            state("a", .working), state("b", .waiting),
            state("c", .error, live: false), state("d", .done, live: false),
        ])
        #expect(r.liveCount == 2)
        #expect(r.counts.values.reduce(0, +) == 4, "counts 涵蓋全部傳入的 session")
    }

    @Test("attentionCount = error + waiting，done 不計入")
    func attentionCountExcludesDone() {
        let r = policy.aggregate([
            state("a", .error), state("b", .waiting), state("c", .waiting),
            state("d", .done), state("e", .working),
        ])
        #expect(r.attentionCount == 3, "done 是「可以去看了」，不是「你被擋著」")
    }

    @Test("50 個 session 的聚合是 O(n) 且結果穩定")
    func fiftySessions() {
        var s = (0..<49).map { state("s\($0)", .working) }
        s.append(state("boom", .error))
        #expect(policy.aggregate(s).activity == .error)
        #expect(policy.aggregate(s).liveCount == 50)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter AggregatePolicyTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'PriorityAggregatePolicy' in scope`

- [ ] **Step 3: 實作**

```swift
// Sources/AuraCore/AggregatePolicy.swift
import Foundation

public protocol AggregatePolicy: Sendable {
    func aggregate(_ states: [SessionState]) -> IconState
}

/// D1：`error > waiting > working > done > idle`。
///
/// 純函數，與寫入順序、session 先後完全無關 —— 優先序完全來自 `Activity.priority`。
/// 若要調整優先序，改 `Activity.priority`，不要改這裡。
public struct PriorityAggregatePolicy: AggregatePolicy {
    public init() {}

    public func aggregate(_ states: [SessionState]) -> IconState {
        guard !states.isEmpty else { return .empty }

        var counts: [Activity: Int] = [:]
        var top = Activity.idle
        var live = 0

        for s in states {
            counts[s.activity, default: 0] += 1
            top = max(top, s.activity)
            if s.liveness != .ended { live += 1 }
        }
        return IconState(activity: top, counts: counts, liveCount: live)
    }
}
```

- [ ] **Step 4: 執行確認通過**

Run: `swift test --filter AggregatePolicyTests 2>&1 | tail -10`
Expected: 全部 PASS（11 個測試）

- [ ] **Step 5: Mutation 驗證（D1 的關鍵 gate）**

手動把 `top = max(top, s.activity)` 改成 `top = s.activity`（即最後一個贏），
執行 `swift test --filter AggregatePolicyTests`。

Expected: `twoWorkingOneErrorIsError` 與 `orderIndependent` **必須 FAIL**。還原後全綠。

- [ ] **Step 6: Commit**

```bash
git add Sources/AuraCore/AggregatePolicy.swift Tests/AuraCoreTests/AggregatePolicyTests.swift
git commit -m "feat(core): AggregatePolicy 依 D1 優先序聚合，與寫入順序無關"
```

---

### Task 10: SnapshotIO —— flock 讀寫與檔名安全

**Files:**
- Create: `Sources/AuraHookFile/SnapshotIO.swift`
- Test: `Tests/AuraCoreTests/SnapshotIOTests.swift`

**Interfaces:**
- Consumes: `SessionSnapshot`
- Produces:
  ```swift
  public enum SnapshotIO {
      public static let defaultRoot: URL                      // ~/.agentaura/sessions
      public static func isSafeSessionID(_ id: String) -> Bool
      public static func url(for sessionID: String, root: URL) throws -> URL
      /// 取 LOCK_SH 讀取；解析失敗回 nil（呼叫端須保留上次已知狀態）
      public static func read(sessionID: String, root: URL) -> SessionSnapshot?
      /// 取 LOCK_EX，read-merge-write。`transform` 收到既有值（可能為 nil）並回傳新值
      public static func update(sessionID: String, root: URL,
                               _ transform: (SessionSnapshot?) -> SessionSnapshot) throws
      public static func delete(sessionID: String, root: URL) throws
      public static func allSessionIDs(root: URL) -> [String]
      public static let encoder: JSONEncoder                   // .iso8601
      public static let decoder: JSONDecoder                   // .iso8601
  }
  public enum SnapshotIOError: Error, Equatable { case unsafeSessionID(String) }
  ```

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/AuraCoreTests/SnapshotIOTests.swift
import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

@Suite("SnapshotIO 鎖與檔名安全")
struct SnapshotIOTests {

    /// 每個測試各自一個暫存 root，避免互相干擾。
    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-test-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func snap(_ id: String, _ a: Activity) -> SessionSnapshot {
        var s = SessionSnapshot(sessionID: id)
        s.mainActivity = a; s.writtenAt = Date(timeIntervalSince1970: 1_788_628_000)
        s.hookEventName = "PreToolUse"
        return s
    }

    // ---- round-trip ----

    @Test("寫入後讀回完全相同")
    func roundTrip() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .waiting) }
        let back = try #require(SnapshotIO.read(sessionID: "s1", root: root))
        #expect(back == snap("s1", .waiting))
    }

    @Test("update 的 transform 收到既有值，可做累積")
    func updateSeesExisting() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .working) }
        try SnapshotIO.update(sessionID: "s1", root: root) { old in
            #expect(old?.mainActivity == .working, "第二次 update 必須看到第一次的結果")
            var s = old!; s.toolFailures = 7; return s
        }
        #expect(SnapshotIO.read(sessionID: "s1", root: root)?.toolFailures == 7)
    }

    @Test("讀取不存在的 session 回 nil")
    func readMissing() throws {
        #expect(SnapshotIO.read(sessionID: "nope", root: try makeRoot()) == nil)
    }

    // ---- 對抗式：畸形檔案 ----

    @Test("截斷的 JSON 檔回 nil，不得 crash")
    func truncatedFileReturnsNil() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .waiting) }
        let url = try SnapshotIO.url(for: "s1", root: root)
        let full = try Data(contentsOf: url)
        for cut in [0, 1, full.count / 3, full.count / 2, full.count - 1] {
            try full.prefix(cut).write(to: url)
            #expect(SnapshotIO.read(sessionID: "s1", root: root) == nil,
                    "截斷 \(cut) bytes 應回 nil —— 呼叫端須保留上次已知狀態，不得當成 session 不存在")
        }
    }

    @Test("垃圾內容回 nil")
    func garbageFileReturnsNil() throws {
        let root = try makeRoot()
        let url = try SnapshotIO.url(for: "s1", root: root)
        for junk in ["", "   ", "not json", "{}", "[]", "null", "{\"schema\":1}"] {
            try Data(junk.utf8).write(to: url)
            #expect(SnapshotIO.read(sessionID: "s1", root: root) == nil)
        }
    }

    // ---- 檔名安全（path traversal）----

    @Test("合法 session_id 通過")
    func safeIDsAccepted() {
        for id in ["abc123", "e69dc6d9-7364-4619-a438-159b48151b02", "a.b_c-d", "A1"] {
            #expect(SnapshotIO.isSafeSessionID(id), "\(id) 應合法")
        }
    }

    @Test("path traversal 與控制字元一律拒絕")
    func unsafeIDsRejected() {
        for id in ["..", ".", "../etc/passwd", "a/b", "a\\b", "", " ", "a b",
                   "a\u{0}b", "a\nb", "~/x", "/abs", String(repeating: "x", count: 200)] {
            #expect(!SnapshotIO.isSafeSessionID(id), "\(id.debugDescription) 應被拒絕")
        }
    }

    @Test("不安全的 session_id 讓 url(for:) 丟錯，不得寫到目錄外")
    func unsafeIDThrows() throws {
        let root = try makeRoot()
        #expect(throws: SnapshotIOError.self) {
            _ = try SnapshotIO.url(for: "../escaped", root: root)
        }
    }

    // ---- 併發（flock 的存在理由）----

    @Test("同一 session 的 8 條併發 update 不遺失任何一次累加")
    func concurrentUpdatesDoNotLoseCounts() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .working) }

        let iterations = 40, workers = 8
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            for _ in 0..<iterations {
                try? SnapshotIO.update(sessionID: "s1", root: root) { old in
                    var s = old ?? self.snap("s1", .working)
                    s.toolFailures += 1
                    return s
                }
            }
        }
        let final = try #require(SnapshotIO.read(sessionID: "s1", root: root))
        #expect(final.toolFailures == iterations * workers,
                "flock 必須讓 read-merge-write 成為原子操作")
    }

    @Test("50 個不同 session 併發寫入互不干擾")
    func concurrentDistinctSessions() throws {
        let root = try makeRoot()
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            try? SnapshotIO.update(sessionID: "s\(i)", root: root) { _ in
                self.snap("s\(i)", i.isMultiple(of: 3) ? .waiting : .working)
            }
        }
        #expect(SnapshotIO.allSessionIDs(root: root).count == 50)
        for i in 0..<50 {
            #expect(SnapshotIO.read(sessionID: "s\(i)", root: root)?.sessionID == "s\(i)")
        }
    }

    @Test("併發讀寫時讀取端不會拿到半截檔（讀到 nil 可接受，crash 不可）")
    func concurrentReadWhileWriting() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .working) }
        DispatchQueue.concurrentPerform(iterations: 4) { w in
            for i in 0..<200 {
                if w == 0 {
                    try? SnapshotIO.update(sessionID: "s1", root: root) { old in
                        var s = old ?? self.snap("s1", .working); s.toolFailures = i; return s
                    }
                } else {
                    _ = SnapshotIO.read(sessionID: "s1", root: root)
                }
            }
        }
        #expect(SnapshotIO.read(sessionID: "s1", root: root) != nil)
    }

    // ---- 其他 ----

    @Test("delete 移除檔案，allSessionIDs 隨之更新")
    func deleteRemoves() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .done) }
        #expect(SnapshotIO.allSessionIDs(root: root) == ["s1"])
        try SnapshotIO.delete(sessionID: "s1", root: root)
        #expect(SnapshotIO.allSessionIDs(root: root).isEmpty)
        try SnapshotIO.delete(sessionID: "s1", root: root)   // 重複刪不得丟錯
    }

    @Test("allSessionIDs 忽略非 .json 檔與子目錄")
    func allSessionIDsFilters() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .done) }
        try Data("x".utf8).write(to: root.appendingPathComponent("README.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        #expect(SnapshotIO.allSessionIDs(root: root) == ["s1"])
    }

    @Test("root 不存在時 update 會自動建立")
    func createsRootDirectory() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-test-\(UUID().uuidString)/deep/sessions")
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .idle) }
        #expect(SnapshotIO.read(sessionID: "s1", root: root) != nil)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter SnapshotIOTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'SnapshotIO' in scope`

- [ ] **Step 3: 實作**

```swift
// Sources/AuraHookFile/SnapshotIO.swift
import Foundation
import AuraCore

public enum SnapshotIOError: Error, Equatable {
    case unsafeSessionID(String)
}

/// 狀態檔的讀寫。所有寫入在 `flock(LOCK_EX)` 下完成 read-merge-write；
/// 讀取取 `LOCK_SH`。
///
/// 檔案是 per-session，故跨 session 零競爭；同一 session 內事件近乎循序，
/// 但 `async: true` 理論上可能重疊 —— 鎖是必要的，不是可選的。
public enum SnapshotIO {

    public static let defaultRoot = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".agentaura/sessions")

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 只接受單一路徑片段的安全字元，長度 1...128。
    public static func isSafeSessionID(_ id: String) -> Bool {
        guard (1...128).contains(id.count), id != ".", id != ".." else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public static func url(for sessionID: String, root: URL = defaultRoot) throws -> URL {
        guard isSafeSessionID(sessionID) else { throw SnapshotIOError.unsafeSessionID(sessionID) }
        return root.appendingPathComponent("\(sessionID).json")
    }

    public static func read(sessionID: String, root: URL = defaultRoot) -> SessionSnapshot? {
        guard let url = try? url(for: sessionID, root: root),
              let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        flock(fh.fileDescriptor, LOCK_SH)
        defer { flock(fh.fileDescriptor, LOCK_UN) }
        guard let data = try? fh.readToEnd(), !data.isEmpty else { return nil }
        return try? decoder.decode(SessionSnapshot.self, from: data)
    }

    public static func update(sessionID: String,
                              root: URL = defaultRoot,
                              _ transform: (SessionSnapshot?) -> SessionSnapshot) throws {
        let url = try url(for: sessionID, root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let fd = open(url.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EWOULDBLOCK) }
        defer { flock(fd, LOCK_UN) }

        let fh = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let existing = (try? fh.readToEnd()).flatMap { $0.isEmpty ? nil : $0 }
            .flatMap { try? decoder.decode(SessionSnapshot.self, from: $0) }

        let data = try encoder.encode(transform(existing))
        try fh.seek(toOffset: 0)
        try fh.truncate(atOffset: 0)
        try fh.write(contentsOf: data)
        try fh.synchronize()
    }

    public static func delete(sessionID: String, root: URL = defaultRoot) throws {
        let url = try url(for: sessionID, root: root)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func allSessionIDs(root: URL = defaultRoot) -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        return items
            .filter { $0.pathExtension == "json"
                   && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter(isSafeSessionID)
            .sorted()
    }
}
```

> **實作備註：** `truncate` + 就地覆寫（而非 tmp+rename）是刻意的 —— rename 會換掉 inode，
> 讓其他行程持有的 `flock` 落在舊 inode 上，鎖就失效了。就地覆寫加 `LOCK_SH` 讀取，
> 是唯一能同時保證鎖語意與讀取一致性的組合；讀到半截時回 `nil`，由呼叫端保留上次狀態。

- [ ] **Step 4: 執行確認通過**

Run: `swift test --filter SnapshotIOTests 2>&1 | tail -12`
Expected: 全部 PASS（13 個測試）

- [ ] **Step 5: Mutation 驗證 —— flock 是否真的有牙齒**

手動把 `update` 裡的 `flock(fd, LOCK_EX)` 那行連同 `defer { flock(fd, LOCK_UN) }` 註解掉，
執行 `swift test --filter SnapshotIOTests`。

Expected: `concurrentUpdatesDoNotLoseCounts` **必須 FAIL**（累加數會少於 320）。還原後全綠。

> 若沒鎖也偶然通過，把 `iterations` 提高到 200 再測 —— 競態必須能穩定重現，
> 否則這條測試沒有牙齒。

- [ ] **Step 6: Commit**

```bash
git add Sources/AuraHookFile/SnapshotIO.swift Tests/AuraCoreTests/SnapshotIOTests.swift
git commit -m "feat(io): SnapshotIO 以 flock 保證 read-merge-write 原子性，含 path traversal 防護"
```

---

### Task 11: aura-hook CLI

被 hook 呼叫的執行檔。**任何錯誤都必須靜默 `exit 0`** —— 觀測性絕不可干擾 agent。

**Files:**
- Create: `Sources/aura-hook/main.swift`
- Test: `Tests/AuraCoreTests/AuraHookCLITests.swift`

**Interfaces:**
- Consumes: `HookPayload`、`MergeRules`、`SnapshotIO`、`SysctlLiveness`
- Produces: 執行檔 `aura-hook`。行為契約：
  - stdin 讀 hook JSON；`AGENTAURA_ROOT` 環境變數可覆寫狀態檔目錄（測試用）
  - 記錄 `getppid()` 與其啟動時戳為 `pid` / `pid_started_at`
  - **一律 `exit 0`**，stdout / stderr 一律不輸出

- [ ] **Step 1: 寫失敗測試（黑箱：真的跑執行檔）**

```swift
// Tests/AuraCoreTests/AuraHookCLITests.swift
import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

@Suite("aura-hook CLI 黑箱行為")
struct AuraHookCLITests {

    /// 找出 `swift build` 產出的 aura-hook。
    static func binaryURL() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                break
            }
        }
        for config in ["debug", "release"] {
            let url = dir.appendingPathComponent(".build/\(config)/aura-hook")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw TestError.binaryMissing
    }

    enum TestError: Error { case binaryMissing }

    struct Result { let exitCode: Int32; let stdout: String; let stderr: String }

    /// 把 payload 餵進 stdin，回傳 exit code 與輸出。
    func run(_ payload: String, root: URL) throws -> Result {
        let p = Process()
        p.executableURL = try Self.binaryURL()
        p.environment = ProcessInfo.processInfo.environment.merging(
            ["AGENTAURA_ROOT": root.path]) { _, new in new }
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
        try p.run()
        inPipe.fileHandleForWriting.write(Data(payload.utf8))
        try inPipe.fileHandleForWriting.close()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(exitCode: p.terminationStatus,
                      stdout: String(decoding: out, as: UTF8.self),
                      stderr: String(decoding: err, as: UTF8.self))
    }

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-cli-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // ---- 正常路徑 ----

    @Test("寫入狀態檔並 exit 0")
    func happyPath() throws {
        let root = try makeRoot()
        let r = try run(#"{"hook_event_name":"PermissionRequest","session_id":"cli1","cwd":"/tmp","tool_name":"Bash"}"#, root: root)
        #expect(r.exitCode == 0)
        let s = try #require(SnapshotIO.read(sessionID: "cli1", root: root))
        #expect(s.mainActivity == .waiting)
        #expect(s.mainTool == "Bash")
        #expect(s.schema == 1)
    }

    @Test("記錄 pid 與 pid_started_at，且該 pid 當下可驗證為活著")
    func recordsPIDAndStartTime() throws {
        let root = try makeRoot()
        _ = try run(#"{"hook_event_name":"PreToolUse","session_id":"cli2"}"#, root: root)
        let s = try #require(SnapshotIO.read(sessionID: "cli2", root: root))
        let pid = try #require(s.pid)
        let started = try #require(s.pidStartedAt)
        #expect(pid > 0)
        #expect(started > 1_600_000_000)
        // 父行程就是這個測試行程 —— 應仍活著
        #expect(SysctlLiveness().isAlive(pid: pid, startedAt: started))
    }

    @Test("subagent 事件寫進 sub 槽，不覆蓋主 agent 的 waiting")
    func subagentGoesToSubSlot() throws {
        let root = try makeRoot()
        _ = try run(#"{"hook_event_name":"PermissionRequest","session_id":"cli3","tool_name":"Bash"}"#, root: root)
        _ = try run(#"{"hook_event_name":"PostToolUse","session_id":"cli3","tool_name":"Write","agent_id":"a1","agent_type":"Explore"}"#, root: root)
        let s = try #require(SnapshotIO.read(sessionID: "cli3", root: root))
        #expect(s.mainActivity == .waiting, "端到端也必須保住 waiting")
        #expect(s.subActivity == .working)
        #expect(s.effectiveActivity == .waiting)
    }

    @Test("累積欄位跨多次呼叫保留")
    func accumulatesAcrossInvocations() throws {
        let root = try makeRoot()
        _ = try run(#"{"hook_event_name":"UserPromptSubmit","session_id":"cli4"}"#, root: root)
        for _ in 0..<3 {
            _ = try run(#"{"hook_event_name":"PostToolUseFailure","session_id":"cli4","tool_name":"Bash"}"#, root: root)
        }
        _ = try run(#"{"hook_event_name":"SubagentStart","session_id":"cli4","agent_id":"a1","agent_type":"Explore"}"#, root: root)
        let s = try #require(SnapshotIO.read(sessionID: "cli4", root: root))
        #expect(s.toolFailures == 3)
        #expect(s.subagents == ["Explore": 1])
        #expect(s.turnStartedAt != nil)
    }

    @Test("真實 fixture 全部餵進去都 exit 0 且產生狀態檔")
    func allRealPayloadsAccepted() throws {
        let root = try makeRoot()
        for json in try Fixtures.rawEvents(named: "round1") {
            let data = try Fixtures.jsonData(json)
            let r = try run(String(decoding: data, as: UTF8.self), root: root)
            #expect(r.exitCode == 0)
        }
        #expect(!SnapshotIO.allSessionIDs(root: root).isEmpty)
    }

    // ---- 靜默失敗（Global Constraint）----

    @Test("畸形輸入一律 exit 0 且無任何輸出", arguments: [
        "", "   ", "not json", "{", "}{", "null", "[]", "[1,2,3]", "\"str\"", "42",
        #"{"session_id":"x"}"#,                        // 缺 hook_event_name
        #"{"hook_event_name":"Stop"}"#,                 // 缺 session_id
        #"{"hook_event_name":"Stop","session_id":123}"#,// session_id 型別錯
    ])
    func malformedInputIsSilent(_ payload: String) throws {
        let r = try run(payload, root: try makeRoot())
        #expect(r.exitCode == 0, "觀測性絕不可干擾 agent")
        #expect(r.stdout.isEmpty, "不得有任何 stdout")
        #expect(r.stderr.isEmpty, "不得有任何 stderr")
    }

    @Test("session_id 含 path traversal 時不寫任何檔案且 exit 0")
    func pathTraversalRejected() throws {
        let root = try makeRoot()
        let outside = root.deletingLastPathComponent().appendingPathComponent("escaped.json")
        let r = try run(#"{"hook_event_name":"Stop","session_id":"../escaped"}"#, root: root)
        #expect(r.exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: outside.path), "不得寫到目錄外")
        #expect(SnapshotIO.allSessionIDs(root: root).isEmpty)
    }

    @Test("目錄唯讀時仍 exit 0（磁碟滿 / 權限問題的代理情境）")
    func readOnlyRootIsSilent() throws {
        let root = try makeRoot()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let r = try run(#"{"hook_event_name":"Stop","session_id":"ro1"}"#, root: root)
        #expect(r.exitCode == 0)
        #expect(r.stderr.isEmpty)
    }

    @Test("超大 payload（1MB last_assistant_message）不 crash 且 exit 0")
    func hugePayload() throws {
        let big = String(repeating: "長訊息內容 ", count: 100_000)
        let json = try String(decoding: JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Stop", "session_id": "big1", "last_assistant_message": big,
        ]), as: UTF8.self)
        let r = try run(json, root: try makeRoot())
        #expect(r.exitCode == 0)
    }

    // ---- 效能（DoD：p95 < 5ms）----

    @Test("單次呼叫的 wall-clock 中位數 < 50ms（含 process spawn）")
    func latency() throws {
        let root = try makeRoot()
        var times: [Double] = []
        for i in 0..<20 {
            let t = Date()
            _ = try run(#"{"hook_event_name":"PreToolUse","session_id":"perf\#(i % 3)","tool_name":"Bash"}"#, root: root)
            times.append(Date().timeIntervalSince(t) * 1000)
        }
        let median = times.sorted()[times.count / 2]
        #expect(median < 50, "中位數 \(median)ms —— 含 spawn 的寬鬆門檻；精確 p95 用 hyperfine 量（Task 13）")
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift build 2>&1 | tail -5`
Expected: FAIL — `Sources/aura-hook` 沒有 `main.swift`

- [ ] **Step 3: 實作**

```swift
// Sources/aura-hook/main.swift
import Foundation
import AuraCore
import AuraHookFile

/// 被 Claude Code hook 呼叫。stdin 收 hook JSON，併進 `~/.agentaura/sessions/<id>.json`。
///
/// **任何失敗都必須靜默 exit 0**（Global Constraint）：這是觀測性程式，
/// 絕不可讓錯誤浮上 agent 的畫面或影響其行為。
/// 實證教訓（user CLAUDE.md #8）：收尾/觀測動作炸掉會殺掉同輪的保本工作。

func rootURL() -> URL {
    if let override = ProcessInfo.processInfo.environment["AGENTAURA_ROOT"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    return SnapshotIO.defaultRoot
}

func main() {
    // 1. 讀 stdin。讀不到就安靜結束。
    guard let data = try? FileHandle.standardInput.readToEnd(), !data.isEmpty else { return }

    // 2. 解析。畸形就安靜結束。
    guard let payload = HookPayload(data: data) else { return }

    // 3. 取父行程資訊 —— 父行程即呼叫此 hook 的 claude 本體。
    //    若 Task 01 的 mechanisms.md 判定父行程是 shell 而非 claude，
    //    改為不寫 pid，改由 HookFileSource 走心跳 TTL 判活。
    let ppid = getppid()
    let started = SysctlLiveness().startTime(ofPID: ppid)

    // 4. merge-write。任何 IO 錯誤都吞掉。
    try? SnapshotIO.update(sessionID: payload.sessionID, root: rootURL()) { existing in
        MergeRules.merge(payload, into: existing,
                         pid: ppid, pidStartedAt: started, now: Date())
    }
}

main()
// 隱含 exit 0：沒有任何 exit(非零) 路徑，也不輸出 stdout / stderr。
```

- [ ] **Step 4: 建置並執行測試**

```bash
swift build 2>&1 | tail -5
swift test --filter AuraHookCLITests 2>&1 | tail -15
```
Expected: build 成功；全部 PASS（10 個測試，含 13 個畸形輸入的參數化案例）

- [ ] **Step 5: 手動確認靜默性**

```bash
echo 'garbage' | ./.build/debug/aura-hook; echo "exit=$?"
```
Expected: `exit=0`，且**畫面上不得出現任何其他文字**

- [ ] **Step 6: Mutation 驗證 —— 靜默失敗是否真的被測到**

手動把 `guard let payload = HookPayload(data: data) else { return }` 改成
`else { FileHandle.standardError.write(Data("bad payload\n".utf8)); exit(1) }`，
執行 `swift build && swift test --filter AuraHookCLITests`。

Expected: `malformedInputIsSilent` **必須 FAIL**（exit code 與 stderr 兩項都會紅）。還原後全綠。

- [ ] **Step 7: Commit**

```bash
git add Sources/aura-hook/main.swift Tests/AuraCoreTests/AuraHookCLITests.swift
git commit -m "feat(hook): aura-hook CLI，任何錯誤靜默 exit 0

觀測性絕不可干擾 agent（user CLAUDE.md Lessons Learned #8）。
畸形輸入、path traversal、目錄唯讀皆有黑箱測試覆蓋。"
```

---

### Task 12: HookFileSource —— FSEvents 監看與 bootstrap

**Files:**
- Create: `Sources/AuraCore/EventSource.swift`
- Create: `Sources/AuraHookFile/HookFileSource.swift`
- Test: `Tests/AuraCoreTests/HookFileSourceTests.swift`

**Interfaces:**
- Consumes: `SnapshotIO`、`SessionSnapshot`
- Produces:
  ```swift
  public protocol EventSource: Sendable {
      /// app 啟動時掃目錄，還原現況
      func bootstrap() -> [SessionSnapshot]
      /// 目錄有變動時吐出受影響的 snapshot
      var snapshots: AsyncStream<SessionSnapshot> { get }
      func start()
      func stop()
  }
  public final class HookFileSource: EventSource {
      public init(root: URL = SnapshotIO.defaultRoot, latency: TimeInterval = 0.1)
  }
  ```

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/AuraCoreTests/HookFileSourceTests.swift
import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

@Suite("HookFileSource FSEvents 監看", .serialized)
struct HookFileSourceTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-fse-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ id: String, _ a: Activity, to root: URL) throws {
        try SnapshotIO.update(sessionID: id, root: root) { old in
            var s = old ?? SessionSnapshot(sessionID: id)
            s.mainActivity = a
            s.hookEventName = "PreToolUse"
            s.writtenAt = Date()
            return s
        }
    }

    /// 從 AsyncStream 收集事件，直到滿足條件或逾時。
    func collect(_ source: HookFileSource, until predicate: @escaping ([SessionSnapshot]) -> Bool,
                 timeout: TimeInterval = 5) async -> [SessionSnapshot] {
        var got: [SessionSnapshot] = []
        let deadline = Date().addingTimeInterval(timeout)
        for await snap in source.snapshots {
            got.append(snap)
            if predicate(got) || Date() > deadline { break }
        }
        return got
    }

    // ---- bootstrap ----

    @Test("bootstrap 掃出目錄裡既有的全部 session")
    func bootstrapReadsExisting() throws {
        let root = try makeRoot()
        try write("b1", .waiting, to: root)
        try write("b2", .working, to: root)
        try write("b3", .error,   to: root)

        let source = HookFileSource(root: root)
        let got = source.bootstrap()
        #expect(Set(got.map(\.sessionID)) == ["b1", "b2", "b3"],
                "app 沒開時累積的事件，啟動即還原（spec §1 失效模式 2）")
        #expect(got.first { $0.sessionID == "b1" }?.mainActivity == .waiting)
    }

    @Test("bootstrap 對空目錄回空陣列，不丟錯")
    func bootstrapEmpty() throws {
        #expect(HookFileSource(root: try makeRoot()).bootstrap().isEmpty)
    }

    @Test("bootstrap 對不存在的目錄回空陣列，不丟錯")
    func bootstrapMissingDirectory() {
        let root = URL(fileURLWithPath: "/tmp/aura-definitely-missing-\(UUID().uuidString)")
        #expect(HookFileSource(root: root).bootstrap().isEmpty)
    }

    @Test("bootstrap 跳過畸形檔案但保留其餘（部分損壞不得拖垮全部）")
    func bootstrapSkipsCorrupt() throws {
        let root = try makeRoot()
        try write("good1", .waiting, to: root)
        try write("good2", .working, to: root)
        try Data("{ truncated".utf8).write(to: root.appendingPathComponent("bad.json"))

        let got = HookFileSource(root: root).bootstrap()
        #expect(Set(got.map(\.sessionID)) == ["good1", "good2"])
    }

    // ---- 即時監看 ----

    @Test("新檔案出現時吐出 snapshot")
    func detectsNewFile() async throws {
        let root = try makeRoot()
        let source = HookFileSource(root: root)
        source.start()
        defer { source.stop() }

        Task { try? self.write("live1", .waiting, to: root) }
        let got = await collect(source) { $0.contains { $0.sessionID == "live1" } }
        #expect(got.contains { $0.sessionID == "live1" && $0.mainActivity == .waiting })
    }

    @Test("既有檔案被覆寫時吐出新 snapshot")
    func detectsModification() async throws {
        let root = try makeRoot()
        try write("live2", .working, to: root)
        let source = HookFileSource(root: root)
        source.start()
        defer { source.stop() }

        Task { try? self.write("live2", .error, to: root) }
        let got = await collect(source) { $0.contains { $0.mainActivity == .error } }
        #expect(got.contains { $0.sessionID == "live2" && $0.mainActivity == .error })
    }

    @Test("多個 session 併發寫入全部都收到")
    func detectsManySessions() async throws {
        let root = try makeRoot()
        let source = HookFileSource(root: root)
        source.start()
        defer { source.stop() }

        Task {
            for i in 0..<10 { try? self.write("many\(i)", .working, to: root) }
        }
        let got = await collect(source, until: { Set($0.map(\.sessionID)).count >= 10 }, timeout: 10)
        #expect(Set(got.map(\.sessionID)).count >= 10)
    }

    @Test("stop 之後不再吐事件")
    func stopEndsStream() async throws {
        let root = try makeRoot()
        let source = HookFileSource(root: root)
        source.start()
        source.stop()
        try write("after-stop", .working, to: root)

        // stream 應已結束；收集 1 秒內不得拿到 after-stop
        var got: [SessionSnapshot] = []
        let task = Task { for await s in source.snapshots { got.append(s) } }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        task.cancel()
        #expect(!got.contains { $0.sessionID == "after-stop" })
    }

    @Test("重複 start / stop 不 crash")
    func repeatedStartStop() throws {
        let source = HookFileSource(root: try makeRoot())
        source.start(); source.start()
        source.stop();  source.stop()
    }

    @Test("root 不存在時 start 會自動建立目錄")
    func startCreatesRoot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-fse-\(UUID().uuidString)/deep/sessions")
        let source = HookFileSource(root: root)
        source.start()
        defer { source.stop() }
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter HookFileSourceTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'HookFileSource' in scope`

- [ ] **Step 3: 實作 EventSource protocol**

```swift
// Sources/AuraCore/EventSource.swift
import Foundation

/// 狀態來源的抽象。
///
/// 目前唯一實作是 `HookFileSource`（方案 1）。方案 3（zero-config 觀測
/// `~/.claude/projects/**/*.jsonl`）未來接在這個縫上，不需改動核心邏輯。
public protocol EventSource: AnyObject, Sendable {
    /// app 啟動時掃出現況。靜止態（waiting/done/error）天生就在檔案裡。
    func bootstrap() -> [SessionSnapshot]
    /// 來源有變動時吐出受影響的 snapshot。
    var snapshots: AsyncStream<SessionSnapshot> { get }
    func start()
    func stop()
}
```

- [ ] **Step 4: 實作 HookFileSource**

```swift
// Sources/AuraHookFile/HookFileSource.swift
import Foundation
import AuraCore

/// 用 FSEvents 監看 `~/.agentaura/sessions`，把變動的檔案讀成 `SessionSnapshot`。
public final class HookFileSource: EventSource, @unchecked Sendable {

    private let root: URL
    private let latency: TimeInterval
    private let queue = DispatchQueue(label: "io.agentaura.fsevents")
    private var stream: FSEventStreamRef?
    private var continuation: AsyncStream<SessionSnapshot>.Continuation?
    private let lock = NSLock()

    public let snapshots: AsyncStream<SessionSnapshot>

    public init(root: URL = SnapshotIO.defaultRoot, latency: TimeInterval = 0.1) {
        self.root = root
        self.latency = latency
        var cont: AsyncStream<SessionSnapshot>.Continuation!
        self.snapshots = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    deinit { stop() }

    public func bootstrap() -> [SessionSnapshot] {
        SnapshotIO.allSessionIDs(root: root)
            .compactMap { SnapshotIO.read(sessionID: $0, root: root) }
    }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard stream == nil else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let source = Unmanaged<HookFileSource>.fromOpaque(info).takeUnretainedValue()
            // kFSEventStreamCreateFlagFileEvents 下 eventPaths 是 C 字串陣列。
            let paths = unsafeBitCast(eventPaths, to: UnsafePointer<UnsafePointer<CChar>>.self)
            var changed: Set<String> = []
            for i in 0..<count {
                let name = (String(cString: paths[i]) as NSString).lastPathComponent
                guard name.hasSuffix(".json") else { continue }
                changed.insert(String(name.dropLast(5)))
            }
            source.emit(sessionIDs: changed)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

        guard let s = FSEventStreamCreate(
            nil, callback, &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, flags)
        else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        continuation?.finish()
        continuation = nil
    }

    /// 讀不到（半截 JSON、剛被刪）就跳過 —— 呼叫端保留上次已知狀態。
    private func emit(sessionIDs: Set<String>) {
        for id in sessionIDs {
            guard SnapshotIO.isSafeSessionID(id),
                  let snap = SnapshotIO.read(sessionID: id, root: root) else { continue }
            continuation?.yield(snap)
        }
    }
}
```

> **實作備註：** 若 Swift 6 的嚴格併發檢查對 `callback` 捕獲 `Unmanaged` 有意見，
> 把 `callback` 移到檔案層級的 `private let`（而非 `start()` 內的區域變數）即可。
> 測試意圖不變。

- [ ] **Step 5: 執行確認通過**

Run: `swift test --filter HookFileSourceTests 2>&1 | tail -12`
Expected: 全部 PASS（10 個測試）

- [ ] **Step 6: Mutation 驗證**

手動把 `bootstrap()` 改成 `return []`，執行 `swift test --filter HookFileSourceTests`。

Expected: `bootstrapReadsExisting` 與 `bootstrapSkipsCorrupt` **必須 FAIL**。還原後全綠。

- [ ] **Step 7: Commit**

```bash
git add Sources/AuraCore/EventSource.swift Sources/AuraHookFile/HookFileSource.swift \
        Tests/AuraCoreTests/HookFileSourceTests.swift
git commit -m "feat(io): HookFileSource 以 FSEvents 監看狀態目錄，bootstrap 還原現況"
```

---

### Task 13: Claude Code plugin + composition root + 端到端 wired-gate

**這是整個計畫最重要的一個 task。** tested ≠ wired：前面 12 個 task 全綠，只證明「能用」，
不證明「有用」。plugin 的 command 路徑一錯，整個產品靜默失效而所有單元測試照樣全綠 ——
這正是 前一個專案 留下 7 個死 hook 的失效方式。

**Files:**
- Create: `plugin/.claude-plugin/plugin.json`
- Create: `plugin/hooks/hooks.json`
- Create: `Sources/AuraHookFile/PipelineGraph.swift`（composition root，無 UI）
- Test: `Tests/AuraCoreTests/CompositionRootTests.swift`
- Test: `Tests/AuraCoreTests/EndToEndWiredGateTests.swift`

**Interfaces:**
- Consumes: 全部前述元件
- Produces:
  ```swift
  public final class PipelineGraph: @unchecked Sendable {
      public init(root: URL, liveness: LivenessProbing, policy: AggregatePolicy, source: EventSource)
      public static func production(root: URL = SnapshotIO.defaultRoot) -> PipelineGraph
      public private(set) var registry: SessionRegistry
      public var iconState: IconState { get }
      public var onIconStateChange: ((IconState) -> Void)?
      public func start()          // bootstrap + 開始消費 snapshots
      public func stop()
      public func acknowledgeAll() // 刪除已結束且已確認的狀態檔
      public func refreshLiveness()
  }
  ```

- [ ] **Step 1: 建立 plugin manifest 與 hooks 註冊**

```bash
mkdir -p plugin/.claude-plugin plugin/hooks
cat > plugin/.claude-plugin/plugin.json <<'EOF'
{
  "name": "agentaura",
  "version": "0.1.0",
  "description": "把 Claude Code 的運行狀態顯示在 macOS menu bar",
  "author": "AgentAura"
}
EOF
```

`hooks.json` —— **全部 `async: true`**（Global Constraint）。
`Notification` 加 matcher 只收需要使用者的 6 種型別作為縱深防禦，
但 payload 內的型別檢查（`EventMapping.notificationEffect`）才是正確性保證。

```bash
cat > plugin/hooks/hooks.json <<'EOF'
{
  "SessionStart":       [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "UserPromptSubmit":   [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "PreToolUse":         [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "PostToolUse":        [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "PostToolUseFailure": [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "PostToolBatch":      [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "PermissionRequest":  [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "PermissionDenied":   [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "SubagentStart":      [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "SubagentStop":       [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "Stop":               [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "StopFailure":        [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "SessionEnd":         [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "PostModelSwitch":    [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "Elicitation":        [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "ElicitationResult":  [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "PreCompact":         [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "PostCompact":        [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }],
  "Notification": [
    { "matcher": "permission_prompt|idle_prompt|agent_needs_input|elicitation_dialog|elicitation_url_dialog|agent_completed",
      "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "async": true }] }
  ]
}
EOF
```

- [ ] **Step 2: 寫 plugin 設定的 wired-gate 測試（先寫、必失敗）**

這組測試把 `hooks.json` 當**生產設定**驗，不是當文件看。

```swift
// Tests/AuraCoreTests/CompositionRootTests.swift
import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

@Suite("Plugin 設定 wired-gate")
struct PluginWiringTests {

    static func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        fatalError("找不到 Package.swift")
    }

    static func hooksJSON() throws -> [String: Any] {
        let url = repoRoot().appendingPathComponent("plugin/hooks/hooks.json")
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// 攤平出 hooks.json 裡的每一個 hook entry。
    static func entries() throws -> [(event: String, entry: [String: Any])] {
        var out: [(String, [String: Any])] = []
        for (event, value) in try hooksJSON() {
            for matcher in (value as? [[String: Any]]) ?? [] {
                for h in (matcher["hooks"] as? [[String: Any]]) ?? [] { out.append((event, h)) }
            }
        }
        return out
    }

    @Test("plugin.json 是合法 JSON 且有 name")
    func manifestValid() throws {
        let url = Self.repoRoot().appendingPathComponent("plugin/.claude-plugin/plugin.json")
        let obj = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        #expect(obj?["name"] as? String == "agentaura")
    }

    @Test("每一個 hook 都是 async: true —— 絕不可拖慢 agent")
    func allHooksAreAsync() throws {
        let all = try Self.entries()
        #expect(!all.isEmpty)
        for (event, h) in all {
            #expect(h["async"] as? Bool == true, "\(event) 的 hook 缺少 async: true")
        }
    }

    @Test("每一個 hook 的 command 都指向同一個 aura-hook 相對路徑")
    func allHooksPointAtAuraHook() throws {
        for (event, h) in try Self.entries() {
            let cmd = try #require(h["command"] as? String)
            #expect(cmd == "${CLAUDE_PLUGIN_ROOT}/bin/aura-hook", "\(event) 的 command 不一致：\(cmd)")
        }
    }

    /// **source-derived 跨層一致性 gate。**
    ///
    /// 來源集合從 `EventMapping.handledEvents`（生產碼）推導，不是手維護的第二份清單。
    /// user CLAUDE.md Lessons Learned #9：hand-maintained 清單自己會 drift ——
    /// 本專案已實際發生過：`Elicitation` 映射到 `waiting` 卻沒註冊，那個「MCP server
    /// 在等你輸入」的狀態永遠收不到，而單元測試照樣全綠。
    ///
    /// 斷言是**雙向等式**，兩個方向都有代價：
    /// - 有映射沒註冊 → 對照表是死碼，該狀態永遠收不到（tested≠wired）
    /// - 有註冊沒映射 → 每個事件白付一次 hook 呼叫，卻不影響任何狀態
    @Test("hooks.json 註冊的 event 集合必須等於 EventMapping.handledEvents")
    func registeredEventsMatchHandledEvents() throws {
        let registered = Set(try Self.hooksJSON().keys)
        let handled = EventMapping.handledEvents

        let mappedNotRegistered = handled.subtracting(registered)
        let registeredNotMapped = registered.subtracting(handled)

        #expect(mappedNotRegistered.isEmpty,
                "有映射卻沒註冊（對照表是死碼）：\(mappedNotRegistered.sorted())")
        #expect(registeredNotMapped.isEmpty,
                "有註冊卻沒映射（白付 hook 呼叫）：\(registeredNotMapped.sorted())")
    }

    /// source-derived 雙向等式，與 `registeredEventsMatchHandledEvents` 同一個理由。
    ///
    /// - matcher 少收 → 該型別的 `Notification` 永遠不會抵達，對照表是死碼
    /// - matcher 多收 → 收了卻被當雜訊，白付 hook 呼叫
    @Test("Notification matcher 必須等於 EventMapping.notificationMatcherTypes")
    func notificationMatcherMatchesMapping() throws {
        let notif = try #require(try Self.hooksJSON()["Notification"] as? [[String: Any]])
        let matcher = try #require(notif.first?["matcher"] as? String)
        let inMatcher = Set(matcher.split(separator: "|").map(String.init))
        let expected = EventMapping.notificationMatcherTypes

        #expect(expected.subtracting(inMatcher).isEmpty,
                "matcher 漏收（對照表是死碼）：\(expected.subtracting(inMatcher).sorted())")
        #expect(inMatcher.subtracting(expected).isEmpty,
                "matcher 多收（白付 hook 呼叫）：\(inMatcher.subtracting(expected).sorted())")

        // 再確認 matcher 收的每一個型別實際上真的會改變狀態
        for t in inMatcher {
            #expect(EventMapping.effect(forEvent: "Notification", notificationType: t) != .noChange,
                    "matcher 收了 \(t) 但對照表把它當雜訊")
        }
    }

    @Test("aura-hook 二進位存在且可執行（安裝腳本的驗收條件）")
    func auraHookBinaryExists() throws {
        let root = Self.repoRoot()
        let candidates = ["\(".build/debug")/aura-hook", "\(".build/release")/aura-hook"]
            .map { root.appendingPathComponent($0) }
        #expect(candidates.contains { FileManager.default.isExecutableFile(atPath: $0.path) },
                "先跑 swift build。安裝腳本必須把此二進位放到 plugin/bin/aura-hook")
    }
}
```

- [ ] **Step 3: 執行確認失敗**

Run: `swift test --filter PluginWiringTests 2>&1 | tail -10`
Expected: 若 Step 1 已建檔則多數 PASS；`auraHookBinaryExists` 需先 `swift build`。
**刻意先跑一次確認 `coversAllMappedEvents` 與 `matcherTypesAreAllHandled` 真的會抓錯** ——
暫時從 `hooks.json` 刪掉 `PermissionRequest` 那行，跑測試看到 FAIL，再加回來。

- [ ] **Step 4: 寫 composition root 測試**

```swift
// 附加到 Tests/AuraCoreTests/CompositionRootTests.swift
@Suite("PipelineGraph composition root", .serialized)
struct CompositionRootTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-graph-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("production() 的每個依賴都真的接上，沒有 nil")
    func productionGraphIsWired() {
        let g = PipelineGraph.production(root: try! makeRoot())
        #expect(g.source is HookFileSource, "production 必須用真的檔案來源")
        #expect(g.liveness is SysctlLiveness, "production 必須用真的 pid 探測，不是 stub")
        #expect(g.policy is PriorityAggregatePolicy)
    }

    @Test("start() 會消耗 bootstrap 的結果並更新 iconState")
    func startConsumesBootstrap() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "boot1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "boot1")
            s.mainActivity = .error; s.terminated = true; s.writtenAt = Date()
            return s
        }
        let g = PipelineGraph.production(root: root)
        g.start()
        defer { g.stop() }
        #expect(g.iconState.activity == .error,
                "app 沒開時累積的未確認 error，啟動後必須立刻反映在 icon 上")
    }

    @Test("onIconStateChange callback 真的被呼叫（spy 斷言，不接受被 catch-all 吞掉）")
    func callbackIsInvoked() throws {
        let root = try makeRoot()
        let g = PipelineGraph.production(root: root)
        var received: [IconState] = []
        g.onIconStateChange = { received.append($0) }

        try SnapshotIO.update(sessionID: "cb1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "cb1"); s.mainActivity = .waiting
            s.pid = getpid(); s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
            s.writtenAt = Date(); return s
        }
        g.start()
        defer { g.stop() }
        #expect(!received.isEmpty, "start() 必須觸發至少一次 icon 更新")
        #expect(received.last?.activity == .waiting)
    }

    @Test("acknowledgeAll 會刪除已結束且已確認的狀態檔")
    func acknowledgeDeletesFiles() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "ack1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "ack1")
            s.mainActivity = .done; s.terminated = true; s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        #expect(g.iconState.activity == .done)

        g.acknowledgeAll()
        #expect(g.iconState.activity == .idle, "確認後尾巴清空，燈回正常")
        #expect(SnapshotIO.allSessionIDs(root: root).isEmpty, "已結束且已確認 → 檔案刪除")
    }

    @Test("refreshLiveness 會把 pid 已死的 working session 移出")
    func refreshLivenessDropsDeadSessions() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "dead1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "dead1")
            s.mainActivity = .working
            s.pid = 999_999; s.pidStartedAt = 12_345      // 不存在的 pid
            s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        g.refreshLiveness()
        #expect(g.iconState.activity == .idle,
                "terminal 被強制關掉、SessionEnd 沒來 → 不得永遠卡 working")
    }
}
```

- [ ] **Step 5: 實作 PipelineGraph**

```swift
// Sources/AuraHookFile/PipelineGraph.swift
import Foundation
import AuraCore

/// Composition root（無 UI 部分）。
///
/// **唯一的組裝點。** 每個依賴都必須在此接上，並由 CompositionRootTests 用
/// spy 斷言真的被呼叫 —— 單元測試證明「能用」，這裡證明「有用」。
public final class PipelineGraph: @unchecked Sendable {

    public let liveness: LivenessProbing
    public let policy: AggregatePolicy
    public let source: EventSource
    public let root: URL

    public private(set) var registry = SessionRegistry()
    public var onIconStateChange: ((IconState) -> Void)?

    private var consumeTask: Task<Void, Never>?
    private let lock = NSLock()

    public init(root: URL, liveness: LivenessProbing, policy: AggregatePolicy, source: EventSource) {
        self.root = root; self.liveness = liveness; self.policy = policy; self.source = source
    }

    public var iconState: IconState {
        lock.lock(); defer { lock.unlock() }
        return policy.aggregate(registry.visible)
    }

    public func start() {
        source.start()
        for snap in source.bootstrap() { ingest(snap) }
        notifyChange()
        consumeTask = Task { [weak self] in
            guard let self else { return }
            for await snap in self.source.snapshots {
                self.ingest(snap)
                self.notifyChange()
            }
        }
    }

    public func stop() {
        consumeTask?.cancel(); consumeTask = nil
        source.stop()
    }

    /// 面板開啟：確認全部，並刪除已結束且已確認的狀態檔。
    public func acknowledgeAll() {
        lock.lock()
        let removable = registry.acknowledgeAll()
        lock.unlock()
        for id in removable {
            // 刪檔失敗不可影響其他工作（user CLAUDE.md #8：收尾動作各自 try/except）
            try? SnapshotIO.delete(sessionID: id, root: root)
        }
        notifyChange()
    }

    /// 重新驗證所有 session 的 pid —— 抓「terminal 被強制關掉，SessionEnd 沒來」。
    public func refreshLiveness() {
        lock.lock()
        let ids = Array(registry.states.keys)
        lock.unlock()
        for id in ids {
            guard let snap = SnapshotIO.read(sessionID: id, root: root) else { continue }
            ingest(snap)
        }
        notifyChange()
    }

    private func ingest(_ snap: SessionSnapshot) {
        let state = SessionReducer.state(from: snap, liveness: liveness)
        lock.lock(); registry.upsert(state); lock.unlock()
    }

    private func notifyChange() { onIconStateChange?(iconState) }

    /// production 組裝：每個依賴都是真的實作，沒有測試替身。
    public static func production(root: URL = SnapshotIO.defaultRoot) -> PipelineGraph {
        PipelineGraph(root: root,
                      liveness: SysctlLiveness(),
                      policy: PriorityAggregatePolicy(),
                      source: HookFileSource(root: root))
    }
}
```

> **層次說明：** `PipelineGraph` 放在 `AuraHookFile`（而非 `AuraCore`），因為它需要
> `SnapshotIO`。放進 `AuraCore` 會造成 core → IO 的反向依賴。`AuraCore` 維持
> 「純邏輯、零 IO、零 AppKit」。

- [ ] **Step 6: 執行測試**

Run: `swift build && swift test --filter CompositionRootTests 2>&1 | tail -12`
Expected: 全部 PASS（5 個測試）

- [ ] **Step 7: 寫端到端 wired-gate（不 mock 任何一層）**

```swift
// Tests/AuraCoreTests/EndToEndWiredGateTests.swift
import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

/// 用**真的** aura-hook 二進位 + 真的檔案 + 真的 FSEvents + 真的 pid 探測。
/// 任何一層 mock 都會讓這組測試失去意義。
@Suite("端到端 wired-gate", .serialized)
struct EndToEndWiredGateTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-e2e-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 真的 spawn aura-hook。
    func fireHook(_ payload: String, root: URL) throws {
        let p = Process()
        p.executableURL = try AuraHookCLITests.binaryURL()
        p.environment = ProcessInfo.processInfo.environment.merging(
            ["AGENTAURA_ROOT": root.path]) { _, new in new }
        let pipe = Pipe()
        p.standardInput = pipe
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        pipe.fileHandleForWriting.write(Data(payload.utf8))
        try pipe.fileHandleForWriting.close()
        p.waitUntilExit()
    }

    /// 等到 iconState 滿足條件或逾時。
    func wait(for graph: PipelineGraph, until predicate: @escaping (IconState) -> Bool,
              timeout: TimeInterval = 5) async -> IconState {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(graph.iconState) { return graph.iconState }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return graph.iconState
    }

    @Test("hook 觸發 → 檔案 → FSEvents → IconState 變成 waiting")
    func hookToIconState() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }
        #expect(graph.iconState.activity == .idle)

        try fireHook(#"{"hook_event_name":"PermissionRequest","session_id":"e2e1","cwd":"/tmp/proj","tool_name":"Bash"}"#, root: root)

        let final = await wait(for: graph) { $0.activity == .waiting }
        #expect(final.activity == .waiting, "整條鏈路必須真的接通")
        #expect(final.attentionCount == 1)
    }

    @Test("三個 session：2 working + 1 error → icon 為 error（D1 端到端）")
    func aggregationEndToEnd() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }

        try fireHook(#"{"hook_event_name":"PreToolUse","session_id":"w1","tool_name":"Bash"}"#, root: root)
        try fireHook(#"{"hook_event_name":"PreToolUse","session_id":"w2","tool_name":"Read"}"#, root: root)
        try fireHook(#"{"hook_event_name":"StopFailure","session_id":"e1","reason":"overloaded_error"}"#, root: root)

        let final = await wait(for: graph) { $0.activity == .error && $0.counts.values.reduce(0,+) >= 3 }
        #expect(final.activity == .error, "使用者原始舉例，端到端驗證")
        #expect(final.counts[.working] == 2)
        #expect(final.counts[.error] == 1)
    }

    @Test("subagent 在 20ms 內插入事件，waiting 端到端不被抹除（critical bug 的最終防線）")
    func subagentDoesNotMaskWaitingEndToEnd() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }

        try fireHook(#"{"hook_event_name":"PermissionRequest","session_id":"mask1","tool_name":"Bash"}"#, root: root)
        _ = await wait(for: graph) { $0.activity == .waiting }

        // 模擬實測時序：主 agent 被擋住時 subagent 連發事件
        for _ in 0..<8 {
            try fireHook(#"{"hook_event_name":"PostToolUse","session_id":"mask1","tool_name":"Write","agent_id":"sub1","agent_type":"implementer"}"#, root: root)
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(graph.iconState.activity == .waiting,
                "8 個 subagent 事件之後，橘燈仍必須亮著")
    }

    @Test("SessionEnd 之後未確認的 done 仍計入，acknowledgeAll 後才消失")
    func unackedTailEndToEnd() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }

        try fireHook(#"{"hook_event_name":"Stop","session_id":"tail1","last_assistant_message":"全部完成"}"#, root: root)
        try fireHook(#"{"hook_event_name":"SessionEnd","session_id":"tail1","reason":"exit"}"#, root: root)

        let afterEnd = await wait(for: graph) { $0.activity == .done }
        #expect(afterEnd.activity == .done, "整夜 pipeline 跑完、terminal 收掉，早上仍看得到綠燈")

        graph.acknowledgeAll()
        #expect(graph.iconState.activity == .idle)
        #expect(SnapshotIO.allSessionIDs(root: root).isEmpty)
    }

    @Test("50 個 session 併發 hook 全部進到 IconState")
    func fiftyConcurrentSessions() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }

        DispatchQueue.concurrentPerform(iterations: 50) { i in
            try? self.fireHook(
                #"{"hook_event_name":"PreToolUse","session_id":"c\#(i)","tool_name":"Bash"}"#, root: root)
        }
        let final = await wait(for: graph, until: { $0.counts.values.reduce(0,+) >= 50 }, timeout: 20)
        #expect(final.counts.values.reduce(0, +) >= 50)
    }
}
```

- [ ] **Step 8: 執行端到端測試**

Run: `swift build && swift test --filter EndToEndWiredGateTests 2>&1 | tail -12`
Expected: 全部 PASS（5 個測試）

- [ ] **Step 9: Mutation 驗證 —— wired-gate 是否真的有牙齒**

```bash
# 把 plugin 的 command 路徑改成不存在的檔案
sed -i.bak 's|/bin/aura-hook|/bin/aura-hook-typo|g' plugin/hooks/hooks.json
swift test --filter PluginWiringTests 2>&1 | tail -5    # allHooksPointAtAuraHook 必須 FAIL
mv plugin/hooks/hooks.json.bak plugin/hooks/hooks.json

# 把某個 hook 的 async 拿掉
sed -i.bak '0,/"async": true/s//"async": false/' plugin/hooks/hooks.json
swift test --filter PluginWiringTests 2>&1 | tail -5    # allHooksAreAsync 必須 FAIL
mv plugin/hooks/hooks.json.bak plugin/hooks/hooks.json

swift test 2>&1 | tail -5                                # 還原後全綠
```

另外手動驗一次：把 `PipelineGraph.production` 的 `liveness:` 改成 `StubLiveness(table: [:])`，
`productionGraphIsWired` 必須 FAIL —— 這條擋的是「production 用了測試替身」這類接線錯誤。

- [ ] **Step 10: 量測 DoD**

```bash
# hook 延遲 p95（需要 hyperfine：brew install hyperfine）
export AGENTAURA_ROOT=$(mktemp -d)/sessions
echo '{"hook_event_name":"PreToolUse","session_id":"bench","tool_name":"Bash"}' > /tmp/aura-bench.json
hyperfine --warmup 20 --min-runs 200 './.build/release/aura-hook < /tmp/aura-bench.json'

# 覆蓋率
swift test --enable-code-coverage 2>&1 | tail -3
xcrun llvm-cov report \
  .build/debug/AgentAuraPackageTests.xctest/Contents/MacOS/AgentAuraPackageTests \
  -instr-profile .build/debug/codecov/default.profdata \
  -ignore-filename-regex='(Tests|\.build)/' 2>/dev/null | tail -20

# 行數上限
find Sources -name '*.swift' -exec wc -l {} + | sort -rn | head -10
```

把結果填進 `docs/superpowers/plans/2026-09-08-agentaura-pipeline-dod.md`：

| 項目 | 門檻 | 實測 |
|---|---|---|
| hook 延遲 p95 | < 5ms | |
| 端到端反應 p95 | < 250ms | |
| `AuraCore` 覆蓋率 | ≥ 90% | |
| 單檔行數 | ≤ 200 | |
| agent 減速 | 0 ms（async） | |

未達標者不得進 M4，須先補足或在 spec 記為 known gap 並說明理由。

- [ ] **Step 11: Commit**

```bash
git add plugin Sources/AuraHookFile/PipelineGraph.swift \
        Tests/AuraCoreTests/CompositionRootTests.swift \
        Tests/AuraCoreTests/EndToEndWiredGateTests.swift \
        docs/superpowers/plans/2026-09-08-agentaura-pipeline-dod.md
git commit -m "feat(plugin): Claude Code plugin + composition root + 端到端 wired-gate

plugin 設定當生產設定驗：全部 async、command 路徑一致、涵蓋 EventMapping
的每個 event、Notification matcher 與對照表兩邊契約一致。

端到端 wired-gate 用真的 aura-hook 二進位 + 真檔案 + 真 FSEvents + 真 pid
探測，不 mock 任何一層。含 subagent 20ms 插隊不抹除 waiting 的最終防線。"
```

---

### Task 14: 安裝腳本 + 實機驗證

Task 13 的 `hooks.json` 指向 `${CLAUDE_PLUGIN_ROOT}/bin/aura-hook`，但**沒有任何東西
把二進位放到那裡** —— 這是 self-review 抓到的真實缺口。本 task 補上安裝腳本，
並在**真的 Claude Code** 裡跑一輪，證明整條鏈路在實機上通。

前 13 個 task 全綠只證明「在測試環境能用」。這個 task 證明「在真的 Claude Code 裡有用」。

**Files:**
- Create: `scripts/build-plugin.sh`
- Create: `scripts/verify-install.sh`
- Create: `docs/INSTALL.md`
- Test: `Tests/AuraCoreTests/InstallLayoutTests.swift`

**Interfaces:**
- Consumes: Task 13 的 `plugin/`、Task 11 的 `aura-hook`
- Produces: `plugin/bin/aura-hook`（universal binary）；`scripts/verify-install.sh` 的 exit code
  即實機驗收結果

- [ ] **Step 1: 寫失敗測試 —— plugin 佈局**

```swift
// Tests/AuraCoreTests/InstallLayoutTests.swift
import Testing
import Foundation

@Suite("安裝佈局")
struct InstallLayoutTests {

    static func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        fatalError("找不到 Package.swift")
    }

    /// 從 `hooks.json` 的 command 字串**推導**出應存在的路徑，不寫死。
    ///
    /// 若寫死 `plugin/bin/aura-hook`，有人把 hooks.json 改成
    /// `${CLAUDE_PLUGIN_ROOT}/exec/aura-hook` 並同步改掉 Task 13 的字面值時，
    /// 這條測試仍會檢查舊路徑 —— 全綠但產品靜默失效。這正是 前一個專案 的失效方式。
    static func expectedBinaryPath() throws -> URL {
        let url = repoRoot().appendingPathComponent("plugin/hooks/hooks.json")
        let obj = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        let dict = try #require(obj as? [String: Any])
        var commands: Set<String> = []
        for (_, v) in dict {
            for matcher in (v as? [[String: Any]]) ?? [] {
                for h in (matcher["hooks"] as? [[String: Any]]) ?? [] {
                    if let c = h["command"] as? String { commands.insert(c) }
                }
            }
        }
        #expect(commands.count == 1, "全部 hook 應指向同一個 command：\(commands.sorted())")
        let command = try #require(commands.first)
        // 安裝後 plugin 根目錄就是 repo 的 plugin/
        let relative = command.replacingOccurrences(of: "${CLAUDE_PLUGIN_ROOT}/", with: "plugin/")
        return repoRoot().appendingPathComponent(relative)
    }

    @Test("hooks.json 指向的路徑，在 repo 的 plugin 目錄下真的存在且可執行")
    func pluginBinaryIsInPlace() throws {
        let bin = try Self.expectedBinaryPath()
        #expect(FileManager.default.isExecutableFile(atPath: bin.path),
                "\(bin.path) 不存在或不可執行。先跑 scripts/build-plugin.sh。"
                + "這條擋的正是 前一個專案 留下死 hook 的失效方式")
    }

    @Test("plugin 的 aura-hook 是 universal binary（arm64 + x86_64）")
    func binaryIsUniversal() throws {
        let bin = try Self.expectedBinaryPath()
        try #require(FileManager.default.isExecutableFile(atPath: bin.path))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        p.arguments = ["-archs", bin.path]
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run(); p.waitUntilExit()
        let archs = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(archs.contains("arm64"), "archs=\(archs)")
        #expect(archs.contains("x86_64"), "開源給別人用，Intel Mac 也要能跑。archs=\(archs)")
    }

    @Test("plugin 的 aura-hook 真的能處理 payload")
    func pluginBinaryWorks() throws {
        let bin = try Self.expectedBinaryPath()
        try #require(FileManager.default.isExecutableFile(atPath: bin.path))
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-install-\(UUID().uuidString)/sessions")

        let p = Process()
        p.executableURL = bin
        p.environment = ProcessInfo.processInfo.environment.merging(
            ["AGENTAURA_ROOT": root.path]) { _, new in new }
        let pipe = Pipe(); p.standardInput = pipe
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run()
        pipe.fileHandleForWriting.write(Data(
            #"{"hook_event_name":"PermissionRequest","session_id":"inst1","tool_name":"Bash"}"#.utf8))
        try pipe.fileHandleForWriting.close()
        p.waitUntilExit()

        #expect(p.terminationStatus == 0)
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("inst1.json").path),
            "安裝用的二進位必須真的能寫狀態檔，不只是存在")
    }

    @Test("INSTALL.md 存在且含移除步驟（R6：一步安裝、一步移除）")
    func installDocHasUninstall() throws {
        let doc = try String(contentsOf: Self.repoRoot().appendingPathComponent("docs/INSTALL.md"),
                             encoding: .utf8)
        #expect(doc.contains("plugin uninstall"), "必須寫明如何完整移除")
        #expect(doc.contains(".agentaura"), "必須說明狀態目錄可安全手動刪除")
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter InstallLayoutTests 2>&1 | tail -8`
Expected: FAIL — `plugin/bin/aura-hook` 不存在

- [ ] **Step 3: 寫建置腳本**

```bash
cat > scripts/build-plugin.sh <<'EOF'
#!/usr/bin/env bash
# 建置 universal aura-hook 並放進 plugin/bin/，供 hooks.json 的
# ${CLAUDE_PLUGIN_ROOT}/bin/aura-hook 使用。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 建置 arm64"
swift build -c release --arch arm64 --product aura-hook
echo "==> 建置 x86_64"
swift build -c release --arch x86_64 --product aura-hook

mkdir -p plugin/bin
echo "==> 合併成 universal binary"
lipo -create -output plugin/bin/aura-hook \
  .build/arm64-apple-macosx/release/aura-hook \
  .build/x86_64-apple-macosx/release/aura-hook
chmod +x plugin/bin/aura-hook

echo "==> 驗證"
lipo -archs plugin/bin/aura-hook
echo '{"hook_event_name":"PreToolUse","session_id":"buildcheck","tool_name":"Bash"}' \
  | AGENTAURA_ROOT="$(mktemp -d)/sessions" ./plugin/bin/aura-hook
echo "exit=$?  （必須是 0）"
echo "==> plugin/bin/aura-hook 就緒"
EOF
chmod +x scripts/build-plugin.sh
mkdir -p scripts && ./scripts/build-plugin.sh
```

Expected: `lipo -archs` 輸出含 `arm64` 與 `x86_64`；最後的 `exit=0`

- [ ] **Step 4: 執行測試確認通過**

Run: `swift test --filter InstallLayoutTests 2>&1 | tail -10`
Expected: 前 3 個 PASS；`installDocHasUninstall` 仍 FAIL（文件還沒寫）

- [ ] **Step 5: 寫 INSTALL.md**

```bash
cat > docs/INSTALL.md <<'EOF'
# 安裝 AgentAura

## 需求

- macOS 13 或以上
- Swift 6 工具鏈（`xcode-select --install` 或完整 Xcode）
- Claude Code

## 安裝

```bash
git clone <repo> && cd AgentAura
./scripts/build-plugin.sh          # 建置 universal aura-hook 到 plugin/bin/
claude plugin install ./plugin     # 註冊 hooks（不會修改 ~/.claude/settings.json）
./scripts/verify-install.sh        # 驗證整條鏈路
```

**不需要重啟 Claude Code** —— hook 設定變更會立即對執行中的 session 生效（已實測確認）。

## 完整移除

```bash
claude plugin uninstall agentaura
rm -rf ~/.agentaura                # 狀態目錄，可安全刪除
```

移除後 `~/.claude/settings.json` **不會留下任何 AgentAura 引用** ——
這是刻意的設計：AgentAura 從不修改 `settings.json`，全部靠 plugin 機制。

## 狀態目錄

`~/.agentaura/sessions/<session_id>.json` —— 每個 Claude Code session 一個檔，
內容是瞬時狀態，可隨時安全刪除（app 會在下一個 hook 事件時重建）。

## 疑難排解

**燈沒反應**

```bash
ls -la ~/.agentaura/sessions/                        # 有檔案嗎？
claude plugin list | grep agentaura                  # plugin 裝了嗎？
lipo -archs plugin/bin/aura-hook                     # 二進位在嗎、架構對嗎？
echo '{"hook_event_name":"Stop","session_id":"t1"}' | ./plugin/bin/aura-hook; echo $?
```

`aura-hook` **永遠 exit 0 且不輸出任何訊息**（設計如此：觀測性程式絕不可干擾 agent）。
所以「沒有錯誤訊息」不代表成功 —— 請看 `~/.agentaura/sessions/` 是否真的有檔案。
EOF
```

- [ ] **Step 6: 寫實機驗證腳本**

```bash
cat > scripts/verify-install.sh <<'EOF'
#!/usr/bin/env bash
# 實機驗收：在真的 Claude Code 裡跑一輪，確認狀態檔真的被寫出來。
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$HOME/.agentaura/sessions"
FAIL=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }

echo "== 1. plugin 二進位 =="
[ -x plugin/bin/aura-hook ] && ok "plugin/bin/aura-hook 可執行" \
                            || bad "plugin/bin/aura-hook 不存在 —— 先跑 scripts/build-plugin.sh"
lipo -archs plugin/bin/aura-hook 2>/dev/null | grep -q arm64 \
  && ok "含 arm64" || bad "缺 arm64"

echo "== 2. plugin 已註冊 =="
claude plugin list 2>/dev/null | grep -q agentaura \
  && ok "agentaura plugin 已安裝" || bad "未安裝 —— claude plugin install ./plugin"

echo "== 3. settings.json 未被污染（R6）=="
python3 -c "
import json,pathlib,sys
p=pathlib.Path.home()/'.claude/settings.json'
d=json.loads(p.read_text()) if p.exists() else {}
h=json.dumps(d.get('hooks',{}))
sys.exit(1 if 'agentaura' in h.lower() or 'aura-hook' in h else 0)
" && ok "settings.json 沒有 AgentAura 引用" || bad "settings.json 被寫入了 —— 違反 D3/R6"

echo "== 4. 實機跑一輪 =="
BEFORE=$(ls "$ROOT" 2>/dev/null | wc -l | tr -d ' ')
echo "  執行：claude -p '請執行 echo agentaura-verify'"
claude -p "請執行 echo agentaura-verify" >/dev/null 2>&1
sleep 1
AFTER=$(ls "$ROOT" 2>/dev/null | wc -l | tr -d ' ')
[ "$AFTER" -gt "$BEFORE" ] && ok "狀態檔數量 $BEFORE → $AFTER" \
                           || bad "沒有新狀態檔 —— hook 沒被觸發或 aura-hook 沒寫成功"

echo "== 5. 狀態檔內容合理 =="
LATEST=$(ls -t "$ROOT"/*.json 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
  python3 -c "
import json,sys
d=json.load(open('$LATEST'))
checks=[('schema==1', d.get('schema')==1),
        ('有 session_id', bool(d.get('session_id'))),
        ('有 main_activity', d.get('main_activity') in ['idle','done','working','waiting','error']),
        ('有 pid', isinstance(d.get('pid'), int)),
        ('有 pid_started_at', isinstance(d.get('pid_started_at'), int))]
for name, passed in checks:
    print(('  \033[32m✓\033[0m ' if passed else '  \033[31m✗\033[0m ')+name)
sys.exit(0 if all(p for _,p in checks) else 1)
" || FAIL=1
  echo "  最新狀態檔：$LATEST"
else
  bad "找不到任何狀態檔"
fi

echo
[ "$FAIL" -eq 0 ] && echo "實機驗收 PASS" || echo "實機驗收 FAIL"
exit "$FAIL"
EOF
chmod +x scripts/verify-install.sh
```

- [ ] **Step 7: 實機執行驗收**

```bash
claude plugin install ./plugin
./scripts/verify-install.sh
```

Expected: 全部 ✓，最後印出 `實機驗收 PASS`

**若第 4 項失敗**（沒有新狀態檔）—— 依序排查：
1. `${CLAUDE_PLUGIN_ROOT}` 的實際展開值是否與 Task 01 `mechanisms.md` 記錄的一致
2. plugin 是否支援 `async: true`（Task 01 機制 1 的結論）
3. 手動 `echo '<payload>' | ./plugin/bin/aura-hook` 是否真的寫出檔案

**若第 5 項的 `有 pid` 失敗** —— 即 Task 01 機制 2 判定的「`getppid()` 不是 claude 本體」成真，
按 Task 06 的前置條件切換到 session 心跳 TTL 方案。

- [ ] **Step 8: 執行全部測試**

Run: `swift test 2>&1 | tail -20`
Expected: 全部 PASS

- [ ] **Step 9: 把 plugin/bin 加入 .gitignore（建置產物不進版控）**

```bash
echo "plugin/bin/" >> .gitignore
```

`InstallLayoutTests` 因此在乾淨 checkout 上會 FAIL —— **這是刻意的**：
它強制執行者先跑 `scripts/build-plugin.sh`，正是「二進位必須真的在位」這條 gate 的意義。
CI 的做法是在測試前先跑建置腳本。

- [ ] **Step 10: Commit**

```bash
git add scripts docs/INSTALL.md Tests/AuraCoreTests/InstallLayoutTests.swift .gitignore
git commit -m "feat(install): 建置腳本、實機驗收腳本與安裝文件

補上 self-review 抓到的缺口：hooks.json 指向 \${CLAUDE_PLUGIN_ROOT}/bin/aura-hook，
但先前沒有任何東西把二進位放到那裡。

build-plugin.sh 產 universal binary（arm64 + x86_64，開源給 Intel Mac 用戶）。
verify-install.sh 在真的 Claude Code 裡跑一輪，並驗證 settings.json 未被污染。
INSTALL.md 含完整移除步驟（R6）。"
```

---

## Self-Review

### 1. Spec 覆蓋

| Spec 章節 | Task | 備註 |
|---|---|---|
| §0 R1 多 session 聚合 | T09 · T13 | |
| §0 R2 開源標準 | T14 | universal binary、不寫死路徑、可逆安裝 |
| §0 R3 read-only | — | scope 決策，無需實作 |
| §0 R4 注意力預算 | — | **plan 2（M4）** |
| §0 R5 形態證據決定 | — | **plan 2（M4）** |
| §0 R6 一步安裝／移除／自我健檢 | T13 · T14 | 自我健檢在 **plan 2（M5）** |
| §0 D1 聚合優先序 | T03 · T09 | `Activity.priority` 為唯一來源 + mutation |
| §0 D2 打開面板即確認 | T08 · T13 | 面板本身在 plan 2 |
| §0 D3 plugin 而非 settings.json | T13 · T14 | `verify-install.sh` 驗 settings.json 未污染 |
| §1 架構總覽 | T13 | `PipelineGraph` |
| §2.1 檔案契約 | T05 | |
| §2.1.1 實測校正 7 項 | T02 · T04 | fixture 完整性測試把校正釘死 |
| §2.2 event→activity 對照 | T03 | |
| §2.2.1 Notification 12 型別 | T03 · T13 | matcher 與對照表雙邊契約一致性 |
| §2.3 記憶體模型 | T07 | |
| §2.4 unacked 尾巴 | T08 · T13 | |
| §2.5 main/sub 分槽 | T05 · T11 · T13 | 三層都有（單元／CLI 黑箱／端到端） |
| §3.2 plugin 安裝機制 | T13 · T14 | |
| §3.3 read-merge-write | T10 | flock mutation 驗證 |
| §3.4 介面縫 | T09 · T12 | `AggregatePolicy` / `EventSource`；`IconRenderer` 在 plan 2 |
| §3.5 pid liveness 與回收 | T06 | |
| §3.6 menu bar 渲染 | — | **plan 2** |
| §3.7 面板內容 | — | **plan 2**（`PanelViewModel` 一併） |
| §3.8 自我健檢 | T14（部分） | 死 hook 偵測在 **plan 2** |
| §4 錯誤處理（12 列） | 見下 | |
| §5.1 對抗式 double（15 項） | T02 · T04 · T05 · T06 · T10 · T11 | |
| §5.2 composition-root smoke | T13 | |
| §5.3 mutation 驗證（8 項） | T03 · T05 · T06 · T08 · T09 · T10 · T11 · T12 · T13 | 每個關鍵 gate 都有 |
| §5.4 UI 驗收 | — | **plan 2** |
| §6 檔案佈局 | 本計畫檔案結構表 | `AgentAuraApp/` 在 plan 2 |
| §7 DoD | T13 Step 10 | 幀率／CPU／記憶體在 plan 2 |
| §8 M0 | T01 | |
| §10 provenance | T02 | fixture 由 `docs/evidence/` 衍生 |

**§4 錯誤處理逐列對應：**

| 失效模式 | Task |
|---|---|
| terminal 強制關閉、`SessionEnd` 未觸發 | T06 · T13（`refreshLiveness`） |
| pid 被回收 | T06 |
| 讀到寫入一半的 JSON | T04 · T10 · T12 |
| 未知 `notification_type` | T03 |
| Claude Code 新增 hook event | T03 · T04 |
| app 未運行時累積事件 | T12（`bootstrap`）· T13 |
| 殘留檔案 | T13（`refreshLiveness`）· T08 |
| 磁碟滿／目錄不可寫 | T11 |
| session 數量爆掉（50+） | T08 · T09 · T10 · T13 |
| 螢幕睡眠／menu bar 被遮蔽 | **plan 2** |
| `session_id` 含 path traversal | T10 · T11 |
| 時鐘倒退 | **plan 2**（`PanelViewModel` 的相對時間 clamp） |

### 2. 缺口（已補 / 已知）

- **已補：** `hooks.json` 指向 `${CLAUDE_PLUGIN_ROOT}/bin/aura-hook` 但沒有 task 把二進位放到那裡
  → 新增 **T14**（建置腳本 + 實機驗收 + 安裝文件）
- **已補：** `PipelineGraph` 原本放在 `AuraCore` 卻需要 `SnapshotIO`，會造成 core → IO 反向依賴
  → 改放 `AuraHookFile`
- **刻意留給 plan 2：** `PanelViewModel`（含時鐘倒退 clamp）、`IconRenderer` protocol、
  `AnimationDriver`、螢幕睡眠節流、自我健檢死 hook 偵測、幀率／CPU／記憶體 DoD
- **依賴 T01 結論：** 若 `getppid()` 不等於 claude 本體，T06 改走 session 心跳 TTL
  （前置條件已寫在 T06 開頭，T14 Step 7 有對應的排查指引）

### 3. 型別一致性

檢查過的跨 task 契約：`Activity` / `EventEffect`（T03）→ T04 · T05 · T09；
`HookPayload`（T04）→ T05 · T11；`SessionSnapshot` · `effectiveActivity`（T05）→ T07 · T10 · T11 · T12；
`MergeRules.merge(_:into:pid:pidStartedAt:now:)`（T05）→ T11；`SessionState`（T07）→ T08 · T09；
`IconState`（T07）→ T09 · T13；`LivenessProbing` · `StubLiveness`（T06）→ T07 · T13；
`SnapshotIO`（T10）→ T11 · T12 · T13；`EventSource`（T12）→ T13；
`AuraHookCLITests.binaryURL()`（T11）→ T13 · T14 共用。

> `SessionState` 沒有明確 `public init`，測試靠 memberwise（internal）init 建構 ——
> 因為測試用 `@testable import`，這樣可行且刻意（不對外暴露建構子）。

---

## 執行方式

Plan 完成，存於 `docs/superpowers/plans/2026-09-08-agentaura-pipeline.md`。

**任務相依：** T01 → T02 → T03 → T04 → T05 → {T06, T07} → T08 → T09 → T10 → T11 → T12 → T13 → T14

T06 與 T07 可並行（互不依賴）。其餘為線性相依。
T01 需要**使用者親自操作互動 session**（`PermissionRequest` / `Notification` 只在互動模式觸發），
不能全自動化。

**每個 task 的 pre-flight：** `git branch --show-current` 確認不在 `main`。
