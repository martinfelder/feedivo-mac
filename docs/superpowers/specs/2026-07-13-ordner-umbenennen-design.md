# Design: Ordner in der Sidebar umbenennen

**Datum:** 2026-07-13
**Status:** Genehmigt, bereit für Implementierungsplan

## Ausgangslage

Ordner in der linken Sidebar (`SidebarFolderSection` in
`Feedivo/Views/Sidebar/SidebarView.swift:686`) lassen sich aktuell nur erstellen
(`AddFeedSheet`) und löschen (nur wenn leer, über das Kontextmenü). Es gibt keine
Möglichkeit, einen bestehenden Ordner umzubenennen.

Architektonische Besonderheit, die das Design berücksichtigen muss: Ordner sind in
Feedivo rein namensbasiert (kein eigenes Fremdschlüssel-Konzept, das Feeds
referenzieren). Ein Ordner kann existieren als:
- expliziter `FeedFolderRecord`-Datensatz (Tabelle `feed_folders`, z. B. für leere,
  bewusst angelegte Ordner), und/oder
- implizit, ausschließlich über `FeedRecord.folderName`-Strings (Tabelle `feeds`,
  Spalte `folderName`) der zugehörigen Feeds.

`FeedFolderOrganizer.folderNames(...)` führt beide Quellen bereits case-insensitiv
zu einer einheitlichen, angezeigten Ordnerliste zusammen. Ein Umbenennen muss daher
zwingend beide Speicherorte konsistent aktualisieren.

## Ziel

Ordner sollen sich per Doppelklick auf den Namen inline umbenennen lassen (analog zu
macOS-Finder-Umbenennung), zusätzlich über einen neuen Kontextmenü-Eintrag
"Ordner umbenennen".

## Nicht-Ziele

- Kein automatisches Zusammenführen (Merge) von Feeds, wenn ein Ordner in einen
  bereits existierenden Namen umbenannt wird — das wird stattdessen mit einer
  Fehlermeldung abgelehnt.
- Kein Fix für den separat bekannten, unabhängigen Altbug, dass das Löschen eines
  Ordners verwaiste `folderName`-Referenzen auf Feeds hinterlässt.
- Keine Änderung an der bestehenden "Ordner löschen"-Logik.

## Datenschicht

Neue Methode auf `FeedFolderStore` (`Feedivo/Stores/FeedFolderStore.swift`):

```swift
func renameFolder(from oldName: String, to newName: String) throws
```

Ablauf, vollständig innerhalb einer einzigen `database.write`-Transaktion:

1. `newName` trimmen (`.whitespacesAndNewlines`). Ist das Ergebnis leer, wird
   `FeedFolderRenameError.emptyName` geworfen — kein DB-Zugriff nötig.
2. Case-insensitiver Kollisions-Check per SQL (`COLLATE NOCASE`) über **beide**
   Tabellen (`feed_folders.name` und `feeds.folderName`), unter Ausschluss des
   umzubenennenden Ordners selbst (`oldName`, case-insensitiv verglichen). Trifft
   der neue Name auf einen *anderen* bestehenden Ordner, wird
   `FeedFolderRenameError.duplicateName` geworfen. Eine reine
   Großschreibungskorrektur des eigenen Namens (z. B. "tech" → "Tech") zählt dabei
   nicht als Kollision und ist erlaubt.
3. Bei bestandener Prüfung: `UPDATE feeds SET folderName = ? WHERE folderName = ?
   COLLATE NOCASE` (alle Feeds mit dem alten Namen), danach
   `UPDATE feed_folders SET name = ?, updatedAt = ? WHERE name = ? COLLATE NOCASE`
   (nur falls ein expliziter Datensatz existiert — Update auf 0 Zeilen ist dabei
   kein Fehler, deckt rein implizite Ordner ab).

Neuer, kleiner Fehlertyp im selben File:

