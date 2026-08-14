# MCP-Server Ein/Aus-Schalter + Verbindungs-Hilfe — Design-Spec

## Ziel

Der Nutzer soll selbst entscheiden können, ob `FeedivoMCPServer` (siehe ADR-011,
`docs/superpowers/specs/2026-08/2026-08-12-mcp-server-design.md`) tatsächlich Daten
herausgibt. Bisher öffnet der Server die Datenbank bedingungslos, sobald ein
MCP-Client (Claude Desktop/Claude Code) ihn startet — es gibt keinerlei Kontrolle
durch den Nutzer, ob dieser Zugriff gewünscht ist. Da der Server persönliche
Lesedaten (Feed-Abos, Artikelinhalte, Gelesen-/Stern-Status) an einen externen
Prozess/eine KI weitergibt, soll das ein bewusstes Opt-in sein — standardmäßig
deaktiviert.

Zusätzlich, direkt im selben neuen Einstellungen-Bereich: eine Komfort-Zeile, die
den fertigen Claude-Desktop-Konfigurations-Snippet zum Kopieren anzeigt (bereits im
ursprünglichen Design-Spec unter „Distribution" als „optional, nicht blockierend"
vorgesehen — wird jetzt umgesetzt, da ohnehin ein neuer Tab für den Schalter
gebaut wird).

## Warum kein Live-Reconnect

Ein MCP-Client wie Claude Desktop startet den Serverprozess einmal pro
Sitzung/App-Start und hält ihn dann. Schaltet der Nutzer den Schalter während einer
laufenden Claude-Desktop-Sitzung um, merkt der Client das nicht automatisch — ein
Neustart von Claude Desktop (oder ein manuelles Neu-Verbinden, falls der Client das
anbietet) ist nötig, damit die neue Einstellung greift. Für v1 akzeptiert (kein
Live-Reconnect-Mechanismus, keine Cross-Process-Benachrichtigung an einen bereits
laufenden Server-Prozess).

## Datenmodell

Neue Migration `v31_create_mcp_server_settings` in `FeedivoDatabaseMigrator.swift`
(aktueller Stand: v30). Neue Tabelle `mcp_server_settings`:

```sql
CREATE TABLE mcp_server_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    isEnabled BOOLEAN NOT NULL DEFAULT 0
);
INSERT INTO mcp_server_settings (id, isEnabled) VALUES (1, 0);
```

Bewusst eine eigene, zweckgebundene Single-Row-Tabelle statt einer generischen
Key-Value-Settings-Tabelle (YAGNI — kein zweiter Bedarf für plattformweite
SQLite-Settings erkennbar, jede andere Einstellung in Feedivo bleibt bei
`@AppStorage`/`UserDefaults`).

**Warum SQLite statt `UserDefaults` (Abweichung von der sonstigen Projekt-
Konvention, bewusst begründet):** `UserDefaults`-Schreibvorgänge werden von
`cfprefsd` gepuffert und nicht sofort auf die Plist-Datei durchgeschrieben — ein
externer, unsandboxed Prozess, der die Plist-Datei direkt läse, könnte kurz nach
einem Toggle-Wechsel noch den alten Wert sehen. SQLite/GRDB im WAL-Modus bietet
dagegen eine bereits in diesem Projekt ausführlich verifizierte Garantie: ein
Commit ist sofort für jeden anderen lesenden Prozess sichtbar (siehe Gotcha zu
GRDBs `PRAGMA query_only`-Verhalten und `FeedivoMCPServerDatabase.swift`). Diese
Einstellung ist die einzige in der App, die zuverlässig aus einem zweiten,
unabhängigen Prozess gelesen werden muss — deshalb die Ausnahme.

## App-Seite (`Feedivo`)

- Neuer `MCPServerSettingsStore` (`Feedivo/Stores/MCPServerSettingsStore.swift`),
  analog zu bestehenden Stores: `isEnabled() throws -> Bool`,
  `setEnabled(_ isEnabled: Bool) throws`.
