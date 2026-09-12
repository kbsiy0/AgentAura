import Foundation
import Security

/// `SecTranslocateIsTranslocatedURL` 沒有公開的 Swift overlay 宣告（實測 `import Security`
/// 之後直接呼叫是「cannot find in scope」——它是私有／未公開頭檔的 C symbol，不是 Swift
/// 看不到 Security module），標準解法是用 `@_silgen_name` 直接綁定符號、不需要 bridging
/// header（實測：`nm` 在現代 macOS 讀不到系統框架二進位——已進 dyld shared cache——
/// 但 `@_silgen_name` 綁定後照樣連結成功、呼叫回傳合理值）。
@_silgen_name("SecTranslocateIsTranslocatedURL")
private func SecTranslocateIsTranslocatedURL(
    _ path: CFURL, _ isTranslocated: UnsafeMutablePointer<DarwinBoolean>,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool

/// spec §4.1／§4.2（S1-A4／S1-S3）：`translocated`／`inDownloads` 只准算在 app 層——
/// `AuraHookFile` 的白名單只有 Foundation ＋ CoreServices，`import Security` 不准出現在那裡。
/// `Installer.connect(...)`／`LoginItem.init` 都把這兩個布林當**注入參數**，這裡是唯一的
/// 生產計算點。
enum RunningBundle {
    /// App Translocation：Gatekeeper 把「從下載的 zip／DMG 直接雙擊」的 app 跑在一個
    /// 唯讀、隨機命名的臨時掛載點——那個路徑會在下一次啟動消失，掛上去的 symlink
    /// 會變成斷鏈（S1-A4）。`SecTranslocateIsTranslocatedURL` 是唯一能問出「現在是不是
    /// 這種臨時掛載」的 API；失敗（非 translocated 或 API 本身出錯）一律回 `false`——
    /// 這一格判斷錯的代價是「多擋一次使用者」，比「靜默接上一個會消失的路徑」安全。
    static func isTranslocated(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        var isTranslocated: DarwinBoolean = false
        let status = SecTranslocateIsTranslocatedURL(bundleURL as CFURL, &isTranslocated, nil)
        return status && isTranslocated.boolValue
    }

    /// `~/Downloads` 同理會消失（使用者清下載資料夾、或 App 只是暫放在那裡還沒搬進
    /// 「應用程式」）——不需要 Security API，直接比較已解析的絕對路徑前綴。
    static func isInDownloads(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let downloads else { return false }
        let resolvedBundle = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedDownloads = downloads.resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedBundle == resolvedDownloads
            || resolvedBundle.hasPrefix(resolvedDownloads + "/")
    }
}
