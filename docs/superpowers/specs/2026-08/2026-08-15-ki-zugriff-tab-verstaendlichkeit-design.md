# Design: Einstellungen-Tab „KI-Zugriff" verständlicher gestalten

**Datum:** 2026-08-15
**Status:** Zur Review

## Kontext

Der Tab „KI-Zugriff" (`MCPServerSettingsView` in `Feedivo/Views/Settings/SettingsView.swift`)
entstand am 2026-08-14 zusammen mit dem MCP-Server-Schalter (siehe
`2026-08-14-mcp-server-schalter-design.md`). Er funktioniert, ist aber schwer verständlich —
belegt durch die Live-Verifikation am 2026-08-15, bei der der Nutzer an genau seinen Schwächen
scheiterte.

Konkrete Befunde am bestehenden Stand:

1. **Fachjargon ohne Auflösung.** Überschrift „KI-Zugriff (MCP):", Schalter „MCP-Server
   aktivieren". Weder „MCP" noch „Server" sagen, was tatsächlich passiert.
2. **Ein Textblock mit vier Aussagen.** Die Schalter-Beschreibung erklärt gleichzeitig, was die
   Funktion tut, welche Daten gelesen werden, dass sie standardmäßig nur liest, und dass ein
   Client-Neustart nötig ist. Der Neustart-Hinweis steht am Ende — er ist aber der Punkt, an dem
   die Einrichtung real scheitert.
3. **Die Einrichtung endet beim JSON-Schnipsel.** Wohin er gehört, steht nur als Klammerbemerkung
   im Hilfetext darunter. Dass danach der Client neu gestartet werden muss, steht in einem
   anderen Absatz weiter oben.
4. **Keinerlei Rückmeldung.** Es ist nicht erkennbar, ob je ein Client verbunden war. Am
   2026-08-15 lief ein Serverprozess seit Stunden mit einer veralteten Werkzeugliste (7 statt 10),
   ohne dass das irgendwo sichtbar gewesen wäre — der Nutzer bemerkte es erst, als eine Aktion
   nicht funktionierte.

## Architektur

### 1. Client-Erkennung — `MCPClientDetector`

Neuer, reiner Typ in `Feedivo/Services/MCPClientDetector.swift`.

```swift
struct MCPClient: Equatable {
    let displayName: String       // "Claude Desktop"
    let configPath: String        // "~/Library/Application Support/Claude/claude_desktop_config.json"
}

enum MCPClientDetector {
    static func installedClients(
        lookup: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    ) -> [MCPClient]
}
```

Die Erkennung läuft über **LaunchServices**, nicht über Dateizugriff — `urlForApplication(
withBundleIdentifier:)` funktioniert unter der App-Sandbox, ein Blick in `/Applications` täte es
nicht. Die `lookup`-Closure ist injizierbar, damit die Auswertung ohne echte Installation testbar
ist.

**Bekannt ist zunächst ausschließlich Claude Desktop** (`com.anthropic.claudefordesktop`). Auf dem
Entwicklungsrechner sind auch ChatGPT und Ollama installiert; für beide ist weder gesichert, ob
sie MCP über eine Konfigurationsdatei einbinden, noch wo diese läge. Sie zu erkennen, ohne einen
Pfad nennen zu können, würde falsche Erwartungen wecken. Die Liste bekannter Clients ist eine
Datenkonstante — ein weiterer Client ist später eine zusätzliche Zeile, keine Strukturänderung.

### 2. Verbindungsnachweis — Migration v35

Zwei neue Spalten auf der bestehenden Single-Row-Tabelle `mcp_server_settings`:

| Spalte | Typ | Bedeutung |
|---|---|---|
| `lastConnectedAt` | `DATETIME`, nullable | Zeitpunkt des letzten Serverstarts |
| `lastConnectedToolCount` | `INTEGER`, nullable | Anzahl der dabei angebotenen Werkzeuge |

**Der Server schreibt beide beim Start** — bewusst **unabhängig vom Schreibzugriff-Schalter**.
Das weicht die bisherige Regel auf, dass der Server ohne Schreibzugriff die Datenbank
ausschließlich read-only öffnet, und braucht deshalb eine klare Grenze: Die Zusage „rein lesend"
gilt weiterhin uneingeschränkt für **Inhalte** (Artikel, Tags, Status, Feeds). Vermerkt wird
ausschließlich, *dass* und *womit* sich ein Client verbunden hat.

Umsetzung im Server: nach dem Aktiv-Gate und nach dem Aufbau der Werkzeugliste eine kurzlebige
Schreibverbindung öffnen, die beiden Spalten setzen, Verbindung schließen. Schlägt das fehl, wird
der Fehler auf stderr protokolliert und der Server läuft normal weiter — ein fehlender
Verbindungsvermerk darf den Dienst nie blockieren.

**Verworfene Alternative:** Eine Darwin-Notification wie beim bestehenden Live-Refresh
(`MCPWriteNotifier`) bräuchte keine Schreibverbindung, verpufft aber, wenn Feedivo beim Start des
Clients nicht läuft — was der Normalfall ist, da Claude Desktop seine MCP-Server beim eigenen
Start hochfährt.

### 3. Der Tab — drei getrennte Bereiche

**Bereich „Zugriff"** — die beiden bestehenden Schalter, entjargonisiert:

