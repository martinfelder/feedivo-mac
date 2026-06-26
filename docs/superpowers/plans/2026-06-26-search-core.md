# Search Core Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first Feedivo search slice: `Cmd+F` opens a compact article-list search that can search the current view or all articles by title, summary, content, or everything.

**Architecture:** Keep search inside the existing article-list pipeline. Add a small testable search model next to `ArticleListQuery`, let `ArticleListPreparedArticles` apply search after existing sorting and filtering, and keep read/hidden display behavior in `ArticleListDisplayState`. The UI adds a compact search bar above the list and a focused command action for `Cmd+F`.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, `@Query`, `@FocusState`, `FocusedValues`, localized strings via `L10n` and `Localizable.xcstrings`.

---

## File Structure

- Modify `Feedivo/Views/ArticleList/ArticleListQuery.swift`
  - Add `ArticleSearchField`, `ArticleSearchScope`, `ArticleSearchQuery`.
  - Extend `ArticleListPreparedArticles.prepare(...)` with an optional search query.
- Modify `FeedivoTests/ArticleListQueryTests.swift`
  - Add unit tests for the search model and the prepared-articles pipeline.
- Modify `Feedivo/Views/ArticleList/ArticleListView.swift`
  - Add global article query for the `Alle Artikel` search scope.
  - Add search bar UI, focus handling, result empty state, and search query plumbing.
- Modify `Feedivo/App/ArticleCommandActions.swift`
  - Add a separate focused search command action so existing article actions
    remain untouched.
- Modify `Feedivo/App/ArticleCommands.swift`
  - Add `Suchen...` with `Cmd+F`.
- Modify `Feedivo/Resources/L10n.swift`
  - Add localized string accessors for search UI.
- Modify `Feedivo/Resources/Localizable.xcstrings`
  - Add German, English, French, and Italian strings for the first slice.
- Modify `FEATURES.md`
  - Mark Feature 9.1/9.2 as in progress or partially implemented after code lands.

---

### Task 1: Add Failing Search Model Tests

**Files:**
- Modify: `FeedivoTests/ArticleListQueryTests.swift`
- Later modify: `Feedivo/Views/ArticleList/ArticleListQuery.swift`

- [ ] **Step 1: Add failing tests for search matching**

Add these tests after `articleFilterOptionFaelltBeiUngueltigemRawValueAufStandardZurueck()`:

```swift
@Test func articleSearchQuerySuchtInTitelZusammenfassungUndInhalt() {
    let titleArticle = Article(title: "SwiftUI Suche", summary: "Andere Worte", content: "Noch mehr Text")
    let summaryArticle = Article(title: "Nachrichten", summary: "Apple veröffentlicht Beta", content: "Noch mehr Text")
    let contentArticle = Article(title: "Analyse", summary: "Andere Worte", content: "Readability extrahiert Volltext")
    let unrelatedArticle = Article(title: "Sport", summary: "Fussball", content: "Resultate")
    let articles = [titleArticle, summaryArticle, contentArticle, unrelatedArticle]

    #expect(
        ArticleSearchQuery(text: "swiftui", field: .title)
            .filtered(articles)
            .map(\.title) == ["SwiftUI Suche"]
    )
    #expect(
        ArticleSearchQuery(text: "BETA", field: .summary)
            .filtered(articles)
            .map(\.title) == ["Nachrichten"]
    )
    #expect(
        ArticleSearchQuery(text: "volltext", field: .content)
            .filtered(articles)
            .map(\.title) == ["Analyse"]
    )
    #expect(
        ArticleSearchQuery(text: "apple", field: .all)
            .filtered(articles)
            .map(\.title) == ["Nachrichten"]
    )
}

@Test func articleSearchQueryIgnoriertLeerzeichenUndLeereSucheFiltertNicht() {
    let firstArticle = Article(title: "Erster Treffer", summary: "Swift", content: nil)
    let secondArticle = Article(title: "Zweiter Treffer", summary: "Mac", content: nil)
    let articles = [firstArticle, secondArticle]

    #expect(
        ArticleSearchQuery(text: "  swift  ", field: .all)
            .filtered(articles)
            .map(\.title) == ["Erster Treffer"]
    )
    #expect(
        ArticleSearchQuery(text: "   ", field: .all)
            .filtered(articles)
            .map(\.title) == ["Erster Treffer", "Zweiter Treffer"]
    )
}
```

