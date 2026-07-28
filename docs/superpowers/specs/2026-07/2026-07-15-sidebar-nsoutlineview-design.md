# Design-Spec: Sidebar-Migration auf AppKit NSOutlineView

**Datum:** 2026-07-15
**Status:** Design genehmigt, Implementierung noch NICHT begonnen

## Kontext

Feature 15.2 ("Feeds per Drag & Drop organisieren") wurde mit SwiftUIs nativer
`.draggable`/`.dropDestination`-API (Transferable + NSItemProvider + macOS-Pasteboard)
umgesetzt. In einer sehr langen Debugging-Session (2026-07-14/15) hat sich per
Live-Log-Stream-Diagnose zweifelsfrei gezeigt, dass dieser Mechanismus auf diesem System
intermittierend komplett wirkungslos bleibt — mal feuert `.dropDestination` gar nicht, mal
hängt die zugrundeliegende Datei-Promise-/Pasteboard-Verhandlung fest. Fünf grundlegend
unterschiedliche Fixversuche haben das NICHT zuverlässig behoben:

1. Info.plist-`UTExportedTypeDeclarations`-Fix (echter, aber nicht hinreichender Bugfix)
2. `.contentShape(Rectangle())` vor `.dropDestination`
3. `isTargeted`-Callback-Überladung zur Diagnose
4. Ein konsolidierter, Preference-basierter Zonen-Hit-Testing-Mechanismus (einzelner
   äußerer `dropDestination` statt verteilter)
5. Wechsel von `CodableRepresentation` (löst intern Datei-Promise-Verhandlung aus) auf
   eine datei-promise-freie `ProxyRepresentation` (reines `public.utf8-plain-text`)

Ein rein SwiftUI-eigener Ersatz per `DragGesture` + manuellem State funktionierte zwar
FUNKTIONAL zuverlässig, aber ganz ohne jegliches visuelles Feedback (kein schwebendes
Vorschaubild, keine Ziel-Markierung) — nicht ausreichend.

Recherche in NetNewsWire (`Ranchero-Software/NetNewsWire`, offene Referenz-App für
macOS-RSS-Reader) bestätigte: Die Sidebar dort ist klassisches AppKit `NSOutlineView` +
`NSPasteboardWriting` (über ein `PasteboardWriterOwner`-Protokoll, pro Domänentyp ein
eigener `*PasteboardWriter`) + `registerForDraggedTypes`/`validateDrop`/`acceptDrop`.
Damit bekommt man automatisch das schwebende Drag-Vorschaubild, die
Einfüge-Linien-Markierung und die Ziel-Hervorhebung vom Betriebssystem, statt sie selbst
nachzubauen.

**Aktuelle Sidebar-Architektur (wichtig für dieses Design):** `SidebarView.swift` ist
KEINE `List`, sondern eine reine `ScrollView` mit verschachtelten `VStack`s. Vier
Abschnitte werden nacheinander gerendert: Standard-Smart-Folders, Eigene Smart Folders,
Tags, Ordner/Feeds (`foldersSection`, enthält ordnerlose Feeds + `ForEach` über Ordner mit
verschachtelten Feed-Zeilen). Jeder Abschnitt hat seine eigene, komplett
handgeschriebene SwiftUI-Header-Komponente (`CollapsibleSidebarSection`,
`SidebarFolderSection`) mit eigenem Chevron-Button, Inline-Umbenennen,
Kontextmenü.

## Ziel

1. Zuverlässiges, sichtbares Drag & Drop (schwebendes Vorschaubild, Einfüge-Linie,
   Ziel-Hervorhebung) für alle vier Sidebar-Bereiche: Feeds, Ordner, Tags, Smart Folders.
2. Die gesamte Sidebar (Smart Folders Standard+Eigene, Tags, Ordner/Feeds) wird zu EINER
   `NSOutlineView`, gebrückt per `NSViewRepresentable`, nach dem Vorbild von NetNewsWire.
