import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// T13i（r16／r15 review n6）：`CodexSnippetSizing` 的行高常數要有自己的推導 gate——
/// 照既有 `SessionsCardSizingDerivationTests` 的形狀（離屏渲染真實 view、與常數比對
/// ±0.5pt）。**為什麼不能只照抄 `SessionsCardSizing` 的形狀而不照抄它的 gate**：那個先例
/// 的第一版把 `rowHeight` 寫死成 33（量測時用的是沒有副行的列）被 review 退回，真實有副行
/// 是 49pt——沒有推導 gate，改壞版面不會有任何測試變紅（`SessionsCardSizing.swift:15`）。
/// **上限與下限必須共用同一個量到的行高**：`CodexSnippetSizing.height`（上限，12 行）與
/// `CodexSnippetHeightTests` 的 6 行下限，都是這裡守住的同一個 `lineHeight` 常數的倍數。
@MainActor
@Suite("CodexSnippetSizing 的常數真的等於真實渲染量出來的高度")
struct CodexSnippetSizingDerivationTests {

    /// 孤立渲染 `Text(...).font(.system(size: 10, design: .monospaced)).padding(8)`
    /// （逐字照抄 `CodexSectionView.snippetBlock` 的字型與 padding）——餵已知行數的
    /// **顯式換行**字串（不是會自動換行的長字串：換行不依賴 layout pass 就準確，
    /// `CodexSnippetHeightMeasurement.step7RealSnippetWrappedHeight` 已經踩過「沒有真的
    /// layout pass，自動換行量不到」的坑）。
    func isolatedTextHeight(lines: Int) -> CGFloat {
        let text = Array(repeating: "X", count: lines).joined(separator: "\n")
        let hosting = NSHostingView(rootView:
            Text(text).font(.system(size: 10, design: .monospaced)).padding(8))
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 2000)
        return hosting.fittingSize.height
    }

    @Test("真實量到的每行高度等於 CodexSnippetSizing.lineHeight（±0.5pt）")
    func lineHeightMatchesRealMeasurement() {
        // 用 1 行與 12 行的高度差 ÷ 11，取兩個相距較遠的樣本點降低取整誤差。
        let h1 = isolatedTextHeight(lines: 1)
        let h12 = isolatedTextHeight(lines: 12)
        let measuredLineHeight = (Double(h12) - Double(h1)) / 11
        #expect(abs(measuredLineHeight - CodexSnippetSizing.lineHeight) <= 0.5, """
            真實渲染量到每行 \(measuredLineHeight)pt，但 CodexSnippetSizing.lineHeight = \
            \(CodexSnippetSizing.lineHeight)pt —— 兩者該對齊，字型／padding 改了卻沒有同步\
            更新常數。
            """)
    }

    @Test("真實量到的 padding 截距等於 CodexSnippetSizing.verticalPadding（±0.5pt）")
    func verticalPaddingMatchesRealMeasurement() {
        let h1 = isolatedTextHeight(lines: 1)
        let h12 = isolatedTextHeight(lines: 12)
        let measuredLineHeight = (Double(h12) - Double(h1)) / 11
        let measuredIntercept = Double(h1) - measuredLineHeight
        #expect(abs(measuredIntercept - CodexSnippetSizing.verticalPadding) <= 0.5, """
            真實渲染量到截距 \(measuredIntercept)pt，但 CodexSnippetSizing.verticalPadding = \
            \(CodexSnippetSizing.verticalPadding)pt —— `.padding(8)` 上下共 16pt 是唯一的\
            截距來源，改了 padding 卻沒有同步更新常數。
            """)
    }

    /// **review 指出的具體迴歸類型**（同 `SessionsCardSizingDerivationTests` 的既有理由）：
    /// `CodexSnippetSizing.height` 必須至少能容納下 `minVisibleLines` 行——這條用真實渲染
    /// 直接驗證「12 行的固定高度」不小於「真實渲染 6 行的高度」，同 `CodexSnippetHeightTests`
    /// 的下限守衛互相點名（兩層各自的消費者不同：這裡守常數本身自洽，那裡守 view 真的接上）。
    @Test("CodexSnippetSizing.height 不小於真實渲染 minVisibleLines 行的高度")
    func heightNeverClipsMinimumVisibleLines() {
        let measured = isolatedTextHeight(lines: CodexSnippetSizing.minVisibleLines)
        #expect(CodexSnippetSizing.height >= Double(measured), """
            CodexSnippetSizing.height = \(CodexSnippetSizing.height)pt，\
            但真實渲染 \(CodexSnippetSizing.minVisibleLines) 行需要 \(measured)pt —— \
            snippet 區塊會把下限那幾行裁掉一截。
            """)
    }
}
