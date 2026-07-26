import SwiftUI
import GRDB

/// Sheet zum Auflösen laufender Feld-Ebene-Konflikte (Phase 3) — pro Konflikt zwei Buttons
/// „Dieses Gerät"/„Anderes Gerät". Nach Auswahl wird der gemergte Wert direkt in die
/// betroffene Tabelle geschrieben und der Konflikt aus `pending_sync_conflicts` entfernt.
/// Siehe Design-Spec `docs/superpowers/specs/2026-07-26-icloud-sync-phase3-design.md`,
/// Abschnitt 5.
struct SyncConflictResolutionView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.dismiss) private var dismiss
    @State private var conflicts: [PendingSyncConflictRecord] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(
                    Dictionary(grouping: conflicts, by: { "\($0.recordType)|\($0.recordName)" })
                        .sorted(by: { $0.key < $1.key }),
                    id: \.key
                ) { _, group in
                    Section(group.first?.recordType ?? "") {
                        ForEach(group) { conflict in
                            conflictRow(conflict)
                        }
                    }
                }
            }
            .navigationTitle(L10n.syncConflictsTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.commonDone) { dismiss() }
                }
            }
            .task { loadConflicts() }
            .alert(L10n.commonError, isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue { errorMessage = nil }
                }
            )) {
                Button(L10n.commonOK) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func conflictRow(_ conflict: PendingSyncConflictRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conflict.fieldName)
                .font(.headline)
            HStack {
                Button(action: { resolve(conflict, keepLocal: true) }) {
                    VStack(alignment: .leading) {
                        Text(L10n.syncConflictsThisDevice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(conflict.localValue)
                    }
                }
                .buttonStyle(.bordered)
                Button(action: { resolve(conflict, keepLocal: false) }) {
                    VStack(alignment: .leading) {
                        Text(L10n.syncConflictsOtherDevice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(conflict.serverValue)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadConflicts() {
        guard let feedivoDatabase else { return }
        do {
            conflicts = try PendingSyncConflictStore(database: feedivoDatabase).conflicts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolve(_ conflict: PendingSyncConflictRecord, keepLocal: Bool) {
        guard let feedivoDatabase, let mapping = CloudSyncEngine.mapping(forRecordType: conflict.recordType) else { return }
        do {
            if !keepLocal {
                try applyServerFieldValue(conflict, mapping: mapping, database: feedivoDatabase)
            }
            // `keepLocal == true`: der lokale Wert steht bereits in der Tabelle (er wurde nie
            // überschrieben, siehe Task 5) — nur den Konflikt-Eintrag entfernen und den
            // nächsten regulären Sendeversuch anstoßen.
            guard let conflictID = conflict.id else { return }
            try PendingSyncConflictStore(database: feedivoDatabase).resolve(id: conflictID)
            try CloudSyncPendingChangeStore(database: feedivoDatabase).enqueue(
                recordType: conflict.recordType,
                recordName: conflict.recordName,
                changeType: .save
            )
            CloudSyncEngine.notifyPendingChangesAvailable(database: feedivoDatabase)
            // Weder `PendingSyncConflictStore.resolve(id:)` noch `CloudSyncPendingChangeStore.
            // enqueue(...)` bumpen selbst den Statuszähler (Store-Konvention: das ist Aufgabe
            // des Aufrufers, siehe CLAUDE.md-Gotcha „GRDB statt SwiftData") — ohne diesen
            // Aufruf bliebe das „Konflikte: N"-Badge im Sync-Tab nach dem Schließen dieses
            // Sheets auf dem alten Stand stehen.
            SQLiteDataInvalidation.bumpStatusVersion()
            loadConflicts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Schreibt den Server-Wert für GENAU dieses eine Feld in die lokale Tabelle — über einen
    /// direkten SQL-`UPDATE`, da die einzelnen `CloudSyncRecordMapping`-Typen keine generische
    /// Ein-Feld-Update-Methode anbieten (bewusst: Feld-Ebene-Schreibzugriff ist ein
    /// Phase-3-spezifischer Bedarf, kein allgemeiner Store-Anwendungsfall). Der `mapping`-
    /// Parameter selbst dient hier nur als Existenz-Beweis (der Aufrufer hat bereits
    /// verifiziert, dass für `conflict.recordType` ein registriertes Mapping existiert, bevor
    /// überhaupt ein SQL-Statement gebaut wird) — die eigentliche Tabellennamens-Auflösung
    /// läuft bewusst über die eigene, lokale `tableName(forRecordType:)`-Zuordnung.
    private func applyServerFieldValue(
        _ conflict: PendingSyncConflictRecord,
        mapping: any CloudSyncRecordMapping.Type,
        database: FeedivoDatabase
    ) throws {
        let tableName = Self.tableName(forRecordType: conflict.recordType)
        try database.write { db in
            try db.execute(
                sql: "UPDATE \(tableName) SET \(conflict.fieldName) = ? WHERE id = ?",
                arguments: [conflict.serverValue, conflict.recordName]
            )
        }
    }

    private static func tableName(forRecordType recordType: String) -> String {
        switch recordType {
        case "Tag": return "tags"
        case "Feed": return "feeds"
        case "FeedFolder": return "feed_folders"
        case "Rule": return "rules"
        case "RuleCondition": return "rule_conditions"
        case "SmartFolder": return "smart_folders"
        case "SmartFolderCondition": return "smart_folder_conditions"
        default: return ""
        }
    }
}
