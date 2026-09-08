import Testing
@testable import AuraCore

@Suite("注意力預算（R4）")
struct IconAppearanceTests {

    func appearance(_ a: Activity, waiting: Int = 0, error: Int = 0,
                    working: Int = 0, reduceMotion: Bool = false) -> IconAppearance {
        var counts: [Activity: Int] = [:]
        if waiting > 0 { counts[.waiting] = waiting }
        if error > 0 { counts[.error] = error }
        if working > 0 { counts[.working] = working }
        if counts.isEmpty { counts[a] = 1 }
        let icon = IconState(activity: a, counts: counts, liveCount: working + waiting)
        return AppearancePolicy.appearance(for: icon, reduceMotion: reduceMotion)
    }

    // ---- 核心規則：只有需要你行動的狀態才會動 ----

    @Test("done 與 idle 完全不動；waiting 與 error 會動")
    func onlyAttentionStatesAnimate() {
        #expect(appearance(.waiting).needsAnimation)
        #expect(appearance(.error).needsAnimation)
        #expect(!appearance(.done).needsAnimation, "done 是「可以去看了」，不是「你被擋著」")
        #expect(!appearance(.idle).needsAnimation)
        // working 技術上仍會重繪（極慢呼吸），但幀率與對比都遠低於 waiting ——
        // 那個差距由 workingAndWaitingAreDistinguishable 守。
        #expect(appearance(.working).needsAnimation,
                "working 有極微動畫讓人看得出在跑；強度差距另有測試")
    }

    @Test("幀率符合 DoD 的分層門檻")
    func frameRateTiers() {
        #expect(appearance(.idle).targetFPS == 0, "idle 必須零重繪")
        #expect(appearance(.done).targetFPS == 0, "done 必須零重繪")
        #expect(appearance(.working).targetFPS <= 10, "working 是常態，≤10 fps")
        #expect(appearance(.waiting).targetFPS >= 30, "waiting 要流暢才有警示效果")
        #expect(appearance(.error).targetFPS >= 30)
    }

    @Test("working 的呼吸低對比且週期長 —— 它是常態，不該搶注意力")
    func workingIsSubtle() {
        guard case .breathe(let period, let lo, let hi) = appearance(.working).animation else {
            Issue.record("working 應為 breathe"); return
        }
        #expect(period >= 3.0, "週期至少 3 秒，實際 \(period)")
        #expect(hi - lo <= 0.35, "透明度對比不得超過 0.35，實際 \(hi - lo)")
    }

    @Test("waiting 的呼吸明顯 —— 它需要你行動")
    func waitingIsSalient() {
        guard case .breathe(let period, let lo, let hi) = appearance(.waiting).animation else {
            Issue.record("waiting 應為 breathe"); return
        }
        #expect(period <= 1.5, "週期不超過 1.5 秒")
        #expect(hi - lo >= 0.6, "對比至少 0.6，才與 working 明顯不同")
    }

    @Test("error 是 double blink，與 waiting 的呼吸在形狀上就不同")
    func errorIsDoubleBlink() {
        guard case .doubleBlink = appearance(.error).animation else {
            Issue.record("error 應為 doubleBlink"); return
        }
    }

    @Test("working 與 waiting 的動畫參數差距足夠大，餘光可辨")
    func workingAndWaitingAreDistinguishable() {
        guard case .breathe(let wp, let wlo, let whi) = appearance(.working).animation,
              case .breathe(let ap, let alo, let ahi) = appearance(.waiting).animation else {
            Issue.record("兩者都應為 breathe"); return
        }
        #expect(wp / ap >= 2.0, "週期至少差 2 倍，實際 \(wp) vs \(ap)")
        #expect((ahi - alo) / (whi - wlo) >= 2.0, "對比至少差 2 倍")
    }

    // ---- 減少動態效果 ----

    @Test("系統開啟減少動態效果時，全部改為靜態")
    func reduceMotionDisablesAllAnimation() {
        for a in Activity.allCases {
            let ap = appearance(a, reduceMotion: true)
            #expect(ap.animation == .none, "\(a) 在 reduceMotion 下應為 .none")
            #expect(ap.targetFPS == 0, "\(a) 在 reduceMotion 下應零重繪")
        }
    }

    @Test("reduceMotion 不改變 activity —— 只改呈現方式")
    func reduceMotionKeepsActivity() {
        for a in Activity.allCases {
            #expect(appearance(a, reduceMotion: true).activity == a)
        }
    }

    // ---- 計數透傳 ----

    @Test("attentionCount 與 liveCount 透傳自 IconState")
    func countsPassThrough() {
        let ap = appearance(.error, waiting: 2, error: 1, working: 3)
        #expect(ap.attentionCount == 3, "error 1 + waiting 2")
        #expect(ap.liveCount == 5)
    }
}
