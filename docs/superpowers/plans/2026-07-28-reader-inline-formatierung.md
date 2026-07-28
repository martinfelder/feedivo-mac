# Reader Inline-Formatierung (Fett/Kursiv/Links/Farben) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Der native SwiftUI-Artikel-Reader zeigt Fett, Kursiv, klickbare Links (öffnen
im Standardbrowser) und Hex-Textfarben aus dem Artikel-HTML an, statt sie beim
HTML-zu-Plain-Text-Parsing zu verlieren.

**Architecture:** `ReaderContentBlock`-Fälle tragen künftig `[ReaderInlineRun]`
(ein neuer, reiner Sendable-Werttyp mit Bold/Italic/Link/Farbe-Flags) statt
`String`. Ein neuer, rekursiver Regex-Parser (`ReaderContentRenderer.inlineRuns
(fromHTML:)`) erkennt `<a href>`, `<b>`/`<strong>`, `<i>`/`<em>` sowie
`style="color:...\"` auf diesen Tags plus zusätzlich auf `<span>`. Ein neuer,
pure Policy-Typ `ReaderInlineColorSafety` prüft Farben zur Render-Zeit gegen den
Kontrast von Hell-/Dunkelmodus. Die Rendering-Seite (`SQLiteReaderView`) baut aus
den Runs eine `AttributedString` und zeigt sie über `Text(AttributedString)`
statt `Text(String)`.

**Tech Stack:** Swift 5.9+, SwiftUI, `NSRegularExpression` (kein externer
HTML-Parser, konsistent mit dem Rest von `ReaderContentRenderer.swift`), Swift
Testing (kein XCTest).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- Kein XCTest — alle Tests mit Swift Testing (`import Testing`, `@Test func`, `#expect`).
- Build/Test-Verifikation ausschließlich über echte `xcodebuild`-Läufe — SourceKit-
  Diagnosen im Editor sind bekanntermaßen oft veraltete Fehlalarme (siehe CLAUDE.md-Gotcha),
  niemals als Fehlerquelle werten.
- Volle Testsuite (`xcodebuild test` ohne `-only-testing:`) hängt bekanntermaßen —
  immer gezielt mit `-only-testing:FeedivoTests/<SuiteName>` und
  `-parallel-testing-enabled NO` testen.
- Nur Hex-Farben (`#RGB`/`#RRGGBB`) werden geparst, keine CSS-Farbnamen.
- Nur `http`/`https`-Links werden als klickbar übernommen — alle anderen Schemata
  (`javascript:`, `data:`, `file:`, …) werden beim Parsen verworfen.
- Committen direkt auf `main` (kein Feature-Branch/Worktree, etablierte
  Projektpräferenz), ein Commit pro Task.
- Änderungen an `Feedivo/Views/Reader/ReaderContentRenderer.swift` dürfen die
  bestehende Vorschautext-Funktion `htmlToPlainText(_:)` nicht verändern — sie bleibt
  unverändert für Artikelliste/Suche.

---

### Task 1: `ReaderInlineRun`-Datenmodell + Konstruktions-Kompatibilität

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderContentRenderer.swift:1-57` (Typdeklarationen)
- Test: `FeedivoTests/FeedivoTests.swift` (neuer Test, keine Änderung an bestehenden)

**Interfaces:**
- Produces: `struct ReaderInlineRun: Equatable, Sendable { let text: String; let
  isBold: Bool; let isItalic: Bool; let linkURL: URL?; let colorHex: String? }`;
  `ReaderContentBlock.paragraph`/`.heading`/`.quote`/`.listItem` tragen jetzt
  `[ReaderInlineRun]`; vier neue Convenience-Factories
  `static func paragraph(_ text: String) -> Self` (analog für heading/quote/listItem),
  die einen einzelnen unformatierten Run erzeugen — bestehender Aufrufcode wie
  `.paragraph("Text")` bleibt dadurch **unverändert kompilierbar** (Swift wählt per
  Overload-Resolution zwischen `[ReaderInlineRun]`- und `String`-Parameter).

- [ ] **Step 1: Failing Test schreiben**

Füge in `FeedivoTests/FeedivoTests.swift` direkt nach der bestehenden Funktion
`readerContentRendererErzeugtAbsaetzeAusHTML()` (endet bei Zeile 137) diesen neuen
Test ein:

```swift
    @Test func readerContentBlockKonstruktionMitPlainStringErzeugtEinzelnenUnformatiertenRun() {
        let block = ReaderContentBlock.paragraph("Einfacher Text")

        #expect(block == .paragraph([
            ReaderInlineRun(text: "Einfacher Text", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
        ]))
    }
```

- [ ] **Step 2: Test laufen lassen, RED bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/readerContentBlockKonstruktionMitPlainStringErzeugtEinzelnenUnformatiertenRun -parallel-testing-enabled NO
```

Erwartet: Compile-Fehler — `ReaderInlineRun` existiert noch nicht,
`.paragraph([...])` ist noch kein gültiger Aufruf.

- [ ] **Step 3: `ReaderInlineRun` + Case-Migration implementieren**

In `Feedivo/Views/Reader/ReaderContentRenderer.swift` die bestehenden Zeilen 1-57
(vom Datei-Anfang bis zum Ende der `compactID`-Methode) durch Folgendes ersetzen:

```swift
import Foundation

/// Ein einzelnes, zusammenhängendes Textstück innerhalb eines Reader-Content-Blocks
/// mit optionaler Inline-Formatierung (Fett/Kursiv/Link/Farbe). Reiner, SwiftUI-
/// unabhängiger Sendable-Werttyp — die Umwandlung in `AttributedString` passiert
/// erst an der Rendering-Grenze (siehe ReaderInlineRun+AttributedString.swift).
struct ReaderInlineRun: Equatable, Sendable {
    let text: String
    let isBold: Bool
    let isItalic: Bool
    let linkURL: URL?
    let colorHex: String?
}

enum ReaderContentBlock: Equatable, Sendable {
    case paragraph([ReaderInlineRun])
    case heading([ReaderInlineRun])
    case quote([ReaderInlineRun])
    case listItem([ReaderInlineRun])
    case image(urlString: String)

    /// Erzeugt einen einzelnen, unformatierten Run — deckt den bisherigen
    /// "reiner Text ohne Formatierung"-Fall ab, damit bestehender Aufrufcode wie
    /// `.paragraph("Text")` unverändert kompiliert.
    static func paragraph(_ text: String) -> Self {
        .paragraph([ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)])
    }

    static func heading(_ text: String) -> Self {
        .heading([ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)])
    }

    static func quote(_ text: String) -> Self {
        .quote([ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)])
    }

    static func listItem(_ text: String) -> Self {
        .listItem([ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)])
    }
}

struct ReaderContentBlockEntry: Identifiable, Equatable, Sendable {
    let id: String
    let index: Int
    let block: ReaderContentBlock

    static func entries(from blocks: [ReaderContentBlock]) -> [ReaderContentBlockEntry] {
        var occurrenceCountsByID: [String: Int] = [:]

        return blocks.enumerated().map { index, block in
            let blockID = block.id
            let occurrence = occurrenceCountsByID[blockID, default: 0]
            occurrenceCountsByID[blockID] = occurrence + 1

            return ReaderContentBlockEntry(
                id: "\(blockID):\(occurrence)",
                index: index,
                block: block
            )
        }
    }
}

extension ReaderContentBlock: Identifiable {
    // Kompakte, inhaltsbasierte Basis-Identität (statt Positions-Index). Früher nutzte
    // ForEach `contentBlocks.indices, id: \.self`. Wenn der Inhalt per Refresh
    // verschoben wurde, blieb die Identität an der Position hängen und veraltete
    // Darstellung/Animationen. ReaderContentBlockEntry ergänzt bei doppelten
    // Blöcken eine Vorkommensnummer, damit SwiftUI eindeutige Listen-IDs erhält.
    var id: String {
        switch self {
        case .paragraph(let runs):
            return compactID(prefix: "p", value: runs.plainText)
        case .heading(let runs):
            return compactID(prefix: "h", value: runs.plainText)
        case .quote(let runs):
            return compactID(prefix: "q", value: runs.plainText)
        case .listItem(let runs):
            return compactID(prefix: "li", value: runs.plainText)
        case .image(let urlString):
            return compactID(prefix: "img", value: urlString)
        }
    }

    private func compactID(prefix: String, value: String) -> String {
        "\(prefix):\(value.count):\(value.hashValue)"
    }
}

private extension Array where Element == ReaderInlineRun {
    /// Reiner, verketteter Text ohne Formatierungsinformation — Basis für die
    /// inhaltsbasierte Block-Identität oben.
    var plainText: String {
        map(\.text).joined()
    }
}
```

**Wichtig:** Der Rest der Datei (ab der ursprünglichen Zeile 59, `enum
ReaderContentRenderer`) bleibt in diesem Task **unverändert** — `appendTextBlock`/
`appendTextBlocks` rufen weiterhin `.paragraph(text)`/`.heading(text)`/etc. mit
einem `String`-Argument auf, was dank der neuen Convenience-Factories weiterhin
kompiliert und identisches Verhalten liefert (ein einzelner unformatierter Run).

- [ ] **Step 4: Test laufen lassen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO
```

Erwartet: Alle Tests in `FeedivoTests` grün, inklusive des neuen Tests — die
bestehenden 12 `readerContentRenderer*`/`readerContentBlock*`-Tests aus
`FeedivoTests.swift:126-293` bleiben unverändert bestehen und grün, da sich
das beobachtbare Verhalten (noch) nicht geändert hat.

- [ ] **Step 5: Build verifizieren**

```bash
xcodebuild -scheme Feedivo -configuration Debug build
```

Erwartet: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Reader/ReaderContentRenderer.swift FeedivoTests/FeedivoTests.swift
git commit -m "$(cat <<'EOF'
Feat: ReaderInlineRun-Datenmodell für Reader-Blöcke eingeführt

ReaderContentBlock trägt jetzt [ReaderInlineRun] statt String, Convenience-
Factories erhalten bestehenden Aufrufcode (.paragraph("Text") etc.) unverändert
kompilierbar. Reiner Datenmodell-Schritt, keine Verhaltensänderung — Vorbereitung
für echte Inline-Formatierungserkennung in Task 3.
EOF
)"
```

---

### Task 2: `ReaderInlineColorSafety` — Kontrast-Sicherheitsprüfung für Farben

**Files:**
- Create: `Feedivo/Views/Reader/ReaderInlineColorSafety.swift`
- Test: `FeedivoTests/ReaderInlineColorSafetyTests.swift` (neue Datei)

**Interfaces:**
- Consumes: nichts aus Task 1 (vollständig eigenständiger, reiner Typ).
- Produces: `enum ReaderInlineColorSafety { static let lightBackgroundLuminance:
  Double; static let darkBackgroundLuminance: Double; static func
  isSafeColor(hex: String, againstBackgroundLuminance: Double) -> Bool; static
  func color(fromHex hex: String) -> Color? }` — beide Funktionen werden von
  Task 4 konsumiert.

