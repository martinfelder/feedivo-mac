# Design: Feeds in der Sidebar per Doppelklick umbenennen

**Datum:** 2026-07-13
**Status:** Genehmigt, bereit für Implementierungsplan

## Ausgangslage

Direkt im Anschluss an das Ordner-Umbenennen-Feature (siehe
`docs/superpowers/specs/2026-07-13-ordner-umbenennen-design.md`) soll derselbe
Inline-Doppelklick-Mechanismus auch für Feeds in der Sidebar gelten.

Feeds haben bereits einen Umbenennen-Weg: der Kontextmenü-Eintrag „Feed
umbenennen…" öffnet `FeedRenameView` (`Feedivo/Views/Sidebar/FeedRenameView.swift`),
ein separates Sheet-Fenster, das zusätzlich zum Anzeigenamen auch den
ursprünglichen Feed-Titel anzeigt und einen „Ursprung wiederherstellen"-Button
bietet. Diese Funktionalität passt nicht in ein einzeiliges Sidebar-Textfeld.

## Ziel

Doppelklick auf den Feed-Namen startet Inline-Bearbeitung, analog zu Ordnern.
Der bestehende Dialog bleibt zusätzlich über das Kontextmenü erreichbar.

## Nicht-Ziele

- Kein zusätzlicher Kontextmenü-Eintrag für die Inline-Bearbeitung (der
  bestehende „Feed umbenennen…"-Eintrag bleibt unverändert und öffnet weiterhin
  den vollen Dialog — zwei „Umbenennen"-Einträge im selben Menü wären
  redundant).
- Keine Änderung an `FeedRenameView` oder der „Ursprung wiederherstellen"-Funktion.
- Keine Namens-Kollisionsprüfung — Feeds haben, anders als Ordner, keine
  Eindeutigkeits-Regel für Anzeigenamen.

## Datenschicht

`FeedStore.renameFeed(id:displayTitle:) throws` existiert bereits
(`Feedivo/Stores/FeedStore.swift:46`) und wirft `FeedStoreError.emptyTitle` bei
leerem/nur-Whitespace-Namen — keine neue Store-Methode nötig.

`FeedStoreError` (`Feedivo/Stores/FeedStore.swift:352`) hat aktuell **keine**
`LocalizedError`-Konformität. Dadurch zeigt selbst der bestehende
`FeedRenameView`-Dialog beim Speichern eines leeren Namens aktuell eine
generische Systemfehlermeldung statt eines freundlichen deutschen Texts (kein
Aufrufer konsumiert bisher `errorDescription`, da dieser Fall bislang von
keinem Testfall oder Code abgedeckt wird — verifiziert per Grep über den
gesamten Produktions- und Test-Baum). Ergänzung:

```swift
enum FeedStoreError: Error, Equatable, LocalizedError {
    case emptyTitle
    case missingFeed
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyTitle: L10n.feedRenameEmptyName
        case .missingFeed: nil
        case .databaseUnavailable: L10n.feedRenameDatabaseUnavailable
        }
    }
}
```

`.missingFeed` bleibt ohne eigenen Text (`nil`, fällt auf die generische
Systemmeldung zurück) — über den neuen Inline-Weg nicht erreichbar (Umbenennen
wird nur auf sichtbar existierenden Zeilen angeboten) und bislang nirgends
speziell behandelt, daher bewusst unangetastet. `.databaseUnavailable` ist neu
und wird — wie beim Ordner-Pendant — ausschließlich vom UI-seitigen
`SidebarView.renameFeed(id:to:)`-Wrapper geworfen, falls die
`\.feedivoDatabase`-Environment fehlt; wiederverwendet den bereits
vorhandenen Key `L10n.feedRenameDatabaseUnavailable`.

## UI-Schicht

### Strukturänderung an `FeedRowView`

