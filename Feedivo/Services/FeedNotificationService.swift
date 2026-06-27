import Foundation
import UserNotifications

struct FeedRefreshNotificationResult: Equatable, Sendable {
    var feedTitle: String
    var newArticleCount: Int
    var isNotificationEnabled: Bool
}

struct FeedNotificationSummary: Equatable, Sendable {
    var title: String
    var body: String
    var newArticleCount: Int
    var feedTitles: [String]
}

struct RuleNotificationResult: Equatable, Sendable {
    var ruleID: UUID
    var ruleName: String
    var message: String
    var articleTitle: String
    var feedTitle: String
    var priority: RuleNotificationPriority
}

struct RuleNotificationSummary: Equatable, Sendable {
    var title: String
    var body: String
    var priority: RuleNotificationPriority
    var ruleIDs: [UUID]
}

enum FeedNotificationAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case provisional
    case ephemeral
    case unknown

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }
}

enum FeedNotificationService {
    static func summary(from results: [FeedRefreshNotificationResult]) -> FeedNotificationSummary? {
        let activeResults = results.filter {
            $0.isNotificationEnabled && $0.newArticleCount > 0
        }

        guard !activeResults.isEmpty else {
            return nil
        }

        let newArticleCount = activeResults.reduce(0) { partialResult, result in
            partialResult + result.newArticleCount
        }
        let feedTitles = activeResults.map(\.feedTitle)

        return FeedNotificationSummary(
            title: L10n.feedNotificationSummaryTitle(newArticleCount),
            body: feedTitles.joined(separator: ", "),
            newArticleCount: newArticleCount,
            feedTitles: feedTitles
        )
    }

    static func authorizationStatus() async -> FeedNotificationAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return FeedNotificationAuthorizationStatus(settings.authorizationStatus)
    }

    static func ruleSummary(from results: [RuleNotificationResult]) -> RuleNotificationSummary? {
        guard !results.isEmpty else {
            return nil
        }

        if results.count == 1, let result = results.first {
            return RuleNotificationSummary(
                title: result.message,
                body: result.feedTitle,
                priority: result.priority,
                ruleIDs: [result.ruleID]
            )
        }

        let groupedResults = Dictionary(grouping: results, by: \.ruleID)
        let largestGroup = groupedResults.values
            .sorted { firstGroup, secondGroup in
                if firstGroup.count == secondGroup.count {
                    return (firstGroup.first?.ruleName ?? "") < (secondGroup.first?.ruleName ?? "")
                }

                return firstGroup.count > secondGroup.count
            }
            .first ?? results
        let ruleName = largestGroup.first?.ruleName ?? L10n.ruleNotificationFallbackRuleName
        let priority = results.contains { $0.priority == .critical } ? RuleNotificationPriority.critical : .normal

        // Bisher wurde im Body nur die größte Regel-Gruppe gezeigt — Artikel
        // kleinerer Gruppen fielen komplett unter den Tisch. Stattdessen alle
        // gemeldeten Artikel (Gruppen absteigend nach Größe) auflisten, damit
        // keine Notification-Inhalte verloren gehen.
        let sortedGroups = groupedResults.values.sorted { firstGroup, secondGroup in
            if firstGroup.count == secondGroup.count {
                return (firstGroup.first?.ruleName ?? "") < (secondGroup.first?.ruleName ?? "")
            }

            return firstGroup.count > secondGroup.count
        }
        let body = sortedGroups.flatMap { $0.map(\.articleTitle) }
            .joined(separator: ", ")

        return RuleNotificationSummary(
            title: L10n.ruleNotificationSummaryTitle(count: largestGroup.count, ruleName: ruleName),
            body: body,
            priority: priority,
            ruleIDs: Array(Set(results.map(\.ruleID)))
        )
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
        } catch {
            return false
        }
    }

    static func presentRefreshSummary(for results: [FeedRefreshNotificationResult]) async {
        guard let summary = summary(from: results) else {
            return
        }

        await present(
            title: summary.title,
            body: summary.body,
            userInfo: [
                "feedivoNotificationType": "feedRefresh",
                "feedTitles": summary.feedTitles
            ],
            identifierPrefix: "feed-refresh",
            isCritical: false
        )
    }

    static func presentRuleSummary(for results: [RuleNotificationResult]) async {
        guard let summary = ruleSummary(from: results) else {
            return
        }

        await present(
            title: summary.title,
            body: summary.body,
            userInfo: [
                "feedivoNotificationType": "rule",
                "ruleIDs": summary.ruleIDs.map(\.uuidString)
            ],
            identifierPrefix: "rule",
            isCritical: summary.priority == .critical
        )
    }

    /// Gemeinsame Delivery-Pipeline für Feed-Refresh- und Regel-Notifications.
    /// Zuvor stand die Identische Authorisierungs-+Zustell-Logik doppelt in
    /// `presentRefreshSummary` und `presentRuleSummary`.
    private static func present(
        title: String,
        body: String,
        userInfo: [String: Any],
        identifierPrefix: String,
        isCritical: Bool
    ) async {
        guard await isAuthorized() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        if isCritical {
            content.interruptionLevel = .timeSensitive
        }

        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        // Zustellfehler bewusst als try? — eine fehlschlagende Notification soll
        // nicht den Refresh-Flow abbrechen; der User merkt ohnehin nur die
        // ausbleibende Benachrichtigung.
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Löst die Authorisierung auf und fragt ggf. nach, falls noch nicht
    /// entschieden. Wurde zuvor in beiden present-Methoden identisch geführt.
    private static func isAuthorized() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied, .unknown:
            return false
        }
    }
}
