/// T29：`AppEnvironment.swift` 的兩個較輕量確認框（移除掛載／改指向這個 App）＋兩者共用的
/// 「取消」按鈕＋`AppDelegate+Connect.swift` 的三句連線失敗訊息（帶底層錯誤描述）＋一句
/// 「需要系統設定核准」的固定文案。完整移除確認框另成一個檔案（`L10nUninstallConfirmation.swift`）
/// ——內容更長、且有自己專屬的中英語意 gate（`UninstallConfirmationCopyTests`），
/// 分開才不會把兩種確認框的翻譯攪在一起（同 `L10nPanelBanner` doc comment講的切法）。
public enum L10nConfirmationAlerts: L10nCatalog, Sendable {
    /// 三個確認框（含 `L10nUninstallConfirmation`）共用同一顆「取消」按鈕。
    case cancelButtonTitle
    case disconnectTitle
    case disconnectBody
    case disconnectConfirmButton
    case replaceMountTitle
    case replaceMountBody
    case replaceMountConfirmButton
    /// T13j（S1-5，D-ac）：`.disconnectCodex` 的確認框——比照 `disconnectTitle`／
    /// `disconnectBody`／`disconnectConfirmButton` 的既有形狀，但**點名 Codex**
    /// （對照既有 `disconnectTitle` 已經點名 Claude Code）。目前 `.disconnectCodex`
    /// 直接進 `performDisconnectCodex()`，一下點擊直接刪 `~/.codex/hooks.json`，
    /// 而列標題結尾有刪節號——macOS 慣例裡刪節號的意思是「按下去會先問你」，
    /// 相鄰的 Claude 那列會問、Codex 這列不問，兩列不對稱（persona r1 S1-5）。
    case disconnectCodexTitle
    case disconnectCodexBody
    case disconnectCodexConfirmButton
    /// `LoginItemError.requiresApproval`：無條件成功但系統要求手動核准登入項目。
    case loginItemRequiresApproval

    public func text(_ language: Language) -> String {
        switch self {
        case .cancelButtonTitle:
            switch language {
            case .english: return "Cancel"
            case .traditionalChinese: return "取消"
            }
        case .disconnectTitle:
            switch language {
            case .english: return "Remove the Claude Code mount?"
            case .traditionalChinese: return "移除 Claude Code 掛載？"
            }
        case .disconnectBody:
            switch language {
            case .english:
                return """
                    This removes the ~/.claude/skills/agentaura mount, so Claude Code's hook stops reporting execution status.

                    This won't delete AgentAura itself, any session history, or your color settings — AgentAura stays \
                    in the menu bar, and you can reconnect anytime by tapping Connect.
                    """
            case .traditionalChinese:
                return """
                    這會移除 ~/.claude/skills/agentaura 這個掛載，讓 Claude Code 的 hook 停止回報執行狀態。

                    不會刪除 AgentAura 本身、不會刪除任何 session 紀錄或你的顏色設定——AgentAura 會留在選單列，\
                    要再用的話隨時可以按「接上」。
                    """
            }
        case .disconnectConfirmButton:
            switch language {
            case .english: return "Remove mount"
            case .traditionalChinese: return "移除掛載"
            }
        case .replaceMountTitle:
            switch language {
            case .english: return "Point at this app instead?"
            case .traditionalChinese: return "改指向這個 App？"
            }
        case .replaceMountBody:
            switch language {
            case .english:
                return """
                    The current mount points somewhere else (e.g. your own development repo). Pointing it at this \
                    app instead switches that mount to the app's built-in version — the original mount stops working.

                    This won't delete any files the original mount pointed to — it only changes where \
                    ~/.claude/skills/agentaura points. To switch back, reconnect from the original location.
                    """
            case .traditionalChinese:
                return """
                    目前的掛載指向別的地方（例如你自己的開發用 repo）。改指向這個 App 之後，
                    那份掛載會被換成 App 內建的版本，原本的掛載不會再生效。

                    不會刪除原本掛載指向的任何檔案——只是換了 ~/.claude/skills/agentaura 指向哪裡，
                    要換回去的話可以到原本的位置重新接上一次。
                    """
            }
        case .replaceMountConfirmButton:
            switch language {
            case .english: return "Point at this app"
            case .traditionalChinese: return "改指向這個 App"
            }
        case .disconnectCodexTitle:
            switch language {
            case .english: return "Remove the Codex mount?"
            case .traditionalChinese: return "移除 Codex 掛載？"
            }
        case .disconnectCodexBody:
            switch language {
            case .english:
                return """
                    This removes the entry AgentAura wrote into ~/.codex/hooks.json, so Codex's hook stops \
                    reporting execution status — but only if that file still matches exactly what we wrote; \
                    anything else in it is left untouched.

                    This won't delete AgentAura itself, any session history, or your color settings — AgentAura stays \
                    in the menu bar, and you can reconnect anytime by tapping Connect.
                    """
            case .traditionalChinese:
                return """
                    這會移除 AgentAura 寫進 ~/.codex/hooks.json 的那份設定，讓 Codex 的 hook 停止回報執行狀態\
                    ——但只有在那份檔案內容還跟我們寫的逐位元組相符時才會刪除，其餘內容不會被動到。

                    不會刪除 AgentAura 本身、不會刪除任何 session 紀錄或你的顏色設定——AgentAura 會留在選單列，\
                    要再用的話隨時可以按「接上」。
                    """
            }
        case .disconnectCodexConfirmButton:
            switch language {
            case .english: return "Remove mount"
            case .traditionalChinese: return "移除掛載"
            }
        case .loginItemRequiresApproval:
            switch language {
            case .english:
                return "Go to System Settings → General → Login Items and allow AgentAura for this to take effect."
            case .traditionalChinese:
                return "需要在系統設定 → 一般 → 登入項目 允許 AgentAura，之後才會真的生效。"
            }
        }
    }

    /// `AppDelegate+Connect.swift` 的 `performConnect` catch 分支——帶系統錯誤描述。
    public static func connectFailed(underlying: String, language: Language) -> String {
        switch language {
        case .english: return "Couldn't connect: \(underlying)"
        case .traditionalChinese: return "接上失敗：\(underlying)"
        }
    }

    /// `performDisconnect` 的 catch 分支。
    public static func disconnectFailed(underlying: String, language: Language) -> String {
        switch language {
        case .english: return "Couldn't remove the mount: \(underlying)"
        case .traditionalChinese: return "移除掛載失敗：\(underlying)"
        }
    }

    /// `performSetLaunchAtLogin` 的兜底 catch 分支（不是 `.requiresApproval`／
    /// `.mustMoveToApplications` 那兩個已有專屬訊息的 case）。
    public static func setLaunchAtLoginFailed(underlying: String, language: Language) -> String {
        switch language {
        case .english: return "Couldn't set launch at login: \(underlying)"
        case .traditionalChinese: return "設定開機自動啟動失敗：\(underlying)"
        }
    }
}
