import Foundation
import GRDB

/// Datenbank-Spiegel des iCloud-Sync-Aktiv-Flags.
///
/// **Quelle der Wahrheit bleibt UserDefaults** (`CloudSyncSettings.isEnabledKey`, direkt an den
/// `@AppStorage`-Schalter in `SyncSettingsView` gebunden). Diese Tabelle ist ein reiner Spiegel,
/// der bei jedem App-Start (`FeedivoApp.init`) und bei jedem Umlegen des Schalters
/// (`SyncSettingsView.onChange`) abgeglichen wird — dadurch selbstheilend, falls beide je
/// auseinanderlaufen.
///
/// **Warum ueberhaupt gespiegelt:** `FeedivoMCPServer` laeuft bewusst unsandboxed (ADR-011),
/// sein `UserDefaults.standard` zeigt auf eine andere Preferences-Domaene als die der sandboxed
/// Feedivo-App. `CloudSyncSettings.isEnabled()` liefert dort praktisch immer `false` — die
/// Store-Gates (`enqueuePendingSync`) haetten MCP-Schreibvorgaenge deshalb nie in die
/// Sync-Warteschlange eingereiht, waehrend `statusSyncUpdatedAt` trotzdem gesetzt wurde
/// (Last-Write-Wins haette eingehende Remote-Aenderungen dauerhaft unterdrueckt).
struct CloudSyncSettingsStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Liest das Flag ueber eine **bereits offene** Transaktions-Verbindung.
    ///
    /// Das ist die Variante, die alle `enqueuePendingSync`-Gates verwenden: sie laufen bereits
    /// innerhalb eines `database.write`-Blocks. Ein `database.read`/`database.write` von dort
    /// aus verletzt GRDBs Reentranz-Precondition ("Database methods are not reentrant.",
    /// `DatabasePool.swift`/`DatabaseQueue.swift`) und crasht zur Laufzeit. Nebeneffekt des
    /// Lesens ueber `db`: das Gate sieht garantiert denselben Datenbankzustand wie die
    /// Mutation, die es begleitet.
    ///
    /// Fail-closed: jeder Fehler (fehlende Tabelle, Lesefehler) liefert `false`. Nicht zu
    /// synchronisieren ist sicherer als faelschlich zu synchronisieren — es geht nichts
    /// verloren, der Push passiert beim naechsten erfolgreichen Lesen.
    static func isEnabled(in db: Database) -> Bool {
        do {
            return try Bool.fetchOne(db, sql: "SELECT isEnabled FROM cloud_sync_settings WHERE id = 1") ?? false
        } catch {
            return false
        }
    }

    func isEnabled() throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(db, sql: "SELECT isEnabled FROM cloud_sync_settings WHERE id = 1") ?? false
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE cloud_sync_settings SET isEnabled = ? WHERE id = 1", arguments: [isEnabled])
        }
    }

    /// Gleicht den Spiegel gegen die Quelle der Wahrheit ab. Wird bei jedem App-Start und bei
    /// jedem Umlegen des Schalters aufgerufen — bewusst unbedingt (nicht einmalig gated), damit
    /// ein einmal auseinandergelaufener Zustand sich beim naechsten Start von selbst repariert.
    func mirrorFromUserDefaults(_ defaults: UserDefaults = .standard) throws {
        try setEnabled(CloudSyncSettings.isEnabled(in: defaults))
    }
}
