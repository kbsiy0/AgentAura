import Testing
import Foundation
import AuraCore
@testable import AuraHookFile

/// T06：R-8 不變式 1（檔案半）——CX37a／CX37b（spec §4.4／§4.8／§6.3）。兩側的安裝物件
/// 不重疊是兩條**獨立** gate（`installerTouchesOnlyAllowedPaths`／CX14）各自的結論，
/// 這裡驗的是**交錯操作**本身：對任一側做任意序列的 connect／disconnect／reconnect，
/// 另一側的檔案（＋這裡額外量的 mtime，見下方說明）必須零變動。
@Suite("兩側互不干擾——檔案半（CX37a／CX37b）")
struct CodexCoexistenceSequenceTests {

    /// 五個操作，**程式推導**序列用（不手列）。
    enum Operation: CaseIterable, CustomStringConvertible {
        case connectClaude, connectCodex, disconnectClaude, disconnectCodex, reconnectCodexStale

        var description: String {
            switch self {
            case .connectClaude: "connectClaude"
            case .connectCodex: "connectCodex"
            case .disconnectClaude: "disconnectClaude"
            case .disconnectCodex: "disconnectCodex"
            case .reconnectCodexStale: "reconnectCodex(stale)"
            }
        }
    }

    /// 全部長度 1...maxLength 的序列，笛卡兒積展開——**不手列**，數量由這個函式本身決定
    /// （長度 n 貢獻 5^n 條）。
    static func sequences(maxLength: Int) -> [[Operation]] {
        var all: [[Operation]] = []
        var currentLength: [[Operation]] = [[]]
        for _ in 1...maxLength {
            currentLength = currentLength.flatMap { prefix in Operation.allCases.map { prefix + [$0] } }
            all.append(contentsOf: currentLength)
        }
        return all
    }

    private static let hookBinaryPath = "/Applications/AgentAura.app/Contents/MacOS/aura-hook"

    // MARK: - CX37a（零 spawn，全部 5+25+125+625=780 條）

    /// **為什麼跳過 spawn 是等價的**（見 §4.8）：`claudeHome` 底下唯一會被
    /// `performConnectSteps()` 碰到的兩步是 `guardWriteTarget()` ＋ `atomicReplace()`；
    /// `verifyByExecuting` 對 `claudeHome` 的樹沒有任何貢獻（只寫
    /// `verificationRootOverride` 指定的位置，`removexattr` 作用在 bundle 內的二進位）。
    /// 直接呼叫這兩步，先例是 `InstallerClobberTests.performConnectStepsGuardsWriteTargetDirectly`。
    /// **與 CX37b 互相點名**：這條跳過的 exec 驗證，CX37b 用生產路徑補上。
    @Test("CX37a：長度 1–4 全部 780 條序列，每步後另一側零差異；結束時兩側皆 connected 則 probe() 皆為 connected",
          arguments: Self.sequences(maxLength: 4))
    func bothSidesNeverDisturbEachOthersFiles(_ sequence: [Operation]) throws {
        let layout = try CodexTwoSidedFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        var claudeConnected = false
        var lastWrittenCodexJSON: Data?

        for op in sequence {
            let artifactPath = otherSideArtifactPath(for: op, layout: layout)
            let mtimeBefore = mtimeStamp(atPath: artifactPath)
            let snapshotBefore = otherSideSnapshot(for: op, layout: layout)

            switch op {
            case .connectClaude:
                if (try? performConnectClaudeDirect(installer)) != nil { claudeConnected = true }
            case .disconnectClaude:
                if (try? installer.disconnect()) != nil { claudeConnected = false }
            case .connectCodex:
                performConnectCodex(codexInstaller, lastWritten: &lastWrittenCodexJSON)
            case .disconnectCodex:
                performDisconnectCodex(codexInstaller, lastWritten: &lastWrittenCodexJSON)
            case .reconnectCodexStale:
                performReconnectCodexStale(codexInstaller, lastWritten: &lastWrittenCodexJSON)
            }

            let mtimeAfter = mtimeStamp(atPath: artifactPath)
            #expect(mtimeBefore == mtimeAfter,
                    "\(op) 之後另一側關鍵檔案的 mtime 不得被動到：\(artifactPath)，序列 \(sequence)")
            let snapshotAfter = otherSideSnapshot(for: op, layout: layout)
            let delta = DirectoryTreeSnapshot.changedPaths(before: snapshotBefore, after: snapshotAfter)
            #expect(delta.isEmpty, "\(op) 之後另一側必須零差異，實際：\(delta.sorted())，序列 \(sequence)")
        }