```swift
enum FeedFolderRenameError: LocalizedError {
    case emptyName
    case duplicateName
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyName: L10n.feedRenameEmptyName
        case .duplicateName: L10n.sidebarAddFolderDuplicateError
        case .databaseUnavailable: L10n.feedRenameDatabaseUnavailable
        }
    }
}
```

Alle drei referenzierten `L10n`-Keys existieren bereits und sind bewusst generisch
genug formuliert, um hier wiederverwendet zu werden ("Der Name darf nicht leer
sein." / "Dieser Ordner existiert bereits." / "SQLite-Datenbank ist nicht
verfügbar.") — keine neuen Fehlertext-Keys nötig. `.databaseUnavailable` wird nicht
von `FeedFolderStore.renameFolder` selbst geworfen (der Store bekommt die
Datenbank injiziert und kann sie nicht "verlieren"), sondern ausschließlich vom
UI-seitigen `SidebarView.renameFolder(from:to:)`-Wrapper, falls die
`\.feedivoDatabase`-Environment nil ist — siehe unten.

## UI-Schicht (`SidebarFolderSection`, `SidebarView.swift`)

**Struktur-Änderung:** Aktuell ist die gesamte Kopfzeile (Chevron + Ordner-Icon +
Name) ein einziger `Button`, der beim Klick ein-/ausklappt. Das wird aufgeteilt:

- Chevron + Ordner-Icon bleiben in einem eigenen `Button(action: toggle)`.
- Der Name (`Text`, bzw. im Bearbeitungsmodus `TextField`) ist eine separate
  Sibling-View mit zwei Tap-Gesten auf derselben View:
  - `.onTapGesture(count: 1) { toggle() }` — bewahrt das bisherige Verhalten,
    dass ein Klick auf den Namen den Ordner ein-/ausklappt.
  - `.onTapGesture(count: 2) { beginEditing() }` — startet die Inline-Bearbeitung.

  SwiftUI löst count-1- und count-2-Gesten auf derselben View korrekt auf (der
  Einzelklick wartet kurz, ob ein zweiter folgt).

**Bearbeitungsmodus:**

- Neue lokale `@State`-Properties in `SidebarFolderSection`: `isEditingName: Bool`,
  `editedName: String`, `renameErrorMessage: String?`, plus
  `@FocusState private var isNameFieldFocused: Bool`.
- `beginEditing()`: `editedName = title`, `isEditingName = true`,
  `isNameFieldFocused = true`.
- Im Bearbeitungsmodus ersetzt ein fokussiertes `TextField(text: $editedName)` den
  `Text`, mit `.onSubmit { commitOrShowError() }` und `.onExitCommand {
  cancelEditing() }` (Escape).
- `.onChange(of: isNameFieldFocused)`: wechselt der Fokus von `true` auf `false`
  **während** `isEditingName == true`, wird ebenfalls `commitOrShowError()`
  aufgerufen (Fokusverlust verhält sich wie Enter). Da `cancelEditing()` und ein
  erfolgreiches `commitOrShowError()` `isEditingName` bereits vor der
  Fokus-Änderung auf `false` setzen, verhindert die Guard-Bedingung
  (`isEditingName == true`) ein doppeltes Auslösen.
- `commitOrShowError()`: trimmt `editedName`. Ist der getrimmte Name identisch zum
  aktuellen Titel (inkl. Groß-/Kleinschreibung), wird der Bearbeitungsmodus ohne
  Store-Aufruf beendet (No-op). Andernfalls `try renameFolder(trimmed)` (siehe
  unten) — bei Erfolg `isEditingName = false`, `renameErrorMessage = nil`; bei
  Fehlschlag bleibt `isEditingName == true`, `renameErrorMessage` wird gesetzt
  (roter Rahmen ums `TextField` + Fehlertext in kleiner Schrift darunter, wie beim
  bestehenden `FeedRenameView`-Muster). Das gilt auch, wenn der Fokus zwischenzeitlich
  bereits verloren ging (bewusster Randfall, siehe unten).
- `cancelEditing()`: `editedName = title`, `isEditingName = false`,
  `renameErrorMessage = nil`.

**Neuer Parameter** an `SidebarFolderSection`:

```swift
let renameFolder: (String) throws -> Void
```

Aufruf aus `SidebarView` pro Ordner-Zeile:

```swift
SidebarFolderSection(
    title: entry.folderName,
    isExpanded: isExpanded,
    deleteEmptyFolder: ...,
    renameFolder: { newName in
        try renameFolder(from: entry.folderName, to: newName)
    }
) {
    toggleFolder(named: entry.folderName)
} content: {
    ...
}
```

Neue private Methode in `SidebarView` (analog zu `deleteFeedFolder`):

```swift
private func renameFolder(from oldName: String, to newName: String) throws {
    guard let database = feedivoDatabase else {
        throw FeedFolderRenameError.databaseUnavailable
    }
    try FeedFolderStore(database: database).renameFolder(from: oldName, to: newName)
    SQLiteDataInvalidation.bumpStatusVersion()
}
```

**Kontextmenü-Erweiterung:** Neuer Eintrag oberhalb des bestehenden
"Löschen"-Eintrags im `contextMenu` (Zeile ~722):

```swift
Button {
    beginEditing()
} label: {
    Label(L10n.sidebarFolderRenameCommand, systemImage: "pencil")
}
```

Neuer L10n-Key `sidebar.folder.rename.command` = "Ordner umbenennen" / "Rename
Folder" (ohne Auslassungspunkte, da keine weitere Dialogeingabe folgt — anders als
z. B. "Feed umbenennen…", das einen Dialog öffnet).

