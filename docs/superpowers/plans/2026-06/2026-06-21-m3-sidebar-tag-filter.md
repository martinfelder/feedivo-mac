# M3 Sidebar Tag Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add clickable article tag filters to the Feedivo sidebar.

**Architecture:** Extend the existing sidebar selection enum with a tag case, resolve the selected tag in `ContentView`, and add a matching `ArticleListView` scope. Keep tag rows lightweight and avoid sidebar count calculations.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, Feedivo MVVM structure.

---

### Task 1: Tag Article Query

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListQuery.swift`
- Test: `FeedivoTests/ArticleListQueryTests.swift`

- [ ] **Step 1: Add failing test for tag filtering**

Add this test to `ArticleListQueryTests`:

```swift
@MainActor
@Test func tagFetchDescriptorLaedtNurArtikelMitAusgewaehltemTagSortiert() throws {
    let container = try ModelContainer(
        for: Feed.self,
        FeedFolder.self,
        FeedLogEntry.self,
        Article.self,
        Tag.self,
        Rule.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let selectedTag = Tag(name: "Swift", colorHex: "#3B82F6")
    let otherTag = Tag(name: "Mac", colorHex: "#22C55E")
    let olderArticle = Article(
        title: "Aelter",
        publishedAt: Date(timeIntervalSince1970: 100)
    )
    olderArticle.tags = [selectedTag]
    let newerArticle = Article(
        title: "Neuer",
        publishedAt: Date(timeIntervalSince1970: 300)
    )
    newerArticle.tags = [selectedTag, otherTag]
    let unrelatedArticle = Article(
        title: "Fremd",
        publishedAt: Date(timeIntervalSince1970: 500)
    )
    unrelatedArticle.tags = [otherTag]

    context.insert(selectedTag)
    context.insert(otherTag)
    context.insert(olderArticle)
    context.insert(newerArticle)
    context.insert(unrelatedArticle)
    try context.save()

    let articles = try context.fetch(
        ArticleListQuery.tagFetchDescriptor(for: selectedTag)
    )

    #expect(articles.map(\.title) == ["Neuer", "Aelter"])
}
```

- [ ] **Step 2: Run the targeted tests and expect failure**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListQueryTests -derivedDataPath /private/tmp/feedivo-m3-sidebar-tag-filter-derived-data
```

Expected: FAIL because `ArticleListQuery.tagFetchDescriptor(for:)` does not exist.

- [ ] **Step 3: Add tag predicate and descriptor**

Add to `ArticleListQuery`:

```swift
static func tagPredicate(for tag: Tag) -> Predicate<Article> {
    let tagID = tag.id
    return #Predicate<Article> { article in
        article.tags.contains { articleTag in
            articleTag.id == tagID
        }
    }
}

static func tagFetchDescriptor(for tag: Tag) -> FetchDescriptor<Article> {
    FetchDescriptor(
        predicate: tagPredicate(for: tag),
        sortBy: sortDescriptors
    )
}
```

- [ ] **Step 4: Run targeted tests and expect pass**

Run the same `xcodebuild ... -only-testing:FeedivoTests/ArticleListQueryTests ...` command.

Expected: PASS.

### Task 2: Sidebar Selection and Tag Rows

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarSelection.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`

- [ ] **Step 1: Add tag selection case**

Change `SidebarSelection` to:

```swift
enum SidebarSelection: Hashable {
    case smartFilter(SmartFilter)
    case feed(PersistentIdentifier)
    case tag(PersistentIdentifier)
}
```

- [ ] **Step 2: Query and render tags in SidebarView**

Add `@Query(sort: \Tag.name) private var tags: [Tag]`.

Replace the empty `tagsSection` content with:

```swift
if !tags.isEmpty {
    tagRows(tags)
}
```

Add:

```swift
private func tagRows(_ tags: [Tag]) -> some View {
    ForEach(tags) { tag in
        Button {
            selection = .tag(tag.persistentModelID)
        } label: {
            TagSidebarRow(tag: tag)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(
            SidebarRowButtonStyle(
                isSelected: selection == .tag(tag.persistentModelID)
            )
        )
    }
}
```

Add a private `TagSidebarRow` view that renders a color circle and one-line tag name using `TagColorPalette.color(for:)`.

### Task 3: ContentView and ArticleList Tag Scope

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Views/ArticleList/ArticleListView.swift`

- [ ] **Step 1: Resolve selected tags in ContentView**

Add `@Query(sort: \Tag.name) private var tags: [Tag]`.

Add:

```swift
private var selectedTag: Tag? {
    guard case .tag(let tagID) = sidebarSelection else {
        return nil
    }

    return tags.first { $0.persistentModelID == tagID }
}
```

In the content column, after the selected feed branch, add a branch for `selectedTag` that creates `ArticleListView(tag:selectedArticle:navigationState:)`.

- [ ] **Step 2: Add tag scope to ArticleListView**

Extend `Scope` with `case tag(Tag)`, add an `init(tag:selectedArticle:navigationState:)`, add a switch branch, and create `TagArticleListContent` matching the existing `FeedArticleListContent` structure but using `ArticleListQuery.tagPredicate(for:)` and `Text(tag.name)`.

### Task 4: Documentation and Full Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `Feedivo/Resources/AGENTS.md`
- Modify: `docs/FEATURES.md`

- [ ] **Step 1: Update project memory**

Document that M3 Block B is complete:

- Sidebar shows clickable article tags.
- Tag filters show matching articles.
- Tag counts, feed tags, and rules remain out of scope.

- [ ] **Step 2: Run full unit verification**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -derivedDataPath /private/tmp/feedivo-m3-sidebar-tag-filter-derived-data
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Commit implementation**

Stage only the implementation, tests, docs, spec, and plan files. Do not stage Xcode `UserInterfaceState.xcuserstate`.

Commit:

```bash
git commit -m "feat: add sidebar tag filters"
```