        try assertBothConnectedImpliesBothProbeConnected(
            installer: installer, codexInstaller: codexInstaller,
            claudeConnected: claudeConnected, lastWrittenCodexJSON: lastWrittenCodexJSON, sequence: sequence)
    }

    // MARK: - CX37b（生產路徑，含 spawn，長度 ≤2 共 30 條）

    /// **為什麼只到長度 2**：這條走完整 `installer.connect(force:translocated:inDownloads:)`，
    /// 每個 `connectClaude` 都可能真的 `Process().run()`——長度 4 的 780 條會是 2930 次操作
    /// 等級的 spawn 量，在全套件並行下會把機器灌滿（同 `SpawnGate` 文件講的既有教訓）。
    /// 長度 ≤2（30 條）已經涵蓋「任兩個操作前後緊鄰」的每一種組合，接住 CX37a 跳過
    /// spawn 驗證可能漏掉的東西；再往上加長度只是同一種组合的重複排列，不是新的風險面。
    /// **與 CX37a 互相點名**：CX37a 用零 spawn 的等價呼叫覆蓋全部 780 條長序列。
    @Test("CX37b：長度 1–2 共 30 條，connectClaude 走完整 connect()（含 spawn），每步後另一側零差異",
          arguments: Self.sequences(maxLength: 2))
    func bothSidesNeverDisturbEachOthersFilesOnProductionPath(_ sequence: [Operation]) async throws {
        let layout = try CodexTwoSidedFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        var claudeConnected = false
        var lastWrittenCodexJSON: Data?

        for op in sequence {
            let artifactPath = otherSideArtifactPath(for: op, layout: layout)
            let mtimeBefore = mtimeStamp(atPath: artifactPath)
            let snapshotBefore = otherSideSnapshot(for: op, layout: layout)

            switch op {
            case .connectClaude:
                let succeeded = (try? await SpawnGate.shared.run {
                    try installer.connect(force: false, translocated: false, inDownloads: false)
                }) != nil
                if succeeded { claudeConnected = true }
            case .disconnectClaude:
                if (try? installer.disconnect()) != nil { claudeConnected = false }
            case .connectCodex:
                performConnectCodex(codexInstaller, lastWritten: &lastWrittenCodexJSON)
            case .disconnectCodex:
                performDisconnectCodex(codexInstaller, lastWritten: &lastWrittenCodexJSON)
            case .reconnectCodexStale:
                performReconnectCodexStale(codexInstaller, lastWritten: &lastWrittenCodexJSON)
            }

            let mtimeAfter = mtimeStamp(atPath: artifactPath)
            #expect(mtimeBefore == mtimeAfter,
                    "\(op) 之後另一側關鍵檔案的 mtime 不得被動到：\(artifactPath)，序列 \(sequence)")
            let snapshotAfter = otherSideSnapshot(for: op, layout: layout)
            let delta = DirectoryTreeSnapshot.changedPaths(before: snapshotBefore, after: snapshotAfter)
            #expect(delta.isEmpty, "\(op) 之後另一側必須零差異，實際：\(delta.sorted())，序列 \(sequence)")
        }

        try assertBothConnectedImpliesBothProbeConnected(
            installer: installer, codexInstaller: codexInstaller,
            claudeConnected: claudeConnected, lastWrittenCodexJSON: lastWrittenCodexJSON, sequence: sequence)
    }

    // MARK: - 共用步驟

    /// CX37a 專用：`connectClaude` 的零 spawn 等價呼叫（見上方 doc comment）。
    private func performConnectClaudeDirect(_ installer: Installer) throws {
        if !FileManager.default.fileExists(atPath: installer.skillsURL.path) {
            try FileManager.default.createDirectory(at: installer.skillsURL, withIntermediateDirectories: false)
        }
        try installer.guardWriteTarget()
        try installer.atomicReplace()
    }

    private func performConnectCodex(_ codexInstaller: CodexInstaller, lastWritten: inout Data?) {
        let json = CodexHooksJSON.json(hookBinaryPath: Self.hookBinaryPath)
        if let written = try? codexInstaller.connect(json: json, translocated: false, inDownloads: false) {
            lastWritten = written
        }
    }

    private func performDisconnectCodex(_ codexInstaller: CodexInstaller, lastWritten: inout Data?) {
        if (try? codexInstaller.disconnect(ifContentsEqual: lastWritten)) != nil {
            lastWritten = nil
        }
    }

    /// `reconnectCodex(stale)`：T06 範圍內沒有 `CodexState`（T07 才有），這裡以「先
    /// disconnect（best-effort）再 connect」表達 app 層 `performConnectCodex()` 在
    /// `.connectedStalePath` 下會做的事（R-9），純檔案層級的化簡。
    private func performReconnectCodexStale(_ codexInstaller: CodexInstaller, lastWritten: inout Data?) {
        _ = try? codexInstaller.disconnect(ifContentsEqual: lastWritten)
        lastWritten = nil
        performConnectCodex(codexInstaller, lastWritten: &lastWritten)
    }

    private func otherSideSnapshot(for op: Operation, layout: CodexTwoSidedFixture.Layout)
        -> [String: DirectoryTreeSnapshot.Entry] {
        switch op {
        case .connectClaude, .disconnectClaude:
            return DirectoryTreeSnapshot.take(root: layout.codexHome)
        case .connectCodex, .disconnectCodex, .reconnectCodexStale:
            return ClaudeHomeTreeSnapshot.take(claudeHome: layout.claudeHome)
        }
    }

    /// `DirectoryTreeSnapshot.Entry` 不含 mtime（只有 kind／mode／size／payload／
    /// symlinkTarget，見 `Tests/AuraCoreTests/Support/DirectoryTreeSnapshot.swift`）——
    /// 內容與型別都沒變、只是 mtime 被動過的 mutation（⑧：`CodexInstaller.connect`
    /// 順手 touch 另一側的關鍵檔案）不會反映在 `Entry` 的相等性上。這裡對「另一側」
    /// 那個具體會被 mutation ⑧ 碰到的檔案（`hooks.json` 或 `skills/agentaura`）
    /// 額外量一次 `st_mtimespec`，不修改共用的 `DirectoryTreeSnapshot`——那個型別
    /// 被 CX14／CX18／既有 Claude 側測試共用，加欄位會改變所有既有比對的語意
    /// （目錄本身的 mtime 會因為新增/移除子項而自然變動，牽動既有「差異恰為 {X}」
    /// 斷言），風險與本 task 的範圍不成比例。
    private func otherSideArtifactPath(for op: Operation, layout: CodexTwoSidedFixture.Layout) -> String {
        switch op {
        case .connectClaude, .disconnectClaude:
            return layout.codexHome.appendingPathComponent("hooks.json").path
        case .connectCodex, .disconnectCodex, .reconnectCodexStale:
            return layout.claudeHome.appendingPathComponent("skills/agentaura").path
        }
    }

    private struct MTimeStamp: Equatable { let sec: Int; let nsec: Int }

    private func mtimeStamp(atPath path: String) -> MTimeStamp? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return MTimeStamp(sec: st.st_mtimespec.tv_sec, nsec: Int(st.st_mtimespec.tv_nsec))
    }

    /// 序列結束時，若**我們自己的操作紀錄**認為兩側都已連上，`probe()` 獨立推導出的
    /// 狀態也必須都是 connected——這是唯一能讓「wiring 看似成功、實際 probe 讀不到」
    /// 這類 bug 被這條 gate 抓到的地方（同 Lessons #5 tested≠wired 的既有教訓）。
    private func assertBothConnectedImpliesBothProbeConnected(
        installer: Installer, codexInstaller: CodexInstaller,
        claudeConnected: Bool, lastWrittenCodexJSON: Data?, sequence: [Operation]
    ) throws {
        guard claudeConnected, lastWrittenCodexJSON != nil else { return }
        guard case .connected = InstallState.from(installer.probe(), verification: .unknown) else {
            Issue.record("序列認為 claude 已連上，但 probe() 推導的狀態不是 .connected，序列 \(sequence)")
            return
        }
        let codexObservation = codexInstaller.probe()
        #expect(codexObservation.entryType == .regularFile && codexObservation.contents == lastWrittenCodexJSON,
                "序列認為 codex 已連上，但 probe() 讀回的內容對不上，序列 \(sequence)")
    }
}
