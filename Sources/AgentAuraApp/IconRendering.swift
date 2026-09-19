import AppKit
import AuraCore

/// `AppDelegate` 依賴的選單列介面。
///
/// **這個 protocol 存在的理由是可測性，不是抽象癖。** spec §5.2 要求一條 composition-root
/// smoke：「`StatusItemController` **真的**收到 `IconState` 更新（spy 斷言呼叫確實發生，
/// 不是被 catch-all 吞掉）」。沒有這個縫，`AppDelegate` 就無法被注入 spy —— 最終 review
/// 實測：把 `graph.start()` 與 liveness timer 整段註解掉（產品完全不動），220/220 全綠。
///
/// Change 2：`setPanel` 改吃 `PanelModel`，加圖例改色三個入口（`onPickColor`／
/// `onResetColors`／`setPopoverPinned`）。T04（D-j）：前兩者併入單一
/// `onAction: ((PanelAction) -> Void)`（不給預設值，忘了接線要是編譯錯）。T08（§4.4）：
/// `onOpen` 在 popover 真的要顯示**之前**呼叫（只 probe＋setPanel，不 acknowledge）；
/// `showPanel()` 是首啟自動開面板專用的程式化顯示，**不**觸發 `onOpen`（首啟順序已經
/// 在呼叫它之前用真實狀態 `setPanel` 過，觸發只會多一次無意義的 reprobe）。
///
/// T12（B1）：`onRightClick` 是右鍵快速路徑（footer 的「Options ⌄」主入口不受影響、
/// 左鍵行為完全不變）——原本移到獨立檔案是為了讓 `StatusItemController.swift`
/// 有空間放 B1／B3 的實作，不是為了這個 protocol 本身。
@MainActor
protocol IconRendering: AnyObject {
    func apply(_ appearance: IconAppearance, phase: Double)
    var isVisible: Bool { get }
    func attachPopover()
    func setPanel(_ model: PanelModel)
    var onClose: (() -> Void)? { get set }
    var onOpen: (() -> Void)? { get set }
    var onAction: ((PanelAction) -> Void)? { get set }
    /// B1：右鍵直接開 Options 的快速路徑（`StatusItemController.togglePopover` 偵測）。
    var onRightClick: (() -> Void)? { get set }
    func setPopoverPinned(_ pinned: Bool)
    func showPanel()
    /// T11（S0-2）：tooltip 的第二個輸入，獨立於 `apply`（動畫幀 vs 狀態驅動，互相獨立）。
    /// `AppDelegate.refreshPanel()` 每次都呼叫，是 `installState` 唯一的傳遞路徑。
    func setInstallState(_ state: InstallState)
    /// T17／T18：色板第一次出現時**要避開的矩形**——面板已顯示就是面板本身，
    /// 否則退回選單列圖示。放在它旁邊而不是下方（T18 實機：放下方會被面板整個蓋住，
    /// `NSPopover` 的視窗層級在一般面板之上）。沒有 window 時為 nil（離屏測試就是這一格）。
    var avoidScreenFrame: CGRect? { get }
    /// T16：轉發到 `drawing.setShowsPlate`——`AppDelegate` 不綁死 `StatusItemController`
    /// 型別，同這個 protocol 其餘成員的理由。
    func setIconPlate(_ shows: Bool)
    /// T32：換選單列 icon 造型——同 `setIconPlate` 的理由，`AppDelegate` 不綁死型別。
    func setIconShape(_ shape: IconShape)
    /// 這個 renderer 有沒有資格把**真的**系統面板（`NSColorPanel.shared`）叫到螢幕上。
    /// 真的選單列圖示 ⇒ `true`；測試的 spy 沒有圖示、沒有視窗 ⇒ `false`。`AppDelegate`
    /// 在 `applicationDidFinishLaunching` 用它設定 `ColorPickerCoordinator.presentsPanel`，
    /// 讓所有走真實接線的測試（38 個 `AppDelegate(root:…)` 建構點）一次被涵蓋，
    /// 不必每條測試自己記得關——2026-09-19 實機回報：全量測試每跑一次色板就閃一次。
    var presentsSystemPanels: Bool { get }
}