3. Bestehendes Verhalten bleibt vollständig erhalten: Inline-Umbenennen (Feed/Ordner),
   Kontextmenüs, Favicons, Ungelesen-Badges, Klick-Auswahl, Ein-/Ausklappen von
   Abschnitten/Ordnern, Tag-Manager-/Smart-Folder-Erstellen-Buttons.
4. Neu (Erweiterung ggü. dem bisherigen Funktionsumfang): Tags und Smart Folders werden
   per Drag & Drop sortierbar (Smart Folders: Datenschicht existiert bereits, nur ohne
   UI; Tags: komplett neu inkl. Datenschicht).

## Nicht-Ziele

- Kein Cross-App-Interop (Drag aus/in andere Apps, Finder, Spotlight) — reine
  In-Prozess-Nutzung, wie beim bestehenden Feed/Folder-Drag.
- Keine visuelle Neugestaltung der Zeilen — bestehende SwiftUI-Row-Views werden 1:1
  wiederverwendet (siehe Abschnitt "Zeilen-Rendering").
- Kein Umsortieren von Feeds/Ordnern quer über Grenzen hinweg, die es heute auch nicht
  gibt (z. B. Smart Folder zwischen Standard- und Eigene-Gruppe verschieben bleibt
  weiterhin unmöglich).
- Keine Änderung an der Darstellung/dem Verhalten der übrigen Sidebar-Elemente
  (Aktionszeile oben, Sheets, Alerts) — nur der scrollbare Baum-Teil wird ersetzt.

## Architektur-Überblick

Neue Dateien unter `Feedivo/Views/Sidebar/`:

- **`SidebarOutlineNode.swift`** — Baum-Modell. `SidebarOutlineNode` als `NSObject`-
  Subklasse (AppKit braucht Referenzsemantik für Item-Identität in
  `NSOutlineViewDataSource`), mit stabiler `let id: String` und einem Payload-Enum:
  ```swift
  enum Payload {
      case smartFoldersHeader(isDefault: Bool)
      case smartFolder(SQLiteSmartFolderSnapshot, isDefault: Bool)
      case tagsHeader
      case tag(TagSidebarSnapshot)
      case foldersHeader
      case folder(name: String)
      case feed(FeedSidebarSnapshot, folderName: String?)
  }
  ```
  `isEqual`/`hash` überschrieben auf Basis von `id`. Eine statische Bau-Funktion
  `SidebarOutlineNode.buildTree(from: SQLiteSidebarState) -> [SidebarOutlineNode]`
  produziert die vier Top-Level-Header-Knoten mit ihren Kindern, unter Wiederverwendung
  von `FeedFolderOrganizer` für Ordner-Gruppierung/-Sortierung (unverändert).

- **`SidebarOutlineView.swift`** — `NSViewRepresentable`, kapselt `NSScrollView` +
  `NSOutlineView`. `Coordinator` implementiert `NSOutlineViewDataSource` +
  `NSOutlineViewDelegate`. Ersetzt die aktuelle `ScrollView`/`VStack`-Sektionsstruktur
  in `SidebarView.body` (der Teil ab `defaultSmartFoldersSection` bis `foldersSection`,
  Zeilen ~64–73 in der aktuellen Datei).

- **`SidebarOutlinePasteboard.swift`** — `NSPasteboardWriting`-Typen für Feed/Ordner/
  Tag/Smart-Folder. Ersetzt `SidebarDragAndDrop.swift` vollständig (Transferable-Ansatz,
  `FeedDragItem`/`FolderDragItem`/`DropInsertionSide` werden gelöscht bzw. durch die
  AppKit-Äquivalente ersetzt).

`SidebarView.swift` bleibt bestehen für Aktionszeile, Sheets, Alerts,
Bestätigungsdialoge (`.sheet`, `.confirmationDialog`) und `.task(id:)`-Datenladen —
`body` hostet ab jetzt nur noch `SidebarOutlineView(state: sqliteSidebarState,
selection: $selection, ...)` anstelle der bisherigen vier Sektions-Aufrufe.

