# AgentAura 實作計畫（M0-M3 資料管線 + M4/M5 的 UI 最小可用版）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 Claude Code hook → 狀態檔 → `IconState` 的完整資料管線（T01-T14），再加上足以「產出一版可以用的版本」的 UI（T15-T18：選單列 icon、面板、`.app`）。

**Architecture:** Claude Code plugin 註冊全部 async hook → `aura-hook` CLI 在 `flock` 下 merge-write `~/.agentaura/sessions/<session_id>.json` → `HookFileSource` 以 FSEvents 監看 → `SessionReducer` 產 `SessionState` → `AggregatePolicy` 產 `IconState`。核心邏輯（`AuraCore`）為純函數且零 AppKit 依賴。

**Tech Stack:** Swift 6（swift-testing）、SwiftPM、FSEvents、`flock(2)`、`sysctl(KERN_PROC_PID)`、Claude Code plugin hooks

**Spec:** `docs/superpowers/specs/2026-09-08-agentaura-design.md`

**範圍說明：** T01-T14 涵蓋 spec 的 M0-M3（資料管線 + plugin + 安裝）。
T15-T18 是後來追加的第二部分，取 M4/M5 裡「讓它能用」的最小子集。

**明確不在本計畫內的 M4 工作**：spec 的 R5 要求「形態用證據決定，不預先鎖定」——
M4 原本要**同時**做兩個原型（A：8 顆迷你 LED 燈條；B：單一符號 + 顏色 + 動畫），
共用同一份 `IconState`、只換 `IconRenderer` 實作，再由 persona-tester 對
**餘光辨識**與**遠距辨識**打分後選一個。**本計畫只做形態 A**，
沒有做 A/B 比較，所以 **R5 尚未滿足**，必須記為 known gap 而不是宣稱達成。

> **一個已知的形態觀察（留給 M4）**：`LEDStripView` 目前把 8 顆 LED 畫成
> **完全相同的顏色與 alpha**，所以那 8 顆的資訊量等於 1 顆 —— 它是裝飾，
> 不是資料。而 `IconAppearance` 其實已經帶著 `liveCount` 與 `attentionCount`，
> 要讓「亮幾顆」有意義只需要幾行。
>
> **刻意不在這裡改**：那是形態決策，而 R5 明文要求形態由 A/B 證據決定、
> 不預先鎖定。現在的畫法符合 spec §3.6 的字面（一條反映**聚合**狀態的燈條 +
> R4 的動畫語言），改它會變成我用直覺替 M4 做決定。
> M4 做 A/B 時把「8 顆是否該編碼 session 數」一併列為受測變項。

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

## Mutation 驗證的標準程序

關鍵 gate 一律要做，判準是**實際看到 RED**——「相信它會紅」不算通過。

1. `cp <file> /tmp/aura-mut.bak`
2. **手動編輯**那一處。**不要用 `sed`**：對多行 Swift 的 `sed` 很脆，本計畫已有
   兩處 sed 指令被實測證實打錯目標或產生不合法的 Swift。各 task 的 mutation
   說明會指名「把什麼改成什麼」，照著改即可。
3. `swift test --filter <指定的 suite>` —— 確認**指定的那些測試真的 FAIL**，
   把真實輸出貼進報告。
4. `cp /tmp/aura-mut.bak <file>` 還原。**不要用 `git checkout <file>`**：
   mutation 常發生在該檔第一次 commit 之前，檔案尚未被追蹤，
   `git checkout` 會回 `pathspec did not match`（實測）。
5. 再跑一次確認全綠。

若某個 mutation **沒有**讓指定測試變紅，那比實作本身更重要：代表那個測試
看不見它聲稱要保護的東西。**回報，不要繞過。**

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
        .executableTarget(name: "AgentAuraApp", dependencies: ["AuraCore", "AuraHookFile"]),
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

