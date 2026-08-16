# Live-Verbindungsstatus im KI-Zugriff-Tab — Design

**Datum:** 2026-08-16
**Status:** Entwurf, vom Nutzer im Gespräch bestätigt

## Anlass

Der Einstellungen-Tab „KI-Zugriff" zeigt seit dem 2026-08-15 einen Verbindungsvermerk:
wann zuletzt ein Client den MCP-Server startete und mit wie vielen Werkzeugen. Was er nicht
zeigt: ob gerade jetzt eine Verbindung besteht. Beim Testen dieses Vermerks fiel auf, dass auf
dem Rechner des Nutzers **zwei** Serverprozesse gleichzeitig liefen, ohne dass das irgendwo
sichtbar war.

## Ziel

Der Tab zeigt an, ob aktuell mindestens ein KI-Client verbunden ist, und benennt ihn. Bei
mehreren gleichzeitigen Verbindungen erscheint eine Zeile je Sitzung. Die Anzeige hält sich
selbst aktuell, solange der Tab sichtbar ist.

## Nicht im Umfang

- **Einrichtungsassistent für weitere Clients** (Dropdown mit erkannten Clients, Anleitung oder
  Eintragen per Dateiauswahl). Vom Nutzer ausdrücklich als eigenes Folgevorhaben abgetrennt —
  es braucht ein eigenes Datenmodell, Sandbox-Dateizugriff und pro Client ein anderes
  JSON-Format (`mcpServers` bei Claude Desktop und Cursor, `context_servers` bei Zed, `servers`
  bei VS Code). Der Einrichtungsbereich bleibt vorerst bei Claude Desktop.
- **Warnung bei veralteter Werkzeugliste** (laufender Server bietet 7 an, Schalter ergäben 10).
  Vom Nutzer abgewählt zugunsten der schlichten „läuft gerade"-Anzeige.
- Verbindungsdauer, Verlauf vergangener Sitzungen, Trennen einer Sitzung aus der App heraus.

## Architektur

### Datenmodell — Migration v36

Neue Tabelle `mcp_server_sessions`, eine Zeile je laufendem Serverprozess:

| Spalte | Typ | Bedeutung |
|---|---|---|
| `pid` | INTEGER, Primärschlüssel | Prozess-ID des Serverprozesses |
| `clientName` | TEXT NOT NULL | Abgeleiteter Anzeigename des Clients, z. B. „Claude" |
| `startedAt` | DATETIME NOT NULL | Zeitpunkt des Serverstarts |
| `toolCount` | INTEGER NOT NULL | Werkzeuge, die dieser Prozess tatsächlich anbietet |
| `lastHeartbeatAt` | DATETIME NOT NULL | Letztes Lebenszeichen |

`pid` als Primärschlüssel, Einfügen per `INSERT OR REPLACE`: Das Betriebssystem verwendet
Prozess-IDs wieder, ein neuer Prozess mit alter ID überschreibt so sauber die tote Zeile.

Die Spalten `lastConnectedAt`/`lastConnectedToolCount` aus v35 **bleiben unverändert**. Sie
beantworten „wann zuletzt", auch wenn gerade niemand verbunden ist; die neue Tabelle beantwortet
„wer jetzt". Kein Widerspruch, kein Rückbau.

**Aufräumen:** Der Server löscht bei jedem Start Zeilen, deren `lastHeartbeatAt` älter als
10 Minuten ist. Damit wächst die Tabelle nicht, ohne dass die App aufräumen müsste.

### Client-Erkennung

Der Serverprozess läuft **unsandboxed** und darf deshalb seinen Elternprozess ermitteln:
`getppid()`, dann `proc_pidpath()` für dessen Pfad. Aus dem Pfad wird ein Anzeigename
abgeleitet:

1. Enthält der Pfad eine `.app`-Komponente, gewinnt deren Name ohne Endung.
   `/Applications/Claude.app/Contents/Helpers/disclaimer` → `Claude`
2. Sonst der reine Dateiname: `/opt/homebrew/bin/node` → `node`
3. Schlägt die Ermittlung fehl: `Unbekannt`

Gespeichert wird **nur der Anzeigename**, nie der Pfad — er könnte Verzeichnisnamen des Nutzers
enthalten.

Die Ableitung ist eine reine Funktion und liegt bewusst in `Feedivo/Services/`, geteilt per
Xcode-Target-Membership: Das Test-Target `FeedivoMCPServerTests` läuft in diesem Projekt
strukturell nie (`Could not find test host` bei Command-Line-Tool-Targets), eine Funktion im
Server-Target wäre also nicht laufzeitgeprüft. Der Server selbst behält nur den Systemaufruf.

### Heartbeat

Nach dem Eintrag der Sitzung startet der Server einen Hintergrund-Task, der alle **15 Sekunden**
`lastHeartbeatAt` seiner eigenen Zeile aktualisiert. Er hält dafür seine Schreibverbindung offen,
statt sie alle 15 Sekunden neu zu öffnen.