## Zeilen-Rendering & Interaktion

Jede Outline-Zeile — inklusive Header-Zeilen wie „Ordner", „Tags", „Smart Folders" —
wird über `NSHostingView` mit den **unveränderten** bestehenden SwiftUI-Views gerendert:
`FeedRowView`, `SidebarFolderSection`, der Header-Teil von `CollapsibleSidebarSection`,
sowie die bestehenden (aktuell inline in `SidebarView.swift` lebenden) Tag- und
Smart-Folder-Zeilen-Views. Diese Views werden dafür aus ihrem bisherigen
`ForEach`-Kontext gelöst und einzeln instanziierbar gemacht (falls nicht schon), ändern
sich inhaltlich aber nicht. Damit bleiben Inline-Umbenennen, Kontextmenüs, Favicons,
Badges pixelgenau wie heute.

Der Coordinator dequeued pro Knotentyp eine `NSTableCellView`, die einmalig einen
`NSHostingView<AnyView>` erhält (analog zum bestehenden `MenubarStatusItemController`-
Muster: konkreter View-Typ nötig, `hostingController.rootView` muss über die
Objekt-Lebensdauer denselben generischen Typ behalten) und dessen `rootView` bei jedem
`outlineView(_:viewFor:item:)`-Aufruf aktualisiert wird.

Wichtige Konsequenz: `NSOutlineView`s eigenes Auswahl-Highlighting und die native
Disclosure-Triangle werden deaktiviert (`selectionHighlightStyle = .none`,
`indentationPerLevel` auf Header-Ebene ausgeblendet bzw. Platz für die Triangle nicht
reserviert). Auswahl-Hervorhebung und Ein-/Ausklappen bleiben wie bisher rein
SwiftUI-gesteuert:

- Der bestehende Chevron-Button in `CollapsibleSidebarSection`/`SidebarFolderSection`
  ruft weiterhin dieselbe App-eigene Toggle-Logik auf (bestehende `@AppStorage`-Flags +
  `collapsedFolderNames`-Set). Der Coordinator beobachtet diese Zustände und spiegelt sie
  per `outlineView.expandItem(_:)`/`collapseItem(_:)` in die Outline-Baumstruktur.
- `outlineView(_:shouldSelectItem:)` liefert immer `false` — `NSOutlineView` verwaltet
  gar keine eigene Zeilenauswahl. Klick-Auswahl bleibt vollständig über die bestehenden
  `select()`-Closures innerhalb der SwiftUI-Row-Views gesteuert, die `selection: Binding
  <SidebarSelection?>` wie bisher direkt setzen. `NSOutlineView` wird dadurch zu einer
  reinen Baum-Layout- und Drag-Engine, nicht zu einem eigenständigen
  Auswahl-verwaltenden Steuerelement. Drag-Initiierung (`pasteboardWriterForItem`) ist
  von der Zeilenauswahl unabhängig und funktioniert unverändert per Klick-und-Ziehen auf
  die Zeile unter dem Mauszeiger.

## Drag & Drop-Mechanik

- Pro ziehbarem Knotentyp ein eigener `NSPasteboardWriting`-Typ mit dediziertem UTType:
  - `.feedivoFeedDragItem` (bestehend, weiterverwendet)
  - `.feedivoFolderDragItem` (bestehend, weiterverwendet)
  - `.feedivoTagDragItem` (**neu**)
  - `.feedivoSmartFolderDragItem` (**neu**)

  Beide neuen UTTypes brauchen — wie ihre beiden Vorgänger — einen
  `UTExportedTypeDeclarations`-Eintrag in `Feedivo/Info.plist` (bekannter Gotcha: macOS
  validiert beim tatsächlichen Drag-Betrieb dagegen, auch bei rein appinterner Nutzung
  ohne Cross-App-Interop — ohne Eintrag meldet das System zur Laufzeit einen Fehler,
  trotz `BUILD SUCCEEDED`).

