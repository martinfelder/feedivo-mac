# Design-Spec: Tags direkt im Reader-Header hinzufügen

**Datum:** 2026-07-13
**Status:** Zur Nutzer-Review

## Kontext

Im Reader (`SQLiteReaderView.swift`) wird unter dem Artikeltitel bereits eine Chip-Zeile
angezeigt (`readerArticleMetadata`, Zeilen 471–486): ein Ordner-Chip (falls der Feed einem
Ordner zugeordnet ist) und ein Chip pro zugewiesenem Tag. Diese Zeile ist aktuell rein
lesend — es gibt keine Möglichkeit, direkt aus dem Reader heraus einen Tag hinzuzufügen
oder zu entfernen. Die volle Tag-Verwaltung (bestehende Tags zuweisen/entfernen per
Toggle-Pill, neuen Tag mit Name + Farbe erstellen) existiert bereits, aber nur im separaten
Metadaten-Inspector (`ArticleMetadataInspectorView.swift`, `tagSection`/`tagCreator`,
Zeilen 270–338).

## Ziel

Neben den bestehenden Chips erscheint ein "+"-Button. Ein Klick öffnet ein Popover mit
denselben Optionen wie im Metadaten-Inspector: bestehende Tags per Klick zuweisen/entfernen,
neuen Tag mit Name und Farbe erstellen und direkt zuweisen.

## Nicht-Ziele

- Keine Änderung an der Ordner-Zuweisung (nur Tags sind betroffen).
- Keine neue Tag-Verwaltungsseite (Umbenennen/Löschen von Tags bleibt in `TagManagerView`).
- Kein Entfernen des bestehenden Metadaten-Inspectors — beide Zugriffswege bleiben
  nebeneinander bestehen.

## Architektur-Überblick

Die Tag-Zuweisungs-/Erstellungslogik wird aus `ArticleMetadataInspectorView` in einen neuen,
eigenständigen View-Baustein extrahiert und an zwei Stellen eingebettet:

1. **`ArticleMetadataInspectorView`** — bestehende `tagSection` nutzt künftig den neuen
   Baustein statt ihrer bisherigen Inline-Logik (Verhalten für den Nutzer unverändert).
2. **`SQLiteReaderView`** — neuer "+"-Button am Ende der Chip-Zeile öffnet denselben
   Baustein in einem `.popover(...)`.

Dieser Ansatz vermeidet Code-Duplikation der Tag-Mutationslogik (Zuweisen/Erstellen läuft
über GRDB/`TagStore` mit mehreren Sonderfällen — Merge von Feed- und Artikel-Tags,
Duplikat-Erkennung beim Erstellen per Namensvergleich). Das Projekt hat bereits einmal
Divergenz-Probleme durch dieselbe Logik an zwei Stellen erlebt (siehe CLAUDE.md-Gotcha zu
duplizierten SQL-SELECT-Listen zwischen `ArticleDatabase.swift`/`TimelineStore.swift`) —
hier wird das von vornherein vermieden.

## Komponente 1 (neu): `ArticleTagAssignmentView`

Neue Datei: `Feedivo/Views/Reader/ArticleTagAssignmentView.swift`

```swift
struct ArticleTagAssignmentView: View {
    @Environment(\.feedivoDatabase) private var database
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let articleID: String
    let snapshotTags: [ReaderArticleTagMetadata]

    @State private var assignedTags: [TagRecord] = []
    @State private var availableTags: [TagRecord] = []
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.defaultColorHex

    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // leerer Zustand ODER FlowLayout aus tagTogglePill(assignedTags: true/false)
            tagCreator // TextField + Farb-Picker + "+"-Button
        }
        .task(id: articleID) { loadTags() }
        .onChange(of: directTagVersion) { _, _ in loadTags() }
    }

    // 1:1 verschoben aus ArticleMetadataInspectorView, articleID/currentSnapshot.id
    // wird zu articleID, currentSnapshot.tags wird zum snapshotTags-Parameter:
    // - tagTogglePill(_:isActive:)
    // - tagCreator
    // - loadTags()
    // - mergedAssignedTags(directTags:)
    // - toggleTag(_:isActive:)
    // - addTag()
    // - normalizedTagName(_:)
}
```

- **`snapshotTags`** dient als Merge-Basis (analog zum bisherigen `currentSnapshot.tags` in
  `mergedAssignedTags`), damit auch Tags, die nur über den Feed vererbt sind, in der
  zugewiesenen Liste erscheinen, auch bevor der erste `TagStore`-Query zurückkommt.
- **Selbst-Synchronisation:** Nach jeder eigenen Mutation ruft die View wie bisher
  `SidebarBadgeInvalidation.bumpDirectTagVersion()` auf. Da die View selbst auch
  `directTagVersion` per `@AppStorage`/`.onChange` beobachtet, lädt sie ihre Liste zusätzlich
  neu, wenn irgendwo anders im Programm (z. B. im jeweils anderen der beiden Aufrufer, falls
  beide gleichzeitig sichtbar sind) ein Tag geändert wurde. Das ist bewusst dieselbe
  Beobachtungs-Konvention, die `SQLiteReaderView` schon für die Chip-Zeile selbst nutzt
  (siehe Kommentar dort, Zeilen 65–71) — hier auf den neuen Baustein übertragen.