- [ ] **Step 1: Failing Tests schreiben**

Erstelle `FeedivoTests/ReaderInlineColorSafetyTests.swift`:

```swift
import Testing
@testable import Feedivo

struct ReaderInlineColorSafetyTests {
    @Test func isSafeColorAkzeptiertDunklenTextAufHellemHintergrund() {
        #expect(ReaderInlineColorSafety.isSafeColor(
            hex: "#000000",
            againstBackgroundLuminance: ReaderInlineColorSafety.lightBackgroundLuminance
        ))
    }

    @Test func isSafeColorVerwirftDunkleFarbeAufDunklemHintergrund() {
        #expect(!ReaderInlineColorSafety.isSafeColor(
            hex: "#1A1A2E",
            againstBackgroundLuminance: ReaderInlineColorSafety.darkBackgroundLuminance
        ))
    }

    @Test func isSafeColorAkzeptiertHelleFarbeAufDunklemHintergrund() {
        #expect(ReaderInlineColorSafety.isSafeColor(
            hex: "#FFFFFF",
            againstBackgroundLuminance: ReaderInlineColorSafety.darkBackgroundLuminance
        ))
    }

    @Test func isSafeColorUnterstuetztKurzformHex() {
        #expect(ReaderInlineColorSafety.isSafeColor(
            hex: "#000",
            againstBackgroundLuminance: ReaderInlineColorSafety.lightBackgroundLuminance
        ))
    }

    @Test func isSafeColorVerwirftNichtParsebareHexWerte() {
        #expect(!ReaderInlineColorSafety.isSafeColor(
            hex: "notacolor",
            againstBackgroundLuminance: ReaderInlineColorSafety.lightBackgroundLuminance
        ))
        #expect(!ReaderInlineColorSafety.isSafeColor(
            hex: "#12345",
            againstBackgroundLuminance: ReaderInlineColorSafety.lightBackgroundLuminance
        ))
    }

    @Test func colorFromHexLiefertNilBeiUngueltigemWert() {
        #expect(ReaderInlineColorSafety.color(fromHex: "notacolor") == nil)
    }

    @Test func colorFromHexLiefertWertBeiGueltigemHex() {
        #expect(ReaderInlineColorSafety.color(fromHex: "#FF0000") != nil)
    }
}
```

- [ ] **Step 2: Test laufen lassen, RED bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderInlineColorSafetyTests -parallel-testing-enabled NO
```

Erwartet: Compile-Fehler — `ReaderInlineColorSafety` existiert noch nicht.

- [ ] **Step 3: Implementierung schreiben**

Erstelle `Feedivo/Views/Reader/ReaderInlineColorSafety.swift`:

```swift
import SwiftUI

/// Entscheidet, ob eine aus Artikel-HTML übernommene Textfarbe gegen den
/// aktuellen Reader-Hintergrund ausreichend Kontrast hat. Bewusst als reine,
/// unabhängig testbare Entscheidung ausgelagert (analog zu
/// BackgroundRefreshService.isPrematureTick(...)) — die eigentliche Anwendung
/// der Farbe passiert erst beim AttributedString-Aufbau (siehe
/// ReaderInlineRun+AttributedString.swift).
enum ReaderInlineColorSafety {
    /// Referenzhelligkeit für den hellen Reader-Hintergrund (nahezu Weiß).
    static let lightBackgroundLuminance = 1.0
    /// Referenzhelligkeit für den dunklen Reader-Hintergrund (typisches
    /// macOS-Dunkelmodus-Fensterhintergrund-Grau, kein reines Schwarz).
    static let darkBackgroundLuminance = 0.12

    /// Bewusst niedrig angesetzt (kein strenges WCAG-4.5:1-Textkontrast-Maß) —
    /// die Farbe ist eine dekorative Ergänzung zur ohnehin bereits lesbaren
    /// Standard-Textfarbe, kein alleiniger Lesbarkeits-Träger.
    private static let minimumContrastRatio = 2.5