```swift
// Sources/AgentAuraApp/main.swift
// 佔位：Task 16 填入實際內容（menu bar app 本體）。
// 與上面同理：Package.swift 宣告了這個 executableTarget，沒有原始檔就 build 不起來。
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
import Testing        // #require 是 swift-testing 的巨集，helper 檔也要 import

enum Fixtures {
    /// 讀取探針 ndjson，回傳剝開 `_payload` 後的原始 hook JSON 字典陣列。
    static func rawEvents(named name: String) throws -> [[String: Any]] {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "ndjson"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").compactMap { line -> [String: Any]? in
            // 先轉 String：對 Substring 呼叫 trimmingCharacters(in:) 時
            // `.whitespaces` 的 contextual base 推不出來（實測 Swift 6.3.3 編譯錯誤）。
            let text = String(line)
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty,
                  let data = text.data(using: .utf8),
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

> 註：`#require` 是 swift-testing 的巨集，所以這個 helper 檔也必須 `import Testing` ——
> 少了它會得到 `no macro named 'require'`（實測）。

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
    // MARK: - 隔離 gate：問編譯器，不掃原始碼

    /// 為什麼改成問編譯器（前四輪都掃原始碼文字，每輪都被新的語法形狀打破：scoped
    /// import → access-level import → attribute 字串參數 → regex literal `/…/`、
    /// 插值、「多行字串的開頭 delimiter 後面必須換行」…）：
    ///
    /// 1. 掃文字等於重寫一份 Swift lexer，任何近似都留下繞過空間；
    /// 2. 更關鍵——掃文字答的是「這份**文字**裡有沒有 import AppKit 的字樣」，而
    ///    Global Constraint 問的是「AuraCore **建起來**會不會依賴 AppKit」，且含
    ///    transitive：只寫 `import Mid`、而 Mid 內部 `@_exported import AppKit` 的
    ///    檔案全文「AppKit」出現 0 次，依賴卻是真的（實測 trace 確實回報 AppKit）。
    ///
    /// 編譯器用的就是編譯這個 module 的那套 lexer，答的也正是第 2 個問題 —— 沒有
    /// 語法能騙過它，corpus 也不必隨 Swift 語法演進而增長。
    static let bannedModules: Set<String> = ["AppKit", "SwiftUI", "Cocoa"]

    /// gate 用的 target triple：arch 跟著主機（Intel Mac 也要能跑），最低版本對齊
    /// Package.swift 的 `.macOS(.v13)`，一致性由 `manifestPinsGateAssumptions` 釘住。
    static var gateTarget: String {
        #if arch(arm64)
        "arm64-apple-macos13"
        #elseif arch(x86_64)
        "x86_64-apple-macos13"
        #else
        #error("未支援的架構：請補上這個架構的 gate target triple")
        #endif
    }

    // ─────────────────────────────────────────────────────────────────────
    // 這道 gate 走過五輪。前四輪都在同一個 regex 上打補丁，每一輪都綠燈交付、
    // 每一輪都還藏著一個漏放：
    //   1. contains("import AppKit")      漏 import class AppKit.NSWindow
    //   2. 行首錨定 regex                  漏 9 種 attribute / access-level 形狀
    //   3. 前綴放寬到任意 attribute        誤攔 @available(..., message: "(x) import ...")
    //   4. 括號內容排除引號                漏 @_documentation(metadata: "foo") import AppKit
    //   5. 兩段式：先中性化字面值再比對    19 個漏放 / 4 個根因（regex literal 狀態、
    //                                      插值近似、lineTerminators 超集、5 種宣告前綴）
    //
    // 結構性結論：**單一 regex 沒辦法同時描述 Swift 的宣告前綴文法、又判斷某個位置
    // 是否落在字面值裡。** 補到底就是在寫一個 Swift lexer。
    //
    // 所以第五輪換問題：不問「這些檔案的文字裡有沒有寫 import AppKit」，
    // 改問「AuraCore 編出來的時候有沒有載入 AppKit」——後者才是 Global Constraint
    // 真正要求的（「不得依賴」），用的是編譯 module 的同一個 lexer，任何語法都騙不過，
    // 而且能抓到源碼掃描**結構上抓不到**的遞移依賴（實測：檔案裡 AppKit 出現 0 次，
    // 只寫 import Mid，仍被攔下）。
    // ─────────────────────────────────────────────────────────────────────

    struct GateFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// 全新的暫存目錄。每次都要新的：`-emit-loaded-module-trace-path` 是**附加**寫入
    /// （實測路徑已存在會再接一個 JSON 物件），沿用固定路徑會讀到上一輪的殘留。
    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-isolation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    /// 問編譯器：把這些檔案編起來會載入哪些 module？任何前提壞掉（沒有輸入檔、swiftc
    /// 失敗、trace 沒寫出來、解析不出 module）一律 throw —— 不准因此變成「乾淨」。
    static func loadedModules(compiling files: [URL], searchPaths: [String] = [],
                              tracePathOverride: String? = nil) throws -> Set<String> {
        guard !files.isEmpty else {
            throw GateFailure("沒有可編譯的原始檔 —— gate 不能空跑")
        }
        return try withTemporaryDirectory { dir in
            let trace = tracePathOverride ?? dir.appendingPathComponent("trace.json").path
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["swiftc", "-typecheck", "-target", gateTarget,
                              "-emit-loaded-module-trace", "-emit-loaded-module-trace-path", trace]
                + searchPaths.flatMap { ["-I", $0] } + files.map(\.path)
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            try task.run()
            let log = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            task.waitUntilExit()                       // 先讀完再等，pipe 才不會塞滿卡死

            guard task.terminationStatus == 0 else {
                throw GateFailure("""
                    swiftc 編譯失敗（exit \(task.terminationStatus)），gate 無法作答。
                    這必須是紅燈：前提壞掉時放行，等於把 gate 關掉。
                    指令：swiftc \(task.arguments!.dropFirst().joined(separator: " "))
                    編譯器輸出：
                    \(log)
                    """)
            }
            guard FileManager.default.fileExists(atPath: trace) else {
                throw GateFailure("swiftc 沒有產出 module trace（\(trace)）。編譯器輸出：\n\(log)")
            }
            let text = try String(contentsOfFile: trace, encoding: .utf8)
            var modules: Set<String> = []
            for line in text.split(separator: "\n") where !line.isEmpty {
                guard let data = String(line).data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let infos = object["swiftmodulesDetailedInfo"] as? [[String: Any]]
                else { throw GateFailure("module trace 解析失敗：\(line)") }
                modules.formUnion(infos.compactMap { $0["name"] as? String })
            }
            guard !modules.isEmpty else {
                throw GateFailure("module trace 解析出 0 個 module —— 空 trace 不能讀成「乾淨」（\(trace)）")
            }
            return modules
        }
    }

    @Test("AuraCore 編譯時不得載入 AppKit / SwiftUI / Cocoa")
    func coreLoadsNoUIModules() throws {
        let files = Self.swiftFiles(under: "Sources/AuraCore")   // 掃磁碟，不用手寫清單
        #expect(!files.isEmpty, "掃不到 AuraCore 的原始檔 —— gate 不能空跑")
        let loaded = try Self.loadedModules(compiling: files)
        let banned = loaded.intersection(Self.bannedModules)
        #expect(banned.isEmpty, """
            AuraCore 編譯時載入了禁止的 module：\(banned.sorted().joined(separator: ", "))
            （這次共載入 \(loaded.count) 個 module）
            """)
    }

    /// 正向對照：gate 真的抓得到違規，而不是永遠回報「乾淨」。`import Cocoa` 這個
    /// probe 順便釘住一件容易誤會的事——module trace **不會**出現 `Cocoa` 這個名字
    /// （它是 re-export AppKit 的 Clang module），是靠 `AppKit` 被攔下來的。
    @Test("編譯器 gate 對真違規會紅（正向對照）")
    func compilerGateCatchesViolations() throws {
        for line in ["import AppKit", "import Cocoa", "import SwiftUI"] {
            let loaded = try Self.withTemporaryDirectory { dir -> Set<String> in
                let probe = dir.appendingPathComponent("Probe.swift")
                try "\(line)\npublic enum Probe { public static let v = 1 }\n"
                    .write(to: probe, atomically: true, encoding: .utf8)
                return try Self.loadedModules(compiling: [probe])
            }
            let banned = loaded.intersection(Self.bannedModules)
            #expect(!banned.isEmpty, "gate 沒抓到 `\(line)` —— 解析壞了會讓所有東西看起來都乾淨")
        }
    }

    /// 釘住這個機制**唯一**做得到、掃文字永遠做不到的事：transitive 依賴。
    /// probe 的原始碼全文沒有「AppKit」字樣，只 `import Mid`，而 Mid 內部
    /// `@_exported import AppKit` —— 任何文字 gate 對它必然是綠的。
    @Test("gate 抓得到 transitive 依賴（文字裡沒有 AppKit 也算）")
    func compilerGateCatchesTransitiveDependency() throws {
        let loaded = try Self.withTemporaryDirectory { dir -> Set<String> in
            let mid = dir.appendingPathComponent("Mid.swift")
            try "@_exported import AppKit\npublic enum Mid { public static let v = 1 }\n"
                .write(to: mid, atomically: true, encoding: .utf8)
            let build = Process()
            build.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            build.arguments = ["swiftc", "-emit-module", "-module-name", "Mid",
                               "-target", Self.gateTarget, "-emit-module-path",
                               dir.appendingPathComponent("Mid.swiftmodule").path, mid.path]
            try build.run()
            build.waitUntilExit()
            try #require(build.terminationStatus == 0, "建不出 Mid.swiftmodule，這個對照組就失效了")
            let source = "import Mid\npublic enum Probe { public static let v = Mid.v }\n"
            #expect(!source.contains("AppKit"), "probe 原始碼必須不含 AppKit 字樣，否則證明不了 transitive")
            let probe = dir.appendingPathComponent("Probe.swift")
            try source.write(to: probe, atomically: true, encoding: .utf8)
            return try Self.loadedModules(compiling: [probe], searchPaths: [dir.path])
        }
        #expect(loaded.contains("AppKit"), "transitive 依賴沒被抓到 —— 這是換掉文字 gate 的主要理由")
    }

    /// 反向對照：gate 自己的前提壞掉時必須紅，不准讀成「乾淨」—— 這條 task 反覆
    /// 產生的失敗模式正是 silent degradation。trace 寫不出去（實測 swiftc exit 1）
    /// 與完全沒有輸入檔，兩種前提破壞都必須 throw。
    @Test("gate 前提壞掉時必須紅，不准安靜放行（反向對照）")
    func compilerGateFailsLoudlyWhenBroken() {
        #expect(throws: GateFailure.self, "trace 寫不出來時不能回報乾淨") {
            _ = try Self.loadedModules(compiling: Self.swiftFiles(under: "Sources/AuraCore"),
                                       tracePathOverride: "/nonexistent-\(UUID().uuidString)/trace.json")
        }
        #expect(throws: GateFailure.self, "沒有輸入檔時不能回報乾淨") {
            _ = try Self.loadedModules(compiling: [])
        }
    }

    /// 編譯器 gate 用單獨的 `swiftc` 跑，前提是 AuraCore 沒有 target dependency（否則
    /// 要補 `-I`）。把前提釘在 manifest 上：一旦長出依賴或平台版本調動，這個測試要紅在
    /// 「請補 -I／同步 triple」，而不是讓 gate 安靜地編不動。字串比對對排版敏感，但
    /// 敏感的方向是安全的（改格式會紅，不會靜默放行）。
    @Test("Package.swift 仍撐得住編譯器 gate 的假設")
    func manifestPinsGateAssumptions() throws {
        let manifest = try String(contentsOf: Self.repoRoot().appendingPathComponent("Package.swift"),
                                  encoding: .utf8)
        #expect(manifest.contains(#".target(name: "AuraCore"),"#),
                "AuraCore 有了 target dependency：gate 的 swiftc 需要對應的 -I 路徑")
        #expect(manifest.contains(".macOS(.v13)"),
                "平台最低版本變了：請同步 IsolationTests.gateTarget")
    }

    // MARK: - 檔案長度

    /// 正確算行數：`split(separator: "\n", omittingEmptySubsequences: false).count` 對
    /// 結尾有換行的檔案會多算 1（`"a\nb\n"` → 3），使「≤200」實際擋在 199。改成數換行。
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

    /// 行數上限分層：`Sources/` ≤ 200、`Tests/` ≤ 300 —— 測試檔合理地帶著 fixture
    /// 判讀邏輯，所以給 300，而不是留一個沒寫明的豁免。掃描對象由磁碟推導（`Sources`／
    /// `Tests` 遞迴），新增 module 或 test target 不會靜默逃過上限。
    @Test("Sources 每檔 ≤ 200 行、Tests 每檔 ≤ 300 行")
    func fileLengthLimit() throws {
        for (layer, limit) in [("Sources", 200), ("Tests", 300)] {
            let files = Self.swiftFiles(under: layer)
            #expect(!files.isEmpty, "\(layer) 掃不到任何 .swift —— gate 不能空跑")
            for file in files {
                let lines = Self.lineCount(of: try String(contentsOf: file, encoding: .utf8))
                #expect(lines <= limit, "\(layer)/\(file.lastPathComponent) 有 \(lines) 行，超過 \(limit) 行上限")
            }
        }
    }
}
```

- [ ] **Step 6: 寫 fixture 完整性測試（確認真實資料真的載進來了）**

放獨立檔，不要附加到 `IsolationTests.swift` —— 隔離約束與 fixture 完整性是
兩件事，而且合在一起會撞上 `Tests/` ≤ 300 行的上限。

```swift
// Tests/AuraCoreTests/FixtureIntegrityTests.swift
import Testing
import Foundation

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

    /// 對現實的回歸測試 —— **必須含 round2**。
    ///
    /// round1 + round1b 只有 6 種 event（`SessionStart`、`UserPromptSubmit`、
    /// `PreToolUse`、`PostToolUse`、`Stop`、`SessionEnd`），而這 6 種全都已被本檔
    /// 其他具名測試釘住，所以只載它們等於零增量保護。
    ///
    /// round2 多帶 5 種本測試否則完全碰不到的：`Notification`、`PermissionRequest`、
    /// `PostToolBatch`、`PostToolUseFailure`、`SubagentStop`。其中
    /// **`PostToolUseFailure` 與 `Notification` 正是兩個靠實測才修對的映射**
    /// （前者原本錯映射成 error、後者的未知型別 fallback 原本錯成 waiting），
    /// 也就是最該有現實回歸測試的兩個。覆蓋從 6 種提升到 11 種。
    @Test("三份 fixture 裡的每個真實 event 都不落到 noChange")
    func realEventsAreAllMapped() throws {
        let all = try Fixtures.rawEvents(named: "round1")
            + Fixtures.rawEvents(named: "round1b")
            + Fixtures.rawEvents(named: "round2")
        let kinds = Set(all.compactMap { $0["hook_event_name"] as? String })
        #expect(kinds.count >= 11, "三份 fixture 應涵蓋至少 11 種 event，實際 \(kinds.sorted())")
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

三個驗證都照 Global Constraints 的標準程序（`cp` 備份 → 手動編輯 → 看 RED → `cp` 還原 → 看綠）。

**驗證 1 —— 撤掉 D1 優先序**
`Sources/AuraCore/Activity.swift`：把 `case .waiting: 3` 改成 `case .waiting: 1`。
Run: `swift test --filter ActivityTests`
Expected FAIL: `priorityOrder`、`maxPreservesWaiting`（`prioritiesAreDistinct` 也會連帶紅，
因為 priority 值不再兩兩不同——這是正常的連帶效果，不是額外問題）。

**驗證 2 —— `PostToolUseFailure` 改回 error**
`Sources/AuraCore/EventMapping.swift`：把 `"PostToolUseFailure"` 從 working 那一組的
字串清單移除，加進 `case "StopFailure":` 那一行變成
`case "StopFailure", "PostToolUseFailure":`。
Run: `swift test --filter EventMappingTests`
Expected FAIL: `toolFailureIsNotError`（其餘測試不受影響）。

**驗證 3 —— `Notification` 未知型別改回 waiting**
`Sources/AuraCore/EventMapping.swift`，在 `notificationEffect(_:)` 內部：
把**最後一行**的 `return .noChange` 改成 `return .setActivity(.waiting)`。
注意是 `notificationEffect` 的結尾那一行，**不是**外層 `effect(forEvent:)` 的
`default:` 分支——改錯位置會得到不合法的 Swift 而根本編不過。
Run: `swift test --filter EventMappingTests`
Expected FAIL: `notificationNoise`（6 個參數化案例全紅）與 `notificationUnknown`。
`notificationUnknown` 裡 `nil` 的那個子案例會維持綠——那條走的是
`guard let type else` 分支，本 mutation 不影響它，屬正確行為。

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
      public let toolError: String?         // error，tool 失敗的實際訊息
      public let isInterrupt: Bool          // is_interrupt，使用者 Ctrl+C 中斷 != tool 失敗
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
        // 用 closure 而非 `contains(where: \.isSubagent)`：把 key-path 當函式傳進
        // rethrows 函式時，#expect 的巨集展開會判定「call can throw」而編譯失敗（實測）。
        #expect(payloads.contains { $0.isSubagent })
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
        // 刻意分兩行：`#require` 不能嵌在另一個 `#require` 裡
        //（error: recursive expansion of macro 'require'），實測 Swift 6.3.3。
        let json = try #require(starts.first)
        let p = try #require(HookPayload(json: json))
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
        let first = try #require(reqs.first)
        let p = try #require(HookPayload(json: first))
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
        let json = try #require(ends.first)
        let p = try #require(HookPayload(json: json))
        #expect(p.reason == "prompt_input_exit", "實測值")
        #expect(p.effect == .sessionEnded)
    }

> **以下兩個系統性掃描放獨立檔 `Tests/AuraCoreTests/HookPayloadToleranceTests.swift`**
> （需要 `import Testing` / `import Foundation` / `@testable import AuraCore` 與自己的
> `@Suite`）。理由：`HookPayloadTests.swift` 含它們會到 361 行，超過 `Tests/` ≤ 300
> 的上限；而且「手工列舉的容錯」與「系統性掃描」本來就是兩種職責。

    /// **提取正確性掃描。**
    ///
    /// 對每個欄位問：「當真實 payload 裡有合法值時，屬性有沒有解析出來？」
    /// 抓的是「欄位存在卻被讀成 nil」這一類 —— 例如 key 名寫錯、巢狀路徑走錯、
    /// `nonEmpty` 誤把合法值濾掉。
    ///
    /// 這個測試**不破壞任何東西**；損壞容忍度是 `perFieldCorruptionTolerance` 的職責。
    /// 兩者保證不同的事，不可互相取代。
    ///
    /// 已知邊界：它只運動 corpus 裡實際出現過的 key，所以 `end_reason` 與
    /// `to_model`（防禦性的替代名，現實從未產出）碰不到 —— 那兩個由
    /// `reasonFieldTolerance` 與 `modelFromPostModelSwitch` 覆蓋。
    /// **看到「重複的」手工測試不要刪，它們正好覆蓋 corpus-derived 碰不到的部分。**
    @Test("真實 payload 有合法值的欄位，都必須被解析出來")
    func extractionMatchesRawValues() throws {
        struct FieldProbe {
            let name: String
            let hasRawValue: ([String: Any]) -> Bool
            let propertyValue: (HookPayload) -> Any?
        }

        let probes: [FieldProbe] = [
            .init(name: "cwd", hasRawValue: { ($0["cwd"] as? String)?.isEmpty == false }, propertyValue: { $0.cwd }),
            .init(name: "permissionMode", hasRawValue: { ($0["permission_mode"] as? String)?.isEmpty == false }, propertyValue: { $0.permissionMode }),
            .init(name: "source", hasRawValue: { ($0["source"] as? String)?.isEmpty == false }, propertyValue: { $0.source }),
            .init(name: "reason", hasRawValue: { (($0["reason"] as? String) ?? ($0["end_reason"] as? String))?.isEmpty == false }, propertyValue: { $0.reason }),
            .init(name: "toolName", hasRawValue: { ($0["tool_name"] as? String)?.isEmpty == false }, propertyValue: { $0.toolName }),
            .init(name: "toolDescription", hasRawValue: { (($0["tool_input"] as? [String: Any])?["description"] as? String)?.isEmpty == false }, propertyValue: { $0.toolDescription }),
            .init(name: "toolDurationMs", hasRawValue: { $0["duration_ms"] is Int }, propertyValue: { $0.toolDurationMs }),
            .init(name: "model", hasRawValue: { (($0["model"] as? String) ?? ($0["to_model"] as? String))?.isEmpty == false }, propertyValue: { $0.model }),
            .init(name: "notificationType", hasRawValue: { ($0["notification_type"] as? String)?.isEmpty == false }, propertyValue: { $0.notificationType }),
            .init(name: "notificationMessage", hasRawValue: { ($0["message"] as? String)?.isEmpty == false }, propertyValue: { $0.notificationMessage }),
            .init(name: "lastMessage", hasRawValue: { ($0["last_assistant_message"] as? String)?.isEmpty == false }, propertyValue: { $0.lastMessage }),
            .init(name: "agentID", hasRawValue: { ($0["agent_id"] as? String)?.isEmpty == false }, propertyValue: { $0.agentID }),
            .init(name: "agentType", hasRawValue: { ($0["agent_type"] as? String)?.isEmpty == false }, propertyValue: { $0.agentType }),
        ]

        let all = try Fixtures.rawEvents(named: "round1")
            + Fixtures.rawEvents(named: "round1b")
            + Fixtures.rawEvents(named: "round2")
        #expect(all.count == 141)

        var exercised: Set<String> = []
        var combinations = 0
        for json in all {
            guard let p = HookPayload(json: json) else {
                Issue.record("真實 payload 解析失敗：\(json["hook_event_name"] ?? "?")")
                continue
            }
            for probe in probes where probe.hasRawValue(json) {
                combinations += 1
                #expect(probe.propertyValue(p) != nil,
                        "\(probe.name) 原始值存在卻沒被解析出來（event: \(json["hook_event_name"] ?? "?"))")
                exercised.insert(probe.name)
            }
        }

        for probe in probes {
            #expect(exercised.contains(probe.name),
                    "真實 fixture 裡沒有任何 payload 讓 \(probe.name) 有值 —— 這個欄位的覆蓋率是空的")
        }
        #expect(combinations > 0)
    }

    /// **損壞容忍度掃描 —— 這個型別存在的核心主張。**
    ///
    /// `HookPayload` 刻意不用 `Codable`，理由是「字典讀取容忍未知／缺失／改型的
    /// 欄位，而 `Codable` 會讓整個 decode 失敗」。**那句話就是這個測試在驗的東西。**
    ///
    /// 從真實 payload 的實際 key 推導（不是手工清單，所以新增欄位自動涵蓋）：
    /// 逐一移除、逐一換成 5 種不符型別，斷言只有 `hook_event_name` 與 `session_id`
    /// 是必要的，其餘任何欄位壞掉都不得讓整個解析失敗（該欄位變 nil 即可）。
    ///
    /// **與 `extractionMatchesRawValues` 不重疊，兩者都不能刪**：那個驗「好資料上
    /// 提取正確」，這個驗「壞資料不會拖垮整體」。曾經有一版把兩者混為一談，
    /// 結果核心主張對 14 個 optional 欄位中的 12 個完全沒有測試。
    @Test("逐一破壞真實 payload 的每個欄位：只有兩個是必要的")
    func perFieldCorruptionTolerance() throws {
        // 三份 fixture 全用，**不取樣**。
        //
        // 曾經有一版寫 `where i % 8 == 0`（為了控制測試時間），結果它靜默掏空了覆蓋：
        // 9 個這個型別真的會讀的 key 完全沒有損壞測試，因為那個 stride 剛好錯過
        // 它們在 corpus 裡的每一次出現 —— 其中包括 `error` 與 `is_interrupt`
        // （`toolError` / `isInterrupt` 的來源），它們唯一的出現位置在 round2 的
        // index 66，而 66 % 8 == 2。
        //
        // 取樣省下的時間遠不值得換掉覆蓋（1032 次建構 ~0.014s）。
        let reals = try Fixtures.rawEvents(named: "round1")
            + Fixtures.rawEvents(named: "round1b")
            + Fixtures.rawEvents(named: "round2")
        let required: Set<String> = ["hook_event_name", "session_id"]
        var checked: Set<String> = []

        for json in reals {
            for key in json.keys {
                checked.insert(key)

                var dropped = json
                dropped.removeValue(forKey: key)
                if required.contains(key) {
                    #expect(HookPayload(json: dropped) == nil,
                            "\(key) 是必要欄位，移除後應回 nil")
                } else {
                    #expect(HookPayload(json: dropped) != nil,
                            "\(key) 非必要，移除後仍應解析成功")
                }

                for wrong: Any in [NSNull(), 42, ["nested": [1, 2, 3]], [1, 2, 3], true] {
                    var retyped = json
                    retyped[key] = wrong
                    if required.contains(key) {
                        #expect(HookPayload(json: retyped) == nil,
                                "\(key) 型別錯時應回 nil")
                    } else {
                        #expect(HookPayload(json: retyped) != nil,
                                "\(key) 型別錯時不該讓整個解析失敗，該欄位變 nil 即可")
                    }
                }
            }
        }
        // 斷言涵蓋 corpus 裡出現過的**每一個** key，而不是「至少 N 個」——
        // 後者無法察覺取樣把某些 key 整批跳過。
        let allCorpusKeys = Set(reals.flatMap { $0.keys })
        #expect(checked == allCorpusKeys,
                "漏掃的 key：\(allCorpusKeys.subtracting(checked).sorted())")

        // 特別點名這個型別會讀、且 corpus 有的 key —— 最容易被取樣跳過的那一批
        for key in ["error", "is_interrupt", "message", "model",
                    "notification_type", "reason", "source", "tool_input"] {
            if allCorpusKeys.contains(key) {
                #expect(checked.contains(key), "\(key) 在 corpus 裡卻沒被掃到")
            }
        }
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
    public let toolDescription: String?
    /// `PostToolUseFailure` 的錯誤訊息。
    ///
    /// 欄位名是 `error`，**不是**文件說的 `tool_error`（spec §2.1.2 曾據一份手寫的
    /// key 過濾清單錯誤斷言「沒有錯誤欄位」，那份清單裡沒有 `error`）。
    public let toolError: String?
    /// `is_interrupt` —— 使用者按 Ctrl+C 中斷，而不是 tool 真的失敗。
    ///
    /// 語意差別有後果：中斷是使用者的動作，**不該計入 `tool_failures`**。
    /// 缺欄位時視為 `false`（絕大多數事件不帶它）。
    public let isInterrupt: Bool
    public let toolDurationMs: Int?
    public let notificationType: String?
    public let notificationMessage: String?
    public let model: String?
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
        toolError        = Self.nonEmpty(json["error"])
        isInterrupt      = (json["is_interrupt"] as? Bool) ?? false
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

**測試分三個檔**，因為全部放一起會到 367 行、超過 `Tests/` ≤ 300 的上限，
而且分槽邏輯（§2.5 / §2.5.1）與累積欄位本來就是兩種職責：

- `MergeRulesTestSupport.swift` —— 共用的 helper（不重複三份）
- `MergeRulesSlotTests.swift` —— §2.5 / §2.5.1 的分槽規則
- `MergeRulesTests.swift` —— 累積欄位、terminated、Codable

```swift
// Tests/AuraCoreTests/MergeRulesTestSupport.swift
import Foundation
@testable import AuraCore

/// 三個 MergeRules 測試檔共用。抽出來而不是複製三份 —— 複製的話改一處要記得改三處。
enum MergeFixture {
    static let t0 = Date(timeIntervalSince1970: 1_788_628_000)

    static func payload(_ event: String, tool: String? = nil, agent: String? = nil,
                        agentType: String? = nil, notif: String? = nil) -> HookPayload {
        var json: [String: Any] = ["hook_event_name": event, "session_id": "s1"]
        if let tool { json["tool_name"] = tool }
        if let agent { json["agent_id"] = agent; json["agent_type"] = agentType ?? "implementer" }
        if let notif { json["notification_type"] = notif }
        return HookPayload(json: json)!
    }

    static func merge(_ p: HookPayload, into s: SessionSnapshot?,
                      at t: Date? = nil) -> SessionSnapshot {
        MergeRules.merge(p, into: s, pid: 4242, pidStartedAt: 111, now: t ?? t0)
    }
}
```

兩個測試檔各自在開頭寫這三行，就能沿用原本的呼叫寫法：

```swift
    let t0 = MergeFixture.t0
    func payload(_ e: String, tool: String? = nil, agent: String? = nil,
                 agentType: String? = nil, notif: String? = nil) -> HookPayload {
        MergeFixture.payload(e, tool: tool, agent: agent, agentType: agentType, notif: notif)
    }
    func merge(_ p: HookPayload, into s: SessionSnapshot?, at t: Date? = nil) -> SessionSnapshot {
        MergeFixture.merge(p, into: s, at: t)
    }
```

**`MergeRulesSlotTests.swift`** 收下面標了「§2.5」與「§2.5.1」的測試
（`subagentCannotMaskWaiting` 到 `internalSubagentNotCounted`）；
**`MergeRulesTests.swift`** 收其餘（累積欄位、terminated、Codable round-trip）。

```swift
// Tests/AuraCoreTests/MergeRulesSlotTests.swift
import Testing
import Foundation
@testable import AuraCore

@Suite("MergeRules 分槽（§2.5 / §2.5.1）")
struct MergeRulesSlotTests {
    let t0 = MergeFixture.t0
    func payload(_ e: String, tool: String? = nil, agent: String? = nil,
                 agentType: String? = nil, notif: String? = nil) -> HookPayload {
        MergeFixture.payload(e, tool: tool, agent: agent, agentType: agentType, notif: notif)
    }
    func merge(_ p: HookPayload, into s: SessionSnapshot?, at t: Date? = nil) -> SessionSnapshot {
        MergeFixture.merge(p, into: s, at: t)
    }

    // ---- 核心：subagent 不得蓋掉主 agent 的 waiting ----

    /// §2.5 的原始情境。
    ///
    /// 注意這裡**沒有**斷言 `subActivity == .working`：§2.5.1 之後，主槽處於靜止態
    /// （`waiting` 是靜止態）時 subagent 事件被完全忽略，所以 sub 槽保持 nil。
    /// 這個測試守的是**意圖** —— 橘燈不會因為 subagent 插隊而消失 —— 而 §2.5.1
    /// 的規則比原本的 `max` 更強地達成同一件事。
    ///
    /// sub 槽真的被寫入的情況見 `subagentRecordedWhileWorking`（主槽非靜止）。
    @Test("subagent 的 PostToolUse 不得蓋掉主 agent 的 waiting")
    func subagentCannotMaskWaiting() {
        var s = merge(payload("PermissionRequest", tool: "Bash"), into: nil)
        #expect(s.mainActivity == .waiting)

        // 20ms 後 subagent 插入事件 —— 實測的真實間隔
        s = merge(payload("PostToolUse", tool: "Write", agent: "sub1"),
                  into: s, at: t0.addingTimeInterval(0.02))

        #expect(s.mainActivity == .waiting, "主槽必須維持 waiting")
        #expect(s.subActivity == nil, "主槽靜止 → subagent 事件被忽略（§2.5.1）")
        #expect(s.effectiveActivity == .waiting, "橘燈不會消失 —— 這才是這個測試的意圖")
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

    /// **系統性的欄位帶過來測試。**
    ///
    /// `merge` 用 `?? s.field` 或 `if let ... { s.field = ... }` 把 14 個欄位帶過來，
    /// 但原本只有 `model` 有專門的帶過來測試。其餘 13 個若哪天被寫成直接覆寫
    /// （`s.cwd = p.cwd`），一個不帶 `cwd` 的事件就會把它清成 nil，而沒有任何測試會紅。
    ///
    /// 這個測試先用一連串事件把每個「來自 payload」的欄位都填上非 nil 值，
    /// 斷言確實都填上了（否則後面就是 nil == nil，證明不了任何事），
    /// 再送一個什麼都不帶的最小事件，斷言全部存活。
    @Test("後續事件不得清掉先前累積的欄位")
    func fieldsCarryForward() {
        func p(_ json: [String: Any]) -> HookPayload {
            HookPayload(json: json.merging(["session_id": "s1"]) { a, _ in a })!
        }
        var s = merge(p(["hook_event_name": "SessionStart", "cwd": "/x/proj",
                         "source": "startup", "model": "claude-opus-5[1m]"]), into: nil)
        s = merge(p(["hook_event_name": "UserPromptSubmit",
                     "permission_mode": "default", "effort": ["level": "xhigh"]]), into: s)
        s = merge(p(["hook_event_name": "PostToolUse", "tool_name": "Bash",
                     "tool_input": ["description": "下載檔案"], "duration_ms": 1234]), into: s)
        s = merge(p(["hook_event_name": "Notification",
                     "notification_type": "idle_prompt", "message": "等你輸入"]), into: s)

        // 先證明測試資料真的填上了 —— 否則下面是 nil == nil，什麼都沒驗到
        #expect(s.cwd != nil && s.source != nil && s.model != nil
                && s.permissionMode != nil && s.effort != nil && s.mainTool != nil
                && s.toolDescription != nil && s.toolDurationMs != nil
                && s.notificationType != nil && s.notificationMessage != nil,
                "setup 必須把每個欄位都填上非 nil")

        let before = s
        // 一個什麼都不帶的最小事件
        s = merge(p(["hook_event_name": "PostToolBatch"]), into: s,
                  at: t0.addingTimeInterval(60))

        #expect(s.cwd == before.cwd)
        #expect(s.source == before.source)
        #expect(s.model == before.model)
        #expect(s.permissionMode == before.permissionMode)
        #expect(s.effort == before.effort)
        #expect(s.mainTool == before.mainTool)
        #expect(s.toolDescription == before.toolDescription)
        #expect(s.toolDurationMs == before.toolDurationMs)
        #expect(s.notificationType == before.notificationType)
        #expect(s.notificationMessage == before.notificationMessage)
        #expect(s.turnStartedAt == before.turnStartedAt)
        #expect(s.writtenAt == t0.addingTimeInterval(60), "只有時戳該變")
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

    @Test("使用者 Ctrl+C 中斷不計入 toolFailures —— 那是使用者的動作")
    func interruptIsNotAFailure() {
        let interrupted = HookPayload(json: [
            "hook_event_name": "PostToolUseFailure", "session_id": "s1",
            "tool_name": "Bash", "is_interrupt": true,
            "error": "Interrupted by user",
        ])!
        var s = merge(interrupted, into: nil)
        s = merge(interrupted, into: s)
        #expect(s.toolFailures == 0, "中斷兩次仍是 0 次失敗")
        #expect(s.mainActivity == .working)

        let real = HookPayload(json: [
            "hook_event_name": "PostToolUseFailure", "session_id": "s1",
            "tool_name": "Read", "is_interrupt": false,
            "error": "File does not exist",
        ])!
        s = merge(real, into: s)
        #expect(s.toolFailures == 1, "真正的失敗才計入")
        #expect(s.toolError == "File does not exist")
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

    /// **CodingKeys 完整性 gate。**
    ///
    /// 刻意把**每一個** stored property 都填上與預設值不同的值再 round-trip。
    /// 若只靠幾次 merge 產生的 snapshot（原本的寫法），沒被填到的欄位即使從
    /// `CodingKeys` 漏掉，round-trip 仍會相等 —— 測不出來。這是 optional 欄位
    /// 特別危險的地方：漏掉的 key 解碼成 nil，而原值本來就是 nil。
    @Test("JSON round-trip 保留每一個 stored property")
    func codableRoundTripCoversEveryField() throws {
        var s = SessionSnapshot(sessionID: "round-trip-1")
        s.schema              = 7
        s.hookEventName       = "PermissionRequest"
        s.writtenAt           = Date(timeIntervalSince1970: 1_788_628_111)
        s.pid                 = 4242
        s.pidStartedAt        = 1_757_352_011
        s.cwd                 = "/Users/you/專案 🚀/payments-api"
        s.permissionMode      = "default"
        s.effort              = "xhigh"
        s.model               = "claude-opus-5[1m]"
        s.source              = "startup"
        s.reason              = "prompt_input_exit"
        s.mainActivity        = .waiting
        s.mainTool            = "Bash"
        s.subActivity         = .working
        s.subTool             = "Grep"
        s.subAgentType        = "Explore"
        s.notificationType    = "idle_prompt"
        s.notificationMessage = "Claude is waiting for your input"
        s.lastMessage         = "全部完成"
        s.toolDescription     = "Download example.com to dl2.html"
        s.toolDurationMs      = 12_403
        s.toolError           = "File does not exist"
        s.turnStartedAt       = Date(timeIntervalSince1970: 1_788_628_000)
        s.subagents           = ["Explore": 2, "implementer": 1]
        s.toolFailures        = 3
        s.terminated          = true

        // 「每個欄位都不是預設值」這件事本身要被檢查，不能只寫在 doc-comment 裡。
        //
        // 這個 gate 曾經自己漏過欄位：宣稱涵蓋「每一個 stored property」，但
        // `toolError` 與 `schema` 從頭到尾沒被設值。實測把 `case toolError` 或
        // `case schema` 從 CodingKeys 移掉 —— 編譯照過（optional 有隱含 nil 預設值、
        // schema 有明確預設值），全套件 121 個測試無一變紅。
        //
        // 手寫的欄位清單會 drift，所以改用 `Mirror` 從型別本身推導：
        // 只要有任何 stored property 停在預設值，這裡就紅，並指名是哪一個。
        let blank = SessionSnapshot(sessionID: "blank")
        let mine = Array(Mirror(reflecting: s).children)
        let theirs = Array(Mirror(reflecting: blank).children)
        #expect(mine.count == theirs.count)
        for (a, b) in zip(mine, theirs) {
            #expect("\(a.value)" != "\(b.value)", """
                stored property `\(a.label ?? "?")` 沒被設成非預設值 —— 這個 gate 對它是盲的。
                把它從 CodingKeys 移掉不會有任何測試變紅。請在上面補一行設值。
                """)
        }

        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(SessionSnapshot.self, from: try enc.encode(s))
        #expect(back == s)

        // 額外確認：JSON 的 key 名都是 snake_case（檔案是人會讀的）
        let obj = try JSONSerialization.jsonObject(with: try enc.encode(s)) as? [String: Any]
        let keys = Set((obj ?? [:]).keys)
        for k in keys {
            #expect(k == k.lowercased(), "JSON key 應為 snake_case，但出現 \(k)")
        }
        #expect(keys.contains("main_activity") && keys.contains("tool_description")
                && keys.contains("notification_message") && keys.contains("pid_started_at"),
                "抽查幾個 snake_case key 確實存在")
    }

    @Test("merge 產生的 snapshot 也能 round-trip")
    func codableRoundTripFromMerge() throws {
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
    /// 最後一次 tool 失敗的訊息（`PostToolUseFailure` 的 `error`）。
    public var toolError: String?
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
        case toolError           = "tool_error"
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
        // 使用者按 Ctrl+C 中斷不算失敗 —— 那是使用者的動作。
        // `is_interrupt` 與 `error` 同在 `PostToolUseFailure` 上（實測）。
        if p.hookEventName == "PostToolUseFailure", !p.isInterrupt { s.toolFailures += 1 }
        if let e = p.toolError { s.toolError = e }
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

Expected: **`subagentRecordedWhileWorking` 與 `stopClearsSubSlot` 必須 FAIL**。

> 註：這裡原本寫 `subagentCannotMaskWaiting` 與 `mainToolNotOverwritten`，那是**錯的**
> （T05 implementer 實測後回報）。原因：前者的情境裡主槽**已經是 waiting（靜止態）**，
> §2.5.1 的 guard 在觸及「單槽 vs 分槽」那一行之前就 `break` 了，所以這個 mutation
> 在該測試裡不可觀察；後者從不斷言 `mainActivity`，而它的情境裡 `mainActivity` 恰好
> 已等於 subagent 的效果值（`working`），用同一個值覆寫看不出差別。
>
> 性質仍然被覆蓋 —— 只是由那兩個**直接斷言 `subActivity`** 的測試覆蓋。
> 這是「mutation 有牙齒、但我指名的咬合點不對」的實例：mutation 表的測試名對應
> 必須用實測驗證，不能靠讀碼推。
確認 RED 後 `cp /tmp/aura-mut.bak Sources/AuraCore/MergeRules.swift   # 見 Global Constraints 的標準程序` 還原，再跑一次確認全綠。

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
      public let model: String?               // 只有 SessionStart / PostModelSwitch 提供
      public let activity: Activity           // max(main, sub)
      public let mainActivity: Activity, subActivity: Activity?
      public let currentTool: String?, subagentTool: String?   // subagentTool 形如 "Explore → Grep"
      public let toolDurationMs: Int?
      public let turnStartedAt: Date?
      public let subagents: [String: Int], toolFailures: Int
      public let lastMessage: String?, errorType: String?
      public let toolError: String?          // 最後一次真正的 tool 失敗訊息
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
    /// 模型名稱。只有 `SessionStart`（與 `PostModelSwitch` 的 `to_model`）提供，
    /// 由 `MergeRules` 帶過來。
    ///
    /// 註：早期版本因為誤判「payload 不帶 model」而移除過這個欄位，後來實測推翻。
    /// 補回時只補了 `HookPayload` 與 `SessionSnapshot`，忘了輸出端 —— 值存得到卻
    /// 傳不出去，面板拿不到。修一條資料流要走完 payload → 檔案 → state → UI 四段。
    public let model: String?
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
    /// 最後一次真正的 tool 失敗訊息（使用者中斷不算，見 `MergeRules`）。
    public let toolError: String?
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
            model: s.model,
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
            toolError: s.toolError,
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
Expected: 全部 PASS（**12 個測試**）　<!-- 原寫 13；implementer 清點 @Test 實為 12 -->

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
      public mutating func remove(_ id: String)          // 檔案消失時移除
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
                     permissionMode: nil, effort: nil, model: nil,
                     activity: a, mainActivity: a, subActivity: nil,
                     currentTool: nil, subagentTool: nil, toolDurationMs: nil,
                     turnStartedAt: nil, subagents: [:], toolFailures: 0,
                     lastMessage: nil, errorType: nil, toolError: nil,
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

    @Test("remove 移除 session 與其確認狀態")
    func removeClearsBoth() {
        var r = SessionRegistry()
        r.upsert(state("a", .done, live: false))
        _ = r.acknowledgeAll()
        r.upsert(state("a", .working))
        r.remove("a")
        #expect(r.states["a"] == nil)
        #expect(!r.isAcknowledged("a"), "確認狀態也要清掉，否則同 id 重建後會被誤判為已看過")
        #expect(r.visible.isEmpty)
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

    /// 移除一個 session。
    ///
    /// 用於「狀態檔已不存在」的情況：檔案是狀態的唯一真實來源，沒有檔案就沒有 session。
    /// 若該 session 其實還活著，下一個 hook 事件會把它重建回來。
    public mutating func remove(_ id: String) {
        states[id] = nil
        acknowledged.remove(id)
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
Expected: 全部 PASS（**15 個測試**）　<!-- 原寫 11；implementer 清點 @Test 實為 15 -->

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
                     permissionMode: nil, effort: nil, model: nil,
                     activity: a, mainActivity: a, subActivity: nil,
                     currentTool: nil, subagentTool: nil, toolDurationMs: nil,
                     turnStartedAt: nil, subagents: [:], toolFailures: 0,
                     lastMessage: nil, errorType: nil, toolError: nil,
                     liveness: live ? .alive(pid: 1) : .ended,
                     updatedAt: Date(timeIntervalSince1970: 1_788_628_000))
    }

    @Test("2 個 working + 1 個 error → error（使用者原始舉例）")
    func twoWorkingOneErrorIsError() {
        // `.error` 刻意**不放在陣列首尾** —— 放在尾端時，「最後一個贏」的錯誤
        // 實作會巧合給出正確答案，這條測試就對 D1 的核心 mutation 失去鑑別力
        // （實測：mutation 下只有 `orderIndependent` 變紅，這條照樣綠）。
        let r = policy.aggregate([state("a", .working), state("b", .error), state("c", .working)])
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
        // try 要在 #expect 之外求值：巨集展開後會把引數包進 autoclosure，
        // 裡面的 try 變成「call can throw, but it is not marked with 'try'」。
        let root = try makeRoot()
        #expect(SnapshotIO.read(sessionID: "nope", root: root) == nil)
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

    /// 三個過濾條件各有一個**只有它能擋**的樣本 —— 否則某個條件移除了測試還是綠的。
    /// 實測過：原本只放一個叫 `sub` 的目錄，光靠副檔名就擋掉了，
    /// `isRegularFile` 與 `isSafeSessionID` 兩個過濾都是空轉。
    @Test("allSessionIDs 的三個過濾條件各自都有牙齒")
    func allSessionIDsFilters() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "s1", root: root) { _ in self.snap("s1", .done) }

        // 只有副檔名過濾擋得住
        try Data("x".utf8).write(to: root.appendingPathComponent("README.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        // 只有 isRegularFile 擋得住：一個**目錄**叫 dir.json
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dir.json"),
                                                withIntermediateDirectories: true)
        // 只有 isSafeSessionID 擋得住：檔名 stem 含空白，是合法檔名但不是合法 session id
        try Data("{}".utf8).write(to: root.appendingPathComponent("bad name.json"))

        #expect(SnapshotIO.allSessionIDs(root: root) == ["s1"],
                "多出來的是：\(SnapshotIO.allSessionIDs(root: root))")
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
Expected: 全部 PASS（**14 個測試**，實測）

- [ ] **Step 5: Mutation 驗證 —— flock 是否真的有牙齒**

手動把 `update` 裡的 `flock(fd, LOCK_EX)` 那行連同 `defer { flock(fd, LOCK_UN) }` 註解掉，
執行 `swift test --filter SnapshotIOTests`。

Expected: `concurrentUpdatesDoNotLoseCounts` **必須 FAIL**（累加數會少於 320）。還原後全綠。

> 已實測：移除鎖後 3/3 次都紅，320 次累加只剩 9 / 22 / 29 次。不需要調高 `iterations`。

- [ ] **Step 5b: Mutation 驗證 —— `allSessionIDs` 的三個過濾條件**

分別把 `allSessionIDs` 的 `isRegularFile` 檢查、以及 `.filter(isSafeSessionID)` 各自移除一次。

Expected: 兩次都必須讓 `allSessionIDsFilters` **FAIL** —— 移除 `isRegularFile` 會多出 `"dir"`，
移除 `isSafeSessionID` 會多出 `"bad name"`。兩者在生產上的後果都是**幽靈 session**：
面板列出一個 `read` 永遠回 nil 的 id。

> 這條測試的前一版只放了一個叫 `sub` 的目錄，光靠副檔名過濾就擋掉了，
> 導致另外兩個過濾條件移除後測試照樣全綠 —— 空轉的守衛比沒有守衛更糟，
> 因為它製造信心。三個條件各需要一個**只有它擋得住**的樣本。

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

    @Test("端到端：主槽 waiting 時 subagent 事件不得改變 activity")
    func subagentDoesNotMaskWaitingEndToEnd() throws {
        let root = try makeRoot()
        _ = try run(#"{"hook_event_name":"PermissionRequest","session_id":"cli3","tool_name":"Bash"}"#, root: root)
        _ = try run(#"{"hook_event_name":"PostToolUse","session_id":"cli3","tool_name":"Write","agent_id":"a1","agent_type":"Explore"}"#, root: root)
        let s = try #require(SnapshotIO.read(sessionID: "cli3", root: root))
        #expect(s.mainActivity == .waiting, "端到端也必須保住 waiting")
        #expect(s.subActivity == nil, "主槽靜止 → 忽略 subagent（§2.5.1）")
        #expect(s.effectiveActivity == .waiting)
    }

    @Test("端到端：主槽 working 時 subagent 事件寫進 sub 槽")
    func subagentGoesToSubSlotWhenWorking() throws {
        let root = try makeRoot()
        _ = try run(#"{"hook_event_name":"PreToolUse","session_id":"cli3b","tool_name":"Bash"}"#, root: root)
        _ = try run(#"{"hook_event_name":"PostToolUse","session_id":"cli3b","tool_name":"Grep","agent_id":"a1","agent_type":"Explore"}"#, root: root)
        let s = try #require(SnapshotIO.read(sessionID: "cli3b", root: root))
        #expect(s.mainActivity == .working)
        #expect(s.subActivity == .working)
        #expect(s.subTool == "Grep")
        #expect(s.subAgentType == "Explore")
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

    @Test("stdin 直接關閉（沒有任何輸入）仍 exit 0")
    func closedStdin() throws {
        let root = try makeRoot()
        let p = Process()
        p.executableURL = try Self.binaryURL()
        p.environment = ProcessInfo.processInfo.environment.merging(
            ["AGENTAURA_ROOT": root.path]) { _, new in new }
        let inPipe = Pipe(), out = Pipe(), err = Pipe()
        p.standardInput = inPipe; p.standardOutput = out; p.standardError = err
        try p.run()
        try inPipe.fileHandleForWriting.close()   // 立刻關閉，不寫任何 bytes
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        #expect(o.isEmpty && e.isEmpty)
    }

    /// **行為式強制「任何錯誤都靜默 exit 0」**，取代靠人讀程式碼確認沒有
    /// force unwrap / `try!` / `fatalError`。
    ///
    /// 用 regex 掃原始碼找 `!` 的誤報率太高（`!=`、`!x`、字串裡的 `!` 都會中）。
    /// 改成把真實 payload 系統性破壞後餵進去 —— Swift runtime trap 會以 signal
    /// 中止（terminationStatus 非 0），所以行為測試抓得到，而且不依賴我對程式碼的閱讀。
    @Test("真實 payload 的系統性破壞版本全部 exit 0 且無輸出")
    func fuzzedRealPayloadsAreSilent() throws {
        let root = try makeRoot()
        let reals = try Fixtures.rawEvents(named: "round2")
        var cases: [(String, Data)] = []

        for (i, json) in reals.enumerated() where i % 4 == 0 {   // 取樣，控制測試時間
            let full = try Fixtures.jsonData(json)

            // (1) 在多個比例處截斷
            for frac in [0.1, 0.35, 0.6, 0.9] {
                cases.append(("truncate-\(frac)-\(i)", full.prefix(Int(Double(full.count) * frac))))
            }
            // (2) 逐一移除每個 key
            for key in json.keys {
                var m = json; m.removeValue(forKey: key)
                cases.append(("drop-\(key)-\(i)", try Fixtures.jsonData(m)))
            }
            // (3) 逐一把每個值換成型別不符的東西
            for key in json.keys {
                for wrong: Any in [NSNull(), 42, ["nested": ["deep": [1, 2, 3]]], [1, 2, 3]] {
                    var m = json; m[key] = wrong
                    cases.append(("retype-\(key)-\(i)", try Fixtures.jsonData(m)))
                }
            }
        }

        #expect(cases.count > 200, "破壞案例數應有規模，實際 \(cases.count)")

        for (label, data) in cases {
            let r = try run(String(decoding: data, as: UTF8.self), root: root)
            #expect(r.exitCode == 0, "\(label) 的 exit code 是 \(r.exitCode)，不是 0")
            #expect(r.stdout.isEmpty, "\(label) 有 stdout：\(r.stdout.prefix(120))")
            #expect(r.stderr.isEmpty, "\(label) 有 stderr：\(r.stderr.prefix(120))")
        }

        // 破壞過程不得在狀態目錄產生非預期檔案
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for f in files {
            #expect(f.hasSuffix(".json"), "狀態目錄出現非 .json 檔：\(f)")
            #expect(SnapshotIO.isSafeSessionID(String(f.dropLast(5))),
                    "狀態目錄出現不安全的檔名：\(f)")
        }
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
Expected: build 成功；全部 PASS（**13 個 `@Test` 宣告**，其中 `malformedInputIsSilent`
內含 13 個參數化案例）　<!-- 原寫 10；implementer 清點回報實為 13 -->

> **Step 2 的 RED 型態與描述不同（已知，仍是有效 RED）**：這裡原本預期 `swift build`
> 因缺 `main.swift` 而失敗，但 T09 已建立 2 行 placeholder `main.swift`（純註解）
> 以滿足 `Package.swift` 的 `executableTarget` 宣告，所以 build 會成功。
> 改用 `swift test --filter AuraHookCLITests` 驗證失敗時，實際看到的是黑箱測試
> 對 placeholder 執行檔寫入已關閉的 stdin pipe 導致 **SIGPIPE（signal 13）崩潰**，
> 而非某條測試斷言失敗。這仍證明 Step 1 的測試在測真正的執行檔行為。

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

    /// 收集到的事件。用 actor 是為了讓逾時分支也能報出「收到了哪些」。
    actor Collected {
        private var items: [SessionSnapshot] = []
        func add(_ s: SessionSnapshot) -> [SessionSnapshot] { items.append(s); return items }
        func all() -> [SessionSnapshot] { items }
    }

    /// 從 AsyncStream 收集事件，直到滿足條件或**真的**逾時。
    ///
    /// 前一版寫成 `for await { got.append(); if predicate || Date() > deadline { break } }`,
    /// deadline 只在收到元素之後才檢查 —— 零元素時 `for await` 永久 block，
    /// `timeout` 參數形同虛設。實測：把 `FSEventStreamStart` 移除後，這個 suite
    /// 不是變紅而是**掛住**（90s 強殺、零輸出），CI 上會變成 hung job 而非失敗。
    /// 逾時必須由一條獨立的 task 計時並取消收集端。
    func collect(_ source: HookFileSource,
                 until predicate: @escaping @Sendable ([SessionSnapshot]) -> Bool,
                 timeout: TimeInterval = 5) async -> [SessionSnapshot] {
        let box = Collected()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await snap in source.snapshots {
                    if predicate(await box.add(snap)) { break }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            }
            await group.next()      // 誰先完成就結束
            group.cancelAll()
        }
        return await box.all()
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
        let root = try makeRoot()
        #expect(HookFileSource(root: root).bootstrap().isEmpty)
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

        // 用有界的 `collect`，不要直接 `for await`。
        //
        // 前一版是 `for await s in source.snapshots { got.append(s) }`，靠
        // 「stop() 會 finish() continuation，所以迭代立刻結束」來終止 ——
        // 但那正是這條測試的**被測物**。實測：把 stop() 裡的 finish() 拿掉，
        // 這條測試不是變紅而是掛住（120s 強殺）。
        // 拿被測物當迴圈終止條件，等於測試在假設結論成立。
        let got = await collect(source, until: { !$0.isEmpty }, timeout: 1)
        #expect(!got.contains { $0.sessionID == "after-stop" })
    }

    @Test("stop 是終局：再 start 也不會復活（釘死契約，不是缺陷）")
    func stopIsTerminal() async throws {
        let root = try makeRoot()
        let source = HookFileSource(root: root)
        source.start()
        source.stop()
        source.start()                      // 嘗試復活
        defer { source.stop() }

        Task { try? self.write("revived", .working, to: root) }
        let got = await collect(source, until: { !$0.isEmpty }, timeout: 1)
        #expect(got.isEmpty, """
            契約：`snapshots` 是 init 建立的單一 AsyncStream，stop() 會 finish() 它，
            之後 start() 不會有任何事件。生產上只在 applicationWillTerminate 呼叫一次，
            所以這是刻意的契約。若這條變紅，表示有人讓 start() 可以復活 —— 那是好事，
            但 AppDelegate 的生命週期假設要一起改，別讓它靜默地變成兩套語意。
            """)
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
            // 未設 kFSEventStreamCreateFlagUseCFTypes，故 eventPaths 是 char **。
            // 用 assumingMemoryBound 而非 unsafeBitCast —— 後者從 raw pointer 硬轉型別，
            // 編譯器會警告可能造成 undefined behavior（實測 Swift 6.3.3 確實會警告）。
            let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
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

    /// **stop() 是終局。** `snapshots` 是 `init` 建立的單一 AsyncStream，
    /// 這裡 `finish()` 之後再 `start()` 也不會有任何事件 —— source 已經聾了。
    /// 生產上只在 `applicationWillTerminate` 呼叫一次，故這是刻意的契約；
    /// `stopIsTerminal` 測試把它釘死，未來若有人加「休眠後重啟」會立刻紅。
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
Expected: 全部 PASS（**11 個測試**，實測 0.140s）

- [ ] **Step 6: Mutation 驗證（三個，全部實測過）**

**6a — `bootstrap()` 改成 `return []`**
Expected: `bootstrapReadsExisting` 與 `bootstrapSkipsCorrupt` **必須 FAIL**。

**6b — 移除 `FSEventStreamStart(s)`（連同 `FSEventStreamSetDispatchQueue`）**
Expected: `detectsNewFile`、`detectsModification`、`detectsManySessions` **必須 FAIL**，
且各在 ~5s（逾時）而非無限等待。實測：3 紅、suite 20.6s 結束。

> 這一條是這個 task 最重要的 mutation：它證明那三條測試真的走 FSEvents，
> 而不是被別的路徑餵飽。**前提**：`collect` 必須是有界的（見 Step 1 的註解）——
> 用原本那版 `collect`，同樣的 mutation 會讓 suite **掛住**（實測 90s 強殺、
> 零輸出），CI 上是 hung job 而不是紅燈。

**6c — 移除 `stop()` 裡的 `continuation?.finish()` 與 `continuation = nil` 兩行**
Expected: `stopIsTerminal` **必須 FAIL**（會收到 `revived`），0.02s 內結束。

> **必須是兩行一起移除。** 這裡原本只寫「移除 `continuation?.finish()`」，那是錯的
> （T10-T12 的 implementer 實測後回報，我確認）：契約實際是由 `continuation = nil`
> 保證的 —— 它讓之後的 `continuation?.yield(snap)` 恆為 no-op。`finish()` 唯一的
>作用是讓**已經在跑**的 `for await` 消費者提早結束；只移除它的話，`stopIsTerminal`
> 裡新開的 `collect()` 仍然收不到事件（只是從 0.001s 變成等到 timeout 的 ~1.05s），
> 斷言照樣成立。我先前「實測會紅」的紀錄，實際跑的是**兩行一起移除**的版本。
>
> **衍生缺口（已知，刻意接受）**：因此 `stopIsTerminal` 對「忘記發出 `finish()`
> 訊號」這件事**沒有牙齒**。要蓋到那個性質，測試得換一種設計：先啟動一個持續
> 消費 `snapshots` 的背景 task，再 `stop()`，斷言那個迴圈會在有界時間內自然結束
> （而不是新開一個 `collect()` 檢查有沒有收到新事件）。
> 目前生產上唯一的消費者是 `PipelineGraph`，它在 `stop()` 之後就不再被使用，
> 所以漏發 `finish()` 的實際後果只是一條 task 留在 await 上直到 app 結束 ——
> 記在此處，交最終 review 決定要不要補。
>
> 這一條釘的是「stop() 是終局」的契約。同樣需要有界的 `collect`：
> `stopEndsStream` 原本直接 `for await`，靠「stream 已 finish」終止迴圈 ——
> 而那正是被測物本身，拿被測物當終止條件，mutation 下就是掛住（實測 120s 強殺）。
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
- Create: `.claude-plugin/marketplace.json`（本地安裝用；`claude plugin install` 只吃 marketplace）
- Create: `Sources/AuraHookFile/PipelineGraph.swift`（composition root，無 UI）
- Test: `Tests/AuraCoreTests/PluginWiringTests.swift`（plugin 設定與平台契約）
- Test: `Tests/AuraCoreTests/CompositionRootTests.swift`（物件圖接線）
- Test: `Tests/AuraCoreTests/EndToEndWiredGateTests.swift`

**Interfaces:**
- Consumes: 全部前述元件
- Produces:
  ```swift
  public final class PipelineGraph: @unchecked Sendable {
      public init(root: URL, liveness: LivenessProbing, policy: AggregatePolicy, source: EventSource)
      public static func production(root: URL = SnapshotIO.defaultRoot) -> PipelineGraph
      private(set) var registry: SessionRegistry   // **internal** —— 外部讀取繞過 lock
      public var visibleSessions: [SessionState] { get }   // 上鎖，對外唯一途徑
      public var iconState: IconState { get }
      public var onIconStateChange: ((IconState) -> Void)?
      public func start()          // bootstrap + 開始消費 snapshots
      public func stop()
      public func acknowledgeAll() // 刪除已結束且已確認的狀態檔
      public func refreshLiveness()
  }
  ```

- [ ] **Step 1: 建立 plugin manifest、marketplace manifest 與 hooks 註冊**

> **這一段的每個位元組都經 `claude plugin validate` 驗證通過（零 error 零 warning）。**
> 先前的版本有兩個會讓產品**完全靜默失效**的錯誤，而 Step 2 的 wired-gate 測試
> 當時**全部綠燈** —— 因為那些測試比對的是自己從檔案讀出來的字典，不是平台的契約：
>
> 1. `plugin.json` 的 `author` 寫成字串。validator：`author: Invalid input`。
> 2. `hooks.json` 把事件直接放在**最外層**。validator：
>    `PreToolUse/PermissionRequest is declared at the top level, outside the "hooks" object`
>    —— **整個 plugin 的 hook 一個都不會載入**。
>
> 這就是 tested ≠ wired 的教科書案例，也是為什麼 Step 2 多了一條
> 「跑官方 validator」的測試：**手寫的檢查只能驗我以為的契約**。

```bash
mkdir -p plugin/.claude-plugin plugin/hooks .claude-plugin
cat > plugin/.claude-plugin/plugin.json <<'EOF'
{
  "name": "agentaura",
  "version": "0.1.0",
  "description": "把 Claude Code 的運行狀態顯示在 macOS menu bar",
  "author": {
    "name": "AgentAura",
    "email": ""
  }
}
EOF
```

`hooks.json` —— 事件全部包在最外層的 `"hooks"` 物件裡，**全部 `async: true`**
（Global Constraint），command 路徑加引號（官方 plugin 的慣例；`$HOME` 含空白時
才不會裂開）。`Notification` 加 matcher 只收需要使用者的 6 種型別作為縱深防禦，
但 payload 內的型別檢查（`EventMapping.notificationEffect`）才是正確性保證。

```bash
cat > plugin/hooks/hooks.json <<'EOF'
{
  "description": "把 Claude Code 的運行狀態寫進 ~/.agentaura/sessions/，供 menu bar app 讀取",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "PostToolBatch": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "PermissionDenied": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "PostModelSwitch": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "Elicitation": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "ElicitationResult": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt|agent_needs_input|elicitation_dialog|elicitation_url_dialog|agent_completed",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
            "async": true
          }
        ]
      }
    ]
  }
}
EOF
```

**本地 marketplace manifest。** `claude plugin install` **只從 marketplace 安裝**
（`plugin@marketplace`），**不吃本地目錄路徑** —— 實測 `claude plugin install --help`：
「Install a plugin from available marketplaces」。本地安裝的正確途徑是
`claude plugin marketplace add <path>`（`marketplace add` 明文支援 URL / **path** /
GitHub repo）再 install。所以 repo 根目錄需要這個檔：

```bash
cat > .claude-plugin/marketplace.json <<'EOF'
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "agentaura",
  "description": "AgentAura 的本地 marketplace —— 自用安裝用，不上架",
  "owner": { "name": "AgentAura", "email": "" },
  "plugins": [
    {
      "name": "agentaura",
      "description": "把 Claude Code 的運行狀態顯示在 macOS menu bar",
      "source": "./plugin",
      "category": "development"
    }
  ]
}
EOF
```

- [ ] **Step 2: 寫 plugin 設定的 wired-gate 測試（先寫、必失敗）**

> 這一段獨立成 `Tests/AuraCoreTests/PluginWiringTests.swift`。與 Step 4 合在同一個檔
> 會是 321 行、超過測試檔 300 行上限（那個上限正是 `IsolationTests.fileLengthLimit`
> 在把關的）。責任本來就不同：這一份驗**平台契約**，Step 4 那份驗**物件圖接線**。

這組測試把 `hooks.json` 當**生產設定**驗，不是當文件看。

```swift
// Tests/AuraCoreTests/PluginWiringTests.swift
//
// 從 CompositionRootTests.swift 拆出來 —— 合併後 321 行，超過測試檔 300 行上限，
// 而那個上限正是 IsolationTests.fileLengthLimit 在把關的。責任也本來就不同：
// 這一份驗的是 **plugin 設定與平台契約**，那一份驗的是 **物件圖的接線**。
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

    static func hooksFile() throws -> [String: Any] {
        let url = repoRoot().appendingPathComponent("plugin/hooks/hooks.json")
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// 事件對照表在**內層**的 `"hooks"` 物件裡。
    ///
    /// 這個 `["hooks"]` 是被 `claude plugin validate` 教出來的：先前的版本把事件
    /// 直接放在最外層，validator 回報
    /// 「PreToolUse/... is declared at the top level, outside the "hooks" object」——
    /// 整個 plugin 的 hook 一個都不會載入，而本檔案的每一條測試當時**全綠**，
    /// 因為它們比對的是自己讀出來的那份字典，不是平台的契約。
    static func hooksJSON() throws -> [String: Any] {
        try #require(try hooksFile()["hooks"] as? [String: Any],
                     "hooks.json 的事件必須包在最外層的 \"hooks\" 物件裡")
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
        let all = try Self.entries()
        #expect(!all.isEmpty)
        for (event, h) in all {
            let cmd = try #require(h["command"] as? String)
            // 官方 plugin 的慣例是把路徑加引號 —— $HOME 含空白時才不會裂開。
            #expect(cmd == "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
                    "\(event) 的 command 不一致：\(cmd)")
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
        // 只取 `.first` 而不驗長度，等於對「未來多加一個 matcher 區塊」視而不見。
        #expect(notif.count == 1, "Notification 有 \(notif.count) 個 matcher 區塊，這條測試只驗第一個")
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

    /// **結構 gate。** 事件不得出現在最外層。
    @Test("hooks.json 的事件包在 \"hooks\" 物件裡，最外層沒有裸事件名")
    func hooksAreNestedUnderHooksKey() throws {
        let file = try Self.hooksFile()
        #expect(file["hooks"] != nil, "缺少最外層的 \"hooks\" 物件")
        let leaked = EventMapping.handledEvents.filter { file[$0] != nil }
        #expect(leaked.isEmpty, """
            這些事件被放在最外層，plugin 的 hook 一個都不會載入：\(leaked.sorted())
            `claude plugin validate` 會說 "declared at the top level, outside the \"hooks\" object"。
            """)
    }

    /// **平台契約 gate —— 用官方 validator，不用手寫的假設。**
    ///
    /// 手寫的檢查只能驗我以為的契約；`claude plugin validate` 驗的是平台真正的契約。
    /// 這個 gate 抓到過兩個手寫檢查完全看不見的錯：`author` 必須是物件而非字串，
    /// 以及事件必須包在 `"hooks"` 物件裡（否則整個 plugin 的 hook 都不載入）。
    ///
    /// **必須要求零 warning**，不能只看 exit code：validator 對
    /// 「unknown hook event」、「no type」、「async 型別錯」都只給 **warning**
    /// 並仍然 `exit 0`，而每一個 warning 都寫著 **entry ignored at runtime** ——
    /// 也就是一個靜默的死 hook。實測確認 exit code 在有 warning 時仍是 0。
    /// **平台契約 gate —— 用官方 validator，而且用官方的 `--strict`。**
    ///
    /// 手寫的檢查只能驗我以為的契約；`claude plugin validate` 驗的是平台真正的契約。
    /// 這個 gate 抓到過兩個手寫檢查完全看不見的錯：`author` 必須是物件而非字串，
    /// 以及事件必須包在 `"hooks"` 物件裡（否則整個 plugin 的 hook 都不載入）。
    ///
    /// **為什麼是 `--strict` 而不是自己比對輸出文字**：validator 對
    /// 「unknown hook event」、「no type」、「async 型別錯」只給 **warning** 並仍然
    /// `exit 0`，而每個 warning 都寫著 **entry ignored at runtime** —— 一個靜默的死 hook。
    /// 這裡原本寫 `!out.contains("warning")`，功能上碰巧對，但比對的是**人類可讀文字**：
    /// CLI 改個措辭、加個色碼、做在地化，這條檢查就會悄悄失真而測試不知情。
    /// 官方提供了 `--strict`（"Treat warnings as errors (exit 1)"），那是穩定契約。
    /// `--json` 只是為了讓失敗訊息能指名是哪個檔、哪一條。
    @Test("claude plugin validate --strict 對 plugin 與 marketplace 都通過")
    func officialValidatorIsClean() throws {
        for target in ["plugin", "."] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["claude", "plugin", "validate", "--strict", "--json", target]
            task.currentDirectoryURL = Self.repoRoot()
            let pipe = Pipe()
            task.standardOutput = pipe; task.standardError = pipe
            try task.run()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            task.waitUntilExit()

            // 從 JSON 撈出所有 errors / warnings，讓失敗訊息可讀
            var problems: [String] = []
            if let data = out.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var buckets: [[String: Any]] = []
                if let m = obj["manifest"] as? [String: Any] { buckets.append(m) }
                buckets += (obj["contents"] as? [[String: Any]]) ?? []
                for b in buckets {
                    for kind in ["errors", "warnings"] {
                        for item in (b[kind] as? [[String: Any]]) ?? [] {
                            problems.append("\(kind): \(item["message"] as? String ?? "\(item)")")
                        }
                    }
                }
            }
            #expect(task.terminationStatus == 0, """
                claude plugin validate --strict \(target) 失敗（exit \(task.terminationStatus)）。
                每個 warning 都代表一個「entry ignored at runtime」的死 hook：
                \(problems.isEmpty ? out : problems.joined(separator: "\n"))
                """)
            #expect(problems.isEmpty, "validate \(target) 有問題：\(problems.joined(separator: "\n"))")
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
@testable import AuraHookFile

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

    @Test("狀態檔被外部刪除後，refreshLiveness 移除該 session")
    func refreshLivenessDropsDeletedFiles() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "gone1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "gone1")
            s.mainActivity = .waiting
            s.pid = getpid(); s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
            s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        #expect(g.iconState.activity == .waiting)

        // 模擬使用者手動清理：rm ~/.agentaura/sessions/*
        try SnapshotIO.delete(sessionID: "gone1", root: root)
        g.refreshLiveness()
        #expect(g.iconState.activity == .idle, "檔案消失 → 不得留下幽靈 session")
    }

    @Test("狀態目錄被整個刪除後，refreshLiveness 重建它")
    func refreshLivenessRecreatesRoot() throws {
        let root = try makeRoot()
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        try FileManager.default.removeItem(at: root)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        g.refreshLiveness()
        #expect(FileManager.default.fileExists(atPath: root.path),
                "目錄不存在會讓後續 hook 寫入失敗（aura-hook 會靜默放棄）")
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

    /// **刻意不是 `public`。**
    ///
    /// 所有寫入都在 `lock` 下，但一個 `public` 的裸屬性讓外部可以**繞過 lock 直接讀**，
    /// 與 `ingest()` 的鎖內寫入形成未同步的並發存取 —— `@unchecked Sendable` 的承諾
    /// 就只兌現了一半。實證：面板的 `refreshPanel()` 原本寫 `graph.registry.visible`，
    /// 正是這種讀取。收成 `internal` 之後，App target（只 `import AuraHookFile`）
    /// 拿不到它，被迫走下面那個上鎖的 `visibleSessions`；測試用 `@testable` 仍可存取。
    private(set) var registry = SessionRegistry()

    /// 面板要列的 session。**上鎖**讀取 —— 這是外部取得 registry 內容的唯一途徑。
    public var visibleSessions: [SessionState] {
        lock.lock(); defer { lock.unlock() }
        return registry.visible
    }
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
        // 目錄若被整個刪掉（例如使用者手動清理），重建它 —— 否則後續 hook 寫入會失敗。
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for id in ids {
            guard let snap = SnapshotIO.read(sessionID: id, root: root) else {
                // 檔案已不存在。檔案是狀態的唯一真實來源，沒有檔案就沒有 session。
                // 若該 session 其實還活著，下一個 hook 事件會重建它。
                // 不處理這條會讓外部刪檔（rm ~/.agentaura/sessions/*）後
                // 面板永遠顯示那些幽靈 session。
                lock.lock(); registry.remove(id); lock.unlock()
                continue
            }
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
Expected: 全部 PASS（**7 個測試**）　<!-- 原寫 5；清點 @Test 實為 7 -->

- [ ] **Step 7: 寫端到端 wired-gate（不 mock 任何一層）**

```swift
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

        // `error` 刻意**先發**，不放在最後。
        //
        // 原本的順序是 working、working、error —— error 剛好是最後一個事件，
        // 所以「last-write-wins」的錯誤實作在這個順序下也會給出 `.error`，
        // 這條端到端測試因此無法單獨排除那個替代假說。
        // 把 error 移到最前面，last-write-wins 會得到 `.working`，測試就有鑑別力了。
        // （同一招在 T09 的 `twoWorkingOneErrorIsError` 用過 —— 固定測資的
        // 元素位置會決定一個 mutation 是否可觀察。）
        try fireHook(#"{"hook_event_name":"StopFailure","session_id":"e1","reason":"overloaded_error"}"#, root: root)
        try fireHook(#"{"hook_event_name":"PreToolUse","session_id":"w1","tool_name":"Bash"}"#, root: root)
        try fireHook(#"{"hook_event_name":"PreToolUse","session_id":"w2","tool_name":"Read"}"#, root: root)

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

        // 必須等到 SessionEnd 真的處理完（liveCount 歸零），不能只等 activity == .done：
        // Stop 本身就已經把 activity 設成 .done，但那時 liveness 仍是 .alive
        // （pid 是這個測試行程本身，一直活著）。在高併發下（跑整個 suite 而非只跑
        // 這一條）FSEvents 會把 Stop / SessionEnd 兩次寫入拆成兩個獨立事件，
        // 只等 activity == .done 會在 SessionEnd 事件抵達前提早返回，導致下面的
        // acknowledgeAll 抓不到「已結束」而不會刪檔——實測重現過這個 flake。
        let afterEnd = await wait(for: graph) { $0.activity == .done && $0.liveCount == 0 }
        #expect(afterEnd.activity == .done, "整夜 pipeline 跑完、terminal 收掉，早上仍看得到綠燈")
        #expect(afterEnd.liveCount == 0, "SessionEnd 必須被處理過，session 才算真正結束")

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

> 用 Global Constraints 的標準程序（`cp` 備份 → 手動編輯 → 看紅 → `cp` 還原），
> **不要用 `sed`**。這一段先前寫成 `sed -i.bak` + `mv`，與 Global Constraints
> 自相矛盾；已改正。

**9a — command 路徑打錯**（`/bin/aura-hook` → `/bin/aura-hook-typo`，共 **19 處**）
Expected: `allHooksPointAtAuraHook` **必須 FAIL**。
這一條擋的是 前一個專案 留下 7 個死 hook 的失效方式：路徑錯一個字，整個產品
靜默失效而所有單元測試照樣全綠。

**9b — 把任一個 hook 的 `async` 改成 `false`**
Expected: `allHooksAreAsync` **必須 FAIL**，訊息指名是哪個 event。
實測輸出：`↳ SessionStart 的 hook 缺少 async: true`。

**9c — 從 `hooks.json` 刪掉 `"Elicitation"` 這一整個 key**
Expected: `registeredEventsMatchHandledEvents` **必須 FAIL**，
訊息為 `↳ 有映射卻沒註冊（對照表是死碼）：["Elicitation"]`。

> **這是三個裡最重要的一個，因為它是實證發生過的 bug**：`Elicitation` 映射到
> `waiting` 卻沒註冊，「MCP server 在等你輸入」那個狀態永遠收不到，而所有
> 單元測試全綠。source-derived 雙向等式就是為這件事存在的 —— 9c 驗的是
> 那個 gate 真的會咬，不只是寫得漂亮。

**9d — `entries()` 改成 `return []`**
Expected: `allHooksAreAsync` 與 `allHooksPointAtAuraHook` **兩條都必須 FAIL**
（兩者都有 `#expect(!all.isEmpty)` 護欄）。

> 實測記錄：`allHooksPointAtAuraHook` 原本**沒有**那行護欄，於是這個 mutation 下
> 它**空轉通過** —— 一個 `for` 迴圈跑零次，裡面的斷言一次都不執行。
> 已在 Step 2 的測試碼補上護欄。這種「零樣本恆綠」是本專案已中過七次的那族缺陷。

```bash
swift test 2>&1 | tail -5    # 四個 mutation 全部還原後，必須全綠
```

另外手動驗一次：把 `PipelineGraph.production` 的 `liveness:` 改成 `StubLiveness(table: [:])`，
`productionGraphIsWired` 必須 FAIL —— 這條擋的是「production 用了測試替身」這類接線錯誤。

- [ ] **Step 10: 量測 DoD**

```bash
# hook 延遲 p95
#
# 本機**沒有裝 hyperfine**（已實測 `which hyperfine` → not found），所以不要
# 把 DoD 量測綁在它上面 —— 缺工具就量不到，等於這個 DoD 從沒被驗過。
# 下面是零依賴的等價量測；若你確實裝了 hyperfine，用它更精準。
export AGENTAURA_ROOT=$(mktemp -d)/sessions
echo '{"hook_event_name":"PreToolUse","session_id":"bench","tool_name":"Bash"}' > /tmp/aura-bench.json
swift build -c release
python3 - <<'BENCH'
import subprocess, time, statistics, os
os.environ.setdefault("AGENTAURA_ROOT", os.environ["AGENTAURA_ROOT"])
payload = open("/tmp/aura-bench.json","rb").read()
for _ in range(20):                                  # warmup
    subprocess.run(["./.build/release/aura-hook"], input=payload, capture_output=True)
ts = []
for _ in range(200):
    t = time.perf_counter()
    subprocess.run(["./.build/release/aura-hook"], input=payload, capture_output=True)
    ts.append((time.perf_counter() - t) * 1000)
ts.sort()
print(f"n=200  median={statistics.median(ts):.2f}ms  "
      f"p95={ts[int(.95*len(ts))]:.2f}ms  max={max(ts):.2f}ms")
BENCH

# 若有 hyperfine 才跑這一行（沒有就跳過，上面的 python 已給出數字）
command -v hyperfine >/dev/null && hyperfine --warmup 20 --min-runs 200 './.build/release/aura-hook < /tmp/aura-bench.json'

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
| ↑ 量測工具 | 零依賴 python（不要求 hyperfine） | |
| 端到端反應 p95 | < 250ms | |
| `AuraCore` 覆蓋率 | ≥ 90% | |
| 單檔行數 | ≤ 200 | |
| agent 減速 | 0 ms（async） | |

未達標者不得進 M4，須先補足或在 spec 記為 known gap 並說明理由。

- [ ] **Step 11: Commit**

```bash
git add .claude-plugin/marketplace.json plugin Sources/AuraHookFile/PipelineGraph.swift \
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
        // **不在這裡再解析一次 `hooks.json`。**
        //
        // 這裡原本有第二份解析器，於是 T13 把事件包進 `"hooks"` 物件時它沒同步，
        // 四條測試裡三條變紅。紅是好事，但代價是兩份程式碼要靠人記得一起改 ——
        // 那正是「接縫」的定義。改成直接用 `PluginWiringTests.entries()`，
        // 全 repo 只留一份 hooks.json 解析器。
        let commands = Set(try PluginWiringTests.entries().compactMap { $0.entry["command"] as? String })
        #expect(commands.count == 1, "全部 hook 應指向同一個 command：\(commands.sorted())")
        let command = try #require(commands.first)
        // command 是加了引號的（官方慣例，$HOME 含空白才不會裂開），先剝掉
        let unquoted = command.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        // 安裝後 plugin 根目錄就是 repo 的 plugin/
        let relative = unquoted.replacingOccurrences(of: "${CLAUDE_PLUGIN_ROOT}/", with: "plugin/")
        return repoRoot().appendingPathComponent(relative)
    }

    @Test("hooks.json 指向的路徑，在 repo 的 plugin 目錄下真的存在且可執行")
    func pluginBinaryIsInPlace() throws {
        let bin = try Self.expectedBinaryPath()
        // #expect 的訊息參數型別是 `Comment`（ExpressibleByStringInterpolation），
        // 不能用字串串接 —— `+` 會讓它變成 String，編譯錯誤（實測）。
        #expect(FileManager.default.isExecutableFile(atPath: bin.path),
                "\(bin.path) 不存在或不可執行。先跑 scripts/build-plugin.sh。這條擋的正是 前一個專案 留下死 hook 的失效方式")
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
        // 斷言**真正的移除指令**，不是一個代理字串。
        //
        // 這裡原本斷言 `doc.contains("plugin uninstall")`。安裝方式改成 skills-dir
        // 掛載之後，那個字串只剩在一句「**沒有** `claude plugin uninstall` 這一步」
        // 的說明裡 —— 斷言靠一段**語意相反**的文字通過，等於什麼都沒驗。
        // 代理字串會 drift，指令不會。
        #expect(doc.contains("## 完整移除"), "必須有完整移除的段落")
        #expect(doc.contains("rm ~/.claude/skills/agentaura"),
                "必須寫明真正的移除指令（skills-dir 掛載就是刪那個 symlink）")
        #expect(doc.contains("ln -sfn") && doc.contains("~/.claude/skills/agentaura"),
                "安裝指令也要在文件裡，且與實際機制一致")
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

echo "==> 驗證架構"
archs=$(lipo -archs plugin/bin/aura-hook)
echo "$archs"
for a in arm64 x86_64; do
  case "$archs" in *"$a"*) ;; *) echo "缺 $a"; exit 1 ;; esac
done

echo "==> 驗證真的跑得起來且 exit 0"
# 這裡刻意關掉 errexit 再自己判斷：
# 原本寫成 `cmd; echo "exit=$?  （必須是 0）"`，但在 `set -euo pipefail` 下，
# 非 0 會讓腳本在 echo 之前就死掉 —— 那行**永遠只印得出 exit=0**，
# 「必須是 0」這句話製造了一個不存在的檢查。實測確認（腳本直接 exit 1、零輸出）。
BENCHROOT="$(mktemp -d)/sessions"
set +e
echo '{"hook_event_name":"PreToolUse","session_id":"buildcheck","tool_name":"Bash"}' \
  | AGENTAURA_ROOT="$BENCHROOT" ./plugin/bin/aura-hook
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "aura-hook 回了 $rc，契約要求一律 0"; exit 1; }

# exit 0 不等於真的寫了檔 —— 契約是「靜默 exit 0」，所以 exit code 本身
# 無法區分「成功」與「內部炸掉但被吞掉」。必須驗產物。
[ -s "$BENCHROOT/buildcheck.json" ] || { echo "沒有寫出狀態檔 —— exit 0 是假的成功"; exit 1; }
grep -q '"main_activity":"working"' "$BENCHROOT/buildcheck.json" \
  || { echo "狀態檔內容不對：$(cat "$BENCHROOT/buildcheck.json")"; exit 1; }

echo "==> plugin/bin/aura-hook 就緒"
EOF
chmod +x scripts/build-plugin.sh
./scripts/build-plugin.sh
```

Expected（已實測全部通過）：
- `lipo -archs plugin/bin/aura-hook` → `x86_64 arm64`
- `aura-hook` exit 0
- 狀態檔內容為
  `{"hook_event_name":"PreToolUse","main_activity":"working","main_tool":"Bash","pid":...,"pid_started_at":...,"schema":1,"session_id":"buildcheck",...}`

> `swift build -c release --arch arm64` / `--arch x86_64` 兩者都可用，
> 產物在 `.build/<arch>-apple-macosx/release/aura-hook`（已實測）。
>
> **為什麼要驗產物而不只驗 exit code**：`aura-hook` 的契約是「任何錯誤都靜默
> exit 0」，所以 exit code 本身**無法區分成功與失敗** —— 這是刻意的設計
> （觀測性絕不可干擾 agent），代價就是驗收不能靠它。

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
./scripts/build-plugin.sh                            # 建置 universal aura-hook 到 plugin/bin/
claude plugin validate --strict ./plugin             # 官方 validator，零 error 零 warning
ln -sfn "$PWD/plugin" ~/.claude/skills/agentaura     # 掛載（settings.json 零改動）
./scripts/verify-install.sh                          # 驗證整條鏈路
```

**下一個 Claude Code session 起生效**（skills-dir 的 plugin 在 session 啟動時載入；
已在執行中的 session 不會中途載入新 plugin）。

> **為什麼用 `~/.claude/skills/`，而不是 marketplace：**
>
> `claude plugin install` **只從 marketplace 安裝**（`--help`：「Install a plugin
> from available marketplaces」），本地安裝要先 `claude plugin marketplace add <path>`。
> **但那會寫 `~/.claude/settings.json`** —— 實測 `marketplace add` 在
> `extraKnownMarketplaces` 裡加一筆 `agentaura → directory /path/to/repo`，
> **直接違反 D3/R6「AgentAura 從不修改 settings.json」**。
>
> `~/.claude/skills/<name>/` 是 Claude Code 的另一條 plugin 載入路徑
> （`claude plugin init --help`：「auto-loads next session as `<name>@skills-dir`」）。
> 實測：
> - 現有 5 個 skills-dir plugin 在 `settings.json` 裡**零命中**
> - 掛上 symlink 後 `claude plugin list` 顯示 `agentaura@skills-dir ... ✔ loaded`
> - 跑一個真的 `claude -p` session，hook 觸發、狀態檔寫出、內容完整
> - **`settings.json` 的 md5 完全沒變**
>
> 用 **symlink** 而不是複製：改了程式碼重跑 `build-plugin.sh` 就生效，
> 不需要重新安裝。（要凍結版本的話把 `ln -sfn` 換成 `cp -R` 即可。）

**不需要重啟 Claude Code** —— hook 設定變更會立即對執行中的 session 生效（已實測確認）。

## 完整移除

```bash
rm ~/.claude/skills/agentaura     # 移除掛載（hooks 隨之失效）
rm -rf ~/.agentaura               # 狀態目錄，可安全刪除
```

一步安裝、一步移除（R6）。驗證移除乾淨：

```bash
claude plugin list | grep -c -i agentaura           # → 0
grep -c -i agentaura ~/.claude/settings.json        # → 0（**全程都是 0**）
ls ~/.agentaura 2>/dev/null | wc -l                 # → 0
```

第二行的重點是「**全程**都是 0」，不是「移除後變成 0」——
AgentAura 從頭到尾沒有寫過 `settings.json` 的任何一個位元組。

移除後 `~/.claude/settings.json` **不會留下任何 AgentAura 引用** ——
這是刻意的設計：AgentAura 從不修改 `settings.json`，全部靠 plugin 機制。

## 狀態目錄

`~/.agentaura/sessions/<session_id>.json` —— 每個 Claude Code session 一個檔，
內容是瞬時狀態，可隨時安全刪除（app 會在下一個 hook 事件時重建）。

## 疑難排解

**燈沒反應**

```bash
ls -la ~/.agentaura/sessions/                        # 有檔案嗎？
claude plugin list | grep -A3 -i agentaura           # 載入了嗎？應顯示 ✔ loaded
ls -la ~/.claude/skills/agentaura                    # 掛載還在嗎？指向對的地方嗎？
claude plugin validate --strict ./plugin             # manifest 有 error / warning 嗎？
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
[ -e "$HOME/.claude/skills/agentaura" ] \
  && ok "掛載存在：$(readlink "$HOME/.claude/skills/agentaura" 2>/dev/null || echo '（實體目錄）')" \
  || bad "未掛載 —— ln -sfn \"$PWD/plugin\" ~/.claude/skills/agentaura"
claude plugin list 2>/dev/null | grep -q "agentaura@skills-dir" \
  && ok "Claude Code 已載入 agentaura@skills-dir" \
  || bad "Claude Code 沒載入 —— 這是新 session 才會生效的，先開一個新 session 再跑"

echo "== 2b. 官方 validator 零 error 零警告 =="
# 只看 exit code 是空轉的：validator 對「unknown hook event」、「no type」、
# 「async 型別錯」都只給 **warning** 並仍然 exit 0，而每個 warning 都寫著
# **entry ignored at runtime** —— 也就是一個靜默的死 hook。
# 實測確認 exit code 在有 warning 時仍是 0，所以這裡必須看輸出文字。
for target in ./plugin .; do
  out=$(claude plugin validate "$target" 2>&1)
  if echo "$out" | grep -qi "warning\|✘"; then
    bad "validate $target 有 error/warning："
    echo "$out" | sed 's/^/      /'
  elif echo "$out" | grep -q "Validation passed"; then
    ok "validate $target 乾淨"
  else
    bad "validate $target 沒有印出通過：$out"
  fi
done

echo "== 3. settings.json 全檔零污染（D3/R6）=="
# **掃整個檔案，不只掃 hooks 區塊。**
#
# 前一版只看 `d.get('hooks', {})`。實測 `claude plugin marketplace add .` 會在
# `extraKnownMarketplaces` 裡寫一筆 agentaura —— 那個位置**完全不在** hooks 底下，
# 舊檢查會給綠燈。一個只看自己想得到的那個角落的檢查，等於沒有檢查。
python3 -c "
import json, pathlib, sys
p = pathlib.Path.home()/'.claude/settings.json'
raw = p.read_text() if p.exists() else '{}'
hits = [k for k in ['agentaura', 'aura-hook', 'AgentAura'] if k.lower() in raw.lower()]
if hits:
    d = json.loads(raw)
    where = [key for key in d if any(h.lower() in json.dumps(d[key]).lower() for h in hits)]
    print('    污染位置：' + ', '.join(where))
    sys.exit(1)
sys.exit(0)
" && ok "settings.json 全檔零 AgentAura 引用" \
  || bad "settings.json 被寫入了 —— 違反 D3/R6。AgentAura 不該碰這個檔案的任何位元組"

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
claude plugin validate --strict ./plugin          # 零 error 零 warning
md5 -q ~/.claude/settings.json                    # 記下指紋
ln -sfn "$PWD/plugin" ~/.claude/skills/agentaura  # 掛載
claude plugin list | grep -A3 -i agentaura        # 應顯示 agentaura@skills-dir ... ✔ loaded
md5 -q ~/.claude/settings.json                    # **必須與上面那個相同**
./scripts/verify-install.sh
```

> **這一步會動到使用者的 `~/.claude/skills/`**（多一個 symlink），
> 逆操作是 `rm ~/.claude/skills/agentaura`，一行。
> **`~/.claude/settings.json` 全程不被修改** —— 上下兩次 `md5` 必須相同，
> 這是比 verify 腳本更直接的證據。
>
> **不要用 `claude plugin marketplace add`**：實測它會在 `extraKnownMarketplaces`
> 寫一筆，直接違反 D3/R6。這個路徑已從 plan 移除。
>
> **已實測的完整結果**（controller 在派工前跑過一次）：
> `claude plugin list` → `agentaura@skills-dir ... ✔ loaded`；
> `claude -p "請執行 echo ..."` 之後 `~/.agentaura/sessions/` 出現一個狀態檔，
> 內容含 `main_activity: "done"`、`main_tool: "Bash"`、`terminated: true`、
> `tool_duration_ms: 289`、`last_message`、`turn_started_at`、`pid` / `pid_started_at`、
> `effort` / `permission_mode` / `source` / `reason`；`settings.json` 的 md5 不變。

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

---

# 第二部分：UI（M4-M5）

原計畫只到 M0-M3。使用者的目標是「產出一版可以用的版本」，而 T14 結束時的狀態是
「hook 寫得出狀態、端到端驗證通過」的可驗證管線 —— **但看不到燈**。以下四個 task
把它變成可用的 app。

**貫穿的設計決定：動畫決策放在 `AuraCore`，做成純資料。**

`IconState` → `IconAppearance`（顏色、動畫種類、幀率）是純函數，可在無 GUI 環境
測試；AppKit 層只負責把 `IconAppearance` 畫出來。這樣做的三個理由：

1. **注意力預算（R4）變成可單元測試的東西。**「只有 waiting 與 error 會動」
   是產品決策，不該埋在 `NSView.draw` 裡靠肉眼驗。
2. 守住 Global Constraint「`AuraCore` 不得依賴 AppKit」—— 由編譯器 gate 強制。
3. 形態 A／B（R5）只需換 renderer，`IconAppearance` 不動。

---

### Task 15: IconAppearance —— 注意力預算的可測形式

**Files:**
- Create: `Sources/AuraCore/IconAppearance.swift`
- Test: `Tests/AuraCoreTests/IconAppearanceTests.swift`

**Interfaces:**
- Consumes: `IconState`、`Activity`
- Produces:
  ```swift
  public enum IconAnimation: Equatable, Sendable {
      case none                                  // 靜態
      case breathe(period: Double, min: Double, max: Double)
      case doubleBlink(period: Double)
  }
  public struct IconAppearance: Equatable, Sendable {
      public let activity: Activity
      public let animation: IconAnimation
      public let targetFPS: Int                  // 0 = 不需重繪
      public let attentionCount: Int
      public let liveCount: Int
      public var needsAnimation: Bool            // targetFPS > 0
  }
  public enum AppearancePolicy {
      public static func appearance(for icon: IconState, reduceMotion: Bool) -> IconAppearance
  }
  ```

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/AuraCoreTests/IconAppearanceTests.swift
import Testing
@testable import AuraCore

@Suite("注意力預算（R4）")
struct IconAppearanceTests {

    func appearance(_ a: Activity, waiting: Int = 0, error: Int = 0,
                    working: Int = 0, reduceMotion: Bool = false) -> IconAppearance {
        var counts: [Activity: Int] = [:]
        if waiting > 0 { counts[.waiting] = waiting }
        if error > 0 { counts[.error] = error }
        if working > 0 { counts[.working] = working }
        if counts.isEmpty { counts[a] = 1 }
        let icon = IconState(activity: a, counts: counts, liveCount: working + waiting)
        return AppearancePolicy.appearance(for: icon, reduceMotion: reduceMotion)
    }

    // ---- 核心規則：只有需要你行動的狀態才會動 ----

    @Test("done 與 idle 完全不動；waiting 與 error 會動")
    func onlyAttentionStatesAnimate() {
        #expect(appearance(.waiting).needsAnimation)
        #expect(appearance(.error).needsAnimation)
        #expect(!appearance(.done).needsAnimation, "done 是「可以去看了」，不是「你被擋著」")
        #expect(!appearance(.idle).needsAnimation)
        // working 技術上仍會重繪（極慢呼吸），但幀率與對比都遠低於 waiting ——
        // 那個差距由 workingAndWaitingAreDistinguishable 守。
        #expect(appearance(.working).needsAnimation,
                "working 有極微動畫讓人看得出在跑；強度差距另有測試")
    }

    @Test("幀率符合 DoD 的分層門檻")
    func frameRateTiers() {
        #expect(appearance(.idle).targetFPS == 0, "idle 必須零重繪")
        #expect(appearance(.done).targetFPS == 0, "done 必須零重繪")
        #expect(appearance(.working).targetFPS <= 10, "working 是常態，≤10 fps")
        #expect(appearance(.waiting).targetFPS >= 30, "waiting 要流暢才有警示效果")
        #expect(appearance(.error).targetFPS >= 30)
    }

    @Test("working 的呼吸低對比且週期長 —— 它是常態，不該搶注意力")
    func workingIsSubtle() {
        guard case .breathe(let period, let lo, let hi) = appearance(.working).animation else {
            Issue.record("working 應為 breathe"); return
        }
        #expect(period >= 3.0, "週期至少 3 秒，實際 \(period)")
        #expect(hi - lo <= 0.35, "透明度對比不得超過 0.35，實際 \(hi - lo)")
    }

    @Test("waiting 的呼吸明顯 —— 它需要你行動")
    func waitingIsSalient() {
        guard case .breathe(let period, let lo, let hi) = appearance(.waiting).animation else {
            Issue.record("waiting 應為 breathe"); return
        }
        #expect(period <= 1.5, "週期不超過 1.5 秒")
        #expect(hi - lo >= 0.6, "對比至少 0.6，才與 working 明顯不同")
    }

    @Test("error 是 double blink，與 waiting 的呼吸在形狀上就不同")
    func errorIsDoubleBlink() {
        guard case .doubleBlink = appearance(.error).animation else {
            Issue.record("error 應為 doubleBlink"); return
        }
    }

    @Test("working 與 waiting 的動畫參數差距足夠大，餘光可辨")
    func workingAndWaitingAreDistinguishable() {
        guard case .breathe(let wp, let wlo, let whi) = appearance(.working).animation,
              case .breathe(let ap, let alo, let ahi) = appearance(.waiting).animation else {
            Issue.record("兩者都應為 breathe"); return
        }
        #expect(wp / ap >= 2.0, "週期至少差 2 倍，實際 \(wp) vs \(ap)")
        #expect((ahi - alo) / (whi - wlo) >= 2.0, "對比至少差 2 倍")
    }

    // ---- 減少動態效果 ----

    @Test("系統開啟減少動態效果時，全部改為靜態")
    func reduceMotionDisablesAllAnimation() {
        for a in Activity.allCases {
            let ap = appearance(a, reduceMotion: true)
            #expect(ap.animation == .none, "\(a) 在 reduceMotion 下應為 .none")
            #expect(ap.targetFPS == 0, "\(a) 在 reduceMotion 下應零重繪")
        }
    }

    @Test("reduceMotion 不改變 activity —— 只改呈現方式")
    func reduceMotionKeepsActivity() {
        for a in Activity.allCases {
            #expect(appearance(a, reduceMotion: true).activity == a)
        }
    }

    // ---- 計數透傳 ----

    @Test("attentionCount 與 liveCount 透傳自 IconState")
    func countsPassThrough() {
        let ap = appearance(.error, waiting: 2, error: 1, working: 3)
        #expect(ap.attentionCount == 3, "error 1 + waiting 2")
        #expect(ap.liveCount == 5)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter IconAppearanceTests`
Expected: FAIL — `cannot find 'AppearancePolicy' in scope`

- [ ] **Step 3: 實作**

```swift
// Sources/AuraCore/IconAppearance.swift

/// Menu bar icon 的動畫形式。
public enum IconAnimation: Equatable, Sendable {
    case none
    /// 透明度在 `min`…`max` 之間以 `period` 秒往復。
    case breathe(period: Double, min: Double, max: Double)
    /// 每 `period` 秒閃兩下。
    case doubleBlink(period: Double)
}

/// 一個 `IconState` 該長什麼樣。純資料，不含任何繪製。
public struct IconAppearance: Equatable, Sendable {
    public let activity: Activity
    public let animation: IconAnimation
    /// 建議重繪幀率。`0` 表示完全靜態，`AnimationDriver` 不該排程任何重繪。
    public let targetFPS: Int
    public let attentionCount: Int
    public let liveCount: Int

    public var needsAnimation: Bool { targetFPS > 0 }
}

/// 注意力預算（R4）—— **這是產品決策，所以放在可單元測試的地方**。
///
/// 規則：只有需要使用者行動的狀態才會動。使用者的常態是多 agent 併行、
/// 整夜跑 pipeline；若 `working` 也搶眼，menu bar 幾乎永遠在動，「動起來」
/// 就失去訊號價值，必須辨色才知道發生什麼事。
///
/// 換來三件事：常態安靜；**餘光就能判斷、不需辨色**；大多數時間零重繪。
public enum AppearancePolicy {

    public static func appearance(for icon: IconState,
                                 reduceMotion: Bool = false) -> IconAppearance {
        let (animation, fps) = reduceMotion
            ? (IconAnimation.none, 0)
            : motion(for: icon.activity)
        return IconAppearance(activity: icon.activity,
                              animation: animation,
                              targetFPS: fps,
                              attentionCount: icon.attentionCount,
                              liveCount: icon.liveCount)
    }

    static func motion(for activity: Activity) -> (IconAnimation, Int) {
        switch activity {
        case .idle, .done:
            // 完全靜態。done 是「你可以去看了」，不是「你被擋著」。
            return (.none, 0)
        case .working:
            // 常態：看得出在跑，但不搶注意力。週期長、對比低、幀率低。
            return (.breathe(period: 4.0, min: 0.35, max: 0.60), 10)
        case .waiting:
            // 需要行動：週期短、對比高，與 working 差 4 倍週期、3 倍對比。
            return (.breathe(period: 1.1, min: 0.20, max: 1.00), 30)
        case .error:
            // 需要行動，且形狀與 waiting 不同 —— 不必辨色也能區分。
            return (.doubleBlink(period: 1.1), 30)
        }
    }
}
```

- [ ] **Step 4: 執行確認通過**

Run: `swift test --filter IconAppearanceTests`
Expected: 全部 PASS（9 個測試）

- [ ] **Step 5: Mutation 驗證**

依 Global Constraints 的標準程序。三個：

1. 把 `.working` 的 `targetFPS` 從 `10` 改成 `30` → `frameRateTiers` 必須 RED
2. 把 `.done` 的 `(.none, 0)` 改成 `(.breathe(period: 2, min: 0.3, max: 0.9), 30)`
   → `onlyAttentionStatesAnimate` 與 `frameRateTiers` 必須 RED
3. 把 `.waiting` 的週期改成 `4.0`（與 working 相同）
   → `workingAndWaitingAreDistinguishable` 與 `waitingIsSalient` 必須 RED

第 3 個是重點：它守的是「餘光可辨」這個產品性質，而那是最容易在調參時
不小心破壞、又最不容易從程式碼看出來的東西。

- [ ] **Step 6: Commit**

```bash
git add Sources/AuraCore/IconAppearance.swift Tests/AuraCoreTests/IconAppearanceTests.swift
git commit -F - <<'EOF'
feat(core): IconAppearance —— 把注意力預算做成可單元測試的純資料

只有 waiting 與 error 會動；working 是常態，用長週期低對比的呼吸；
done 與 idle 完全靜態、零重繪。放在 AuraCore 而非 NSView.draw 裡，
是為了讓「動 = 需要你」這條產品決策能被測試，而不是靠肉眼驗。
EOF
```

---

### Task 16: AnimationSchedule + StatusItemController —— 讓燈亮起來

**這個 task 結束時，app 可以跑起來並在 menu bar 顯示狀態。**

同樣的切法：**要不要動、多久動一次**是可測的決策，放 `AuraCore`；
AppKit 層只負責照排程重繪。省電邏輯（螢幕睡眠、icon 被遮蔽）是這個決策的輸入，
不是散落在 AppKit callback 裡的 if。

**Files:**
- Modify: `Package.swift`（新增 `AgentAuraApp` executable target）
- Create: `Sources/AuraCore/AnimationSchedule.swift`
- Create: `Sources/AgentAuraApp/main.swift`
- Create: `Sources/AgentAuraApp/AppDelegate.swift`
- Create: `Sources/AgentAuraApp/StatusItemController.swift`
- Create: `Sources/AgentAuraApp/LEDStripView.swift`
- Create: `Sources/AgentAuraApp/AnimationDriver.swift`
- Test: `Tests/AuraCoreTests/AnimationScheduleTests.swift`

**Interfaces:**
- Consumes: `IconAppearance`、`AppearancePolicy`、`PipelineGraph`
- Produces:
  ```swift
  // AuraCore（可測、無 AppKit）
  public struct DisplayEnvironment: Equatable, Sendable {
      public var screenAsleep: Bool
      public var iconVisible: Bool
      public var reduceMotion: Bool
      public init(screenAsleep: Bool = false, iconVisible: Bool = true, reduceMotion: Bool = false)
  }
  public enum AnimationSchedule {
      /// 回傳重繪間隔（秒）；`nil` 表示不該排程任何重繪。
      public static func interval(for icon: IconState, in env: DisplayEnvironment) -> Double?
  }

  // AgentAuraApp（AppKit）
  protocol IconRendering: AnyObject { func apply(_ appearance: IconAppearance, phase: Double) }
  final class StatusItemController: IconRendering
  final class AnimationDriver
  ```

- [ ] **Step 1: 寫失敗測試（純邏輯部分）**

```swift
// Tests/AuraCoreTests/AnimationScheduleTests.swift
import Testing
@testable import AuraCore

@Suite("動畫排程與省電")
struct AnimationScheduleTests {

    func icon(_ a: Activity) -> IconState {
        IconState(activity: a, counts: [a: 1], liveCount: a == .idle ? 0 : 1)
    }

    @Test("螢幕睡眠時完全不排程重繪 —— 沒人看得到，白吃電池")
    func screenAsleepStopsEverything() {
        for a in Activity.allCases {
            let env = DisplayEnvironment(screenAsleep: true)
            #expect(AnimationSchedule.interval(for: icon(a), in: env) == nil,
                    "\(a) 在螢幕睡眠時仍排程重繪")
        }
    }

    @Test("icon 被遮蔽（全螢幕 app）時不排程重繪")
    func hiddenIconStopsEverything() {
        for a in Activity.allCases {
            let env = DisplayEnvironment(iconVisible: false)
            #expect(AnimationSchedule.interval(for: icon(a), in: env) == nil)
        }
    }

    @Test("減少動態效果時不排程重繪")
    func reduceMotionStopsEverything() {
        for a in Activity.allCases {
            let env = DisplayEnvironment(reduceMotion: true)
            #expect(AnimationSchedule.interval(for: icon(a), in: env) == nil)
        }
    }

    @Test("正常情況下，靜態狀態不排程、動態狀態按幀率排程")
    func normalIntervals() {
        let env = DisplayEnvironment()
        #expect(AnimationSchedule.interval(for: icon(.idle), in: env) == nil)
        #expect(AnimationSchedule.interval(for: icon(.done), in: env) == nil)

        let working = try! #require(AnimationSchedule.interval(for: icon(.working), in: env))
        let waiting = try! #require(AnimationSchedule.interval(for: icon(.waiting), in: env))
        #expect(working >= 0.09, "working ≤ 10 fps，間隔至少 0.09s，實際 \(working)")
        #expect(waiting <= 0.034, "waiting ≥ 30 fps，間隔至多 0.034s，實際 \(waiting)")
        #expect(working > waiting * 2, "working 的間隔要明顯長於 waiting")
    }

    @Test("間隔與 IconAppearance 的 targetFPS 一致 —— 不得各自定義幀率")
    func intervalMatchesAppearance() {
        let env = DisplayEnvironment()
        for a in Activity.allCases {
            let ap = AppearancePolicy.appearance(for: icon(a))
            let iv = AnimationSchedule.interval(for: icon(a), in: env)
            if ap.targetFPS == 0 {
                #expect(iv == nil, "\(a) targetFPS 為 0 卻排了間隔")
            } else {
                let expected = 1.0 / Double(ap.targetFPS)
                #expect(iv != nil && abs(iv! - expected) < 0.0001,
                        "\(a) 的間隔應為 1/\(ap.targetFPS)，實際 \(iv as Any)")
            }
        }
    }

    @Test("任何一個省電條件成立就停止，不需要全部成立")
    func anySuppressorStops() {
        let combos = [
            DisplayEnvironment(screenAsleep: true, iconVisible: true, reduceMotion: false),
            DisplayEnvironment(screenAsleep: false, iconVisible: false, reduceMotion: false),
            DisplayEnvironment(screenAsleep: false, iconVisible: true, reduceMotion: true),
        ]
        for env in combos {
            #expect(AnimationSchedule.interval(for: icon(.error), in: env) == nil,
                    "env=\(env) 應停止重繪")
        }
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter AnimationScheduleTests`
Expected: FAIL — `cannot find 'AnimationSchedule' in scope`

- [ ] **Step 3: 實作純邏輯部分**

```swift
// Sources/AuraCore/AnimationSchedule.swift

/// 影響「該不該動」的外部條件。
///
/// 做成一個值而不是散在 AppKit callback 裡的 if：省電規則因此可以被測試，
/// 而且新增一個抑制條件時只有一處要改。
public struct DisplayEnvironment: Equatable, Sendable {
    public var screenAsleep: Bool
    public var iconVisible: Bool
    public var reduceMotion: Bool

    public init(screenAsleep: Bool = false, iconVisible: Bool = true, reduceMotion: Bool = false) {
        self.screenAsleep = screenAsleep
        self.iconVisible = iconVisible
        self.reduceMotion = reduceMotion
    }

    /// 任一條件成立就不該動。
    public var suppressesAnimation: Bool { screenAsleep || !iconVisible || reduceMotion }
}

public enum AnimationSchedule {

    /// 重繪間隔（秒）；`nil` 表示不該排程任何重繪。
    ///
    /// 幀率**一律**取自 `AppearancePolicy`，不在這裡另定一份 —— 兩處各自定義
    /// 幀率就會 drift，而 DoD 是照 `IconAppearance.targetFPS` 量的。
    public static func interval(for icon: IconState,
                                in env: DisplayEnvironment) -> Double? {
        guard !env.suppressesAnimation else { return nil }
        let fps = AppearancePolicy.appearance(for: icon, reduceMotion: env.reduceMotion).targetFPS
        guard fps > 0 else { return nil }
        return 1.0 / Double(fps)
    }
}
```

- [ ] **Step 4: 執行確認通過**

Run: `swift test --filter AnimationScheduleTests`
Expected: 全部 PASS（6 個測試）

- [ ] **Step 5: 在 `Package.swift` 新增 app target**

> 這裡原本寫「`Package.swift` 從 Task 02 起就宣告了 `AgentAuraApp`，不需要改」——
> **那是錯的**（我在派工前實查）。實際的 `Package.swift` 只有四個 target
> （`AuraCore`、`AuraHookFile`、`aura-hook`、`AuraCoreTests`），
> `Sources/AgentAuraApp/` 也不存在。照原文跑，`grep` 會回空、implementer 會卡住。

在 `.executableTarget(name: "aura-hook", ...)` 那一行**之後**插入：

```swift
        .executableTarget(name: "AgentAuraApp", dependencies: ["AuraCore", "AuraHookFile"]),
```

Run: `grep -n AgentAuraApp Package.swift && swift build 2>&1 | tail -3`
Expected: 找得到那一行；`swift build` 成功。

> **對隔離 gate 的影響（已實測，不需額外處理）**：`IsolationTests` 的
> `nonUITargetsLoadNoUIModules` 用「`Sources/` 下的目錄 − `uiTargets` 允許清單」
> 決定要 gate 誰，而 `uiTargets` 已經是 `["AgentAuraApp"]`，所以新增這個 target
> 不會讓那條測試變紅。
>
> 反過來，`uiExemptionsAreEarned`（豁免必須被賺到 —— 被豁免的 target 必須**真的**
> 載入 AppKit）在此之前因為目錄不存在而**跳過**，從這個 task 起會真的開始執行。
> 若它變紅，代表 `AgentAuraApp` 沒有載入任何 UI module —— 那它就不該被豁免。

- [ ] **Step 6: 實作 AppKit 層**

```swift
// Sources/AgentAuraApp/LEDStripView.swift
import AppKit
import AuraCore

/// 形態 A：menu bar 裡的 8 顆迷你 LED 燈條。
///
/// `phase` 由 `AnimationDriver` 推進（0…1 的循環位置），view 自己不持有計時器 ——
/// 這樣「多久畫一次」的決策留在可測的 `AnimationSchedule`，view 只負責畫。
@MainActor
final class LEDStripView: NSView {
    /// 刻意不叫 `appearance` —— `NSView` 已有一個 `appearance: NSAppearance?`，
    /// 同名會得到「cannot override a property with type 'NSAppearance?'」。
    private var iconAppearance = AppearancePolicy.appearance(for: IconState.empty)
    private var phase: Double = 0

    static let ledCount = 8
    static let ledWidth: CGFloat = 3
    static let ledGap: CGFloat = 2
    static let ledHeight: CGFloat = 12

    static var preferredWidth: CGFloat {
        CGFloat(ledCount) * ledWidth + CGFloat(ledCount - 1) * ledGap
    }

    func update(_ appearance: IconAppearance, phase: Double) {
        self.iconAppearance = appearance
        self.phase = phase
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = Self.color(for: iconAppearance.activity)
        let alpha = Self.alpha(for: iconAppearance.animation, phase: phase)
        var x: CGFloat = 0
        let y = (bounds.height - Self.ledHeight) / 2
        for _ in 0..<Self.ledCount {
            let r = NSRect(x: x, y: y, width: Self.ledWidth, height: Self.ledHeight)
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
            x += Self.ledWidth + Self.ledGap
        }
    }

    /// 顏色跟隨 menu bar 的深淺色 —— `NSColor` 的 system color 會自己處理。
    static func color(for activity: Activity) -> NSColor {
        switch activity {
        case .idle:    return .tertiaryLabelColor
        case .working: return .systemBlue
        case .waiting: return .systemOrange
        case .done:    return .systemGreen
        case .error:   return .systemRed
        }
    }

    static func alpha(for animation: IconAnimation, phase: Double) -> CGFloat {
        switch animation {
        case .none:
            return 1.0
        case .breathe(_, let lo, let hi):
            // 三角波比 sin 便宜，且在低幀率下看起來一樣
            let t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            return CGFloat(lo + (hi - lo) * t)
        case .doubleBlink:
            // 一個週期內：亮 亮 暗 —— 兩次短閃後留一段暗
            switch phase {
            case ..<0.14, 0.28..<0.42: return 1.0
            default:                   return 0.08
            }
        }
    }
}
```

```swift
// Sources/AgentAuraApp/AnimationDriver.swift
import AppKit
import AuraCore

/// 照 `AnimationSchedule` 的決定推進 `phase` 並要求重繪。
///
/// 它**不決定**該不該動 —— 那是 `AnimationSchedule` 的職責。它只負責：
/// 監聽環境變化、把新的環境交給 `AnimationSchedule`、依回傳的間隔排程。
@MainActor
final class AnimationDriver {
    private var timer: Timer?
    private var phase: Double = 0
    private var icon: IconState = .empty
    private var env = DisplayEnvironment()
    private let onFrame: (IconAppearance, Double) -> Void

    init(onFrame: @escaping (IconAppearance, Double) -> Void) {
        self.onFrame = onFrame
        // 觀察者的 closure 是 @Sendable，但我們指定 queue: .main，所以實際一定在
        // main actor 上執行 —— 用 assumeIsolated 把這個事實告訴編譯器。
        // 少了它會得到一串 "capture of 'self' with non-Sendable type" 警告。
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.screenAsleep = true } }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.screenAsleep = false } }
        }
        nc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update {
                    $0.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                }
            }
        }
        env.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func setIcon(_ icon: IconState) {
        self.icon = icon
        reschedule()
    }

    func setIconVisible(_ visible: Bool) {
        update { $0.iconVisible = visible }
    }

    private func update(_ mutate: (inout DisplayEnvironment) -> Void) {
        mutate(&env)
        reschedule()
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        let appearance = AppearancePolicy.appearance(for: icon, reduceMotion: env.reduceMotion)
        // 靜態狀態也要畫一次，否則停止動畫後畫面留在上一格
        onFrame(appearance, 0)

        guard let interval = AnimationSchedule.interval(for: icon, in: env) else { return }
        let period = Self.period(of: appearance.animation) ?? 1.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase = (self.phase + interval / period).truncatingRemainder(dividingBy: 1)
                self.onFrame(appearance, self.phase)
            }
        }
    }

    static func period(of animation: IconAnimation) -> Double? {
        switch animation {
        case .none: return nil
        case .breathe(let p, _, _): return p
        case .doubleBlink(let p): return p
        }
    }
}
```

```swift
// Sources/AgentAuraApp/StatusItemController.swift
import AppKit
import AuraCore

@MainActor
protocol IconRendering: AnyObject {
    func apply(_ appearance: IconAppearance, phase: Double)
}

/// 擁有 `NSStatusItem`，把 `IconAppearance` 交給 view 畫。
@MainActor
final class StatusItemController: IconRendering {
    private let item: NSStatusItem
    private let strip = LEDStripView()

    init() {
        item = NSStatusBar.system.statusItem(withLength: LEDStripView.preferredWidth + 8)
        strip.frame = NSRect(x: 4, y: 0,
                             width: LEDStripView.preferredWidth,
                             height: item.statusBar?.thickness ?? 22)
        item.button?.addSubview(strip)
        item.button?.toolTip = "AgentAura"
    }

    var isVisible: Bool { item.isVisible }

    func apply(_ appearance: IconAppearance, phase: Double) {
        strip.update(appearance, phase: phase)
        item.button?.toolTip = Self.tooltip(for: appearance)
    }

    static func tooltip(for a: IconAppearance) -> String {
        if a.attentionCount > 0 { return "\(a.attentionCount) 個需要你 · \(a.liveCount) 個在跑" }
        if a.liveCount > 0 { return "\(a.liveCount) 個 session 在跑" }
        return "沒有活著的 session"
    }
}
```

```swift
// Sources/AgentAuraApp/AppDelegate.swift
import AppKit
import AuraCore
import AuraHookFile

/// Composition root。唯一的組裝點。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var graph: PipelineGraph!
    private var status: StatusItemController!
    private var driver: AnimationDriver!
    private var livenessTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusItemController()
        driver = AnimationDriver { [weak self] appearance, phase in
            self?.status.apply(appearance, phase: phase)
        }

        graph = PipelineGraph.production()
        // onIconStateChange 從 FSEvents 的背景 queue 上來，所以要 hop 回 main。
        graph.onIconStateChange = { icon in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.driver.setIcon(icon)
                self.driver.setIconVisible(self.status.isVisible)
            }
        }
        graph.start()

        // spec §3.5：每 5s 重驗 pid，抓「terminal 被強制關掉、SessionEnd 沒來」
        livenessTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.graph.refreshLiveness() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        livenessTimer?.invalidate()
        graph?.stop()
    }
}
```

```swift
// Sources/AgentAuraApp/main.swift
import AppKit

// menu bar app：不要 dock icon、不要主視窗。
// 以裸執行檔跑時 setActivationPolicy 就足夠；.app bundle 另由 Info.plist
// 的 LSUIElement 宣告（Task 18）。
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 7: 建置並手動確認燈會亮**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Test run with"

# 手動確認：先造幾個假狀態，再跑 app
mkdir -p ~/.agentaura/sessions
python3 - <<'EOF'
import json, pathlib, datetime
root = pathlib.Path.home()/".agentaura/sessions"
root.mkdir(parents=True, exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z")
for sid, act in [("demo-working","working"), ("demo-waiting","waiting")]:
    (root/f"{sid}.json").write_text(json.dumps({
        "schema": 1, "session_id": sid, "hook_event_name": "PreToolUse",
        "written_at": now, "cwd": f"/Users/you/Code/Vibe/{sid}",
        "main_activity": act, "subagents": {}, "tool_failures": 0,
        "terminated": False, "is_interrupt": False,
    }, ensure_ascii=False))
print("已造 2 個假狀態檔")
EOF

./.build/debug/AgentAuraApp &
APP=$!
sleep 3
# waiting 優先級低於 error 但高於 working → 應顯示橘色呼吸
echo "看 menu bar 右側應出現橘色呼吸的 8 顆燈條"
sleep 10
kill $APP
rm -f ~/.agentaura/sessions/demo-*.json
```

Expected: menu bar 出現燈條，且**橘色明顯呼吸**（因為有一個 waiting）。
把其中一個檔案的 `main_activity` 改成 `error` 再跑，應變成紅色 double blink。

- [ ] **Step 8: Mutation 驗證**

依標準程序，兩個：

1. 把 `DisplayEnvironment.suppressesAnimation` 改成只看 `reduceMotion`
   → `screenAsleepStopsEverything`、`hiddenIconStopsEverything`、`anySuppressorStops` 必須 RED
2. 把 `AnimationSchedule.interval` 的幀率改成寫死 `30`（不取自 `AppearancePolicy`）
   → `intervalMatchesAppearance` 與 `normalIntervals` 必須 RED

第 2 個守的是「幀率只有一個來源」—— 兩處各自定義幀率就會 drift，而 DoD 是照
`IconAppearance.targetFPS` 量的。

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/AuraCore/AnimationSchedule.swift Sources/AgentAuraApp \
        Tests/AuraCoreTests/AnimationScheduleTests.swift
git commit -F - <<'EOF'
feat(app): menu bar 燈條 + 動畫排程 —— 第一個看得到的版本

AnimationSchedule 放在 AuraCore：要不要動、多久動一次是可測的決策，
省電條件（螢幕睡眠、icon 被遮蔽、減少動態效果）是它的輸入，不是散在
AppKit callback 裡的 if。幀率一律取自 AppearancePolicy，不另定一份。

AppKit 層很薄：LEDStripView 只負責畫（phase 由外部推進，view 不持有計時器），
AnimationDriver 只負責監聽環境與排程，StatusItemController 只負責 NSStatusItem。
EOF
```

---

### Task 17: PanelViewModel + 面板 —— 看得到每個 session

**Files:**
- Create: `Sources/AuraCore/PanelViewModel.swift`
- Create: `Sources/AgentAuraApp/PanelView.swift`
- Modify: `Sources/AgentAuraApp/StatusItemController.swift`（掛上 popover）
- Modify: `Sources/AgentAuraApp/AppDelegate.swift`（打開面板即 acknowledge）
- Test: `Tests/AuraCoreTests/PanelViewModelTests.swift`

**Interfaces:**
- Consumes: `SessionState`、`IconState`、`Activity`
- Produces:
  ```swift
  public struct PanelRow: Equatable, Sendable, Identifiable {
      public let id: String
      public let projectName: String
      public let activity: Activity
      public let headline: String       // 正在做什麼 / 在等什麼
      public let detail: String         // 本輪多久 · subagent · 失敗數
      public let meta: String           // 模型 · effort · permission_mode
      public let relativeTime: String
      public let isEnded: Bool
  }
  public enum PanelViewModel {
      public static func rows(from states: [SessionState], now: Date) -> [PanelRow]
      public static func title(for icon: IconState) -> String
      public static func relativeTime(from date: Date, now: Date) -> String
      public static func duration(_ seconds: Double) -> String
  }
  ```

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/AuraCoreTests/PanelViewModelTests.swift
import Testing
import Foundation
@testable import AuraCore

@Suite("面板呈現")
struct PanelViewModelTests {

    let now = Date(timeIntervalSince1970: 1_788_700_000)

    func state(_ id: String, _ a: Activity, tool: String? = nil,
               turnStart: Double? = nil, subagents: [String: Int] = [:],
               failures: Int = 0, updated: Double = 0, live: Bool = true,
               model: String? = "claude-opus-5", lastMessage: String? = nil,
               toolError: String? = nil) -> SessionState {
        SessionState(id: id, projectName: id, projectPath: "/x/\(id)",
                     permissionMode: "default", effort: "high", model: model,
                     activity: a, mainActivity: a, subActivity: nil,
                     currentTool: tool, subagentTool: nil, toolDurationMs: nil,
                     turnStartedAt: turnStart.map { now.addingTimeInterval(-$0) },
                     subagents: subagents, toolFailures: failures,
                     lastMessage: lastMessage, errorType: nil, toolError: toolError,
                     liveness: live ? .alive(pid: 1) : .ended,
                     updatedAt: now.addingTimeInterval(-updated))
    }

    // ---- 排序：與 D1 優先序一致 ----

    @Test("排序是 error → waiting → working → done")
    func sortFollowsPriority() {
        let rows = PanelViewModel.rows(from: [
            state("w", .working), state("d", .done),
            state("e", .error), state("a", .waiting),
        ], now: now)
        #expect(rows.map { $0.id } == ["e", "a", "w", "d"])
    }

    @Test("同一組內最近活動優先")
    func recentFirstWithinGroup() {
        let rows = PanelViewModel.rows(from: [
            state("old", .working, updated: 300),
            state("new", .working, updated: 5),
            state("mid", .working, updated: 60),
        ], now: now)
        #expect(rows.map { $0.id } == ["new", "mid", "old"])
    }

    @Test("已結束的排在同組下半部")
    func endedGoesLast() {
        let rows = PanelViewModel.rows(from: [
            state("ended", .done, updated: 5, live: false),
            state("alive", .done, updated: 300, live: true),
        ], now: now)
        #expect(rows.map { $0.id } == ["alive", "ended"], "活著的優先，即使它更久沒動")
    }

    // ---- 內容 ----

    @Test("waiting 的主行說出在等什麼，不只是 tool 名")
    func waitingHeadlineNamesWhatIsAsked() {
        let rows = PanelViewModel.rows(from: [state("p", .waiting, tool: "Bash")], now: now)
        let h = rows[0].headline
        #expect(h.contains("Bash"))
        #expect(h.contains("等") || h.contains("批准"), "要看得出是在等你，實際：\(h)")
    }

    @Test("working 的主行顯示目前的 tool")
    func workingHeadlineShowsTool() {
        let rows = PanelViewModel.rows(from: [state("p", .working, tool: "Edit")], now: now)
        #expect(rows[0].headline.contains("Edit"))
    }

    @Test("done 的主行顯示完成訊息的摘要")
    func doneHeadlineShowsMessage() {
        let long = String(repeating: "完成了很多事情。", count: 40)
        let rows = PanelViewModel.rows(from: [state("p", .done, lastMessage: long)], now: now)
        #expect(rows[0].headline.count <= 90, "摘要要截斷，實際 \(rows[0].headline.count) 字")
        #expect(!rows[0].headline.isEmpty)
    }

    @Test("error 的主行顯示錯誤訊息")
    func errorHeadlineShowsError() {
        let rows = PanelViewModel.rows(from: [
            state("p", .error, toolError: "overloaded_error"),
        ], now: now)
        #expect(rows[0].headline.contains("overloaded_error"))
    }

    @Test("副行含本輪時長、subagent 數、失敗數")
    func detailHasCounters() {
        let rows = PanelViewModel.rows(from: [
            state("p", .working, turnStart: 487, subagents: ["Explore": 2, "implementer": 1], failures: 3),
        ], now: now)
        let d = rows[0].detail
        #expect(d.contains("8m") || d.contains("8 m") || d.contains("487"), "要有本輪時長，實際：\(d)")
        #expect(d.contains("3"), "要有 subagent 總數 3，實際：\(d)")
        #expect(d.contains("失敗") || d.contains("fail"), "要有失敗數，實際：\(d)")
    }

    @Test("沒有計數時副行不顯示 0，避免視覺噪音")
    func detailOmitsZeros() {
        let rows = PanelViewModel.rows(from: [state("p", .working)], now: now)
        #expect(!rows[0].detail.contains("0 subagent"))
        #expect(!rows[0].detail.contains("0 失敗"))
    }

    @Test("meta 含模型與 permission_mode")
    func metaHasModelAndMode() {
        let rows = PanelViewModel.rows(from: [state("p", .working)], now: now)
        #expect(rows[0].meta.contains("opus"))
        #expect(rows[0].meta.contains("default"))
    }

    @Test("模型缺失時 meta 不顯示空白欄位")
    func metaHandlesMissingModel() {
        let rows = PanelViewModel.rows(from: [state("p", .working, model: nil)], now: now)
        #expect(!rows[0].meta.hasPrefix(" ·"), "不得留下懸空的分隔符，實際：\(rows[0].meta)")
        #expect(rows[0].meta.contains("default"))
    }

    // ---- 時間格式化與時鐘倒退 ----

    @Test("時鐘倒退時不顯示負數")
    func clockSkewClampsToZero() {
        // updatedAt 在未來
        let s = state("p", .working, updated: -600)
        let rows = PanelViewModel.rows(from: [s], now: now)
        #expect(!rows[0].relativeTime.contains("-"), "實際：\(rows[0].relativeTime)")
    }

    @Test("turnStartedAt 在未來時，本輪時長不是負數")
    func futureTurnStartClamps() {
        let s = state("p", .working, turnStart: -300)
        let rows = PanelViewModel.rows(from: [s], now: now)
        #expect(!rows[0].detail.contains("-"), "實際：\(rows[0].detail)")
    }

    @Test("時長格式在各量級都可讀")
    func durationFormatting() {
        #expect(PanelViewModel.duration(0) == "0s")
        #expect(PanelViewModel.duration(45).contains("45"))
        #expect(PanelViewModel.duration(90).contains("1m"))
        #expect(PanelViewModel.duration(3_700).contains("1h"))
        #expect(PanelViewModel.duration(-5) == "0s", "負數 clamp 到 0")
    }

    // ---- 標題 ----

    @Test("標題把「有人在等你」放在最前面")
    func titleLeadsWithAttention() {
        let icon = IconState(activity: .waiting,
                             counts: [.waiting: 1, .working: 2], liveCount: 3)
        let t = PanelViewModel.title(for: icon)
        #expect(t.contains("1"))
        #expect(t.contains("等"), "實際：\(t)")
    }

    @Test("沒有 session 時標題明確說沒有，不留空白")
    func titleWhenEmpty() {
        #expect(!PanelViewModel.title(for: .empty).isEmpty)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

Run: `swift test --filter PanelViewModelTests`
Expected: FAIL — `cannot find 'PanelViewModel' in scope`（以及 `SessionState` 缺 `toolError` 參數）

- [ ] **Step 3: 確認 `SessionState.toolError` 已存在**

Task 07 就宣告了它，`SessionReducer` 也已帶過來。本 task 不需要改那兩個檔。

Run: `grep -n toolError Sources/AuraCore/SessionState.swift Sources/AuraCore/SessionReducer.swift`
Expected: 各一行

- [ ] **Step 4: 實作 PanelViewModel**

```swift
// Sources/AuraCore/PanelViewModel.swift
import Foundation

public struct PanelRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let projectName: String
    public let activity: Activity
    public let headline: String
    public let detail: String
    public let meta: String
    public let relativeTime: String
    public let isEnded: Bool
}

/// 面板的呈現邏輯。純函數，所以排序、截斷、時間格式化都可測 ——
/// 這些是最容易在 UI 層被寫成「看起來對」但邊界錯的東西（負數時長、懸空分隔符、
/// 未截斷的長訊息把面板撐爆）。
public enum PanelViewModel {

    public static func rows(from states: [SessionState], now: Date = Date()) -> [PanelRow] {
        states
            .sorted { a, b in
                // 與 D1 一致：優先序高的在前
                if a.activity != b.activity { return a.activity > b.activity }
                // 活著的優先於已結束的
                let aEnded = a.liveness == .ended, bEnded = b.liveness == .ended
                if aEnded != bEnded { return !aEnded }
                // 同組內最近活動優先
                return a.updatedAt > b.updatedAt
            }
            .map { row(for: $0, now: now) }
    }

    static func row(for s: SessionState, now: Date) -> PanelRow {
        PanelRow(id: s.id,
                 projectName: s.projectName,
                 activity: s.activity,
                 headline: headline(for: s),
                 detail: detail(for: s, now: now),
                 meta: meta(for: s),
                 relativeTime: relativeTime(from: s.updatedAt, now: now),
                 isEnded: s.liveness == .ended)
    }

    static func headline(for s: SessionState) -> String {
        switch s.activity {
        case .waiting:
            let what = s.currentTool ?? "輸入"
            return "等你批准：\(what)"
        case .error:
            return s.toolError ?? s.errorType ?? "執行失敗"
        case .done:
            return summarise(s.lastMessage) ?? "已完成"
        case .working:
            if let sub = s.subagentTool { return sub }
            return s.currentTool ?? "執行中"
        case .idle:
            return "等你下指令"
        }
    }

    /// 完成訊息可能很長（實測有數千字），面板不能被它撐爆。
    static func summarise(_ text: String?, limit: Int = 80) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let flat = text.split(whereSeparator: \.isNewline)
            .first?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !flat.isEmpty else { return nil }
        return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
    }

    static func detail(for s: SessionState, now: Date) -> String {
        var parts: [String] = []
        if let start = s.turnStartedAt {
            parts.append("本輪 " + duration(now.timeIntervalSince(start)))
        }
        let subs = s.subagents.values.reduce(0, +)
        if subs > 0 { parts.append("\(subs) subagents") }
        if s.toolFailures > 0 { parts.append("\(s.toolFailures) tool 失敗") }
        return parts.joined(separator: " · ")
    }

    static func meta(for s: SessionState) -> String {
        [s.model, s.effort, s.permissionMode]
            .compactMap { $0 }                 // 缺值就整段省略，不留懸空分隔符
            .joined(separator: " · ")
    }

    public static func duration(_ seconds: Double) -> String {
        let t = Int(max(0, seconds))           // 時鐘倒退 clamp 到 0
        if t < 60 { return "\(t)s" }
        if t < 3_600 { return "\(t / 60)m \(t % 60)s" }
        return "\(t / 3_600)h \((t % 3_600) / 60)m"
    }

    public static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let t = max(0, now.timeIntervalSince(date))
        if t < 5 { return "剛剛" }
        return duration(t) + "前"
    }

    public static func title(for icon: IconState) -> String {
        let attention = icon.attentionCount
        if attention > 0 {
            let live = icon.liveCount
            return live > attention
                ? "\(attention) 個在等你 · \(live - attention) 個在跑"
                : "\(attention) 個在等你"
        }
        if icon.liveCount > 0 { return "\(icon.liveCount) 個 session 在跑" }
        let done = icon.counts[.done] ?? 0
        return done > 0 ? "\(done) 個已完成" : "沒有活著的 session"
    }
}
```

- [ ] **Step 5: 執行確認通過**

Run: `swift test --filter PanelViewModelTests`
Expected: 全部 PASS（16 個測試）

- [ ] **Step 6: 實作 SwiftUI 面板**

```swift
// Sources/AgentAuraApp/PanelView.swift
import SwiftUI
import AuraCore

struct PanelView: View {
    let title: String
    let rows: [PanelRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4))

            if rows.isEmpty {
                Text("沒有活著的 session")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            PanelRowView(row: row)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(width: 380)
    }
}

struct PanelRowView: View {
    let row: PanelRow

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(Self.color(row.activity))
                .frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.projectName).font(.system(size: 12, weight: .semibold))
                    Text(row.meta).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(row.headline)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(row.activity == .error ? .red : .primary)
                    .lineLimit(1).truncationMode(.middle)
                if !row.detail.isEmpty || row.isEnded {
                    Text([row.detail, row.isEnded ? "已結束 · \(row.relativeTime)" : row.relativeTime]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    static func color(_ a: Activity) -> Color {
        switch a {
        case .idle:    return .secondary
        case .working: return .blue
        case .waiting: return .orange
        case .done:    return .green
        case .error:   return .red
        }
    }
}
```

- [ ] **Step 7: 掛上 popover 並讓開啟即 acknowledge**

```swift
// Sources/AgentAuraApp/StatusItemController.swift —— 在 init 之後加入
    private let popover = NSPopover()
    var onOpen: (() -> Void)?

    func attachPopover() {
        popover.behavior = .transient
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
    }

    func setPanel(title: String, rows: [PanelRow]) {
        popover.contentViewController = NSHostingController(
            rootView: PanelView(title: title, rows: rows))
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // 開啟即 acknowledge（D2）—— 面板是唯一互動，用它當確認手勢
            onOpen?()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
```

`StatusItemController` 需要 `import SwiftUI`（`NSHostingController`）。

```swift
// Sources/AgentAuraApp/AppDelegate.swift —— applicationDidFinishLaunching 內，graph.start() 之前
        status.attachPopover()
        status.onOpen = { [weak self] in
            guard let self else { return }
            self.graph.acknowledgeAll()
            self.refreshPanel()
        }
```

```swift
// AppDelegate 新增方法
    private func refreshPanel() {
        let icon = graph.iconState
        // `graph.registry` 是 internal 且未加鎖 —— 走上鎖的 `visibleSessions`。
        // 這個 callback 會從 FSEvents 的背景 queue 觸發，直接讀 registry 就是 data race。
        let rows = PanelViewModel.rows(from: graph.visibleSessions)
        status.setPanel(title: PanelViewModel.title(for: icon), rows: rows)
    }
```

並在 `onIconStateChange` 的 main-actor block 裡一併呼叫 `refreshPanel()`。

- [ ] **Step 8: 建置 + 手動確認**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Test run with"
```

造幾個假狀態（含 waiting / done / error 各一）再跑 app，點 menu bar icon：
面板應列出三列、排序為 error → waiting → done，且**點開之後 icon 的橘/紅燈消失**
（acknowledge 生效）。

- [ ] **Step 9: Mutation 驗證**

依標準程序，三個：

1. `rows` 的排序改成只按 `updatedAt`（拿掉 activity 比較）→ `sortFollowsPriority` 必須 RED
2. `duration` 的 `max(0, seconds)` 改成 `seconds` →
   **`futureTurnStartClamps` 與 `durationFormatting` 必須 RED**

   > 這裡原本也列了 `clockSkewClampsToZero`，**那是錯的**（T17 的 implementer
   > 實測後回報）。原因：`clockSkewClampsToZero` 測的是 `relativeTime`，
   > 而 `relativeTime` 內部有**自己獨立的** `max(0, now.timeIntervalSince(date))`，
   > 在呼叫 `duration()` 之前就已經把值 clamp 到非負 —— 所以 `duration()` 內部的
   > clamp 被拿掉時，`relativeTime` 拿到的輸入本來就是 0，不受影響。
   >
   > 兩個獨立的 clamp 各自需要各自的 mutation。implementer 沒有為了讓它變紅
   > 而加斷言，處置正確。
3. `meta` 的 `compactMap { $0 }` 改成 `map { $0 ?? "" }` → `metaHandlesMissingModel` 必須 RED

第 3 個守的是「缺值不留懸空分隔符」—— 那是 UI 最典型的「看起來對，直到某個欄位缺值」。

- [ ] **Step 10: Commit**

```bash
git add Sources/AuraCore/PanelViewModel.swift Sources/AuraCore/SessionState.swift \
        Sources/AuraCore/SessionReducer.swift Sources/AgentAuraApp \
        Tests/AuraCoreTests/PanelViewModelTests.swift
git commit -F - <<'EOF'
feat(app): 面板 —— 排序、截斷、時間格式化都是可測的純函數

PanelViewModel 放 AuraCore：排序（與 D1 優先序一致）、完成訊息截斷、
時長格式化與時鐘倒退 clamp、缺值不留懸空分隔符 —— 這些是 UI 層最容易寫成
「看起來對，直到某個欄位缺值」的東西，所以放在可測的地方。

打開面板即 acknowledge（D2）：面板是唯一互動，用它當確認手勢摩擦最低。
EOF
```

---

### Task 18: .app bundle + 實機啟動驗收

**這個 task 結束時有一個可以雙擊執行的 AgentAura.app。**

**Files:**
- Create: `scripts/build-app.sh`
- Create: `Resources/Info.plist`
- Create: `scripts/verify-app.sh`
- Modify: `docs/INSTALL.md`

- [ ] **Step 1: Info.plist**

`LSUIElement` 是 menu bar app 的關鍵 —— 沒有它會出現 dock icon 與主視窗。

```bash
mkdir -p Resources
cat > Resources/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AgentAura</string>
    <key>CFBundleDisplayName</key><string>AgentAura</string>
    <key>CFBundleIdentifier</key><string>io.agentaura.app</string>
    <key>CFBundleExecutable</key><string>AgentAuraApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <!-- menu bar app：不要 dock icon、不要主視窗 -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
```

- [ ] **Step 2: 組 bundle 的腳本**

```bash
cat > scripts/build-app.sh <<'EOF'
#!/usr/bin/env bash
# 組出 AgentAura.app（universal），並驗證 bundle 結構與 LSUIElement。
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/AgentAura.app

echo "==> 建置 universal 執行檔"
swift build -c release --arch arm64   --product AgentAuraApp
swift build -c release --arch x86_64  --product AgentAuraApp

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/AgentAuraApp" \
  .build/arm64-apple-macosx/release/AgentAuraApp \
  .build/x86_64-apple-macosx/release/AgentAuraApp
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> 驗證"
lipo -archs "$APP/Contents/MacOS/AgentAuraApp"
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist"
test -x "$APP/Contents/MacOS/AgentAuraApp"

echo "==> ad-hoc 簽章（未簽章的 bundle 在部分系統設定下無法啟動）"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP" 2>&1 | tail -2

echo "==> $APP 就緒"
EOF
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

Expected: `lipo -archs` 含 `arm64` 與 `x86_64`；`LSUIElement` 為 `true`；簽章驗證通過。

- [ ] **Step 3: 實機啟動驗收腳本**

```bash
cat > scripts/verify-app.sh <<'EOF'
#!/usr/bin/env bash
# 實機驗收：造假狀態 → 啟動 app → 確認它活著且真的讀到狀態 → 收工。
set -uo pipefail
cd "$(dirname "$0")/.."
APP=build/AgentAura.app
ROOT="$HOME/.agentaura/sessions"
FAIL=0
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }

[ -d "$APP" ] || { bad "$APP 不存在 —— 先跑 scripts/build-app.sh"; exit 1; }

echo "== 1. 造三個假狀態（waiting / working / error）=="
mkdir -p "$ROOT"
python3 - <<'PY'
import json, pathlib, datetime
root = pathlib.Path.home()/".agentaura/sessions"
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z")
for sid, act in [("verify-waiting","waiting"), ("verify-working","working"), ("verify-error","error")]:
    (root/f"{sid}.json").write_text(json.dumps({
        "schema": 1, "session_id": sid, "hook_event_name": "PreToolUse",
        "written_at": now, "turn_started_at": now,
        "cwd": f"/Users/you/Code/Vibe/{sid}", "model": "claude-opus-5[1m]",
        "permission_mode": "default", "effort": "high",
        "main_activity": act, "main_tool": "Bash",
        "subagents": {}, "tool_failures": 0, "terminated": False,
    }, ensure_ascii=False))
print("  已造 3 個")
PY

echo "== 2. 啟動 app =="
open "$APP"
sleep 4
if pgrep -f "AgentAura.app/Contents/MacOS/AgentAuraApp" >/dev/null; then
  ok "app 在跑"
else
  bad "app 沒起來或已退出"
fi

echo "== 3. 確認沒有 dock icon（LSUIElement 生效）=="
# LSUIElement 的 app 不會出現在 Dock 的執行中清單
if osascript -e 'tell application "System Events" to get name of every process whose background only is false' 2>/dev/null | grep -q AgentAura; then
  bad "出現在前景 process 清單 —— LSUIElement 沒生效"
else
  ok "沒有 dock icon"
fi

echo "== 4. app 真的讀到狀態了嗎 =="
# 刪掉一個狀態檔，refreshLiveness 應在 5s 內移除它；用「app 沒 crash」當代理指標
rm -f "$ROOT/verify-working.json"
sleep 7
if pgrep -f "AgentAura.app/Contents/MacOS/AgentAuraApp" >/dev/null; then
  ok "狀態檔被外部刪除後 app 仍存活（refreshLiveness 沒炸）"
else
  bad "app 在狀態檔被刪後掛掉"
fi

echo "== 5. 收工 =="
pkill -f "AgentAura.app/Contents/MacOS/AgentAuraApp" 2>/dev/null && ok "已關閉" || ok "已不在執行"
rm -f "$ROOT"/verify-*.json
ok "假狀態已清除"

echo
[ "$FAIL" -eq 0 ] && echo "實機驗收 PASS" || echo "實機驗收 FAIL"
exit "$FAIL"
EOF
chmod +x scripts/verify-app.sh
./scripts/verify-app.sh
```

Expected: 五項全 ✓，最後印 `實機驗收 PASS`。

**肉眼確認（腳本無法代替）**：app 跑起來時看 menu bar 右側 ——
應出現**紅色 double blink 的燈條**（三個假狀態裡有一個 error，D1 優先序取最大），
點一下應開出面板列出三列、排序 error → waiting → working。

- [ ] **Step 4: 更新 INSTALL.md —— 補上 app 的建置與啟動**

> **錨點必須對到 `INSTALL.md` 的現況。** 這一段原本拿 marketplace 流程當 `OLD`，
> 但 T14 的 fix round 已把安裝改成 skills-dir 掛載 —— `s.count(OLD)` 是 0，assert 會炸。
> （T18 的 implementer 正確地停下來回報而不是自行調整錨點，那個 assert 護欄起了作用。）

用 Edit 工具直接改 `docs/INSTALL.md`（不要用腳本 —— 這段本身就是「錨點會 drift」的案例）：

**4a.** 在「## 安裝」的程式碼區塊裡，把

```
./scripts/verify-install.sh                          # 驗證整條鏈路
```

換成

```
./scripts/verify-install.sh                          # 驗證 hook 鏈路

./scripts/build-app.sh                               # 組出 build/AgentAura.app
./scripts/verify-app.sh                              # 實機啟動驗收
open build/AgentAura.app                             # 開始使用
```

並在該區塊之後補一行：

> 要開機自動啟動：把 `build/AgentAura.app` 拖進「系統設定 → 一般 → 登入項目」。

**4b.** 在「## 完整移除」的程式碼區塊**最前面**補兩行：

```
pkill -f AgentAura.app            # 關掉 app
rm -rf build/AgentAura.app        # 刪掉 app（建置產物，隨時可重建）
```

（原有的 `rm ~/.claude/skills/agentaura` 與 `rm -rf ~/.agentaura` 兩行保留不動 ——
`installDocHasUninstall` 斷言的正是那兩行。）

Run: `swift test --filter installDocHasUninstall`
Expected: 仍然 PASS（斷言的 `rm ~/.claude/skills/agentaura` 與 `ln -sfn` 都還在）。
- [ ] **Step 4b: 把 `build/` 加入 `.gitignore`（建置產物不進版控）**

```bash
grep -q '^build/$' .gitignore || printf 'build/\n' >> .gitignore
git check-ignore -v build/    # 必須印出命中的規則
```

> T14 已經為 `plugin/bin/` 做過同一件事，這裡漏了 —— `build/AgentAura.app`
> 是 universal binary + bundle，數十 MB，絕不該進版控。

- [ ] **Step 5: Commit**

```bash
git add .gitignore Resources/Info.plist scripts/build-app.sh scripts/verify-app.sh docs/INSTALL.md
git commit -F - <<'EOF'
feat(app): .app bundle + 實機啟動驗收 —— 第一個可雙擊執行的版本

LSUIElement 是關鍵：沒有它 menu bar app 會出現 dock icon 與主視窗。
verify-app.sh 的第 3 項就是驗這件事（查前景 process 清單裡沒有 AgentAura），
因為那是「看起來能跑但形態錯了」最容易漏掉的一項。

第 4 項刻意刪掉一個狀態檔再等 7 秒：refreshLiveness 每 5s 跑一次，
這驗的是「外部刪檔不會讓 app 掛掉」——那條路徑在 spec §4 有，但只有實機
啟動才驗得到。
EOF
```

---
