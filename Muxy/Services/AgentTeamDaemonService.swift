import AppKit
import Foundation

@MainActor
final class AgentTeamDaemonService {
    static let shared = AgentTeamDaemonService()
    nonisolated static let discoveryBackoff: TimeInterval = 30

    struct DaemonStatusResponse: Codable {
        struct RunMeta: Codable {
            let run_id: String
            let team: String
            let flow: String?
            let status: String
            let workers: [String]?
            let updated_at: String
        }

        struct Reservation: Codable {
            let id: String
            let worker: String
            let paths: [String]
            let active: Bool
        }

        let ok: Bool
        let error: String?
        let http_base_url: String?
        let project_root: String?
        let runs: [RunMeta]?
        let reservations: [Reservation]?
    }

    struct Snapshot {
        let projectPath: String
        let response: DaemonStatusResponse

        var hasVisibleContent: Bool {
            !(response.runs ?? []).isEmpty || !(response.reservations ?? []).isEmpty
        }
    }

    private let stageWindowController = StageWindowController()
    private var appState: AppState?
    private var projectStore: ProjectStore?
    private var worktreeStore: WorktreeStore?
    private var refreshTimer: Timer?
    private var daemonURLByProjectPath: [String: URL] = [:]
    private var nextDiscoveryAttemptByProjectPath: [String: Date] = [:]
    private var isRefreshing = false

    private init() {}

    func configure(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        self.appState = appState
        self.projectStore = projectStore
        self.worktreeStore = worktreeStore
        stageWindowController.start()
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refresh()
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        guard let projectPath = activeProjectPath() else {
            stageWindowController.render(nil)
            return
        }
        let statePath = URL(fileURLWithPath: projectPath).appendingPathComponent(".agent-team").path
        guard FileManager.default.fileExists(atPath: statePath) else {
            daemonURLByProjectPath[projectPath] = nil
            nextDiscoveryAttemptByProjectPath[projectPath] = nil
            stageWindowController.render(nil)
            return
        }
        isRefreshing = true
        Task {
            let snapshot = await loadSnapshot(projectPath: projectPath, forceDiscovery: force)
            await MainActor.run {
                self.isRefreshing = false
                self.stageWindowController.render(snapshot?.hasVisibleContent == true ? snapshot : nil)
            }
        }
    }

    private func activeProjectPath() -> String? {
        guard let appState, let projectStore, let projectID = appState.activeProjectID else { return nil }
        guard let project = projectStore.projects.first(where: { $0.id == projectID }) else { return nil }
        if let worktreeStore,
           let key = appState.activeWorktreeKey(for: projectID),
           let worktree = worktreeStore.worktree(projectID: projectID, worktreeID: key.worktreeID)
        {
            return worktree.path
        }
        return project.path
    }

    private func loadSnapshot(projectPath: String, forceDiscovery: Bool) async -> Snapshot? {
        if let baseURL = daemonURLByProjectPath[projectPath],
           let response = await fetchStatus(baseURL: baseURL)
        {
            nextDiscoveryAttemptByProjectPath[projectPath] = nil
            return Snapshot(projectPath: projectPath, response: response)
        }

        daemonURLByProjectPath[projectPath] = nil
        let now = Date()
        guard forceDiscovery ||
            Self.shouldAttemptDiscovery(now: now, notBefore: nextDiscoveryAttemptByProjectPath[projectPath])
        else {
            return nil
        }

        guard let response = await Self.discoverStatus(projectPath: projectPath) else {
            daemonURLByProjectPath[projectPath] = nil
            nextDiscoveryAttemptByProjectPath[projectPath] = Self.nextDiscoveryAttempt(after: now)
            return nil
        }
        nextDiscoveryAttemptByProjectPath[projectPath] = nil
        if let rawBaseURL = response.http_base_url, let baseURL = URL(string: rawBaseURL) {
            daemonURLByProjectPath[projectPath] = baseURL
        }
        return Snapshot(projectPath: projectPath, response: response)
    }

    nonisolated static func shouldAttemptDiscovery(now: Date, notBefore: Date?) -> Bool {
        guard let notBefore else { return true }
        return now >= notBefore
    }

    nonisolated static func nextDiscoveryAttempt(after date: Date) -> Date {
        date.addingTimeInterval(discoveryBackoff)
    }

    private nonisolated static func discoverStatus(projectPath: String) async -> DaemonStatusResponse? {
        guard let agentTeamCLI = resolveAgentTeamCLI() else { return nil }
        let process = Process()
        process.executableURL = agentTeamCLI
        process.arguments = ["daemon", "status", "--root", projectPath]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return try? JSONDecoder().decode(DaemonStatusResponse.self, from: data)
    }

    private func fetchStatus(baseURL: URL) async -> DaemonStatusResponse? {
        let url = baseURL.appending(path: "api/status")
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            return nil
        }
        return try? JSONDecoder().decode(DaemonStatusResponse.self, from: data)
    }

    private nonisolated static func resolveAgentTeamCLI() -> URL? {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/bin/agent-team",
            "/opt/homebrew/bin/agent-team",
            "/usr/local/bin/agent-team",
        ] + envPath.split(separator: ":").map { String($0) + "/agent-team" }

        for candidate in candidates {
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }
}
