# Einrichtungsassistent für KI-Clients — Design

**Datum:** 2026-08-16
**Status:** Entwurf, vom Nutzer im Gespräch bestätigt

## Anlass

Der Einstellungen-Tab „KI-Zugriff" kennt bislang genau einen Client: Claude Desktop. Der
Statusbereich benennt seit dem Live-Verbindungsstatus dagegen **jeden** verbundenen Client, auch
unbekannte — eine Einrichtung nur für Claude Desktop wirkt daneben halbherzig. Wer Feedivo in
Cursor, VS Code, Zed, Windsurf oder Claude Code einbinden will, muss sich Pfad und Format selbst
zusammensuchen.

## Ziel

Ein Dropdown listet die unterstützten KI-Clients, installierte zuerst und als solche markiert.
Darunter erscheint für den gewählten Client der Konfigurationspfad und ein passend formatierter
Schnipsel zum Kopieren. Wo das Format es sicher zulässt, trägt ein Knopf den Eintrag nach
Dateiauswahl selbst ein.

## Nicht im Umfang

- **Eintrag wieder entfernen.** Wer Feedivo abklemmen will, schaltet den Zugriff im selben Tab
  aus; der Konfigurationseintrag darf dann folgenlos stehen bleiben.
- **Client automatisch neu starten.** Feedivo ist sandboxed und darf fremde Programme weder
  beenden noch starten. Der Hinweis „Client neu starten" bleibt Text.
- **Codex, ChatGPT, Ollama, Warp.** Für sie ist kein datei-basierter MCP-Weg gesichert bekannt
  (Codex nutzt TOML, nicht JSON). Sie aufzunehmen hieße, etwas zu behaupten, das niemand hier
  prüfen kann.
- **Projektbezogene Konfigurationen.** Cursor und VS Code erlauben MCP-Einträge auch pro
  Projektordner. Der Assistent deckt nur die benutzerweite Konfiguration ab.

## Client-Verzeichnis

| Client | Erkennung | Konfigurationspfad | Schema | Eintragen |
|---|---|---|---|---|
| Claude Desktop | `com.anthropic.claudefordesktop` | `~/Library/Application Support/Claude/claude_desktop_config.json` | `mcpServers` | ja |
| Cursor | `com.todesktop.230313mzl4w4u92` | `~/.cursor/mcp.json` | `mcpServers` | ja |
| Windsurf | `com.exafunction.windsurf` | `~/.codeium/windsurf/mcp_config.json` | `mcpServers` | ja |
| VS Code | `com.microsoft.VSCode` | `~/Library/Application Support/Code/User/mcp.json` | `servers` | nein |
| Zed | `dev.zed.Zed` | `~/.config/zed/settings.json` | `context_servers` | nein |
| Claude Code | nicht erkennbar | — | Terminal-Befehl | nein |

**Quellenlage, ehrlich gekennzeichnet:** Claude Desktops Datei wurde auf diesem Rechner
eingelesen, VS Codes Datei existiert dort (leer). Zed, Cursor und Windsurf sind hier **nicht
installiert** — deren Pfade und Formate stammen aus einer Web-Recherche vom 2026-08-16 und
wurden nie gegen eine echte Installation geprüft. Ihre Bundle-Identifikatoren sind der
unsicherste Teil: Sie stammen nicht aus der Recherche, sondern aus allgemeinem Wissen. Schlägt
die Erkennung fehl, ist der Schaden begrenzt — der Client erscheint dann ohne Häkchen, bleibt
aber wählbar.

**Schema-Beispiele.** `mcpServers` und `servers` sind flach:

```json
{ "mcpServers": { "feedivo": { "command": "/Pfad/zu/FeedivoMCPServer" } } }
```

Zed verschachtelt den Befehl:

```json
{ "context_servers": { "feedivo": { "command": { "path": "/Pfad/zu/FeedivoMCPServer", "args": [] } } } }
```

Claude Code bekommt statt einer Datei einen Befehl:

```
claude mcp add feedivo /Pfad/zu/FeedivoMCPServer
```

## Architektur

### Erkennung und ihre Grenze

Die Erkennung läuft weiter über LaunchServices (`NSWorkspace.urlForApplication(
withBundleIdentifier:)`) — der bestehende `MCPClientDetector` wird von „liefert die installierten
Clients" auf „liefert alle Clients, jeweils mit Installationskennzeichen" erweitert.

**Feedivo kann nicht prüfen, ob die Konfigurationsdatei existiert.** Die Sandbox verbietet jeden
Lesezugriff auf `~/.cursor/`, `~/.config/zed/` und die übrigen Orte, solange der Nutzer sie nicht
selbst über eine Dateiauswahl freigegeben hat. Der Assistent zeigt den Pfad deshalb als Angabe,
nie als Befund — Formulierungen wie „gefunden" oder „bereits eingetragen" wären eine Behauptung
ohne Grundlage.

Claude Code hat kein App-Bundle und ist damit gar nicht erkennbar; es steht ohne
Installationskennzeichen im Dropdown.

### Zusammenführen als reine Funktion

