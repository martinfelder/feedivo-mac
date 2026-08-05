import Foundation
import GRDB

struct FeedivoDatabase {
    enum DebugTableInspectionError: Error {
        case unsupportedTableName(String)
    }

    private let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    static func open(at fileURL: URL) throws -> FeedivoDatabase {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            // NORMAL statt GRDBs FULL-Default: bleibt bei einem App-Crash
            // weiterhin sicher; nur ein OS-Crash/Stromausfall könnte im
            // Extremfall die letzte, noch nicht auf Platte geschriebene
            // Transaktion verlieren — ein für einen RSS-Reader akzeptabler
            // Trade-off (auch NetNewsWire geht ihn ein, siehe
            // FMDatabase+Extras.swift). NORMAL ist ausserdem genau die von
            // SQLite selbst empfohlene Einstellung im WAL-Modus (siehe unten).
            try database.execute(sql: "PRAGMA synchronous = NORMAL")
        }

        // DatabasePool statt DatabaseQueue (2026-08-05, Nutzer-Report "Artikel
        // erscheint erst nach ~1s"): eine DatabaseQueue serialisiert AUSNAHMSLOS
        // jeden Lese- UND Schreibzugriff über eine einzige SQLite-Verbindung.
        // Per Live-Log (log stream) verifiziert: markiert der Nutzer einen
        // Artikel beim Auswaehlen als gelesen, reagieren mehrere Views
        // unabhaengig auf denselben SQLiteDataInvalidation.shared.bumpStatusVersion()
        // — u. a. laedt die Artikelliste sich selbst (mit 200ms Debounce) komplett
        // neu, waehrend der Reader zeitgleich nur den einen neu ausgewaehlten
        // Artikel per PK nachladen will. Auf einer DatabaseQueue muss dieser an
        // sich triviale, indexierte Einzelzeilen-Read hinter der viel teureren
        // Listen-Abfrage in der Warteschlange warten, was den gemessenen
        // ~600-900ms-Reader-Delay erklaerte. DatabasePool aktiviert automatisch
        // SQLites WAL-Journal-Modus (siehe GRDB.swift/DatabasePool.swift,
        // setUpWALMode) und erlaubt dadurch mehrere ECHT PARALLELE Lesezugriffe
        // gleichzeitig zu einem laufenden Schreibzugriff (WAL-Snapshot-Isolation)
        // — Schreibzugriffe bleiben weiterhin serialisiert (ein Writer), nur
        // Reads muessen nicht mehr hintereinander warten. `FeedivoDatabase`
        // kapselt bereits `any DatabaseWriter` (dem gemeinsamen GRDB-Protokoll
        // von DatabaseQueue UND DatabasePool) — kein Aufrufer in Stores/Services
        // musste dafuer angepasst werden. `inMemoryForTests()` bleibt bewusst
        // auf DatabaseQueue: DatabasePool benoetigt eine echte Datei, da jede
        // `:memory:`-Verbindung sonst ihre eigene, isolierte Datenbank waere.
        let pool = try DatabasePool(path: fileURL.path, configuration: configuration)
        try FeedivoDatabaseMigrator.migrator.migrate(pool)
        return FeedivoDatabase(writer: pool)
    }

    static func inMemoryForTests() throws -> FeedivoDatabase {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            // NetNewsWire setzt dieselbe Pragma bewusst explizit (siehe
            // FMDatabase+Extras.swift), mit der Begründung, dass eine einzige,
            // serialisierte Verbindung (hier: GRDBs DatabaseQueue) von WAL nicht
            // profitiert, FULL-Synchronität (GRDBs Default) aber unnötig viele
            // fsyncs pro Transaktion erzwingt. NORMAL bleibt bei einem App-Crash
            // weiterhin sicher; nur ein OS-Crash/Stromausfall könnte im
            // Extremfall die letzte, noch nicht auf Platte geschriebene
            // Transaktion verlieren — ein für einen RSS-Reader akzeptabler
            // Trade-off, den NetNewsWire selbst eingeht.
            try database.execute(sql: "PRAGMA synchronous = NORMAL")
        }

        let queue = try DatabaseQueue(configuration: configuration)
        try FeedivoDatabaseMigrator.migrator.migrate(queue)
        return FeedivoDatabase(writer: queue)
    }

    func read<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try writer.read(block)
    }

    /// Führt einen Read auf GRDBs eigener Datenbank-Queue aus. Aufrufer können
    /// dadurch nur die Ergebnisübernahme auf dem Main Actor halten, ohne die
    /// eigentliche SQL-Abfrage dort zu blockieren.
    func readAsync<Value: Sendable>(
        _ block: @escaping @Sendable (Database) throws -> Value
    ) async throws -> Value {
        try await writer.read(block)
    }

    func write<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try writer.write(block)
    }

    func debugTableNames() throws -> Set<String> {
        try read { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table'
                """)
            return Set(rows.compactMap { row in row["name"] as String? })
        }
    }

    func debugIndexNames() throws -> Set<String> {
        try read { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'index'
                """)
            return Set(rows.compactMap { row in row["name"] as String? })
        }
    }

    func debugTriggerNames() throws -> Set<String> {
        try read { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'trigger'
                """)
            return Set(rows.compactMap { row in row["name"] as String? })
        }
    }

    func debugForeignKeys(for tableName: String) throws -> [String] {
        let allowedTableName: String

        switch tableName {
        case "feeds",
             "articles",
             "article_statuses",
             "feed_logs",
             "tags",
             "article_tags",
             "feed_tags",
             "feed_folders",
             "rules",
             "rule_conditions",
             "smart_folders",
             "smart_folder_conditions":
            allowedTableName = tableName
        default:
            throw DebugTableInspectionError.unsupportedTableName(tableName)
        }

        return try read { database in
            let rows = try Row.fetchAll(database, sql: "PRAGMA foreign_key_list(\(allowedTableName))")
            return rows.compactMap { row in row["table"] as String? }
        }
    }
}
