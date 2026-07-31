import SwiftUI
import Observation
import AppKit
import OSLog

@main
struct FeedivoApp: App {
    @AppStorage("appLanguage")
    private var appLanguageRawValue = AppLanguage.system.rawValue

    @AppStorage(AppAppearance.storageKey)
    private var appAppearanceRawValue = AppAppearance.defaultMode.rawValue

    @AppStorage(InterfaceTextSize.storageKey)
    private var interfaceTextSizeRawValue = InterfaceTextSize.defaultSize.rawValue

    @AppStorage(BackgroundRefreshSettings.isEnabledKey)
    private var backgroundRefreshIsEnabled = BackgroundRefreshSettings.defaultIsEnabled

    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

    @AppStorage(ArticleRetentionSettings.isEnabledKey)
    private var articleRetentionIsEnabled = ArticleRetentionSettings.defaultIsEnabled

    @AppStorage(ArticleRetentionSettings.retentionDaysKey)
    private var articleRetentionDays = ArticleRetentionSettings.defaultRetentionDays

    @AppStorage(ArticleRetentionSettings.minimumArticlesPerFeedKey)
    private var articleRetentionMinimumArticlesPerFeed = ArticleRetentionSettings.defaultMinimumArticlesPerFeed

    @AppStorage(ArticleRetentionSettings.includesProtectedArticlesKey)
    private var articleRetentionIncludesProtectedArticles = ArticleRetentionSettings.defaultIncludesProtectedArticles

    @AppStorage(SpotlightIndexingSettings.isEnabledKey)
    private var spotlightIndexingIsEnabled = SpotlightIndexingSettings.defaultIsEnabled

