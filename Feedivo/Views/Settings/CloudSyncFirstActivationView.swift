import SwiftUI
import CloudKit
import OSLog

/// Einmaliger Merge-Dialog beim Umlegen des iCloud-Sync-Schalters — erscheint VOR dem
/// eigentlichen Backfill. Zeigt erkannte Namens-Duplikate (Tag/FeedFolder) zur Entscheidung,
/// oder nur eine kurze Zusammenfassung, falls keine gefunden wurden. Siehe Design-Spec
/// `docs/superpowers/specs/2026-07-26-icloud-sync-phase3-design.md`, Abschnitt 6.
///
/// Wichtig für die Aufrufreihenfolge (siehe `SettingsView.swift`, `SyncSettingsView`): dieses
/// Sheet wird gezeigt, BEVOR `CloudSyncEngine.start()` zum ersten Mal läuft — `onContinue()`
/// löst `start()` erst nach `applyDecisions()` aus. Würde die Engine zuerst starten, würde ihr
/// `backfillAllExistingRecords`-Schritt jeden lokalen Datensatz bereits bedingungslos
/// einreihen, bevor die hier getroffenen Merge-/Beide-behalten-Entscheidungen überhaupt
/// angewendet wurden — genau das Problem, das dieser Dialog verhindern soll.
struct CloudSyncFirstActivationView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.dismiss) private var dismiss
    let onContinue: () -> Void

    @State private var isLoading = true
    @State private var collisions: [CloudSyncFirstActivationAnalyzer.FirstActivationCollision] = []
    @State private var decisions: [String: Bool] = [:] // Schlüssel: cloudRecordID.recordName, true = zusammenführen
    /// Verbesserung nach Nutzer-Feedback zum Dialog: `true`, wenn mindestens eine der beiden
    /// CloudKit-Abfragen in `loadCollisions()` fehlgeschlagen ist (z. B. kein Netz). Ohne dieses
    /// Flag sah der Dialog bei "Prüfung fehlgeschlagen" optisch identisch aus wie bei "Prüfung
    /// erfolgreich, keine Duplikate gefunden" — beides zeigte denselben positiven Text.
    @State private var checkFailed = false
    /// Zweiter Bugfix (Nutzer-Report 2026-08-08, per `/usr/bin/log stream` verifiziert): `true`,
    /// wenn der Fehlschlag konkret der bekannte CloudKit-Schema-Fehler "Field 'recordName' is not
    /// marked queryable" ist (siehe `CloudSyncFirstActivationAnalyzer.isMissingQueryableIndexError`)
    /// — steuert, ob die generische oder die gezielte, actionable Warnung angezeigt wird.
    @State private var checkFailedIsMissingIndex = false
    /// Whole-Branch-Review-Fund (Important 3): nicht-`nil`, sobald mindestens eine
    /// Merge-/Beide-behalten-Entscheidung in `applyDecisions()` fehlgeschlagen ist — zeigt
    /// einen Fehler-Alert, statt (wie zuvor) den Fehler nur zu loggen und trotzdem zu
    /// `start()` weiterzulaufen. Das Sheet bleibt in diesem Fall offen: der Nutzer kann seine
    /// Entscheidung im Picker anpassen (z. B. „Zusammenführen" statt „Beide behalten") und
    /// erneut auf „Weiter" tippen — `applyDecisions()` ist absichtlich idempotent gehalten
    /// (dieselbe, beim Laden einmalig eingefrorene `collision.name` wird bei jedem erneuten
    /// Versuch als Grundlage genutzt), ein erneuter Klick ist deshalb ein echter Retry, keine
    /// Doppel-Anwendung.
    @State private var mergeFailureMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.firstActivationTitle)
                .font(.title2.bold())

            // Verbesserung nach Nutzer-Feedback: der Dialog nannte bisher nicht, WAS er
            // eigentlich prüft (nur Tags/Ordner, nicht Feeds/Regeln/Artikelstatus — die laufen
            // über den separaten Last-Write-Wins-Konfliktpfad nach der Aktivierung). Immer
            // sichtbar, unabhängig vom Lade-/Ergebniszustand.
            Text(L10n.firstActivationScopeNote)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if checkFailed {
                    Label(
                        checkFailedIsMissingIndex ? L10n.firstActivationCheckFailedMissingIndex : L10n.firstActivationCheckFailed,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
                if collisions.isEmpty {
                    // Bei fehlgeschlagenem Check bewusst KEINE positive "keine Duplikate
                    // gefunden"-Meldung mehr zeigen — die Warnung oben ersetzt sie, statt beide
                    // widersprüchlichen Aussagen übereinander darzustellen.
                    if !checkFailed {
                        Text(L10n.firstActivationNoCollisions)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Bei einem Teilfehlschlag (z. B. Tags-Abfrage erfolgreich, Ordner-Abfrage
                    // nicht) können trotzdem bereits gefundene Kollisionen vorliegen — die
                    // Warnung UND die Liste erscheinen dann gemeinsam, statt echte Funde zu
                    // verstecken.
                    List(collisions, id: \.cloudRecordID.recordName) { collision in
                        collisionRow(collision)
                    }
                }
            }

            HStack {
                Spacer()
                Button(L10n.firstActivationContinue) {
                    // Whole-Branch-Review-Fund (Important 3): nur bei VOLLSTÄNDIGEM Erfolg
                    // (keine einzige fehlgeschlagene Kollision) tatsächlich fortfahren — bei
                    // jedem Fehlschlag bleibt das Sheet offen und zeigt den Alert weiter unten,
                    // statt den Nutzer im Unklaren zu lassen, während `start()` bereits mit
                    // einem unaufgelösten Duplikat losläuft.
                    guard applyDecisions() else { return }
                    // Review-Fix (Task 14, Critical 2): erst HIER, beim tatsächlichen
                    // Abschluss des Erst-Aktivierungs-Ablaufs, wird die Sperre wieder
                    // aufgehoben — siehe CloudSyncSettings.pendingFirstActivationKey und
                    // FeedivoApp.init(). Muss vor onContinue() (löst CloudSyncEngine.start()
                    // aus) geschehen, auch wenn es für den aktuellen start()-Aufruf selbst
                    // keine Rolle spielt — die Reihenfolge macht den Zustand während des
                    // gesamten Übergangs konsistent, falls onContinue() künftig einmal
                    // asynchron würde.
                    CloudSyncSettings.setPendingFirstActivation(false)
                    onContinue()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 300)
        .task { await loadCollisions() }
        .alert(L10n.commonError, isPresented: Binding(
            get: { mergeFailureMessage != nil },
            set: { newValue in
                if !newValue { mergeFailureMessage = nil }
            }
        )) {
            Button(L10n.commonOK) { mergeFailureMessage = nil }
        } message: {
            Text(mergeFailureMessage ?? "")
        }
    }

    @ViewBuilder
    private func collisionRow(_ collision: CloudSyncFirstActivationAnalyzer.FirstActivationCollision) -> some View {
        let key = collision.cloudRecordID.recordName
        Picker(collision.name, selection: Binding(
            get: { decisions[key] ?? true },
            set: { decisions[key] = $0 }
        )) {
            Text(L10n.firstActivationMerge).tag(true)
            Text(L10n.firstActivationKeepBoth).tag(false)
        }
        .pickerStyle(.segmented)
    }

    private func loadCollisions() async {
        let container = CKContainer(identifier: CloudSyncSettings.cloudKitContainerIdentifier)
        let (tags, folders, fetchFailed, missingQueryableIndex) = await CloudSyncFirstActivationAnalyzer.fetchExistingCloudRecords(container: container)
        checkFailed = fetchFailed
        checkFailedIsMissingIndex = missingQueryableIndex

        guard let feedivoDatabase else {
            isLoading = false
            return
        }
        do {
            collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: feedivoDatabase, tagRecords: tags, folderRecords: folders)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Erst-Aktivierungs-Duplikat-Erkennung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            collisions = []
        }
        isLoading = false
    }

    /// Wendet alle getroffenen Merge-/Beide-behalten-Entscheidungen an. Liefert `true`, wenn
    /// ALLE Kollisionen erfolgreich verarbeitet wurden — nur dann darf der Aufrufer mit
    /// `start()` fortfahren. Whole-Branch-Review-Fund (Important 3): die ursprüngliche Version
    /// fing Fehler pro Kollision nur ab, loggte sie und lief unbeirrt weiter bis zu
    /// `setPendingFirstActivation(false)`/`onContinue()` — schlägt z. B. `keepBoth` fehl, weil
    /// der disambiguierte Name („X (2)") selbst schon existiert (UNIQUE-Index auf
    /// `tags.name`), würde die Sync-Engine trotzdem mit einem weiterhin unaufgelösten Duplikat
    /// starten, ohne dass der Nutzer davon je erfährt. Jetzt: Fehlschläge werden gesammelt und
    /// als Alert angezeigt (siehe `mergeFailureMessage`), der Aufrufer bricht ab statt
    /// fortzufahren.
    private func applyDecisions() -> Bool {
        guard let feedivoDatabase else { return true }
        var failedCollisionNames: [String] = []
        for collision in collisions {
            let shouldMerge = decisions[collision.cloudRecordID.recordName] ?? true
            do {
                if shouldMerge {
                    try CloudSyncFirstActivationMerger.merge(collision, database: feedivoDatabase)
                } else {
                    try CloudSyncFirstActivationMerger.keepBoth(collision, database: feedivoDatabase)
                }
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Erst-Aktivierungs-Entscheidung konnte nicht angewendet werden: \(error.localizedDescription, privacy: .public)")
                failedCollisionNames.append(collision.name)
            }
        }
        // Store-Konvention (siehe CLAUDE.md-Gotcha „GRDB statt SwiftData"): weder `merge`
        // noch `keepBoth` bumpen selbst den Statuszähler — ohne diesen Aufruf würde die
        // Sidebar nach einem Merge (z. B. verschwundener Duplikat-Tag) nicht neu laden. Läuft
        // bewusst auch bei Teilfehlschlägen, damit die erfolgreich verarbeiteten Kollisionen
        // sofort sichtbar werden, während der Nutzer die fehlgeschlagenen im Alert anpasst.
        if !collisions.isEmpty {
            SQLiteDataInvalidation.shared.bumpStatusVersion()
        }

        guard failedCollisionNames.isEmpty else {
            mergeFailureMessage = L10n.firstActivationMergeFailedMessage(
                failedCollisionNames.joined(separator: ", ")
            )
            return false
        }
        return true
    }
}