Der bestehende `FeedivoMCPServerConnectionRecorder` wird dafür vom statischen `enum` zu einem
Objekt mit Lebensdauer. Er behält seine bisherige Aufgabe (Vermerk in `mcp_server_settings`) und
übernimmt zusätzlich Sitzungseintrag und Heartbeat.

Wie bisher gilt: Der Vermerk läuft **unabhängig vom Schreibzugriff-Schalter**. Die Zusage „rein
lesend" bezieht sich auf Inhalte — Artikel, Tags, Status, Feeds. Geschrieben werden ausschließlich
Verbindungsmetadaten.

### Anzeige

Eine Sitzung gilt als aktiv, wenn ihr Heartbeat jünger als **40 Sekunden** ist — zwei verpasste
Intervalle plus Puffer.

- **Mindestens eine aktive Sitzung:** eine Zeile mit grünem Punkt, Client-Name und
  Werkzeug-Anzahl, z. B. „● Claude — 10 Werkzeuge".

  Sitzungen werden dabei nach Name **und** Werkzeug-Anzahl gruppiert: Ein Client startet
  durchaus mehrere Serverprozesse gleichzeitig (auf dem Rechner des Nutzers waren es zwei),
  zwei identische Zeilen wären nur verwirrend. Bei mehr als einer Sitzung derselben Gruppe
  erscheint die Anzahl: „● Claude (2 Verbindungen) — 10 Werkzeuge". Bieten zwei Prozesse
  desselben Clients unterschiedlich viele Werkzeuge an — der Fall, dass einer noch auf einer
  veralteten Liste sitzt —, bleiben es getrennte Zeilen; genau dann ist der Unterschied die
  interessante Information.

  Sortiert wird nach Name, bei gleichem Namen nach Werkzeug-Anzahl, damit die Reihenfolge
  zwischen zwei Aktualisierungen stabil bleibt.
- **Keine aktive Sitzung:** grauer Punkt „Nicht verbunden", darunter der bestehende Text
  „Zuletzt verbunden: … · 10 Werkzeuge (inkl. Schreibzugriff)". So entsteht keine Doppelung.

Aktualisiert wird alle **5 Sekunden** über eine Schleife in `.task`. SwiftUI bricht sie ab,
sobald die Ansicht verschwindet — bei geschlossenen Einstellungen läuft nichts.

### Fehlerbehandlung

- **Server:** Jeder Fehler beim Sitzungseintrag oder Heartbeat wird auf stderr protokolliert und
  verschluckt. Ein fehlender Heartbeat ist kosmetisch und darf den Dienst nie blockieren. Auch
  eine veraltete Datenbank ohne Tabelle `mcp_server_sessions` (Feedivo seit dem Update nicht
  gestartet, siehe ADR-011: der Server migriert nie) führt nur zu einem Logeintrag.
- **App:** Ein Lesefehler ergibt „Nicht verbunden". Die Anzeige behauptet im Zweifel nie eine
  Verbindung.

## Testbarkeit

Per TDD abgedeckt:

- Migration v36 legt die Tabelle mit den erwarteten Spalten an.
- Store: Sitzung eintragen, Heartbeat aktualisieren, alte Sitzungen löschen.
- Frische-Filter: Sitzung mit frischem Heartbeat gilt als aktiv, mit altem nicht, leere Tabelle
  ergibt „nicht verbunden".
- Namensableitung: `.app`-Pfad, einfacher Binärpfad, leerer Pfad.
- Statustext für keine, eine und mehrere Sitzungen — einschließlich zweier Sitzungen desselben
  Clients mit gleicher Werkzeug-Anzahl (eine Zeile mit Anzahl) und mit unterschiedlicher
  Werkzeug-Anzahl (zwei getrennte Zeilen).

Nicht automatisiert prüfbar und deshalb manuell zu verifizieren: dass sich die Anzeige bei
geöffnetem Tab tatsächlich von selbst aktualisiert, und dass der Client-Name für Claude Desktop
korrekt „Claude" lautet.

## Bewusste Entscheidungen

1. **Heartbeat statt Prozessabfrage.** Eine sandboxed App kann fremde Prozesse nicht zuverlässig
   beobachten; `kill(pid, 0)` wäre unter Sandbox unsicher und würde bei mehreren Prozessen nur
   einen erfassen. Der Preis ist ein Zeitstempel-Update alle 15 Sekunden.
2. **Kein Ping/Pong über Darwin-Notifications.** Wäre schreibfrei und sofort, verlangte aber
   einen eigenen Thread mit laufender `CFRunLoop` im Server — deutlich mehr Nebenläufigkeit an
   der heikelsten Stelle, ohne dass der Nutzer einen Unterschied sähe.
3. **Name aus dem Bundle statt aus einer Client-Liste.** Funktioniert für jeden MCP-Client, auch
   für unbekannte, und kann nicht veralten. Der angezeigte Name ist deshalb „Claude", nicht
   „Claude Desktop".
4. **~40 Sekunden Verzögerung beim Trennen** werden bewusst hingenommen. Kürzere Toleranz hieße
   häufigere Schreibvorgänge für einen Zustandswechsel, den niemand in Echtzeit beobachtet.
