import Foundation
import Testing
@testable import Feedivo

struct FeedivoURLSchemeParserTests {
    @Test func addMitGueltigerURLLiefertAddFeedAction() {
        let url = URL(string: "feedivo://add?url=https://example.com/feed.xml")!

        #expect(
            FeedivoURLSchemeParser.action(for: url) ==
            .addFeed(urlString: "https://example.com/feed.xml")
        )
    }

    @Test func addOhneURLQueryItemLiefertNil() {
        let url = URL(string: "feedivo://add")!

        #expect(FeedivoURLSchemeParser.action(for: url) == nil)
    }

    @Test func addMitLeererURLLiefertNil() {
        let url = URL(string: "feedivo://add?url=")!

        #expect(FeedivoURLSchemeParser.action(for: url) == nil)
    }

    @Test func articleMitGueltigerUUIDLiefertOpenArticleAction() {
        let uuid = UUID()
        let url = URL(string: "feedivo://article?id=\(uuid.uuidString)")!

        #expect(FeedivoURLSchemeParser.action(for: url) == .openArticle(articleID: uuid))
    }

    @Test func articleMitUngueltigerUUIDLiefertNil() {
        let url = URL(string: "feedivo://article?id=not-a-uuid")!

        #expect(FeedivoURLSchemeParser.action(for: url) == nil)
    }

    @Test func unbekannterHostLiefertNil() {
        let url = URL(string: "feedivo://unknown?foo=bar")!

        #expect(FeedivoURLSchemeParser.action(for: url) == nil)
    }

    @Test func falschesSchemaLiefertNil() {
        let url = URL(string: "https://add?url=https://example.com/feed.xml")!

        #expect(FeedivoURLSchemeParser.action(for: url) == nil)
    }
}