    static func isSafeColor(hex: String, againstBackgroundLuminance backgroundLuminance: Double) -> Bool {
        guard let components = rgbComponents(fromHex: hex) else {
            return false
        }

        let colorLuminance = relativeLuminance(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
        let lighter = max(colorLuminance, backgroundLuminance)
        let darker = min(colorLuminance, backgroundLuminance)
        let contrastRatio = (lighter + 0.05) / (darker + 0.05)

        return contrastRatio >= minimumContrastRatio
    }

    static func color(fromHex hex: String) -> Color? {
        guard let components = rgbComponents(fromHex: hex) else {
            return nil
        }

        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    private static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func rgbComponents(fromHex hex: String) -> (red: Double, green: Double, blue: Double)? {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }

        let expanded: String
        switch normalized.count {
        case 3:
            expanded = normalized.map { "\($0)\($0)" }.joined()
        case 6:
            expanded = normalized
        default:
            return nil
        }

        guard let value = Int(expanded, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return (red, green, blue)
    }
}
```

- [ ] **Step 4: Test laufen lassen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderInlineColorSafetyTests -parallel-testing-enabled NO
```

Erwartet: Alle 7 Tests grün.

- [ ] **Step 5: Build verifizieren**

```bash
xcodebuild -scheme Feedivo -configuration Debug build
```

Erwartet: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Reader/ReaderInlineColorSafety.swift FeedivoTests/ReaderInlineColorSafetyTests.swift
git commit -m "$(cat <<'EOF'
Feat: ReaderInlineColorSafety prüft Artikel-Textfarben auf Kontrast

Reine, unabhängig testbare Policy-Funktion — verwirft Hex-Farben aus fremdem
Artikel-HTML, die gegen den aktuellen Hell-/Dunkelmodus-Hintergrund zu wenig
Kontrast hätten. Eigenständiger Baustein, noch nicht in den Reader verdrahtet.
EOF
)"
```

---

### Task 3: Inline-Tag-Parser (`inlineRuns(fromHTML:)`)

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderContentRenderer.swift`
- Test: `FeedivoTests/FeedivoTests.swift`

**Interfaces:**
- Consumes: `ReaderInlineRun` aus Task 1.
- Produces: `static func inlineRuns(fromHTML html: String) -> [ReaderInlineRun]`
  — wird von Task 4 indirekt genutzt (bereits in diesem Task in
  `appendTextBlock`/`appendTextBlocks` verdrahtet, die Blöcke selbst tragen ab
  hier echte formatierte Runs).

- [ ] **Step 1: Failing Tests schreiben**

Ersetze in `FeedivoTests/FeedivoTests.swift` die drei betroffenen bestehenden
Tests (deren Erwartungen sich durch die neue Formatierungserkennung ändern) und
füge sechs neue Tests hinzu. Ersetze zunächst
`readerContentRendererErzeugtAbsaetzeAusHTML()` (Zeilen 126-137):

```swift
    @Test func readerContentRendererErzeugtAbsaetzeAusHTML() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: "<p>Erster <strong>Absatz</strong>.</p><p>Zweiter Absatz.</p>",
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph([
                ReaderInlineRun(text: "Erster ", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: "Absatz", isBold: true, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: ".", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
            ]),
            .paragraph("Zweiter Absatz.")
        ])
    }
```

Ersetze `readerContentRendererErkenntStrukturierteTextbloecke()` (Zeilen 215-237):

```swift
    @Test func readerContentRendererErkenntStrukturierteTextbloecke() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: """
            <h2>Zwischentitel</h2>
            <p>Ein normaler Absatz.</p>
            <blockquote>Ein zitiertes Argument.</blockquote>
            <ul>
                <li>Erster Punkt</li>
                <li>Zweiter Punkt mit <strong>Betonung</strong></li>
            </ul>
            """,
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .heading("Zwischentitel"),
            .paragraph("Ein normaler Absatz."),
            .quote("Ein zitiertes Argument."),
            .listItem("Erster Punkt"),
            .listItem([
                ReaderInlineRun(text: "Zweiter Punkt mit ", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: "Betonung", isBold: true, isItalic: false, linkURL: nil, colorHex: nil)
            ])
        ])
    }
```

Ersetze `readerContentRendererDekodiertHTMLEntitiesOhneWebKitPfad()` (Zeilen 259-273):

```swift
    @Test func readerContentRendererDekodiertHTMLEntitiesOhneWebKitPfad() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: """
            <p>AT&amp;T &lt; Telekom&nbsp;— &#8230;</p>
            <p>Link: <a href="https://example.com">öffnen</a><br>Neue Zeile</p>
            """,
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph("AT&T < Telekom — …"),
            .paragraph([
                ReaderInlineRun(text: "Link: ", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: "öffnen", isBold: false, isItalic: false, linkURL: URL(string: "https://example.com"), colorHex: nil),
                ReaderInlineRun(text: " Neue Zeile", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
            ])
        ])
    }
```

Füge direkt danach (nach der soeben ersetzten Funktion) diese sechs neuen Tests ein:

```swift
    @Test func readerContentRendererErkenntKursivSchrift() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: "<p>Ein <em>betonter</em> Satz.</p>",
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph([
                ReaderInlineRun(text: "Ein ", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: "betonter", isBold: false, isItalic: true, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: " Satz.", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
            ])
        ])
    }

    @Test func readerContentRendererVerwirftUnsichereLinkSchemata() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: #"<p>Klick <a href="javascript:alert(1)">hier</a>.</p>"#,
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph([
                ReaderInlineRun(text: "Klick ", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: "hier", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: ".", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
            ])
        ])
    }

    @Test func readerContentRendererIgnoriertDataHrefAttribute() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: #"<p><a data-href="https://tracking.example.com/click">Text</a></p>"#,
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph([
                ReaderInlineRun(text: "Text", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
            ])
        ])
    }

    @Test func readerContentRendererUebernimmtHexFarbeAusSpanStyle() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: #"<p>Ein <span style="color:#FF0000">roter</span> Begriff.</p>"#,
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph([
                ReaderInlineRun(text: "Ein ", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: "roter", isBold: false, isItalic: false, linkURL: nil, colorHex: "#FF0000"),
                ReaderInlineRun(text: " Begriff.", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
            ])
        ])
    }

    @Test func readerContentRendererIgnoriertUngueltigeFarbwerte() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: #"<p>Kein <span style="color:notacolor">Wert</span>.</p>"#,
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph([
                ReaderInlineRun(text: "Kein ", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: "Wert", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: ".", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
            ])
        ])
    }

    @Test func readerContentRendererIgnoriertBackgroundColorStattTextfarbe() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: #"<p>Kein <span style="background-color:#FF0000">Text</span>.</p>"#,
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph([
                ReaderInlineRun(text: "Kein ", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: "Text", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
                ReaderInlineRun(text: ".", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
            ])
        ])
    }

    @Test func readerContentRendererVerschachteltFettUndLinkEineEbene() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: #"<p><b><a href="https://example.com">Wichtiger Link</a></b></p>"#,
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph([
                ReaderInlineRun(
                    text: "Wichtiger Link",
                    isBold: true,
                    isItalic: false,
                    linkURL: URL(string: "https://example.com"),
                    colorHex: nil
                )
            ])
        ])
    }
```

- [ ] **Step 2: Test laufen lassen, RED bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO
```

Erwartet: Die drei ersetzten Tests UND die sechs neuen Tests schlagen fehl (alter
Parser strippt weiterhin alles zu reinem Text) — alle anderen Tests bleiben grün.

- [ ] **Step 3: Parser implementieren**

In `Feedivo/Views/Reader/ReaderContentRenderer.swift`, füge nach den bestehenden
Regex-Konstanten (nach `entityExpression`, vor `static func blocks(...)`) diese
neuen Regex-Konstanten ein:

```swift
    private static let inlineTagExpression = try! NSRegularExpression(
        pattern: #"<(a|b|strong|i|em|span)\b([^>]*)>(.*?)</\1>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let hrefAttributeExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)href\s*=\s*["']([^"']*)["']"#,
        options: [.caseInsensitive]
    )
    private static let styleAttributeExpression = try! NSRegularExpression(
        pattern: #"style\s*=\s*["']([^"']*)["']"#,
        options: [.caseInsensitive]
    )
    private static let colorDeclarationExpression = try! NSRegularExpression(
        pattern: #"(?:^|;)\s*color\s*:\s*(#[0-9A-Fa-f]{3}|#[0-9A-Fa-f]{6})"#,
        options: [.caseInsensitive]
    )
```

Ersetze anschließend `appendTextBlocks(from:to:)` und `appendTextBlock(from:tag:to:)`
(bestehende Zeilen 219-250) durch:

```swift
    private static func appendTextBlocks(from html: String, to blocks: inout [ReaderContentBlock]) {
        let htmlWithoutListContainers = stringByReplacingMatches(
            in: html,
            expression: listContainerExpression,
            replacement: ""
        )

        for runs in splitIntoParagraphRuns(fromPreparedHTML: htmlWithoutListContainers) {
            blocks.append(.paragraph(runs))
        }
    }

