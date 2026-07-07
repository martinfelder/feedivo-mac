# Ordner-Auswahl beim Feed-Hinzufügen — Design

## Ziel

Beim Hinzufügen eines Feeds über `AddFeedSheet` soll der Feed direkt einem Ordner zugeordnet
werden können. Bisher wird jeder neue Feed ohne Ordner (`folderName == nil`) angelegt; die
Zuordnung ist erst nachträglich über die Feed-Eigenschaften möglich. Die Ordner-Auswahl soll
als Auswahlmenü mit bestehenden Ordnern plus einer „Neuer Ordner…"-Option erfolgen.

## Kontext / Ist-Zustand

- Ordner-Zugehörigkeit ist denormalisiert als `folderName: String?` direkt auf `FeedRecord`.
  Zusätzlich existiert die Tabelle `feed_folders` (`FeedFolderRecord`: `id`, `name`) für explizit
  angelegte — auch leere — Ordner.
- Gruppierung/Normalisierung der Ordnernamen läuft über `FeedFolderOrganizer`
  (`normalizedFolderName`, `folderNames(feedFolderNames:explicitFolderNames:)`), case-insensitiv.
- Der OPML-Import in `SQLiteFeedSubscriptionService.importOPMLFeeds` setzt bereits beim Anlegen
  `folderName` auf dem `FeedRecord` und legt für neue Ordnernamen einen `FeedFolderRecord` an
  (Referenzmuster für diese Änderung).
- `AddFeedSheet` (in `Feedivo/Views/Sidebar/SidebarView.swift`) hat einen zweistufigen Flow:
  URL eingeben → `FeedDiscoveryService` findet Feeds → ein Ergebnis auswählen → „Abonnieren".
  „Abonnieren" ruft `FeedViewModel.addFeed(urlString:sqliteDatabase:)`.

## Design

### Schreibpfad (Ansatz A: `folderName` durch die Service-Schichten durchreichen)

Ein optionaler `folderName: String?` wird durch die bestehende Aufrufkette gereicht — atomar,
ohne zweiten Schreibvorgang, konsistent mit dem OPML-Pfad:

1. `FeedViewModel.addFeed(urlString:sqliteDatabase:folderName:)` — neuer optionaler Parameter
   (Default `nil`, damit bestehende Aufrufer unverändert bleiben).
2. `SQLiteFeedActionService.addFeed(urlString:refreshIntervalMinutes:folderName:)` — reicht
   durch.
3. `SQLiteFeedSubscriptionService.addFeed(urlString:refreshIntervalMinutes:folderName:)`:
   - normalisiert den Namen via `FeedFolderOrganizer.normalizedFolderName(folderName)`,
   - setzt das Ergebnis auf den neu gebauten `FeedRecord` (bisher implizit `nil`),
   - legt bei neuem (normalisiertem) Namen zusätzlich einen `FeedFolderRecord` an — dieselbe
     Logik wie im OPML-Zweig (Duplikat-Vermeidung über bereits vorhandene Ordnernamen,
     case-insensitiv).

Die Anlage von Feed und Folder-Record erfolgt im selben Ablauf wie bisher; die vorhandene
Fehlerbehandlung/Cleanup-Logik (`cleanupSQLiteSubscription`) bleibt unangetastet.

### UI (`AddFeedSheet`)

Neue „Ordner"-Zeile, die erst erscheint, wenn ein Feed-Ergebnis ausgewählt ist (also am
Abonnieren-Schritt), platziert zwischen Feed-Vorschau und Button-Zeile.

- Ein `Menu`/`Picker` zeigt:
  - „Kein Ordner" (Default-Auswahl)
  - alle bestehenden Ordnernamen, ermittelt als Union aus `FeedFolderStore.folders()` und den
    vorhandenen Feed-`folderName`s, normalisiert/sortiert über `FeedFolderOrganizer`
  - Trenner + „Neuer Ordner…"
- Auswahl von „Neuer Ordner…" blendet ein kleines Inline-`TextField` für den neuen Namen ein.
- Die Ordnerliste wird beim Erscheinen des Sheets bzw. beim Eintreffen der Discovery-Ergebnisse
  aus der Datenbank geladen.

Neuer View-State in `AddFeedSheet`:
- `selectedFolderName: String?` — `nil` = kein Ordner
- `isCreatingNewFolder: Bool`
- `newFolderName: String`
- `availableFolderNames: [String]`

Beim „Abonnieren" wird der effektive Ordnername bestimmt (ausgewählter Ordner, oder bei „Neuer
Ordner…" der getrimmte `newFolderName`) und an `FeedViewModel.addFeed(…, folderName:)` übergeben.

### Edge Cases

- Leerer/Whitespace-Ordnername oder „Neuer Ordner…" ohne Eingabe → `folderName == nil`
  (kein Ordner). Durchgesetzt über `FeedFolderOrganizer.normalizedFolderName`, das genau dafür
  `nil` liefert.
- Case-insensitiver Match gegen bestehende Ordner verhindert Duplikate (ein neu getippter Name,
  der einem bestehenden Ordner entspricht, landet im bestehenden Ordner; kein zweiter
  `FeedFolderRecord`).
- Bestehende Aufrufer von `addFeed` ohne `folderName`-Argument verhalten sich unverändert
  (Default `nil`).

### L10n

- „Ordner"-Label und „Kein Ordner" aus vorhandenen Keys wiederverwenden
  (`feedPropertiesFolder`, `feedPropertiesNoFolder`).
- Ein neuer Key für „Neuer Ordner…" (Deutsch/Englisch) in `Localizable.xcstrings` + `L10n.swift`.

## Tests

Auf Service-Ebene (Swift Testing, gezielt scoped — kein unscoped `xcodebuild test`):

- `addFeed` mit gültigem `folderName` setzt `feed.folderName` (normalisiert) und legt bei neuem
  Namen einen `FeedFolderRecord` an.
- `addFeed` mit `folderName == nil` lässt `feed.folderName == nil` (bestehendes Verhalten).
- `addFeed` mit einem Namen, der einem bestehenden Ordner (andere Groß-/Kleinschreibung)
  entspricht, legt keinen zweiten `FeedFolderRecord` an.

Die UI (`AddFeedSheet`) wird — wie im Rest der Codebase üblich — nicht unit-getestet; manuelle
Verifikation im laufenden Build (Feed hinzufügen mit „Kein Ordner", bestehendem Ordner und neuem
Ordner; Sidebar-Gruppierung prüfen).
