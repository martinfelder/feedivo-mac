# Design: Menubar-Dropdown — Artikelzeilen visuell aufwerten

**Datum:** 2026-07-10
**Status:** Genehmigt, bereit für Implementierungsplan

## Kontext

Feature 21.1 „Menubar-Icon" ist implementiert und funktioniert (AppKit `NSStatusItem`
statt der ursprünglich geplanten SwiftUI-`MenuBarExtra`, siehe CLAUDE.md-Gotcha vom
2026-07-10 zu deren 100%-CPU-Spin-Bug). Die Artikelzeilen im Dropdown
(`Feedivo/Views/Menubar/MenubarDropdownView.swift`) sind aktuell rein textuell:

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

Nutzer-Feedback: „zu einfach" — kein Favicon, kein Artikelbild, keine Zeitangabe.
Ziel dieser Spec: die Zeilen optisch an die Hauptartikelliste (`ArticleRowView`)
angleichen, ohne die Kompaktheit des Dropdowns (`.frame(width: 320)`) zu verlieren.

## Entscheidung aus dem Brainstorming

Nutzer hat sich für „Thumbnail nur wenn vorhanden" entschieden (von drei
vorgestellten Layout-Optionen): Artikel mit `imageURL` zeigen ein kleines
Thumbnail, Artikel ohne Bild bleiben kompakt bei Favicon + Text — kein
Leerraum für fehlende Bilder, natürliche Zeilenhöhe je nach Inhalt.

## Neue Zeilen-Struktur

Neue kleine View `MenubarArticleRowView` (ersetzt den `Button`-Body-Inhalt der
`ForEach`-Schleife in `MenubarDropdownView.swift`):

```
┌───────────────────────────────────────┐
│ [Favicon] Titel (max. 2 Zeilen)  [Bild]│
│           Feedname · vor 57 Min.       │
└───────────────────────────────────────┘
```

- **Favicon** (16×16pt, leading): `CachedRemoteImageView` aus
  `article.faviconURL`, gleiches Lade-/Fallback-Verhalten wie
  `FeedRowView.faviconView` (`Feedivo/Views/Sidebar/FeedRowView.swift`) —
  kein neues Caching/Fallback-Verhalten erfinden, bestehende Komponente direkt
  wiederverwenden. Fällt bei fehlender/ungültiger URL auf ein generisches
  Feed-Symbol zurück (bestehendes Verhalten von `CachedRemoteImageView`
  übernehmen, keine neue Fallback-Logik).
- **Titel**: `lineLimit(2)` statt bisher `1` (Zeilenumbruch statt Kürzung,
  passt zur größeren Zeile).
- **Feedname · Zeit**: eine `HStack` mit `article.feedTitle` (falls vorhanden)
  und relativer Zeit aus `article.publishedAt`, per `Text(date, style: .relative)`
  formatiert (SwiftUI-Standardformatierung, folgt automatisch der System-/
  App-Sprache — kein neuer Formatter-Code nötig). Fehlt `publishedAt`, wird nur
  der Feedname gezeigt (kein „·" ohne zweiten Teil).
- **Thumbnail** (trailing, nur wenn `article.imageURL` gesetzt und eine gültige
  URL ergibt): ca. 40×40pt, `.clipShape(RoundedRectangle(cornerRadius: 6))`,
  ebenfalls über `CachedRemoteImageView`. Bei fehlendem/ungültigem `imageURL`
  wird kein Platzhalter gezeigt — die Zeile bleibt einfach schmaler (siehe
  gewählte Layout-Option).

Datenquelle bleibt unverändert `ArticleListItemSnapshot` (bereits alle
benötigten Felder: `faviconURL`, `imageURL`, `publishedAt`, `feedTitle`,
`title`) — keine neue Query, kein neues Snapshot-Feld nötig.

## Betroffene Dateien

- **Modify:** `Feedivo/Views/Menubar/MenubarDropdownView.swift` — `ForEach`-Body
  durch Aufruf der neuen `MenubarArticleRowView` ersetzen.
- **Create:** `Feedivo/Views/Menubar/MenubarArticleRowView.swift` — die neue
  Zeilen-View, isoliert testbar/lesbar statt inline in der `ForEach`-Closure.

## Testing

Keine neuen Store-/Datenbank-Methoden, daher keine neuen Unit-Tests im
klassischen Sinn nötig (reine View-Komposition aus bereits vorhandenen,
bereits getesteten Datenfeldern). Bei Bedarf im Implementierungsplan prüfen,
ob eine reine Layout-Entscheidungsfunktion (z. B. „zeige Thumbnail ja/nein"
aus `imageURL`) sich sinnvoll als kleine, testbare `nonisolated static func`
auslagern lässt — analog zum bereits etablierten Muster in
`MenubarStatusItemController.symbolName(forUnreadCount:)`.

## Manuelle Verifikation (nicht automatisierbar)

- Favicons laden korrekt und fallen bei fehlender URL sauber zurück
- Thumbnails erscheinen nur bei Artikeln mit Bild, Zeilen ohne Bild bleiben
  kompakt
- Relative Zeitangabe zeigt sinnvolle Werte auf Deutsch/Englisch (App-Sprache)
- Zweizeiliger Titel bricht sauber um, Dropdown bleibt bei `width: 320` lesbar
- Klickverhalten (Artikel öffnen) bleibt unverändert funktionsfähig

## Out of Scope

- Keine Änderung an Header (Öffnen/Refresh-Buttons), Footer
  („Alle als gelesen markieren") oder Empty State — nur die Artikelzeilen
  selbst
- Keine Änderung an `MenubarIconLabel`/Status-Item-Icon selbst
- Keine neue Einstellung für „Thumbnails an/aus" — feste Verhaltensregel laut
  gewählter Layout-Option (bei Bedarf später als eigene, separate
  Erweiterung)