Aktuell umschließt `SidebarView.feedRows(_:)` jede Zeile in einem einzigen
`Button { selection = .feed(id) } label: { FeedRowView(...) }`, dessen
Auswahl-/Hover-Optik komplett aus `SidebarRowButtonStyle` (einem `ButtonStyle`)
kommt. Für Doppelklick-zum-Umbenennen entsteht dasselbe Kollisionsproblem wie
bei Ordnern: ein Klick ins Textfeld während der Bearbeitung würde vom
umschließenden `Button` mit abgefangen.

**Lösung:** `FeedRowView` verliert den umschließenden `Button` und übernimmt
Auswahl (Einzelklick) sowie Bearbeitungsstart (Doppelklick) selbst — exakt das
Muster aus `SidebarFolderSection`:

- Neue Parameter: `isSelected: Bool`, `select: () -> Void`,
  `renameFeed: (String) throws -> Void`.
- Neue lokale `@State`: `isEditingName: Bool`, `editedName: String`,
  `renameErrorMessage: String?`, plus `@FocusState private var
  isNameFieldFocused: Bool`.
- Der Titel-`Text` bekommt `.onTapGesture(count: 2) { beginEditing() }` und
  `.onTapGesture(count: 1) { select() }` auf derselben View (SwiftUI
  disambiguiert das korrekt).
- Im Bearbeitungsmodus ersetzt ein `TextField` mit `.textFieldStyle(.roundedBorder)`
  den `Text` (identisches Aussehen/Verhalten wie beim finalen Ordner-Design:
  Enter/Fokusverlust bestätigt, Escape bricht ab, roter Rahmen-Overlay bei
  ungültigem Namen).
- Die gesamte Zeile (`HStack`) bekommt einen Klick-Fänger für den restlichen
  Platz (Favicon, Fehler-Icon, Ungelesen-Badge, Leerraum):
  `.onTapGesture { if !isEditingName { select() } }` — verhindert, dass ein
  Klick ins Textfeld während der Bearbeitung stattdessen die Auswahl auslöst
  (identische Absicherung wie beim Ordner-Fix).
- Die Auswahl-/Rahmen-Optik von `SidebarRowButtonStyle` wird manuell
  nachgebaut (`.background { RoundedRectangle(cornerRadius: 8).fill(isSelected
  ? SidebarStyle.activeSelection : Color.clear).overlay { RoundedRectangle(cornerRadius:
  8).stroke(isSelected ? SidebarStyle.activeBorder : Color.clear, lineWidth: 1) } }`,
  plus `.padding(.horizontal, 10)`, `.frame(height:)`, `.padding(.leading:)`
  aus dem bisherigen `SidebarRowButtonStyle(isSelected:leadingIndent:rowHeight:)`-Aufruf).
  Die `.font(...)`-Zeile von `SidebarRowButtonStyle` muss dabei **nicht**
  repliziert werden — jedes sichtbare Text-Element in `FeedRowView` setzt
  bereits seinen eigenen expliziten Font (verifiziert per Code-Lesung), ein
  ererbter Font von außen würde also ohnehin nichts bewirken. Die
  `.foregroundStyle(...)`-Zeile dagegen **muss** repliziert werden: der
  Titel-`Text` setzt aktuell keinen eigenen `foregroundStyle` und erbt ihn
  bislang von `SidebarRowButtonStyle` (`isSelected ? SidebarStyle.primaryText :
  SidebarStyle.primaryText.opacity(0.82)`) — dieser fällt beim Wegfall des
  `Button`-Wrappers ersatzlos weg, wenn er nicht explizit auf den Titel-`Text`
  gesetzt wird. Der Titel-`Text` bekommt daher zusätzlich
  `.foregroundStyle(isSelected ? SidebarStyle.primaryText :
  SidebarStyle.primaryText.opacity(0.82))` direkt gesetzt (identisch zum
  bisherigen ererbten Wert, jetzt nur explizit statt implizit).