## Fehlerbehandlung — Zusammenfassung

| Fall | Verhalten |
|---|---|
| Leerer Name bei Enter/Fokusverlust | Im Bearbeitungsmodus bleiben, roter Rahmen + "Der Name darf nicht leer sein." |
| Namenskollision mit anderem Ordner | Im Bearbeitungsmodus bleiben, roter Rahmen + "Dieser Ordner existiert bereits." |
| Escape | Sofortiger Abbruch, alter Name wiederhergestellt, kein Fehlertext |
| Unveränderter Name (auch bei nur Whitespace-Trim) | Stiller No-op, Bearbeitungsmodus wird beendet |
| Reine Großschreibungsänderung des eigenen Namens | Erlaubt, wird gespeichert |
| DB nicht verfügbar | Im Bearbeitungsmodus bleiben, Fehlertext aus vorhandenem generischem Key |

## Testabdeckung

Neue Unit-Tests für `FeedFolderStore.renameFolder(from:to:)` (in
`FeedivoTests/`, passendes bestehendes Test-File oder neues
`FeedFolderStoreTests.swift`):

1. Erfolgreiche Umbenennung eines expliziten Ordners (`FeedFolderRecord`
   vorhanden) — Name in DB aktualisiert.
2. Erfolgreiche Umbenennung eines rein impliziten Ordners (nur über
   `FeedRecord.folderName`, kein `FeedFolderRecord`) — alle betroffenen Feeds
   aktualisiert.
3. Mehrere Feeds im selben Ordner werden alle konsistent umbenannt.
4. Ablehnung bei leerem/nur-Whitespace-Namen (`FeedFolderRenameError.emptyName`).
5. Ablehnung bei Namenskollision mit einem *anderen* Ordner, case-insensitiv
   geprüft (`FeedFolderRenameError.duplicateName`).
6. Erlaubte reine Großschreibungskorrektur des *eigenen* Namens (z. B. "tech" →
   "Tech") — keine Kollision mit sich selbst.

UI-seitig (SwiftUI-Gesten, Fokus-Verhalten) ist wie bei vergleichbaren, bereits
umgesetzten Sidebar-Interaktionen in diesem Projekt keine automatisierte
Testabdeckung vorgesehen — manuelle Verifikation nach Implementierung (kein
computer-use für native macOS-Apps in dieser Umgebung verfügbar).
