import AppKit

// menu bar app：不要 dock icon、不要主視窗。
// 以裸執行檔跑時 setActivationPolicy 就足夠；.app bundle 另由 Info.plist
// 的 LSUIElement 宣告（Task 18）。
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
