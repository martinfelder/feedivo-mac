import Foundation
import GRDB

struct CleanupRunRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "cleanup_runs"

    var id: String
    var executedAt: Date
    var deletedCount: Int
    var triggerSource: String
    var succeeded: Bool
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        executedAt: Date,
        deletedCount: Int,
        triggerSource: String,
        succeeded: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.executedAt = executedAt
        self.deletedCount = deletedCount
        self.triggerSource = triggerSource
        self.succeeded = succeeded
        self.errorMessage = errorMessage
    }
}
