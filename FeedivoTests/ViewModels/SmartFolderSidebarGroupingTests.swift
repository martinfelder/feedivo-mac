import Testing
@testable import Feedivo

struct SmartFolderSidebarGroupingTests {

    private func makeSnapshot(id: String, defaultKey: String?) -> SQLiteSmartFolderSnapshot {
        SQLiteSmartFolderSnapshot(
            id: id,
            name: id,
            matchMode: .all,
            conditions: [],
            defaultKey: defaultKey
        )
    }

    @Test func defaultFoldersEnthaeltNurEintraegeMitDefaultKey() {
        let snapshots = [
            makeSnapshot(id: "all", defaultKey: "all"),
            makeSnapshot(id: "custom1", defaultKey: nil),
            makeSnapshot(id: "unread", defaultKey: "unread"),
            makeSnapshot(id: "custom2", defaultKey: nil)
        ]

        let result = SmartFolderSidebarGrouping.defaultFolders(from: snapshots)

        #expect(result.map(\.id) == ["all", "unread"])
    }

    @Test func customFoldersEnthaeltNurEintraegeOhneDefaultKey() {
        let snapshots = [
            makeSnapshot(id: "all", defaultKey: "all"),
            makeSnapshot(id: "custom1", defaultKey: nil),
            makeSnapshot(id: "unread", defaultKey: "unread"),
            makeSnapshot(id: "custom2", defaultKey: nil)
        ]

        let result = SmartFolderSidebarGrouping.customFolders(from: snapshots)

        #expect(result.map(\.id) == ["custom1", "custom2"])
    }

    @Test func beideGruppenBleibenLeerBeiLeererEingabe() {
        #expect(SmartFolderSidebarGrouping.defaultFolders(from: []).isEmpty)
        #expect(SmartFolderSidebarGrouping.customFolders(from: []).isEmpty)
    }
}
