import Testing
@testable import AuraCore

/// T32：D-2 的 mutation-record gate——「造型只決定畫什麼形狀，不決定什麼時候動、動多快」。
/// **這條不是重新測 `AppearancePolicy` 本身**（那是既有動畫系列測試的職責）——這裡釘死
/// design doc `2026-09-15-icon-shapes-design.md` §1 那張表的具體數字，擋的是「為了讓
/// 某個造型好看而偷偷調了注意力預算」（R4），也是 `git diff` 之外守住「一行都沒被改」的方式：
/// 改了任何一個數字，這條測試就會指名哪一格錯。
@Suite("D-2：IconAppearance／AppearancePolicy 不因 IconShape 存在而改動")
struct IconAppearanceUnchangedByIconShapeTests {

    @Test("idle／done：靜止、0fps")
    func idleAndDoneAreStill() {
        for activity in [Activity.idle, .done] {
            let (animation, fps) = AppearancePolicy.motion(for: activity)
            #expect(animation == .none, "\(activity) 應該是 .none，實際 \(animation)")
            #expect(fps == 0, "\(activity) 應該 0fps，實際 \(fps)")
        }
    }

    @Test("working：呼吸 4.0s，0.35–0.60，10fps")
    func workingBreathesSlowlyAndDimly() {
        let (animation, fps) = AppearancePolicy.motion(for: .working)
        #expect(animation == .breathe(period: 4.0, min: 0.35, max: 0.60), "實際 \(animation)")
        #expect(fps == 10, "實際 \(fps)")
    }

    @Test("waiting：呼吸 1.1s，0.20–1.00，30fps")
    func waitingBreathesQuicklyAndBrightly() {
        let (animation, fps) = AppearancePolicy.motion(for: .waiting)
        #expect(animation == .breathe(period: 1.1, min: 0.20, max: 1.00), "實際 \(animation)")
        #expect(fps == 30, "實際 \(fps)")
    }

    @Test("error：雙閃 1.1s，30fps")
    func errorDoubleBlinks() {
        let (animation, fps) = AppearancePolicy.motion(for: .error)
        #expect(animation == .doubleBlink(period: 1.1), "實際 \(animation)")
        #expect(fps == 30, "實際 \(fps)")
    }
}