Ein eigener Baustein nimmt den bisherigen Dateiinhalt (`Data`, leer erlaubt), die Schema-Variante
und den Pfad zum Server-Programm und liefert den neuen Dateiinhalt:

- **Leere Datei oder 0 Bytes:** neues Objekt mit genau einem Eintrag.
- **Vorhandenes JSON-Objekt:** nur der Schlüssel `feedivo` unterhalb des Schema-Schlüssels wird
  ergänzt oder ersetzt. Alles andere bleibt unangetastet — die `claude_desktop_config.json`
  dieses Rechners enthält neben MCP-Einträgen auch Fensterzustände, Ordnerfreigaben und Konten.
- **Ungültiges JSON:** Fehler. Kein Rateversuch, keine Reparatur.

Die Funktion berührt kein Dateisystem und ist dadurch vollständig testbar.

### Schreiben mit Sicherungskopie

Der „Eintragen…"-Knopf öffnet ein `NSOpenPanel`, vorbelegt auf den Konfigurationspfad. Erst die
Bestätigung des Nutzers verschafft Feedivo Schreibrecht auf genau diese Datei. Danach: Inhalt
lesen, zusammenführen, **Sicherungskopie** unter `<datei>.feedivo-backup` anlegen, neuen Inhalt
schreiben. Schlägt ein Schritt fehl, bleibt die Originaldatei unverändert.

### Warum drei Clients keinen Eintragen-Knopf bekommen

- **VS Code und Zed** erlauben Kommentare in ihren Konfigurationsdateien. Ein JSON-Roundtrip
  würde diese stillschweigend löschen — fremde Einstellungen zu beschädigen wiegt schwerer als
  ein gesparter Kopiervorgang.
- **Claude Code** speichert in `~/.claude.json` den kompletten Zustand der Kommandozeilen-App
  (auf diesem Rechner unter anderem Modell-Caches, Ankündigungszähler und Terminal-Einrichtung).
  Dort gehört `claude mcp add` hin, nicht ein fremder Schreibzugriff.

Für diese drei bleibt der Kopier-Weg, der ohnehin für alle Clients angeboten wird.

### Bedienung

Der Einrichtungsbereich behält seine drei nummerierten Schritte und bekommt das Dropdown
darüber. Vorausgewählt ist der erste installierte Client, sonst Claude Desktop. Schritt 1 zeigt
Schnipsel und Kopieren-Knopf, bei Datei-Clients zusätzlich den Eintragen-Knopf; Schritt 2 nennt
den Pfad; Schritt 3 den Neustart-Hinweis. Bei Claude Code ersetzt der Terminal-Befehl den
Schnipsel, und Schritt 2 entfällt.

## Fehlerbehandlung

| Fall | Verhalten |
|---|---|
| Nutzer bricht die Dateiauswahl ab | nichts passiert, keine Meldung |
| Datei nicht lesbar oder kein Schreibrecht | Meldung im Tab, Kopier-Weg bleibt |
| Ungültiges JSON (etwa Kommentare) | Meldung „konnte nicht automatisch eingetragen werden", Kopier-Weg bleibt |
| Sicherungskopie schlägt fehl | Abbruch **vor** dem Schreiben, Originaldatei unverändert |
| Eintrag existiert bereits | wird ersetzt, ohne Rückfrage — der Pfad kann sich geändert haben |

## Testbarkeit

Per TDD abgedeckt:

- Zusammenführen: leere Datei, vorhandenes Objekt mit fremden Schlüsseln (bleiben erhalten),
  bereits vorhandener `feedivo`-Eintrag (wird ersetzt), ungültiges JSON (Fehler), alle drei
  Schema-Varianten.
- Client-Verzeichnis: Reihenfolge (installierte zuerst), Kennzeichnung, Vorauswahl ohne
  installierten Client.
- Schnipsel- und Befehlserzeugung je Schema.

Manuell zu verifizieren: dass die Dateiauswahl tatsächlich auf dem richtigen Ordner öffnet, dass
der Eintrag in Claude Desktop ankommt, und dass die Sicherungskopie entsteht. Die
Bundle-Identifikatoren von Cursor, Windsurf und Zed bleiben unverifiziert, solange diese
Programme hier nicht installiert sind.

## Bewusste Entscheidungen

1. **Kopier-Weg für alle, Eintragen nur wo sicher.** Der Kopier-Weg funktioniert unabhängig vom
   Dateiformat und kann nichts beschädigen; das automatische Eintragen ist Komfort obendrauf.
2. **Keine Aussage über den Zustand fremder Dateien.** Lieber „hier gehört es hin" als ein
   „bereits eingetragen", das die Sandbox gar nicht belegen kann.
3. **Nicht installierte Clients bleiben wählbar.** Die Erkennung stützt sich auf
   Bundle-Identifikatoren, die veralten können; ein Client, der nur wegen einer falschen
   Kennung fehlt, wäre schlimmer als ein Eintrag ohne Häkchen.
4. **Sicherungskopie statt Rückfrage-Dialog.** Ein zusätzlicher Bestätigungsschritt hilft nicht,
   wenn die Datei danach trotzdem falsch ist — eine Kopie daneben schon.
