# Design: Inline-Formatierung (Fett/Kursiv/Links/Farben) im nativen Reader

**Datum:** 2026-07-28
**Status:** Vom Nutzer genehmigt, bereit für Implementierungsplan

## Problem

Der native SwiftUI-Artikel-Reader (`ReaderContentRenderer`/`SQLiteReaderView`) reduziert
Artikel-HTML beim Parsen auf reinen Block-Text. `htmlToPlainText(_:)` entfernt pauschal
**alle** HTML-Tags über eine einzige Regex, ohne zwischen strukturellen Block-Tags und
Inline-Formatierungs-Tags zu unterscheiden. Dadurch gehen beim Lesen im nativen Reader
(nicht in der WKWebView-„Originalartikel"-Ansicht) folgende Informationen unwiederbringlich
verloren:

- `<a href="...">Text</a>` → wird zu reinem `"Text"`, das Link-Ziel ist weg
- `<b>`/`<strong>`/`<i>`/`<em>` → werden zu unformatiertem Text

Zusätzlich rendert `SQLiteReaderView.contentBlock(_:)` jeden Block über `Text(String)`,
was selbst bei erhaltenem Markup keine Formatierung anzeigen würde (im Unterschied zu
`Text(AttributedString)`).

Root-Cause-Analyse (siehe Konversation) hat bestätigt: Das ist keine Regression, sondern
eine seit dem ursprünglichen Bau des Renderers bestehende strukturelle Lücke — es gibt im
gesamten Projekt keine `AttributedString`-basierte Rendering-Infrastruktur, die man wiederverwenden könnte.

## Umfang

**Erhalten bleiben sollen:** Fett, Kursiv, klickbare Links (öffnen im Standardbrowser),
Textfarben (nur Hex-Werte aus `style="color:...\"`, mit Kontrast-Sicherheitsprüfung
gegen Hell-/Dunkelmodus).

**Bewusst außerhalb des Umfangs:**
- Unterstreichung, `<code>`/Monospace — vom Nutzer nicht gewählt
- `<mark>` (Hintergrund-Highlight — andere Rendering-Mechanik als Textfarbe, eigenes Feature)
- CSS-Farbnamen (`color: red` etc.) — nur Hex-Farben (`#RRGGBB`/`#RGB`) werden geparst,
  keine ~150-Einträge-Namenstabelle
- Artikelliste-Vorschau und Suchfenster — bleiben reiner Vorschautext, nur der Reader
  selbst bekommt Inline-Formatierung

## Architektur

### Datenmodell (`ReaderContentRenderer.swift`)

Neuer reiner, `Equatable`/`Sendable`-Werttyp:

```swift
struct ReaderInlineRun: Equatable, Sendable {
    let text: String
    let isBold: Bool
    let isItalic: Bool
    let linkURL: URL?
    let colorHex: String?
}
```

`ReaderContentBlock`-Fälle (`.paragraph`, `.heading`, `.quote`, `.listItem`) tragen künftig
`[ReaderInlineRun]` statt `String` (`.image` bleibt unverändert bei `urlString: String`).

Bewusst **kein** direkter Umstieg auf `AttributedString` im Modell: `AttributedString`-
Gleichheit in Tests ist wegen interner Attribut-Runs brüchig, und das Projekt hält Modell-
/Snapshot-Typen konsequent als reine, SwiftUI-unabhängige Sendable-Structs (siehe
„Kernarchitektur" in CLAUDE.md). `[ReaderInlineRun]` ist trivial in Tests konstruierbar und
vergleichbar.

### Parser

Neue Funktion (ersetzt den bisherigen `htmlToPlainText`-Aufruf innerhalb von
`appendTextBlock`/`appendTextBlocks`, `htmlToPlainText` selbst bleibt für die weiterhin
reinen Vorschautext-Konsumenten — Artikelliste, Suche — unverändert bestehen):

```swift
static func inlineRuns(fromHTML html: String) -> [ReaderInlineRun]
```

Erkennt per Regex (gleicher „gut genug, keine echte HTML-Engine"-Stil wie der Rest der
Datei) `<a href="...">`, `<b>`/`<strong>`, `<i>`/`<em>` sowie `style="color:...\"` auf
diesen Tags. **Nachtrag (nach Rückfrage vor der Plan-Erstellung):** `style="color:...\"`
wird zusätzlich auf `<span>` erkannt (reines "Style-only"-Tag ohne eigene Bold/Italic/
Link-Bedeutung) — das ist der in echtem Artikel-HTML weit überwiegende Fall für farbigen
Text, `<span style="color:...">` ohne diese Erweiterung hätte das Farb-Feature in der
Praxis kaum sichtbar gemacht. Eine Ebene Verschachtelung wird unterstützt (z. B. `<b><a href="...">Link
</a></b>` — Bold-Flag wird an den inneren Link-Run vererbt) durch rekursives Parsen des
Tag-Inhalts. Verschachtelung des **gleichen** Tags (`<b>a<b>b</b>c</b>`) wird nicht
unterstützt (Regex kann Verschachtelungstiefe nicht zählen) — bestehende Einschränkung,
analog zu `structuredBlockExpression` auf Block-Ebene.

Kaputtes/nicht schließendes HTML fällt auf reinen Text zurück (kein Crash), analog zur
bestehenden Fallback-Logik auf Block-Ebene.

**Sicherheits-Constraint beim Parsen:** `linkURL` wird nur gesetzt, wenn das Schema
`http`/`https` ist. `javascript:`, `data:`, `file:` u. ä. aus fremdem Artikel-HTML werden
verworfen — der Text bleibt sichtbar, aber ohne Tap-Funktion. Verhindert, dass ein
bösartiger Feed einen Pseudo-Link unterschiebt.

### Rendering (`SQLiteReaderView.swift`)

Neue Hilfsfunktion, die `[ReaderInlineRun]` in eine einzige `AttributedString` übersetzt:

```swift
extension Array where Element == ReaderInlineRun {
    func attributedString(colorScheme: ColorScheme) -> AttributedString
}
```

- Fett → `.inlinePresentationIntent = .stronglyEmphasized`
- Kursiv → `.inlinePresentationIntent = .emphasized`
- Link → `.link`-Attribut (macht den Bereich in `Text(AttributedString)` automatisch
  tippbar)
- Farbe → `.foregroundColor`, aber nur wenn `ReaderInlineColorSafety.isSafeColor(...)`
  zustimmt (siehe unten) — sonst bleibt die Standard-Textfarbe erhalten

`contentBlock(_:)` ruft für `.paragraph`/`.heading`/`.quote`/`.listItem` jetzt
`Text(runs.attributedString(colorScheme: colorScheme))` statt `Text(text)` auf. Bestehende
`.font(...)`/`.fontWeight(...)`/`.lineSpacing(...)`-Modifier auf dem `Text` bleiben
unverändert (Basis-Größe/-Zeilenabstand kommt weiter von außen; Fett/Kursiv/Farbe/Link
kommen aus den Runs).

**Link-Öffnen:** `SQLiteReaderView` bekommt
`.environment(\.openURL, OpenURLAction { url in NSWorkspace.shared.open(url); return .handled })`,
um explizit sicherzustellen, dass getippte Links im Standardbrowser öffnen (nicht in-App).

### Farb-Sicherheit

Neue reine, unit-testbare Funktion (analog zum bestehenden Muster
`BackgroundRefreshService.isPrematureTick(...)` — bewusst ausgelagerte Entscheidung):

```swift
enum ReaderInlineColorSafety {
    static func isSafeColor(hex: String, againstBackgroundLuminance: Double) -> Bool
}
```

Berechnet eine vereinfachte Kontrast-Kennzahl zwischen geparster Farbe und einer
Referenzhelligkeit für Hell- bzw. Dunkelmodus-Hintergrund; bei zu geringem Kontrast wird
die Farbe verworfen. Wird zur Render-Zeit gegen `@Environment(\.colorScheme)` ausgewertet,
sodass derselbe Artikel bei Hell↔Dunkel-Wechsel automatisch neu bewertet wird (kein Caching
über den Farbmodus hinweg).

## Fehlerbehandlung

Kein neues Fehlerbehandlungs-Konzept nötig — der Inline-Parser erbt die bestehende
Fallback-Toleranz der Datei (nicht erkanntes/kaputtes Markup wird als reiner Text
belassen, nie ein Crash).

## Tests

- Bestehende `ReaderContentRenderer*`-Tests (`FeedivoTests.swift:126-284`) werden auf
  `[ReaderInlineRun]`-Vergleiche statt `String`-Vergleiche umgestellt (reine
  Signatur-Anpassung, kein Verhaltensunterschied bei unformatiertem Text).
- Neue Tests für den Inline-Parser: Fett, Kursiv, Link (inkl. `<b><a>...</a></b>`-
  Verschachtelung), Farbe.
- Neue Sicherheits-Tests: `javascript:`-Link wird verworfen (kein `linkURL`), `http(s)`-
  Link wird übernommen.
- Neue, isolierte Unit-Tests für `ReaderInlineColorSafety.isSafeColor(...)` — reine
  Kontrast-Arithmetik, unabhängig von SwiftUI/Rendering.
- Kein Test für die `AttributedString`-Konvertierungsfunktion selbst über reine
  Existenz-/Attribut-Stichproben hinaus — die eigentliche Logik (Run-Struktur,
  Farb-Sicherheit) ist bereits durch die obigen Tests abgedeckt, `AttributedString`-
  Gleichheitsvergleiche in Tests sind brüchig.

## Nicht behandelt / bewusste Limitationen

- Gleiches Tag verschachtelt (`<b>a<b>b</b>c</b>`) — seltener Fall, nicht unterstützt
- CSS-Farbnamen, `<mark>`, Unterstreichung, `<code>`/Monospace — siehe „Umfang" oben
- Artikelliste-Vorschau/Suche bleiben unverändert reiner Text
