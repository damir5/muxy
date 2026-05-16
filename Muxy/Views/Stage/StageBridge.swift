import Foundation
import WebKit

@MainActor
final class StageBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "agentTeam"

    var onRefreshRequested: (() -> Void)?

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName else { return }
        guard let body = message.body as? [String: String], body["action"] == "refresh" else { return }
        onRefreshRequested?()
    }
}
