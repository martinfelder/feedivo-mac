# Menubar-Dropdown Artikelzeilen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die Artikelzeilen im Menubar-Dropdown (`MenubarDropdownView.swift`) von reinem Text
auf Favicon + zweizeiligen Titel + Feedname/Zeit + optionales Thumbnail umstellen, ohne die
Dropdown-Kompaktheit (`.frame(width: 320)`) zu verlieren.

**Architecture:** Neue, isolierte `MenubarArticleRowView` kapselt die komplette Zeilen-Optik
und wird per `article: ArticleListItemSnapshot`-Parameter befüllt (kein neues Model, keine
neue Query). `MenubarDropdownView` ruft sie nur noch als Button-Label auf. Die einzige nicht
rein-visuelle Logik — "zeige Thumbnail ja/nein" — wird als `nonisolated static func` ausgelagert,
analog zu `MenubarStatusItemController.symbolName(forUnreadCount:)`, damit sie ohne View-Rendering
testbar ist.

**Tech Stack:** SwiftUI (macOS), `CachedRemoteImageView` (bestehende Bild-Caching-Komponente),
Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Favicon: 16×16pt, leading, über `CachedRemoteImageView`, gleiches Lade-/Fallback-Verhalten
  wie `FeedRowView.faviconView` — kein neues Caching/Fallback-Verhalten erfinden.
- Titel: `lineLimit(2)` (nicht mehr `1`).
- Feedname · Zeit: `Text(date, style: .relative)` für die Zeit (SwiftUI-Standardformatierung,
  keine eigene Formatter-Logik). Fehlt `publishedAt`, kein "·" ohne zweiten Teil.
- Thumbnail: nur wenn `article.imageURL` gesetzt ist und eine gültige URL ergibt, ca. 40×40pt,
  `.clipShape(RoundedRectangle(cornerRadius: 6))`, trailing, über `CachedRemoteImageView`. Bei
  fehlendem/ungültigem Bild kein Platzhalter — die Zeile bleibt schmaler.
- Datenquelle bleibt `ArticleListItemSnapshot` — keine neue Query, kein neues Snapshot-Feld.
- Keine Änderung an Header, Footer, Empty State, `MenubarIconLabel`/Status-Item-Icon oder neuer
  Einstellung für "Thumbnails an/aus".
- Keine neuen Store-/Datenbank-Unit-Tests nötig — nur die reine Thumbnail-Entscheidungsfunktion
  wird testbar ausgelagert (siehe Spec-Abschnitt "Testing").

---

### Task 1: `MenubarArticleRowView` erstellen (Favicon, Titel, Feedname/Zeit, Thumbnail)

**Files:**
- Create: `Feedivo/Views/Menubar/MenubarArticleRowView.swift`
- Test: `FeedivoTests/MenubarArticleRowViewTests.swift`

**Interfaces:**
- Consumes: `ArticleListItemSnapshot` (`Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift`)
  — Felder `id: String`, `title: String`, `feedTitle: String?`, `faviconURL: String?`,
  `imageURL: String?`, `publishedAt: Date?`. `CachedRemoteImageView<Content: View, Placeholder: View>`
  (`Feedivo/Views/Shared/CachedRemoteImageView.swift`) — `init(url: URL?, targetPixelSize: CGSize? = nil, imageCache: ImageCacheService = .shared, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder)`.
- Produces: `struct MenubarArticleRowView: View` mit `init(article: ArticleListItemSnapshot)`
  (memberwise reicht, `let article: ArticleListItemSnapshot`) und
  `nonisolated static func showsThumbnail(imageURL: String?) -> Bool` — von Task 2 nicht
  benötigt, aber Teil der öffentlichen Test-Oberfläche dieser Datei.

- [ ] **Step 1: Fehlschlagenden Test für die Thumbnail-Entscheidung schreiben**

```swift
import Testing
@testable import Feedivo

struct MenubarArticleRowViewTests {

    @Test func showsThumbnailIstWahrBeiGueltigerImageURL() {
        #expect(MenubarArticleRowView.showsThumbnail(imageURL: "https://example.com/image.jpg") == true)
    }

    @Test func showsThumbnailIstFalschOhneImageURL() {
        #expect(MenubarArticleRowView.showsThumbnail(imageURL: nil) == false)
    }

    @Test func showsThumbnailIstFalschBeiUngueltigerURL() {
        #expect(MenubarArticleRowView.showsThumbnail(imageURL: "") == false)
    }
}
```

Datei anlegen unter `FeedivoTests/MenubarArticleRowViewTests.swift`.

- [ ] **Step 2: Test laufen lassen, um das Fehlschlagen zu verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/MenubarArticleRowViewTests test 2>&1 | tail -20`
Expected: FAIL (Build-Fehler: `MenubarArticleRowView` existiert noch nicht)

- [ ] **Step 3: `MenubarArticleRowView.swift` mit vollständiger Zeilen-Struktur implementieren**

```swift
import SwiftUI

