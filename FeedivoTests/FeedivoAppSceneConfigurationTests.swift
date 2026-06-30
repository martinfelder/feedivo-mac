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

    @Test func settingsSceneUsesOnlyNewSettingsView() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        #expect(appSource.contains("Settings {"))
        #expect(appSource.contains("NewSettingsView()"))
        #expect(!appSource.contains("SettingsCommands()"))
        #expect(!appSource.contains("Einstellungen alt"))
        #expect(!appSource.contains("SettingsView.oldWindowID"))
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

    @Test func appRegistersArticleWindowGroup() throws {
        let projectRoot = projectRootURL()
        let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

        #expect(appSource.contains("WindowGroup(for: ArticleWindowRequest.self)"))
        #expect(appSource.contains("ArticleWindowView(request:"))
        #expect(appSource.contains(".defaultSize(width: 900, height: 720)"))
        #expect(appSource.contains(".modelContainer(modelContainer)"))
    }

    @Test func articleCommandsOpenArticleWindowWithCommandReturn() throws {
        let projectRoot = projectRootURL()
        let commandsSource = try source(at: "Feedivo/App/ArticleCommands.swift", projectRoot: projectRoot)
        let actionsSource = try source(at: "Feedivo/App/ArticleCommandActions.swift", projectRoot: projectRoot)

        #expect(actionsSource.contains("openInArticleWindow"))
        #expect(commandsSource.contains("L10n.articleOpenInWindowCommand"))
        #expect(commandsSource.contains(".keyboardShortcut(.return, modifiers: [.command])"))
        #expect(commandsSource.contains("articleCommandActions?.openInArticleWindow()"))
    }

    @Test func articleRowsOfferOpenInWindowContextAction() throws {
        let projectRoot = projectRootURL()
        let rowSource = try source(at: "Feedivo/Views/ArticleList/ArticleRowView.swift", projectRoot: projectRoot)
        let listSource = try source(at: "Feedivo/Views/ArticleList/ArticleListView.swift", projectRoot: projectRoot)

        #expect(rowSource.contains("onOpenInWindow"))
        #expect(rowSource.contains("L10n.articleOpenInWindowCommand"))
        #expect(listSource.contains("openArticleInWindow(article"))
    }

    @Test func articleWindowRestoreSettingDefaultsToOff() throws {
        let projectRoot = projectRootURL()
        let settingsSource = try source(at: "Feedivo/Views/Settings/SettingsView.swift", projectRoot: projectRoot)
        let restoreSettingsSource = try source(
            at: "Feedivo/Services/ArticleWindowSettings.swift",
            projectRoot: projectRoot
        )

        #expect(restoreSettingsSource.contains("restoreOpenArticleWindowsOnLaunchKey"))
        #expect(restoreSettingsSource.contains("defaultRestoreOpenArticleWindowsOnLaunch = false"))
        #expect(settingsSource.contains("ArticleWindowSettings.restoreOpenArticleWindowsOnLaunchKey"))
        #expect(settingsSource.contains("L10n.settingsRestoreArticleWindowsTitle"))
    }

    @Test func articleWindowUpdatesStoredArticleIDAfterNavigation() throws {
        let projectRoot = projectRootURL()
        let articleWindowSource = try source(at: "Feedivo/Views/Reader/ArticleWindowView.swift", projectRoot: projectRoot)

        #expect(articleWindowSource.contains(".onChange(of: selectedArticleID)"))
        #expect(articleWindowSource.contains("ArticleWindowSettings.forgetOpenArticleID(oldValue)"))
        #expect(articleWindowSource.contains("ArticleWindowSettings.rememberOpenArticleID(newValue)"))
        #expect(articleWindowSource.contains("ArticleWindowSettings.forgetOpenArticleID(selectedArticleID)"))
    }

    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(at relativePath: String, projectRoot: URL) throws -> String {
        let sourceURL = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