- `leadingIndent`/`rowHeight` (bisher `isIndented ? 46 : 0` / `isIndented ? 28
  : 30` am Aufrufort) wandern als weitere Fälle in die bereits vorhandene
  private `DisplayStyle`-Erweiterung (`.regular`/`.folderChild`), da
  `displayStyle` diese Unterscheidung schon kennt.

**Bewusste kosmetische Einbuße:** Die kurze „Press-Flash"-Mikroanimation beim
Klicken-und-Halten (`configuration.isPressed` aus `SidebarRowButtonStyle`)
entfällt, da sie nur innerhalb eines echten `ButtonStyle` verfügbar ist. Nur
der ausgewählt/nicht-ausgewählt-Zustand bleibt sichtbar, der transiente
Hover-Zwischenzustand nicht. Vom Nutzer akzeptiert.

`FeedRowView` ist ausschließlich in `SidebarView.swift` referenziert (beide
Feed-Listen — oberste Ebene und in Ordnern eingerückt — laufen durch dieselbe
`feedRows(_:)`-Hilfsfunktion), keine weiteren Konsumenten betroffen.

### Aufrufstelle (`SidebarView.feedRows(_:)`)

```swift
private func feedRows(_ snapshots: [FeedSidebarSnapshot], isIndented: Bool = false) -> some View {
    ForEach(snapshots) { snapshot in
        FeedRowView(
            snapshot: snapshot,
            displayStyle: isIndented ? .folderChild : .regular,
            isSelected: selection == .feed(snapshot.id),
            select: { selection = .feed(snapshot.id) },
            renameFeed: { newName in
                try renameFeed(id: snapshot.id, to: newName)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            // unverändert: „Feed umbenennen…" (öffnet weiterhin FeedRenameView),
            // „Feed-Eigenschaften", „Löschen"
        }
    }
}
```

Neue private Methode in `SidebarView` (analog zu `renameFolder(from:to:)`):

```swift
private func renameFeed(id: String, to newTitle: String) throws {
    guard let database = feedivoDatabase else {
        throw FeedStoreError.databaseUnavailable
    }

    try FeedStore(database: database).renameFeed(id: id, displayTitle: newTitle)
    SQLiteDataInvalidation.bumpStatusVersion()
}
```

Kein Pendant zu `collapsedFolderNames`/`sidebarDefinitionVersion` nötig — Feeds
haben keinen Ein-/Ausklapp-Zustand und keine namensbasierte
Gruppierungs-Logik, die beim Umbenennen migriert werden müsste.

## Fehlerbehandlung — Zusammenfassung

| Fall | Verhalten |
|---|---|
| Leerer Name bei Enter/Fokusverlust | Im Bearbeitungsmodus bleiben, roter Rahmen + „Der Name darf nicht leer sein." |
| Escape | Sofortiger Abbruch, alter Name wiederhergestellt, kein Fehlertext |
| Unveränderter Name | Stiller No-op, Bearbeitungsmodus wird beendet |
| DB nicht verfügbar | Im Bearbeitungsmodus bleiben, Fehlertext aus vorhandenem generischem Key |

## Testabdeckung

Ergänzung in `FeedivoTests/SQLiteAdminStoreTests.swift` (dort liegt die
bestehende `renameFeed`/`restoreOriginalTitle`-Abdeckung bereits, siehe
`feedStoreMutiertFeedVerwaltungSQLiteFirst`):

1. `renameFeed` lehnt einen leeren/nur-Whitespace-Namen mit
   `FeedStoreError.emptyTitle` ab (bisher ungetestet).
2. `FeedStoreError.emptyTitle.errorDescription` liefert
   `L10n.feedRenameEmptyName` (neuer Test, verifiziert den `LocalizedError`-Fix).

UI-seitig (SwiftUI-Gesten/Fokus-Verhalten) wie beim Ordner-Feature keine
automatisierte Testabdeckung — manuelle Verifikation nach Implementierung.
