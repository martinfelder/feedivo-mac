# Artikelliste: Feste Zeilenhöhe für `ArticleRowView` — Design

Stand: 2026-07-28

## Ausgangspunkt

Teil des NetNewsWire-Performance-Vergleichs (`docs/performance/netnewswire-feedivo-mechanik-vergleich.md`,
Update 2026-07-28, Empfehlung Punkt 4). NetNewsWires größter Einzelhebel für
gefühlte Scroll-Geschwindigkeit ist eine uniforme, einmalig berechnete
Zeilenhöhe in der `NSTableView` — SwiftUIs `List` muss dadurch nie pro
sichtbarer Zeile Text-Layout/Auto-Sizing neu berechnen. Feedivos
`ArticleRowView` (`Feedivo/Views/ArticleList/ArticleRowView.swift`) sizet
sich aktuell natürlich am Inhalt (variable Zeilenzahl bei Titel/Summary).

## Ziel

`ArticleRowView` bekommt eine feste, aus den aktuellen Anzeige-Einstellungen
berechnete Höhe. Kürzere Titel/Summaries lassen dadurch Leerraum statt sich
eng an den Inhalt anzuschmiegen — dieser Trade-off wurde mit dem Nutzer
abgestimmt und akzeptiert.

## Nicht-Ziel

Kein Umstieg auf `NSTableView`/AppKit (Architekturbruch gegen ADR-004/005).
Keine Änderung an der Such-/Menubar-Zeilenansicht über `ArticleRowView`
hinaus (Menubar-Dropdown nutzt `ArticleRowView` mit, profitiert automatisch
mit, ist aber kein primäres Ziel — kein separater Scroll-Performance-Case).

## Architektur

### `ArticleRowHeightMetrics` (neu, reine Funktion)

Neue Datei `Feedivo/Views/ArticleList/ArticleRowHeightMetrics.swift`:

```swift
enum ArticleRowHeightMetrics {
    static func height(
        interfaceTextSize: InterfaceTextSize,
        imagePosition: ArticleListImagePosition,
        summaryLineCount: Int
    ) -> CGFloat
}
```

Berechnet die Höhe **ausschließlich** aus den drei genannten, app-weiten
`@AppStorage`-Einstellungen — nie aus tatsächlichem Artikelinhalt (Titel-
/Summary-Text, Datum, Feedname). Das ist die Grundvoraussetzung für eine
wirklich uniforme Zeilenhöhe.

Berechnungsschritte:

1. **Zeilenhöhen per Font-Metrik** über `NSLayoutManager().defaultLineHeight(for:)`
   für `NSFont.systemFont(ofSize:)` bei den drei in `ArticleRowView` bereits
   verwendeten, skalierten Punktgrößen (Titel 14pt, Metadaten-Zeile 11pt,
   Summary 13pt — `interfaceTextSize.scaled(...)` angewendet wie im
   bestehenden Code). Die Font-Weight-Variante (regular/semibold beim Titel)
   wird ignoriert — beim System-Font ändert das die Zeilenhöhen-Metrik nicht
   relevant.
2. **Titel:** immer 2 Zeilen (entspricht `.lineLimit(2)`).
3. **Metadaten-Zeile (Feedname+Datum):** immer 1 Zeile reserviert — auch für
   den seltenen Fall, dass ein einzelner Artikel weder Datum noch (bei
   ausgeblendetem Feednamen) Metadatentext hat. Das hält die Höhe
   vollständig content-unabhängig (siehe Nicht-Ziel oben).
4. **Summary:** `summaryLineCount` Zeilen, falls `summaryLineCount > 0`,
   sonst 0.
5. **VStack-Spacing:** 6pt je Lücke zwischen den sichtbaren Elementen
   (Metadaten-Zeile + Titel sind immer sichtbar, Summary optional) —
   `elementCount = 2 + (summaryLineCount > 0 ? 1 : 0)`,
   `spacingTotal = 6 * (elementCount - 1)`.
6. **Textstapel-Höhe:** Summe aus 2.–5.
7. **Bildhöhe:** `imagePosition == .hidden ? 0 : interfaceTextSize.scaled(56)`
   (entspricht dem bestehenden `previewImageSide`).
8. **Inhaltshöhe:** `max(Textstapel-Höhe, Bildhöhe)`.
9. **Gesamthöhe:** Inhaltshöhe + bestehendes vertikales Padding (12pt,
   `.padding(.vertical, 6)` oben und unten) + Sicherheitspuffer (4pt) gegen
   minimale Abweichungen zwischen `NSFont`- und SwiftUI-`Text`-Metriken.

### `ArticleRowView`-Verdrahtung

- Neue private computed property `rowContentHeight` (Inhaltshöhe ohne
  äußeres Padding, Schritt 8) und `rowTotalHeight` (Schritt 9), aus den
  bereits vorhandenen `@AppStorage`/`@Environment`-Properties gespeist.
- `.frame(height: rowTotalHeight, alignment: .top)` auf die äußere `HStack`
  (nach dem bestehenden `.padding(...)`).
- Die rechte Spalte (Ungelesen-Punkt + Stern-Button) hat aktuell eine
  hartcodierte `height: 76` (`Feedivo/Views/ArticleList/ArticleRowView.swift:100`)
  — offensichtlich eine grobe, nicht textgrößen-skalierte Annäherung an die
  bisherige variable Höhe. Wird auf `rowContentHeight` umgestellt, sonst
  könnte der Stern-Button bei kleiner Textgröße/kurzer Summary-Einstellung
  über den neuen, dann kürzeren Rahmen hinausragen.

## Testing

- **TDD für `ArticleRowHeightMetrics`** (neue Datei
  `FeedivoTests/ArticleRowHeightMetricsTests.swift`): reine Funktion, kein
  SwiftUI-Rendering nötig.
  - Höhe steigt monoton mit `summaryLineCount` (0 → 1 → 2 → 3).
  - Höhe skaliert mit `interfaceTextSize` (größere Textgröße → größere Höhe).
  - Bildhöhe wirkt als Untergrenze: bei `summaryLineCount: 0` und `.small`-
    Textgröße mit `imagePosition: .left` ist die Gesamthöhe mindestens groß
    genug für das 56pt-Bild (skaliert) + Padding.
  - `imagePosition: .hidden` beeinflusst die Höhe nicht (kein Bild-Floor).
- **`ArticleRowView`-Verdrahtung selbst** ist wie der Rest des Projekts
  nicht automatisiert testbar (kein ViewInspector/UI-Testing-Framework) —
  Build-Verifikation plus manuelle Live-Prüfung durch den Nutzer
  (verschiedene Textgrößen-/Summary-Einstellungen durchklicken, kein
  Clipping des Stern-Buttons oder abgeschnittener Inhalt).

## Offene Punkte / Risiken

- Kein computer-use für native macOS-Apps in dieser Umgebung verfügbar —
  die visuelle Verifikation (kein Clipping, akzeptabler Leerraum bei kurzen
  Titeln) bleibt manuell durch den Nutzer zu bestätigen.
- Der 4pt-Sicherheitspuffer ist eine Schätzung, kein gemessener Wert (siehe
  Ansatz-A-vs-B-Abwägung in der Diskussion) — falls beim Live-Test doch
  Clipping auftritt, ist eine Erhöhung dieses einzelnen Werts der
  naheliegende Nachbesserungspunkt.