- [ ] **Step 2: Run tests and verify they fail for missing types**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListQueryTests test
```

Expected: build fails with errors like `Cannot find 'ArticleSearchQuery' in scope`.

- [ ] **Step 3: Commit the failing-test checkpoint**

Do not commit this step yet if your workflow does not allow red commits. Keep the change unstaged until Task 2 makes it green.

---

### Task 2: Implement Search Model and Prepared Pipeline

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListQuery.swift`
- Modify: `FeedivoTests/ArticleListQueryTests.swift`

- [ ] **Step 1: Add search model below `ArticleFilterOption` dependencies in `ArticleListQuery.swift`**

Insert before `struct ArticleListDisplayState`:

```swift
enum ArticleSearchField: String, CaseIterable, Identifiable {
    case all
    case title
    case summary
    case content

    var id: String {
        rawValue
    }

    static func resolved(from rawValue: String) -> ArticleSearchField {
        ArticleSearchField(rawValue: rawValue) ?? .all
    }
}

enum ArticleSearchScope: String, CaseIterable, Identifiable {
    case currentView
    case allArticles

    var id: String {
        rawValue
    }

    static func resolved(from rawValue: String) -> ArticleSearchScope {
        ArticleSearchScope(rawValue: rawValue) ?? .currentView
    }
}

struct ArticleSearchQuery: Equatable {
    var text: String
    var field: ArticleSearchField
    var scope: ArticleSearchScope

    init(
        text: String = "",
        field: ArticleSearchField = .all,
        scope: ArticleSearchScope = .currentView
    ) {
        self.text = text
        self.field = field
        self.scope = scope
    }

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isActive: Bool {
        !normalizedText.isEmpty
    }

    func includes(_ article: Article) -> Bool {
        guard isActive else {
            return true
        }

        let needle = normalizedText
        switch field {
        case .all:
            return contains(needle, in: article.title)
                || contains(needle, in: article.summary)
                || contains(needle, in: article.content)
                || contains(needle, in: article.offlineContent)
        case .title:
            return contains(needle, in: article.title)
        case .summary:
            return contains(needle, in: article.summary)
        case .content:
            return contains(needle, in: article.content)
                || contains(needle, in: article.offlineContent)
        }
    }

    func filtered(_ articles: [Article]) -> [Article] {
        guard isActive else {
            return articles
        }

        return articles.filter { article in
            includes(article)
        }
    }

    private func contains(_ needle: String, in haystack: String?) -> Bool {
        guard let haystack else {
            return false
        }

        return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
```

- [ ] **Step 2: Extend `ArticleListPreparedArticles.prepare(...)`**

Replace the function signature and body with:

```swift
static func prepare(
    articles: [Article],
    sortArticles: Bool,
    filterOption: ArticleFilterOption,
    searchQuery: ArticleSearchQuery = ArticleSearchQuery(),
    sorter: ([Article]) -> [Article]
) -> ArticleListPreparedArticles {
    let sortedArticles = sortArticles ? sorter(articles) : articles
    let filteredArticles = searchQuery.filtered(filterOption.filtered(sortedArticles))
    return ArticleListPreparedArticles(
        sorted: sortedArticles,
        filtered: filteredArticles
    )
}
```

- [ ] **Step 3: Add pipeline test**

Add after `articleListPreparedArticlesSortiertNurEinmalVorDemFiltern()`:

