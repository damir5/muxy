import AppKit
import WebKit

@MainActor
final class StageWindowController: NSObject, WKNavigationDelegate {
    private let bridge = StageBridge()
    private var panel: NSPanel?
    private var webView: WKWebView?
    private var pendingPayload: AgentTeamDaemonService.Snapshot?
    private var contentLoaded = false
    private var observersInstalled = false

    override init() {
        super.init()
        bridge.onRefreshRequested = { AgentTeamDaemonService.shared.refresh(force: true) }
    }

    func start() {
        installObservers()
        attachToActiveWindow()
    }

    func render(_ snapshot: AgentTeamDaemonService.Snapshot?) {
        pendingPayload = snapshot
        guard let snapshot else {
            panel?.orderOut(nil)
            return
        }
        let panel = ensurePanel()
        attachToActiveWindow()
        panel.orderFrontRegardless()
        push(snapshot)
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let contentRect = NSRect(x: 0, y: 0, width: 360, height: 420)
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let config = WKWebViewConfiguration()
        config.userContentController.add(bridge, name: StageBridge.handlerName)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        panel.contentView = webView

        if let url = Self.stageIndexURL() {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        self.panel = panel
        self.webView = webView
        return panel
    }

    nonisolated static func stageIndexURL(bundle: Bundle = .appResources) -> URL? {
        guard let resourceURL = bundle.resourceURL else { return nil }
        return stageIndexURL(resourceURL: resourceURL)
    }

    nonisolated static func stageIndexURL(resourceURL: URL) -> URL? {
        let candidates = [
            resourceURL.appendingPathComponent("index.html"),
            resourceURL.appendingPathComponent("stage-assets/index.html"),
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc
    private func windowDidBecomeKey(_: Notification) {
        attachToActiveWindow()
    }

    @objc
    private func windowWillClose(_ note: Notification) {
        guard let panel, let window = note.object as? NSWindow, window == panel.parent else { return }
        panel.orderOut(nil)
    }

    private func attachToActiveWindow() {
        guard let panel, let window = NSApp.keyWindow, ShortcutContext.isMainWindow(window) else { return }
        if panel.parent != window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        let frame = window.frame
        let x = frame.maxX - panel.frame.width - 18
        let y = frame.minY + 72
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        contentLoaded = true
        if let pendingPayload {
            push(pendingPayload)
        }
    }

    private func push(_ snapshot: AgentTeamDaemonService.Snapshot) {
        guard contentLoaded, let webView else { return }
        let runs = snapshot.response.runs ?? []
        let reservations = snapshot.response.reservations ?? []
        let payload: [String: Any] = [
            "projectPath": snapshot.projectPath,
            "runs": runs.map { run in
                [
                    "runID": run.run_id,
                    "team": run.team,
                    "flow": run.flow ?? "",
                    "status": run.status,
                    "workers": run.workers ?? [],
                    "updatedAt": run.updated_at,
                ]
            },
            "reservations": reservations
                .filter { $0.active }
                .map { reservation in
                    [
                        "id": reservation.id,
                        "worker": reservation.worker,
                        "paths": reservation.paths,
                    ]
                },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        webView.evaluateJavaScript("window.__agentTeamRender(\(json));")
    }
}
