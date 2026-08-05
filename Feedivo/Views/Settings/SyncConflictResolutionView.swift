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
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if conflicts.isEmpty {
                    ContentUnavailableView(
                        L10n.syncConflictsEmptyTitle,
                        systemImage: "checkmark.circle"
                    )
                } else {
                    List {
                        ForEach(
                            Dictionary(grouping: conflicts, by: { "\($0.recordType)|\($0.recordName)" })
                                .sorted(by: { $0.key < $1.key }),
                            id: \.key
                        ) { _, group in
                            Section(groupHeaderTitle(for: group)) {
                                ForEach(group) { conflict in
                                    conflictRow(conflict)
                                }
                            }
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
            // Ohne diesen expliziten Frame berechnet macOS die Sheet-Fenstergröße einmalig
            // anhand des allerersten Layout-Durchlaufs — der findet statt, BEVOR das
            // asynchrone `.task` unten `conflicts` befüllt (`isLoading` startet als `true`,
            // eine `ProgressView` ohne eigenen Frame hätte ebenfalls eine winzige Idealgröße).
            // Live gegen eine echte, direkt in die SQLite-DB eingefügte Testzeile reproduziert
            // (2026-07-26): das Sheet öffnete sich mit korrektem Titel, aber komplett leerem
            // Inhalt — nur Titelzeile + „Fertig"-Button, keine einzige Konfliktzeile sichtbar,
            // obwohl `pending_sync_conflicts` nachweislich Zeilen enthielt.
            // `CloudSyncFirstActivationView` (dieselbe Sheet-Präsentation aus
            // `SyncSettingsView`) hat genau deshalb bereits `.frame(minWidth: 420, minHeight:
            // 300)` — dieselbe Konstante hier übernommen.
            .frame(minWidth: 420, minHeight: 300)
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

    /// Baut den Gruppen-Header-Titel für einen Konflikt (z. B. "Regel: Intune Artikel") —
    /// Whole-Branch-Review-Fix zu Task 11: die ursprüngliche Version zeigte hier nur den
    /// rohen `recordType` ("Rule"), wodurch zwei Konflikte auf verschiedenen Regeln optisch
    /// nicht unterscheidbar waren. Fällt auf den reinen Typ-Namen zurück, falls der Datensatz
    /// (z. B. weil er inzwischen lokal gelöscht wurde) nicht mehr gefunden werden kann.
    private func groupHeaderTitle(for group: [PendingSyncConflictRecord]) -> String {
        guard let first = group.first else { return "" }
        let typeLabel = Self.recordTypeLabel(forRecordType: first.recordType)
        guard let feedivoDatabase,
              let name = Self.displayName(
                  forRecordType: first.recordType,
                  recordName: first.recordName,
                  database: feedivoDatabase
              ) else {
            return typeLabel
        }
        return "\(typeLabel): \(name)"
    }

    /// Nutzerverständliche Kurzbezeichnung für einen `recordType` (unabhängig vom konkreten
    /// Datensatz) — reiner Fallback-Text, falls kein Name ermittelt werden kann. Bewusst nicht
    /// `private` (anders als `tableName(forRecordType:)` oben) — reine, DB-freie Switch-Logik,
    /// direkt per `@testable import Feedivo` testbar (siehe `SyncConflictResolutionViewTests`).
    static func recordTypeLabel(forRecordType recordType: String) -> String {
        switch recordType {
        case "Tag": return L10n.syncConflictsRecordTypeTag
        case "Feed": return L10n.syncConflictsRecordTypeFeed
        case "FeedFolder": return L10n.syncConflictsRecordTypeFeedFolder
        case "Rule": return L10n.syncConflictsRecordTypeRule
        case "RuleCondition": return L10n.syncConflictsRecordTypeRuleCondition
        case "SmartFolder": return L10n.syncConflictsRecordTypeSmartFolder
        case "SmartFolderCondition": return L10n.syncConflictsRecordTypeSmartFolderCondition
        default: return recordType
        }
    }

    /// Liest den tatsächlichen Anzeigenamen des betroffenen Datensatzes direkt per GRDB-
    /// `fetchOne(db, key:)` (`recordName` ist die lokale Primärschlüssel-ID) — bewusst ohne
    /// Umweg über TagStore/FeedStore/FeedFolderStore/SQLiteRuleStore/SQLiteSmartFolderStore,
    /// da keiner dieser Stores durchgängig eine einfache Ein-Datensatz-nach-ID-Methode anbietet
    /// (TagStore/FeedFolderStore z. B. gar keine) und dieser Lookup ein reiner, isolierter
    /// Phase-3-Anzeigebedarf ist, kein allgemeiner Store-Anwendungsfall (analog zur Begründung
    /// bei `applyServerFieldValue` oben). `RuleCondition`/`SmartFolderCondition` haben selbst
    /// keinen eigenen Namen — zeigt stattdessen den Namen der übergeordneten Regel/des
    /// übergeordneten Intelligenten Ordners. Liefert `nil`, wenn der Datensatz (z. B. durch
    /// zwischenzeitliches lokales Löschen) nicht mehr existiert — der Aufrufer fällt dann auf
    /// den reinen Typ-Namen zurück, statt abzustürzen oder eine leere Zeile zu zeigen. Bewusst
    /// nicht `private` — direkt gegen eine echte In-Memory-`FeedivoDatabase` testbar (siehe
    /// `SyncConflictResolutionViewTests`), inkl. des Eltern-Lookups für Bedingungszeilen und des
    /// Fallback-Falls "Datensatz existiert nicht mehr".
    static func displayName(
        forRecordType recordType: String,
        recordName: String,
        database: FeedivoDatabase
    ) -> String? {
        try? database.read { db -> String? in
            switch recordType {
            case "Tag":
                return try TagRecord.fetchOne(db, key: recordName)?.name
            case "Feed":
                return try FeedRecord.fetchOne(db, key: recordName)?.title
            case "FeedFolder":
                return try FeedFolderRecord.fetchOne(db, key: recordName)?.name
            case "Rule":
                return try RuleRecord.fetchOne(db, key: recordName)?.name
            case "RuleCondition":
                guard let condition = try RuleConditionRecord.fetchOne(db, key: recordName) else {
                    return nil
                }
                return try RuleRecord.fetchOne(db, key: condition.ruleID)?.name
            case "SmartFolder":
                return try SmartFolderRecord.fetchOne(db, key: recordName)?.name
            case "SmartFolderCondition":
                guard let condition = try SmartFolderConditionRecord.fetchOne(db, key: recordName) else {
                    return nil
                }
                return try SmartFolderRecord.fetchOne(db, key: condition.smartFolderID)?.name
            default:
                return nil
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
        defer { isLoading = false }
        guard let feedivoDatabase else { return }
        do {
            conflicts = try PendingSyncConflictStore(database: feedivoDatabase).conflicts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolve(_ conflict: PendingSyncConflictRecord, keepLocal: Bool) {
        guard let feedivoDatabase else { return }
        do {
            try Self.resolveConflict(conflict, keepLocal: keepLocal, database: feedivoDatabase)
            loadConflicts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Kernlogik von `resolve(_:keepLocal:)` — nimmt die Datenbank explizit entgegen statt sie
    /// über `@Environment` zu lesen, analog zu `displayName(forRecordType:recordName:database:)`
    /// oben. Extrahiert, weil `resolve` selbst (View-Methode, liest `@Environment`) VOR diesem
    /// Whole-Branch-Review-Fix komplett ungetestet war — der einzige Produktionscode-Pfad, der
    /// Nutzerdaten bei der Konfliktauflösung tatsächlich mutiert. Bewusst nicht `private`,
    /// siehe `SyncConflictResolutionViewTests`.
    static func resolveConflict(
        _ conflict: PendingSyncConflictRecord,
        keepLocal: Bool,
        database: FeedivoDatabase
    ) throws {
        guard let mapping = CloudSyncEngine.mapping(forRecordType: conflict.recordType) else { return }
        if !keepLocal {
            try applyServerFieldValue(conflict, mapping: mapping, database: database)
        }
        // `keepLocal == true`: der lokale Wert steht bereits in der Tabelle (er wurde nie
        // überschrieben, siehe Task 5) — nur den Konflikt-Eintrag entfernen und den
        // nächsten regulären Sendeversuch anstoßen.
        guard let conflictID = conflict.id else { return }
        try PendingSyncConflictStore(database: database).resolve(id: conflictID)
        try CloudSyncPendingChangeStore(database: database).enqueue(
            recordType: conflict.recordType,
            recordName: conflict.recordName,
            changeType: .save
        )
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
        // Weder `PendingSyncConflictStore.resolve(id:)` noch `CloudSyncPendingChangeStore.
        // enqueue(...)` bumpen selbst den Statuszähler (Store-Konvention: das ist Aufgabe
        // des Aufrufers, siehe CLAUDE.md-Gotcha „GRDB statt SwiftData") — ohne diesen
        // Aufruf bliebe das „Konflikte: N"-Badge im Sync-Tab nach dem Schließen dieses
        // Sheets auf dem alten Stand stehen.
        SQLiteDataInvalidationSignal.shared.bumpStatusVersion()
    }

    /// Schreibt den Server-Wert für GENAU dieses eine Feld in die lokale Tabelle — über einen
    /// direkten SQL-`UPDATE`, da die einzelnen `CloudSyncRecordMapping`-Typen keine generische
    /// Ein-Feld-Update-Methode anbieten (bewusst: Feld-Ebene-Schreibzugriff ist ein
    /// Phase-3-spezifischer Bedarf, kein allgemeiner Store-Anwendungsfall). Der `mapping`-
    /// Parameter selbst dient hier nur als Existenz-Beweis (der Aufrufer hat bereits
    /// verifiziert, dass für `conflict.recordType` ein registriertes Mapping existiert, bevor
    /// überhaupt ein SQL-Statement gebaut wird) — die eigentliche Tabellennamens-Auflösung
    /// läuft bewusst über die eigene, lokale `tableName(forRecordType:)`-Zuordnung. Bewusst
    /// nicht `private` (wie `resolveConflict` oben) — direkt aus
    /// `SyncConflictResolutionViewTests` testbar.
    static func applyServerFieldValue(
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
