# Gelesen/Ungelesen-Anzeige für "Heute" und "Alle Artikel" Design

## Ziel

Die Smart Folder "Alle Artikel" und "Heute" enthalten gemischte Artikel (gelesen und ungelesen), zeigen
aber aktuell keine Zahl in der Sidebar an — die bestehende Badge-Logik (`SmartFolderSidebarBadgeKind`)
kennt nur reine Status-Filter (Ungelesen/Mit Stern/Ausgeblendet/Gespeichert). Diese zwei Ordner sollen
zusätzlich zur ungelesenen Anzahl auch die gelesene Anzahl anzeigen.

## Geltungsbereich

Nur die zwei Default-Smart-Folder mit `defaultKey == "all"` ("Alle Artikel") und `defaultKey == "today"`
("Heute"). Alle anderen Smart Folder (Ungelesen, Mit Stern, Ausgeblendet, Archiviert, benutzerdefinierte)
bleiben bei ihrer bestehenden Einzel-Badge-Logik unverändert.

## Design

### Architektur & Datenfluss

- Neue Methode `TimelineStore.readUnreadCounts(for folder: SQLiteSmartFolderSnapshot) throws ->
  SmartFolderMixedCounts` (neuer Struct: `SmartFolderMixedCounts: Equatable, Sendable { let read: Int;
  let unread: Int }`). Sie nutzt die bestehende private Methode `appendSmartFolderWhereClause`, um exakt
  dieselbe WHERE-Klausel wie die echte Artikelliste des Ordners zu erzeugen (inkl. der "Heute"-
  Datumsbedingung), ergänzt `s.isHidden = 0`, sofern `folder.includesHiddenArticles == false`, und führt
  eine `SUM(CASE WHEN s.isRead = 1 THEN 1 ELSE 0 END)` / `SUM(CASE WHEN s.isRead = 0 THEN 1 ELSE 0 END)`-
  Abfrage über `articles a JOIN feeds f ON f.id = a.feedID JOIN article_statuses s ON s.articleID = a.id`
  aus (JOIN auf `feeds` bleibt aus Konsistenzgründen mit der bestehenden Artikelliste erhalten, auch wenn
  die zwei betroffenen Default-Ordner keine feed-bezogene Bedingung nutzen).
- Da über die vorhandene Bedingungs-SQL-Erzeugung gerechnet wird (statt einer zweiten, separaten
  Datums-Logik), können Badge-Zahl und tatsächlicher Ordner-Inhalt nicht auseinanderlaufen — auch wenn
  ein Ordner später im Editor umbenannt oder in seinen Bedingungen angepasst wird.
- In `SQLiteSidebarState.load(database:showsReadFeeds:)` wird nach dem Laden der Smart-Folder-Snapshots
  für die Ordner mit `defaultKey == "all"` und `defaultKey == "today"` (sofern vorhanden) je einmal
  `readUnreadCounts(for:)` aufgerufen. Ergebnis landet in einer neuen
  `private(set) var mixedCountsByDefaultKey: [String: SmartFolderMixedCounts] = [:]`
  (Schlüssel: `defaultKey`-String). Wird ein Ordner nicht gefunden (gelöscht) oder schlägt die Abfrage
  fehl, bleibt der entsprechende Eintrag im Dictionary einfach aus — kein Fehlerzustand.
- Zwei zusätzliche, feste COUNT-Abfragen pro Sidebar-Refresh (nicht pro Zeile, keine O(n)-Skalierung) —
  konsistent mit den bestehenden Performance-Vorgaben für Sidebar-Badges.

### Visuelles Design

In `SmartFolderSidebarRow` (`Feedivo/Views/Sidebar/SidebarView.swift`): Existiert für den Ordner (per
`smartFolder.defaultKey`) ein Eintrag in `mixedCountsByDefaultKey`, werden statt des bisherigen einzelnen
`badgeText` zwei Elemente nebeneinander gerendert, jeweils nur sichtbar, wenn ihr Wert > 0 ist:

- **Gelesen-Zahl** (links, näher am Ordner-Namen): schlichter Text in `SidebarStyle.secondaryText`, ohne
  Kapsel-Hintergrund, gleiche Schriftgröße/-gewicht wie die bestehende Badge (`11pt, semibold,
  monospacedDigit`).
- **Ungelesen-Zahl** (rechts, am äußeren Rand): unverändert wie die bestehende Badge — Kapsel-Hintergrund
  `SidebarStyle.activeSelection`, `Capsule()`-Form.

Für alle anderen Ordner ändert sich die Zeilen-Darstellung nicht — die bestehende
`SmartFolderSidebarBadge.badgeText(for:snapshot:)`-Logik bleibt für sie die einzige Quelle.

### Edge Cases

- Beide Zahlen 0 → kein Badge/Text sichtbar (wie bisher bei leeren Ordnern).
- Nur Gelesen > 0, Ungelesen = 0 → nur die dezente Gelesen-Zahl erscheint, keine Kapsel.
- Nur Ungelesen > 0, Gelesen = 0 → nur die Kapsel erscheint, wie beim heutigen Einzel-Badge-Verhalten.
- Wird "Heute" oder "Alle Artikel" gelöscht, fehlt der entsprechende Eintrag im Dictionary — die Zeile
  existiert dann ohnehin nicht mehr in der Sidebar.
- Wird "Heute" im Editor umbenannt oder farblich angepasst, bleibt `defaultKey` erhalten — die Zuordnung
  funktioniert unverändert. Nur eine inhaltliche Änderung der Bedingungen (z. B. von "heute" auf "diese
  Woche") ändert automatisch mit, was gezählt wird — gewünschtes Verhalten, kein Sonderfall.

## Nicht Teil dieses Designs

- Keine Erweiterung auf weitere/benutzerdefinierte Smart Folder — nur die zwei genannten Default-Ordner.
- Keine Änderung an der bestehenden Einzel-Badge-Logik für Ungelesen/Mit Stern/Ausgeblendet/Archiviert.
- Kein neues Nutzer-Setting zum Ein-/Ausblenden der Gelesen-Zahl.

## Tests

Neuer Test für `TimelineStore.readUnreadCounts(for:)`: Artikel mit gemischtem Lesestatus in einem Ordner
ohne Bedingungen (Äquivalent zu "Alle Artikel") und in einem Ordner mit Datumsbedingung (Äquivalent zu
"Heute"), inkl. eines ausgeblendeten Artikels zur Prüfung der Hidden-Exklusion (darf in keiner der beiden
Zahlen mitgezählt werden, wenn `includesHiddenArticles == false`).
