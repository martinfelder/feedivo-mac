import Foundation
import Testing
@testable import Feedivo

struct SmartFilterTests {

    @MainActor
    @Test func allArticlesFilterZeigtAlleArtikel() {
        let readArticle = Article(title: "Gelesen", isRead: true)
        let unreadArticle = Article(title: "Ungelesen", isRead: false)

        #expect(SmartFilter.allArticles.includes(readArticle))
        #expect(SmartFilter.allArticles.includes(unreadArticle))
    }

    @MainActor
    @Test func unreadFilterZeigtNurUngeleseneArtikel() {
        let readArticle = Article(title: "Gelesen", isRead: true)
        let unreadArticle = Article(title: "Ungelesen", isRead: false)

        #expect(!SmartFilter.unread.includes(readArticle))
        #expect(SmartFilter.unread.includes(unreadArticle))
    }

    @MainActor
    @Test func starredFilterZeigtNurArtikelMitStern() {
        let normalArticle = Article(title: "Normal", isStarred: false)
        let starredArticle = Article(title: "Mit Stern", isStarred: true)

        #expect(!SmartFilter.starred.includes(normalArticle))
        #expect(SmartFilter.starred.includes(starredArticle))
    }

    @MainActor
    @Test func todayFilterNutztKalendertag() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 20,
            hour: 14
        ).date)
        let today = Article(
            title: "Heute",
            publishedAt: now.addingTimeInterval(-2 * 60 * 60)
        )
        let yesterday = Article(
            title: "Gestern",
            publishedAt: now.addingTimeInterval(-24 * 60 * 60)
        )
        let missingDate = Article(title: "Ohne Datum", publishedAt: nil)

        #expect(SmartFilter.today.includes(today, now: now, calendar: calendar))
        #expect(!SmartFilter.today.includes(yesterday, now: now, calendar: calendar))
        #expect(!SmartFilter.today.includes(missingDate, now: now, calendar: calendar))
    }

    @Test func filterIconsHabenPassendeFarben() {
        #expect(SmartFilter.allArticles.iconColor == .blue)
        #expect(SmartFilter.unread.iconColor == .teal)
        #expect(SmartFilter.starred.iconColor == .yellow)
        #expect(SmartFilter.today.iconColor == .green)
    }
}