    private static func appendTextBlock(from html: String, tag: String, to blocks: inout [ReaderContentBlock]) {
        let runs = inlineRuns(fromHTML: html)
        guard !runs.isEmpty else {
            return
        }

        if tag.hasPrefix("h") {
            blocks.append(.heading(runs))
            return
        }

        switch tag {
        case "blockquote":
            blocks.append(.quote(runs))
        case "li":
            blocks.append(.listItem(runs))
        default:
            blocks.append(.paragraph(runs))
        }
    }

    /// Zerlegt HTML mit `<br>`/Block-Grenzen in mehrere Absätze (ein Aufruf von
    /// `paragraphs(fromPreparedHTML:)` liefert die Zeilengrenzen als reine
    /// Strings), parst dann jede Zeile einzeln auf Inline-Formatierung — die
    /// Grenzen selbst müssen weiterhin auf Basis von reinem Text erkannt werden,
    /// da `<br>`/Block-Tags Absatzgrenzen markieren, keine Formatierung.
    private static func splitIntoParagraphRuns(fromPreparedHTML htmlOrText: String) -> [[ReaderInlineRun]] {
        paragraphs(fromPreparedHTML: htmlOrText).map { [ReaderInlineRun(text: $0, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)] }
    }

    /// Erkennt Inline-Formatierung (Fett/Kursiv/Link/Farbe) in HTML-Text und
    /// zerlegt ihn in Runs. Eine Ebene Verschachtelung unterschiedlicher Tags
    /// wird unterstützt (z. B. `<b><a href="...">Link</a></b>`); Verschachtelung
    /// des GLEICHEN Tags (`<b>a<b>b</b>c</b>`) nicht — Regex kann
    /// Verschachtelungstiefe nicht zählen (bestehende Einschränkung dieser
    /// Datei, analog zu `structuredBlockExpression` auf Block-Ebene).
    static func inlineRuns(fromHTML html: String) -> [ReaderInlineRun] {
        var runs = rawInlineRuns(fromHTML: html)
        trimOuterWhitespace(&runs)
        return runs
    }

    private static func rawInlineRuns(fromHTML html: String) -> [ReaderInlineRun] {
        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        let matches = inlineTagExpression.matches(in: html, range: range)
        guard !matches.isEmpty else {
            return plainInlineRuns(fromHTML: html)
        }

        var runs: [ReaderInlineRun] = []
        var currentIndex = html.startIndex

        for match in matches {
            guard
                let matchRange = Range(match.range, in: html),
                let tagRange = Range(match.range(at: 1), in: html),
                let attributesRange = Range(match.range(at: 2), in: html),
                let innerRange = Range(match.range(at: 3), in: html)
            else {
                continue
            }

            runs.append(contentsOf: plainInlineRuns(fromHTML: String(html[currentIndex ..< matchRange.lowerBound])))

            let tag = String(html[tagRange]).lowercased()
            let attributes = String(html[attributesRange])
            let innerRuns = rawInlineRuns(fromHTML: String(html[innerRange]))
            runs.append(contentsOf: applyingInlineStyle(tag: tag, attributes: attributes, to: innerRuns))

            currentIndex = matchRange.upperBound
        }

        runs.append(contentsOf: plainInlineRuns(fromHTML: String(html[currentIndex ..< html.endIndex])))
        return runs
    }