- Fehlerfall (`database == nil` bzw. GRDB-Fehler): identisch zum bisherigen Verhalten —
  stiller Fallback auf `snapshotTags`, keine Mutation möglich, kein Alert (bestehende
  Konvention in `ArticleMetadataInspectorView`, hier unverändert übernommen).

## Komponente 2: Integration in `ArticleMetadataInspectorView` (Refactor)

- `tagSection` bettet `ArticleTagAssignmentView(articleID: currentSnapshot.id, snapshotTags: currentSnapshot.tags)`
  innerhalb des bestehenden `inspectorSection(L10n.readerInspectorTags, isExpanded: $isTagSectionExpanded) { … }`
  ein.
- Entfernt werden (jetzt tot, da in den neuen Baustein verschoben): `@State`-Properties
  `assignedTags`, `availableTags`, `newTagName`, `newTagColorHex`; Methoden `loadTags()`,
  `mergedAssignedTags(directTags:)`, `toggleTag(_:isActive:)`, `addTag()`,
  `normalizedTagName(_:)`, `tagTogglePill(_:isActive:)`, `tagCreator`.
- `reloadInspectorData()` verliert ihren `loadTags()`-Aufruf sowie die
  `assignedTags`/`availableTags`-Fallback-Zuweisungen in den Fehlerpfaden — sie kümmert sich
  nur noch um `currentSnapshot` (Read/Star/Folder-Felder) und `folderNames`. Ebenso verlieren
  `.task { … }` und `.onChange(of: snapshot) { … }` am View-Body ihren zusätzlichen
  `loadTags()`-Aufruf.
- Verhalten für den Nutzer: unverändert. Reiner interner Refactor.

## Komponente 3: Integration in `SQLiteReaderView` ("+"-Button + Popover)

**Wichtige Layout-Konsequenz:** Bisher rendert `readerArticleMetadata` überhaupt nichts,
wenn weder ein Ordner noch Tags vorhanden sind (`if folderName != nil || !snapshot.tags.isEmpty`).
Damit auch für Artikel ohne bisherige Tags der erste Tag über den Header angelegt werden
kann, muss die Chip-Zeile künftig **immer** gerendert werden — mindestens mit dem
"+"-Button. Das bedeutet: Artikel, die bisher gar keine Metadaten-Zeile unter dem Titel
zeigten, bekommen jetzt durchgängig eine schmale Zeile (~26pt hoch) mit nur dem
"+"-Button. Das ist eine bewusste, notwendige Konsequenz des Features (kein Weg, sonst den
ersten Tag aus dem Header heraus anzulegen) und wird hier explizit als Spec-Entscheidung
festgehalten.

```swift
@ViewBuilder
private func readerArticleMetadata(_ snapshot: ArticleReaderSnapshot) -> some View {
    let folderName = FeedFolderOrganizer.normalizedFolderName(snapshot.folderName)
    FlowLayout(spacing: 8) {
        if let folderName {
            readerFolderChip(folderName)
        }
        ForEach(snapshot.tags) { tag in
            readerTagChip(tag)
        }
        readerAddTagButton(snapshot)
    }
    .padding(.top, 2)
}

@State private var isTagAssignmentPopoverPresented = false

private func readerAddTagButton(_ snapshot: ArticleReaderSnapshot) -> some View {
    Button {
        isTagAssignmentPopoverPresented.toggle()
    } label: {
        Image(systemName: "plus")
            .font(interfaceTextSize.font(size: 12, weight: .semibold))
    }
    .buttonStyle(.plain)
    .frame(width: readerMetadataChipHeight, height: readerMetadataChipHeight)
    .background(.secondary.opacity(0.08), in: Circle())
    .overlay {
        Circle().stroke(.secondary.opacity(0.16), lineWidth: 1)
    }
    .help(L10n.readerAddTagCommand)
    .popover(isPresented: $isTagAssignmentPopoverPresented) {
        ArticleTagAssignmentView(articleID: snapshot.id, snapshotTags: snapshot.tags)
            .padding(12)
            .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
    }
}
```

- Styling bewusst abweichend von den Chips (Kreis statt Kapsel), damit der Button klar als
  Aktion statt als Inhalt erkennbar ist. Gleiche Höhe wie die Chips (`readerMetadataChipHeight`),
  damit die Zeile optisch nicht "springt".
- Popover-Größe orientiert sich an, aber ist kompakter als der volle Inspector
  (`minWidth: 280, idealWidth: 318, maxWidth: 360` dort) — im Popover-Kontext reicht weniger
  Platz, da kein Kontext-/Quellen-Bereich mitgerendert wird.
