// Sources/AgentAuraApp/AppDelegate.swift
import AppKit
import AuraCore
import AuraHookFile

/// Composition root。唯一的組裝點。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var graph: PipelineGraph!
    private var status: (any IconRendering)!
    private var driver: AnimationDriver!
    private var livenessTimer: Timer?

    /// Change 2：internal（不是 private）讓 smoke test 能直接觀測／驅動
    /// （`delegate.paletteStore.palette`、`delegate.colorCoordinator.changeColor(...)`）。
    var paletteStore: PaletteStore!
    var colorCoordinator: ColorPickerCoordinator!

    /// 三個注入點，**預設值就是生產設定** —— 生產路徑與測試路徑走同一段程式碼。
    /// 沒有這些縫，這整個 composition root 就沒有任何測試碰得到
    /// （最終 review 實測：把下面的 `graph.start()` 與 timer 註解掉，220/220 全綠）。
    private let root: URL
    private let livenessInterval: TimeInterval
    private let defaults: UserDefaults
    private let makeRenderer: @MainActor () -> any IconRendering

    init(root: URL = SnapshotIO.defaultRoot,
         livenessInterval: TimeInterval = 5,
         defaults: UserDefaults = .standard,
         makeRenderer: @escaping @MainActor () -> any IconRendering = { StatusItemController() }) {
        self.root = root
        self.livenessInterval = livenessInterval
        self.defaults = defaults
        self.makeRenderer = makeRenderer
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = makeRenderer()
        paletteStore = PaletteStore(defaults: defaults)
        colorCoordinator = ColorPickerCoordinator()
        driver = AnimationDriver { [weak self] appearance, phase in
            self?.status.apply(appearance, phase: phase)
        }
        // 同步區內（第一次 icon 交付之前）套上持久化的色——`onIconStateChange` 的
        // Task 一定落在後一個 turn，所以「同步區」比「在 graph.start() 之前」更準確
        // 的說法是「在下面這段回呼真正跑起來之前」（spec §4.3）。
        driver.setPalette(paletteStore.palette)

        paletteStore.onChange = { [weak self] in
            guard let self else { return }
            self.driver.setPalette(self.paletteStore.palette)
            self.refreshPanel()
        }
        status.onPickColor = { [weak self] activity in
            guard let self else { return }
            self.status.setPopoverPinned(true)
            self.colorCoordinator.pick(activity, current: self.paletteStore.palette[activity])
        }
        colorCoordinator.onPick = { [weak self] activity, color in
            self?.applyColor(color, for: activity)
        }
        colorCoordinator.onEnd = { [weak self] in
            self?.status.setPopoverPinned(false)
        }
        status.onResetColors = { [weak self] in
            self?.resetColors()
        }

        graph = PipelineGraph.production(root: root)
        // onIconStateChange 從 FSEvents 的背景 queue 上來，所以要 hop 回 main。
        graph.onIconStateChange = { icon in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.driver.setIcon(icon)
                self.driver.setIconVisible(self.status.isVisible)
                self.refreshPanel()
            }
        }
        status.attachPopover()
        status.onOpen = { [weak self] in
            guard let self else { return }
            self.graph.acknowledgeAll()
            self.refreshPanel()
        }
        graph.start()

        // spec §3.5：每 5s 重驗 pid，抓「terminal 被強制關掉、SessionEnd 沒來」
        livenessTimer = Timer.scheduledTimer(withTimeInterval: livenessInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.graph.refreshLiveness() }
        }
    }

    private func refreshPanel() {
        let icon = graph.iconState
        let model = PanelModel.make(icon: icon, sessions: graph.visibleSessions, palette: paletteStore.palette)
        status.setPanel(model)
    }

    /// `store.set` 先 `onChange`（driver.setPalette + refreshPanel 立刻反映）再落盤。
    func applyColor(_ color: RGBA, for activity: Activity) {
        paletteStore.set(color, for: activity)
    }

    func resetColors() {
        paletteStore.reset()
    }

    func applicationWillTerminate(_ notification: Notification) {
        livenessTimer?.invalidate()
        graph?.stop()
        colorCoordinator?.detach()   // 收尾動作各自獨立（Lessons #8）；也讓每條建 AppDelegate 的 smoke 不留 observer
    }
}