/// Einzelne Artikelzeile im Menubar-Dropdown: Favicon (leading) + Titel
/// (max. 2 Zeilen) + Feedname/relative Zeit, optional Thumbnail (trailing),
/// wenn der Artikel ein Bild hat. Ersetzt die zuvor rein textuelle Zeile in
/// `MenubarDropdownView`.
struct MenubarArticleRowView: View {
    let article: ArticleListItemSnapshot

    var body: some View {
        HStack(spacing: 8) {
            faviconView
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .lineLimit(2)

                subtitleView
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if Self.showsThumbnail(imageURL: article.imageURL) {
                Spacer(minLength: 8)
                thumbnailView
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch (article.feedTitle, article.publishedAt) {
        case let (feedTitle?, publishedAt?):
            HStack(spacing: 4) {
                Text(feedTitle)
                Text("·")
                Text(publishedAt, style: .relative)
            }
        case let (feedTitle?, nil):
            Text(feedTitle)
        case let (nil, publishedAt?):
            Text(publishedAt, style: .relative)
        case (nil, nil):
            EmptyView()
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURL = article.faviconURL, let url = URL(string: faviconURL) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } placeholder: {
                fallbackFaviconIcon
            }
        } else {
            fallbackFaviconIcon
        }
    }

    private var fallbackFaviconIcon: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let imageURLString = article.imageURL, let url = URL(string: imageURLString) {
            CachedRemoteImageView(
                url: url,
                targetPixelSize: CGSize(width: 80, height: 80)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.clear
            }
        }
    }

    /// Reine Entscheidung "zeige Thumbnail?" — testbar ohne View-Rendering,
    /// analog `MenubarStatusItemController.symbolName(forUnreadCount:)`.
    /// `nonisolated`, da rein wertbasiert.
    nonisolated static func showsThumbnail(imageURL: String?) -> Bool {
        guard let imageURL, URL(string: imageURL) != nil else { return false }
        return true
    }
}
```

- [ ] **Step 4: Test laufen lassen, um das Bestehen zu verifizieren**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/MenubarArticleRowViewTests test 2>&1 | tail -20`
Expected: PASS (`** TEST SUCCEEDED **`)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Menubar/MenubarArticleRowView.swift FeedivoTests/MenubarArticleRowViewTests.swift
git commit -m "Feature: MenubarArticleRowView mit Favicon/Titel/Zeit/Thumbnail erstellt"
```

---

### Task 2: `MenubarDropdownView` auf `MenubarArticleRowView` umstellen

**Files:**
- Modify: `Feedivo/Views/Menubar/MenubarDropdownView.swift:59-76`

**Interfaces:**
- Consumes: `MenubarArticleRowView(article: ArticleListItemSnapshot)` aus Task 1 (Datei
  `Feedivo/Views/Menubar/MenubarArticleRowView.swift`).
- Produces: nichts, das von weiteren Tasks konsumiert wird — dies ist die letzte Task dieses Plans.

- [ ] **Step 1: `ForEach`-Body in `MenubarDropdownView.swift` durch die neue Row-View ersetzen**

Aktueller Code (`Feedivo/Views/Menubar/MenubarDropdownView.swift:59-76`):

```swift
                ForEach(articles) { article in
                    Button {
                        open(article)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(article.title)
                                .lineLimit(1)
                            if let feedTitle = article.feedTitle {
                                Text(feedTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                }
```

Ersetzen durch:

```swift
                ForEach(articles) { article in
                    Button {
                        open(article)
                    } label: {
                        MenubarArticleRowView(article: article)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                }
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Bestehende Menubar-Testsuiten gegen Regressionen laufen lassen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/MenubarArticleRowViewTests -only-testing:FeedivoTests/MenubarStatusItemControllerTests -only-testing:FeedivoTests/MenubarSettingsTests test 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **` (alle drei Suiten grün)

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Menubar/MenubarDropdownView.swift
git commit -m "Feature: Menubar-Dropdown nutzt MenubarArticleRowView statt reiner Text-Zeile"
```

---

## Manuelle Verifikation (nicht automatisierbar, kein computer-use für native macOS-Apps)

Nach Abschluss beider Tasks vom Nutzer (Martin) manuell zu prüfen, siehe Spec-Abschnitt
"Manuelle Verifikation":

- Favicons laden korrekt und fallen bei fehlender URL sauber auf das generische Feed-Symbol zurück
- Thumbnails erscheinen nur bei Artikeln mit Bild, Zeilen ohne Bild bleiben kompakt (kein Leerraum)
- Relative Zeitangabe zeigt sinnvolle Werte auf Deutsch/Englisch (App-Sprache)
- Zweizeiliger Titel bricht sauber um, Dropdown bleibt bei `width: 320` lesbar
- Klickverhalten (Artikel öffnen, sowohl `inFeedivo` als auch `inBrowser`) bleibt unverändert funktionsfähig
