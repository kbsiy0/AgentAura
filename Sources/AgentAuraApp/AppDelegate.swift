import AppKit
import AuraCore
import AuraHookFile

/// Composition root。唯一的組裝點。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var graph: PipelineGraph!
    private var status: StatusItemController!
    private var driver: AnimationDriver!
    private var livenessTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusItemController()
        driver = AnimationDriver { [weak self] appearance, phase in
            self?.status.apply(appearance, phase: phase)
        }

        status.attachPopover()
        status.onOpen = { [weak self] in
            guard let self else { return }
            self.graph.acknowledgeAll()
            self.refreshPanel()
        }

        graph = PipelineGraph.production()
        // onIconStateChange 從 FSEvents 的背景 queue 上來，所以要 hop 回 main。
        graph.onIconStateChange = { icon in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.driver.setIcon(icon)
                self.driver.setIconVisible(self.status.isVisible)
                self.refreshPanel()
            }
        }
        graph.start()

        // spec §3.5：每 5s 重驗 pid，抓「terminal 被強制關掉、SessionEnd 沒來」
        livenessTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.graph.refreshLiveness() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        livenessTimer?.invalidate()
        graph?.stop()
    }

    private func refreshPanel() {
        let icon = graph.iconState
        // `graph.registry` 是 internal 且未加鎖 —— 走上鎖的 `visibleSessions`。
        // 這個 callback 會從 FSEvents 的背景 queue 觸發，直接讀 registry 就是 data race。
        let rows = PanelViewModel.rows(from: graph.visibleSessions)
        status.setPanel(title: PanelViewModel.title(for: icon), rows: rows)
    }
}
