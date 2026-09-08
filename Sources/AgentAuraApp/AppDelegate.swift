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

        graph = PipelineGraph.production()
        // onIconStateChange 從 FSEvents 的背景 queue 上來，所以要 hop 回 main。
        graph.onIconStateChange = { icon in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.driver.setIcon(icon)
                self.driver.setIconVisible(self.status.isVisible)
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
}
