# Suchfenster Split-View Design

## Ziel

Das Artikel-Suchfenster (`ArticleSearchWindowView`) zeigt Treffer aktuell als reine Liste; die
einzige Aktion pro Zeile ist "Original öffnen" (Safari), was immer aus der App herausführt. Das
Fenster soll übersichtlicher werden und Treffer sollen ohne Fensterwechsel angesehen werden können.

## Design

### Layout

Das Suchfenster wird zweispaltig: Ergebnisliste links (schmaler als bisher, ca. 40% Breite),
Vorschau-Panel rechts. Die `minWidth` steigt von 620 auf ~900, `minHeight` bleibt bei 460.

Der Header wird kompakter: Der zweizeilige Block aus Icon+Titel+Beschreibungstext
(`L10n.articleSearchWindowDescription`) entfällt, weil der Fenstertitel ("Suchen…") das bereits
sagt. Suchfeld, Filter-Zeile und Treffer-Zähler bleiben unverändert oben, gewinnen aber vertikalen
Platz für die Ergebnisliste.

### Vorschau-Panel (rechts)

Leichtgewichtige Vorschau statt vollem Reader-Rendering — keine zweite Kopie der
`ReaderContentBlock`-Logik aus `SQLiteReaderView`:

- Titel, Feed-Name, Datum (wie in der bestehenden Zeile)
- Vorhandener Klartext-Summary (`ArticleListSnapshot.summary`), kein neues Parsing
- Zwei Aktionen:
  - **"Vollständig im Reader öffnen"** — ruft denselben Mechanismus wie
    `ContentView.openSQLiteArticleInWindow(articleID:)`
    (`ContentView.swift:418-427`): `openWindow(value: ArticleWindowRequest(articleID: uuid))`.
    Kein neuer Fenstertyp, keine neue Logik — reine Wiederverwendung.
  - **"Original öffnen"** — bestehender Safari-Button, unverändert übernommen.
- Wenn kein Treffer ausgewählt ist (z. B. direkt nach dem Öffnen des Fensters), zeigt die rechte
  Spalte einen leeren Platzhalter-Zustand ("Artikel auswählen").

### Interaktion mit der Liste

- Einfacher Klick auf eine Zeile wählt sie aus und lädt die Vorschau rechts.
- Doppelklick auf eine Zeile öffnet direkt das volle Reader-Fenster (wie der
  "Vollständig öffnen"-Button in der Vorschau) — kein Umweg über die Vorschau nötig.
- Die bestehende Safari-Aktion pro Zeile bleibt zusätzlich als Icon-Button erhalten (wie heute).

### Zustand

Neuer `@State private var selectedResultID: String?` in `ArticleSearchWindowView`, der auf den
angeklickten `ArticleListSnapshot.id` zeigt. Die Vorschau ist eine `@ViewBuilder`-Berechnung aus
`snapshots.first(where: { $0.id == selectedResultID })`.

### L10n

Neuer Key für den "Vollständig öffnen"-Button (z. B. `article.search.openInReader`); alle anderen
verwendeten Strings existieren bereits (`L10n.articleOpenOriginalCommand` etc.).

## Nicht Teil dieses Designs

Rohes HTML in manchen Artikel-Zusammenfassungen (z. B. bei Feeds wie GoogleWatchBlog,
appgefahren.de) ist ein Problem der Summary-Erzeugung beim Feed-Parsing, nicht des Suchfensters.
Separates Thema, falls gewünscht.

## Tests

Reine SwiftUI-Layout-/Interaktionsänderung ohne neue Business-Logik — `openWindow(value:)` ist
bereits produktiv im Einsatz. Manuelle Verifikation im Suchfenster genügt: Klick lädt Vorschau,
Doppelklick öffnet Reader-Fenster, "Vollständig öffnen"-Button tut dasselbe, "Original öffnen"
bleibt wie bisher.
