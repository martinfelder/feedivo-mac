import Foundation

enum LocalExtensionBridgeAddResult: Equatable {
    case added
    case alreadyExists
    case error(String)
}

// Reine Routing-/Verarbeitungslogik fuer den lokalen Erweiterungs-Server,
// bewusst getrennt von der NWListener-Socket-Verdrahtung (siehe
// LocalExtensionBridgeServer) — dadurch ohne echten Netzwerk-Bind testbar.
struct LocalExtensionBridgeRouter {
    typealias StatusChecker = @Sendable (String) async -> Bool
    typealias FeedAdder = @Sendable (String) async -> LocalExtensionBridgeAddResult

    private let checkSubscribed: StatusChecker
    private let addFeed: FeedAdder

    init(checkSubscribed: @escaping StatusChecker, addFeed: @escaping FeedAdder) {
        self.checkSubscribed = checkSubscribed
        self.addFeed = addFeed
    }

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/status"):
            return await handleStatus(request)
        case ("POST", "/add"):
            return await handleAdd(request)
        default:
            return .json(statusCode: 404, statusText: "Not Found", object: [
                "result": "error",
                "message": "Unbekannte Route"
            ])
        }
    }

    private func handleStatus(_ request: HTTPRequest) async -> HTTPResponse {
        guard let url = request.queryItems["url"], !url.isEmpty else {
            return .json(statusCode: 400, statusText: "Bad Request", object: [
                "result": "error",
                "message": "Fehlender url-Parameter"
            ])
        }

        let subscribed = await checkSubscribed(url)
        return .json(statusCode: 200, statusText: "OK", object: ["subscribed": subscribed])
    }

    private func handleAdd(_ request: HTTPRequest) async -> HTTPResponse {
        guard
            let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
            let url = json["url"] as? String,
            !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .json(statusCode: 400, statusText: "Bad Request", object: [
                "result": "error",
                "message": "Fehlender oder ungültiger url-Wert"
            ])
        }

        switch await addFeed(url) {
        case .added:
            return .json(statusCode: 200, statusText: "OK", object: ["result": "added"])
        case .alreadyExists:
            return .json(statusCode: 200, statusText: "OK", object: ["result": "alreadyExists"])
        case let .error(message):
            return .json(statusCode: 500, statusText: "Internal Server Error", object: [
                "result": "error",
                "message": message
            ])
        }
    }
}
