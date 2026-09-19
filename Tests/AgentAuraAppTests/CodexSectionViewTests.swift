import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// T09（CX36 `codexSectionRendersEveryState`）：`CodexSectionView` 依 §4.6 表窮盡分支。
///
/// **定義域走兩層 `samples` 鏈**（`CodexStateKind.allCases.flatMap(CodexState.samples)`，
/// `.blockedByBundlePath` 那一格因此自動展開成 `RejectionKind.allCases.flatMap(Rejection.samples)`
/// 的全部 9 個代表值），**不直接迭代 `Rejection`**——T07 review m1 實測：在這條 gate 落地前，
/// 把兩個代表 `Rejection` 改成單一值，全相關 suite 全綠（`rows` 層零鑑別力），這是那兩層鏈的
/// 第一個真正會分辨它們的消費者。`.connectedStalePath`／`.occupiedByOther` 另外吃
/// `pathRejection`／`codexSnippet` 這兩個外部輸入（不是 `CodexState` 自己的 payload，
/// 見 `PanelModel.codexPathRejection` 的 doc comment），domain 因此再乘一個「nil／非 nil」維度。
///
/// **用 `dump(_:to:)` 讀 SwiftUI 值型別樹裡的字面文字**（同既有
/// `Wave2WiringTests.optionsSectionUsesMountTargetNote` 的手法）——不需要真的 `NSWindow`／
/// 離屏渲染就能斷言「畫面上有沒有某句話／某顆按鈕」，比像素掃描更直接、更不會被字型渲染
/// 細節干擾。`.unavailable`／`.connected` 額外補一條**像素**零 diff 守衛（mutation②：
/// 沒有它，`.unavailable` 也畫東西這件事只有 dump 檢查得到，`OptionsExpandTests` 的
/// worst-case 高度斷言未必踩得到）。
@MainActor
@Suite("CodexSectionView 窮盡涵蓋六態 × 兩種 Rejection（CX36）")
struct CodexSectionViewTests {

    /// 真的產生器輸出，不是手寫字面——供「snippet 與產生器同源」那條斷言使用（mutation③）。
    static let realSnippet = CodexHooksJSON.snippet(hookBinaryPath: "/Applications/AgentAura.app/Contents/PlugIns/aura-hook")

    static func model(codex: CodexState, codexSnippet: String?,
                      codexPathRejection: CodexHookPathCheck.Rejection?) -> PanelModel {
        PanelModel.make(icon: .empty, sessions: [], palette: .default,
                        install: .notConnected, version: "1.0", optionsExpanded: false,
                        launchAtLogin: nil, externalTargetPath: nil, banner: nil,
                        systemReduceMotion: false, userReduceMotion: false, iconPlate: true,
                        iconShape: .ledStrip, language: .traditionalChinese,
                        codex: codex, codexSnippet: codexSnippet, codexPathRejection: codexPathRejection)
    }

    /// **不用 `dump(_:to:)` 的文字輸出**——實測撞到坑：`dump` 印字串時會把內容裡的反斜線
    /// 再轉義一次（供人閱讀），而 `CodexHooksJSON.snippet(...)` 的真實輸出含 `JSONSerialization`
    /// 逸出的 `\/`，逐字比對會因為雙重轉義而永遠找不到、卻不是因為畫面真的沒有那段內容
    /// （T09 實測：先用 `dump` 寫這條斷言，`.occupiedByOther`／`.unsupportedCharacter` 兩格
    /// 假紅）。改成直接用 `Mirror` 遞迴收集 SwiftUI 值型別樹裡**所有** `String` 葉節點，
    /// 逐一用 `==`／`contains` 比對——比對的是真的 Swift `String` 值本身，不是重新序列化
    /// 過的可讀文字，同樣不需要真的 `NSWindow`／離屏渲染。
    static func leafStrings(_ value: Any) -> [String] {
        if let s = value as? String { return [s] }
        var found: [String] = []
        for child in Mirror(reflecting: value).children {
            found.append(contentsOf: leafStrings(child.value))
        }
        return found
    }

    static func dumped(_ model: PanelModel) -> String {
        leafStrings(CodexSectionView(model: model, onAction: { _ in }).body).joined(separator: "\u{0}")
    }

