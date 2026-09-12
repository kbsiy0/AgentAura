import Foundation

/// T19 配套 C：底板關閉時，狀態色直接疊在選單列上——這個純函式判斷某個顏色在「淺色選單列」
/// 背景下是否幾乎看不見。純 WCAG 相對亮度對比（sRGB），零外部依賴，`OptionsMenuModel` 用它
/// 決定「燈條底板」列要不要給提醒（見該檔 `lightBarWarning`）。
///
/// **背景參照＝純白 `#ffffff`＝最壞情況，不是量錯**：這是淺色選單列在亮度軸上的上界——真實
/// 選單列就算透出桌布，亮度也不會超過純白。用它當參照代表「連最壞情況都看不見才值得提醒」，
/// 比挑一個實測透明度／桌布組合更保守，也更不會漏掉真正的問題（`docs/2026-09-09-m4-ab-decision.md`
/// 量過同一塊底板在不同桌布下的選單列實色差很多，沒有單一「真實」淺色選單列色可挑）。
/// team-lead 實機量到的「淺色選單列」白色是 1.12:1（用她量到的半透明選單列近似色當參照，
/// 比純白暗一點）；這裡用純白算出白色對比恆為 1.00:1——**兩者參照背景不同，不是誰量錯**，
/// 純白更保守（更早觸發提醒），2026-09-11 team-lead 確認採用這個版本。
///
/// **門檻 < 1.5:1**：team-lead 建議的量級，本檔獨立算過驗證（不是抄她表上的數字——她給的是
/// 不同參照背景下的對照值，見上段）。以目前的狀態色驗證：白 → 1.00:1（觸發）；
/// 舊預設 systemBlue → 3.65:1、目前 waiting/error/done → 約 2.06／3.41／2.02:1（皆不觸發）——
/// 四色與白色之間有 > 0.5 的安全邊界，不是卡在門檻邊緣的巧合值。
public enum ContrastCheck {
    private static let lightBar = RGBA(r: 1, g: 1, b: 1, a: 1)

    private static func linearize(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func relativeLuminance(_ c: RGBA) -> Double {
        0.2126 * linearize(c.r) + 0.7152 * linearize(c.g) + 0.0722 * linearize(c.b)
    }

    /// WCAG 相對亮度對比（≥ 1，與順序無關）。
    static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        let (hi, lo) = la >= lb ? (la, lb) : (lb, la)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// `rgba` 疊在淺色選單列（以純白近似）上是否幾乎看不見（對比 < 1.5:1）。
    public static func lowOnLightBar(_ rgba: RGBA) -> Bool {
        contrast(rgba, lightBar) < 1.5
    }
}