    private static func plainInlineRuns(fromHTML html: String) -> [ReaderInlineRun] {
        let text = normalizedInlineWhitespace(htmlToPlainText(html))
        guard !text.isEmpty else {
            return []
        }
        return [ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)]
    }

    private static func applyingInlineStyle(
        tag: String,
        attributes: String,
        to innerRuns: [ReaderInlineRun]
    ) -> [ReaderInlineRun] {
        guard !innerRuns.isEmpty else {
            return []
        }

        let isBold = tag == "b" || tag == "strong"
        let isItalic = tag == "i" || tag == "em"
        let linkURL = tag == "a" ? safeLinkURL(fromAttributes: attributes) : nil
        let colorHex = colorHex(fromAttributes: attributes)

        return innerRuns.map { run in
            ReaderInlineRun(
                text: run.text,
                isBold: run.isBold || isBold,
                isItalic: run.isItalic || isItalic,
                linkURL: run.linkURL ?? linkURL,
                colorHex: run.colorHex ?? colorHex
            )
        }
    }

    private static func safeLinkURL(fromAttributes attributes: String) -> URL? {
        guard
            let match = hrefAttributeExpression.firstMatch(in: attributes, range: NSRange(attributes.startIndex ..< attributes.endIndex, in: attributes)),
            let hrefRange = Range(match.range(at: 1), in: attributes)
        else {
            return nil
        }

        let value = String(attributes[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }

        return url
    }

    private static func colorHex(fromAttributes attributes: String) -> String? {
        guard
            let styleMatch = styleAttributeExpression.firstMatch(in: attributes, range: NSRange(attributes.startIndex ..< attributes.endIndex, in: attributes)),
            let styleValueRange = Range(styleMatch.range(at: 1), in: attributes)
        else {
            return nil
        }

        let styleValue = String(attributes[styleValueRange])
        guard
            let colorMatch = colorDeclarationExpression.firstMatch(in: styleValue, range: NSRange(styleValue.startIndex ..< styleValue.endIndex, in: styleValue)),
            let colorRange = Range(colorMatch.range(at: 1), in: styleValue)
        else {
            return nil
        }

        return String(styleValue[colorRange]).uppercased()
    }

    /// Wie `normalizedWhitespace`, aber ohne die Außenränder zu trimmen — das
    /// übernimmt `trimOuterWhitespace` über die gesamte Run-Liste hinweg, sonst
    /// gingen Leerzeichen an Segmentgrenzen verloren (z. B. "Text vor
    /// <b>fett</b> danach").
    private static func normalizedInlineWhitespace(_ text: String) -> String {
        var result = ""
        var previousWasWhitespace = false
        for character in text {
            if character.isWhitespace {
                if !previousWasWhitespace {
                    result.append(" ")
                }
                previousWasWhitespace = true
            } else {
                result.append(character)
                previousWasWhitespace = false
            }
        }
        return result
    }

    private static func trimOuterWhitespace(_ runs: inout [ReaderInlineRun]) {
        guard !runs.isEmpty else {
            return
        }

        if let first = runs.first {
            runs[0] = ReaderInlineRun(
                text: String(first.text.drop { $0 == " " }),
                isBold: first.isBold,
                isItalic: first.isItalic,
                linkURL: first.linkURL,
                colorHex: first.colorHex
            )
        }

        if let last = runs.last {
            let trimmedText = String(String(last.text.reversed()).drop { $0 == " " }.reversed())
            runs[runs.count - 1] = ReaderInlineRun(
                text: trimmedText,
                isBold: last.isBold,
                isItalic: last.isItalic,
                linkURL: last.linkURL,
                colorHex: last.colorHex
            )
        }

        runs.removeAll { $0.text.isEmpty }
    }
```

- [ ] **Step 4: Test laufen lassen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO
```

Erwartet: Alle Tests in `FeedivoTests` grün, inklusive der drei aktualisierten
und sechs neuen Tests.

- [ ] **Step 5: Build verifizieren**

```bash
xcodebuild -scheme Feedivo -configuration Debug build
```

Erwartet: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Reader/ReaderContentRenderer.swift FeedivoTests/FeedivoTests.swift
git commit -m "$(cat <<'EOF'
Feat: Inline-Tag-Parser erkennt Fett/Kursiv/Links/Farben im Artikel-HTML

inlineRuns(fromHTML:) ersetzt die bisherige pauschale Tag-Entfernung in
appendTextBlock/appendTextBlocks für a/b/strong/i/em/span. Links nur bei
http(s)-Schema, Farben nur als Hex aus style=color (auch auf <span>). Eine
Ebene Verschachtelung unterschiedlicher Tags wird unterstützt.
EOF
)"
```

---

### Task 4: Rendering — `AttributedString`-Konvertierung + `SQLiteReaderView`-Verdrahtung

**Files:**
- Create: `Feedivo/Views/Reader/ReaderInlineRun+AttributedString.swift`
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift:1-9` (Environment-Properties)
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift:319-337` (`.environment(\.openURL, ...)`)
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift:646-700` (`contentBlock(_:)`)
- Test: `FeedivoTests/ReaderInlineRunAttributedStringTests.swift` (neue Datei)

**Interfaces:**
- Consumes: `ReaderInlineRun` (Task 1), `ReaderInlineColorSafety.isSafeColor`/
  `.color(fromHex:)` (Task 2), `ReaderContentBlock.paragraph`/etc. mit echten
  Runs (Task 3).
- Produces: `extension Array where Element == ReaderInlineRun { func
  attributedString(colorScheme: ColorScheme) -> AttributedString }`.

