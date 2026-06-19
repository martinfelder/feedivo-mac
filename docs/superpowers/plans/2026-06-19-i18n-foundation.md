# i18n Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feedivo bekommt eine i18n-Foundation mit Apple String Catalog und den Startsprachen Deutsch, Englisch, Franzoesisch und Italienisch.

**Architecture:** Sichtbare UI-Texte werden ueber stabile Keys aus `Localizable.xcstrings` geladen. SwiftUI-Views verwenden eine kleine `L10n`-Hilfsdatei fuer `LocalizedStringKey`; Service- und ViewModel-Fehler verwenden `String(localized:)`. Dynamische Feed- und Artikelinhalte bleiben unveraendert.

**Tech Stack:** SwiftUI, Swift String Catalog (`.xcstrings`), `LocalizedStringKey`, `String(localized:)`, Swift Testing, Xcode 26.

---

## File Structure

- Create `Feedivo/Resources/Localizable.xcstrings`: String Catalog mit `de`, `en`, `fr`, `it`.
- Create `Feedivo/Resources/L10n.swift`: stabile Keys fuer Views und lokalisierte Runtime-Strings fuer Fehlertexte.
- Modify `Feedivo/Views/ContentView.swift`: Placeholder-Texte lokalisieren.
- Modify `Feedivo/Views/Sidebar/SidebarView.swift`: Add-Feed-UI lokalisieren.
- Modify `Feedivo/Views/ArticleList/ArticleListView.swift`: Empty-State lokalisieren.
- Modify `Feedivo/Views/ArticleList/ArticleRowView.swift`: Tooltips, Kontextmenue, Accessibility lokalisieren.
- Modify `Feedivo/Views/Reader/ReaderView.swift`: Original-Link lokalisieren.
- Modify `Feedivo/Views/Settings/SettingsView.swift`: Settings-Texte lokalisieren.
- Modify `Feedivo/Services/FeedService.swift`: `FeedServiceError.errorDescription` lokalisieren.
- Modify `Feedivo/ViewModels/FeedViewModel.swift`: Formular-Fehler lokalisieren.
- Modify `FeedivoTests/FeedivoTests.swift`: lokalisierte Error-Strings pruefen.
- Modify `AGENTS.md` and `docs/FEATURES.md`: Projektgedaechtnis und Feature-Roadmap nachfuehren.

## String Keys and Translations

Use these exact keys in `Localizable.xcstrings`:

| Key | de | en | fr | it |
|---|---|---|---|---|
| `content.noFeedSelected.title` | Kein Feed ausgewählt | No feed selected | Aucun flux sélectionné | Nessun feed selezionato |
| `content.noFeedSelected.description` | Wähle einen Feed in der Sidebar aus. | Select a feed in the sidebar. | Sélectionnez un flux dans la barre latérale. | Seleziona un feed nella barra laterale. |
| `content.noArticleSelected.title` | Kein Artikel ausgewählt | No article selected | Aucun article sélectionné | Nessun articolo selezionato |
| `content.noArticleSelected.description` | Wähle einen Artikel aus der Liste aus. | Select an article from the list. | Sélectionnez un article dans la liste. | Seleziona un articolo dall'elenco. |
| `sidebar.empty.title` | Noch keine Feeds | No feeds yet | Aucun flux pour le moment | Ancora nessun feed |
| `sidebar.addFeed.button` | Feed hinzufügen | Add feed | Ajouter un flux | Aggiungi feed |
| `sidebar.addFeed.title` | Feed hinzufügen | Add feed | Ajouter un flux | Aggiungi feed |
| `sidebar.addFeed.url.placeholder` | https://example.com/feed.xml | https://example.com/feed.xml | https://example.com/feed.xml | https://example.com/feed.xml |
| `common.cancel` | Abbrechen | Cancel | Annuler | Annulla |
| `common.add` | Hinzufügen | Add | Ajouter | Aggiungi |
| `articleList.empty.title` | Keine Artikel | No articles | Aucun article | Nessun articolo |
| `articleList.empty.description` | Dieser Feed hat noch keine gespeicherten Artikel. | This feed has no saved articles yet. | Ce flux n'a pas encore d'articles enregistrés. | Questo feed non ha ancora articoli salvati. |
| `articleRow.star.remove` | Stern entfernen | Remove star | Retirer l'étoile | Rimuovi stella |
| `articleRow.star.add` | Mit Stern markieren | Add star | Ajouter une étoile | Aggiungi stella |
| `articleRow.unread` | Ungelesen | Unread | Non lu | Non letto |
| `articleRow.markRead` | Als gelesen markieren | Mark as read | Marquer comme lu | Segna come letto |
| `articleRow.markUnread` | Als ungelesen markieren | Mark as unread | Marquer comme non lu | Segna come non letto |
| `reader.openOriginal` | Original öffnen | Open original | Ouvrir l'original | Apri originale |
| `settings.reading.section` | Lesen | Reading | Lecture | Lettura |
| `settings.markReadOnOpen.title` | Artikel beim Öffnen als gelesen markieren | Mark articles as read when opened | Marquer les articles comme lus à l'ouverture | Segna gli articoli come letti all'apertura |
| `settings.markReadOnOpen.description` | Wenn diese Option aktiv ist, markiert Feedivo einen Artikel als gelesen, sobald du ihn in der Liste öffnest. | When this option is enabled, Feedivo marks an article as read as soon as you open it from the list. | Lorsque cette option est activée, Feedivo marque un article comme lu dès que vous l'ouvrez depuis la liste. | Quando questa opzione è attiva, Feedivo segna un articolo come letto appena lo apri dall'elenco. |
| `feed.error.invalidURL` | Die Feed-URL ist ungültig. | The feed URL is invalid. | L'URL du flux n'est pas valide. | L'URL del feed non è valido. |
| `feed.error.parsingFailed` | Der Feed konnte nicht gelesen werden. | The feed could not be read. | Le flux n'a pas pu être lu. | Impossibile leggere il feed. |
| `feed.error.emptyURL` | Bitte gib eine Feed-URL ein. | Please enter a feed URL. | Veuillez saisir une URL de flux. | Inserisci un URL del feed. |
| `feed.error.addFailed` | Der Feed konnte nicht hinzugefügt werden. | The feed could not be added. | Le flux n'a pas pu être ajouté. | Impossibile aggiungere il feed. |

## Task 1: Create String Catalog and L10n Helper

**Files:**
- Create: `Feedivo/Resources/Localizable.xcstrings`
- Create: `Feedivo/Resources/L10n.swift`

- [ ] **Step 1: Create `Localizable.xcstrings`**

Create the catalog with `sourceLanguage` `de` and every key from the "String Keys and Translations" section of this plan. Each key must use this JSON shape:

```json
{
  "sourceLanguage": "de",
  "strings": {
    "common.add": {
      "localizations": {
        "de": { "stringUnit": { "state": "translated", "value": "Hinzufügen" } },
        "en": { "stringUnit": { "state": "translated", "value": "Add" } },
        "fr": { "stringUnit": { "state": "translated", "value": "Ajouter" } },
        "it": { "stringUnit": { "state": "translated", "value": "Aggiungi" } }
      }
    }
  },
  "version": "1.0"
}
```

- [ ] **Step 2: Create `L10n.swift`**

```swift
import SwiftUI

enum L10n {
    static let contentNoFeedSelectedTitle = LocalizedStringKey("content.noFeedSelected.title")
    static let contentNoFeedSelectedDescription = LocalizedStringKey("content.noFeedSelected.description")
    static let contentNoArticleSelectedTitle = LocalizedStringKey("content.noArticleSelected.title")
    static let contentNoArticleSelectedDescription = LocalizedStringKey("content.noArticleSelected.description")
    static let sidebarEmptyTitle = LocalizedStringKey("sidebar.empty.title")
    static let sidebarAddFeedButton = LocalizedStringKey("sidebar.addFeed.button")
    static let sidebarAddFeedTitle = LocalizedStringKey("sidebar.addFeed.title")
    static let sidebarAddFeedURLPlaceholder = LocalizedStringKey("sidebar.addFeed.url.placeholder")
    static let commonCancel = LocalizedStringKey("common.cancel")
    static let commonAdd = LocalizedStringKey("common.add")
    static let articleListEmptyTitle = LocalizedStringKey("articleList.empty.title")
    static let articleListEmptyDescription = LocalizedStringKey("articleList.empty.description")
    static let articleRowUnread = LocalizedStringKey("articleRow.unread")
    static let readerOpenOriginal = LocalizedStringKey("reader.openOriginal")
    static let settingsReadingSection = LocalizedStringKey("settings.reading.section")
    static let settingsMarkReadOnOpenTitle = LocalizedStringKey("settings.markReadOnOpen.title")
    static let settingsMarkReadOnOpenDescription = LocalizedStringKey("settings.markReadOnOpen.description")

    static var articleRowStarRemove: String {
        String(localized: "articleRow.star.remove")
    }

    static var articleRowStarAdd: String {
        String(localized: "articleRow.star.add")
    }

    static var articleRowUnreadText: String {
        String(localized: "articleRow.unread")
    }

    static var articleRowMarkRead: String {
        String(localized: "articleRow.markRead")
    }

    static var articleRowMarkUnread: String {
        String(localized: "articleRow.markUnread")
    }

    static var feedErrorInvalidURL: String {
        String(localized: "feed.error.invalidURL")
    }

    static var feedErrorParsingFailed: String {
        String(localized: "feed.error.parsingFailed")
    }

    static var feedErrorEmptyURL: String {
        String(localized: "feed.error.emptyURL")
    }

    static var feedErrorAddFailed: String {
        String(localized: "feed.error.addFailed")
    }
}
```

