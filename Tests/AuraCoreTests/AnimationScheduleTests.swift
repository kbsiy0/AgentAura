import Testing
@testable import AuraCore

@Suite("動畫排程與省電")
struct AnimationScheduleTests {

    func icon(_ a: Activity) -> IconState {
        IconState(activity: a, counts: [a: 1], liveCount: a == .idle ? 0 : 1)
    }

    @Test("螢幕睡眠時完全不排程重繪 —— 沒人看得到，白吃電池")
    func screenAsleepStopsEverything() {
        for a in Activity.allCases {
            let env = DisplayEnvironment(screenAsleep: true)
            #expect(AnimationSchedule.interval(for: icon(a), in: env) == nil,
                    "\(a) 在螢幕睡眠時仍排程重繪")
        }
    }

    @Test("icon 被遮蔽（全螢幕 app）時不排程重繪")
    func hiddenIconStopsEverything() {
        for a in Activity.allCases {
            let env = DisplayEnvironment(iconVisible: false)
            #expect(AnimationSchedule.interval(for: icon(a), in: env) == nil)
        }
    }

    @Test("減少動態效果時不排程重繪")
    func reduceMotionStopsEverything() {
        for a in Activity.allCases {
            let env = DisplayEnvironment(reduceMotion: true)
            #expect(AnimationSchedule.interval(for: icon(a), in: env) == nil)
        }
    }

    @Test("正常情況下，靜態狀態不排程、動態狀態按幀率排程")
    func normalIntervals() {
        let env = DisplayEnvironment()
        #expect(AnimationSchedule.interval(for: icon(.idle), in: env) == nil)
        #expect(AnimationSchedule.interval(for: icon(.done), in: env) == nil)

        let working = try! #require(AnimationSchedule.interval(for: icon(.working), in: env))
        let waiting = try! #require(AnimationSchedule.interval(for: icon(.waiting), in: env))
        #expect(working >= 0.09, "working ≤ 10 fps，間隔至少 0.09s，實際 \(working)")
        #expect(waiting <= 0.034, "waiting ≥ 30 fps，間隔至多 0.034s，實際 \(waiting)")
        #expect(working > waiting * 2, "working 的間隔要明顯長於 waiting")
    }

    @Test("間隔與 IconAppearance 的 targetFPS 一致 —— 不得各自定義幀率")
    func intervalMatchesAppearance() {
        let env = DisplayEnvironment()
        for a in Activity.allCases {
            let ap = AppearancePolicy.appearance(for: icon(a))
            let iv = AnimationSchedule.interval(for: icon(a), in: env)
            if ap.targetFPS == 0 {
                #expect(iv == nil, "\(a) targetFPS 為 0 卻排了間隔")
            } else {
                let expected = 1.0 / Double(ap.targetFPS)
                #expect(iv != nil && abs(iv! - expected) < 0.0001,
                        "\(a) 的間隔應為 1/\(ap.targetFPS)，實際 \(iv as Any)")
            }
        }
    }

    @Test("任何一個省電條件成立就停止，不需要全部成立")
    func anySuppressorStops() {
        let combos = [
            DisplayEnvironment(screenAsleep: true, iconVisible: true, reduceMotion: false),
            DisplayEnvironment(screenAsleep: false, iconVisible: false, reduceMotion: false),
            DisplayEnvironment(screenAsleep: false, iconVisible: true, reduceMotion: true),
        ]
        for env in combos {
            #expect(AnimationSchedule.interval(for: icon(.error), in: env) == nil,
                    "env=\(env) 應停止重繪")
        }
    }
}