- Popover-Verhalten: bleibt beim Togglen einzelner Tags offen (Standard-`.popover`-Verhalten
  in SwiftUI — schließt nur bei Klick außerhalb oder erneutem Klick auf den "+"-Button),
  analog zum heute gebauten Mehrfach-Tag-Suchpopover in `ArticleSearchWindowView`.
- Da `ArticleWindowView` (Artikel-Popout-Fenster) `SQLiteReaderView` intern wiederverwendet,
  ist keine zweite Integration nötig — der "+"-Button erscheint dort automatisch mit.

## Datenfluss / Synchronisation

```
Nutzer klickt "+" im Reader-Header
  → Popover zeigt ArticleTagAssignmentView(articleID: snapshot.id, snapshotTags: snapshot.tags)
  → View lädt via TagStore: assignedTags (gemergt aus snapshotTags + direkten Zuweisungen), availableTags
  → Nutzer togglet Tag ODER erstellt neuen Tag
  → TagStore-Mutation (assign/remove/save)
  → SidebarBadgeInvalidation.bumpDirectTagVersion()
  → (a) ArticleTagAssignmentView selbst: .onChange(of: directTagVersion) → loadTags() erneut
  → (b) SQLiteReaderView: bereits bestehende @AppStorage-Beobachtung von directTagVersion
        → reloadCurrentArticleSnapshot() → state.snapshot wird neu geladen
        → Chip-Zeile (readerArticleMetadata) zeigt den neuen Tag als Chip
  → (c) Falls Metadaten-Inspector gleichzeitig offen ist: dessen eingebettete
        ArticleTagAssignmentView-Instanz reagiert ebenfalls auf denselben Versionszähler
```

Es gibt keinen neuen Zustand, der manuell zwischen Reader-Header und Inspector
synchronisiert werden müsste — beide hängen ausschließlich am bereits etablierten
`SidebarBadgeInvalidation.directTagVersionKey`-Mechanismus.

## Fehlerbehandlung

Unverändert gegenüber dem bestehenden Verhalten im Inspector: `guard let database else { return }`
in allen Mutationsmethoden, `do/catch` mit stillem Fallback bei GRDB-Fehlern (kein Alert).
Das ist bewusst konsistent mit dem Rest des Reader-Moduls und keine Verschlechterung
gegenüber dem Status quo.

## L10n

Neuer Key für den Tooltip des "+"-Buttons:

```swift
static let readerAddTagCommand = String(localized: "reader.addTag.command")
```

(Wert z. B. "Tag hinzufügen" / "Add Tag" — folgt dem Muster von `articleCreateRuleCommand`.)
Alle übrigen Texte (`readerInspectorTags`, `readerInspectorNoTags`, `readerInspectorNewTag`,
`readerInspectorAddTagPlaceholder`) werden unverändert aus dem bestehenden Bestand
wiederverwendet, da `ArticleTagAssignmentView` exakt dieselbe UI wie die bisherige
`tagSection` rendert.

## Testing / Verifikation

- `SQLiteTagStoreTests.swift` deckt die zugrunde liegende `TagStore`-Logik
  (Zuweisen/Entfernen/Erstellen) bereits ab und bleibt unverändert gültig, da an `TagStore`
  selbst nichts geändert wird.
- Für `ArticleMetadataInspectorView`/`SQLiteReaderView` existieren im Projekt keine
  dedizierten View-Unit-Tests (SwiftUI-View-Structs werden in diesem Projekt konventionell
  nicht per ViewInspector o. Ä. getestet) — das gilt auch für den neuen Baustein.
  Verifikation erfolgt über `xcodebuild build` (Kompilierfähigkeit) plus manuelle visuelle
  Prüfung durch den Nutzer (kein computer-use für native macOS-Apps in dieser Umgebung
  verfügbar, siehe bestehende Einträge in CLAUDE.md zu offenen manuellen Verifikationen).
- Manuelle Prüfpunkte für den Nutzer: (1) "+" erscheint bei Artikeln ohne jegliche Chips,
  (2) Popover zeigt korrekt zugewiesene vs. verfügbare Tags, (3) neuer Tag erscheint sofort
  als Chip im Header, (4) bei gleichzeitig offenem Metadaten-Inspector bleiben beide
  Ansichten synchron, (5) Popout-Fenster (`ArticleWindowView`) zeigt denselben Button.

## Betroffene Dateien

- **Neu:** `Feedivo/Views/Reader/ArticleTagAssignmentView.swift`
- **Geändert:** `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift` (Refactor: tote
  Tag-Logik entfernt, `tagSection` nutzt neuen Baustein)
- **Geändert:** `Feedivo/Views/Reader/SQLiteReaderView.swift` (neuer "+"-Button, Popover,
  Chip-Zeile immer sichtbar statt bedingt)
- **Geändert:** `Feedivo/Resources/L10n.swift` (+1 neuer Key `readerAddTagCommand`)
