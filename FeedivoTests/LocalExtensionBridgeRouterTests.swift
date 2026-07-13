import Foundation
import Testing
@testable import Feedivo

struct LocalExtensionBridgeRouterTests {
    private func decodeJSONObject(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @Test func statusMitBekannterURLLiefertSubscribedTrue() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { url in url == "https://example.com/feed.xml" },
            addFeed: { _ in .error("sollte nicht aufgerufen werden") }
        )
        let request = HTTPRequest(
            method: "GET",
            path: "/status",
            queryItems: ["url": "https://example.com/feed.xml"],
            headers: [:],
            body: Data()
        )

        let response = await router.handle(request)

        #expect(response.statusCode == 200)
        #expect(decodeJSONObject(response.body)["subscribed"] as? Bool == true)
    }

    @Test func statusOhneURLParameterLiefert400() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in true },
            addFeed: { _ in .error("sollte nicht aufgerufen werden") }
        )
        let request = HTTPRequest(method: "GET", path: "/status", queryItems: [:], headers: [:], body: Data())

        let response = await router.handle(request)

        #expect(response.statusCode == 400)
    }

    @Test func addMitGueltigerURLRuftAddFeedAufUndLiefertAdded() async {
        var receivedURL: String?
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in false },
            addFeed: { url in
                receivedURL = url
                return .added
            }
        )
        let body = Data("{\"url\":\"https://example.com/feed.xml\"}".utf8)
        let request = HTTPRequest(method: "POST", path: "/add", queryItems: [:], headers: [:], body: body)

        let response = await router.handle(request)

        #expect(receivedURL == "https://example.com/feed.xml")
        #expect(response.statusCode == 200)
        #expect(decodeJSONObject(response.body)["result"] as? String == "added")
    }

    @Test func addMitBereitsVorhandenemFeedLiefertAlreadyExists() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in false },
            addFeed: { _ in .alreadyExists }
        )
        let body = Data("{\"url\":\"https://example.com/feed.xml\"}".utf8)
        let request = HTTPRequest(method: "POST", path: "/add", queryItems: [:], headers: [:], body: body)

        let response = await router.handle(request)

        #expect(response.statusCode == 200)
        #expect(decodeJSONObject(response.body)["result"] as? String == "alreadyExists")
    }

    @Test func addMitFehlerLiefert500MitNachricht() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in false },
            addFeed: { _ in .error("Netzwerkfehler") }
        )
        let body = Data("{\"url\":\"https://example.com/feed.xml\"}".utf8)
        let request = HTTPRequest(method: "POST", path: "/add", queryItems: [:], headers: [:], body: body)

        let response = await router.handle(request)

        #expect(response.statusCode == 500)
        #expect(decodeJSONObject(response.body)["message"] as? String == "Netzwerkfehler")
    }

    @Test func addMitUngueltigemBodyLiefert400() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in false },
            addFeed: { _ in .error("sollte nicht aufgerufen werden") }
        )
        let request = HTTPRequest(method: "POST", path: "/add", queryItems: [:], headers: [:], body: Data("kein json".utf8))

        let response = await router.handle(request)

        #expect(response.statusCode == 400)
    }

    @Test func unbekannteRouteLiefert404() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in false },
            addFeed: { _ in .error("sollte nicht aufgerufen werden") }
        )
        let request = HTTPRequest(method: "GET", path: "/unbekannt", queryItems: [:], headers: [:], body: Data())

        let response = await router.handle(request)

        #expect(response.statusCode == 404)
    }
}
