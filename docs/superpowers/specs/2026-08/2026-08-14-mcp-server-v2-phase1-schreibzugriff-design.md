# Design: Feedivo-MCP-Server V2, Phase 1 — Schreibzugriff-Fundament

**Datum:** 2026-08-14
**Status:** Zur Review

## Kontext

Der `FeedivoMCPServer` (siehe ADR-011 in CLAUDE.md) ist seit v1 (2026-08-14) read-only:
7 Tools (`list_feeds`, `list_folders`, `list_tags`, `search_articles`, `get_article`,
`list_smart_folders`, `get_smart_folder_articles`), abgesichert über `configuration.readonly = true`
auf einer `DatabaseQueue`, und einen einzigen Ein/Aus-Schalter "KI-Zugriff" in den
Einstellungen (`MCPServerSettingsView`, `MCPServerSettingsStore`, Migration v31,
Tabelle `mcp_server_settings`).

Für V2 wurde der Gesamtscope (Schreibzugriff, mehr Lese-Tools, bessere Suche) im
Brainstorming in vier Phasen zerlegt:

1. **Schreibzugriff-Fundament** (dieses Dokument) — Status-Aktionen (Gelesen/Stern/
   Verstecken), Tag-Zuweisung auf Artikel, plus Cross-Process-Live-Refresh
2. Feed hinzufügen/entfernen (voller FeedKit-Netzwerk-Abruf)
3. Neue Lese-Tools (Regeln, Feed-Fehler, HTML-Body-Option)
4. Such-/Filter-Verbesserungen (Datumsbereich, Sortierung, Pagination, kombinierte Filter)

Dieses Dokument deckt ausschließlich Phase 1 ab. Phasen 2–4 werden jeweils eigene,
spätere Spec→Plan→SDD-Zyklen.

## Architektur & Schalter

**Migration v32** ergänzt `mcp_server_settings` um eine neue Spalte
`writeAccessIsEnabled INTEGER NOT NULL DEFAULT 0` (Single-Row-Tabelle, analog zu v31).

**`MCPServerSettingsStore`** bekommt zwei neue Methoden: `isWriteAccessEnabled()` /
`setWriteAccessEnabled(_:)`, nach demselben Muster wie die bestehenden
`isEnabled()`/`setEnabled(_:)`.

**Settings-UI** (`MCPServerSettingsView`): zweiter Toggle "Schreibzugriff erlauben",
direkt unter dem bestehenden "KI-Zugriff"-Schalter eingerückt, ausgegraut/disabled
solange der Hauptschalter aus ist. Schaltet der Nutzer den Hauptschalter aus, wird
der Schreib-Schalter automatisch mit auf `false` zurückgesetzt — der Hauptschalter
ist ohnehin das äußere Fail-Closed-Gate (Server startet gar nicht, wenn er aus ist),
aber ein still im Hintergrund weiter aktiver Schreib-Flag wäre verwirrend, sobald der
Nutzer den Hauptschalter später wieder anschaltet, ohne sich an den Schreibzugriff zu
erinnern.

**`main.swift`**: liest nach dem bestehenden Fail-Closed-Check (Hauptschalter) zusätzlich
`isWriteAccessEnabled()`. Bei `true` wird eine **zweite** Datenbankverbindung geöffnet:
neue `FeedivoMCPServerDatabase.openWritable(at:)`, nutzt `DatabasePool` (nicht
`DatabaseQueue` — matcht den Schreib-Modus der Haupt-App, siehe `FeedivoDatabase.swift`)
**ohne** `configuration.readonly`. Die bestehende readonly-`DatabaseQueue` bleibt
unverändert für alle Lese-Tools bestehen — zwei getrennte GRDB-Verbindungen zur selben
Datei innerhalb desselben Prozesses sind unter SQLite/WAL unproblematisch (das
Haupt-App-Target und der MCP-Server sind ohnehin bereits zwei unabhängige Prozesse, die
dieselbe Datenbankdatei parallel öffnen).

Schlägt das Öffnen der Schreibverbindung fehl (z. B. Berechtigungsproblem), degradiert
der Server bewusst auf reinen Lesezugriff (Warnung nach stderr, kein harter Absturz) —
Lese-Tools bleiben in diesem Fall trotzdem nutzbar.

## Neue Tools & Datenfluss

### `update_article_status`

Parameter: `articleID` (required, String), `isRead`/`isStarred`/`isHidden`
(je optional, Bool). Mindestens eins der drei Felder muss gesetzt sein, sonst
`isError: true`. Ruft für jedes tatsächlich übergebene Feld die passende bestehende
`ArticleStatusStore`-Methode auf der schreibbaren Verbindung auf:

- `isRead` gesetzt → `ArticleStatusStore.setRead(_:articleID:at:)`
- `isStarred` gesetzt → `ArticleStatusStore.setStarred(_:articleID:at:)`
- `isHidden` gesetzt → `ArticleStatusStore.setHidden(_:articleID:at:)`

