import Testing
import Foundation
@testable import AuraHookFile
import AuraCore

/// spec §8 的 probe 成本門檻**唯一的常駐 gate**（T10a 補上——integrator 是臨場量的，
/// 量完就沒了，沒有任何東西擋得住下一次回歸）。
///
/// **它守的是「類別」不是「毫秒數」**：`probe()` 必須維持「固定次數的 syscall」，
/// 不得長出目錄列舉、遞迴走訪或 exec（那些是**毫秒**級，會直接撞穿這個上限）。
///
/// **T10b：從絕對時間上限改成相對控制組的倍率**（T10a 剛加的 `30 ms` 絕對上限，自己就在
/// 全套件並行的 20 次連跑裡紅了 4 次——跟這個 change 要關掉的另一類 flake 同一個病灶：
/// 用絕對時間量負載會抖動的東西）。控制組在**同一次執行**裡，用跟 `probe()` 同一組
/// syscall（`lstat`／`readlink`／`realpath`／`stat`×4／`access`）直接打 libc，不經過
/// `Installer`。並行負載會讓兩邊**同時**變慢，比值因此穩定；而「長出目錄列舉／遞迴走訪／
/// exec」只會讓 probe 那組暴衝、不會讓控制組跟著暴衝——比值一樣抓得到回歸。
///
/// **實測（本機，未並行，連跑 5 次取樣）**：倍率落在 1.51x–1.74x。上限給到 **4x**——
/// 距實測上緣還有 >2 倍餘裕，吸收「並行負載讓兩邊變慢的程度不完全同步」這件事，
/// 同時遠低於「多出一次目錄列舉」會撞出的倍率（mutation 實測見 commit message）。
@Suite("Installer probe 成本（§8）", .serialized)
struct InstallerProbeCostTests {

    /// 控制組：`probe()` 在 connected 狀態下已知一定要做的那組 syscall，直接打 libc，
    /// 不經過 `Installer`——`lstat` ＋ `readlink` ＋ `realpath` ＋ `stat`(resolved) ＋
    /// `stat`+`access`(bin) ＋ `stat`(hooks.json) ＋ `stat`(bundlePlugin) ＋ `stat`(claudeHome)。
    private static func controlGroupOnce(claudeHomePath: String, linkPath: String, resolvedPath: String,
                                         hooksJSONPath: String, binPath: String, bundlePluginPath: String) {
        var st = stat()
        _ = stat(claudeHomePath, &st)
        _ = lstat(linkPath, &st)
        var buf = [Int8](repeating: 0, count: 1024)
        _ = readlink(linkPath, &buf, buf.count)
        if let raw = realpath(linkPath, nil) { free(raw) }
        _ = stat(resolvedPath, &st)
        _ = stat(hooksJSONPath, &st)
        _ = stat(binPath, &st)
        _ = access(binPath, X_OK)
        _ = stat(bundlePluginPath, &st)
    }

    @Test("connected 狀態下 100 次 probe 相對控制組的倍率不得超過 4x（守的是「沒有列舉／沒有 exec」，負載不敏感）")
    func probeCostStaysBoundedRelativeToControlGroup() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        // T10b：只有這一次性的 setup connect() 會真的 spawn，經過 SpawnGate；下面的計時迴圈
        // 只呼叫 probe()（不 spawn），刻意留在閘門外——量的是 probe 本身，不該被序列化影響。
        _ = try await SpawnGate.shared.run {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }

        // 前提：真的處於 connected（走完整條最長路徑），否則量到的是 early-return 的便宜版本
        let state = InstallState.from(installer.probe(), verification: .verified)
        guard case .connected = state else {
            Issue.record("前提失敗：fixture 應該是 connected，實際 \(state)——量到的會是 early return 的路徑")
            return
        }

        let claudeHomePath = layout.claudeHome.path
        let linkPath = layout.claudeHome.appendingPathComponent("skills/agentaura").path
        guard let resolvedCStr = realpath(linkPath, nil) else {
            Issue.record("前提失敗：realpath(\(linkPath)) 解析不出來，控制組建不起來")
            return
        }
        let resolvedPath = String(cString: resolvedCStr)
        free(resolvedCStr)
        let hooksJSONPath = resolvedPath + "/hooks/hooks.json"
        let binPath = resolvedPath + "/bin/aura-hook"
        let bundlePluginPath = layout.bundlePlugin.path

        // 暖機：兩邊各跑一次，付掉 fixture 路徑第一次觸碰的快取成本。
        _ = installer.probe()
        Self.controlGroupOnce(claudeHomePath: claudeHomePath, linkPath: linkPath, resolvedPath: resolvedPath,
                              hooksJSONPath: hooksJSONPath, binPath: binPath, bundlePluginPath: bundlePluginPath)

        let probeStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<100 { _ = installer.probe() }
        let probeElapsed = DispatchTime.now().uptimeNanoseconds - probeStart

        let controlStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<100 {
            Self.controlGroupOnce(claudeHomePath: claudeHomePath, linkPath: linkPath, resolvedPath: resolvedPath,
                                  hooksJSONPath: hooksJSONPath, binPath: binPath, bundlePluginPath: bundlePluginPath)
        }
        let controlElapsed = DispatchTime.now().uptimeNanoseconds - controlStart

        let ratio = Double(probeElapsed) / Double(max(controlElapsed, 1))
        #expect(ratio <= 4, """
            probe() 100 次相對控制組 100 次的倍率是 \(String(format: "%.2f", ratio))x（上限 4x）。
            probe \(Double(probeElapsed) / 1_000_000) ms，控制組 \(Double(controlElapsed) / 1_000_000) ms。
            實測基準 ≈ 1.3x；超過 4x 幾乎只有一種成因——probe 長出了目錄列舉、遞迴走訪或 exec，
            這些是控制組不會有、但會讓 probe 那組單獨暴衝的成本。exec 驗證**只准**在
            connect／replaceExternalMount／啟動背景驗證這三條路徑（spec §4.1），
            面板每次開啟的 probe 一律不得 exec。
            """)
    }
}