- [ ] **Step 3: Verify file inclusion**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`

Expected: Build succeeds. Because the project uses Xcode file-system synchronized groups, new files under `Feedivo/Resources` are included automatically.

## Task 2: Localize Errors and Add Tests

**Files:**
- Modify: `Feedivo/Services/FeedService.swift`
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Modify: `FeedivoTests/FeedivoTests.swift`

- [ ] **Step 1: Write failing error localization tests**

Add to `FeedivoTests/FeedivoTests.swift`:

```swift
@Test func feedServiceErrorTexteSindLokalisiert() {
    #expect(FeedServiceError.invalidURL.errorDescription == "Die Feed-URL ist ungültig.")
    #expect(FeedServiceError.parsingFailed.errorDescription == "Der Feed konnte nicht gelesen werden.")
}
```

- [ ] **Step 2: Run test to verify current state**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/feedServiceErrorTexteSindLokalisiert`

Expected before implementation: Either compile failure because `L10n` is not wired yet or PASS with current German strings. If it passes immediately, keep the test as a regression test and continue; the implementation still moves the source from hard-coded text to String Catalog.

- [ ] **Step 3: Localize `FeedServiceError`**

Change `errorDescription` in `Feedivo/Services/FeedService.swift` to:

```swift
var errorDescription: String? {
    switch self {
    case .invalidURL:
        return L10n.feedErrorInvalidURL
    case .parsingFailed:
        return L10n.feedErrorParsingFailed
    }
}
```

- [ ] **Step 4: Localize `FeedViewModel` fallback strings**

Change `Feedivo/ViewModels/FeedViewModel.swift`:

```swift
guard !cleanedURL.isEmpty else {
    errorMessage = L10n.feedErrorEmptyURL
    return
}
```

And:

```swift
} catch let error as LocalizedError {
    errorMessage = error.errorDescription ?? L10n.feedErrorAddFailed
} catch {
    errorMessage = L10n.feedErrorAddFailed
}
```

- [ ] **Step 5: Run error tests**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/feedServiceErrorTexteSindLokalisiert`

Expected: PASS.

## Task 3: Localize SwiftUI Views

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Modify: `Feedivo/Views/ArticleList/ArticleListView.swift`
- Modify: `Feedivo/Views/ArticleList/ArticleRowView.swift`
- Modify: `Feedivo/Views/Reader/ReaderView.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Localize `ContentView`**

Replace placeholder calls with:

```swift
ContentUnavailableView(
    L10n.contentNoFeedSelectedTitle,
    systemImage: "newspaper",
    description: Text(L10n.contentNoFeedSelectedDescription)
)
```

and:

```swift
ContentUnavailableView(
    L10n.contentNoArticleSelectedTitle,
    systemImage: "doc.text",
    description: Text(L10n.contentNoArticleSelectedDescription)
)
```

- [ ] **Step 2: Localize `SidebarView`**

Use:

```swift
Text(L10n.sidebarEmptyTitle)
```

```swift
Label(L10n.sidebarAddFeedButton, systemImage: "plus")
```

```swift
Text(L10n.sidebarAddFeedTitle)
```

```swift
TextField(L10n.sidebarAddFeedURLPlaceholder, text: $urlString)
```

