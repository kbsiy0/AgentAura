import AppKit

// menu bar app：不要 dock icon、不要主視窗。
// 以裸執行檔跑時 setActivationPolicy 就足夠；.app bundle 另由 Info.plist
// 的 LSUIElement 宣告（Task 18）。
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// r1 review M4：confirmDisconnectCodex 沒有預設值（同 codexDependencies 的既有理由），
// 生產路徑在這裡明傳真的確認框。
let delegate = AppDelegate(
    confirmDisconnectCodex: { language, onConfirm in
        CodexDisconnectConfirmation.present(language: language, onConfirm: onConfirm)
    },
    codexDependencies: .production())
app.delegate = delegate
app.run()
