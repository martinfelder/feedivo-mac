# Design: Feeds per Drag & Drop organisieren (Feature 15.2)

**Datum:** 2026-07-14
**Status:** Genehmigt, bereit für Implementierungsplan

## Ausgangslage

Feeds lassen sich Ordnern aktuell nur über ein Freitextfeld in den Feed-
Eigenschaften (`FeedPropertiesView.editableFolderRow`) zuweisen. Sowohl Feeds
innerhalb eines Ordners/„Ohne Ordner" (`FeedFolderOrganizer.sortedSnapshots`)
als auch die Ordner selbst (`FeedFolderOrganizer.folderNames`) werden dabei
**immer** alphabetisch sortiert — es gibt aktuell kein persistiertes
Sortier-Feld, weder auf `FeedRecord` noch auf `FeedFolderRecord`.

Architektonische Besonderheit, die dieses Design berücksichtigen muss (siehe
auch `docs/superpowers/specs/2026-07-13-ordner-umbenennen-design.md`): Ein
Ordner kann rein **implizit** existieren, ausschließlich über
`FeedRecord.folderName`-Strings, ganz ohne zugehörigen `FeedFolderRecord`
(z. B. nach einem OPML-Import). `FeedFolderOrganizer.folderNames(...)` führt
beide Quellen bereits case-insensitiv zu einer einheitlichen Anzeigeliste
zusammen.

Feature 15.2 war laut `FEATURES.md` mit „Hoher Aufwand — nach v1" zurückgestellt.

## Ziel