```swift
Button(L10n.commonCancel) {
    dismiss()
}
```

```swift
Text(L10n.commonAdd)
```

- [ ] **Step 3: Localize `ArticleListView`**

Use:

```swift
ContentUnavailableView(
    L10n.articleListEmptyTitle,
    systemImage: "doc.text.magnifyingglass",
    description: Text(L10n.articleListEmptyDescription)
)
```

- [ ] **Step 4: Localize `ArticleRowView`**

Use string-returning helpers where SwiftUI expects plain `String`:

```swift
.help(article.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
```

```swift
Button(article.isRead ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead) {
    onToggleRead()
}
```

```swift
Button(article.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd) {
    onToggleStarred()
}
```

```swift
.help(L10n.articleRowUnreadText)
```

In `accessibilityLabel`, replace literals:

```swift
if !article.isRead {
    parts.append(L10n.articleRowUnreadText)
}

if article.isStarred {
    parts.append(L10n.articleRowStarAdd)
}
```

- [ ] **Step 5: Localize `ReaderView`**

Use:

```swift
Link(L10n.readerOpenOriginal, destination: url)
```

- [ ] **Step 6: Localize `SettingsView`**

Use:

```swift
Section(L10n.settingsReadingSection) {
    Toggle(L10n.settingsMarkReadOnOpenTitle, isOn: $markArticleReadOnSelection)

    Text(L10n.settingsMarkReadOnOpenDescription)
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 7: Build localized views**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`

Expected: Build succeeds.

## Task 4: Static String Audit

**Files:**
- Inspect: `Feedivo/Views`
- Inspect: `Feedivo/ViewModels`
- Inspect: `Feedivo/Services`

- [ ] **Step 1: Run visible string search**

Run:

```bash
rg -n 'Text\("|Button\("|Toggle\("|Label\("|Link\("|ContentUnavailableView\(|help\("|Section\("' Feedivo/Views Feedivo/ViewModels Feedivo/Services
```

Expected remaining matches:

- Dynamic strings such as `Text(article.title)`, `Label(feed.title, ...)`, `.navigationTitle(feed.title)`, `.navigationTitle(article.title)`.
- No hard-coded German visible UI text remains outside `Localizable.xcstrings`.

- [ ] **Step 2: Fix any remaining hard-coded visible UI strings**

If the command shows a static visible German string, add a key to `Localizable.xcstrings`, add a constant to `L10n.swift`, and replace the literal. For example, a new empty-state title should become a concrete key and helper:

```swift
static let sidebarEmptyTitle = LocalizedStringKey("sidebar.empty.title")
```

Then the view uses:

```swift
Text(L10n.sidebarEmptyTitle)
```

- [ ] **Step 3: Run full tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **`.

## Task 5: Documentation and Commit

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [ ] **Step 1: Update `AGENTS.md`**

Add:

- Technology stack row/note: Localization via Swift String Catalog.
- Implemented code section for `Localizable.xcstrings` and `L10n.swift`.
- Gotcha: dynamic feed/article content is not translated.
- Latest changes entry for i18n foundation.

- [ ] **Step 2: Update `docs/FEATURES.md`**

Change multilingual UI from "Spaeter" to "Fertig als Basis" or add current stand:

```markdown
- i18n Foundation ist vorhanden: Deutsch, Englisch, Franzoesisch und Italienisch via String Catalog.
- Sprachumschalter in der App bleibt spaeter.
```

- [ ] **Step 3: Final status check**

Run:

```bash
git status --short --branch
```

Expected: Only intended files modified plus possibly Xcode `UserInterfaceState.xcuserstate`, which must not be staged.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add AGENTS.md docs/FEATURES.md Feedivo/Resources/Localizable.xcstrings Feedivo/Resources/L10n.swift Feedivo/Services/FeedService.swift Feedivo/ViewModels/FeedViewModel.swift Feedivo/Views/ContentView.swift Feedivo/Views/Sidebar/SidebarView.swift Feedivo/Views/ArticleList/ArticleListView.swift Feedivo/Views/ArticleList/ArticleRowView.swift Feedivo/Views/Reader/ReaderView.swift Feedivo/Views/Settings/SettingsView.swift FeedivoTests/FeedivoTests.swift
git commit -m "Add i18n foundation"
```

Expected: Commit succeeds with only intended files.