- [ ] **Step 1: Failing Test schreiben**

Erstelle `FeedivoTests/ReaderInlineRunAttributedStringTests.swift`:

```swift
import SwiftUI
import Testing
@testable import Feedivo

struct ReaderInlineRunAttributedStringTests {
    @Test func attributedStringSetztLinkAttribut() {
        let runs = [
            ReaderInlineRun(text: "Text", isBold: false, isItalic: false, linkURL: URL(string: "https://example.com"), colorHex: nil)
        ]

        let attributed = runs.attributedString(colorScheme: .light)

        #expect(attributed.link == URL(string: "https://example.com"))
    }

    @Test func attributedStringSetztFettUndKursivIntent() {
        let runs = [
            ReaderInlineRun(text: "Text", isBold: true, isItalic: true, linkURL: nil, colorHex: nil)
        ]

        let attributed = runs.attributedString(colorScheme: .light)
        let intent = attributed.runs.first?.inlinePresentationIntent

        #expect(intent == [.stronglyEmphasized, .emphasized])
    }

    @Test func attributedStringVerwirftFarbeOhneAusreichendenKontrast() {
        let runs = [
            ReaderInlineRun(text: "Text", isBold: false, isItalic: false, linkURL: nil, colorHex: "#1A1A2E")
        ]

        let attributed = runs.attributedString(colorScheme: .dark)

        #expect(attributed.runs.first?.foregroundColor == nil)
    }

    @Test func attributedStringUebernimmtFarbeMitAusreichendemKontrast() {
        let runs = [
            ReaderInlineRun(text: "Text", isBold: false, isItalic: false, linkURL: nil, colorHex: "#FF0000")
        ]

        let attributed = runs.attributedString(colorScheme: .light)

        #expect(attributed.runs.first?.foregroundColor != nil)
    }

    @Test func attributedStringVerkettetMehrereRunsZuEinemString() {
        let runs = [
            ReaderInlineRun(text: "Vor ", isBold: false, isItalic: false, linkURL: nil, colorHex: nil),
            ReaderInlineRun(text: "fett", isBold: true, isItalic: false, linkURL: nil, colorHex: nil),
            ReaderInlineRun(text: " danach", isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
        ]

        let attributed = runs.attributedString(colorScheme: .light)

        #expect(String(attributed.characters) == "Vor fett danach")
    }
}
```

- [ ] **Step 2: Test laufen lassen, RED bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderInlineRunAttributedStringTests -parallel-testing-enabled NO
```

Erwartet: Compile-Fehler — `attributedString(colorScheme:)` existiert noch nicht.

- [ ] **Step 3: Konvertierungsfunktion implementieren**

Erstelle `Feedivo/Views/Reader/ReaderInlineRun+AttributedString.swift`:

```swift
import SwiftUI

extension Array where Element == ReaderInlineRun {
    /// Baut aus den Runs eines Reader-Content-Blocks eine einzige
    /// `AttributedString` — Fett/Kursiv über `inlinePresentationIntent` (von
    /// `Text(AttributedString)` automatisch gerendert), Link über `.link`
    /// (macht den Bereich automatisch tippbar), Farbe nur wenn
    /// `ReaderInlineColorSafety` gegen den aktuellen Farbmodus zustimmt.
    func attributedString(colorScheme: ColorScheme) -> AttributedString {
        let backgroundLuminance = colorScheme == .dark
            ? ReaderInlineColorSafety.darkBackgroundLuminance
            : ReaderInlineColorSafety.lightBackgroundLuminance

        var result = AttributedString()

        for run in self {
            var segment = AttributedString(run.text)

            var intent: InlinePresentationIntent = []
            if run.isBold {
                intent.insert(.stronglyEmphasized)
            }
            if run.isItalic {
                intent.insert(.emphasized)
            }
            if !intent.isEmpty {
                segment.inlinePresentationIntent = intent
            }

            if let linkURL = run.linkURL {
                segment.link = linkURL
            }

            if
                let colorHex = run.colorHex,
                ReaderInlineColorSafety.isSafeColor(hex: colorHex, againstBackgroundLuminance: backgroundLuminance),
                let color = ReaderInlineColorSafety.color(fromHex: colorHex)
            {
                segment.foregroundColor = color
            }

            result += segment
        }

        return result
    }
}
```

- [ ] **Step 4: Test laufen lassen, GREEN bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderInlineRunAttributedStringTests -parallel-testing-enabled NO
```

Erwartet: Alle 5 Tests grün.

- [ ] **Step 5: `SQLiteReaderView` verdrahten**

In `Feedivo/Views/Reader/SQLiteReaderView.swift`, Zeile 9 (nach
`@Environment(\.openWindow) private var openWindow`) ergänzen:

```swift
    @Environment(\.colorScheme) private var colorScheme
```

In derselben Datei, den bestehenden `body`-Modifier-Chain direkt nach der
schließenden Klammer des `Group { ... }`-Blocks (aktuell Zeile 336, unmittelbar
vor `.navigationTitle(state.snapshot?.title ?? "")`) um diesen Modifier ergänzen:

```swift
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
```

Ersetze anschließend `contentBlock(_:)` (bestehende Zeilen 646-700) durch:

