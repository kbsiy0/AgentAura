import AppKit
import Testing
@testable import AgentAuraApp

/// T16：spec §4.1 第 140 行的算術錯誤（`8×3 + 7×2 = 34`，正確是 **38**）讓 `preferredWidth`
/// 硬寫死成 42——同一行 spec 自己宣稱「LED 上下各 3pt、左右各 4pt 邊距」，但套算下來
/// 右邊距其實是 0（第八顆燈的右邊界正好貼齊 42pt 的底板右緣），左邊距卻是 4——
/// 燈條因此被推向底板右側（使用者回報「底面板其實在圖片的右邊，有點跑版」）。
///
/// 這條 gate 補的正是 spec 自己宣稱卻從未強制過的性質：**四邊邊距必須相等**。
/// 直接從 `LEDStripView` 的實際幾何（`plateRect`／`ledRect(at:)`）算，不寫魔術數字——
/// `preferredWidth`／`plateInset` 之後不管怎麼調，只要四邊不等寬這條就會紅。
@MainActor
@Suite("LED 底板四邊邊距對稱（T16）")
struct LEDPlateSymmetryTests {

    func makeView() -> LEDStripView {
        let v = LEDStripView()
        v.frame = NSRect(x: 0, y: 0, width: LEDStripView.preferredWidth, height: LEDStripView.plateHeight)
        return v
    }

    @Test("左邊距 == 右邊距 == 上邊距 == 下邊距")
    func fourMarginsAreEqual() {
        let view = makeView()
        let plate = view.plateRect
        let firstLED = view.ledRect(at: 0)
        let lastLED = view.ledRect(at: LEDStripView.ledCount - 1)

        let left = firstLED.minX - plate.minX
        let right = plate.maxX - lastLED.maxX
        let top = plate.maxY - firstLED.maxY
        let bottom = firstLED.minY - plate.minY

        #expect(left == right, "左邊距 \(left) 應等於右邊距 \(right) —— 燈條偏向了某一側")
        #expect(left == top, "左邊距 \(left) 應等於上邊距 \(top)")
        #expect(left == bottom, "左邊距 \(left) 應等於下邊距 \(bottom)")
        #expect(right == bottom, "右邊距 \(right) 應等於下邊距 \(bottom)")
    }

    @Test("四邊邊距實測值等於 plateInset（正向對照，不是空氣測試）")
    func marginsEqualPlateInset() {
        let view = makeView()
        let plate = view.plateRect
        let firstLED = view.ledRect(at: 0)
        let lastLED = view.ledRect(at: LEDStripView.ledCount - 1)

        #expect(firstLED.minX - plate.minX == LEDStripView.plateInset)
        #expect(plate.maxX - lastLED.maxX == LEDStripView.plateInset, """
            右邊距實際 \(plate.maxX - lastLED.maxX)pt，應等於 plateInset(\(LEDStripView.plateInset))pt——
            這條會抓到「preferredWidth 沒有真的跟著 ledSpan／plateInset 推導」的回歸
            """)
    }
}
