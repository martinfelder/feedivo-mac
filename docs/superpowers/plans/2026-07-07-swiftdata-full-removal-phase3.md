# SwiftData vollständig entfernen — Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alle verbleibenden SwiftData-Abhängigkeiten aus FeedivoMac entfernen — tote `@Model`-Verwendungen in 17 Produktionsdateien, tote/migrationsbedürftige Tests in ~13 Testdateien, und am Ende die 9 `@Model`-Klassen selbst.

**Architecture:** Wie Phase 1/2 — pro Datei(-paar) ein Task, in Abhängigkeitsreihenfolge. Komplett tote Dateien werden gelöscht (Phase-1-Muster). Dateien mit gemischtem toten/aktiven Code werden methodengenau bereinigt (Phase-2-Muster). Die 9 `@Model`-Dateien werden erst im letzten Task gelöscht, wenn alle Konsumenten bereinigt sind.

**Tech Stack:** Swift, SwiftUI (macOS 14+), GRDB/SQLite (Produktivpfad), Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Kein neuer Testcode nötig — reine Lösch-/Migrations-Operation.
- Build bleibt grün; bestehende, **gescopte** Tests bleiben grün (NICHT die volle ungefilterte
  Suite via `xcodebuild test` ohne `-only-testing:` — die hängt nachweislich, ein bekanntes,
  unabhängiges Infrastrukturproblem dieses Projekts).
- Bekannte, vorbestehende Fehlschläge außerhalb des Scopes: 5 Tests in
  `FeedivoAppSceneConfigurationTests.swift` (`contentViewNutztSQLiteReaderFuerSQLiteAuswahl`,
  `settingsFensterBleibtAufGlobalePreferencesReduziert`,
  `sidebarAktionenStehenOberhalbDerIntelligentenOrdner`,
  `sidebarSmartFolderBadgesNutzenSQLiteSnapshots`, `sqliteReaderBleibtOptischNahAnMainReaderToolbar`)
  und 3 Tests in `SQLiteReaderStateTests.swift` (`readerStateLaedtSnapshotUndPreparedArticle`,
  `readerStateToggeltStarredUndLaedtSnapshotNeu`, `readerStateToggeltReadUndLaedtSnapshotNeu`) —
  beide unabhängig verifiziert, nicht durch diese Phase verursacht, nicht anfassen.
  `refreshAllFeedsMitSQLiteDatabaseNutztSQLiteFirstOhneDoppeltenAbruf` und
  `refreshAllFeedsMitSQLiteDatabaseMeldetFeedBenachrichtigungen` in `FeedViewModelTests.swift` sind
  nur unter Volllast flakey (vorbestehend, Phase 1 verifiziert).
- **VERBINDLICHE Reihenfolge:** Task 24 (die 9 `@Model`-Dateien löschen) MUSS der letzte Task sein
  — jeder andere Task muss zuerst abgeschlossen sein, weil erst dann keine Produktions- oder
  Testdatei mehr auf `Article`/`Feed`/`FeedFolder`/`FeedLogEntry`/`Rule`/`RuleCondition`/
  `SmartFolder`/`SmartFolderCondition`/`Tag` verweist.
- Jeder Implementierer verifiziert vor dem Löschen erneut per `grep` (nicht nur Dateiname-Treffer,
  echte Aufrufe), genau wie in Phase 1/2 etabliert.
- Fixture-Migration nutzt durchgängig bereits existierende SQLite-native Typen (keine neuen
  Test-only-Typen).
- **Bekannte Ausnahme vom "Build bleibt nach jedem Task grün"-Prinzip:** `FeedivoTests/ArticleListQueryTests.swift`
  enthält (neben den in Phase 2 bereits bereinigten Tests) noch je einen Test für
  `ArticleFilterOption`/`ArticleSortOption`, deren zugrundeliegende `Article`-typisierte Methoden in
  Task 6 bzw. Task 8 entfernt werden. Task 22 bereinigt diese Datei final. Falls beim Ausführen von
  Task 6, 7 oder 8 der volle Projekt-Build wegen `ArticleListQueryTests.swift` fehlschlägt, ist das
  für diesen einen Zeitraum erwartet — der jeweilige Task committet trotzdem (siehe Hinweis in Task
  6), und der `-only-testing:`-Testlauf jedes Tasks scopet ohnehin nur auf die eigene Zieldatei, sodass
  dieser bekannte, vorübergehende Fremdfehler die eigene Verifikation nicht verfälscht. Ab Task 22
  ist der Build wieder durchgehend grün.

---

## Task 1: `SmartFolderEngine.swift` + `SmartFolderEngineTests.swift` löschen

**Files:**
- Delete: `Feedivo/Services/SmartFolderEngine.swift`
- Delete: `FeedivoTests/SmartFolderEngineTests.swift`

**Interfaces:** Keine Abhängigkeiten von/zu anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "SmartFolderEngine\." Feedivo FeedivoTests`

Erwartung: Treffer nur in `Feedivo/Services/SmartFolderEngine.swift` (Definition) und
`FeedivoTests/SmartFolderEngineTests.swift` (Tests). Falls ein Treffer in einer anderen
Produktionsdatei auftaucht: STOPPEN, BLOCKED melden.

- [ ] **Step 2: Beide Dateien löschen**

```bash
rm Feedivo/Services/SmartFolderEngine.swift
rm FeedivoTests/SmartFolderEngineTests.swift
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Services/SmartFolderEngine.swift FeedivoTests/SmartFolderEngineTests.swift
git commit -m "Remove dead SmartFolderEngine.swift (0 production callers)"
```

---

## Task 2: `SmartFilter.swift` + `SmartFilterTests.swift` bereinigen

**KORRIGIERT nach BLOCKED-Meldung des ersten Implementierungsversuchs:** Der ursprüngliche Plan
stufte diese Datei fälschlich als komplett tot ein. Tatsächlich ist NUR die Methode
`includes(_ article: Article, now:calendar:)` tot — das Enum `SmartFilter` selbst (Cases,
`.title`, `.systemImage`, `.iconColor`, `.id`) ist ein lebendiger Navigations-/Auswahltyp, genutzt
in `SQLiteFeedArticleListState.swift`, `Stores/TimelineStore.swift`, `Views/ContentView.swift`,
`Views/Sidebar/SidebarSelection.swift`, `Views/ArticleList/SQLiteFeedArticleListView.swift`. Dieser
Task ist daher eine methodengenaue Bereinigung (Phase-2-Muster), keine Datei-Löschung
(Phase-1-Muster).

**Files:**
- Modify: `Feedivo/Views/Sidebar/SmartFilter.swift`
- Modify: `FeedivoTests/SmartFilterTests.swift`

**Interfaces:**
- Produces: `SmartFilter` (enum mit Cases `.allArticles`/`.unread`/`.starred`/`.today`/`.hidden`,
  `.id`, `.title`, `.systemImage`, `.iconColor`), `SmartFilterIconColor` bleiben unverändert
  (genutzt von `SQLiteFeedArticleListState.swift`, `TimelineStore.swift`, `ContentView.swift`,
  `SidebarSelection.swift`, `SQLiteFeedArticleListView.swift`).
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "\.includes(" Feedivo FeedivoTests | grep -v "ArticleFilterOption.swift\|ArticleMarkReadOption.swift"`

Erwartung: `SmartFilter.includes(_:Article...)` hat 0 Aufrufer außer den 5 Tests in
`FeedivoTests/SmartFilterTests.swift`, die exakt diese Methode testen.

- [ ] **Step 2: Tote `Article`-Methode entfernen**

Ersetze den kompletten Inhalt von `Feedivo/Views/Sidebar/SmartFilter.swift`:

```swift
import Foundation
import SwiftUI

enum SmartFilterIconColor: Hashable {
    case blue
    case teal
    case yellow
    case green
    case gray

    var color: Color {
        switch self {
        case .blue:
            return .blue
        case .teal:
            return .teal
        case .yellow:
            return .yellow
        case .green:
            return .green
        case .gray:
            return .gray
        }
    }
}

enum SmartFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allArticles
    case unread
    case starred
    case today
    case hidden

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .allArticles:
            return L10n.smartFilterAllArticles
        case .unread:
            return L10n.smartFilterUnread
        case .starred:
            return L10n.smartFilterStarred
        case .today:
            return L10n.smartFilterToday
        case .hidden:
            return L10n.smartFilterHidden
        }
    }

    var systemImage: String {
        switch self {
        case .allArticles:
            return "tray.full"
        case .unread:
            return "circle.fill"
        case .starred:
            return "star.fill"
        case .today:
            return "calendar"
        case .hidden:
            return "eye.slash"
        }
    }

    var iconColor: SmartFilterIconColor {
        switch self {
        case .allArticles:
            return .blue
        case .unread:
            return .teal
        case .starred:
            return .yellow
        case .today:
            return .green
        case .hidden:
            return .gray
        }
    }
}
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt fehl (Tests referenzieren noch die entfernte `includes(_:)`-Methode) —
nächster Schritt behebt das.

- [ ] **Step 4: `SmartFilterTests.swift` bereinigen**

Lies die Datei komplett (76 Zeilen, 6 Tests). Entferne die 5 Tests, die `.includes(` aufrufen:
`allArticlesFilterZeigtAlleArtikel`, `unreadFilterZeigtNurUngeleseneArtikel`,
`starredFilterZeigtNurArtikelMitStern`, `todayFilterNutztKalendertag`,
`hiddenFilterZeigtNurAusgeblendeteArtikel`. Behalte den Test `filterIconsHabenPassendeFarben` (testet
`.iconColor`, kein `Article`-Bezug).

- [ ] **Step 5: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SmartFilterTests 2>&1 | tail -60`
Erwartung: der verbleibende Test grün.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Sidebar/SmartFilter.swift FeedivoTests/SmartFilterTests.swift
git commit -m "Remove dead Article-typed includes(_:) method from SmartFilter"
```

---

## Task 3: `OfflineDownloadService.swift` + `OfflineDownloadServiceTests.swift` löschen

**Files:**
- Delete: `Feedivo/Services/OfflineDownloadService.swift`
- Delete: `FeedivoTests/OfflineDownloadServiceTests.swift`

**Interfaces:** Keine Abhängigkeiten von/zu anderen Tasks. `SQLiteOfflineDownloadService` (in
`Feedivo/Stores/SQLiteOfflineStore.swift`) ist der lebendige Ersatz und bleibt unverändert.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "OfflineDownloadService(\|\.saveForOffline(\|\.archiveForOffline(\|\.removeArchive(\|\.removeOfflineContent(\|OfflineArticleStorage\." Feedivo FeedivoTests`

Erwartung: `OfflineDownloadService(` nur innerhalb der eigenen Datei; `.saveForOffline(` etc. haben
0 Aufrufer außerhalb dieser Datei und ihrer Testdatei; `OfflineArticleStorageSummary`/
`OfflineArticleStorage` wird auch von `SQLiteOfflineStore.swift` referenziert (das bleibt
unverändert, nicht Teil der Löschung). Falls ein Produktions-Aufrufer von `saveForOffline`/
`archiveForOffline`/`removeArchive`/`removeOfflineContent` außerhalb dieser Datei auftaucht:
STOPPEN, BLOCKED melden.

- [ ] **Step 2: Beide Dateien löschen**

```bash
rm Feedivo/Services/OfflineDownloadService.swift
rm FeedivoTests/OfflineDownloadServiceTests.swift
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Services/OfflineDownloadService.swift FeedivoTests/OfflineDownloadServiceTests.swift
git commit -m "Remove dead OfflineDownloadService.swift (superseded by SQLiteOfflineDownloadService)"
```

---

## Task 4: `RuleEngine.swift` + `RuleEngineTests.swift` bereinigen

**Files:**
- Modify: `Feedivo/Services/RuleEngine.swift`
- Modify: `FeedivoTests/RuleEngineTests.swift`

**Interfaces:**
- Produces: `RuleEngine.applySQLiteRules(_:to:)`, `RuleEngine.matchingArticleCount(conditionDrafts:matchMode:articles:[ArticleRuleSnapshot])`,
  `RuleEngine.RuleSnapshot`, `RuleEngine.ArticleRuleSnapshot`, `RuleEngine.TagSnapshot`,
  `RuleEngine.RuleConditionSnapshot`, `RuleEngine.SQLiteRuleApplicationResult`,
  `RuleEngine.ArticleTagAssignment` bleiben unverändert (aktiv genutzt von
  `SQLiteRuleEvaluationStore.swift`, `SQLiteFeedRefreshService.swift`).
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "RuleEngine\.applyRules\b\|RuleEngine\.applyRulesWithNotifications\|RuleEngine\.snapshots(from:\|RuleEngine\.applyRulesToExistingArticles\|RuleEngine\.matchingArticleCount(conditionDrafts:matchMode:articles:\[Article\]" Feedivo`

Erwartung: 0 Treffer außerhalb von `Feedivo/Services/RuleEngine.swift` selbst und
`Feedivo/ViewModels/FeedViewModel.swift` (dessen einziger Aufrufer, `refreshFeedContents`, wird in
Task 15 als tot entfernt — falls Task 15 bereits abgeschlossen ist, sollte dieser Treffer schon
weg sein). Falls ein anderer Produktions-Aufrufer auftaucht: STOPPEN, BLOCKED melden.

- [ ] **Step 2: Tote `@Model`-Hälfte aus `RuleEngine.swift` entfernen**

Ersetze den kompletten Inhalt von `Feedivo/Services/RuleEngine.swift`:

```swift
import Foundation

enum RuleEngine {
    struct RuleApplicationResult: Equatable {
        var appliedActionCount: Int
        var notifications: [RuleNotificationResult]
    }

    struct RuleConditionSnapshot: Equatable, Sendable {
        var field: String
        var conditionOperator: String
        var value: String
        var sortOrder: Int
    }

    struct RuleSnapshot: Equatable, Sendable {
        var id: UUID
        var name: String
        var isEnabled: Bool
        var conditionMatchMode: String
        var actionRaw: String
        var notificationTemplate: String
        var notificationPriorityRaw: String
        var sortOrder: Int
        var conditions: [RuleConditionSnapshot]
        var assignTag: TagSnapshot?
    }

    struct TagSnapshot: Equatable, Sendable {
        var id: String
        var name: String
        var colorHex: String
    }

    struct ArticleRuleSnapshot: Equatable, Sendable {
        var id: String
        var title: String
        var summary: String?
        var feedTitle: String
    }

    struct SQLiteRuleApplicationResult: Equatable, Sendable {
        var appliedActionCount: Int
        var hiddenArticleIDs: [String]
        var tagAssignments: [ArticleTagAssignment]
        var notifications: [RuleNotificationResult]
    }

    struct ArticleTagAssignment: Equatable, Sendable {
        var articleID: String
        var tag: TagSnapshot
    }

    private struct NormalizedCondition {
        var field: String
        var conditionOperator: String
        var lowercasedValue: String
        var regularExpression: NSRegularExpression?
    }

    private struct PreparedRuleSnapshot {
        let rule: RuleSnapshot
        let conditions: [NormalizedCondition]
        let matchMode: RuleMatchMode
    }

    static func applySQLiteRules(
        _ rules: [RuleSnapshot],
        to articles: [ArticleRuleSnapshot]
    ) -> SQLiteRuleApplicationResult {
        let preparedRules = preparedSQLiteRules(rules)
        var appliedActionCount = 0
        var hiddenArticleIDs: [String] = []
        var tagAssignments: [ArticleTagAssignment] = []
        var assignedArticleTagPairs = Set<String>()
        var notifications: [RuleNotificationResult] = []

        for article in articles {
            for preparedRule in preparedRules {
                guard matches(
                    conditions: preparedRule.conditions,
                    matchMode: preparedRule.matchMode,
                    article: article
                ) else {
                    continue
                }

                switch RuleAction.normalized(preparedRule.rule.actionRaw) {
                case .assignTag:
                    guard let tag = preparedRule.rule.assignTag else {
                        continue
                    }

                    let assignmentKey = "\(article.id)|\(tag.id)"
                    guard assignedArticleTagPairs.insert(assignmentKey).inserted else {
                        continue
                    }

                    tagAssignments.append(
                        ArticleTagAssignment(
                            articleID: article.id,
                            tag: tag
                        )
                    )
                    appliedActionCount += 1
                case .hideArticle:
                    if !hiddenArticleIDs.contains(article.id) {
                        hiddenArticleIDs.append(article.id)
                    }
                    appliedActionCount += 1
                case .notify:
                    notifications.append(notificationResult(for: preparedRule.rule, article: article))
                    appliedActionCount += 1
                }
            }
        }

        return SQLiteRuleApplicationResult(
            appliedActionCount: appliedActionCount,
            hiddenArticleIDs: hiddenArticleIDs,
            tagAssignments: tagAssignments,
            notifications: notifications
        )
    }

    static func matchingArticleCount(
        conditionDrafts: [RuleConditionDraft],
        matchMode: RuleMatchMode,
        articles: [ArticleRuleSnapshot]
    ) -> Int {
        let conditions = normalizedConditions(from: conditionDrafts)
        guard !conditions.isEmpty else {
            return 0
        }

        return articles.reduce(0) { count, article in
            matches(conditions: conditions, matchMode: matchMode, article: article)
                ? count + 1
                : count
        }
    }

    private static func preparedSQLiteRules(_ rules: [RuleSnapshot]) -> [PreparedRuleSnapshot] {
        sortedRules(rules).compactMap { rule in
            guard rule.isEnabled else {
                return nil
            }

            let conditions = normalizedConditions(for: rule)
            guard !conditions.isEmpty else {
                return nil
            }

            return PreparedRuleSnapshot(
                rule: rule,
                conditions: conditions,
                matchMode: RuleMatchMode.normalized(rule.conditionMatchMode)
            )
        }
    }

    private static func matches(
        conditions: [NormalizedCondition],
        matchMode: RuleMatchMode,
        article: ArticleRuleSnapshot
    ) -> Bool {
        switch matchMode {
        case .all:
            return conditions.allSatisfy { condition in
                matches(condition: condition, article: article)
            }
        case .any:
            return conditions.contains { condition in
                matches(condition: condition, article: article)
            }
        }
    }

    private static func sortedRules(_ rules: [RuleSnapshot]) -> [RuleSnapshot] {
        rules.sorted { firstRule, secondRule in
            if firstRule.sortOrder == secondRule.sortOrder {
                return firstRule.name.localizedCaseInsensitiveCompare(secondRule.name) == .orderedAscending
            }

            return firstRule.sortOrder < secondRule.sortOrder
        }
    }

    private static func normalizedConditions(for rule: RuleSnapshot) -> [NormalizedCondition] {
        rule.conditions
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { condition in
                normalizedCondition(
                    field: condition.field,
                    conditionOperator: condition.conditionOperator,
                    value: condition.value
                )
            }
    }

    private static func normalizedConditions(from drafts: [RuleConditionDraft]) -> [NormalizedCondition] {
        drafts.compactMap { draft in
            normalizedCondition(
                field: draft.field.rawValue,
                conditionOperator: draft.conditionOperator.rawValue,
                value: draft.value
            )
        }
    }

    private static func normalizedCondition(
        field: String,
        conditionOperator: String,
        value: String
    ) -> NormalizedCondition? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let expression = regularExpression(
            for: conditionOperator,
            pattern: trimmedValue
        )
        if conditionOperator == RuleConditionOperator.regex.rawValue,
           expression == nil {
            return nil
        }

        return NormalizedCondition(
            field: field,
            conditionOperator: conditionOperator,
            lowercasedValue: trimmedValue.lowercased(),
            regularExpression: expression
        )
    }

    private static func matches(condition: NormalizedCondition, article: ArticleRuleSnapshot) -> Bool {
        guard let fieldValue = fieldValue(for: condition.field, article: article) else {
            return false
        }

        if condition.conditionOperator == RuleConditionOperator.regex.rawValue {
            guard let regularExpression = condition.regularExpression else {
                return false
            }

            let range = NSRange(location: 0, length: fieldValue.utf16.count)
            return regularExpression.firstMatch(in: fieldValue, range: range) != nil
        }

        let normalizedFieldValue = fieldValue.lowercased()

        switch condition.conditionOperator {
        case RuleConditionOperator.contains.rawValue:
            return normalizedFieldValue.contains(condition.lowercasedValue)
        case RuleConditionOperator.startsWith.rawValue:
            return normalizedFieldValue.hasPrefix(condition.lowercasedValue)
        case RuleConditionOperator.endsWith.rawValue:
            return normalizedFieldValue.hasSuffix(condition.lowercasedValue)
        default:
            return false
        }
    }

    private static func regularExpression(
        for conditionOperator: String,
        pattern: String
    ) -> NSRegularExpression? {
        guard conditionOperator == RuleConditionOperator.regex.rawValue else {
            return nil
        }

        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func fieldValue(for field: String, article: ArticleRuleSnapshot) -> String? {
        switch field {
        case RuleConditionField.title.rawValue:
            return article.title
        case RuleConditionField.summary.rawValue:
            return article.summary
        case RuleConditionField.feedTitle.rawValue:
            return article.feedTitle
        default:
            return nil
        }
    }

    private static func notificationResult(for rule: RuleSnapshot, article: ArticleRuleSnapshot) -> RuleNotificationResult {
        RuleNotificationResult(
            ruleID: rule.id,
            ruleName: rule.name,
            message: notificationMessage(for: rule, article: article),
            articleTitle: article.title,
            feedTitle: article.feedTitle,
            priority: RuleNotificationPriority.normalized(rule.notificationPriorityRaw)
        )
    }

    private static func notificationMessage(for rule: RuleSnapshot, article: ArticleRuleSnapshot) -> String {
        let template = rule.notificationTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTemplate = template.isEmpty ? "{Titel}" : template

        return normalizedTemplate
            .replacingOccurrences(of: "{Titel}", with: article.title)
            .replacingOccurrences(of: "{Feed}", with: article.feedTitle)
            .replacingOccurrences(of: "{Regel}", with: rule.name)
    }
}
```

**Wichtig:** `RuleApplicationResult` bleibt in der Datei, auch wenn nach dieser Bereinigung kein
Aufrufer innerhalb von `RuleEngine.swift` mehr existiert — prüfe per
`grep -rn "RuleApplicationResult" Feedivo` ob `FeedViewModel.swift` (vor Abschluss von Task 15)
noch darauf verweist. Falls beim Ausführen dieses Tasks Task 15 noch nicht abgeschlossen ist und
`FeedViewModel.swift` noch `RuleApplicationResult`/`applyRulesWithNotifications` referenziert,
NICHT löschen, sondern den Build-Fehler als Hinweis nehmen, dass die Tasks in der falschen
Reihenfolge laufen — BLOCKED melden statt zu improvisieren.

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt fehl, falls `RuleEngineTests.swift` noch die entfernten Symbole
referenziert — nächster Schritt behebt das.

- [ ] **Step 4: `RuleEngineTests.swift` bereinigen**

Lies die Datei komplett. Entferne alle `@Test func`, die `RuleEngine.applyRules(`,
`RuleEngine.applyRulesWithNotifications(` (die `Rule`/`Article`/`Feed`-Overloads, NICHT
`ArticleRuleSnapshot`-basierte Aufrufe — die gibt es in dieser Datei nicht, alle
`applyRulesWithNotifications`-Aufrufe sind `@Model`-typisiert), `RuleEngine.snapshots(from:)`,
oder `RuleEngine.applyRulesToExistingArticles(` aufrufen — erwartet werden ca. 11 Testfunktionen
mit Namen wie `applyRulesUnterstuetztMehrereBedingungenMitAND`,
`applyRulesBlendetArtikelBeiHideAktionAus` und ähnliche. Behalte alle Tests, die
`RuleEngine.matchingArticleCount(conditionDrafts:matchMode:articles:[ArticleRuleSnapshot])` oder
`RuleEngine.applySQLiteRules(` aufrufen (Namen wie `matchingCountsLiefertTrefferProRegelInEinerMap`,
`previewMatchingArticleCount...` — bei den `previewMatchingArticleCount...`-Tests genau prüfen,
welchen Overload sie aufrufen: falls `articles: [ArticleRuleSnapshot]`, behalten; falls
`articles: [Article]`, löschen).

- [ ] **Step 5: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleEngineTests 2>&1 | tail -60`
Erwartung: alle verbleibenden Tests grün.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/RuleEngine.swift FeedivoTests/RuleEngineTests.swift
git commit -m "Remove dead Article/Rule/Feed-typed half of RuleEngine"
```

---

## Task 5: `SmartFolderFormatter.swift` bereinigen

**Files:**
- Modify: `Feedivo/Views/SmartFolders/SmartFolderFormatter.swift`

**Interfaces:**
- Produces: `displayName(for:SmartFolderRecord)`, `conditionSummary(for:conditions:)`,
  `drafts(for:[SmartFolderConditionRecord])`, `systemImage(for:SmartFolderRecord)`,
  `color(for:SmartFolderRecord)` bleiben unverändert (genutzt von `SmartFolderSettingsView.swift`,
  `SmartFolderEditorView.swift`, `SQLiteSmartFolderSnapshot.swift`).
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "SmartFolderFormatter\.conditionSummary(for: folder: SmartFolder)\|SmartFolderFormatter\.includesHiddenStatus\|SmartFolderFormatter\.showsReadArticlesByDefault\|SmartFolderFormatter\.systemImage(for: folder: SmartFolder)\|SmartFolderFormatter\.color(for: folder: SmartFolder)\|SmartFolderFormatter\.drafts(for: folder: SmartFolder)" Feedivo`

(Die Overload-Auflösung lässt sich per Namens-Grep nicht exakt matchen — verifiziere stattdessen
mit: `grep -rn "SmartFolderFormatter\." Feedivo | grep -v "Views/SmartFolders/SmartFolderFormatter.swift"`
und prüfe für jeden Treffer manuell, ob er den `SmartFolder`/`SmartFolderCondition`-Overload oder
den `SmartFolderRecord`/`SmartFolderConditionRecord`-Overload meint.) Erwartung: kein
Produktions-Aufrufer nutzt die `SmartFolder`/`SmartFolderCondition`-typisierten Overloads.

- [ ] **Step 2: Toten `@Model`-typisierten Teil entfernen**

Ersetze den kompletten Inhalt von `Feedivo/Views/SmartFolders/SmartFolderFormatter.swift`:

```swift
import Foundation
import SwiftUI

enum SmartFolderFormatter {
    static func displayName(for folder: SmartFolderRecord) -> String {
        guard let defaultKey = folder.defaultKey else {
            return folder.name
        }

        switch defaultKey {
        case "all": return String(localized: "smartFolder.default.all")
        case "unread": return String(localized: "smartFolder.default.unread")
        case "starred": return String(localized: "smartFolder.default.starred")
        case "today": return String(localized: "smartFolder.default.today")
        case "hidden": return String(localized: "smartFolder.default.hidden")
        case "archived": return String(localized: "smartFolder.default.archived")
        case "thisWeek": return String(localized: "smartFolder.default.thisWeek")
        case "saved": return String(localized: "smartFolder.default.saved")
        default: return folder.name
        }
    }

    static func conditionSummary(
        for folder: SmartFolderRecord,
        conditions: [SmartFolderConditionRecord]
    ) -> String {
        let conditions = sortedConditions(conditions)
        guard !conditions.isEmpty else {
            return L10n.smartFolderSummaryAllArticles
        }

        let connector = RuleMatchMode.normalized(folder.matchMode) == .all ? L10n.smartFolderSummaryAll : L10n.smartFolderSummaryAny
        return conditions
            .map { condition in
                conditionDescription(condition)
            }
            .joined(separator: " \(connector) ")
    }

    static func drafts(for conditions: [SmartFolderConditionRecord]) -> [SmartFolderConditionDraft] {
        sortedConditions(conditions).compactMap { condition in
            guard let field = SmartFolderConditionField(rawValue: condition.field),
                  let conditionOperator = SmartFolderConditionOperator(rawValue: condition.conditionOperator)
            else {
                return nil
            }

            return SmartFolderConditionDraft(
                field: field,
                conditionOperator: conditionOperator,
                value: condition.value
            )
        }
    }

    static func systemImage(for folder: SmartFolderRecord) -> String {
        SmartFolderAppearance.normalizedIconName(folder.iconName ?? SmartFolderAppearance.defaultIconName)
    }

    static func color(for folder: SmartFolderRecord) -> Color {
        SmartFolderAppearance.color(for: folder.colorHex ?? SmartFolderAppearance.defaultColorHex)
    }

    private static func sortedConditions(_ conditions: [SmartFolderConditionRecord]) -> [SmartFolderConditionRecord] {
        conditions.sorted { firstCondition, secondCondition in
            firstCondition.sortOrder < secondCondition.sortOrder
        }
    }

    private static func conditionDescription(_ condition: SmartFolderConditionRecord) -> String {
        let field = SmartFolderConditionField(rawValue: condition.field)?.title ?? condition.field
        let conditionOperator = SmartFolderConditionOperator(rawValue: condition.conditionOperator)?.title ?? condition.conditionOperator
        let value = displayedValue(fieldRaw: condition.field, value: condition.value)
        return "\(field) \(conditionOperator) \"\(value)\""
    }

    private static func displayedValue(fieldRaw: String, value: String) -> String {
        if fieldRaw == SmartFolderConditionField.status.rawValue,
           let status = SmartFolderStatusValue(rawValue: value) {
            return status.title
        }

        if fieldRaw == SmartFolderConditionField.date.rawValue,
           let dateValue = SmartFolderDateValue(rawValue: value) {
            return dateValue.title
        }

        return value
    }
}
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED (kein dediziertes Testfile für diese Datei bekannt — falls der Build
eine Testdatei zeigt, die einen entfernten Overload aufruft, diese Tests analog zu Step 4 in
anderen Tasks entfernen und im Report vermerken).

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/SmartFolders/SmartFolderFormatter.swift
git commit -m "Remove dead SmartFolder/SmartFolderCondition-typed half of SmartFolderFormatter"
```

---

## Task 6: `ArticleFilterOption.swift` bereinigen

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleFilterOption.swift`

**Interfaces:**
- Produces: `ArticleFilterOption` (enum, `.allCases`, `.storageKey`, `.resolved(from:)`, `.label`,
  `.systemImage`) bleibt unverändert (genutzt von `SQLiteFeedArticleListView.swift`).
- Consumes: keine Abhängigkeiten von anderen Tasks. Zugehörige Tests (falls vorhanden) leben in
  `FeedivoTests/ArticleListQueryTests.swift` — das ist Task 22, nicht dieser Task.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "\.filtered(\|ArticleFilterOption.*\.includes(" Feedivo`

Erwartung: `filtered(_:[Article]...)` und `includes(_:Article...)` haben 0 Aufrufer außerhalb der
eigenen Datei.

- [ ] **Step 2: Tote `Article`-Methoden entfernen**

Ersetze den kompletten Inhalt von `Feedivo/Views/ArticleList/ArticleFilterOption.swift`:

```swift
import Foundation

enum ArticleFilterOption: String, CaseIterable, Identifiable {
    static let storageKey = "articleList.filterOption"

    case all
    case unread
    case starred
    case archived
    case today

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all:
            L10n.articleFilterAll
        case .unread:
            L10n.articleFilterUnread
        case .starred:
            L10n.articleFilterStarred
        case .archived:
            L10n.articleFilterArchived
        case .today:
            L10n.articleFilterToday
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "tray.full"
        case .unread:
            "circle.fill"
        case .starred:
            "star.fill"
        case .archived:
            "archivebox"
        case .today:
            "calendar"
        }
    }

    static func resolved(from rawValue: String) -> ArticleFilterOption {
        ArticleFilterOption(rawValue: rawValue) ?? .all
    }
}
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt evtl. fehl, falls `ArticleListQueryTests.swift` noch `.filtered(`/
`.includes(` auf `ArticleFilterOption` aufruft — falls ja, NUR notieren (nicht selbst fixen), Task
22 behandelt diese Datei explizit.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleFilterOption.swift
git commit -m "Remove dead Article-typed methods from ArticleFilterOption"
```

(Falls Step 3 einen Build-Fehler durch `ArticleListQueryTests.swift` zeigt: committen trotzdem,
der Build-Fehler wird durch Task 22 behoben — in der Commit-Message vermerken:
"Build bricht bis Task 22 (ArticleListQueryTests.swift) — erwartet.")

---

## Task 7: `ArticleMarkReadOption.swift` bereinigen

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleMarkReadOption.swift`

**Interfaces:**
- Produces: `ArticleMarkReadOption` (enum, `.allCases`, `.id`, `.label`) bleibt unverändert.
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "\.matchingArticles(\|ArticleMarkReadOption.*\.includes(" Feedivo FeedivoTests`

Erwartung: 0 Aufrufer außerhalb der eigenen Datei.

- [ ] **Step 2: Tote `Article`-Methoden entfernen**

Ersetze den kompletten Inhalt von `Feedivo/Views/ArticleList/ArticleMarkReadOption.swift`:

```swift
import Foundation

enum ArticleMarkReadOption: CaseIterable, Identifiable {
    case olderThanOneDay
    case olderThanTwoDays
    case olderThanThreeDays
    case olderThanFourDays
    case olderThanOneWeek
    case olderThanTwoWeeks
    case allVisible

    var id: String {
        switch self {
        case .olderThanOneDay:
            "olderThanOneDay"
        case .olderThanTwoDays:
            "olderThanTwoDays"
        case .olderThanThreeDays:
            "olderThanThreeDays"
        case .olderThanFourDays:
            "olderThanFourDays"
        case .olderThanOneWeek:
            "olderThanOneWeek"
        case .olderThanTwoWeeks:
            "olderThanTwoWeeks"
        case .allVisible:
            "allVisible"
        }
    }

    var label: String {
        switch self {
        case .olderThanOneDay:
            L10n.articleMarkReadOlderThanOneDay
        case .olderThanTwoDays:
            L10n.articleMarkReadOlderThanTwoDays
        case .olderThanThreeDays:
            L10n.articleMarkReadOlderThanThreeDays
        case .olderThanFourDays:
            L10n.articleMarkReadOlderThanFourDays
        case .olderThanOneWeek:
            L10n.articleMarkReadOlderThanOneWeek
        case .olderThanTwoWeeks:
            L10n.articleMarkReadOlderThanTwoWeeks
        case .allVisible:
            L10n.articleMarkAllReadCommand
        }
    }
}
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleMarkReadOption.swift
git commit -m "Remove dead Article-typed methods from ArticleMarkReadOption"
```

---

## Task 8: `ArticleSortOption.swift` + `ArticleSortOptionTests.swift` bereinigen

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleSortOption.swift`
- Delete: `FeedivoTests/ArticleSortOptionTests.swift`

**Interfaces:**
- Produces: `ArticleSortOption` (enum, `.storageKey`, `.allCases`, `.id`, `.label`,
  `.resolved(from:)`) bleibt unverändert (genutzt von `ViewCommands.swift`,
  `SQLiteFeedArticleListView.swift`).
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "\.sorted(\[" Feedivo; grep -rn "ArticleSortOption" FeedivoTests`

Erwartung: `ArticleSortOption.sorted(_:[Article])` hat 0 Aufrufer außerhalb der eigenen Datei
(die eigentliche Sortierung läuft über einen eigenen Comparator in
`SQLiteFeedArticleListView.swift:286`); `FeedivoTests/ArticleSortOptionTests.swift` ist die
einzige Testdatei, die `ArticleSortOption.sorted(` aufruft.

- [ ] **Step 2: Tote `Article`-Methoden + private Helfer entfernen**

Ersetze den kompletten Inhalt von `Feedivo/Views/ArticleList/ArticleSortOption.swift`:

```swift
import Foundation

enum ArticleSortOption: String, CaseIterable, Identifiable {
    static let storageKey = "articleList.sortOption"

    case newestFirst
    case oldestFirst
    case feed
    case title
    case shortReadingTimeFirst

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .newestFirst:
            L10n.articleSortNewestFirst
        case .oldestFirst:
            L10n.articleSortOldestFirst
        case .feed:
            L10n.articleSortFeed
        case .title:
            L10n.articleSortTitle
        case .shortReadingTimeFirst:
            L10n.articleSortShortReadingTimeFirst
        }
    }

    static func resolved(from rawValue: String) -> ArticleSortOption {
        ArticleSortOption(rawValue: rawValue) ?? .newestFirst
    }
}
```

- [ ] **Step 3: Testdatei löschen**

```bash
rm FeedivoTests/ArticleSortOptionTests.swift
```

Diese Datei testet ausschließlich die jetzt gelöschte `sorted(_:[Article])`-Methode und ihre
privaten Helfer (`newestFirst`/`oldestFirst`/`compareText`/`compareNumber`/
`compareOptionalDate`/`readingMinutes`/`normalizedText`) — es gibt keine lebendige Alternative zu
migrieren, da die eigentliche Row-Sortierung über einen eigenen Comparator direkt in
`SQLiteFeedArticleListView.swift` läuft, nicht über diesen Enum.

- [ ] **Step 4: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED — außer `FeedivoTests/ArticleListQueryTests.swift` ruft an anderer
Stelle noch `ArticleSortOption.sorted(_:[Article])` auf (ein separater Test dort, unabhängig von
der hier gelöschten `ArticleSortOptionTests.swift`). Falls das der Fall ist, ist dieser eine
Build-Fehler erwartet — siehe Global Constraints — und wird von Task 22 behoben; committen trotzdem.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests 2>&1 | tail -60`
Erwartung: grün außer den 5 bekannten vorbestehenden Fehlschlägen (siehe Global Constraints). Falls
der Build wegen `ArticleListQueryTests.swift` insgesamt fehlschlägt, kann dieser Testlauf nicht
ausgeführt werden — in diesem Fall im Report vermerken und trotzdem committen.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleSortOption.swift FeedivoTests/ArticleSortOptionTests.swift
git commit -m "Remove dead Article-typed sort logic and its tests from ArticleSortOption"
```

---

## Task 9: `FeedPropertiesFormatter.swift` + `FeedPropertiesFormatterTests.swift` bereinigen

**Files:**
- Modify: `Feedivo/Views/Sidebar/FeedPropertiesFormatter.swift`
- Modify: `FeedivoTests/FeedPropertiesFormatterTests.swift`

**Interfaces:**
- Produces: `linkURL(_:)`, `copyableXMLAddress(_:)`, `nextRefreshDate(lastRefreshed:intervalMinutes:)`
  bleiben unverändert (genutzt von `FeedPropertiesView.swift`).
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "FeedPropertiesFormatter\.latestArticle\|FeedPropertiesFormatter\.recentArticleCount\|FeedPropertiesFormatter\.latestLogEntr" Feedivo`

Erwartung: 0 Aufrufer außerhalb der eigenen Datei und `FeedPropertiesFormatterTests.swift`.

- [ ] **Step 2: Tote `Article`/`FeedLogEntry`-Methoden entfernen**

Ersetze den kompletten Inhalt von `Feedivo/Views/Sidebar/FeedPropertiesFormatter.swift`:

```swift
import Foundation

enum FeedPropertiesFormatter {
    static func linkURL(_ urlString: String?) -> URL? {
        guard let urlString else {
            return nil
        }

        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: trimmedURL),
            let scheme = components.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            components.host != nil,
            let url = components.url
        else {
            return nil
        }

        return url
    }

    static func copyableXMLAddress(_ urlString: String) -> String? {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedURL.isEmpty ? nil : trimmedURL
    }

    static func nextRefreshDate(lastRefreshed: Date?, intervalMinutes: Int) -> Date? {
        guard let lastRefreshed else {
            return nil
        }

        return lastRefreshed.addingTimeInterval(TimeInterval(intervalMinutes * 60))
    }
}
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt fehl (Tests referenzieren noch entfernte Methoden) — nächster Schritt
behebt das.

- [ ] **Step 4: Tote Tests aus `FeedPropertiesFormatterTests.swift` entfernen**

Lies die Datei komplett. Entferne die 4 `@Test func`, die `latestArticle(in:`,
`recentArticleCount(in:`, `latestLogEntries(`, oder `latestLogEntryCount(` aufrufen — erwartet
werden Namen wie `latestArticleWaehltNeuestenVeroeffentlichtenArtikel`,
`recentArticleCountZaehltNurArtikelDerLetztenSiebenTage`,
`latestLogEntriesBegrenztAufZwanzigNeuesteEintraege`,
`latestLogEntryCountZaehltNurSichtbareEintraege`. Behalte die Tests für
`nextRefreshDate(lastRefreshed:intervalMinutes:)` und `linkURL`/`copyableXMLAddress`.

- [ ] **Step 5: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedPropertiesFormatterTests 2>&1 | tail -60`
Erwartung: alle verbleibenden Tests grün.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Sidebar/FeedPropertiesFormatter.swift FeedivoTests/FeedPropertiesFormatterTests.swift
git commit -m "Remove dead Article/FeedLogEntry-typed methods from FeedPropertiesFormatter"
```

---

## Task 10: `FeedFolderOrganizer.swift` + `FeedFolderOrganizerTests.swift` bereinigen

**Files:**
- Modify: `Feedivo/Views/Sidebar/FeedFolderOrganizer.swift`
- Modify: `FeedivoTests/FeedFolderOrganizerTests.swift`

**Interfaces:**
- Produces: `folderNames(feedFolderNames:explicitFolderNames:)` (String-basiert),
  `feedsWithoutFolder(from:[FeedSidebarSnapshot])`,
  `feedsByFolderName(in:[FeedSidebarSnapshot],folders:[FeedFolderRecord])`, `normalizedFolderName(_:)`
  bleiben unverändert (genutzt von `SidebarView.swift`, `FeedStore.swift`, `SQLiteReaderView.swift`,
  `ArticleMetadataInspectorView.swift`, `SQLiteFeedSubscriptionService.swift`).
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "FeedFolderOrganizer\.folderNames(in:\|FeedFolderOrganizer\.feedsWithoutFolder(from: feeds\|FeedFolderOrganizer\.visibleFeeds\|FeedFolderOrganizer\.feeds(in:\|FeedFolderOrganizer\.feedsByFolderName(in: feeds" Feedivo`

Erwartung: 0 Produktions-Aufrufer der `[Feed]`/`[FeedFolder]`-typisierten Overloads.

- [ ] **Step 2: Tote `[Feed]`/`[FeedFolder]`-Methoden entfernen**

Ersetze den kompletten Inhalt von `Feedivo/Views/Sidebar/FeedFolderOrganizer.swift`:

```swift
import Foundation

enum SidebarFeedVisibilitySettings {
    static let showsReadFeedsKey = "sidebar.showsReadFeeds"
    static let defaultShowsReadFeeds = true
}

enum FeedFolderOrganizer {

    static func folderNames(feedFolderNames: [String], explicitFolderNames: [String]) -> [String] {
        folderNames(
            feedFolderNames: feedFolderNames.map(Optional.some),
            explicitFolderNames: explicitFolderNames.map(Optional.some)
        )
    }

    static func folderNames(feedFolderNames: [String?], explicitFolderNames: [String?]) -> [String] {
        var canonicalNamesByLowercasedName: [String: String] = [:]

        for folderName in feedFolderNames {
            insert(folderName: folderName, into: &canonicalNamesByLowercasedName)
        }

        for folderName in explicitFolderNames {
            insert(folderName: folderName, into: &canonicalNamesByLowercasedName)
        }

        return canonicalNamesByLowercasedName.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    // Snapshot-basierte Überladungen für den SQLite-only Sidebar-Pfad. Diese
    // Helfer arbeiten ausschließlich auf FeedSidebarSnapshot und brauchen kein
    // SwiftData-Feed-Objekt mehr.
    static func feedsWithoutFolder(from snapshots: [FeedSidebarSnapshot]) -> [FeedSidebarSnapshot] {
        sortedSnapshots(
            snapshots.filter { normalizedFolderName($0.folderName) == nil }
        )
    }

    static func feedsByFolderName(
        in snapshots: [FeedSidebarSnapshot],
        folders: [FeedFolderRecord] = []
    ) -> [(folderName: String, snapshots: [FeedSidebarSnapshot])] {
        let orderedFolderNames = folderNames(
            feedFolderNames: snapshots.map(\.folderName),
            explicitFolderNames: folders.map(\.name)
        )

        var snapshotsByLowercasedName: [String: [FeedSidebarSnapshot]] = [:]
        for snapshot in snapshots {
            guard let normalizedName = normalizedFolderName(snapshot.folderName) else {
                continue
            }
            snapshotsByLowercasedName[normalizedName.lowercased(), default: []].append(snapshot)
        }

        return orderedFolderNames.map { folderName in
            let grouped = snapshotsByLowercasedName[folderName.lowercased()] ?? []
            return (folderName, sortedSnapshots(grouped))
        }
    }

    private static func sortedSnapshots(_ snapshots: [FeedSidebarSnapshot]) -> [FeedSidebarSnapshot] {
        snapshots.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func normalizedFolderName(_ folderName: String?) -> String? {
        guard let trimmedName = folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty
        else {
            return nil
        }

        return trimmedName
    }

    private static func insert(
        folderName: String?,
        into canonicalNamesByLowercasedName: inout [String: String]
    ) {
        guard let folderName = normalizedFolderName(folderName) else {
            return
        }

        let key = folderName.lowercased()
        if canonicalNamesByLowercasedName[key] == nil {
            canonicalNamesByLowercasedName[key] = folderName
        }
    }
}
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt fehl (Tests referenzieren noch entfernte Methoden) — nächster Schritt
behebt das.

- [ ] **Step 4: `FeedFolderOrganizerTests.swift` bereinigen**

Lies die Datei komplett. Entferne jeden `@Test func`, der `folderNames(in:` (die `[Feed]`/
`[FeedFolder]`-Variante), `feedsWithoutFolder(from:` mit `[Feed]`-Argument, `visibleFeeds(from:`,
`feeds(in:from:`, oder `feedsByFolderName(in:` mit `[Feed]`-Argument aufruft. Behalte jeden Test,
der bereits `[String]` (für `folderNames(feedFolderNames:explicitFolderNames:)`) oder
`[FeedSidebarSnapshot]` nutzt — z. B. einen Test namens ähnlich
`folderNamesKoennenAusLeichtenStringsGebildetWerden`. Falls beim Lesen unklar ist, welchen Overload
ein Test aufruft (Swift löst Overloads implizit anhand der Argumenttypen auf), prüfe die Typen der
lokal konstruierten Testdaten (`Feed(...)`/`FeedFolder(...)` → löschen; `String`/
`FeedSidebarSnapshot(...)` → behalten).

- [ ] **Step 5: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedFolderOrganizerTests 2>&1 | tail -60`
Erwartung: alle verbleibenden Tests grün.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Sidebar/FeedFolderOrganizer.swift FeedivoTests/FeedFolderOrganizerTests.swift
git commit -m "Remove dead Feed/FeedFolder-typed methods from FeedFolderOrganizer"
```

---

## Task 11: `ArticleReaderSnapshot.swift` bereinigen

**Files:**
- Modify: `Feedivo/Snapshots/ArticleReaderSnapshot.swift`

**Interfaces:**
- Produces: `ReaderArticleTagMetadata.init(id:name:colorHex:)`, `ReaderArticleTagMetadata.init(record: TagRecord)`,
  `ArticleReaderSnapshot` bleiben unverändert.
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "ReaderArticleTagMetadata(tag:" Feedivo FeedivoTests`

Erwartung: 0 Treffer außer der Definition selbst.

- [ ] **Step 2: Toten `init(tag: Tag)` entfernen**

Von:

```swift
    init(record: TagRecord) {
        self.id = record.id
        self.name = record.name
        self.colorHex = record.colorHex
    }

    init(tag: Tag) {
        self.id = tag.id.uuidString
        self.name = tag.name
        self.colorHex = tag.colorHex
    }
}
```

zu:

```swift
    init(record: TagRecord) {
        self.id = record.id
        self.name = record.name
        self.colorHex = record.colorHex
    }
}
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Snapshots/ArticleReaderSnapshot.swift
git commit -m "Remove dead Tag-based initializer from ReaderArticleTagMetadata"
```

---

## Task 12: `SQLiteSmartFolderSnapshot.swift` bereinigen

**Files:**
- Modify: `Feedivo/Snapshots/SQLiteSmartFolderSnapshot.swift`

**Interfaces:**
- Produces: `SQLiteSmartFolderSnapshot.init(folder: SmartFolderRecord, conditions:)`,
  `SQLiteSmartFolderConditionSnapshot.init?(condition: SmartFolderConditionRecord)` bleiben
  unverändert.
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "SQLiteSmartFolderSnapshot(folder: \|SQLiteSmartFolderConditionSnapshot(condition: condition" Feedivo FeedivoTests`

Erwartung: `init(folder: SmartFolder)` und `init?(condition: SmartFolderCondition)` haben 0
Aufrufer außer sich gegenseitig (der `SmartFolder`-init ruft den `SmartFolderCondition`-init auf).

- [ ] **Step 2: Tote `@Model`-typisierte Initializer entfernen**

Von:

```swift
    @MainActor
    init(folder: SmartFolder) {
        self.id = folder.id.uuidString
        self.name = folder.localizedDisplayName
        self.matchMode = RuleMatchMode.normalized(folder.matchModeRaw)
        self.iconName = folder.iconName
        self.colorHex = folder.colorHex
        self.defaultKey = folder.defaultKey
        self.conditions = (folder.conditions ?? [])
            .sorted { firstCondition, secondCondition in
                firstCondition.sortOrder < secondCondition.sortOrder
            }
            .compactMap(SQLiteSmartFolderConditionSnapshot.init(condition:))
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        matchMode: RuleMatchMode,
        conditionDrafts: [SmartFolderConditionDraft]
    ) {
```

zu:

```swift
    init(
        id: String = UUID().uuidString,
        name: String,
        matchMode: RuleMatchMode,
        conditionDrafts: [SmartFolderConditionDraft]
    ) {
```

Und von:

```swift
    @MainActor
    init?(condition: SmartFolderCondition) {
        guard let field = condition.fieldEnum,
              let conditionOperator = condition.operatorEnum
        else {
            return nil
        }

        self.init(
            field: field,
            conditionOperator: conditionOperator,
            value: condition.value
        )
    }

    init?(condition: SmartFolderConditionRecord) {
```

zu:

```swift
    init?(condition: SmartFolderConditionRecord) {
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Snapshots/SQLiteSmartFolderSnapshot.swift
git commit -m "Remove dead SmartFolder/SmartFolderCondition-based initializers"
```

---

## Task 13: `SidebarUnreadCount.swift` — toten `SmartFolder`-Init entfernen

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarUnreadCount.swift`

**Interfaces:**
- Produces: `SmartFolderSidebarBadgeKind.init?(folder: SQLiteSmartFolderSnapshot)`,
  `SidebarUnreadCount.badgeText`, `SmartFolderSidebarBadge.badgeText/badgeCount`,
  `SidebarBadgeInvalidation` bleiben unverändert (Phase-2-Constraint, `SidebarBadgeInvalidation`
  und `SmartFolderSidebarBadgeKind` NICHT antasten außer dem einen unten genannten Init).
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "SmartFolderSidebarBadgeKind(folder: folder)\|SmartFolderSidebarBadgeKind(folder:" Feedivo FeedivoTests`

Erwartung: der `folder: SmartFolder`-Init-Overload hat 0 Aufrufer (der einzige Produktions-Aufrufer,
`SidebarView.swift:481`, nutzt den `SQLiteSmartFolderSnapshot`-Overload).

- [ ] **Step 2: Toten Init entfernen**

Von:

```swift
    init?(folder: SmartFolder) {
        let conditions = (folder.conditions ?? []).sorted { $0.sortOrder < $1.sortOrder }

        if RuleMatchMode.normalized(folder.matchModeRaw) == .all,
           conditions.count == 1,
           let condition = conditions.first,
           condition.fieldRaw == SmartFolderConditionField.status.rawValue,
           condition.operatorRaw == SmartFolderConditionOperator.is.rawValue,
           let statusValue = SmartFolderStatusValue(rawValue: condition.value) {
            switch statusValue {
            case .unread:
                self = .unread
                return
            case .starred:
                self = .starred
                return
            case .hidden:
                self = .hidden
                return
            case .read, .archived:
                break
            }
        }

        if RuleMatchMode.normalized(folder.matchModeRaw) == .any,
           conditions.count == 2,
           conditions.allSatisfy({ condition in
               condition.fieldRaw == SmartFolderConditionField.status.rawValue
                   && condition.operatorRaw == SmartFolderConditionOperator.is.rawValue
           }) {
            let values = Set(conditions.map(\.value))
            if values == Set([
                SmartFolderStatusValue.starred.rawValue,
                SmartFolderStatusValue.archived.rawValue
            ]) {
                self = .saved
                return
            }
        }

        return nil
    }

    init?(folder: SQLiteSmartFolderSnapshot) {
```

zu:

```swift
    init?(folder: SQLiteSmartFolderSnapshot) {
```

- [ ] **Step 3: `import SwiftData` prüfen**

Nach Step 2 bleibt kein `@Model`-Typ mehr in der Datei referenziert (`SmartFolder` war der letzte).
Entferne `import SwiftData` vom Dateikopf.

- [ ] **Step 4: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarUnreadCount.swift
git commit -m "Remove dead SmartFolder-based init from SmartFolderSidebarBadgeKind"
```

---

## Task 14: `OPMLImportPreviewController.swift` + `OPMLImportPreviewControllerTests.swift` bereinigen

**Files:**
- Modify: `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift`
- Modify: `FeedivoTests/OPMLImportPreviewControllerTests.swift`

**Interfaces:**
- Produces: `availableFolders(existingFolderNames: [String]) -> [String]` bleibt unverändert
  (genutzt von `FirstRunWizardView.swift:681`, `OPMLImportReviewView.swift:332`).
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "\.availableFolders(existingFeeds:" Feedivo FeedivoTests`

Erwartung: 0 Produktions-Aufrufer; nur ein Test in `OPMLImportPreviewControllerTests.swift` nutzt
diesen Overload.

- [ ] **Step 2: Toten `[Feed]`-Overload entfernen**

Von:

```swift
    func availableFolders(existingFeeds: [Feed]) -> [String] {
        availableFolders(existingFolderNames: existingFeeds.compactMap { trimmedFolderName($0.folderName) })
    }

    /// SQLite-Variante: statt SwiftData-`Feed`-Objekten werden nur die
    /// Ordnernamen der bestehenden Feeds übergeben (aus `FeedStore.feeds()`
    /// bzw. `FeedFolderStore`). Duplikat-Check läuft in `opmlImportPreviewRows`
    /// bereits SQLite-basiert, deshalb braucht der Controller keine `Feed`-Liste
    /// mehr.
    func availableFolders(existingFolderNames: [String]) -> [String] {
```

zu:

```swift
    func availableFolders(existingFolderNames: [String]) -> [String] {
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt fehl (Test nutzt noch den entfernten Overload) — nächster Schritt behebt
das.

- [ ] **Step 4: Test auf `existingFolderNames:` migrieren**

Finde den Test `availableFoldersFasstExistingPreviewUndCustomZusammenUndSortiert` (oder ähnlich
benannt) in `FeedivoTests/OPMLImportPreviewControllerTests.swift`. Er ruft aktuell
`controller.availableFolders(existingFeeds: [Feed(url: ..., folderName: ...)])` auf. Ersetze den
Aufruf durch `controller.availableFolders(existingFolderNames: ["Ordnername1", "Ordnername2"])`
(die konkreten Ordnernamen aus den ursprünglich konstruierten `Feed`-Objekten übernehmen — lies den
bestehenden Test, um die exakten Werte zu extrahieren, und ersetze die `Feed(...)`-Konstruktion
durch die reinen Ordnernamen-Strings, die vorher als `folderName:`-Parameter übergeben wurden).

- [ ] **Step 5: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/OPMLImportPreviewControllerTests 2>&1 | tail -60`
Erwartung: alle Tests grün.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift FeedivoTests/OPMLImportPreviewControllerTests.swift
git commit -m "Remove dead Feed-based availableFolders overload, migrate its test"
```

---

## Task 15: `FeedViewModel.swift` + `FeedViewModelTests.swift` bereinigen (größter Task)

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Modify: `FeedivoTests/FeedViewModelTests.swift`

**Interfaces:**
- Produces: `addFeed(urlString:sqliteDatabase:)`, `refreshFeed(feedID:sqliteDatabase:)`,
  `refreshAllFeeds(sqliteDatabase:)`, `deleteFeed(feedID:sqliteDatabase:)`,
  `opmlImportPreviewRows(for:existingFeeds:sqliteDatabase:onProgress:)`, `unreadIncrement(for:)`
  bleiben unverändert. `importOPMLFeeds(_:existingFeeds:allowsDuplicates:refreshAfterImport:refreshIntervalMinutes:context:sqliteDatabase:)`
  bleibt als Methode bestehen, verliert aber ihre tote SwiftData-Fallback-Hälfte (siehe Step 3).
- Consumes: keine Abhängigkeiten von anderen Tasks — aber `RuleEngine.applyRulesWithNotifications`
  (dessen `[Article]`-Overload in Task 4 entfernt wird) wird hier NICHT mehr aufgerufen, sobald
  dieser Task fertig ist. Falls Task 4 vor diesem Task läuft, ist das kein Problem (Reihenfolge
  zwischen Task 4 und 15 ist nicht kritisch, beide entfernen unabhängig tote Aufrufer/Aufrufe).

- [ ] **Step 1: Verifikation**

Run: `grep -n "@available(\*, deprecated" Feedivo/ViewModels/FeedViewModel.swift`

Erwartung: genau 6 Treffer — auf `renameFeed(_:displayTitle:context:)`,
`restoreOriginalFeedTitle(_:context:)`, `addFeed(urlString:context:sqliteDatabase:)`,
`refreshFeed(_:context:sqliteDatabase:)`, `refreshAllFeeds(_:context:sqliteDatabase:)`,
`deleteFeed(_:context:)`. Falls die Anzahl abweicht: STOPPEN, BLOCKED melden (die Analyse dieses
Plans basiert auf exakt 6 Treffern).

- [ ] **Step 2: 6 `@available(deprecated)`-Methoden entfernen**

Entferne die komplette Methode `renameFeed(_:displayTitle:context:)`:

```swift
    @available(*, deprecated, message: "Legacy SwiftData-Editor-Pfad. Feed-Umbenennung läuft produktiv über SQLite-Store-Pfade in den Views.")
    @MainActor
    func renameFeed(_ feed: Feed?, displayTitle: String, context: ModelContext) {
        guard let feed else {
            return
        }

        let cleanedTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            errorMessage = L10n.feedRenameEmptyName
            return
        }

        errorMessage = nil
        feed.originalTitle = feed.originalTitle ?? feed.title
        feed.title = cleanedTitle

        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

Entferne die komplette Methode `restoreOriginalFeedTitle(_:context:)`:

```swift
    @available(*, deprecated, message: "Legacy SwiftData-Editor-Pfad. Feed-Rollback läuft produktiv über SQLite-Store-Pfade in den Views.")
    @MainActor
    func restoreOriginalFeedTitle(_ feed: Feed?, context: ModelContext) {
        guard let feed else {
            return
        }

        let originalTitle = feed.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let originalTitle, !originalTitle.isEmpty else {
            return
        }

        errorMessage = nil
        feed.title = originalTitle
        feed.originalTitle = originalTitle

        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

Entferne die komplette Methode `addFeed(urlString:context:sqliteDatabase:)` (die deprecated
Variante mit `context:`, NICHT `addFeed(urlString: String, sqliteDatabase: FeedivoDatabase?)`, die
danach folgt und bleibt):

```swift
    @MainActor
    @available(*, deprecated, message: "Legacy SwiftData-Fallback. Für produktive Fluesse FeedViewModel.addFeed(urlString:sqliteDatabase:) direkt mit Datenbank nutzen.")
    func addFeed(
        urlString: String,
        context: ModelContext? = nil,
        sqliteDatabase: FeedivoDatabase? = nil
    ) async {
        let cleanedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            errorMessage = L10n.feedErrorEmptyURL
            return
        }

        // Reentrancy-Guard — konsistent mit refreshFeed/refreshAllFeeds/importOPMLFeeds:
        // ein parallel laufender Refresh würde sonst isLoading überschreiben und die
        // UI fälschlich „nicht lädt" zeigen, während der Hintergrund-Refresh weiterläuft.
        guard !isLoading else {
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        if let sqliteDatabase {
            do {
                let service = SQLiteFeedSubscriptionService(
                    database: sqliteDatabase,
                    fetchFeed: fetchFeed,
                    discoverFaviconURL: discoverFaviconURL
                )
                _ = try await service.addFeed(
                    urlString: cleanedURL,
                    refreshIntervalMinutes: BackgroundRefreshSettings.defaultIntervalMinutes,
                    context: context
                )
                SQLiteDataInvalidation.bumpStatusVersion()
            } catch let error as LocalizedError {
                errorMessage = error.errorDescription ?? L10n.feedErrorAddFailed
            } catch {
                errorMessage = L10n.feedErrorAddFailed
            }

            return
        }

        do {
            let parsedFeed = try await fetchFeed(cleanedURL)

            // Duplikat-Prüfung — konsistent zum OPML-Pfad (importOPMLFeeds):
            // ein bereits abonnierter Feed mit derselben normalisierten URL
            // wird nicht erneut hinzugefügt. Prüfung nach fetchFeed, weil erst
            // dann die kanonische sourceURL feststeht.
            guard let context else {
                errorMessage = L10n.feedErrorAddFailed
                return
            }
            let knownFeedURLs = Set(
                ((try? context.fetch(FetchDescriptor<Feed>())) ?? [])
                    .map { normalizedFeedURL($0.url) }
            )
            if knownFeedURLs.contains(normalizedFeedURL(parsedFeed.sourceURL)) {
                errorMessage = L10n.feedErrorDuplicate
                return
            }

            let enrichedArticles = await enrichArticleImagesIfNeeded(parsedFeed.articles)
            let feed = Feed(
                url: parsedFeed.sourceURL,
                title: parsedFeed.title,
                feedDescription: parsedFeed.description,
                faviconURL: await faviconURL(for: parsedFeed),
                siteURL: parsedFeed.siteURL,
                followedAt: Date(),
                lastRefreshed: Date()
            )

            feed.articles = enrichedArticles.map { parsedArticle in
                Article(
                    title: parsedArticle.title,
                    link: parsedArticle.link,
                    summary: parsedArticle.summary,
                    content: parsedArticle.content,
                    publishedAt: parsedArticle.publishedAt,
                    imageURL: parsedArticle.imageURL,
                    sourceID: parsedArticle.sourceID,
                    feed: feed
                )
            }
            feed.unreadCount = Self.unreadIncrement(for: feed.articles ?? [])

            context.insert(feed)
            appendLog(
                kind: .info,
                message: L10n.feedLogAdded,
                to: feed,
                context: context
            )
            try context.save()

            if let sqliteDatabase {
                try mirrorFeedToSQLite(feed, context: context, database: sqliteDatabase)
            }
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? L10n.feedErrorAddFailed
        } catch {
            errorMessage = L10n.feedErrorAddFailed
        }

    }
```

Entferne die komplette Methode `refreshFeed(_:context:sqliteDatabase:)` (die deprecated Variante,
NICHT `refreshFeed(feedID:sqliteDatabase:)`, die bleibt):

```swift
    @MainActor
    @available(*, deprecated, message: "Legacy SwiftData-Fallback. Produktions-Refresh nutzt `refreshFeed(feedID:sqliteDatabase:)`.")
    func refreshFeed(
        _ feed: Feed?,
        context: ModelContext,
        sqliteDatabase: FeedivoDatabase? = nil
    ) async {
        guard !isLoading else {
            // Statt stillen Drops: Nutzer bekommt Feedback, dass bereits
            // aktualisiert wird, und sein Aufruf nicht verloren geht.
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        guard let feed else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await refreshFeedContents(feed, context: context)
            if let sqliteDatabase {
                try mirrorFeedToSQLite(feed, context: context, database: sqliteDatabase)
            }
            await notifyFeedRefresh([result.feedNotification])
            await notifyRuleNotifications(result.ruleNotifications)
        } catch let error as LocalizedError {
            appendLog(
                kind: .error,
                message: error.errorDescription ?? L10n.feedErrorParsingFailed,
                to: feed,
                context: context
            )
            try? context.save()
            errorMessage = error.errorDescription ?? L10n.feedErrorParsingFailed
        } catch {
            appendLog(
                kind: .error,
                message: L10n.feedErrorParsingFailed,
                to: feed,
                context: context
            )
            try? context.save()
            errorMessage = L10n.feedErrorParsingFailed
        }

        isLoading = false
    }
```

Entferne die komplette Methode `refreshAllFeeds(_:context:sqliteDatabase:)` (die deprecated
Variante mit `[Feed]`, NICHT `refreshAllFeeds(sqliteDatabase:)`, die bleibt):

```swift
    @available(*, deprecated, message: "Legacy SwiftData-Fallback. Produktiver Sammel-Refresh nutzt `refreshAllFeeds(sqliteDatabase:)`.")
    @MainActor
    func refreshAllFeeds(
        _ feeds: [Feed],
        context: ModelContext,
        sqliteDatabase: FeedivoDatabase? = nil
    ) async {
        guard !isLoading else {
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        guard !feeds.isEmpty else {
            return
        }

        isLoading = true
        errorMessage = nil
        recentRefreshStatus = nil
        refreshItems = feeds.map { feed in
            FeedRefreshItem(
                feedID: feed.id,
                feedTitle: feed.title,
                feedURL: feed.url,
                status: .pending
            )
        }
        let refreshStatusStart = ContinuousClock().now
        operationProgress = FeedOperationProgress(
            title: L10n.feedProgressRefreshAllTitle,
            completedCount: 0,
            totalCount: feeds.count
        )
        var failedFeedTitles: [String] = []
        var notificationResults: [FeedRefreshNotificationResult] = []
        var ruleNotificationResults: [RuleNotificationResult] = []

        defer {
            isLoading = false
            operationProgress = nil
        }

        // M4: Regeln einmal für den gesamten Refresh holen statt pro Feed neu
        // zu fetchen. Wird an refreshFeedContents weitergereicht.
        let refreshRules = (try? context.fetch(FetchDescriptor<Rule>())) ?? []

        // Feed-Refresh läuft bewusst gedrosselt. Bei vielen Feeds bleibt die App
        // dadurch bedienbarer und Server werden weniger hart getroffen.
        for feedBatch in feedBatches(from: feeds) {
            updateRefreshItemStatuses(
                for: feedBatch.map(\.id),
                status: .refreshing
            )

            await withTaskGroup(of: FeedRefreshOutcome.self) { group in
                for feed in feedBatch {
                    group.addTask { @MainActor in
                        do {
                            let result = try await self.refreshFeedContents(
                                feed,
                                context: context,
                                rules: refreshRules,
                                savesImmediately: false
                            )
                            self.updateRefreshItemStatus(for: feed.id, status: .succeeded)
                            return .success(result)
                        } catch let error as LocalizedError {
                            self.appendLog(
                                kind: .error,
                                message: error.errorDescription ?? L10n.feedErrorParsingFailed,
                                to: feed,
                                context: context
                            )
                            self.updateRefreshItemStatus(for: feed.id, status: .failed)
                            return .failure(feed.title)
                        } catch {
                            self.appendLog(
                                kind: .error,
                                message: L10n.feedErrorParsingFailed,
                                to: feed,
                                context: context
                            )
                            self.updateRefreshItemStatus(for: feed.id, status: .failed)
                            return .failure(feed.title)
                        }
                    }
                }

                for await outcome in group {
                    switch outcome {
                    case .success(let result):
                        notificationResults.append(result.feedNotification)
                        ruleNotificationResults.append(contentsOf: result.ruleNotifications)
                    case .failure(let failedTitle):
                        failedFeedTitles.append(failedTitle)
                    }

                    incrementOperationProgress()
                }
            }

            try? context.save()
            if let sqliteDatabase {
                for feed in feedBatch {
                    try? mirrorFeedToSQLite(feed, context: context, database: sqliteDatabase)
                }
            }
        }

        await notifyFeedRefresh(notificationResults)
        await notifyRuleNotifications(ruleNotificationResults)
        await waitForMinimumRefreshStatusDuration(since: refreshStatusStart)

        recentRefreshStatus = FeedRefreshStatusSummary(
            newArticleCount: notificationResults.reduce(0) { $0 + $1.newArticleCount },
            failedFeedCount: failedFeedTitles.count,
            totalFeedCount: feeds.count
        )

        if failedFeedTitles.isEmpty {
            lastRefreshOutcome = .success
        } else if failedFeedTitles.count < feeds.count {
            // Teilfehler: einige Feeds konnten nicht aktualisiert werden, der
            // Rest aber schon. Status „partial" statt pauschal „failed".
            lastRefreshOutcome = .partial(failedCount: failedFeedTitles.count)
            errorMessage = L10n.feedErrorRefreshAllPartial(
                failedFeedTitles.count,
                feedTitles: failedFeedTitles.joined(separator: ", ")
            )
        } else {
            lastRefreshOutcome = .failure
            errorMessage = L10n.feedErrorRefreshAllPartial(
                failedFeedTitles.count,
                feedTitles: failedFeedTitles.joined(separator: ", ")
            )
        }
    }
```

Entferne die komplette Methode `deleteFeed(_:context:)` (die deprecated Variante, NICHT
`deleteFeed(feedID:sqliteDatabase:)`, die bleibt):

```swift
    @available(*, deprecated, message: "Legacy SwiftData-Fallback. Produktions-Löschen nutzt `deleteFeed(feedID:sqliteDatabase:)`.")
    @MainActor
    func deleteFeed(_ feed: Feed?, context: ModelContext) {
        guard let feed else {
            return
        }

        errorMessage = nil
        do {
            let feedID = feed.id
            let descriptor = FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.feedID == feedID
                }
            )
            let articles = try context.fetch(descriptor)

            for article in articles {
                context.delete(article)
            }

            // .nullify statt .cascade (CloudKit-kompatibel): LogEntries manuell
            // löschen, sonst verwaisten sie nach dem Feed-Löschen.
            for entry in feed.logEntries ?? [] {
                context.delete(entry)
            }

            context.delete(feed)

            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 3: Toten SwiftData-Zweig von `importOPMLFeeds` entfernen**

Von:

```swift
        if let sqliteDatabase {
            let service = SQLiteFeedSubscriptionService(
                database: sqliteDatabase,
                fetchFeed: fetchFeed,
                discoverFaviconURL: discoverFaviconURL
            )
            let sqliteResult = try await service.importOPMLFeeds(
                opmlFeeds,
                allowsDuplicates: allowsDuplicates,
                refreshAfterImport: refreshAfterImport,
                refreshIntervalMinutes: refreshIntervalMinutes,
                context: context
            )
            if !sqliteResult.failedFeedTitles.isEmpty {
                errorMessage = L10n.feedErrorRefreshAllPartial(
                    sqliteResult.failedFeedTitles.count,
                    feedTitles: sqliteResult.failedFeedTitles.joined(separator: ", ")
                )
            }
            if sqliteResult.imported > 0 {
                SQLiteDataInvalidation.bumpStatusVersion()
            }

            return OPMLImportResult(
                total: sqliteResult.total,
                imported: sqliteResult.imported,
                skippedDuplicates: sqliteResult.skippedDuplicates
            )
        }

        guard let context else {
            errorMessage = L10n.feedErrorAddFailed
            return OPMLImportResult(total: opmlFeeds.count, imported: 0, skippedDuplicates: 0)
        }

        var knownFeedURLs = Set(existingFeeds.map { normalizedFeedURL($0.url) })
        var importedCount = 0
        var skippedDuplicateCount = 0
        var failedFeedTitles: [String] = []

        // Phase 1: Deduplizierung und Feed-Erstellung (sequenziell — URL-Set darf nicht concurrent mutiert werden)
        var feedsToRefresh: [Feed] = []
        for opmlFeed in opmlFeeds {
            let cleanedURL = opmlFeed.xmlURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedURL.isEmpty else {
                continue
            }

            let normalizedURL = normalizedFeedURL(cleanedURL)
            guard allowsDuplicates || knownFeedURLs.insert(normalizedURL).inserted else {
                skippedDuplicateCount += 1
                continue
            }

            let feed = Feed(
                url: cleanedURL,
                title: opmlFeed.title.trimmingCharacters(in: .whitespacesAndNewlines),
                siteURL: opmlFeed.htmlURL,
                followedAt: Date(),
                folderName: opmlFeed.folderName,
                refreshIntervalMinutes: BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes)
            )
            context.insert(feed)
            appendLog(
                kind: .info,
                message: L10n.feedLogImportedFromOPML,
                to: feed,
                context: context
            )
            importedCount += 1
            feedsToRefresh.append(feed)
        }

        // Phase 2: Neue Feeds in begrenzten Gruppen abrufen. So bleibt Netzwerk-I/O
        // parallel, ohne bei großen OPML-Imports alle Feeds gleichzeitig anzustoßen.
        if refreshAfterImport && !feedsToRefresh.isEmpty {
            operationProgress = FeedOperationProgress(
                title: L10n.feedProgressOPMLImportTitle,
                completedCount: 0,
                totalCount: feedsToRefresh.count
            )
        }

        if refreshAfterImport {
            for feedBatch in feedBatches(from: feedsToRefresh) {
                await withTaskGroup(of: String?.self) { group in
                    for feed in feedBatch {
                        group.addTask { @MainActor in
                            do {
                                _ = try await self.refreshFeedContents(feed, context: context)
                                return nil
                            } catch let error as LocalizedError {
                                self.appendLog(
                                    kind: .error,
                                    message: error.errorDescription ?? L10n.feedErrorParsingFailed,
                                    to: feed,
                                    context: context
                                )
                                try? context.save()
                                return feed.title
                            } catch {
                                self.appendLog(
                                    kind: .error,
                                    message: L10n.feedErrorParsingFailed,
                                    to: feed,
                                    context: context
                                )
                                try? context.save()
                                return feed.title
                            }
                        }
                    }

                    for await failedTitle in group {
                        if let failedTitle {
                            failedFeedTitles.append(failedTitle)
                        }

                        incrementOperationProgress()
                    }
                }
            }
        }

        try context.save()
        if let sqliteDatabase {
            for feed in feedsToRefresh {
                try? mirrorFeedToSQLite(feed, context: context, database: sqliteDatabase)
            }
        }
        if !failedFeedTitles.isEmpty {
            errorMessage = L10n.feedErrorRefreshAllPartial(
                failedFeedTitles.count,
                feedTitles: failedFeedTitles.joined(separator: ", ")
            )
        }

        return OPMLImportResult(
            total: opmlFeeds.count,
            imported: importedCount,
            skippedDuplicates: skippedDuplicateCount
        )
    }
```

zu:

```swift
        let service = SQLiteFeedSubscriptionService(
            database: sqliteDatabase,
            fetchFeed: fetchFeed,
            discoverFaviconURL: discoverFaviconURL
        )
        let sqliteResult = try await service.importOPMLFeeds(
            opmlFeeds,
            allowsDuplicates: allowsDuplicates,
            refreshAfterImport: refreshAfterImport,
            refreshIntervalMinutes: refreshIntervalMinutes
        )
        if !sqliteResult.failedFeedTitles.isEmpty {
            errorMessage = L10n.feedErrorRefreshAllPartial(
                sqliteResult.failedFeedTitles.count,
                feedTitles: sqliteResult.failedFeedTitles.joined(separator: ", ")
            )
        }
        if sqliteResult.imported > 0 {
            SQLiteDataInvalidation.bumpStatusVersion()
        }

        return OPMLImportResult(
            total: sqliteResult.total,
            imported: sqliteResult.imported,
            skippedDuplicates: sqliteResult.skippedDuplicates
        )
    }
```

**Wichtig:** Diese Vereinfachung setzt voraus, dass Task 17 (`SQLiteFeedSubscriptionService.swift`)
den `context:`-Parameter auf `importOPMLFeeds` bereits entfernt hat. Falls Task 17 in deiner
Ausführungsreihenfolge noch nicht abgeschlossen ist, lasse den Aufruf vorerst mit
`context: nil` stehen (`context: context` durch `context: nil` ersetzen) und vermerke im Report,
dass Task 17 diesen Aufruf noch weiter vereinfachen wird. Auch die Funktionssignatur
`importOPMLFeeds(_:existingFeeds:allowsDuplicates:refreshAfterImport:refreshIntervalMinutes:context:sqliteDatabase:)`
selbst behält vorerst ihren `context: ModelContext? = nil`-Parameter — dieser wird zusammen mit
`existingFeeds: [Feed]` erst final entfernt, sobald auch der letzte Aufrufer (Task 24s
Model-Löschung) das erzwingt; bis dahin bleiben beide Parameter unbenutzt aber kompilierbar
(Swift erlaubt unbenutzte Parameter). Falls der Compiler eine "unused parameter"-Warnung zeigt,
ist das erwartet und kein Fehler.

- [ ] **Step 4: `RuleApplicationResult`/`applyRulesWithNotifications`-Bezug prüfen**

Nach den Steps 2-3 verweist `FeedViewModel.swift` nicht mehr auf
`RuleEngine.applyRulesWithNotifications(rules:to:feed:)` (nur noch auf
`RuleEngine.applyRulesWithNotifications` innerhalb von `refreshFeedContents`, das in Step 5
entfernt wird). Kein Handlungsbedarf in diesem Schritt — nur zur Orientierung für den nächsten
Schritt.

- [ ] **Step 5: Private Helfer entfernen, die nur den toten Pfaden dienten**

Entferne `mirrorFeedToSQLite(_:context:database:)`:

```swift
    // BRÜCKEN-SCHREIBPFAD (hart isoliert, Plan T8): Spiegelt einen SwiftData-
    // `Feed` nach SQLite (`FeedRecord` + Artikel). Wird nur aus den verbleibenden
    // SwiftData-first Pfaden (addFeed/rename/restore) aufgerufen, die ihrerseits
    // noch auf das SwiftData-`Feed`-Modell angewiesen sind, weil `Article.feed`/
    // `Tag.feeds` Relationships leben. Sobald diese Pfade SQLite-only sind,
    // entfällt diese Funktion. Keine neuen Reads hierüber — Reads laufen über
    // `FeedStore`/`ArticleStore`.
    @MainActor
    private func mirrorFeedToSQLite(
        _ feed: Feed,
        context: ModelContext,
        database: FeedivoDatabase
    ) throws {
        let feedID = feed.id.uuidString
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(
                id: feedID,
                url: feed.url,
                title: feed.title,
                websiteURL: feed.siteURL,
                faviconURL: feed.faviconURL,
                folderName: feed.folderName,
                refreshIntervalMinutes: feed.refreshIntervalMinutes,
                lastRefreshedAt: feed.lastRefreshed,
                lastETag: feed.httpETag,
                lastModified: feed.httpLastModified,
                lastBodyHash: feed.httpContentHash,
                lastHTTPStatusCode: feed.lastHTTPStatusCode,
                unreadCount: feed.unreadCount,
                createdAt: feed.followedAt ?? Date(),
                updatedAt: Date()
            )
        )

        let articles = try articlesForSQLiteMirror(feed: feed, context: context)
        let inputs = articles.map { article in
            ArticleUpsertInput(
                feedID: feedID,
                sourceID: article.sourceID,
                link: article.link,
                title: article.title,
                summary: article.summary,
                content: article.content,
                imageURL: article.imageURL,
                author: article.author,
                publishedAt: article.publishedAt,
                arrivedAt: article.publishedAt ?? feed.lastRefreshed ?? Date()
            )
        }

        _ = try ArticleStore(database: database).upsert(inputs)
        let unreadCount = try ArticleStatusStore(database: database).unreadCount(feedID: feedID)
        try feedStore.setUnreadCount(unreadCount, feedID: feedID)
    }
```

Entferne `articlesForSQLiteMirror(feed:context:)`:

```swift
    @MainActor
    private func articlesForSQLiteMirror(feed: Feed, context: ModelContext) throws -> [Article] {
        let feedID = Optional(feed.id)
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID
            }
        )
        descriptor.sortBy = [
            SortDescriptor(\.publishedAt, order: .reverse),
            SortDescriptor(\.id, order: .reverse)
        ]
        return try context.fetch(descriptor)
    }
```

Entferne `refreshFeedContents(_:context:rules:savesImmediately:)` komplett (die gesamte Methode
von `@MainActor private func refreshFeedContents(` bis zu ihrer schließenden `}`, direkt vor dem
Kommentar zu `unreadIncrement(for:)`).

Entferne `existingArticlesByIdentity(for:context:)`:

```swift
    private func existingArticlesByIdentity(for feed: Feed, context: ModelContext) throws -> [String: Article] {
        let feedID = Optional(feed.id)
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID
            }
        )
        descriptor.propertiesToFetch = Article.refreshLookupPropertiesToFetch
        let articles = try context.fetch(descriptor)
        var articlesByIdentity: [String: Article] = [:]
        for article in articles {
            for identityKey in articleIdentityKeys(article) where articlesByIdentity[identityKey] == nil {
                articlesByIdentity[identityKey] = article
            }
        }

        return articlesByIdentity
    }
```

Entferne `appendLog(kind:message:to:context:)`:

```swift
    @MainActor
    private func appendLog(
        kind: FeedLogEntryKind,
        message: String,
        to feed: Feed,
        context: ModelContext
    ) {
        let entry = FeedLogEntry(kind: kind, message: message, feed: feed)
        context.insert(entry)
        var logEntries = feed.logEntries ?? []
        logEntries.append(entry)
        feed.logEntries = logEntries
        pruneLogEntries(for: feed, context: context)
    }
```

Entferne `pruneLogEntries(for:context:)`:

```swift
    @MainActor
    private func pruneLogEntries(for feed: Feed, context: ModelContext) {
        let entriesToDelete = (feed.logEntries ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .dropFirst(20)

        for entry in entriesToDelete {
            context.delete(entry)
        }
    }
```

- [ ] **Step 6: Verwaiste weitere private Helfer prüfen und entfernen**

Nach Step 5 sind folgende private Helfer nur noch vom (jetzt entfernten) `refreshFeedContents`
aufgerufen worden — prüfe per `grep -n "existingArticle(in:\|updateMissingArticleImages(\|updateStoredArticleContent(\|enrichedArticlesByIdentity(\|enrichArticleImagesIfNeeded(\|parsedArticleNeedsPageImage(\|isMissingImage(\|articleIdentityKeys(_ article: Article\|faviconURL(for:" Feedivo/ViewModels/FeedViewModel.swift`,
ob sie jetzt 0 Aufrufer haben (nur noch ihre eigene Definition). Für jeden Helfer mit 0 verbleibenden
Aufrufern: Methode komplett entfernen. Erwartet werden (aber verifiziere jeden einzeln, bevor du
löschst — manche werden evtl. noch von `addFeed(urlString:sqliteDatabase:)`s Closure-Defaults im
`init` benötigt, z. B. via `enrichArticleImages`-Property, die im Konstruktor auf
`FeedService.enrichArticleImagesIfNeeded` zeigt — das ist eine andere, gleichnamige Funktion in
einer anderen Datei und bleibt unangetastet):
`existingArticle(in:for:)`, `updateMissingArticleImages(in:from:)`,
`updateStoredArticleContent(in:from:)`, `enrichedArticlesByIdentity(for:)`,
`articleIdentityKeys(_ article: Article)` (Achtung: NICHT `articleIdentityKeys(for parsedArticle:
ParsedArticle)` — das bleibt, da es weiterhin von `primaryArticleIdentity`/`enrichedArticlesByIdentity`
gebraucht wird, falls diese bleiben), `faviconURL(for:)` (falls nicht mehr von
`addFeed(urlString:sqliteDatabase:)`-Pfad gebraucht — prüfen, ob `SQLiteFeedSubscriptionService`
seine eigene `faviconURL`-Logik hat und diese hier komplett verwaist ist).

Falls du unsicher bist, ob ein Helfer wirklich verwaist ist, LÖSCHE IHN NICHT — lass ihn stehen,
Swift kompiliert unbenutzte private Methoden ohne Fehler (nur eine Warnung), und vermerke die
Unsicherheit im Report. Es ist besser, eine harmlose tote private Methode zu übersehen, als
versehentlich eine noch gebrauchte zu löschen.

- [ ] **Step 7: `import SwiftData` prüfen**

Nach den obigen Schritten: prüfe per `grep -n "\bModelContext\b\|\bFetchDescriptor\b\|#Predicate" Feedivo/ViewModels/FeedViewModel.swift`,
ob noch SwiftData-API-Aufrufe übrig sind (erwartet: nein, außer evtl. im noch nicht bereinigten
`importOPMLFeeds`-Signatur-Rest aus Step 3, falls Task 17 noch nicht lief). Falls 0 Treffer:
`import SwiftData` entfernen.

- [ ] **Step 8: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -80`
Erwartung: Build schlägt fehl (Tests referenzieren noch entfernte Methoden) — nächster Schritt
behebt das.

- [ ] **Step 9: `FeedViewModelTests.swift` bereinigen**

Lies die Datei komplett (2610 Zeilen, ~53 Tests). Entferne jeden `@Test func`, der eine der in
Step 2 entfernten Methoden aufruft (`renameFeed(_:displayTitle:context:)`,
`restoreOriginalFeedTitle(_:context:)`, `addFeed(urlString:context:sqliteDatabase:)` mit einem
echten `context`-Argument, `refreshFeed(_:context:sqliteDatabase:)`,
`refreshAllFeeds(_:context:sqliteDatabase:)` mit `[Feed]`-Argument, `deleteFeed(_:context:)`) —
erwartet werden ca. 28 Testfunktionen, u. a. `addFeedLehntDuplikatMitBekannterUrlAb`,
`addFeedLegtNeuenFeedAnWennUrlNochUnbekannt`, mehrere `importOPMLFeeds...`/`context`-basierte
Tests, `renameFeedSpeichertAnzeigenamenUndBehältOriginalnamen`,
`restoreOriginalFeedTitleSetztAnzeigenamenZurueck`, alle `deleteFeed...`-Tests (5 Stück),
`refreshFeedFuegtNurNeueArtikelHinzuUndAktualisiertMetadaten` und ihre ~10 `context`-basierten
Geschwister-Tests. Behalte alle Tests mit `MitSQLiteDatabase` im Namen (z. B.
`refreshAllFeedsMitSQLiteDatabaseNutztSQLiteFirstOhneDoppeltenAbruf`,
`refreshAllFeedsMitSQLiteDatabaseWendetHideUndNotifyRegelnAn`,
`refreshAllFeedsMitSQLiteDatabaseWendetAssignTagRegelnAn`),
`addFeedMitSQLiteDatabaseLegtArtikelNurInSQLiteAn`,
`opmlImportPreviewDelegiertAnSQLiteSubscriptionService`,
`opmlImportPreviewOhneSQLiteDatabaseLiefertLeereListe`,
`importOPMLFeedsSpiegeltNeueFeedsNachSQLite`,
`unreadIncrementZaehltKeineGelesenenOderVerstecktenArtikel`. Prüfe den Test
`opmlFeedsForExportNutztAktuelleFeedMetadaten` separat: er ruft
`FeedViewModel.opmlFeedsForExport(from: [Feed])` auf — diese statische Methode bleibt bestehen
(nicht Teil der in Step 2 entfernten Liste), also bleibt auch dieser Test unverändert.

- [ ] **Step 10: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -80`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests 2>&1 | tail -100`
Erwartung: alle verbleibenden Tests grün außer den 2 bekannten, nur unter Volllast flakey
(`refreshAllFeedsMitSQLiteDatabaseNutztSQLiteFirstOhneDoppeltenAbruf`,
`refreshAllFeedsMitSQLiteDatabaseMeldetFeedBenachrichtigungen` — siehe Global Constraints).

- [ ] **Step 11: Commit**

```bash
git add Feedivo/ViewModels/FeedViewModel.swift FeedivoTests/FeedViewModelTests.swift
git commit -m "Remove dead SwiftData bridge methods and helpers from FeedViewModel"
```

---

## Task 16: `ArticleRetentionCleanupService.swift` + `ArticleRetentionCleanupServiceTests.swift` bereinigen

**Files:**
- Modify: `Feedivo/Services/ArticleRetentionCleanupService.swift`
- Modify: `FeedivoTests/ArticleRetentionCleanupServiceTests.swift`

**Interfaces:**
- Produces: `removeExpiredSQLiteArticles(database:isEnabled:retentionDays:minimumArticlesPerFeed:includeProtectedArticles:now:)`
  (der Basis-Overload ohne `in`-Parameter) bleibt unverändert und wird zum EINZIGEN verbleibenden
  Overload (genutzt von `FeedivoApp.swift`, `FeedPropertiesView.swift`, `SettingsView.swift` —
  diese rufen bereits den parameterlosen Overload auf, nicht den `in _: ModelContext?`-Bridge-Overload).
- Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -rn "removeExpiredSQLiteArticles(" Feedivo`

Erwartung: `FeedivoApp.swift`, `FeedPropertiesView.swift`, `SettingsView.swift` rufen alle den
Overload OHNE `in:`-Parameter auf (`removeExpiredSQLiteArticles(database:isEnabled:...)`). Falls
einer dieser Aufrufer tatsächlich `in:` übergibt: STOPPEN, BLOCKED melden.

- [ ] **Step 2: Vestigialen `in _: ModelContext?`-Overload entfernen**

Von:

```swift
    @MainActor
    @discardableResult
    static func removeExpiredSQLiteArticles(
        in _: ModelContext? = nil,
        database: FeedivoDatabase,
        isEnabled: Bool,
        retentionDays: Int,
        minimumArticlesPerFeed: Int = ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
        includeProtectedArticles: Bool = false,
        now: Date = Date()
    ) throws -> Int {
        try removeExpiredSQLiteArticles(
            database: database,
            isEnabled: isEnabled,
            retentionDays: retentionDays,
            minimumArticlesPerFeed: minimumArticlesPerFeed,
            includeProtectedArticles: includeProtectedArticles,
            now: now
        )
    }

    private static func shouldRemove(
```

zu:

```swift
    private static func shouldRemove(
```

- [ ] **Step 3: `import SwiftData` entfernen**

Nach Step 2 gibt es keinen `ModelContext`-Bezug mehr in der Datei. Entferne `import SwiftData` vom
Dateikopf (Zeile 3), `import GRDB` und `import Foundation` bleiben.

- [ ] **Step 4: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: Build schlägt fehl (Tests nutzen noch den entfernten Overload mit `in:`) — nächster
Schritt behebt das.

- [ ] **Step 5: `ArticleRetentionCleanupServiceTests.swift` migrieren**

Lies die Datei komplett. Die 5 verbleibenden `sqliteCleanup...`-Tests rufen aktuell
`removeExpiredSQLiteArticles(in: context, database: database, ...)` auf, wobei `context` aus einem
lokalen `testContext()`-Helfer stammt, der einen echten `ModelContainer` aufbaut und einen `Feed(...)`
einfügt — rein um den jetzt entfernten Parameter zu befüllen. Ersetze in jedem der 5 Tests
`removeExpiredSQLiteArticles(in: context, database: database, ...)` durch
`removeExpiredSQLiteArticles(database: database, ...)` (den `in: context,`-Parameter entfernen,
alle anderen Argumente unverändert lassen). Entferne danach den `testContext()`-Helfer und den
`let context = try testContext()`-Aufruf am Anfang jedes der 5 Tests, falls `context` sonst nirgends
im jeweiligen Testkörper mehr gebraucht wird (prüfe pro Test, ob `context` noch anderweitig
verwendet wird, bevor du die Zeile entfernst — erwartet: nein, `context` diente ausschließlich dem
jetzt entfernten Parameter). Falls nach dem Entfernen aller `context`-Nutzungen `import SwiftData`
am Kopf der Testdatei nicht mehr gebraucht wird, ebenfalls entfernen.

- [ ] **Step 6: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleRetentionCleanupServiceTests 2>&1 | tail -60`
Erwartung: alle 7 Tests grün.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/ArticleRetentionCleanupService.swift FeedivoTests/ArticleRetentionCleanupServiceTests.swift
git commit -m "Remove vestigial ModelContext parameter from ArticleRetentionCleanupService"
```

---

## Task 17: `SQLiteFeedSubscriptionService.swift` + `SQLiteFeedSubscriptionServiceTests.swift` bereinigen

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift`
- Modify: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`

**Interfaces:**
- Produces: `addFeed(urlString:refreshIntervalMinutes:)`,
  `importOPMLFeeds(_:allowsDuplicates:refreshAfterImport:refreshIntervalMinutes:)` (beide OHNE
  `context:`-Parameter) bleiben als einzige Signaturen bestehen.
- Consumes: Task 15 (`FeedViewModel.swift`) ruft diese Methoden auf — falls Task 15 bereits
  abgeschlossen ist, dort ggf. den verbliebenen `context: context`/`context: nil`-Parameter aus dem
  Aufruf entfernen (siehe Step 5 unten).

- [ ] **Step 1: Verifikation**

Run: `grep -rn "shouldUseSwiftDataBridge\|saveSwiftDataBridge\|SwiftDataBridgeSettings" Feedivo FeedivoTests`

Erwartung: `shouldUseSwiftDataBridge`/`saveSwiftDataBridge` nur in dieser Datei; alle Produktions-
Aufrufer von `addFeed`/`importOPMLFeeds` auf diesem Service übergeben `context: nil` oder gar
keinen `context`.

- [ ] **Step 2: `context`-Parameter und Bridge-Logik aus `addFeed` entfernen**

Von:

```swift
    func addFeed(
        urlString: String,
        refreshIntervalMinutes: Int = 60,
        context: ModelContext? = nil
    ) async throws -> SQLiteFeedSubscriptionResult {
        let cleanedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            throw SQLiteFeedSubscriptionError.emptyURL
        }

        let parsedFeed = try await fetchFeed(cleanedURL)
        let feedStore = FeedStore(database: database)
        let candidateURLs = Set([cleanedURL, parsedFeed.sourceURL].map(normalizedFeedURL))
        let existingFeeds = try feedStore.feeds()
        let shouldWriteSwiftDataBridge = shouldUseSwiftDataBridge(context: context)
        let existingSwiftDataFeeds = shouldWriteSwiftDataBridge
            ? (try context?.fetch(FetchDescriptor<Feed>()) ?? [])
            : []
        guard !existingFeeds.contains(where: { candidateURLs.contains(normalizedFeedURL($0.url)) }),
              !existingSwiftDataFeeds.contains(where: { candidateURLs.contains(normalizedFeedURL($0.url)) }) else {
            throw SQLiteFeedSubscriptionError.duplicateFeed
        }
```

zu:

```swift
    func addFeed(
        urlString: String,
        refreshIntervalMinutes: Int = 60
    ) async throws -> SQLiteFeedSubscriptionResult {
        let cleanedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            throw SQLiteFeedSubscriptionError.emptyURL
        }

        let parsedFeed = try await fetchFeed(cleanedURL)
        let feedStore = FeedStore(database: database)
        let candidateURLs = Set([cleanedURL, parsedFeed.sourceURL].map(normalizedFeedURL))
        let existingFeeds = try feedStore.feeds()
        guard !existingFeeds.contains(where: { candidateURLs.contains(normalizedFeedURL($0.url)) }) else {
            throw SQLiteFeedSubscriptionError.duplicateFeed
        }
```

Und weiter unten in derselben Methode, von:

```swift
            if shouldWriteSwiftDataBridge {
                try saveSwiftDataBridge(feedRecord, context: context)
            }
        } catch {
            try? cleanupSQLiteSubscription(feedID: feedID)
            if shouldWriteSwiftDataBridge, let context {
                context.rollback()
            }
            throw error
        }
```

zu:

```swift
        } catch {
            try? cleanupSQLiteSubscription(feedID: feedID)
            throw error
        }
```

- [ ] **Step 3: `context`-Parameter und Bridge-Logik aus `importOPMLFeeds` entfernen**

Von:

```swift
    func importOPMLFeeds(
        _ opmlFeeds: [OPMLFeed],
        allowsDuplicates: Bool,
        refreshAfterImport: Bool,
        refreshIntervalMinutes: Int,
        context: ModelContext? = nil
    ) async throws -> SQLiteOPMLImportResult {
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)
        let logStore = FeedLogStore(database: database)
        let clampedRefreshInterval = BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes)
        let shouldWriteSwiftDataBridge = shouldUseSwiftDataBridge(context: context)
        let existingSwiftDataFeeds = shouldWriteSwiftDataBridge
            ? (try context?.fetch(FetchDescriptor<Feed>()) ?? [])
            : []
        var knownURLs = Set(
            (try feedStore.feeds().map(\.url) + existingSwiftDataFeeds.map(\.url))
                .map(normalizedFeedURL)
        )
```

zu:

```swift
    func importOPMLFeeds(
        _ opmlFeeds: [OPMLFeed],
        allowsDuplicates: Bool,
        refreshAfterImport: Bool,
        refreshIntervalMinutes: Int
    ) async throws -> SQLiteOPMLImportResult {
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)
        let logStore = FeedLogStore(database: database)
        let clampedRefreshInterval = BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes)
        var knownURLs = Set(
            try feedStore.feeds().map(\.url)
                .map(normalizedFeedURL)
        )
```

Danach, im weiteren Methodenkörper: entferne `let shouldWriteCurrentFeedBridge = shouldWriteSwiftDataBridge`
(die lokale Kopie pro Feed), und die drei Stellen, die davon abhängen:

Von:

```swift
            let shouldWriteCurrentFeedBridge = shouldWriteSwiftDataBridge
            var createdFolder: FeedFolderRecord?
```

zu:

```swift
            var createdFolder: FeedFolderRecord?
```

Von:

```swift
                if shouldWriteCurrentFeedBridge {
                    try saveSwiftDataBridge(feedRecord, context: context)
                }
            } catch {
                try? cleanupSQLiteSubscription(feedID: feedID)
                try? cleanupCreatedTags(createdTagIDs)
                try? cleanupCreatedFolder(createdFolder)
                if shouldWriteCurrentFeedBridge, let context {
                    context.rollback()
                }
                throw error
            }
```

zu:

```swift
            } catch {
                try? cleanupSQLiteSubscription(feedID: feedID)
                try? cleanupCreatedTags(createdTagIDs)
                try? cleanupCreatedFolder(createdFolder)
                throw error
            }
```

Von:

```swift
                if let refreshedFeed = try feedStore.feed(id: refreshResult.feedID) {
                    if shouldWriteCurrentFeedBridge {
                        try saveSwiftDataBridge(refreshedFeed, context: context)
                    }
                }
                } catch {
```

zu:

```swift
                } catch {
```

(Der `if let refreshedFeed = try feedStore.feed(id: refreshResult.feedID)`-Block diente
ausschließlich dazu, den Refresh-Feed erneut in die SwiftData-Brücke zu spiegeln — mit dem
Entfallen der Brücke wird der gesamte `if let refreshedFeed`-Block überflüssig und entfernt, nicht
nur sein Inhalt.)

- [ ] **Step 4: `shouldUseSwiftDataBridge`/`saveSwiftDataBridge` löschen**

Entferne die komplette Methode `shouldUseSwiftDataBridge(context:)`:

```swift
    private func shouldUseSwiftDataBridge(context: ModelContext?) -> Bool {
        guard context != nil else {
            return false
        }

        return UserDefaults.standard.object(forKey: SwiftDataBridgeSettings.isEnabledKey) as? Bool
            ?? SwiftDataBridgeSettings.defaultIsEnabled
    }
```

Entferne die komplette Methode `saveSwiftDataBridge(_:context:)` (inkl. ihres Doc-Kommentars, von
`// BRÜCKEN-SCHREIBPFAD...` bis zur schließenden `}` der Methode).

- [ ] **Step 5: Aufrufer in `FeedViewModel.swift` anpassen (falls Task 15 bereits gelaufen ist)**

Prüfe per `grep -n "SQLiteFeedSubscriptionService" Feedivo/ViewModels/FeedViewModel.swift`, ob
noch `context: context` oder `context: nil` an `service.addFeed(...)` oder
`service.importOPMLFeeds(...)` übergeben wird. Falls ja, entferne dort das `context:`-Argument
komplett aus dem jeweiligen Aufruf (die Methodensignaturen auf diesem Service haben den Parameter
jetzt nicht mehr). Falls Task 15 noch nicht gelaufen ist, überspringe diesen Schritt — der
verbleibende `context: context`-Aufruf in `FeedViewModel.swift` verhindert dann vorübergehend den
Build, was erwartet ist und von Task 15 behoben wird.

- [ ] **Step 6: `import SwiftData` prüfen**

Prüfe per `grep -n "ModelContext\|FetchDescriptor" Feedivo/Services/SQLiteFeedSubscriptionService.swift`,
ob noch SwiftData-Bezüge übrig sind (erwartet: 0). Falls 0 Treffer: `import SwiftData` entfernen.

- [ ] **Step 7: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -80`
Erwartung: Build schlägt fehl (Tests nutzen noch `context:`-Argumente) — nächster Schritt behebt
das.

- [ ] **Step 8: `SQLiteFeedSubscriptionServiceTests.swift` bereinigen**

Lies die Datei komplett (943 Zeilen, ~18 Tests). Entferne die ~12 Tests, die explizit die
SwiftData-Bridge testen (Namen wie `addFeedSpeichertSQLiteFeedUndSwiftDataBridgeOhneSwiftDataArtikel`,
`addFeedKannOhneSwiftDataBridgeLaufen`, `addFeedErkenntDuplikatAuchInSwiftDataBridge`,
`importOPMLAktualisiertSwiftDataBridgeNachErfolgreichemRefresh`,
`importOPMLUeberspringtDuplikatAusSwiftDataBridge`). Behalte die 3 "OPML-Importvorschau"-Tests
(`previewMarkiertDuplikateUndNichtErreichbareFeeds`,
`previewMeldetSichtbarenPrueffortschrittInBeidePhasen`,
`previewParalleelisiertBehaeltReihenfolgeUndStatus`) und jeden anderen Test, der `addFeed(urlString:refreshIntervalMinutes:)`
oder `importOPMLFeeds(...)` OHNE `context:`-Argument aufruft — passe deren Aufrufe an, falls sie
noch ein jetzt entferntes `context:`-Argument übergeben (Argument einfach weglassen).

- [ ] **Step 9: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -80`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests 2>&1 | tail -80`
Erwartung: alle verbleibenden Tests grün.

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Services/SQLiteFeedSubscriptionService.swift FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift Feedivo/ViewModels/FeedViewModel.swift
git commit -m "Remove SwiftData bridge from SQLiteFeedSubscriptionService"
```

(Nur `FeedViewModel.swift` mit hinzufügen, falls Step 5 dort tatsächlich etwas geändert hat.)

---

## Task 18: `ArticleExportServiceTests.swift` — Fixture-Migration

**Files:**
- Modify: `FeedivoTests/ArticleExportServiceTests.swift`

**Interfaces:** Keine Produktionsänderung — `ArticleExportService.swift` nutzt bereits
`ArticleExportSnapshot`/`ArticleReaderSnapshot` als Eingabetyp für seine produktiven Pfade.
Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Vorlage identifizieren**

Lies den Test `sqliteExportSnapshotNutztOfflineVolltextUndTags` (oder ähnlich benannt) in
`FeedivoTests/ArticleExportServiceTests.swift` — er konstruiert bereits `ArticleReaderSnapshot`
statt `Article`/`Feed`/`Tag` und dient als Vorlage für die Migration der übrigen ~25 Tests.

- [ ] **Step 2: Alle `Article(...)`/`Feed(...)`/`Tag(...)`-Fixtures auf `ArticleReaderSnapshot` umstellen**

Lies die komplette Datei. Für jeden Test, der `Article(...)`/`Feed(...)`/`Tag(...)` konstruiert und
dann an `ArticleExportService`/`ArticlePDFExportRenderer`/`ArticleExportSnapshot`-APIs übergibt:
ersetze die Konstruktion durch ein direktes `ArticleReaderSnapshot(...)` mit denselben Werten
(gleiche `title`/`summary`/`content`/`publishedAt`/etc., aber ohne den Umweg über `@Model`-Typen).
Nutze `sqliteExportSnapshotNutztOfflineVolltextUndTags` als Vorbild für die Feldbelegung
(insbesondere `tags: [ReaderArticleTagMetadata]` statt `Tag`-Objekte). Prüfe für jeden migrierten
Test per Vergleich mit der Vorlage, dass alle vom jeweiligen Test tatsächlich genutzten Felder
(z. B. `offlineContent`, `imageURL`) in der neuen Snapshot-Konstruktion vorhanden sind — die exakte
Zuordnung hängt vom jeweiligen Testinhalt ab, den du beim Lesen der Datei siehst.

- [ ] **Step 3: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -80`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportServiceTests 2>&1 | tail -100`
Erwartung: alle Tests grün, gleiche Assertions wie vorher (nur die Fixture-Konstruktion hat sich
geändert, nicht das erwartete Verhalten).

- [ ] **Step 4: Commit**

```bash
git add FeedivoTests/ArticleExportServiceTests.swift
git commit -m "Migrate ArticleExportServiceTests fixtures from @Model types to ArticleReaderSnapshot"
```

---

## Task 19: `SQLiteSidebarStateTests.swift` — Fixture-Migration

**Files:**
- Modify: `FeedivoTests/SQLiteSidebarStateTests.swift`

**Interfaces:** Keine Produktionsänderung. Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Toten `Feed(...)`-Fixture-Aufruf finden und migrieren**

Lies die Datei. Finde den Test `visibleSnapshotsFollowSQLiteVisibility` (oder ähnlich benannt), der
`Feed(url: ...)` konstruiert, nur um über `.id.uuidString` an eine UUID-Zeichenkette für
`FeedRecord(id: ...)` zu kommen. Ersetze `Feed(url: "...").id.uuidString` durch
`UUID().uuidString` (eine direkt erzeugte UUID-Zeichenkette — die Testlogik braucht nur eine
plausible, eindeutige ID, nicht das `Feed`-Objekt selbst).

- [ ] **Step 2: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteSidebarStateTests 2>&1 | tail -60`
Erwartung: alle 7 Tests grün.

- [ ] **Step 3: Commit**

```bash
git add FeedivoTests/SQLiteSidebarStateTests.swift
git commit -m "Remove Feed fixture dependency from SQLiteSidebarStateTests"
```

---

## Task 20: `FeedivoTests.swift` — tote Default-Werte-Tests entfernen

**Files:**
- Modify: `FeedivoTests/FeedivoTests.swift`

**Interfaces:** Keine Produktionsänderung. Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation**

Run: `grep -n "@Test func artikelArchivUndHiddenStatusHabenSichereDefaults\|@Test func feedBenachrichtigungenSindStandardmaessigDeaktiviert" FeedivoTests/FeedivoTests.swift`

Erwartung: beide Tests existieren, konstruieren `Article(...)`/`Feed(...)` nur um deren eigene
Default-Werte zu prüfen (kein Bezug zu SQLite-Verhalten).

- [ ] **Step 2: Beide Tests entfernen**

Entferne die kompletten `@Test func`-Blöcke `artikelArchivUndHiddenStatusHabenSichereDefaults` und
`feedBenachrichtigungenSindStandardmaessigDeaktiviert` aus `FeedivoTests/FeedivoTests.swift`. Alle
anderen Tests in dieser 663+ Zeilen langen Datei (FeedService/AppLanguage/InterfaceTextSize/Reader-
Typography/etc.) bleiben unverändert.

- [ ] **Step 3: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests 2>&1 | tail -100`
Erwartung: alle verbleibenden Tests grün.

- [ ] **Step 4: Commit**

```bash
git add FeedivoTests/FeedivoTests.swift
git commit -m "Remove dead Article/Feed default-value tests from FeedivoTests"
```

---

## Task 21: `AppIconBadgeServiceTests.swift` — toten Test entfernen

**Files:**
- Modify: `FeedivoTests/AppIconBadgeServiceTests.swift`

**Interfaces:** Keine Produktionsänderung. Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: Verifikation und Entfernen**

Lies die Datei. Entferne den `@Test func unreadCountZaehltGespeicherteFeedZaehler` (oder ähnlich
benannt) — der einzige Test, der `Feed(...)` konstruiert. Alle anderen 5 Tests
(`unreadCountAusSidebarSnapshotsSummiert`, `updateBadgeSetztUngelesenZaehlerWennAktiv`, etc.)
bleiben unverändert, sie nutzen bereits `FeedSidebarSnapshot`.

- [ ] **Step 2: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/AppIconBadgeServiceTests 2>&1 | tail -60`
Erwartung: alle 5 verbleibenden Tests grün.

- [ ] **Step 3: Commit**

```bash
git add FeedivoTests/AppIconBadgeServiceTests.swift
git commit -m "Remove dead Feed-based test from AppIconBadgeServiceTests"
```

---

## Task 22: `ArticleListQueryTests.swift` — verbleibende `Article`/`Feed`-Fixtures migrieren

**Files:**
- Modify: `FeedivoTests/ArticleListQueryTests.swift`

**Interfaces:** Keine Produktionsänderung. Consumes: Task 6 (`ArticleFilterOption.swift`) und
Task 8 (`ArticleSortOption.swift`) sollten bereits abgeschlossen sein, sonst schlägt der Build
schon vor diesem Task fehl (das ist in Ordnung, dieser Task behebt es).

- [ ] **Step 1: Drei betroffene Tests identifizieren**

Lies die Datei (nach Phase 2 bereits deutlich verkleinert). Finde:
`articleSortOptionSortiertArtikelNachBenutzerauswahl`,
`articleFilterOptionFiltertArtikelNachBenutzerauswahl`,
`articleInitialisiertDirekteFeedIDFuerSchnelleListenQueries`. Alle drei konstruieren
`Article(...)`/`Feed(...)`, um `ArticleSortOption.resolved(from:)`/`.label`,
`ArticleFilterOption.resolved(from:)`/`.label`, bzw. direkte `Article`-Feldzugriffe zu testen.

- [ ] **Step 2: `articleInitialisiertDirekteFeedIDFuerSchnelleListenQueries` entfernen**

Dieser Test prüft `Article(title:feed:).feedID == feed.id` — eine reine `@Model`-Eigenschaft ohne
SQLite-Äquivalent (die SQLite-Welt hat kein Analogon zu dieser direkten Feed-ID-Denormalisierung
auf einem in-memory-Objekt). Entferne den kompletten `@Test func`-Block.

- [ ] **Step 3: `articleSortOptionSortiertArtikelNachBenutzerauswahl`/`articleFilterOptionFiltertArtikelNachBenutzerauswahl` prüfen**

Diese beiden Tests riefen ursprünglich `ArticleSortOption.sorted(_:[Article])`/
`ArticleFilterOption.filtered(_:[Article])` auf — beide Methoden wurden in Task 8/6 bereits
entfernt. Falls diese Tests ausschließlich diese jetzt entfernten Methoden aufrufen, entferne sie
komplett (sie testen dann nur noch toten Code). Falls sie stattdessen nur `.resolved(from:)`/
`.label`/`.storageKey` (die lebendigen, `Article`-unabhängigen APIs) testen und `Article`/`Feed`
nur als unnötiges Beiwerk konstruieren, entferne nur die `Article(...)`/`Feed(...)`-Konstruktion
und ersetze sie durch die minimal nötigen Werte für den Rest der Assertions (meist reicht dann ein
reiner String-Vergleich ohne jede Objekt-Konstruktion). Lies den tatsächlichen Testinhalt, um zu
entscheiden, welcher Fall zutrifft.

- [ ] **Step 4: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListQueryTests 2>&1 | tail -80`
Erwartung: alle verbleibenden Tests grün.

- [ ] **Step 5: Commit**

```bash
git add FeedivoTests/ArticleListQueryTests.swift
git commit -m "Remove remaining Article/Feed fixture dependencies from ArticleListQueryTests"
```

---

## Task 23: Kleine, unabhängige Test-Aufräumarbeiten

**Files:**
- Delete: `FeedivoTests/RuleConditionTests.swift`
- Delete: `FeedivoTests/SmartFolderConditionTests.swift`
- Modify: `FeedivoTests/SQLiteAdminStoreTests.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

**Interfaces:** Keine Produktionsänderung. Consumes: keine Abhängigkeiten von anderen Tasks.

- [ ] **Step 1: `RuleConditionTests.swift` löschen**

Verifikation: `grep -n "@Test func" FeedivoTests/RuleConditionTests.swift` — erwartet genau 2 Tests
(`fieldEnumLiefertNilFuerUnbekanntenRawValue`, `fieldEnumLiefertEnumFuerBekanntenRawValue`), beide
testen `RuleCondition.fieldEnum`/`.operatorEnum` direkt auf dem `@Model`-Typ, kein SQLite-Äquivalent
nötig (`RuleConditionField`/`RuleConditionOperator`-Enums selbst sind bereits in
`SQLiteAdminStoreTests.swift` indirekt abgedeckt). Falls die Anzahl abweicht: STOPPEN, BLOCKED
melden.

```bash
rm FeedivoTests/RuleConditionTests.swift
```

- [ ] **Step 2: `SmartFolderConditionTests.swift` löschen**

Verifikation: `grep -n "@Test func" FeedivoTests/SmartFolderConditionTests.swift` — erwartet genau
2 Tests, gleiches Muster wie Step 1 (`SmartFolderCondition.fieldEnum`/`.operatorEnum` direkt auf dem
`@Model`-Typ). Falls die Anzahl abweicht: STOPPEN, BLOCKED melden.

```bash
rm FeedivoTests/SmartFolderConditionTests.swift
```

- [ ] **Step 3: Unbenutzten `testContext()`-Helfer aus `SQLiteAdminStoreTests.swift` entfernen**

Lies die Datei. Finde den privaten `testContext()`-Helfer, der einen `ModelContainer(for: Feed.self,
FeedFolder.self, ...)` aufbaut. Verifiziere per `grep -n "testContext()" FeedivoTests/SQLiteAdminStoreTests.swift`,
dass er von keinem der 6 echten Tests (`feedFolderStoreSpeichertUndSortiertOrdner`,
`feedStoreMutiertFeedVerwaltungSQLiteFirst`, `tagStoreMutiertTagsSQLiteFirst`,
`ruleStoreSpeichertRegelnMitConditionsUndTagSnapshot`, `ruleStoreMutiertRegelnSQLiteFirst`,
`smartFolderStoreSpeichertOrdnerMitConditionsUndSnapshots`) aufgerufen wird. Falls bestätigt:
entferne den kompletten `testContext()`-Helfer. Falls doch ein Test ihn aufruft: STOPPEN, BLOCKED
melden (das widerspricht der bisherigen Analyse).

- [ ] **Step 4: Gegenstandslosen Model-Datei-Inspektionstest aus `FeedivoAppSceneConfigurationTests.swift` entfernen**

Lies die relevante Stelle. Finde den Test, der eine der 9 `Feedivo/Models/*.swift`-Dateien per Pfad
liest und auf eine bestimmte Property-Deklaration prüft (z. B. ein CloudKit-Relationship-Regressions-
Test, der `Article.swift`s Quelltext nach `var tags: [Tag]?` durchsucht). Verifiziere per
`grep -n "Models/Article.swift\|Models/Feed.swift\|Models/Tag.swift\|Models/Rule.swift\|Models/SmartFolder" FeedivoTests/FeedivoAppSceneConfigurationTests.swift`,
welcher/welche Test(s) betroffen sind. Entferne genau diese(n) Test(s) — der Rest der sehr großen
Datei (dutzende andere Architektur-Konformitätstests) bleibt unverändert.

- [ ] **Step 5: Build und gescopte Tests**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -50`
Erwartung: BUILD SUCCEEDED.

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteAdminStoreTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests 2>&1 | tail -100`
Erwartung: grün außer den 5 bekannten vorbestehenden Fehlschlägen (siehe Global Constraints).

- [ ] **Step 6: Commit**

```bash
git add FeedivoTests/RuleConditionTests.swift FeedivoTests/SmartFolderConditionTests.swift FeedivoTests/SQLiteAdminStoreTests.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "Remove dead @Model-only tests: RuleCondition/SmartFolderCondition/unused test helpers"
```

---

## Task 24: Die 9 `@Model`-Klassen löschen (letzter Task)

**Files:**
- Delete: `Feedivo/Models/Article.swift`
- Delete: `Feedivo/Models/Feed.swift`
- Delete: `Feedivo/Models/FeedFolder.swift`
- Delete: `Feedivo/Models/FeedLogEntry.swift`
- Delete: `Feedivo/Models/Rule.swift`
- Delete: `Feedivo/Models/RuleCondition.swift`
- Delete: `Feedivo/Models/SmartFolder.swift`
- Delete: `Feedivo/Models/SmartFolderCondition.swift`
- Delete: `Feedivo/Models/Tag.swift`

**Interfaces:** Konsumiert die Ergebnisse ALLER vorherigen 23 Tasks. Dieser Task darf erst
gestartet werden, wenn Tasks 1–23 vollständig abgeschlossen und committet sind.

- [ ] **Step 1: Verbindliche Voraussetzungsprüfung**

Run: `grep -rln "\bArticle\b\|\bFeed\b\|\bFeedFolder\b\|\bFeedLogEntry\b\|\bRule\b\|\bRuleCondition\b\|\bSmartFolder\b\|\bSmartFolderCondition\b\|\bTag\b" Feedivo --include="*.swift" | grep -v "Feedivo/Models/"`

Erwartung: JEDER verbleibende Treffer außerhalb von `Feedivo/Models/` ist entweder (a) ein
False-Positive (Kommentar/String/anderer Bezeichner, der zufällig eines der 9 Wörter enthält, z. B.
`FeedRowView`, `RuleEngine`, `SmartFolderFormatter` selbst als Typname — `\b`-Wortgrenzen filtern
das nicht immer heraus) oder (b) ein SQLite-natives Pendant (`FeedRecord`, `TagRecord`,
`RuleSnapshot`, `SmartFolderRecord`, etc. — diese enthalten die 9 Wörter als Präfix, sind aber
andere Typen). Gehe jeden Treffer einzeln durch. Falls ein Treffer eine ECHTE Referenz auf einen
der 9 `@Model`-Typen ist (z. B. eine Funktionssignatur mit `: Article` oder `[Feed]` als
Parametertyp): STOPPEN — das bedeutet ein vorheriger Task ist unvollständig oder es gibt eine bisher
unentdeckte Abhängigkeit. BLOCKED melden mit der genauen Fundstelle, nicht selbst weiterlöschen.

Führe dieselbe Prüfung für `FeedivoTests` aus:
`grep -rln "\bArticle(\|\bFeed(\|\bFeedFolder(\|\bFeedLogEntry(\|\bRule(\|\bRuleCondition(\|\bSmartFolder(\|\bSmartFolderCondition(\|\bTag(" FeedivoTests --include="*.swift"`

Erwartung: 0 Treffer (jede direkte Konstruktion eines der 9 Typen in Tests sollte durch die
vorherigen 23 Tasks bereits entfernt/migriert sein).

- [ ] **Step 2: 9 Model-Dateien löschen**

```bash
rm Feedivo/Models/Article.swift
rm Feedivo/Models/Feed.swift
rm Feedivo/Models/FeedFolder.swift
rm Feedivo/Models/FeedLogEntry.swift
rm Feedivo/Models/Rule.swift
rm Feedivo/Models/RuleCondition.swift
rm Feedivo/Models/SmartFolder.swift
rm Feedivo/Models/SmartFolderCondition.swift
rm Feedivo/Models/Tag.swift
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -100`

Erwartung: BUILD SUCCEEDED. Falls der Build fehlschlägt, zeigt der Compiler exakt, welche Datei(en)
noch einen der 9 Typen referenzieren — das bedeutet Step 1 hat etwas übersehen. Behebe jede
gemeldete Stelle einzeln (nicht pauschal), indem du den verbleibenden Bezug per `grep` im
jeweiligen Kontext verstehst und analog zu den vorherigen Tasks entfernst. Falls die Korrektur
umfangreicher ist als ein einzeiliger Fix: STOPPEN, BLOCKED melden statt eigenmächtig zu
improvisieren.

- [ ] **Step 4: Finaler `import SwiftData`-Sweep**

Run: `grep -rln "import SwiftData" Feedivo FeedivoTests`

Erwartung: 0 Treffer. Falls doch welche auftauchen, öffne jede Datei und prüfe, ob der Import noch
gebraucht wird (z. B. für `ModelContext` in einem bisher unentdeckten Rest) — falls nicht mehr
gebraucht, entfernen.

- [ ] **Step 5: Volle gescopte Testverifikation**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests -only-testing:FeedivoTests/FeedViewModelTests -only-testing:FeedivoTests/RuleEngineTests -only-testing:FeedivoTests/ArticleListQueryTests -only-testing:FeedivoTests/SQLiteAdminStoreTests 2>&1 | tail -150`

Erwartung: grün außer den bekannten vorbestehenden Fehlschlägen aus den Global Constraints (5 in
`FeedivoAppSceneConfigurationTests`, die 2 flakey `FeedViewModelTests`). KEINE neuen Fehlschläge.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Delete all 9 SwiftData @Model classes — SwiftData fully removed from FeedivoMac"
```

---

## Abschluss

Nach Task 24: finaler Whole-Branch-Review über den kompletten Diff-Bereich dieser Phase (Merge-Base:
der Commit, auf dem Phase 3 aufsetzt), dispatcht auf dem leistungsfähigsten verfügbaren Modell.
Push nach `origin/main` nur nach expliziter Nutzerbestätigung (Session-Konvention).