```swift
@Test func articleListPreparedArticlesKombiniertFilterSortierungUndSuche() {
    let unreadNewest = Article(
        title: "Swift Suche",
        summary: "Mac",
        publishedAt: Date(timeIntervalSince1970: 300),
        isRead: false
    )
    let readMiddle = Article(
        title: "Swift gelesen",
        summary: "Mac",
        publishedAt: Date(timeIntervalSince1970: 200),
        isRead: true
    )
    let unreadOldest = Article(
        title: "Andere Meldung",
        summary: "Mac",
        publishedAt: Date(timeIntervalSince1970: 100),
        isRead: false
    )

    let preparedArticles = ArticleListPreparedArticles.prepare(
        articles: [unreadOldest, readMiddle, unreadNewest],
        sortArticles: true,
        filterOption: .unread,
        searchQuery: ArticleSearchQuery(text: "swift", field: .title),
        sorter: ArticleSortOption.newestFirst.sorted
    )

    #expect(preparedArticles.sorted.map(\.title) == [
        "Swift Suche",
        "Swift gelesen",
        "Andere Meldung"
    ])
    #expect(preparedArticles.filtered.map(\.title) == ["Swift Suche"])
}
```

- [ ] **Step 4: Run tests and verify green**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListQueryTests test
```

Expected: `ArticleListQueryTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListQuery.swift FeedivoTests/ArticleListQueryTests.swift
git commit -m "Add article search query model"
```

---

### Task 3: Add Command Plumbing for Cmd+F

**Files:**
- Modify: `Feedivo/App/ArticleCommandActions.swift`
- Modify: `Feedivo/App/ArticleCommands.swift`
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [ ] **Step 1: Add focused search actions**

Append this to `ArticleCommandActions.swift` after the existing `FocusedValues`
extension:

```swift
struct ArticleSearchCommandActions {
    let focusSearch: () -> Void

    init(focusSearch: @escaping () -> Void = {}) {
        self.focusSearch = focusSearch
    }
}

private struct ArticleSearchCommandActionsKey: FocusedValueKey {
    typealias Value = ArticleSearchCommandActions
}