    @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)
    private var updateCheckIsAutomaticCheckEnabled = UpdateCheckSettings.defaultIsAutomaticCheckEnabled

    @AppStorage(UpdateCheckSettings.hasUnseenUpdateKey)
    private var updateCheckHasUnseenUpdate = UpdateCheckSettings.defaultHasUnseenUpdate

    @State private var updateCheckReleasePresentation: GitHubRelease?
    @State private var showsUpdateCheckUpToDateAlert = false
    // Nutzerwunsch: der "Kein Update"-Dialog soll zusätzlich zeigen, was
    // installiert ist und was aktuell auf GitHub als Release existiert.
    @State private var updateCheckUpToDateRelease: GitHubRelease?
    @State private var updateCheckErrorMessage: String?
    // Fix Whole-Branch-Review (Important): verhindert parallele/wiederholte
    // Update-Checks per Menü, während bereits einer läuft (analog zum
    // isChecking-Guard in AboutSettingsView.swift, hier aber ohne Spinner-UI,
    // da der App-Menü-Pfad kein eigenes View-Rendering für Zwischenzustände hat).
    @State private var isUpdateCheckInFlight = false

    // Fix Whole-Branch-Review (Important): `performManualUpdateCheck()` muss das
    // Hauptfenster öffnen/fokussieren, bevor der Check läuft — die Sheet-/Alert-
    // Modifier hängen am Content von `Window("Feedivo", id: "main")`. Ist das
    // Fenster geschlossen (App läuft weiter über den Menubar-Status-Item, siehe
    // MenubarStatusItemController), hätte weder das Sheet noch der Alert einen
    // sichtbaren Ort zum Erscheinen. `openWindow(id:)` gegen die bereits als
    // `Window` (nicht `WindowGroup`) deklarierte Singleton-Szene ist idempotent —
    // bringt ein bereits offenes Fenster nur nach vorn, erzeugt keine Dublette.
    @Environment(\.openWindow) private var openWindow

    // Feature 23.2: AppKit-Delegate fängt feedivo://-URLs zuverlässig ab —
    // auch beim Kaltstart, bevor die SwiftUI-View-Hierarchie existiert (siehe
    // FeedivoAppDelegate). Die geparste Aktion wird in dessen
    // PendingURLSchemeAction abgelegt und unten an ContentView weitergereicht.
    @NSApplicationDelegateAdaptor(FeedivoAppDelegate.self) private var appDelegate

    private let backgroundRefreshScheduler: SystemBackgroundActivityRefreshScheduler
    private let databaseLoadState = DatabaseLoadState()
    private let feedViewModel = FeedViewModel()
    private let feedivoDatabase: FeedivoDatabase
    private let localExtensionBridgeServer: LocalExtensionBridgeServer
    private let cloudSyncEngine: CloudSyncEngine

    init() {
        ReaderFontRegistry.registerBundledFonts()
        let databaseOpenResult = Self.openSQLiteDatabase()
        let database = databaseOpenResult.database
        self.backgroundRefreshScheduler = SystemBackgroundActivityRefreshScheduler(
            feedivoDatabase: database,
            feedViewModel: feedViewModel
        )
        self.feedivoDatabase = database
        self.localExtensionBridgeServer = LocalExtensionBridgeServer(database: database)
        self.cloudSyncEngine = CloudSyncEngine(database: database)
        // Prozessweite Registrierung, siehe CloudSyncEngine.register(_:) — ermöglicht
        // TagStore-Mutationen, die laufende Engine sofort über neue ausstehende Änderungen
        // zu informieren (Fix Whole-Branch-Review: Runtime-Mutationen erreichten sonst nie
        // die laufende CKSyncEngine, nur einen App-Neustart). Bewusst unabhängig davon, ob
        // Sync aktuell aktiv ist — solange die Engine nicht gestartet wurde, ist jeder
        // Benachrichtigungsversuch ein No-Op (siehe notifyPendingChangesAvailable-Guard).
        CloudSyncEngine.register(self.cloudSyncEngine)
        self.databaseLoadState.initializationError = databaseOpenResult.errorDescription
        // Feature 21.1: `NSStatusItem` darf erst in `applicationDidFinishLaunching` entstehen
        // (siehe `FeedivoAppDelegate`) — hier nur die Abhängigkeiten durchreichen.
        if databaseOpenResult.errorDescription == nil {
            self.appDelegate.configureMenubarController(feedivoDatabase: database, feedViewModel: feedViewModel)
            self.localExtensionBridgeServer.start()
        }
        // Review-Fix (Task 14, Critical 2): NICHT mehr blind nach `isEnabled()` starten — der
        // Erst-Aktivierungs-Dialog (`CloudSyncFirstActivationView`) muss laut Design VOR dem
        // allerersten `start()` je Aktivierung laufen. `isEnabledKey` selbst flippt aber sofort
        // beim Umlegen des UI-Schalters, lange bevor der Dialog per „Weiter" abgeschlossen ist —
        // beendet der Nutzer die App, während der Dialog noch offen ist, wäre `isEnabled()`
        // bereits persistent `true`, ohne dass je eine Entscheidung getroffen wurde.
        // `shouldAutoStartSyncEngineAtLaunch` verweigert den Start zusätzlich, solange
        // `pendingFirstActivationKey` noch gesetzt ist — der Dialog erscheint dann beim
        // nächsten Öffnen des Sync-Einstellungen-Tabs erneut (siehe `SyncSettingsView.onAppear`).
        if databaseOpenResult.errorDescription == nil,
           CloudSyncSettings.shouldAutoStartSyncEngineAtLaunch(
               isEnabled: CloudSyncSettings.isEnabled(),
               hasPendingFirstActivation: CloudSyncSettings.hasPendingFirstActivation()
           ) {
            self.cloudSyncEngine.start()
        }
    }

    var body: some Scene {
        let appLanguage = AppLanguage.resolved(from: appLanguageRawValue)
        let interfaceTextSize = InterfaceTextSize.resolved(from: interfaceTextSizeRawValue)
        let appAppearance = AppAppearance.resolved(from: appAppearanceRawValue)

        // `Window` (nicht `WindowGroup`) ist hier bewusst: eine WindowGroup erlaubt
        // laut SwiftUI-Design mehrere gleichzeitige Instanzen — jeder Aufruf von
        // `openWindow(id: "main")` (Menubar-Popover-Button "Feedivo öffnen") hätte
        // damit eine NEUE Instanz erzeugt statt die bestehende zu fokussieren
        // (gefunden 2026-07-11, Nutzer-Report). `Window` ist der echte
        // Singleton-Szenentyp, den die anderen Einzelfenster der App (Suche,
        // Organizer, Statistik) bereits korrekt verwenden.
        Window("Feedivo", id: "main") {
            Group {
                if let initializationError = databaseLoadState.initializationError {
                    ContentUnavailableView {
                        Label(L10n.databaseInitErrorTitle, systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(verbatim: "\(L10n.databaseInitErrorMessage)\n\n\(initializationError)")
                    }
                } else {
                    ContentView(feedViewModel: feedViewModel)
                }
            }
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .environment(databaseLoadState)
                .environment(appDelegate.pendingURLSchemeAction)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
                .toolbarBackground(.hidden, for: .windowToolbar)
                .task {
                    guard databaseLoadState.initializationError == nil else {
                        return
                    }
                    backfillStoredArticleMetadataIfNeeded()
                    trimImageCacheToSelectedLimit()
                    ensureSpotlightBackfillIfNeeded()
                    scheduleBackgroundRefresh()
                    performSilentUpdateCheckIfNeeded()
                }
                .onChange(of: backgroundRefreshIsEnabled) {
                    scheduleBackgroundRefresh()
                }
                .onChange(of: backgroundRefreshIntervalMinutes) {
                    scheduleBackgroundRefresh()
                }
                .onChange(of: articleRetentionIsEnabled) {
                    cleanupExpiredArticlesIfNeeded()
                }
                .onChange(of: articleRetentionDays) {
                    cleanupExpiredArticlesIfNeeded()
                }
                .onChange(of: articleRetentionMinimumArticlesPerFeed) {
                    articleRetentionMinimumArticlesPerFeed = ArticleRetentionSettings.clampedMinimumArticlesPerFeed(
                        articleRetentionMinimumArticlesPerFeed
                    )
                    cleanupExpiredArticlesIfNeeded()
                }
                .onChange(of: articleRetentionIncludesProtectedArticles) {
                    cleanupExpiredArticlesIfNeeded()
                }
                .onChange(of: spotlightIndexingIsEnabled) {
                    handleSpotlightIndexingToggleChange()
                }
                .sheet(item: $updateCheckReleasePresentation) { release in
                    UpdateAvailableSheet(
                        release: release,
                        onOpenOnGitHub: {
                            NSWorkspace.shared.open(release.htmlURL)
                        },
                        onDismiss: {
                            updateCheckReleasePresentation = nil
                        }
                    )
                }
                .alert(L10n.updateCheckUpToDateTitle, isPresented: $showsUpdateCheckUpToDateAlert) {
                    Button(L10n.commonOK, role: .cancel) {}
                } message: {
                    Text(updateCheckUpToDateMessage)
                }
                .alert(
                    L10n.updateCheckErrorTitle,
                    isPresented: Binding(
                        get: { updateCheckErrorMessage != nil },
                        set: { isPresented in
                            if !isPresented {
                                updateCheckErrorMessage = nil
                            }
                        }
                    )
                ) {
                    Button(L10n.commonOK, role: .cancel) {}
                } message: {
                    Text(updateCheckErrorMessage ?? "")
                }
        }
        .commands {
            ArticleCommands()
            FeedCommands()
            ViewCommands()
            // Bewusst statischer Titel (kein "•"-Präfix mehr bei hasUnseenUpdate) — ein
            // dynamischer Menü-Titel zwingt SwiftUI, das komplette App-Menü live per
            // NSMenu.setItemArray: neu aufzubauen, was hier reproduzierbar zu einem
            // AppKit-internen Absturz führte (NSRangeException in
            // NSContextMenuImpl.preferredViewHeightForMenuItemAtIndex:, ausgelöst durch
            // die neuere "Liquid Glass"-Menü-Darstellung, die intern per NSTableView
            // rendert und beim Live-Umbau des Item-Arrays race'd — Nutzer-Report
            // 2026-07-31, reproduziert direkt nach "Nach Updates suchen…" +
            // Bestätigen des "Kein Update"-Alerts). Der Badge-Hinweis lebt jetzt nur
            // noch im "Über"-Tab, hasUnseenUpdate wird weiterhin gepflegt, aber nicht
            // mehr für den Menü-Titel verwendet.
            CommandGroup(after: .appInfo) {
                Button(L10n.updateCheckMenuItem) {
                    performManualUpdateCheck()
                }
            }
            // Entfernt den von SwiftUI automatisch bereitgestellten, aber funktionslosen
            // "Drucken..."-Menuepunkt (Datei-Menue, Standard-Tastenkombination Cmd+P).
            // Ohne diese Entfernung kollidiert er mit dem neuen Drucken-Button in
            // SQLiteReaderView.swift (Feature 25.1), der ebenfalls Cmd+P beansprucht —
            // das Standard-NSMenuItem gewinnt den Tastenkombinations-Konflikt und zeigt
            // beim Ausloesen den generischen AppKit-Fallback-Alert "Diese App
            // unterstuetzt Drucken nicht", statt dass unser Drucken-Button reagiert
            // (Live-Bug-Fund 2026-07-17, Nutzer-Report).
            CommandGroup(replacing: .printItem) {}
        }
        Window(L10n.articleSearchCommand, id: ArticleSearchWindowView.windowID) {
            ArticleSearchWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 760, height: 560)

        Window(OrganizerWindowView.windowTitle, id: OrganizerWindowView.windowID) {
            OrganizerWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }

        Window(L10n.statisticsWindowTitle, id: StatisticsWindowView.windowID) {
            StatisticsWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 820, height: 640)
        .defaultSize(width: 920, height: 620)

        Window(L10n.cleanupHistoryTitle, id: CleanupHistoryWindowView.windowID) {
            CleanupHistoryWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 420, height: 480)

        WindowGroup(for: ArticleWindowRequest.self) { $request in
            // Gemeinsame Modifier auf einem umschließenden Group, damit auch der
            // else-Zweig (fehlende Anfrage) Sprache/Textgröße/Darstellung erbt,
            // statt nur der Erfolgsfall.
            Group {
                if let request {
                    ArticleWindowView(request: request)
                } else {
                    ContentUnavailableView(
                        L10n.articleWindowMissingTitle,
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(L10n.articleWindowMissingDescription)
                    )
                }
            }
            .environment(\.locale, appLanguage.locale)
            .environment(\.interfaceTextSize, interfaceTextSize)
            .environment(\.feedivoDatabase, feedivoDatabase)
            .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
            .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 900, height: 720)

        Settings {
            SettingsView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .environment(databaseLoadState)
                .environment(cloudSyncEngine.status)
                .environment(\.cloudSyncEngine, cloudSyncEngine)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .windowResizability(.contentSize)

        // Feature 21.1: Kein `MenuBarExtra`-Scene-Eintrag hier — das Menubar-Icon läuft
        // komplett selbstständig über `menubarStatusItemController` (AppKit `NSStatusItem`/
        // `NSPopover`, per UserDefaults-KVO reaktiv statt an eine SwiftUI-View gebunden),
        // siehe dessen Doc-Comment für die vollständige Begründung.
    }

    private func scheduleBackgroundRefresh() {
        guard databaseLoadState.initializationError == nil else {
            return
        }
        try? BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: backgroundRefreshIsEnabled,
            intervalMinutes: backgroundRefreshIntervalMinutes,
            scheduler: backgroundRefreshScheduler
        )
    }

    private struct DatabaseOpenResult {
        var database: FeedivoDatabase
        var errorDescription: String?
    }

    private static func openSQLiteDatabase() -> DatabaseOpenResult {
        do {
            return DatabaseOpenResult(
                database: try FeedivoDatabase.open(at: FeedivoDatabaseLocation.databaseURL()),
                errorDescription: nil
            )
        } catch {
            // Die Ersatzdatenbank hält die Scene technisch konstruierbar. Der
            // Hauptinhalt bleibt jedoch blockiert, damit die flüchtige Datenbank
            // niemals wie ein erfolgreicher, leerer Produktivstart aussieht.
            return DatabaseOpenResult(
                database: try! FeedivoDatabase.inMemoryForTests(),
                errorDescription: error.localizedDescription
            )
        }
    }

    private func trimImageCacheToSelectedLimit() {
        try? ImageCacheService.shared.trimCache(
            toLimitInBytes: ImageCacheSettings.currentLimitInBytes
        )
    }

    @MainActor
    private func cleanupExpiredArticlesIfNeeded() {
        guard databaseLoadState.initializationError == nil else {
            return
        }
        ArticleRetentionCleanupService.runAutomaticCleanup(
            database: feedivoDatabase,
            isEnabled: articleRetentionIsEnabled,
            retentionDays: articleRetentionDays,
            minimumArticlesPerFeed: articleRetentionMinimumArticlesPerFeed,
            includeProtectedArticles: articleRetentionIncludesProtectedArticles,
            triggerSource: .settingsChange
        )
    }

    @MainActor
    private func ensureSpotlightBackfillIfNeeded() {
        guard databaseLoadState.initializationError == nil else {
            return
        }
        // Läuft als eigener Task statt inline `await` im aufrufenden
        // `.task { }`-Block (Whole-Branch-Review-Fund, Feature 9.3): Ein
        // sehr großer Artikel-Bestand könnte den Backfill mehrere Sekunden
        // dauern lassen — inline würde das den nachfolgenden
        // `scheduleBackgroundRefresh()`-Aufruf im selben Block verzögern.
        // `SpotlightIndexingService.ensureBackfillIfNeeded` liest inzwischen
        // komplett über `FeedivoDatabase.readAsync` (GRDBs eigene
        // Hintergrund-Queue) statt der vorherigen blockierenden
        // Sync-Variante, blockiert also auch während der Laufzeit dieses
        // Tasks nicht mehr den MainActor/App-Start.
        let database = feedivoDatabase
        Task {
            do {
                try await SpotlightIndexingService.ensureBackfillIfNeeded(database: database)
            } catch {
                AppLogger.dataAccess.error("Spotlight-Backfill: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func runUpdateCheck() async -> UpdateCheckOutcome {
        await UpdateChecker().check(
            currentMarketingVersion: AppVersionInfo.marketingVersion,
            currentBuildNumber: AppVersionInfo.buildNumber
        )
    }

    // Nutzerwunsch: zeigt im "Kein Update"-Dialog zusätzlich die installierte
    // und die aktuell auf GitHub gefundene Version - Zeilenumbruch kommt aus
    // dem lokalisierten Format-String selbst (\n in Localizable.xcstrings).
    private var updateCheckUpToDateMessage: String {
        let installedVersion = "\(AppVersionInfo.marketingVersion) (\(AppVersionInfo.buildNumber))"
        if let tagName = updateCheckUpToDateRelease?.tagName {
            return L10n.updateCheckUpToDateMessage(installedVersion: installedVersion, latestReleaseTag: tagName)
        }
        return L10n.updateCheckUpToDateMessageNoRelease(installedVersion: installedVersion)
    }

    private func performManualUpdateCheck() {
        // Fix Whole-Branch-Review (Important): Hauptfenster öffnen/fokussieren,
        // BEVOR der Check läuft - sonst hängen Sheet/Alert an einem geschlossenen
        // Fenster und erscheinen entweder gar nicht oder überraschend erst beim
        // nächsten Öffnen des Fensters. Siehe Kommentar an openWindow oben.
        openWindow(id: "main")

        // Fix Whole-Branch-Review (Important): Re-Entrancy-Guard - wiederholte
        // Klicks während ein Check bereits läuft dürfen keine weiteren,
        // parallelen GitHub-API-Aufrufe auslösen (60 Requests/Stunde-Budget ohne
        // Authentifizierung). Läuft bereits einer, einfach nichts tun - auch das
        // Badge bleibt in diesem Fall unangetastet.
        guard !isUpdateCheckInFlight else {
            return
        }
        isUpdateCheckInFlight = true

        // Nutzer schaut gerade hin - Badge sofort weg, unabhängig vom Ergebnis.
        updateCheckHasUnseenUpdate = false
        Task {
            let outcome = await runUpdateCheck()
            switch outcome {
            case .updateAvailable(let release):
                updateCheckReleasePresentation = release
            case .upToDate(let latestKnownRelease):
                updateCheckUpToDateRelease = latestKnownRelease
                showsUpdateCheckUpToDateAlert = true
            case .failed(let message):
                updateCheckErrorMessage = message
            }
            isUpdateCheckInFlight = false
        }
    }

    private func performSilentUpdateCheckIfNeeded() {
        guard updateCheckIsAutomaticCheckEnabled else {
            return
        }
        Task {
            let outcome = await runUpdateCheck()
            switch outcome {
            case .updateAvailable:
                updateCheckHasUnseenUpdate = true
            case .upToDate:
                updateCheckHasUnseenUpdate = false
            case .failed(let message):
                // Bewusst keine UI-Unterbrechung beim stillen Start-Check - nur Log.
                AppLogger.dataAccess.error("Update-Check (Start): \(message, privacy: .public)")
            }
        }
    }

    @MainActor
    private func handleSpotlightIndexingToggleChange() {
        if spotlightIndexingIsEnabled {
            ensureSpotlightBackfillIfNeeded()
        } else {
            SpotlightIndexingService.deindexAll()
        }
    }

    @MainActor
    private func backfillStoredArticleMetadataIfNeeded() {
        restoreDefaultSmartFoldersIfNeeded()
    }

    @MainActor
    private func restoreDefaultSmartFoldersIfNeeded() {
        try? SQLiteSmartFolderStore(database: feedivoDatabase).restoreDefaultFolders()
    }
}

// Hält den Status des Datenbank-Ladevorgangs beim App-Start. Bleibt `nil`,
// wenn die on-disk-Datenbank normal geöffnet wurde. Bei einem Fehler bleibt
// die Meldung für die gesamte Sitzung erhalten und blockiert den Hauptinhalt;
// die technische Ersatzdatenbank darf nicht als leerer Produktivstand wirken.
@Observable
final class DatabaseLoadState {
    var initializationError: String?
}
