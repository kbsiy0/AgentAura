import Testing
import Foundation
@testable import AuraCore

/// T17／T18：色板第一次出現的位置。兩次實機回報：
/// 1. 預設跑到螢幕左下角（離剛剛點的色點很遠）
/// 2. T17 改成「掛在錨點下方」之後**更糟**——面板本來就在那裡，色板被整個蓋住
///
/// 所以規則是**不要重疊**：放在面板旁邊、上緣對齊、優先左側。
/// 這組刻意全部是純數字——`AuraCore` 不得載入 CoreGraphics（`IsolationTests` 白名單基準）。
@Suite("色板第一次出現的位置（T18）")
struct ColorPanelPlacementTests {

    /// 1920×1080、選單列高 22。面板寬 380、掛在右側圖示下方。
    enum Screen {
        static let minX = 0.0, maxX = 1920.0, minY = 0.0, maxY = 1055.0
    }
    /// 已顯示的面板（色板要避開它）
    enum Panel {
        static let minX = 1040.0, maxX = 1420.0, maxY = 1055.0
    }

    func origin(panelWidth: Double = 225, panelHeight: Double = 400,
                avoidMinX: Double = Panel.minX, avoidMaxX: Double = Panel.maxX,
                visibleMinX: Double = Screen.minX, visibleMaxX: Double = Screen.maxX)
    -> ColorPanelPlacement.Origin {
        ColorPanelPlacement.origin(avoidMinX: avoidMinX, avoidMaxX: avoidMaxX, avoidMaxY: Panel.maxY,
                                   panelWidth: panelWidth, panelHeight: panelHeight,
                                   visibleMinX: visibleMinX, visibleMaxX: visibleMaxX,
                                   visibleMinY: Screen.minY, visibleMaxY: Screen.maxY)
    }

    /// 使用者實際回報的 bug：色板被面板蓋住。
    @Test("不得與面板重疊——放在它左邊，上緣對齊")
    func doesNotOverlapThePanel() {
        let o = origin()
        #expect(o.x + 225 <= Panel.minX, "右緣 \(o.x + 225) 必須在面板左緣 \(Panel.minX) 之左")
        #expect(Panel.minX - (o.x + 225) == 12, "間距應為 gap 12，實際 \(Panel.minX - (o.x + 225))")
        #expect(o.y + 400 == Panel.maxY, "上緣應與面板上緣對齊，實際 \(o.y + 400)")
        #expect(o.y >= Screen.minY, "不得落到可見範圍之外")
    }

    @Test("左邊放不下就放右邊（面板貼在螢幕左緣的情形）")
    func fallsBackToTheRight() {
        let o = origin(avoidMinX: 20, avoidMaxX: 400)
        #expect(o.x >= 400, "應改放右側，實際 x=\(o.x)")
        #expect(o.x == 400 + 12, "右側也要留 gap 12，實際 \(o.x)")
        #expect(o.x + 225 <= Screen.maxX, "不得溢出右緣")
    }

    @Test("色板比螢幕高時上緣貼齊頂端，不掉到底部（那是最初的左下角行為）")
    func tallPanelPinsToTop() {
        let o = origin(panelHeight: 1200)
        #expect(o.y >= Screen.minY)
        #expect(o.y + 1200 >= Screen.maxY - 0.001, "上緣應貼齊頂端，實際 \(o.y + 1200)")
    }

    @Test("兩側都放不下時仍回合法座標（螢幕真的太窄的退化情形）")
    func degenerateScreen() {
        // 可見範圍只有 500 寬、面板佔掉中間 380 → 兩側都容不下 225 的色板
        let o = origin(avoidMinX: 60, avoidMaxX: 440, visibleMaxX: 500)
        #expect(o.x >= Screen.minX && o.x + 225 <= 500, "仍須落在可見範圍內，實際 x=\(o.x)")
    }
}
