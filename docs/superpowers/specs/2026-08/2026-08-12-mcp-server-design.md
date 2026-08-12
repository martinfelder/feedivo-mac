# Feedivo MCP-Server (v1, read-only) — Design

**Datum:** 2026-08-12
**Status:** Genehmigt, bereit für Implementierungsplan

## Ziel

Ein MCP-Server (Model Context Protocol), mit dem eine KI (Claude Desktop, Claude Code
oder andere MCP-fähige Clients) Feeds und Artikel aus Feedivo lesend abfragen kann —
Volltextsuche, Filterung nach Status/Tag/Feed/Ordner/Zeitraum, Einzelartikel-Inhalt,
Übersichten über Feeds/Ordner/Tags/Intelligente Ordner. Damit werden Abfragen wie
"Fasse mir die ungelesenen Tech-Artikel der letzten 3 Tage zusammen" oder "Mach mir
eine Zusammenstellung der wichtigsten News" möglich — der Server liefert dafür die
Rohdaten (Titel, Kurztext, Metadaten), die inhaltliche Priorisierung/Synthese
übernimmt die KI selbst.

**Bewusst außerhalb des Scopes von v1:** Schreibzugriffe (gelesen/Stern markieren,
Tags zuweisen, Feeds verwalten). Die Architektur ist so gewählt, dass Schreibzugriffe
in einer späteren Phase ohne Bruch nachgezogen werden können (siehe Roadmap unten).

## Warum kein Schreiben in v1

Zwei Gründe, unabhängig von der grundsätzlichen technischen Machbarkeit (siehe
Roadmap — Schreiben direkt in SQLite ist möglich, WAL-Modus erlaubt mehrere Prozesse
auf derselben Datei):

1. **UI-Sync:** Seit dem Performance-Fix vom 2026-08-05 ist `SQLiteDataInvalidation`
   ein reiner in-process `@Observable`-Singleton (vorher `UserDefaults`-basiert,
   prozessübergreifend). Ein externer Schreibzugriff würde die UI einer gerade
   offenen Feedivo-Instanz nicht automatisch aktualisieren, ohne einen zusätzlichen
   Cross-Process-Notify-Mechanismus.
2. **Business-Logik:** Mehrere Tabellen haben nicht-triviale Invarianten, die über
   die App-eigenen `Store`-Klassen gepflegt werden (z. B. der denormalisierte
   `feeds.unreadCount`-Zähler, CloudSyncs `changedFields`-Tracking/Pending-Queue).
   Rohes SQL von außen würde diese Invarianten umgehen.

v1 bleibt deshalb rein lesend — das eliminiert beide Probleme komplett, liefert aber
bereits den Hauptnutzen (KI-gestützte Abfragen/Zusammenfassungen).

## Architektur

### Neues Swift Package: `FeedivoCore`

Extrahiert `Feedivo/Database/` und `Feedivo/Stores/` (die reinen, UI-freien
Persistenz-/Query-Schichten — keine SwiftUI-, keine AppKit-Abhängigkeiten) aus dem
App-Target in ein lokales Swift Package innerhalb des Repos. Sowohl `Feedivo.app`
als auch der neue MCP-Server hängen von `FeedivoCore` ab — eine einzige Quelle der
Wahrheit für Schema, Migrationen und Queries. Kein Risiko von Schema-Drift zwischen
App und Server, da beide denselben Code nutzen.

Dieser Schritt ist ein reiner Extraktions-Refactor ohne Verhaltensänderung an der
App selbst — muss aber sorgfältig gemacht werden (Migrationen, GRDB-Setup,
Environment-Key `\.feedivoDatabase` bleiben app-seitig, nur die reine
Datenzugriffsschicht wandert).

### Neues Executable-Target: `FeedivoMCPServer`

- Im selben Xcode-Projekt, hängt von `FeedivoCore` ab.
- Kommuniziert über **stdio** mit MCP-Clients (JSON-RPC 2.0, MCP-Standardtransport)
  — funktioniert identisch mit Claude Desktop und Claude Code, gleiche Binary,
  unterschiedlicher Config-Eintrag beim Client.
- Öffnet die Feedivo-Datenbankdatei **read-only** über eine eigene `DatabasePool`-
  Instanz (WAL-Modus erlaubt das gefahrlos parallel zu einer eventuell laufenden
  Feedivo-App-Instanz — funktioniert auch, wenn Feedivo gar nicht läuft).
