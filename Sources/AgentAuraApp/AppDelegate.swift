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

    /// 兩個注入點，**預設值就是生產設定** —— 生產路徑與測試路徑走同一段程式碼。
    /// 沒有這兩個縫，這整個 composition root 就沒有任何測試碰得到
    /// （最終 review 實測：把下面的 `graph.start()` 與 timer 註解掉，220/220 全綠）。
    private let root: URL
    private let livenessInterval: TimeInterval
    private let makeRenderer: @MainActor () -> any IconRendering

    init(root: URL = SnapshotIO.defaultRoot,
         livenessInterval: TimeInterval = 5,
         makeRenderer: @escaping @MainActor () -> any IconRendering = { StatusItemController() }) {
        self.root = root
        self.livenessInterval = livenessInterval
        self.makeRenderer = makeRenderer
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = makeRenderer()
        driver = AnimationDriver { [weak self] appearance, phase in
            self?.status.apply(appearance, phase: phase)
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
        let rows = PanelViewModel.rows(from: graph.visibleSessions)
        status.setPanel(title: PanelViewModel.title(for: icon), rows: rows)
    }

    func applicationWillTerminate(_ notification: Notification) {
        livenessTimer?.invalidate()
        graph?.stop()
    }
}