    /// mutation②（**特別確認**，見 T09 brief）：`.unavailable`／`.connected` 必須是零像素差異，
    /// 不只是 dump 裡沒有字——`EmptyView` 本身在 dump 也可能被某些 SwiftUI 版面包裝成非空字串，
    /// 這裡直接量 `NSHostingView.fittingSize`，兩態都該是 (0, 0)。
    @Test("`.unavailable`／`.connected`：CodexSectionView 自己的 fittingSize 是 (0,0)（零版面代價）",
          arguments: [CodexState.unavailable, CodexState.connected])
    func emptyStatesRenderNothing(codex: CodexState) {
        let m = Self.model(codex: codex, codexSnippet: nil, codexPathRejection: nil)
        let hosting = NSHostingView(rootView: CodexSectionView(model: m, onAction: { _ in }))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 200)
        let size = hosting.fittingSize
        #expect(size.width == 0 && size.height == 0, """
            \(codex) 的 CodexSectionView.fittingSize 應該是 (0, 0)，實際 \(size) —— \
            這一態不該畫出任何東西（D-j），畫了會在真面板裡多佔版面
            """)
    }

    @Test(".notConnected：單行提示 ＋「接上 Codex」按鈕")
    func notConnectedShowsPromptAndConnectButton() {
        let m = Self.model(codex: .notConnected, codexSnippet: nil, codexPathRejection: nil)
        let text = Self.dumped(m)
        #expect(text.contains(L10nCodex.notConnectedPrompt.text(.traditionalChinese)))
        #expect(text.contains(L10nCodex.connectRow.text(.traditionalChinese)))
    }

    @Test(".connectedStalePath，pathRejection == nil：「App 移動過」＋「重新接上 Codex」按鈕")
    func staleWithoutRejectionShowsReconnectButton() {
        let m = Self.model(codex: .connectedStalePath, codexSnippet: nil, codexPathRejection: nil)
        let text = Self.dumped(m)
        #expect(text.contains(L10nCodex.staleMovedPrompt.text(.traditionalChinese)))
        #expect(text.contains(L10nCodex.reconnectRow.text(.traditionalChinese)))
    }

    /// mutation⑤ 的守衛：被拒時**不得**畫「重新接上」按鈕（R-9）——不管拒絕理由是哪一種
    /// （這裡兩種都測，`RejectionKind.allCases` 推導，不是只測一種代表值）。
    @Test(".connectedStalePath，pathRejection != nil：換句解釋，不給「重新接上」按鈕",
          arguments: CodexHookPathCheck.RejectionKind.allCases.flatMap(CodexHookPathCheck.Rejection.samples))
    func staleWithRejectionWithholdsReconnectButton(rejection: CodexHookPathCheck.Rejection) {
        let m = Self.model(codex: .connectedStalePath, codexSnippet: nil, codexPathRejection: rejection)
        let text = Self.dumped(m)
        #expect(text.contains(L10nCodex.staleOtherCopyMessage.text(.traditionalChinese)), """
            pathRejection=\(rejection)：沒有看到「這份設定指向另一個位置」的解釋句
            """)
        #expect(!text.contains(L10nCodex.reconnectRow.text(.traditionalChinese)), """
            pathRejection=\(rejection)：仍然畫出「重新接上 Codex」按鈕——R-9 的守衛失效，\
            按下去會先 disconnect 掉一份還在運作的檔
            """)
    }

    @Test(".occupiedByOther，codexSnippet != nil：說明 ＋ snippet（與產生器同源）＋「複製」")
    func occupiedWithSnippetShowsSnippetAndCopyButton() {
        let m = Self.model(codex: .occupiedByOther, codexSnippet: Self.realSnippet, codexPathRejection: nil)
        let text = Self.dumped(m)
        #expect(text.contains(L10nCodex.occupiedIntro.text(.traditionalChinese)))
        // mutation③ 的守衛：斷言的是「真的產生器輸出」出現在畫面裡，不是隨便一句字面——
        // 若 view 改成手寫字串，這裡會找不到 `Self.realSnippet`。
        #expect(text.contains(Self.realSnippet), "畫面上的 snippet 內容跟 CodexHooksJSON.snippet(...) 的真實輸出不同源")
        #expect(text.contains(L10nCodex.copyButtonLabel.text(.traditionalChinese)))
    }

    /// R-10 的守衛：snippet 被扣住時**不給**「複製」按鈕（沒有東西可複製）。
    @Test(".occupiedByOther，codexSnippet == nil：換句話說明，不給 snippet／複製按鈕")
    func occupiedWithoutSnippetWithholdsCopyButton() {
        let m = Self.model(codex: .occupiedByOther, codexSnippet: nil, codexPathRejection: .mustMoveToApplications)
        let text = Self.dumped(m)
        #expect(text.contains(L10nCodex.occupiedIntro.text(.traditionalChinese)))
        #expect(text.contains(L10nCodex.occupiedSnippetWithheldReason.text(.traditionalChinese)))
        #expect(!text.contains(L10nCodex.copyButtonLabel.text(.traditionalChinese)), """
            沒有 snippet 時仍然畫出「複製」按鈕——R-10 的守衛失效（複製一個不存在的東西）
            """)
    }

    @Test(".blockedByBundlePath(.mustMoveToApplications)：解釋 ＋ 出路，不給 snippet／複製按鈕")
    func blockedMustMoveShowsExplanationWithoutSnippet() {
        // 負向斷言必須餵**正向輸入**：這裡刻意給 model 一份真的 snippet。若餵 nil，
        // 「不得畫出 snippet」在任何實作下都成立（T09 review M1：把 view 的這個分支改成會畫
        // snippet，全套件紅 0 條）。D-s 的 view 層守衛就是這一格——決策層那半在 CX40（T10）。
        let m = Self.model(codex: .blockedByBundlePath(.mustMoveToApplications),
                           codexSnippet: Self.realSnippet, codexPathRejection: .mustMoveToApplications)
        let text = Self.dumped(m)
        #expect(text.contains(L10nCodex.blockedPathExplanation.text(.traditionalChinese)))
        #expect(text.contains(InstallerFailure.mustMoveToApplicationsMessage(.traditionalChinese)))
        #expect(!text.contains(L10nCodex.copyButtonLabel.text(.traditionalChinese)), "D-s：mustMoveToApplications 不該給 snippet／複製按鈕")
        #expect(!text.contains(Self.realSnippet), "D-s：mustMoveToApplications 不該畫出 snippet 內容")
    }

    /// mutation④ 的守衛：**必須把字元本身插進句子**，不能只講一句籠統話——涵蓋
    /// `CodexHookPathCheck.unsupportedCharacters` 全部八個字元（定義域推導，不手列），
    /// 且**定義域走 `CodexState.samples(.blockedByBundlePath)`**（見 suite doc comment）。
    @Test(".blockedByBundlePath(.unsupportedCharacter)：解釋 ＋ 指名字元 ＋ snippet（同源）＋「複製」",
          arguments: CodexState.samples(.blockedByBundlePath).compactMap { state -> Character? in
              if case .blockedByBundlePath(.unsupportedCharacter(let c)) = state { return c }
              return nil
          })
    func blockedUnsupportedCharacterNamesTheCharacterAndKeepsSnippet(character: Character) {
        let rejection = CodexHookPathCheck.Rejection.unsupportedCharacter(character)
        let m = Self.model(codex: .blockedByBundlePath(rejection), codexSnippet: Self.realSnippet, codexPathRejection: rejection)
        let text = Self.dumped(m)
        #expect(text.contains(String(character)), """
            字元「\(character)」沒有出現在畫面裡：\(text) —— 只講了一句籠統話，使用者猜不到是哪一個
            """)
        #expect(text.contains(Self.realSnippet), "unsupportedCharacter 應該給 snippet（D-s），且要跟產生器同源")
        #expect(text.contains(L10nCodex.copyButtonLabel.text(.traditionalChinese)))
    }

    /// 正向對照：`CodexState.samples(.blockedByBundlePath)` 這一格恰好是 8 個字元
    /// ＋ 1 個 `.mustMoveToApplications` = 9 個代表值——如果哪天被摧毀成單一值
    /// （T07 review m1 講的那個陷阱），這條會先紅，比上面兩條「找不到字元」更早、更明確
    /// 地指出問題出在 `samples` 這一層而不是 view 這一層。
    @Test("正向對照：CodexState.samples(.blockedByBundlePath) 恰有 9 個代表值")
    func blockedByBundlePathSamplesHasExpectedCardinality() {
        let samples = CodexState.samples(.blockedByBundlePath)
        #expect(samples.count == CodexHookPathCheck.unsupportedCharacters.count + 1, """
            CodexState.samples(.blockedByBundlePath) 應該是「八個字元 ＋ 一個
            mustMoveToApplications」，實際 \(samples.count) 個 —— 兩層 samples 鏈可能被摧毀成
            比較少的代表值，CX36 的鑑別力會跟著消失
            """)
    }
}