- Kein Netzwerk-Listener, keine Ports — rein lokaler stdio-Prozess, den der
  MCP-Client selbst startet und beendet.

### Distribution

Wird als Helper-Executable in `Feedivo.app` mitgebaut und -verteilt (z. B.
`Contents/MacOS/feedivo-mcp-server`) — landet automatisch bei jedem Sparkle-/
Homebrew-Update mit, kein separater Distributionsweg nötig. Nutzer tragen den
absoluten Pfad in ihre MCP-Client-Konfiguration ein.

Optional, nicht blockierend für v1: eine Zeile in den Feedivo-Einstellungen, die
den fertigen Config-Snippet zum Kopieren anzeigt.

## Tools (MCP-Werkzeuge)

| Tool | Zweck | Rückgabe |
|---|---|---|
| `search_articles` | Volltextsuche + Filter: gelesen/ungelesen, Stern, Tag(s), Feed(s), Ordner, Zeitraum, Limit | Liste: Titel, Feed, Datum, Kurztext/Excerpt, Tags, Artikel-ID — **kein Volltext** (Token-Sparsamkeit) |
| `get_article` | Einzelnen Artikel per ID vollständig lesen | Bereinigter Klartext (wiederverwendet `ReaderContentRenderer`s HTML→Text-Konvertierung) |
| `list_feeds` | Alle Feeds mit Ordner-Zuordnung + Ungelesen-Zähler | Liste |
| `list_folders` | Alle Ordner | Liste |
| `list_tags` | Alle Tags mit Anzahl zugeordneter Artikel | Liste |
| `list_smart_folders` | Standard + eigene Intelligente Ordner | Liste |
| `get_smart_folder_articles` | Artikel eines Intelligenten Ordners abfragen (nutzt bestehende Bedingungs-Auswertung) | Liste wie `search_articles` |

`search_articles` liefert bewusst nur Kurztext/Excerpt statt Volltext in der
Trefferliste — für Detailfragen zu einem konkreten Artikel ruft die KI gezielt
`get_article` auf. Das hält Antworten bei größeren Trefferlisten token-günstig.

## Fehlerbehandlung

- Datenbank nicht erreichbar/gesperrt → klare MCP-Fehlerantwort, kein Absturz des
  Server-Prozesses.
- Ungültige/unbekannte Artikel-ID bei `get_article` → definierter "nicht
  gefunden"-Fehler statt stillem Leerergebnis.
- Leere Treffermenge bei `search_articles` ist kein Fehler, sondern eine leere
  Liste.

## Testing

- `FeedivoCore` bekommt eigene Unit-Tests (In-Memory-GRDB, analog zu den
  bestehenden Store-Tests in `FeedivoTests/`).
- `FeedivoMCPServer` bekommt Integrationstests gegen eine echte Test-DB-Datei im
  WAL-Modus (damit das Nebeneinander mit einer "laufenden App" realistisch
  getestet ist, nicht nur In-Memory).
- Manuelle Verifikation: Server in Claude Desktop registrieren, echte Abfragen
  gegen die eigene Feedivo-Datenbank durchspielen.

## Offene technische Frage für den Implementierungsplan

Ob ein bestehendes MCP-Swift-SDK (z. B. das offizielle
`modelcontextprotocol/swift-sdk`) verwendet wird, oder das stdio-JSON-RPC-Protokoll
minimal selbst implementiert wird — abhängig vom Reifegrad/den Abhängigkeiten des
SDKs zum Zeitpunkt der Implementierung. Keine Design-Entscheidung, sondern eine
Recherchefrage für den Plan.

## Roadmap (nicht Teil dieses Plans)

- **v2 — Schreibzugriffe:** gelesen/Stern markieren, Tags zuweisen — direkt über die
  geteilten `FeedivoCore`-Stores (keine Logik-Duplikation), plus eine
  leichtgewichtige Cross-Process-Benachrichtigung (Darwin-Notification /
  `DistributedNotificationCenter`), auf die eine gerade laufende Feedivo-App-Instanz
  reagiert und `SQLiteDataInvalidation.shared.bumpStatusVersion()` aufruft — damit
  bleibt der 2026-08-05er Performance-Fix für den normalen In-App-Pfad unangetastet,
  externe Schreibzugriffe lösen die UI-Aktualisierung nur zusätzlich, gezielt aus.
- **v3+ — Feed-/Regel-Verwaltung:** Feeds hinzufügen/entfernen, OPML-Import, Regeln
  anlegen — analog über die geteilten Stores.