- `outlineView.registerForDraggedTypes([...])` mit allen vier internen UTTypes.

- `validateDrop`/`acceptDrop` im Coordinator entscheiden je nach gezogenem Knotentyp,
  wo ein Drop erlaubt ist — dieselbe Scoping-Logik wie heute, nur zentral im Delegate
  statt über verteilte `.dropDestination`-Closures:

  | Gezogener Typ | Erlaubtes Ziel |
  |---|---|
  | Feed | Auf einen Ordner-Knoten, auf den ordnerlosen Bereich, oder Umsortieren innerhalb eines Ordners/des ordnerlosen Bereichs |
  | Ordner | Nur Umsortieren untereinander (innerhalb des Ordner-Headers) |
  | Tag | Nur Umsortieren untereinander (innerhalb des Tags-Headers) |
  | Smart Folder | Nur Umsortieren innerhalb der eigenen Gruppe (Standard bleibt von Eigene getrennt) |

- `acceptDrop` ruft die passende Store-Methode auf (siehe „Datenschicht-Änderungen"),
  danach löst es denselben Reload-Mechanismus aus wie jede andere Sidebar-Mutation
  (`SQLiteDataInvalidation.bumpStatusVersion()` bzw. der bestehende
  `sqliteSidebarReloadToken`-Trigger).

- Gewinn ggü. der bisherigen SwiftUI-Lösung: Schwebendes Drag-Vorschaubild,
  Einfüge-Linie und Ziel-Hervorhebung kommen automatisch vom Betriebssystem
  (`NSOutlineView.DropOperation` mit `.above`/`.on`), müssen nicht selbst nachgebaut
  werden.

## Datenschicht-Änderungen

- `FeedStore.moveFeed(id:toFolderName:targetIndex:)`,
  `FeedFolderStore.moveFolder(name:targetIndex:)`,
  `SQLiteSmartFolderStore.move(id:toPositionOf:)` — **alle drei unverändert
  wiederverwendet**. Der Smart-Folder-`move` existiert bereits vollständig
  (inkl. `sortOrder`-Spalte), wurde aber bisher nie an eine Drag-UI angebunden.

- **Neu:** `TagStore.move(id:targetIndex:) throws`, analog zu
  `FeedFolderStore.moveFolder` (Ziel-Index-basiert: Liste aller Tags laden, verschieben,
  `sortIndex` für alle betroffenen Tags neu schreiben).

- **Neue Migration `v16_add_tag_sort_index`** (nächster freier Slot — verifiziert per
  `grep -n registerMigration Feedivo/Database/FeedivoDatabaseMigrator.swift`, letzter
  bestehender Eintrag ist `v15_add_feed_and_folder_sort_index`):
  ```swift
  migrator.registerMigration("v16_add_tag_sort_index") { database in
      try database.alter(table: "tags") { table in
          table.add(column: "sortIndex", .integer).notNull().defaults(to: 0)
      }
      try backfillTagSortIndex(database)
  }
  ```
  `backfillTagSortIndex` vergibt `sortIndex`-Werte passend zur aktuellen alphabetischen
  Anzeige (`ORDER BY name COLLATE NOCASE, id COLLATE NOCASE`), damit Bestandsnutzer nach
  dem Update keine sichtbare Umsortierung erleben — identisches Muster zu
  `backfillFeedAndFolderSortIndex` aus v15.

- `TagRecord` bekommt ein neues `var sortIndex: Int` Feld.

- `TagStore.tags()` und `TagStore.sidebarTags()` stellen von `ORDER BY name COLLATE
  NOCASE, id COLLATE NOCASE` auf `ORDER BY sortIndex, name COLLATE NOCASE, id COLLATE
  NOCASE` um (Name bleibt Tie-Breaker für Determinismus bei gleichem `sortIndex`, analog
  zu den bestehenden Feed-/Ordner-Queries).

## Reload-/Sync-Strategie

Kein Diffing nötig (Datenmengen sind klein — Feeds/Tags/Ordner/Smart-Folders typischerweise
im niedrigen Hundert-Bereich). Bei jeder Snapshot-Aktualisierung (gleicher
`.task(id: sqliteSidebarReloadToken)`-Trigger wie heute):

1. Neuen Baum aus dem aktuellen `SQLiteSidebarState` via `SidebarOutlineNode.buildTree`
   aufbauen.
2. `outlineView.reloadData()`.
3. Anhand stabiler `id`-Werte (nicht Objektidentität, da die Knoten bei jedem Rebuild neu
   instanziiert werden) Auswahl und Expansion-Zustand wiederherstellen: bereits
   expandierte Header/Ordner (aus den bestehenden `@AppStorage`-Collapse-Flags und
   `collapsedFolderNames`) erneut per `expandItem` aufklappen; aktuelle `selection`
   bleibt unverändert (sie wird nicht von der Outline-Struktur, sondern vom SwiftUI-
   `select()`-Closure gesetzt, siehe oben).

## Verifikationsplan

`xcodebuild build` allein zählt nicht als Verifikation. Nach Implementierung: manuelles,
**mehrfach wiederholtes** Live-Testen aller folgenden Fälle:

- Feed auf einen Ordner ziehen
- Feed auf den ordnerlosen Bereich ziehen
- Feed innerhalb eines Ordners umsortieren
- Feed innerhalb des ordnerlosen Bereichs umsortieren
- Feed **zurück in seinen ursprünglichen Ordner** ziehen (der zuletzt beobachtete
  Sonderfall, der bei der alten Implementierung lautlos fehlschlug — expliziter
  Regressionstest für den ursprünglichen Bug)
- Ordner umsortieren
- Tag umsortieren
- Smart Folder umsortieren (Standard-Gruppe und Eigene-Gruppe je einzeln, sowie
  Verifikation, dass ein Drop über die Gruppengrenze hinweg abgelehnt wird)

Zusätzlich müssen folgende bestehende Interaktionen unverändert weiterlaufen:
Inline-Umbenennen (Feed per Doppelklick, Ordner per Doppelklick/Kontextmenü),
Kontextmenüs (Feed-Eigenschaften, Ordner löschen, Feed löschen), Klick-Auswahl alle vier
Bereiche, Ein-/Ausklappen aller vier Abschnitte sowie einzelner Ordner, Tag-Manager-Button,
Smart-Folder-Erstellen-Button, „+"-Menü in der Aktionszeile.

## Betroffene/neue Dateien (Zusammenfassung)

**Neu:**
- `Feedivo/Views/Sidebar/SidebarOutlineNode.swift`
- `Feedivo/Views/Sidebar/SidebarOutlineView.swift`
- `Feedivo/Views/Sidebar/SidebarOutlinePasteboard.swift`

**Geändert:**
- `Feedivo/Views/Sidebar/SidebarView.swift` (Sektions-Rendering entfernt, hostet neu
  `SidebarOutlineView`; Header-/Zeilen-Views bleiben inhaltlich unverändert, werden aber
  aus dem `ForEach`-Kontext gelöst)
- `Feedivo/Database/FeedivoDatabaseMigrator.swift` (neue Migration v16)
- `Feedivo/Database/Records/TagRecord.swift` (neues `sortIndex`-Feld)
- `Feedivo/Stores/TagStore.swift` (neue `move`-Methode, `ORDER BY`-Umstellung)
- `Feedivo/Info.plist` (zwei neue `UTExportedTypeDeclarations`-Einträge)

**Gelöscht:**
- `Feedivo/Views/Sidebar/SidebarDragAndDrop.swift` (ersetzt durch
  `SidebarOutlinePasteboard.swift`)