- Neuer Settings-Tab „KI-Zugriff" (`Feedivo/Views/Settings/MCPServerSettingsView.swift`):
  - Toggle „MCP-Server aktivieren", gebunden an `MCPServerSettingsStore`.
  - Erklärender Untertext: welche Daten offengelegt werden (Feeds, Ordner, Tags,
    Artikel inkl. Gelesen-/Stern-Status), dass der Zugriff read-only ist, und der
    Hinweis auf den nötigen Neustart des MCP-Clients nach einer Änderung.
  - Schreibgeschützte Textzeile mit dem fertigen JSON-Config-Snippet:
    ```json
    {
      "mcpServers": {
        "feedivo": { "command": "<Bundle.main.bundlePath>/Contents/MacOS/FeedivoMCPServer" }
      }
    }
    ```
    `Bundle.main.bundlePath` liefert automatisch den tatsächlich laufenden Pfad
    (funktioniert korrekt sowohl für einen Debug-Build aus DerivedData als auch für
    eine echte `/Applications`-Installation — kein hartcodierter Pfad nötig).
  - „Kopieren"-Button (`NSPasteboard.general`) neben dem Snippet.
- Einstellungen-Fensterbreite prüfen: aktuell 960pt für 10 Tabs (siehe Gotcha zur
  Tab-Leisten-Breite) — ein 11. Tab könnte erneut zu knapp werden, im
  Implementierungsplan gezielt gegenprüfen.

## Server-Seite (`FeedivoMCPServer`)

In `main.swift`, direkt nach `FeedivoMCPServerDatabase.openReadOnly()` (die
Verbindung wird für die Flag-Prüfung selbst gebraucht) und **vor** dem Registrieren
jedes Tools sowie **vor** dem Start des `StdioTransport`:

```swift
let isEnabled = try? database.core.read { db in
    try Bool.fetchOne(db, sql: "SELECT isEnabled FROM mcp_server_settings WHERE id = 1")
}
guard isEnabled == true else {
    let message = """
        Feedivo MCP Server ist deaktiviert. Aktiviere ihn unter \
        Feedivo → Einstellungen → KI-Zugriff.\n
        """
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
```

**Fail-closed bei fehlender Tabelle/Zeile:** `try?` fängt einen SQL-Fehler
("no such table", z. B. wenn Feedivo seit dem Update auf diese Version noch nicht
gestartet wurde und die Migration deshalb noch nicht gelaufen ist) ab und liefert
`nil` — der `guard isEnabled == true` schlägt dann identisch fehl wie bei
`isEnabled = false`. Konsistent mit der gewählten „lieber zu vorsichtig als zu
freizügig"-Philosophie: jeder unklare Zustand wird wie „deaktiviert" behandelt,
nie wie „aktiviert".

Bei deaktiviertem Zustand wird **nie** ein MCP-Protokoll-Handshake gestartet und
**kein** Tool registriert — der Prozess beendet sich sofort nach der Prüfung.

## Testing

- `MCPServerSettingsStoreTests` (TDD, In-Memory-GRDB): Standardwert `false` nach
  Migration, `setEnabled(true)`/`setEnabled(false)` persistieren korrekt,
  Round-Trip-Test.
- `FeedivoMCPServerTests`: neue Tests für aktiviert/deaktiviert/fehlende-Tabelle
  als echter Swift-Testing-Quellcode — wie der Rest von `FeedivoMCPServerTests`
  nur build-verifiziert, nicht laufzeitverifiziert über `xcodebuild test` (siehe
  bekannte `TEST_HOST`-Einschränkung, CLAUDE.md-Gotcha).
- Manuelle Live-Verifikationscheckliste (durch den Nutzer): Schalter aus → Claude
  Desktop neu starten → Server-Verbindung scheitert klar erkennbar; Schalter an →
  Neustart → funktioniert wie bisher; „Kopieren"-Button liefert einen Snippet mit
  dem tatsächlich korrekten, existierenden Binary-Pfad; Einstellungen-Fenster zeigt
  den neuen Tab korrekt, keine Breite-/Tab-Leisten-Regression.

## Roadmap (nicht Teil dieses Plans)

- Live-Reconnect/Cross-Process-Benachrichtigung an einen bereits laufenden
  Server-Prozess, falls der Nutzer das künftig als störend empfindet.
- Granularere Freigabe (z. B. nur Metadaten ohne Artikelinhalte) — für v1 bewusst
  verworfen (siehe Brainstorming-Entscheidung), da Feedivo eine Single-User-App
  ohne Berechtigungskonzept ist und kein konkretes Bedürfnis dafür erkennbar war.
