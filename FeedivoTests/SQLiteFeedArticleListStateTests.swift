import Foundation
import GRDB
import Testing
@testable import Feedivo

@MainActor
struct SQLiteFeedArticleListStateTests {
    @Test func listStateLaedtFeedScopePerFeedID() async throws {
        let (database, firstID, secondID) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()

        state.load(
            feedID: "feed-1",
            database: database,
            selectedArticleID: secondID
        )
        await waitForLoad(state)

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [secondID, firstID])
        #expect(state.navigationState.previousArticleID == nil)
        #expect(state.navigationState.nextArticleID == firstID)
    }

    @Test func listStateLaedtWeitereTimelineSeitenNach() async {
        var requestedOffsets: [Int] = []
        let first = snapshot(id: "first")
        let second = snapshot(id: "second")
        let state = SQLiteFeedArticleListState { request in
            requestedOffsets.append(request.offset)
            let rows = request.offset == 0 ? [first] : [second]
            return SQLiteTimelineLoadResult(
                loadState: .loaded,
                rows: rows,
                navigationState: SQLiteArticleNavigationState(
                    articleIDs: rows.map(\.id),
                    selectedArticleID: request.selectedArticleID
                ),
                hasMore: request.offset == 0,
                totalUnreadCount: 2
            )
        }

        state.load(feedID: "feed-1", database: nil, selectedArticleID: "first")
        await waitForRows(state) { $0.map(\.id) == ["first"] }
        #expect(state.hasMore)
        #expect(state.totalUnreadCount == 2)

        state.loadMore()
        await waitForRows(state) { $0.map(\.id) == ["first", "second"] }

        #expect(requestedOffsets == [0, 1])
        #expect(!state.hasMore)
        #expect(state.navigationState.nextArticleID == "second")
    }

    @Test func listStateToggeltReadUndAktualisiertRows() async throws {
        let (database, firstID, _) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()

        state.load(
            feedID: "feed-1",
            database: database,
            selectedArticleID: firstID
        )
        await waitForLoad(state)
        state.toggleRead(articleID: firstID, database: database)
        await waitForRows(state) { rows in
            rows.first(where: { $0.id == firstID })?.isRead == true
        }

        #expect(state.rows.first(where: { $0.id == firstID })?.isRead == true)
        #expect(state.totalUnreadCount == 1)
    }

    @Test func listStateLoeschtArtikelUndEntferntIhnAusRows() async throws {
        let (database, firstID, secondID) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()

        state.load(
            feedID: "feed-1",
            database: database,
            selectedArticleID: firstID
        )
        await waitForLoad(state)

        let succeeded = state.deleteArticle(articleID: firstID, database: database)

        #expect(succeeded)
        #expect(state.rows.map(\.id) == [secondID])
        #expect(state.loadState == .loaded)
    }

    @Test func listStateDeindexiertGeloeschtenArtikelAusSpotlight() async throws {
        let (database, firstID, _) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()
        var deindexedIDs: [String] = []

        state.load(feedID: "feed-1", database: database, selectedArticleID: firstID)
        await waitForLoad(state)

        let succeeded = state.deleteArticle(
            articleID: firstID,
            database: database,
            deindexForSpotlight: { deindexedIDs.append(contentsOf: $0) }
        )

        #expect(succeeded)
        #expect(deindexedIDs == [firstID])
    }

    @Test func listStateSetztFailedStateWennLoeschenFehlschlaegt() async throws {
        let (database, firstID, secondID) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()

        state.load(
            feedID: "feed-1",
            database: database,
            selectedArticleID: firstID
        )
        await waitForLoad(state)
        try database.write { db in
            try db.execute(sql: "DROP TABLE articles")
        }

        let succeeded = state.deleteArticle(articleID: firstID, database: database)

        #expect(!succeeded)
        // "rows bleibt unveraendert" heisst: der vor dem fehlgeschlagenen
        // Loeschen geladene Zustand (beide Artikel, neuester zuerst) bleibt
        // exakt erhalten - nicht nur der Artikel, dessen Loeschung fehlschlug.
        #expect(state.rows.map(\.id) == [secondID, firstID])
        guard case .failed = state.loadState else {
            Issue.record("Erwartete .failed nach fehlgeschlagenem Loeschen, war \(state.loadState)")
            return
        }
    }

    @Test func listStateBehaeltArtikelInUngelesenSmartFolderNachToggleReadSichtbar() async throws {
        let (database, firstID, secondID) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()
        let folder = SQLiteSmartFolderSnapshot(
            id: "smart-unread",
            name: "Ungelesen",
            matchMode: .all,
            conditions: [
                SQLiteSmartFolderConditionSnapshot(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.unread.rawValue
                )
            ]
        )

        state.load(smartFolder: folder, database: database, selectedArticleID: firstID)
        await waitForLoad(state)
        #expect(Set(state.rows.map(\.id)) == Set([firstID, secondID]))

        state.toggleRead(articleID: firstID, database: database)
        await waitForRows(state) { rows in
            rows.first(where: { $0.id == firstID })?.isRead == true
        }

        #expect(Set(state.rows.map(\.id)) == Set([firstID, secondID]))
        #expect(state.rows.first(where: { $0.id == firstID })?.isRead == true)
    }

    // Reproduziert den Nutzer-Report (2026-07-14): "Wenn im Smart Folder
    // Ungelesen der letzte Artikel gelesen wurde, wird die Artikelliste
    // vollstaendig geleert." Bildet die reale Sequenz nach: einziger
    // verbleibender ungelesener Artikel wird per Auswahl gelesen markiert
    // (markReadIfNeeded, wie beim Oeffnen im Reader), danach loest ein
    // erneutes state.load() - wie es der sqliteStatusVersion-Bump in der
    // View ueber .task(id: loadToken) ausloest - eine frische SQL-Abfrage
    // aus, die den jetzt gelesenen Artikel per Bedingung "Status ist
    // ungelesen" korrekt ausschliesst.
    @Test func listStateFuerLetztenArtikelInUngelesenSmartFolderNachAuswahlUndReload() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "SQLite Feed"))
        let onlyID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "only", title: "Einziger Artikel")
        )

        let state = SQLiteFeedArticleListState()
        let folder = SQLiteSmartFolderSnapshot(
            id: "smart-unread",
            name: "Ungelesen",
            matchMode: .all,
            conditions: [
                SQLiteSmartFolderConditionSnapshot(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.unread.rawValue
                )
            ]
        )

        state.load(smartFolder: folder, database: database, selectedArticleID: onlyID)
        await waitForLoad(state)
        #expect(state.rows.map(\.id) == [onlyID])

        let didMarkRead = state.markReadIfNeeded(articleID: onlyID, database: database, isEnabled: true)
        await waitForRows(state) { rows in
            rows.first(where: { $0.id == onlyID })?.isRead == true
        }
        #expect(didMarkRead)

        // Simuliert den View-seitigen Sticky-Snapshot, der unmittelbar nach
        // dem Markieren aus state.rows entnommen wird (siehe
        // SQLiteFeedArticleListView.markSelectedArticleReadIfNeeded).
        let stickySnapshot = try #require(state.rows.first(where: { $0.id == onlyID }))
        #expect(stickySnapshot.isRead == true)

        // Erneuter Scope-Load simuliert den Reload, den der
        // sqliteStatusVersion-Bump in der View ausloest.
        state.load(smartFolder: folder, database: database, selectedArticleID: onlyID)
        await waitForLoad(state)
        #expect(state.rows.isEmpty)

        let merged = SQLiteArticleListDisplayState.mergingStickyRows(
            into: state.rows,
            stickyRowSnapshots: [onlyID: stickySnapshot]
        )
        let displayState = SQLiteArticleListDisplayState(
            rows: merged,
            showsReadArticles: false,
            selectedArticleID: onlyID,
            temporarilyVisibleReadArticleIDs: [onlyID],
            filterOption: .all
        )

        #expect(!displayState.filteredRows.isEmpty)
        #expect(displayState.visibleRows.map(\.id) == [onlyID])
    }

    @Test func listStateMarkiertAusgewaehltenArtikelBeimOeffnenAlsGelesen() async throws {
        let (database, firstID, _) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()

        state.load(
            feedID: "feed-1",
            database: database,
            selectedArticleID: firstID
        )
        await waitForLoad(state)

        let didMarkRead = state.markReadIfNeeded(
            articleID: firstID,
            database: database,
            isEnabled: true
        )
        await waitForRows(state) { rows in
            rows.first(where: { $0.id == firstID })?.isRead == true
        }

        let status = try ArticleStatusStore(database: database).status(articleID: firstID)
        #expect(didMarkRead)
        #expect(status?.isRead == true)
        #expect(state.rows.first(where: { $0.id == firstID })?.isRead == true)
    }

    @Test func listStateLaedtTagScopeAusSQLite() async throws {
        let (database, firstID, secondID) = try makeDatabaseWithFeedAndArticles()
        let tagStore = TagStore(database: database)
        let state = SQLiteFeedArticleListState()
        try tagStore.save(TagRecord(id: "tag-swift", name: "Swift", colorHex: "#ff0000"))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: firstID, at: Date(timeIntervalSince1970: 100))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: secondID, at: Date(timeIntervalSince1970: 200))

        state.load(
            tagID: "tag-swift",
            database: database,
            selectedArticleID: secondID
        )
        await waitForLoad(state)

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [secondID, firstID])
        #expect(state.navigationState.nextArticleID == firstID)
    }

    @Test func listStateLaedtSmartFilterScopeAusSQLite() async throws {
        let (database, firstID, secondID) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()
        try ArticleStatusStore(database: database).setRead(true, articleID: firstID, at: Date())

        state.load(
            smartFilter: .unread,
            database: database,
            selectedArticleID: secondID
        )
        await waitForLoad(state)

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [secondID])
        #expect(state.navigationState.previousArticleID == nil)
        #expect(state.navigationState.nextArticleID == nil)
    }

    @Test func listStateFiltertFeedScopeMitSQLiteFTS() async throws {
        let (database, _, secondID) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()

        state.load(
            feedID: "feed-1",
            searchText: "Second",
            database: database,
            selectedArticleID: secondID
        )
        await waitForLoad(state)

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [secondID])
        #expect(state.navigationState.previousArticleID == nil)
        #expect(state.navigationState.nextArticleID == nil)
    }

    @Test func listStateLaedtHiddenSmartFilterMitAusgeblendetenArtikeln() async throws {
        let (database, firstID, _) = try makeDatabaseWithFeedAndArticles()
        let state = SQLiteFeedArticleListState()
        try ArticleStatusStore(database: database).setHidden(true, articleID: firstID, at: Date())

        state.load(
            smartFilter: .hidden,
            database: database,
            selectedArticleID: firstID
        )
        await waitForLoad(state)

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [firstID])
    }

    @Test func listStateMeldetFehlendenSQLiteFeed() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let state = SQLiteFeedArticleListState()

        state.load(
            feedID: "missing-feed",
            database: database,
            selectedArticleID: nil
        )
        await waitForLoad(state)

        #expect(state.loadState == .missingFeed)
        #expect(state.rows.isEmpty)
    }

    @Test func listStateLaedtBeiDoppelterURLNurArtikelDerFeedID() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Erster Feed"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://example.com/feed.xml", title: "Zweiter Feed"))
        let firstFeedArticleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "first-feed",
                title: "Artikel vom ersten Feed",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let secondFeedArticleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-2",
                sourceID: "second-feed",
                title: "Artikel vom zweiten Feed",
                publishedAt: Date(timeIntervalSince1970: 200),
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )
        let state = SQLiteFeedArticleListState()

        state.load(
            feedID: "feed-2",
            database: database,
            selectedArticleID: secondFeedArticleID
        )
        await waitForLoad(state)

        #expect(state.loadState == .loaded)
        #expect(state.rows.map(\.id) == [secondFeedArticleID])
        #expect(!state.rows.map(\.id).contains(firstFeedArticleID))
    }

    @Test func listStateVerwirftSpaetesErgebnisVonAltemFeedLoad() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        var continuations: [CheckedContinuation<SQLiteTimelineLoadResult, Error>] = []
        var requests: [SQLiteTimelineLoadRequest] = []
        let state = SQLiteFeedArticleListState { request in
            requests.append(request)
            return try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }

        state.load(feedID: "feed-alt", database: database, selectedArticleID: nil)
        await waitForRequestCount(1, continuations: { continuations.count })
        state.load(feedID: "feed-neu", database: database, selectedArticleID: nil)

        continuations[0].resume(returning: loadedResult(rows: [snapshot(id: "alt", feedID: "feed-alt")]))
        await waitForRequestCount(2, continuations: { continuations.count })

        continuations[1].resume(returning: loadedResult(rows: [snapshot(id: "neu", feedID: "feed-neu")]))
        await waitForRows(state) { $0.map(\.id) == ["neu"] }
        await spinMainActor()

        #expect(requests.map(\.scope) == [.feedID("feed-alt"), .feedID("feed-neu")])
        #expect(state.rows.map(\.id) == ["neu"])
    }

    @Test func timelineQueueFuehrtNurNeuestenPendingLoadNachAktuellemAus() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        var continuations: [CheckedContinuation<SQLiteTimelineLoadResult, Error>] = []
        var requests: [SQLiteTimelineLoadRequest] = []
        let state = SQLiteFeedArticleListState { request in
            requests.append(request)
            return try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }

        state.load(feedID: "feed-alt", database: database, selectedArticleID: nil)
        await waitForRequestCount(1, continuations: { continuations.count })
        state.load(feedID: "feed-mitte", database: database, selectedArticleID: nil)
        await spinMainActor()

        #expect(requests.map(\.scope) == [.feedID("feed-alt")])

        state.load(feedID: "feed-neu", database: database, selectedArticleID: nil)
        await spinMainActor()

        #expect(requests.map(\.scope) == [.feedID("feed-alt")])

        continuations[0].resume(returning: loadedResult(rows: [snapshot(id: "alt", feedID: "feed-alt")]))
        await waitForRequestCount(2, continuations: { continuations.count })

        #expect(requests.map(\.scope) == [.feedID("feed-alt"), .feedID("feed-neu")])

        continuations[1].resume(returning: loadedResult(rows: [snapshot(id: "neu", feedID: "feed-neu")]))
        await waitForRows(state) { $0.map(\.id) == ["neu"] }

        #expect(state.rows.map(\.id) == ["neu"])
    }

    @Test func listStateVerwirftSpaetesErgebnisVonAlterSuche() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        var continuations: [CheckedContinuation<SQLiteTimelineLoadResult, Error>] = []
        var requests: [SQLiteTimelineLoadRequest] = []
        let state = SQLiteFeedArticleListState { request in
            requests.append(request)
            return try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }

        state.load(feedID: "feed-1", searchText: "alt", database: database, selectedArticleID: nil)
        await waitForRequestCount(1, continuations: { continuations.count })
        state.load(feedID: "feed-1", searchText: "neu", database: database, selectedArticleID: nil)

        continuations[0].resume(returning: loadedResult(rows: [snapshot(id: "suche-alt")]))
        await waitForRequestCount(2, continuations: { continuations.count })

        continuations[1].resume(returning: loadedResult(rows: [snapshot(id: "suche-neu")]))
        await waitForRows(state) { $0.map(\.id) == ["suche-neu"] }
        await spinMainActor()

        #expect(requests.map(\.searchText) == ["alt", "neu"])
        #expect(state.rows.map(\.id) == ["suche-neu"])
    }

    @Test func abgebrochenerTimelineLoadVeraendertRowsNicht() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        var continuations: [CheckedContinuation<SQLiteTimelineLoadResult, Error>] = []
        let state = SQLiteFeedArticleListState { request in
            return try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }
        state.rows = [snapshot(id: "bestehend")]
        state.loadState = .loaded

        state.load(feedID: "feed-alt", database: database, selectedArticleID: nil)
        await waitForRequestCount(1, continuations: { continuations.count })
        state.load(feedID: "feed-neu", database: database, selectedArticleID: nil)

        continuations[0].resume(returning: loadedResult(rows: [snapshot(id: "alt")]))
        await spinMainActor()
        #expect(state.rows.map(\.id) == ["bestehend"])

        await waitForRequestCount(2, continuations: { continuations.count })
        continuations[1].resume(returning: loadedResult(rows: [snapshot(id: "neu")]))
        await waitForRows(state) { $0.map(\.id) == ["neu"] }
        #expect(state.rows.map(\.id) == ["neu"])
    }

    private func makeDatabaseWithFeedAndArticles() throws -> (FeedivoDatabase, String, String) {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "SQLite Feed"))
        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "first",
                title: "First",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "second",
                title: "Second",
                publishedAt: Date(timeIntervalSince1970: 200),
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )

        return (database, firstID, secondID)
    }

    private func snapshot(
        id: String,
        feedID: String = "feed-1",
        isRead: Bool = false
    ) -> ArticleListSnapshot {
        ArticleListSnapshot(
            id: id,
            feedID: feedID,
            feedTitle: "Feed",
            title: id,
            summary: nil,
            link: nil,
            imageURL: nil,
            publishedAt: nil,
            arrivedAt: Date(timeIntervalSince1970: 100),
            estimatedReadingMinutes: nil,
            isRead: isRead,
            isStarred: false,
            isArchived: false,
            isHidden: false
        )
    }

    private func loadedResult(rows: [ArticleListSnapshot]) -> SQLiteTimelineLoadResult {
        SQLiteTimelineLoadResult(
            loadState: .loaded,
            rows: rows,
            navigationState: SQLiteArticleNavigationState(
                articleIDs: rows.map(\.id),
                selectedArticleID: rows.first?.id
            )
        )
    }

    private func waitForLoad(_ state: SQLiteFeedArticleListState) async {
        for _ in 0..<50 {
            if state.loadState != .idle {
                return
            }
            await Task.yield()
        }
        Issue.record("SQLiteFeedArticleListState hat den Load nicht abgeschlossen.")
    }

    private func waitForRows(
        _ state: SQLiteFeedArticleListState,
        matching predicate: ([ArticleListSnapshot]) -> Bool
    ) async {
        for _ in 0..<50 {
            if predicate(state.rows) {
                return
            }
            await Task.yield()
        }
        Issue.record("SQLiteFeedArticleListState hat nicht die erwarteten Rows geladen.")
    }

    private func waitForRequestCount(
        _ expectedCount: Int,
        continuations: () -> Int
    ) async {
        for _ in 0..<50 {
            if continuations() >= expectedCount {
                return
            }
            await Task.yield()
        }
        Issue.record("Der Timeline-Test-Loader wurde nicht oft genug aufgerufen.")
    }

    private func spinMainActor() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}