- Überschrift: „KI-Zugriff:" (ohne „(MCP)")
- Hauptschalter: „Zugriff für KI-Assistenten erlauben"
- Beschreibung, gekürzt auf zwei Sätze: was gelesen werden darf, und dass es standardmäßig nur
  liest. „Model Context Protocol (MCP)" bleibt als Nebensatz erhalten — der Begriff hilft beim
  Nachschlagen, er darf nur nicht die Hauptaussage verdrängen.
- Der Neustart-Hinweis verschwindet hier und wird zu Schritt 3 der Einrichtung.
- Schreibzugriff-Schalter und -Beschreibung bleiben inhaltlich unverändert.

**Bereich „Einrichtung"** — ersetzt den bisherigen Fließtext durch drei nummerierte Schritte:

1. Konfiguration kopieren (bestehender Knopf, bestehender Schnipsel)
2. In diese Datei einfügen: `<erkannter Pfad>` — als eigene, auswählbare Zeile, nicht als
   Klammerbemerkung
3. `<Clientname>` neu starten

Ist **kein** bekannter Client installiert, ersetzt ein Hinweis den gesamten Bereich („Es wurde
kein unterstützter KI-Client gefunden. Feedivo unterstützt derzeit Claude Desktop."). Ein
Schnipsel ohne Ziel hilft niemandem.

**Bereich „Status"** — eine Zeile, gespeist aus den beiden neuen Spalten:

- Nie verbunden: „Noch nie verbunden — Schritte oben ausführen."
- Verbunden: „Zuletzt verbunden: <Datum, Uhrzeit> · <N> Werkzeuge (nur lesend)" bzw.
  „… · <N> Werkzeuge (inkl. Schreibzugriff)".

Die Werkzeug-Anzahl stammt aus dem **letzten tatsächlichen Serverstart**, nicht aus den aktuellen
Schaltern. Genau darin liegt ihr Wert: Weicht sie vom erwarteten Umfang ab, sitzt der laufende
Client noch auf einer veralteten Liste und muss neu gestartet werden — der Fehlerfall vom
2026-08-15, der bisher unsichtbar war.

## Datenfluss

1. Tab wird geöffnet → `load()` liest wie bisher beide Schalter, zusätzlich `lastConnectedAt` und
   `lastConnectedToolCount`; `MCPClientDetector.installedClients()` liefert die erkannten Clients.
2. Nutzer kopiert den Schnipsel, fügt ihn in die genannte Datei ein, startet den Client neu.
3. Der Client startet den Serverprozess → dieser vermerkt Zeitpunkt und Werkzeug-Anzahl.
4. Beim nächsten Öffnen des Tabs zeigt der Statusbereich den Vermerk.

Der Status aktualisiert sich **nicht live**, während der Tab offen ist — der Vorgang liegt in
einem anderen Prozess, und Polling wäre für diesen seltenen Fall unverhältnismäßig.

## Fehlerbehandlung

- Schreibfehler beim Verbindungsvermerk: stderr-Protokoll, Server läuft weiter.
- Lesefehler beim Statuszustand in der App: Statusbereich zeigt „Noch nie verbunden" (fail-safe,
  identisch zum Nie-verbunden-Fall), der Rest des Tabs bleibt bedienbar.
- Läuft die App gegen eine Datenbank ohne Migration v35 (theoretisch, da die App den Migrator beim
  Start ausführt): dieselbe Behandlung wie ein Lesefehler.

## Testing

- `MCPClientDetector`: Auswertung mit injizierter `lookup`-Closure — Client installiert, nicht
  installiert, mehrere Clients. Keine echte LaunchServices-Abfrage im Test.
- Migration v35: neue Spalten vorhanden, Standardwerte `NULL`, Bestandszeile bleibt erhalten
  (Muster wie die v31/v32/v33-Migrationstests).
- `MCPServerSettingsStore`: Lesen/Schreiben der beiden neuen Spalten, Fail-closed-Verhalten bei
  fehlender Tabelle (analog zu den bestehenden Tests).
- Statusformatierung als **reine Funktion** (Eingabe: Zeitstempel, Anzahl, Schreibzugriff-Flag →
  Ausgabe: fertiger Text), isoliert getestet — kein View-Test nötig.
- Die Server-seitige Schreibstelle liegt in `FeedivoMCPServer`, dessen Testtarget in diesem
  Projekt strukturell nie ausgeführt wird (siehe CLAUDE.md-Gotcha zu `TEST_HOST`). Die eigentliche
  Logik gehört deshalb in `MCPServerSettingsStore` (beiden Targets zugehörig, aus `FeedivoTests`
  echt testbar) — der Server ruft sie nur auf.

## Out of Scope

- **Keine automatische Konfiguration** der Client-Datei. Feedivo ist sandboxed und dürfte sie nur
  nach expliziter Auswahl im Dateidialog anfassen; ein fehlerhaftes Zusammenführen würde dort alle
  MCP-Server unbrauchbar machen. Bewusst als eigenes Vorhaben zurückgestellt.
- **Kein Verbindungstest auf Knopfdruck.** Feedivo kann den Serverprozess nicht selbst starten,
  ohne die Rolle des Clients zu übernehmen.
- **Keine Anzeige nicht unterstützter Clients** (ChatGPT, Ollama), solange kein belastbarer
  Konfigurationsweg dafür bekannt ist.
- **Keine Live-Aktualisierung** des Statusbereichs bei offenem Tab.
- Keine Änderung am Verhalten der beiden Schalter selbst.