```swift
    private func contentBlock(_ block: ReaderContentBlock) -> some View {
        switch block {
        case .paragraph(let runs):
            Text(runs.attributedString(colorScheme: colorScheme))
                .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                .fontWeight(bodyFontWeight)
                .lineSpacing(clampedLineSpacing)
        case .heading(let runs):
            Text(runs.attributedString(colorScheme: colorScheme))
                .font(bodyFontPreset.font(
                    size: min(clampedBodyFontSize + 5, CGFloat(ReaderTypography.defaultTitleFontSize - 2)),
                    relativeTo: .title3,
                    weight: contentHeadingFontWeight
                ))
                .fontWeight(contentHeadingFontWeight)
                .lineSpacing(clampedLineSpacing)
        case .quote(let runs):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 3)

                Text(runs.attributedString(colorScheme: colorScheme))
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineSpacing(clampedLineSpacing)
            }
            .padding(.vertical, 2)
        case .listItem(let runs):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "•")
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .foregroundStyle(.secondary)

                Text(runs.attributedString(colorScheme: colorScheme))
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .lineSpacing(clampedLineSpacing)
            }
        case .image(let urlString):
            CachedRemoteImageView(url: URL(string: urlString), targetPixelSize: readerImageTargetPixelSize) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(height: 180)
            }
        }
    }
```

- [ ] **Step 6: Gezielten Testlauf + Build verifizieren**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -only-testing:FeedivoTests/ReaderInlineColorSafetyTests -only-testing:FeedivoTests/ReaderInlineRunAttributedStringTests -parallel-testing-enabled NO
xcodebuild -scheme Feedivo -configuration Debug build
```

Erwartet: Alle Tests grün, `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Reader/ReaderInlineRun+AttributedString.swift Feedivo/Views/Reader/SQLiteReaderView.swift FeedivoTests/ReaderInlineRunAttributedStringTests.swift
git commit -m "$(cat <<'EOF'
Feat: Reader zeigt Fett/Kursiv/Links/Farben aus Artikel-HTML an

SQLiteReaderView baut Runs jetzt über eine AttributedString-Konvertierung mit
Text(AttributedString) statt Text(String). Links öffnen explizit im
Standardbrowser (NSWorkspace.shared.open), Farben laufen durch die
Kontrast-Sicherheitsprüfung aus ReaderInlineColorSafety.
EOF
)"
```

---

### Task 5: Whole-Branch-Review + manuelle Live-Verifikation vorbereiten

**Files:** keine Code-Änderungen — Review- und Abschluss-Task.

- [ ] **Step 1: Vollständigen gezielten Regressionslauf**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/FeedivoTests \
  -only-testing:FeedivoTests/ReaderInlineColorSafetyTests \
  -only-testing:FeedivoTests/ReaderInlineRunAttributedStringTests \
  -parallel-testing-enabled NO
```

Erwartet: Alle Tests grün.

- [ ] **Step 2: Release-Build**

```bash
xcodebuild -scheme Feedivo -configuration Release build
```

Erwartet: `BUILD SUCCEEDED`.

- [ ] **Step 3: Whole-Branch-Review**

Vollständigen Diff über alle vier Tasks (`git diff origin/main..HEAD` bzw. gegen
den Stand vor Task 1) durch einen frischen Reviewer-Blick prüfen lassen —
insbesondere: Konsistenz zwischen Task 3 (Parser-Regexe) und Task 4
(Rendering-Verdrahtung), keine übersehenen Stellen, an denen `ReaderContentBlock`
noch mit altem `String`-Payload angenommen wird (z. B. andere Konsumenten von
`ReaderContentBlock` außerhalb von `SQLiteReaderView.swift` — vorab per
`grep -rn "case \.paragraph\|case \.heading\|case \.quote\|case \.listItem"
Feedivo/` prüfen, ob es weitere Konsumenten gibt, die in diesem Plan nicht
berücksichtigt wurden).

- [ ] **Step 4: Manuelle Live-Verifikationscheckliste dokumentieren**

Folgende Punkte sind nicht automatisierbar (kein computer-use für native
macOS-Apps) und müssen vom Nutzer live geprüft werden:
1. Artikel mit Fettschrift im Originaltext öffnen — native Reader-Ansicht zeigt
   die Stellen fett.
2. Artikel mit Kursivschrift — zeigt kursiv.
3. Artikel mit einem Link im Fließtext — Link ist farbig/erkennbar, Klick öffnet
   die Ziel-URL im Standardbrowser (nicht in-App).
4. Artikel mit farbig ausgezeichnetem Text (`<span style="color:...">`) — Farbe
   erscheint im Hellmodus.
5. Denselben Artikel im Dunkelmodus öffnen — falls die Originalfarbe zu wenig
   Kontrast hätte, erscheint Standardtextfarbe statt der Originalfarbe.
6. Artikelliste-Vorschau und Suchfenster zeigen weiterhin unformatierten
   Vorschautext (unverändertes Verhalten, kein Regressionsrisiko, aber bewusst
   gegenzuprüfen).

## Self-Review (durchgeführt vor Übergabe)

- **Spec-Abdeckung:** Datenmodell (Task 1), Farb-Sicherheit (Task 2), Parser
  inkl. Link-Schema-Whitelist und span-Farben (Task 3), Rendering inkl.
  Standardbrowser-Öffnen (Task 4) — alle Spec-Abschnitte haben eine Task.
- **Platzhalter-Scan:** Keine TBD/TODO, jeder Schritt enthält vollständigen,
  copy-paste-fähigen Code.
- **Typ-Konsistenz:** `ReaderInlineRun`-Feldnamen (`text`, `isBold`, `isItalic`,
  `linkURL`, `colorHex`) identisch in Task 1 (Definition), Task 3 (Parser-
  Konstruktion) und Task 4 (Konsum in `attributedString(colorScheme:)`) —
  geprüft, keine Abweichung.
