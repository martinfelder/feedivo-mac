import Foundation
import Testing

struct FeedivoAppSceneConfigurationTests {
    @Test func settingsSceneUsesSharedModelContainer() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        let settingsScene = try #require(appSource.range(of: "Settings {"))
        let settingsSource = appSource[settingsScene.lowerBound...]

        #expect(settingsSource.contains(".modelContainer(modelContainer)"))
    }

    @Test func startupTaskTrimsImageCacheToSelectedLimit() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        #expect(appSource.contains("trimImageCacheToSelectedLimit()"))
        #expect(appSource.contains("ImageCacheService.shared.trimCache"))
        #expect(appSource.contains("ImageCacheSettings.currentLimitInBytes"))
    }
}
