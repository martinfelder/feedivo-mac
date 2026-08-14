import Foundation
import GRDB

struct MCPServerSettingsStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func isEnabled() throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(db, sql: "SELECT isEnabled FROM mcp_server_settings WHERE id = 1") ?? false
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE mcp_server_settings SET isEnabled = ? WHERE id = 1", arguments: [isEnabled])
        }
    }
}
