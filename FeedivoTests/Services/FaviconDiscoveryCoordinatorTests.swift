import Foundation
import Testing
@testable import Feedivo

struct FaviconDiscoveryCoordinatorTests {
    @Test func discoverDedupliziertGleichzeitigeAnfragenFuerDieselbeSiteURL() async throws {
        let coordinator = FaviconDiscoveryCoordinator()
        let callCounter = FaviconDiscoveryCallCounter()
        let siteURL = try #require(URL(string: "https://example.com"))

        async let first: String? = coordinator.discover(siteURL: siteURL) { _ in
            await callCounter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return "https://example.com/favicon.ico"
        }
        async let second: String? = coordinator.discover(siteURL: siteURL) { _ in
            await callCounter.increment()
            return "https://example.com/favicon.ico"
        }

        let results = await [first, second]

        #expect(results == ["https://example.com/favicon.ico", "https://example.com/favicon.ico"])
        #expect(await callCounter.count == 1)
    }

    @Test func discoverBehandeltVerschiedeneSiteURLsUnabhaengig() async throws {
        let coordinator = FaviconDiscoveryCoordinator()
        let callCounter = FaviconDiscoveryCallCounter()
        let firstSiteURL = try #require(URL(string: "https://one.example"))
        let secondSiteURL = try #require(URL(string: "https://two.example"))

        async let first: String? = coordinator.discover(siteURL: firstSiteURL) { _ in
            await callCounter.increment()
            return "https://one.example/favicon.ico"
        }
        async let second: String? = coordinator.discover(siteURL: secondSiteURL) { _ in
            await callCounter.increment()
            return "https://two.example/favicon.ico"
        }

        _ = await [first, second]

        #expect(await callCounter.count == 2)
    }
}

private actor FaviconDiscoveryCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
