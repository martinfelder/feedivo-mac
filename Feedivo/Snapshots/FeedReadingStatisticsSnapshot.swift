import Foundation

/// Feed-Statistiken für Feature 14.2 (Integration in `FeedPropertiesView`).
struct FeedReadingStatisticsSnapshot: Equatable, Sendable {
    var averageArticlesPerWeek: Double
    var readPercentage: Double
    var averageReadingMinutes: Double

    static let empty = FeedReadingStatisticsSnapshot(
        averageArticlesPerWeek: 0,
        readPercentage: 0,
        averageReadingMinutes: 0
    )
}
