import AppKit

/// B4：「關於」面板帶實際內容——版本 ＋ 專案網址 ＋ 授權。此前 `showAboutPanel` 只呼叫
/// `NSApp.orderFrontStandardAboutPanel(nil)`，使用者看到的是完全空的 standard panel，
/// 一個字都沒有。純函式，注入到 `AppDelegate.showAboutPanel`；gate 斷言拿到的字典
/// 含版本字串與專案網址，不是只斷言「被呼叫」。
enum AboutContent {
    /// README §授權目前寫「尚未決定（開源時確定）」——這裡照實寫，不能瞎掰一個授權名字
    /// （同 CLAUDE.md「畫面宣稱了它無法保證的事」那個病族，只是換成關於面板）。
    static let license = "授權：尚未決定（開源時確定）"

    /// `.credits` 是 standard about panel 唯一能放自由格式文字（含可點的網址）的欄位——
    /// 版本另走 `.applicationVersion`，兩者是 gate 斷言的兩個獨立來源。
    static func options(version: String) -> [NSApplication.AboutPanelOptionKey: Any] {
        let credits = NSMutableAttributedString(string: license + "\n\n")
        credits.append(NSAttributedString(string: ProjectLinks.repository.absoluteString,
                                          attributes: [.link: ProjectLinks.repository]))
        return [.applicationVersion: version, .credits: credits]
    }
}