- Einen Feed per Drag & Drop auf einen Ordner-Header (oder auf den „Ohne
  Ordner"-Bereich) ziehen, um ihn zuzuweisen bzw. die Zuweisung zu entfernen.
- Feeds innerhalb eines Ordners bzw. innerhalb von „Ohne Ordner" per Drag &
  Drop frei anordnen (statt alphabetisch).
- Die benannten Ordner selbst per Drag & Drop untereinander frei anordnen
  (statt alphabetisch).

## Nicht-Ziele

- **„Ohne Ordner" bleibt fest oben angeheftet** (wie heute) und ist selbst
  nicht Teil der umsortierbaren Ordner-Liste — nur die benannten Ordner
  darunter sind untereinander sortierbar.
- Keine Mehrfachauswahl-Drags — es gibt aktuell keine Mehrfachauswahl für
  Feeds in der Sidebar.
- Kein präziser Einfüge-Strich als visuelles Feedback — nur eine dezente
  Hervorhebung der Zielzeile beim Hovern während des Drags.
- Keine Änderung an Tags oder Intelligenten Ordnern — beide bleiben wie
  bisher alphabetisch bzw. nach ihrer eigenen bestehenden Logik sortiert.
- Kein Fix für den separat bekannten, unabhängigen Altbug, dass Löschen eines
  Ordners verwaiste `folderName`-Referenzen auf Feeds hinterlässt.

## Datenschicht

### Migration v15

Neue Migration `v15_add_feed_and_folder_sort_index` in
`FeedivoDatabaseMigrator.swift` (letzte bestehende Migration ist v14 — vor dem
Schreiben des Implementierungsplans nochmal per `grep -n registerMigration`
verifizieren, siehe bekannter Gotcha in `CLAUDE.md`):

```swift
migrator.registerMigration("v15_add_feed_and_folder_sort_index") { database in
    try database.alter(table: "feeds") { table in
        table.add(column: "sortIndex", .integer).notNull().defaults(to: 0)
    }
    try database.alter(table: "feed_folders") { table in
        table.add(column: "sortIndex", .integer).notNull().defaults(to: 0)
    }

    try backfillFeedAndFolderSortIndex(database)
}
```

**Wichtig:** Diese Migration macht mehr als reines Schema — sie materialisiert
im selben Zug auch alle bisher rein impliziten Ordner in echte
`feed_folders`-Datensätze und vergibt dabei allen Ordnern (alt + neu
materialisiert) sowie allen Feeds `sortIndex`-Werte, die exakt der **heutigen**
alphabetischen Anzeige entsprechen. Ergebnis: Bestandsnutzer sehen nach dem
Update **keine** sichtbare Änderung der Reihenfolge — erst ein manueller Drag
ändert etwas. Das löst die Dual-Source-of-Truth-Altlast (Ordner ohne
Datensatz) dauerhaft und vollständig auf, nicht nur für neu angelegte Ordner.

`backfillFeedAndFolderSortIndex(_:)` (privater Helfer im selben File):

1. Baut dieselbe vereinheitlichte, case-insensitiv deduplizierte,
   alphabetisch sortierte Ordnernamen-Liste wie
   `FeedFolderOrganizer.folderNames(feedFolderNames:explicitFolderNames:)`
   (Logik 1:1 übernommen, nicht neu erfunden — Eingabe: alle
   `feeds.folderName`-Werte + alle `feed_folders.name`-Werte).
2. Für jeden Namen an Position `i` in dieser Liste:
   - Existiert bereits ein `feed_folders`-Datensatz mit diesem Namen
     (case-insensitiv): `UPDATE feed_folders SET sortIndex = i WHERE name = ?
     COLLATE NOCASE`.
   - Sonst: neuer `FeedFolderRecord(name: kanonischerName, sortIndex: i)` wird
     eingefügt — genau das materialisiert den bisher impliziten Ordner.
3. Für Feeds: gruppiert nach normalisiertem `folderName` (getrimmt, leer/`nil`
   → eigene „Ohne Ordner"-Gruppe, case-insensitiv der kanonischen Ordner-
   Schreibweise aus Schritt 1 zugeordnet), pro Gruppe sortiert nach `title
   COLLATE NOCASE` (identisch zu `FeedFolderOrganizer.sortedSnapshots`s
   heutiger Logik) und mit `sortIndex = 0…n-1` innerhalb der Gruppe versehen
   (`UPDATE feeds SET sortIndex = ? WHERE id = ?`).

### `FeedFolderStore.swift` — neue Methoden

```swift
/// Materialisiert alle Ordnernamen, die nur auf feeds.folderName existieren
/// aber (noch) keinen feed_folders-Datensatz haben, als echte Datensätze ans
/// Ende der aktuellen Ordner-Reihenfolge. Idempotent — bereits materialisierte
/// Ordner werden übersprungen. Laufender Sicherheitsnetz-Mechanismus für neu
/// entstehende implizite Ordner NACH der v15-Migration (z. B. künftiger
/// OPML-Import), nicht für den einmaligen Backfill selbst (der läuft direkt
/// in der Migration, siehe oben).
func materializeImplicitFolders() throws

/// Verschiebt den benannten Ordner an targetIndex innerhalb der Liste der
/// benannten Ordner (0-basiert, wird auf 0...anzahlAndererOrdner geklemmt).
/// Materialisiert den Ordner zuerst, falls er noch keinen Datensatz hat.
/// Nummeriert anschließend ALLE benannten Ordner 0...n-1 neu durch.
func moveFolder(name: String, targetIndex: Int) throws
```

`moveFolder` läuft vollständig innerhalb einer `database.write`-Transaktion:
ruft zuerst `materializeImplicitFolders()`-Logik inline mit auf (kein
verschachtelter `database.write`, GRDB erlaubt keine verschachtelten
Schreibtransaktionen), holt alle anderen Ordner sortiert nach `sortIndex`,
fügt den bewegten Ordnernamen an `targetIndex` ein und schreibt `sortIndex =
0...n-1` für die gesamte resultierende Liste.

### `FeedStore.swift` — neue Methode

```swift
/// Weist den Feed ggf. einem neuen Ordner zu (nil = "Ohne Ordner") und
/// positioniert ihn an targetIndex innerhalb der Ziel-Gruppe (0-basiert, wird
/// auf 0...anzahlAndererFeedsInDerGruppe geklemmt). Nummeriert anschließend
/// NUR die Ziel-Gruppe 0...n-1 neu durch — die Quell-Gruppe (falls der Feed
/// den Ordner wechselt) behält ihre bestehenden sortIndex-Werte samt Lücke;
/// das ist harmlos, da nur die relative Reihenfolge zählt, nicht die
/// absoluten Werte.
func moveFeed(id: String, toFolderName: String?, targetIndex: Int) throws
```

Ablauf innerhalb einer `database.write`-Transaktion:
1. `toFolderName` normalisieren (trimmen, leer → `nil`).
2. Alle anderen Feeds der Ziel-Gruppe (`folderName = normalisierterName`
   case-insensitiv, bzw. `folderName IS NULL`, ohne den bewegten Feed) sortiert
   nach `sortIndex` laden.
3. Bewegten Feed an `targetIndex` in diese ID-Liste einfügen.
4. Für jede Position `i`/ID in der resultierenden Liste: `UPDATE feeds SET
   sortIndex = ?, updatedAt = ? WHERE id = ?` — beim bewegten Feed zusätzlich
   `folderName = normalisierterName`.

### `FeedSidebarSnapshot` + `FeedStore.sidebarFeeds()`

`FeedSidebarSnapshot` (`Feedivo/Snapshots/FeedSidebarSnapshot.swift`) bekommt
ein neues Feld `var sortIndex: Int`. `sidebarFeeds()`s SQL-`SELECT` liefert
zusätzlich `f.sortIndex`; der abschließende `.sorted { … }`-Aufruf (aktuell
alphabetisch nach Titel) wird auf `sortIndex` umgestellt — Gleichstand
(sollte nach der Migration nicht vorkommen, ist aber ein sinnvoller
Fallback) bricht weiterhin nach Titel.

### `FeedFolderOrganizer.swift`

- `sortedSnapshots(_:)` sortiert künftig nach `sortIndex` statt nach `title`.
- `folderNames(feedFolderNames:explicitFolderNames:)` bekommt eine neue
  Überladung, die zusätzlich `explicitFolders: [FeedFolderRecord]` statt nur
  `[String]` entgegennimmt und nach deren `sortIndex` sortiert, statt
  alphabetisch. Die bestehende, rein namensbasierte Überladung bleibt für den
  Migrations-Backfill-Code (der noch keine `sortIndex`-Werte kennt) erhalten.
- `feedsByFolderName(in:folders:)` nutzt die neue `sortIndex`-basierte
  Überladung.

### `SQLiteSidebarState.swift`

Ruft `FeedFolderStore(database:).materializeImplicitFolders()` als
allerersten Schritt in ihrer bestehenden `load(...)`-Methode auf, **bevor**
Feeds und Ordner geladen werden — damit neu entstandene implizite Ordner
(z. B. aus einem frischen OPML-Import) sofort mit korrekter Position
erscheinen, statt erst beim übernächsten Laden.

## UI-Schicht

### Neue Datei: `Feedivo/Views/Sidebar/SidebarDragAndDrop.swift`

`SidebarView.swift` ist mit >1300 Zeilen bereits die größte View-Datei des
Projekts — die neuen Drag-&-Drop-Bausteine kommen deshalb in eine eigene,
fokussierte Datei statt sie dort weiter anwachsen zu lassen:

```swift
import SwiftUI
import UniformTypeIdentifiers

/// Transferable-Payload für einen gezogenen Feed (Feed-ID).
struct FeedDragItem: Codable, Transferable {
    let feedID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .feedivoFeedDragItem)
    }
}

/// Transferable-Payload für einen gezogenen Ordner (Ordnername).
struct FolderDragItem: Codable, Transferable {
    let folderName: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .feedivoFolderDragItem)
    }
}

extension UTType {
    static let feedivoFeedDragItem = UTType(exportedAs: "ch.martin.Feedivo.feed-drag-item")
    static let feedivoFolderDragItem = UTType(exportedAs: "ch.martin.Feedivo.folder-drag-item")
}

/// Bestimmt anhand der Y-Position eines Drops innerhalb der Höhe einer
/// Zielzeile, ob "davor" oder "danach" eingefügt werden soll — gemeinsame
/// Logik für Feed- und Ordner-Reordering.
enum DropInsertionSide {
    case before
    case after

    static func of(location: CGPoint, in size: CGSize) -> DropInsertionSide {
        location.y < size.height / 2 ? .before : .after
    }
}
```

Zwei neue `UTType`-Exports sind nötig (analog zu bestehenden
`UTType`-Extensions im Projekt, z. B. für OPML/Artikel-Export-Dokumenttypen)
und müssen zusätzlich in `Info.plist` unter `UTExportedTypeDeclarations`
eingetragen werden (siehe bestehende Einträge dort als Vorlage — sonst
funktioniert `Transferable` mit einem projekteigenen `UTType` auf macOS nicht
zuverlässig über App-Grenzen hinweg; hier aber ohnehin nur App-intern
genutzt, das Deklarieren ist trotzdem der von Apple dokumentierte Weg).

### `SidebarView.swift` — Änderungen an bestehenden Views

**Zwei Verantwortungsebenen**, um Signatur-Drift zwischen Drop-Handler und
Store-Aufruf zu vermeiden:

1. Jeder `.dropDestination`-Closure kennt bereits die aktuell angezeigte,
   geordnete Liste seiner Sektion (`entry.snapshots` in `foldersSection`,
   bzw. die Liste der Ordnernamen in der Ordner-`ForEach`) — er rechnet die
   Geste ("relativ zu Zeile X, Seite `.before`/`.after`") **selbst** in einen
   konkreten `targetIndex: Int` um (`firstIndex(where:)` auf dieser Liste,
   `+1` bei `.after`), bevor er die private Methode aufruft.
2. Die privaten `SidebarView`-Methoden nehmen ausschließlich fertige,
   konkrete Indizes entgegen — dieselbe Signatur wie die darunterliegenden
   Store-Methoden:

```swift
private func moveFeed(id: String, toFolderName: String?, targetIndex: Int) {
    guard let database = feedivoDatabase else { return }
    try? FeedStore(database: database).moveFeed(id: id, toFolderName: toFolderName, targetIndex: targetIndex)
    SQLiteDataInvalidation.bumpStatusVersion()
}

private func moveFolder(name: String, targetIndex: Int) {
    guard let database = feedivoDatabase else { return }
    try? FeedFolderStore(database: database).moveFolder(name: name, targetIndex: targetIndex)
    sidebarDefinitionVersion += 1
}
```

**Feed-Zeilen** (`feedRows(_:isIndented:)`): jede `FeedRowView`-Instanz
bekommt `.draggable(FeedDragItem(feedID: snapshot.id))` sowie
`.dropDestination(for: FeedDragItem.self) { items, location in ... }` —
verwirft Selbst-Drops (`dragged.feedID == snapshot.id`), bestimmt sonst per
`DropInsertionSide.of(location:in:)` die Seite und ruft `moveFeed(id:
toFolderName: <Ordner dieser Ziel-Sektion>, targetIndex: <berechnet>)` auf.
Die Zeilenhöhe für `DropInsertionSide.of` wird über einen lokalen `@State`-
Frame-Cache pro Zeile ermittelt (`.onGeometryChange(for: CGSize.self) { … }`)
— Detail für den Implementierungsplan.

**Ordner-Header** (`SidebarFolderSection`): bekommt zusätzlich
`.draggable(FolderDragItem(folderName: title))`,
`.dropDestination(for: FeedDragItem.self) { items, _ in ... }` (Drop direkt
auf den Header, nicht auf eine bestimmte Feed-Zeile darin → `targetIndex` =
Anzahl der Feeds in diesem Ordner, also ans Ende angehängt) sowie
`.dropDestination(for: FolderDragItem.self) { items, location in ... }`
(Ordner-Reordering, dieselbe `DropInsertionSide`-Logik wie bei Feeds, relativ
zur aktuell angezeigten Ordnerliste).

**„Ohne Ordner"-Bereich**: bekommt ebenfalls einen
`.dropDestination(for: FeedDragItem.self)` (Zuweisung entfernen = `toFolderName:
nil`, ans Ende der „Ohne Ordner"-Gruppe), aber **keinen**
`.dropDestination(for: FolderDragItem.self)` — Ordner können nicht auf „Ohne
Ordner" fallengelassen werden, da „Ohne Ordner" kein Ziel für Ordner-
Reordering ist (siehe Nicht-Ziele).

Fehler aus diesen Store-Aufrufen werden — konsistent mit dem Rest der
Drag-&-Drop-Interaktion (kein Dialog, der den Ziehvorgang unterbricht) — nicht
dem Nutzer angezeigt, sondern still ignoriert (`try?`), analog zu
`duplicateSmartFolder`/`deleteSmartFolder` in derselben Datei. Ein
fehlschlagender Move (z. B. DB kurzzeitig nicht verfügbar) führt im
schlimmsten Fall dazu, dass der Drop optisch nichts bewirkt — kein
Datenverlust, da die Operation rein additiv/umsortierend ist.

**Visuelles Feedback:** `dropDestination(for:isTargeted:action:)` (die
Variante mit zusätzlichem `isTargeted`-Closure) hebt die jeweilige Zielzeile
während des Hoverns dezent hervor (z. B. `SidebarStyle.rowHover`-Hintergrund,
bereits im Projekt vorhanden für den gedrückten Button-Zustand).

## Fehlerbehandlung — Zusammenfassung

| Fall | Verhalten |
|---|---|
| Drop auf sich selbst (Feed auf eigene Zeile, Ordner auf sich selbst) | No-op, kein DB-Zugriff |
| DB nicht verfügbar während eines Drops | Store-Aufruf schlägt still fehl (`try?`), Reihenfolge bleibt unverändert |
| Feed wird auf „Ohne Ordner" gezogen | `folderName = nil`, ans Ende der „Ohne Ordner"-Gruppe |
| Ordner wird auf „Ohne Ordner" gezogen | Kein Drop-Ziel — Geste hat keinen Effekt |
| Rein impliziter Ordner ist Ziel eines Ordner-Reorderings | Wird vor dem eigentlichen Verschieben automatisch materialisiert |

## Testabdeckung

Neue Unit-Tests gegen eine echte In-Memory-GRDB-Datenbank:

**`FeedivoTests/SQLiteDatabaseMigrationTests.swift`** (Migration v15):
1. Nach der Migration haben alle bestehenden Feeds/Ordner `sortIndex`-Werte,
   die der vorherigen alphabetischen Reihenfolge entsprechen (pro Ordner-
   Gruppe bzw. „Ohne Ordner", und für die Ordnerliste selbst).
2. Ein Feed, dessen `folderName` vor der Migration auf keinen
   `feed_folders`-Datensatz verweist, hat danach einen echten Datensatz mit
   korrekt eingereihtem `sortIndex`.

**`FeedivoTests/FeedFolderStoreTests.swift`**:
3. `materializeImplicitFolders()` legt für jeden nur-impliziten Ordnernamen
   genau einen Datensatz an, ans Ende der bestehenden Reihenfolge, und ist
   beim zweiten Aufruf ein No-op (idempotent).
4. `moveFolder(name:targetIndex:)` verschiebt einen bestehenden Ordner an
   eine neue Position, alle anderen Ordner rücken korrekt nach.
5. `moveFolder(name:targetIndex:)` auf einen rein impliziten Ordnernamen
   materialisiert ihn zuerst und positioniert ihn danach korrekt.
6. `targetIndex` außerhalb des gültigen Bereichs (negativ / zu groß) wird
   geklemmt statt einen Fehler zu werfen.

**`FeedivoTests/SQLiteFeedStoreTests.swift`** (oder passendes bestehendes
Test-File):
7. `moveFeed(id:toFolderName:targetIndex:)` innerhalb derselben Gruppe
   ordnet die Gruppe korrekt neu.
8. `moveFeed(id:toFolderName:targetIndex:)` in eine andere Gruppe (inkl.
   `nil` = „Ohne Ordner") setzt `folderName` korrekt und reiht in die
   Ziel-Gruppe ein, ohne die Quell-Gruppe zu berühren.
9. `sidebarFeeds()` liefert Feeds sortiert nach `sortIndex`, nicht mehr nach
   Titel (Regressionstest gegen versehentliches Zurückfallen auf die alte
   Sortierung).

UI-seitige Drag-Gesten selbst sind wie bei vergleichbaren, bereits
umgesetzten Sidebar-Interaktionen in diesem Projekt nicht automatisiert
testbar — manuelle Verifikation nach Implementierung (kein computer-use für
native macOS-Apps in dieser Umgebung verfügbar).