extension FocusedValues {
    var articleSearchCommandActions: ArticleSearchCommandActions? {
        get { self[ArticleSearchCommandActionsKey.self] }
        set { self[ArticleSearchCommandActionsKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Add command button**

In `ArticleCommands`, add this button after the first navigation divider and before read/star actions:

```swift
Button(L10n.articleSearchCommand) {
    articleSearchCommandActions?.focusSearch()
}
.keyboardShortcut("f", modifiers: [.command])
```

Add a `Divider()` after it so search is visually separated from article state actions.

- [ ] **Step 3: Add focused value lookup to `ArticleCommands`**

At the top of `ArticleCommands`, add:

```swift
@FocusedValue(\.articleSearchCommandActions)
private var articleSearchCommandActions
```

- [ ] **Step 4: Add `L10n` accessor**

In `L10n.swift`, near article command strings, add:

```swift
static var articleSearchCommand: String { String(localized: "article.search.command") }
```

- [ ] **Step 5: Add string catalog entry**

Add `article.search.command` to `Localizable.xcstrings` with:

```json
"article.search.command" : {
  "localizations" : {
    "de" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Suchen..."
      }
    },
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Find..."
      }
    },
    "fr" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Rechercher..."
      }
    },
    "it" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Cerca..."
      }
    }
  }
}
```

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/App/ArticleCommandActions.swift Feedivo/App/ArticleCommands.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Add article search command"
```

---

### Task 4: Add Search UI to Article List

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [ ] **Step 1: Add search state and all-articles query**

Inside `ArticleListContent`, add:

```swift
@Query(sort: \Article.publishedAt, order: .reverse)
private var allArticles: [Article]
@State private var searchText = ""
@State private var isSearchPresented = false
@State private var searchField = ArticleSearchField.all
@State private var searchScope = ArticleSearchScope.currentView
@FocusState private var isSearchFieldFocused: Bool
```

- [ ] **Step 2: Route source articles through search scope**

Add:

```swift
private var activeSearchQuery: ArticleSearchQuery {
    ArticleSearchQuery(
        text: searchText,
        field: searchField,
        scope: searchScope
    )
}

private var sourceArticlesForCurrentSearch: [Article] {
    activeSearchQuery.scope == .allArticles && activeSearchQuery.isActive
        ? allArticles
        : articles
}
```

Update `makePreparedArticles()` to use `sourceArticlesForCurrentSearch` and pass `activeSearchQuery`:

```swift
private func makePreparedArticles() -> ArticleListPreparedArticles {
    ArticleListPreparedArticles.prepare(
        articles: sourceArticlesForCurrentSearch,
        sortArticles: sortArticles,
        filterOption: articleFilterOption,
        searchQuery: activeSearchQuery,
        sorter: articleSortOption.sorted
    )
}
```

- [ ] **Step 3: Wrap the list with a search bar**

Replace the top-level `List(selection:)` in `body` with:

```swift
VStack(spacing: 0) {
    if isSearchPresented {
        articleSearchBar
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
    }

    List(selection: $selectedArticle) {
        if filteredArticles.isEmpty {
            articleListEmptyState(isSearching: activeSearchQuery.isActive)
        } else {
            ForEach(visibleArticles) { article in
                articleRow(article, visibleArticles: visibleArticles)
                    .tag(article)
            }

            if displaySnapshot.shouldShowReadArticlesButton {
                showReadArticlesButton(count: displaySnapshot.hiddenReadArticleCount)
            }
        }
    }
}
```

- [ ] **Step 4: Add search bar view**

Add inside `ArticleListContent`:

```swift
private var articleSearchBar: some View {
    HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)

        TextField(L10n.articleSearchPlaceholder, text: $searchText)
            .textFieldStyle(.plain)
            .focused($isSearchFieldFocused)

        Picker("", selection: $searchField) {
            ForEach(ArticleSearchField.allCases) { field in
                Text(label(for: field)).tag(field)
            }
        }
        .labelsHidden()
        .frame(width: 128)

        Picker("", selection: $searchScope) {
            ForEach(ArticleSearchScope.allCases) { scope in
                Text(label(for: scope)).tag(scope)
            }
        }
        .labelsHidden()
        .frame(width: 140)

        Button {
            clearArticleSearch()
        } label: {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(L10n.articleSearchClear)
    }
}
```

- [ ] **Step 5: Add helpers**

Add:

```swift
private func articleListEmptyState(isSearching: Bool) -> some View {
    if isSearching {
        ContentUnavailableView(
            L10n.articleSearchNoResultsTitle,
            systemImage: "magnifyingglass",
            description: Text(L10n.articleSearchNoResultsDescription(activeSearchQuery.normalizedText))
        )
    } else {
        ContentUnavailableView(
            L10n.articleListEmptyTitle,
            systemImage: "doc.text.magnifyingglass",
            description: Text(L10n.articleListEmptyDescription)
        )
    }
}

private func focusArticleSearch() {
    isSearchPresented = true
    DispatchQueue.main.async {
        isSearchFieldFocused = true
    }
}

private func clearArticleSearch() {
    searchText = ""
    searchField = .all
    searchScope = .currentView
    isSearchFieldFocused = true
}

private func label(for field: ArticleSearchField) -> String {
    switch field {
    case .all:
        return L10n.articleSearchFieldAll
    case .title:
        return L10n.articleSearchFieldTitle
    case .summary:
        return L10n.articleSearchFieldSummary
    case .content:
        return L10n.articleSearchFieldContent
    }
}

private func label(for scope: ArticleSearchScope) -> String {
    switch scope {
    case .currentView:
        return L10n.articleSearchScopeCurrentView
    case .allArticles:
        return L10n.articleSearchScopeAllArticles
    }
}
```

- [ ] **Step 6: Provide focused search action from the list**

After the existing `.toolbar { ... }`, add:

```swift
.focusedValue(
    \.articleSearchCommandActions,
    ArticleSearchCommandActions(focusSearch: focusArticleSearch)
)
```

- [ ] **Step 7: Add localized accessors and strings**

Add these `L10n` accessors:

```swift
static var articleSearchPlaceholder: String { String(localized: "article.search.placeholder") }
static var articleSearchClear: String { String(localized: "article.search.clear") }
static var articleSearchFieldAll: String { String(localized: "article.search.field.all") }
static var articleSearchFieldTitle: String { String(localized: "article.search.field.title") }
static var articleSearchFieldSummary: String { String(localized: "article.search.field.summary") }
static var articleSearchFieldContent: String { String(localized: "article.search.field.content") }
static var articleSearchScopeCurrentView: String { String(localized: "article.search.scope.currentView") }
static var articleSearchScopeAllArticles: String { String(localized: "article.search.scope.allArticles") }
static var articleSearchNoResultsTitle: String { String(localized: "article.search.noResults.title") }
static func articleSearchNoResultsDescription(_ query: String) -> String {
    String.localizedStringWithFormat(String(localized: "article.search.noResults.description"), query)
}
```

Add matching German/English/French/Italian string catalog entries. German values:

```text
article.search.placeholder = Artikel suchen
article.search.clear = Suche löschen
article.search.field.all = Alles
article.search.field.title = Titel
article.search.field.summary = Zusammenfassung
article.search.field.content = Inhalt
article.search.scope.currentView = Aktuelle Ansicht
article.search.scope.allArticles = Alle Artikel
article.search.noResults.title = Keine Treffer
article.search.noResults.description %@ = Keine Artikel gefunden für "%@". Ändere den Suchbereich oder den Umfang.
```

- [ ] **Step 8: Build and fix focused command conflicts**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Expected: build succeeds. If focused article actions conflict, split search into its own FocusedValue and update `ArticleCommands` to read it separately.

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Add article list search UI"
```

---

### Task 5: Update Roadmap and Run Full Verification

**Files:**
- Modify: `FEATURES.md`
- Possibly modify: `AGENTS.md`

- [ ] **Step 1: Update `FEATURES.md`**

Change Feature 9.1/9.2 to show the first slice as implemented:

```markdown
### 9.1 Volltext-Suche
- **Status:** 🔨 In Arbeit — Core-Slice umgesetzt
- **Umgesetzt:**
  - `Cmd+F` öffnet/fokussiert die Suche in der Artikelliste.
  - Suche nach Titel, Zusammenfassung, Inhalt oder allem.
  - Umfang: aktuelle Ansicht oder alle Artikel.
  - Bestehende Sortierung, Filter und Anzeige-Logik bleiben erhalten.
- **Noch offen:**
  - Erweiterte Filter aus Feature 9.2.
  - Spotlight aus Feature 9.3.
```

Keep 9.2 as decided but not fully implemented if extended filters are still absent.

- [ ] **Step 2: Update `AGENTS.md` if project structure changed**

If new files were added, update the project structure. If only existing files changed, add a short note under the relevant ArticleList section that search is part of `ArticleListView` and `ArticleListQuery`.

- [ ] **Step 3: Run focused tests**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListQueryTests test
```

Expected: test succeeds.

- [ ] **Step 4: Run full build**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Expected: build succeeds.

- [ ] **Step 5: Inspect git diff**

Run:

```bash
git diff --check
git status --short --branch
```

Expected: no whitespace errors; only intended files changed.

- [ ] **Step 6: Commit final docs**

```bash
git add FEATURES.md AGENTS.md
git commit -m "Update roadmap for search core"
```

Skip committing `AGENTS.md` if it did not change.

---

## Self-Review

- Spec coverage: The plan implements `Cmd+F`, visible search UI, field selection, current/global scope, result empty state, existing sort/filter/read behavior, and test-first search logic.
- Out of scope by design: advanced Feed/Tag/Date/Status search filters, Spotlight, result highlighting, persisted last query.
- TDD coverage: Task 1 and Task 2 add failing tests before production search logic. UI wiring is verified by build; no UI test harness exists for this macOS view yet.
- Type consistency: `ArticleSearchField`, `ArticleSearchScope`, and `ArticleSearchQuery` are defined before use in `ArticleListView`.
