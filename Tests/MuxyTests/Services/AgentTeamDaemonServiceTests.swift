import Foundation
import Testing

@testable import Muxy

@Suite("AgentTeamDaemonService")
struct AgentTeamDaemonServiceTests {
    @Test("stage asset index resolves from a flattened resource root")
    func stageIndexURLResolvesFromRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-stage-assets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("index.html")
        try Data("ok".utf8).write(to: index)

        #expect(StageWindowController.stageIndexURL(resourceURL: root) == index)
    }

    @Test("stage asset index falls back to the stage-assets subdirectory")
    func stageIndexURLResolvesFromStageAssetsSubdirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-stage-assets-\(UUID().uuidString)", isDirectory: true)
        let subdirectory = root.appendingPathComponent("stage-assets", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let index = subdirectory.appendingPathComponent("index.html")
        try Data("ok".utf8).write(to: index)

        #expect(StageWindowController.stageIndexURL(resourceURL: root) == index)
    }

    @Test("discovery is allowed immediately when no backoff is set")
    func discoveryAllowedWithoutBackoff() {
        #expect(AgentTeamDaemonService.shouldAttemptDiscovery(now: Date(), notBefore: nil))
    }

    @Test("discovery waits until the backoff window expires")
    func discoveryBackoffWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let retryAt = AgentTeamDaemonService.nextDiscoveryAttempt(after: now)

        #expect(!AgentTeamDaemonService.shouldAttemptDiscovery(
            now: now.addingTimeInterval(AgentTeamDaemonService.discoveryBackoff - 1),
            notBefore: retryAt
        ))
        #expect(AgentTeamDaemonService.shouldAttemptDiscovery(
            now: retryAt,
            notBefore: retryAt
        ))
    }
}
