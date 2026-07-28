# Design: Mehrfach-Tag-Filterung in der Artikelsuche

**Datum:** 2026-07-13
**Status:** Genehmigt, bereit für Implementierungsplan

## Ausgangslage

Die Artikelsuche (`Feedivo/Views/ArticleList/ArticleSearchWindowView.swift`) hat
bereits eine Tag-Filterung, aber nur als Einzelauswahl: `searchTagPicker`, ein
einfacher `Picker` gebunden an `ArticleSearchWindowState.tagID: UUID?` ("Alle
Tags" oder genau ein Tag). Die zugrunde liegende SQL-Logik in
`ArticleStore.searchArticles(state:)` (`Feedivo/Stores/ArticleStore.swift:265`)
berücksichtigt bereits, dass ein Tag sowohl direkt am Artikel
(`article_tags`) als auch am zugehörigen Feed (`feed_tags`) hängen kann — ein
Artikel gilt als getaggt, wenn eine der beiden Zuordnungen zutrifft.

## Ziel

Mehrfachauswahl von Tags in der Suche, mit einem vom Nutzer wählbaren
Verknüpfungsmodus:
- **Mind. einer** (Default): Artikel hat mindestens einen der ausgewählten Tags.
- **Alle**: Artikel hat alle ausgewählten Tags gleichzeitig.

## Nicht-Ziele

- Keine Änderung an der bestehenden "Tag hängt am Artikel ODER am Feed"-Semantik
  — nur die Verallgemeinerung von einem auf mehrere Tags.
- Keine Änderung an anderen Suchfiltern (Feld, Feed, Datum, Status).
- Keine Änderung an Smart Folders / `RuleEngine` — diese haben ihre eigene,
  unabhängige Tag-Bedingungslogik und sind nicht Teil dieser Anfrage.

## Datenmodell (`Feedivo/Views/ArticleList/ArticleListQuery.swift`)

Neues Enum, analog zu den bestehenden Such-Enums in derselben Datei:

```swift
enum ArticleSearchTagMatchMode: String, CaseIterable, Identifiable {
    case any
    case all

    var id: String {
        rawValue
    }
}
```

`ArticleSearchFilters`, `ArticleSearchQuery` und `ArticleSearchWindowState`
ersetzen jeweils `tagID: UUID?` durch:

```swift
var tagIDs: Set<UUID> = []
var tagMatchMode: ArticleSearchTagMatchMode = .any
```

`ArticleSearchFilters.isActive` prüft künftig `!tagIDs.isEmpty` statt
`tagID != nil` (Rest der Bedingung unverändert). `ArticleSearchWindowState.query`
gibt beide neuen Felder an `ArticleSearchFilters` weiter, exakt wie bisher bei
`tagID`.

## SQL-Schicht (`ArticleStore.searchArticles(state:)`)

Die bestehende Tag-`WHERE`-Klausel-Konstruktion (aktuell ab
`Feedivo/Stores/ArticleStore.swift:285`) wird ersetzt. Beide Verknüpfungsmodi
teilen sich dieselbe Subquery (alle Tags, die am Artikel ODER am Feed hängen),
nur der äußere Vergleich unterscheidet sich:

```sql
-- state.tagMatchMode == .any:
EXISTS (
    SELECT 1 FROM (
        SELECT tagID FROM article_tags WHERE articleID = a.id
        UNION
        SELECT tagID FROM feed_tags WHERE feedID = a.feedID
    ) t WHERE t.tagID IN (?, ?, ...)
)

-- state.tagMatchMode == .all:
(SELECT COUNT(DISTINCT t.tagID) FROM (
    SELECT tagID FROM article_tags WHERE articleID = a.id
    UNION
    SELECT tagID FROM feed_tags WHERE feedID = a.feedID
) t WHERE t.tagID IN (?, ?, ...)) = <Anzahl ausgewählter tagIDs>
```

Wenn `state.tagIDs.isEmpty`, wird — wie bisher bei `tagID == nil` — gar keine
Tag-Klausel angehängt (kein Filter aktiv). Die Platzhalter-Anzahl in
`IN (?, ?, ...)` ist dynamisch (`tagIDs.count` Platzhalter), die Argumente
werden wie die übrigen Filter über `StatementArguments` angehängt.

## UI-Schicht (`ArticleSearchWindowView.swift`)

Der bestehende `searchTagPicker`-Computed-Property wird ersetzt durch einen
`Button`, der ein `.popover` öffnet:

- **Button-Label:** „Tags" wenn `tagIDs.isEmpty`, sonst „Tags (\(tagIDs.count))"
  — neuer formatierter L10n-Key analog zum bestehenden Muster
  `L10n.articleSearchMatchCount(_:)`.
- **Popover-Inhalt:**
  - Oben ein `Picker(selection: $searchState.tagMatchMode)` mit
    `.pickerStyle(.segmented)`, zwei Optionen ("Mind. einer" / "Alle").
  - Darunter pro verfügbarem Tag eine Zeile
    `Toggle(tag.name, isOn: <Binding für Mitgliedschaft in tagIDs>)
    .toggleStyle(.checkbox)`.
  - Falls `tags.isEmpty` (keine Tags im System angelegt): Platzhaltertext statt
    leerer Liste.
- **Popover-Verhalten:** Schließt sich nicht automatisch beim Toggeln eines
  einzelnen Tags (macOS-typisches Verhalten für Mehrfachauswahl-Popover) —
  mehrere Tags nacheinander anhaken bleibt bequem möglich, ohne das Popover
  jedes Mal neu zu öffnen.

Der bisherige L10n-Key `L10n.articleSearchTagAll` ("Alle Tags") entfällt aus
diesem Kontext (kein Einzel-Dropdown mit "Alle"-Option mehr) — wird aber nicht
gelöscht, falls er anderswo noch referenziert wird (Prüfung dazu gehört in den
Implementierungsplan). Neue L10n-Keys: Button-Label-Format (Singular/Plural
über bestehendes `String(localized:)`-Pluralisierungsmuster, siehe
`articleSearchMatchCount`), "Mind. einer", "Alle" (Modus-Bezeichnungen),
Platzhaltertext für "keine Tags vorhanden".

## Fehlerbehandlung

Keine neuen Fehlerfälle — die Tag-IDs werden client-seitig aus der bereits
geladenen `tags: [TagRecord]`-Liste erzeugt (kein zusätzlicher DB-Zugriff beim
Toggeln), und die SQL-Query kann mit einer leeren `tagIDs`-Menge trivial
umgehen (kein Filter). Ein potenziell gelöschter Tag, der noch in
`searchState.tagIDs` steht, während das Popover geschlossen ist, führt zu
einer harmlosen No-Match-Zeile in der `IN (...)`-Klausel — kein Absturz, kein
Sonderfall nötig.

## Testabdeckung

Neue Unit-Tests für `ArticleStore.searchArticles(state:)` (in
`FeedivoTests/`, passendes bestehendes Test-File für `ArticleStore`):

1. `tagIDs` mit einem Tag verhält sich identisch zum bisherigen
   Einzelauswahl-Verhalten (Regressionsschutz für die Migration von `tagID` zu
   `tagIDs`).
2. `tagMatchMode: .any` mit zwei Tags liefert Artikel, die mindestens einen der
   beiden haben (inkl. Artikel, die nur einen der beiden haben).
3. `tagMatchMode: .all` mit zwei Tags liefert nur Artikel, die beide
   gleichzeitig haben (Artikel mit nur einem der beiden Tags werden
   ausgeschlossen).
4. Tag-Zuordnung über den Feed (statt direkt am Artikel) wird in beiden Modi
   weiterhin korrekt berücksichtigt (Regressionsschutz für die bestehende
   Artikel-ODER-Feed-Semantik).
5. Leere `tagIDs`-Menge liefert dasselbe Ergebnis wie ganz ohne Tag-Filter.

UI-seitig (Popover-Interaktion) wie bei anderen SwiftUI-Gesten-Features in
diesem Projekt keine automatisierte Testabdeckung — manuelle Verifikation nach
Implementierung.
