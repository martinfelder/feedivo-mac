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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.firstActivationTitle)
                .font(.title2.bold())

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if collisions.isEmpty {
                Text(L10n.firstActivationNoCollisions)
                    .foregroundStyle(.secondary)
            } else {
                List(collisions, id: \.cloudRecordID.recordName) { collision in
                    collisionRow(collision)
                }
            }

            HStack {
                Spacer()
                Button(L10n.firstActivationContinue) {
                    applyDecisions()
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
        let (tags, folders) = await CloudSyncFirstActivationAnalyzer.fetchExistingCloudRecords(container: container)

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

    private func applyDecisions() {
        guard let feedivoDatabase else { return }
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
            }
        }
        // Store-Konvention (siehe CLAUDE.md-Gotcha „GRDB statt SwiftData"): weder `merge`
        // noch `keepBoth` bumpen selbst den Statuszähler — ohne diesen Aufruf würde die
        // Sidebar nach einem Merge (z. B. verschwundener Duplikat-Tag) nicht neu laden.
        if !collisions.isEmpty {
            SQLiteDataInvalidation.bumpStatusVersion()
        }
    }
}
