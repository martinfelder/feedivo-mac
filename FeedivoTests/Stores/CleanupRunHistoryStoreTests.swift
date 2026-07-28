import Foundation
import GRDB
import Testing
@testable import Feedivo

struct CleanupRunHistoryStoreTests {
    @Test func recordSpeichertEinenErfolgreichenLauf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CleanupRunHistoryStore(database: database)
        let now = Date(timeIntervalSince1970: 10_000_000)

        try store.record(triggerSource: .manual, deletedCount: 5, succeeded: true, errorMessage: nil, now: now)

        let runs = try store.recentRuns()
        #expect(runs.count == 1)
        #expect(runs[0].deletedCount == 5)
        #expect(runs[0].triggerSource == CleanupRunTrigger.manual.rawValue)
        #expect(runs[0].succeeded == true)
        #expect(runs[0].errorMessage == nil)
    }

    @Test func recordSpeichertFehlgeschlagenenLaufMitMeldung() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CleanupRunHistoryStore(database: database)
        let now = Date(timeIntervalSince1970: 10_000_000)

        try store.record(triggerSource: .schedule, deletedCount: 0, succeeded: false, errorMessage: "DB-Fehler", now: now)

        let runs = try store.recentRuns()
        #expect(runs.count == 1)
        #expect(runs[0].succeeded == false)
        #expect(runs[0].errorMessage == "DB-Fehler")
    }

    @Test func recordTrimmtAufDieNeuesten10Laeufe() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CleanupRunHistoryStore(database: database)
        let baseDate = Date(timeIntervalSince1970: 10_000_000)

        for index in 0..<15 {
            try store.record(
                triggerSource: .appStart,
                deletedCount: index,
                succeeded: true,
                errorMessage: nil,
                now: baseDate.addingTimeInterval(TimeInterval(index * 60))
            )
        }

        let runs = try store.recentRuns()
        #expect(runs.count == 10)
        #expect(runs.first?.deletedCount == 14)
        #expect(runs.last?.deletedCount == 5)
    }

    @Test func recentRunsLiefertAbsteigendSortiert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CleanupRunHistoryStore(database: database)
        let baseDate = Date(timeIntervalSince1970: 10_000_000)

        try store.record(triggerSource: .manual, deletedCount: 1, succeeded: true, errorMessage: nil, now: baseDate)
        try store.record(
            triggerSource: .manual, deletedCount: 2, succeeded: true, errorMessage: nil,
            now: baseDate.addingTimeInterval(60)
        )

        let runs = try store.recentRuns()
        #expect(runs.map(\.deletedCount) == [2, 1])
    }
}
