import Testing
@testable import Feedivo

struct SQLiteFeedArticleListLoadTokenTests {
    @Test func gleicheParameterErgebenGleichenToken() {
        let first = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:1",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: ""
        )
        let second = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:1",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: ""
        )

        #expect(first == second)
    }

    @Test func unterschiedlicheScopesErgebenUnterschiedlichenToken() {
        let first = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:1",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: ""
        )
        let second = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:2",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: ""
        )

        #expect(first != second)
    }

    @Test func unterschiedlicheSuchtexteErgebenUnterschiedlichenToken() {
        let first = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:1",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: "Swift"
        )
        let second = SQLiteFeedArticleListLoadToken.make(
            scopeToken: "feed:1",
            directTagVersion: 0,
            sqliteStatusVersion: 3,
            debouncedSearchText: ""
        )

        #expect(first != second)
    }
}