`at` jeweils `Date()` (aktueller Zeitpunkt, kein eigener Tool-Parameter). Unbekannte
`articleID` → verständliche Fehlermeldung statt rohem SQL-/FK-Fehler.

### `assign_tag` / `remove_tag`

Parameter: `articleID`, `tagID` (beide required, IDs wie gewohnt aus `list_tags`/
`search_articles`/`get_article`). Ruft `TagStore.assignTag(tagID:toArticleID:at:)` bzw.
`TagStore.removeTag(tagID:fromArticleID:)` auf der schreibbaren Verbindung auf. Kein
automatisches Tag-Anlegen — der Tag muss bereits existieren (per `list_tags` abfragbar),
sonst Fehlermeldung. Wirkt in Phase 1 bewusst nur auf Artikel, nicht auf Feeds
(`feed_tags` bleibt unangetastet — spätere Phase, falls gewünscht).

Alle drei Tools werden nur in der `ListTools`-Antwort zurückgegeben, wenn Schreibzugriff
aktiv ist — analog zum kompletten Server, der bei deaktiviertem Lesezugriff gar nicht
erst startet. Kein Laufzeit-Fehler bei deaktiviertem Schreibzugriff nötig, das Tool
taucht für den Client schlicht nicht auf.

**Bestätigung von Aktionen:** bewusst NICHT im Feedivo-Server selbst gebaut — das ist
Aufgabe des MCP-Clients (Claude Desktop/Code zeigen von sich aus eine
Tool-Aufruf-Bestätigung, sofern nicht vom Nutzer auto-approved). Der Server selbst führt
jede vom Client tatsächlich gesendete, erlaubte Anfrage direkt aus.

## Cross-Process-Live-Refresh

Nach jedem *erfolgreichen* Schreib-Tool-Aufruf postet der MCP-Server eine
Darwin-Notification (`CFNotificationCenterGetDarwinNotifyCenter()`, fester Name
`ch.martin.Feedivo.mcpServerDidWrite`) — funktioniert prozess- und sandbox-übergreifend
ohne App Group, trägt aber keine Nutzdaten (nur ein "Ping", kein Payload).

Die laufende Feedivo-App registriert dafür beim Start (`FeedivoAppDelegate`) einen
Observer auf dieselbe Notification. Bei Empfang wird auf dem MainActor sowohl
`SQLiteDataInvalidation.shared.bumpStatusVersion()` als auch
`SidebarBadgeInvalidation.shared.bumpDirectTagVersion()` ausgelöst — deckt sowohl
Artikel-Status- als auch Tag-Änderungen ab, ohne dass die Notification selbst
unterscheiden muss, was konkret geändert wurde (ein bisschen überflüssiges Neuladen ist
laut bestehender Architektur bereits als harmlos dokumentiert, siehe die
`@Observable`-Migration vom 2026-08-05).

Läuft Feedivo gerade nicht, verpufft die Notification wirkungslos — kein Fehler, kein
Nachholbedarf (die Datenänderung selbst ist bereits in der Datenbank, die App liest sie
beim nächsten Start ganz normal).

## Fehlerbehandlung

Unbekannte `articleID`/`tagID` (bzw. eine Fremdschlüssel-Verletzung durch die
bestehenden `PRAGMA foreign_keys = ON`-Constraints) werden vom jeweiligen Tool
abgefangen und als verständliche `isError: true`-Meldung zurückgegeben — konsistent zum
bestehenden Muster in `search_articles`/`get_article` (ungültige Werte werden nie still
verworfen).

## Testing

- Migration v32 + `MCPServerSettingsStore`-Erweiterung bekommen normale
  Swift-Testing-Suiten im Haupt-App-Target (wie bei v31/Task 1 des
  Schalter-Features).
- Die neuen MCP-Tools selbst sind — wie bereits alle Tools seit v1 — strukturell nicht
  per `xcodebuild test` laufzeitverifizierbar (TEST_HOST-Limitation für
  Command-Line-Tool-Targets, siehe ADR-011/Gotcha). Absicherung über Build-Verifikation
  + echten Live-stdio-JSON-RPC-Smoke-Test (`initialize`→`notifications/initialized`→
  `tools/call`), analog zu v1.
- Die Cross-Process-Refresh-Kette braucht zusätzlich eine **manuelle Live-Verifikation
  durch den Nutzer**: Feedivo offen, Claude Desktop markiert per `update_article_status`
  einen Artikel als gelesen, die App-UI aktualisiert sich sichtbar ohne Neustart/
  Ordnerwechsel.

## Out of Scope (spätere Phasen)

- Feed hinzufügen/entfernen (Phase 2)
- Tags auf Feeds zuweisen/entfernen
- Bulk-Aktionen ("alle Artikel eines Feeds als gelesen markieren")
- Neue automatisches Tag-Anlegen über den MCP-Server
- Neue Lese-Tools und Such-/Filter-Verbesserungen (Phasen 3/4)
