import Foundation

/// 系統色板（`NSColorPanel`）第一次出現的位置。
///
/// **兩次實機回報換來的規則**：
/// 1. 沒存過位置時 macOS 把它放在螢幕左下角——離剛剛點的那顆色點非常遠。
/// 2. 於是 T17 改成「掛在錨點正下方」——**那更糟**：面板本來就掛在選單列圖示下方，
///    色板被整個蓋住（`NSPopover` 的視窗層級在一般面板之上）。
///
/// 所以正解不是跟 z-order 打架，而是**不要重疊**：色板放在**面板旁邊**，上緣與面板對齊，
/// 優先放左側（選單列圖示通常靠右，左邊空間大），左側放不下就放右側。
///
/// 刻意只吃 `Double`、不吃 `CGRect`：`AuraCore` 不得載入 Foundation 閉包以外的 module
/// （`IsolationTests` 的白名單基準），而幾何型別來自 CoreGraphics。座標系沿用 AppKit
/// 的「原點在左下、y 往上增加」。
public enum ColorPanelPlacement {
    public struct Origin: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    /// - Parameters:
    ///   - avoidMinX/avoidMaxX/avoidMaxY: **要避開的矩形**（已顯示的面板；面板還沒開時
    ///     退回選單列圖示的位置）。只需要它的左右緣與上緣——垂直靠上緣對齊，
    ///     水平靠左右緣決定放哪一側。
    ///   - gap: 色板與面板之間的間距
    /// - Returns: 色板左下角座標，**保證完全落在可見範圍內，且在放得下的情況下不與 avoid 重疊**。
    public static func origin(avoidMinX: Double, avoidMaxX: Double, avoidMaxY: Double,
                             panelWidth: Double, panelHeight: Double,
                             visibleMinX: Double, visibleMaxX: Double,
                             visibleMinY: Double, visibleMaxY: Double,
                             gap: Double = 12) -> Origin {
        // 垂直：上緣與面板上緣對齊（兩者都掛在選單列下方），再夾進可見範圍
        let maxY = max(visibleMinY, visibleMaxY - panelHeight)
        let y = min(max(avoidMaxY - panelHeight, visibleMinY), maxY)

        // 水平：優先左側；左側放不下就右側；兩側都放不下才夾進可見範圍（此時必然會重疊，
        // 但那是「螢幕真的太窄」，不是規則錯——由呼叫端的 gate 明確記錄這個退化情形）
        let maxX = max(visibleMinX, visibleMaxX - panelWidth)
        let left = avoidMinX - gap - panelWidth
        let right = avoidMaxX + gap
        let x: Double
        if left >= visibleMinX {
            x = left
        } else if right <= maxX {
            x = right
        } else {
            x = min(max(left, visibleMinX), maxX)
        }
        return Origin(x: x, y: y)
    }
}
