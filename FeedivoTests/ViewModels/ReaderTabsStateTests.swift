import Foundation
import Testing
@testable import Feedivo

@MainActor
struct ReaderTabsStateTests {
    @Test func openInActiveTabErstelltErstenTabBeiLeererListe() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")

        #expect(state.tabs.count == 1)
        #expect(state.tabs.first?.articleID == "article-1")
        #expect(state.activeArticleID == "article-1")
    }

    @Test func openInActiveTabAktualisiertBestehendenAktivenTab() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        let firstTabID = state.activeTabID

        state.openInActiveTab(articleID: "article-2")

        #expect(state.tabs.count == 1)
        #expect(state.activeTabID == firstTabID)
        #expect(state.activeArticleID == "article-2")
    }

    @Test func openInNewBackgroundTabLaesstAktivenTabUnveraendert() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        let firstTabID = state.activeTabID

        state.openInNewBackgroundTab(articleID: "article-2")

        #expect(state.tabs.count == 2)
        #expect(state.activeTabID == firstTabID)
        #expect(state.activeArticleID == "article-1")
    }

    @Test func openInNewBackgroundTabWirdAktivWennKeinTabOffenIst() {
        let state = ReaderTabsState()

        let newTabID = state.openInNewBackgroundTab(articleID: "article-1")

        #expect(state.tabs.count == 1)
        #expect(state.activeTabID == newTabID)
    }

    @Test func duplicateActiveTabOeffnetHintergrundTabMitGleicherArtikelID() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        let firstTabID = state.activeTabID

        let didDuplicate = state.duplicateActiveTab()

        #expect(didDuplicate)
        #expect(state.tabs.count == 2)
        #expect(state.activeTabID == firstTabID)
        #expect(state.tabs.map(\.articleID) == ["article-1", "article-1"])
    }

    @Test func duplicateActiveTabLiefertFalseOhneAktivenTab() {
        let state = ReaderTabsState()

        let didDuplicate = state.duplicateActiveTab()

        #expect(!didDuplicate)
        #expect(state.tabs.isEmpty)
    }

    @Test func closeTabAktiviertNachbarTabAnGleicherPosition() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")
        state.openInNewBackgroundTab(articleID: "article-3")
        state.activateTab(id: state.tabs[1].id)
        let tabToCloseID = state.tabs[1].id
        let expectedNextActiveID = state.tabs[2].id

        state.closeTab(id: tabToCloseID)

        #expect(state.tabs.count == 2)
        #expect(state.activeTabID == expectedNextActiveID)
    }

    @Test func closeTabAktiviertVorherigenTabWennLetzterTabGeschlossenWird() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")
        state.activateTab(id: state.tabs[1].id)
        let firstTabID = state.tabs[0].id

        state.closeTab(id: state.tabs[1].id)

        #expect(state.tabs.count == 1)
        #expect(state.activeTabID == firstTabID)
    }

    @Test func closeLetztenTabLeertAktivenTab() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")

        state.closeTab(id: state.tabs[0].id)

        #expect(state.tabs.isEmpty)
        #expect(state.activeTabID == nil)
        #expect(state.activeArticleID == nil)
    }

    @Test func schliessenEinesInaktivenTabsAendertAktivenTabNicht() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")
        let activeID = state.activeTabID
        let backgroundTabID = state.tabs[1].id

        state.closeTab(id: backgroundTabID)

        #expect(state.tabs.count == 1)
        #expect(state.activeTabID == activeID)
    }

    @Test func activateNextTabWechseltZumFolgendenTabOhneWraparound() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")
        let secondTabID = state.tabs[1].id

        state.activateNextTab()
        #expect(state.activeTabID == secondTabID)

        state.activateNextTab()
        #expect(state.activeTabID == secondTabID)
    }

    @Test func activatePreviousTabWechseltZumVorherigenTabOhneWraparound() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")
        state.activateTab(id: state.tabs[1].id)
        let firstTabID = state.tabs[0].id

        state.activatePreviousTab()
        #expect(state.activeTabID == firstTabID)

        state.activatePreviousTab()
        #expect(state.activeTabID == firstTabID)
    }

    @Test func activateTabIgnoriertUnbekannteID() {
        let state = ReaderTabsState()
        state.openInActiveTab(articleID: "article-1")
        let activeID = state.activeTabID

        state.activateTab(id: UUID())

        #expect(state.activeTabID == activeID)
    }

    @Test func persistiertOffeneTabsBeiAktivierterEinstellung() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(true, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        let state = ReaderTabsState(userDefaults: defaults)

        state.openInActiveTab(articleID: "article-1")
        state.openInNewBackgroundTab(articleID: "article-2")

        #expect(ReaderTabsSettings.savedArticleIDs(defaults: defaults) == ["article-1", "article-2"])
        #expect(ReaderTabsSettings.savedActiveArticleID(defaults: defaults) == "article-1")
    }

    @Test func persistiertNichtsBeiDeaktivierterEinstellung() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(false, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        let state = ReaderTabsState(userDefaults: defaults)

        state.openInActiveTab(articleID: "article-1")

        #expect(ReaderTabsSettings.savedArticleIDs(defaults: defaults).isEmpty)
    }

    @Test func persistiertAuchNachSchliessenDesLetztenTabs() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(true, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        let state = ReaderTabsState(userDefaults: defaults)
        state.openInActiveTab(articleID: "article-1")

        state.closeTab(id: state.tabs[0].id)

        #expect(ReaderTabsSettings.savedArticleIDs(defaults: defaults).isEmpty)
        #expect(ReaderTabsSettings.savedActiveArticleID(defaults: defaults) == nil)
    }

    @Test func restoreIfEnabledStelltGespeicherteTabsUndAktivenTabWiederHer() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(true, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        ReaderTabsSettings.save(articleIDs: ["article-1", "article-2"], activeArticleID: "article-2", defaults: defaults)

        let state = ReaderTabsState(userDefaults: defaults)
        state.restoreIfEnabled()

        #expect(state.tabs.map(\.articleID) == ["article-1", "article-2"])
        #expect(state.activeArticleID == "article-2")
    }

    @Test func restoreIfEnabledTutNichtsBeiDeaktivierterEinstellung() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(false, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        ReaderTabsSettings.save(articleIDs: ["article-1"], activeArticleID: "article-1", defaults: defaults)

        let state = ReaderTabsState(userDefaults: defaults)
        state.restoreIfEnabled()

        #expect(state.tabs.isEmpty)
    }

    @Test func restoreIfEnabledFaelltAufErstenTabZurueckWennGespeicherterAktiverArtikelFehlt() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(true, forKey: ReaderTabsSettings.restoreTabsOnLaunchKey)
        ReaderTabsSettings.save(articleIDs: ["article-1", "article-2"], activeArticleID: "article-unbekannt", defaults: defaults)

        let state = ReaderTabsState(userDefaults: defaults)
        state.restoreIfEnabled()

        #expect(state.activeArticleID == "article-1")
    }
}
