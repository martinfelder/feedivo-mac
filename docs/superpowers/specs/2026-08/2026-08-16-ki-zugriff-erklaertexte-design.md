# Erklärtexte im Tab „KI-Zugriff" — Design

**Datum:** 2026-08-16
**Status:** Entwurf, vom Nutzer im Gespräch bestätigt

## Anlass

Der Tab sagt zu wenig darüber, was der Nutzer tatsächlich tun muss. Die Einrichtung besteht aus
drei knappen Zeilen („1. Konfiguration kopieren / 2. In diese Datei einfügen: / 3. KI-Client neu
starten"), und zum Schreibzugriff steht ein einziger Satz. Offen bleiben genau die Fragen, an
denen die Einrichtung scheitert:

- Dass jedes Umlegen eines Schalters erst nach einem **Neustart des KI-Clients** wirkt. Der
  Server liest beide Schalter beim Start; ein laufender Client behält seine Werkzeugliste. Genau
  das hat am 2026-08-15 schon einmal in die Irre geführt — ein Serverprozess lief stundenlang mit
  7 statt 10 Werkzeugen weiter, ohne dass der Tab es sichtbar machte.
- Was Schreibzugriff konkret erlaubt — und was auch damit unmöglich bleibt.
- Woran man erkennt, dass es geklappt hat.
- Was zu tun ist, wenn die Konfigurationsdatei fehlt oder schon Einträge enthält.

## Ziel

Der Tab beantwortet diese vier Fragen, ohne unübersichtlich zu werden. Der Neustart-Hinweis steht
dauerhaft an beiden Schaltern; die ausführlichen Erklärungen stecken in zwei Aufklappbereichen.
Weichen Schalterstand und gemeldete Werkzeug-Anzahl voneinander ab, sagt der Tab das im Klartext.

## Nicht im Umfang

- **Den KI-Client neu starten.** Feedivo ist sandboxed und darf fremde Programme weder beenden
  noch starten. Der Hinweis bleibt Text.
- **Prüfen, ob eine Konfigurationsdatei existiert.** Dieselbe Sandbox-Grenze wie beim
  Einrichtungsassistenten: Der Pfad bleibt eine Angabe, nie ein Befund.
- **Neue Werkzeuge oder Schalter.** Diese Arbeit ändert ausschließlich Texte, einen Statusabgleich
  und eine geteilte Konstante.

## Aufbau

### 1. Zugriff — dauerhafter Neustart-Satz an beiden Schaltern

Unter **beiden** Schaltern steht künftig dauerhaft: „Wirkt erst, wenn du den KI-Client danach neu
startest." Bewusst dauerhaft und nicht erst nach dem Umlegen: Beim allerersten Einrichten ist der
Satz am wichtigsten, und genau dann hätte ein zustandsabhängiger Hinweis noch nicht ausgelöst.

Die Beschreibung des Schreibzugriffs wird konkreter als das heutige „Erlaubt Claude, Artikelstatus
(Gelesen/Stern/Versteckt) zu ändern und Tags zuzuweisen" — sie nennt „bestehende Tags", weil die
KI keine anlegen kann (siehe unten).

### 2. Zugriff — Aufklappbereich „Was die KI genau darf"

| Bereich | Inhalt |
|---|---|
| Immer | Feeds, Ordner, Tags und Artikel lesen, samt Gelesen- und Stern-Status; suchen; Intelligente Ordner abrufen |
| Zusätzlich mit Schreibzugriff | Gelesen, Stern und Versteckt setzen; **bestehende** Tags zuweisen und entfernen |
| Auch mit Schreibzugriff unmöglich | Feeds abonnieren oder löschen, Ordner, Regeln und Intelligente Ordner ändern, Tags anlegen oder löschen, Artikeltexte ändern, Artikel löschen |
| Rückgängig | Schalter aus, Client neu starten |

**Belegt, nicht behauptet:** Die drei Schreib-Werkzeuge sind `update_article_status`, `assign_tag`
und `remove_tag`. `AssignTagTool` prüft die übergebene `tagID` gegen `TagStore.sidebarTags()` und
lehnt unbekannte Kennungen ab — es legt also keine Tags an. Wächst die Liste der Schreib-Werkzeuge
später, muss dieser Abschnitt mitwachsen; der Vermerk in CLAUDE.md hält das fest.

### 3. Einrichtung — Aufklappbereich „Wenn etwas nicht passt"

- **Datei gibt es noch nicht:** „Automatisch eintragen…" legt sie an. Beim Kopier-Weg legst du sie
  selbst an, mit dem Schnipsel als vollständigem Inhalt.
- **Datei enthält schon Einträge:** Nur den inneren `"feedivo"`-Block in das vorhandene
  `mcpServers` einsortieren — die Datei nicht ersetzen.
- **Sicherungskopie:** Vor jedem automatischen Eintrag entsteht `<datei>.feedivo-backup`.
- **Kein Eintragen-Knopf bei VS Code, Zed und Claude Code:** Die ersten beiden erlauben Kommentare
  in ihren Dateien, die ein automatischer Eintrag löschen würde; Claude Code hat gar keine
  Konfigurationsdatei, sondern einen Terminal-Befehl.

### 4. Status — die App gleicht selbst ab

Der Statusbereich kennt bereits die Werkzeug-Anzahl jeder **laufenden** Sitzung
(`MCPServerSession.toolCount`, alle fünf Sekunden aktualisiert). Weicht sie von der ab, die die
aktuellen Schalter ergäben, erscheint eine zusätzliche Zeile:

> Der verbundene Client kennt 7 von 10 Werkzeugen — starte ihn neu.

**Verglichen wird ausschließlich gegen laufende Sitzungen, nicht gegen den letzten
Verbindungsvermerk.** Ist gerade kein Client verbunden, gibt es nichts zu melden: Der nächste Start
holt ohnehin die aktuelle Liste, und ein „starte ihn neu" wäre dann ein falscher Rat. Aus demselben
Grund erscheint die Zeile nicht, solange der Zugriff insgesamt ausgeschaltet ist — dann läuft kein
Server, gegen den sich vergleichen ließe.

Laufen mehrere Sitzungen mit unterschiedlichen Anzahlen, erscheint die Zeile, sobald **eine** von
ihnen abweicht; genannt wird die niedrigste abweichende Anzahl. Genau dieser Fall trat am
2026-08-16 real auf, als unbemerkt zwei Serverprozesse gleichzeitig liefen.

## Architektur

### Die erwartete Werkzeug-Anzahl braucht eine gemeinsame Quelle

Die Anzahl entsteht heute allein im Serverprozess: `main.swift` baut `availableTools` auf (sieben
lesende Werkzeuge, bei aktivem Schreibzugriff drei weitere) und übergibt `availableTools.count` an
den Verbindungsvermerk. Die App kennt diese Zahl nicht. Stünde sie fest im Hilfetext, würde die
Aussage stillschweigend falsch, sobald ein Werkzeug dazukommt — der Tab würde etwas behaupten, das
nicht mehr stimmt.

Neuer Baustein `MCPToolInventory` (`Feedivo/Services/`, per Target-Membership auch dem
Server-Target sichtbar — dasselbe Vorgehen wie bei `MCPWriteNotificationName`):

```swift
enum MCPToolInventory {
    static let readOnlyToolCount = 7
    static let writeToolCount = 3
    static func expectedToolCount(isWriteAccessEnabled: Bool) -> Int
}
```

**Die Serverliste bleibt die Wahrheit, die Konstante ist ihr Spiegel.** `main.swift` baut seine
Liste weiter selbst und vergleicht sie nach dem Aufbau gegen `expectedToolCount(…)`; bei einer
Abweichung schreibt es eine Warnung auf stderr. Der Serverstart scheitert deswegen nicht — eine
falsche Zahl im Einstellungen-Tab wiegt weniger als ein Client, der gar nicht mehr startet.

Diese Absicherung ist bewusst schwach: `FeedivoMCPServerTests` läuft in diesem Projekt strukturell
nie (Command-Line-Tool-Targets taugen nicht als `TEST_HOST`), und kein `xcodebuild`-Aufruf
kompiliert überhaupt eine Datei dieses Testziels. Ein echter Test der Übereinstimmung ist deshalb
nicht möglich; stattdessen stehen Kommentare an beiden Stellen und ein Vermerk in CLAUDE.md.

### Der Abgleich selbst ist eine reine Funktion

`MCPConnectionStatusText` (bereits vorhanden, rein und getestet) bekommt eine weitere Funktion, die
aus gemeldeter und erwarteter Anzahl entweder eine Hinweiszeile oder `nil` liefert. Sie kennt weder
Datenbank noch View und ist damit vollständig testbar.

### Die View bekommt zwei Aufklappbereiche

Zwei `DisclosureGroup` — einer im Zugriffs-, einer im Einrichtungsbereich —, beide standardmäßig
zugeklappt. Der Einrichtungsbereich liegt bereits in einer eigenen `setupSection`-Property; der
Zugriffsbereich bekommt aus demselben Grund ebenfalls eine eigene Property, damit der ohnehin große
`body` den Swift-Typprüfer nicht überfordert.

## Fehlerbehandlung

| Fall | Verhalten |
|---|---|
| Kein Client verbunden | Kein Abgleich — der nächste Start holt die aktuelle Liste von selbst |
| Zugriff insgesamt ausgeschaltet | Kein Abgleich — es läuft kein Server, gegen den zu vergleichen wäre |
| Laufende Sitzung passt zum Schalterstand | Keine Hinweiszeile |
| Laufende Sitzung weicht ab | Hinweiszeile mit beiden Zahlen |
| Mehrere Sitzungen, davon eine abweichend | Hinweiszeile mit der niedrigsten abweichenden Anzahl |
| Serverliste weicht von der Konstante ab | Warnung auf stderr, Server startet trotzdem |

## Testbarkeit

Per TDD abgedeckt:

- `MCPToolInventory.expectedToolCount(isWriteAccessEnabled:)` für beide Schalterstände.
- Die neue Abgleichfunktion: passende Anzahl → `nil`; abweichende Anzahl → Zeile mit beiden Zahlen;
  keine laufende Sitzung → `nil`; mehrere Sitzungen mit unterschiedlichen Anzahlen → die niedrigste
  abweichende.

Nicht automatisiert prüfbar: dass die Konstante zur tatsächlichen Serverliste passt (siehe oben),
sowie das gesamte sichtbare Verhalten der Aufklappbereiche — für native macOS-Oberflächen steht in
dieser Umgebung kein Weg zur Verfügung, mit der laufenden App zu interagieren.

Manuell zu verifizieren:

1. Unter beiden Schaltern steht dauerhaft der Neustart-Satz.
2. Beide Aufklappbereiche öffnen und schließen; Inhalte stimmen.
3. Bei laufendem, verbundenem Client den Schreibzugriff einschalten und den Client **nicht** neu
   starten → Statusbereich meldet die abweichende Werkzeug-Anzahl.
4. Client neu starten → die Hinweiszeile verschwindet.
5. Client beenden → die Hinweiszeile erscheint nicht erneut, obwohl der letzte Vermerk noch die
   alte Anzahl trägt.

## Bewusste Entscheidungen

1. **Neustart-Satz dauerhaft statt zustandsabhängig.** Beim ersten Einrichten ist er am
   wichtigsten, und da hätte ein zustandsabhängiger Hinweis noch nicht ausgelöst. Der
   zustandsabhängige Teil sitzt stattdessen im Statusbereich, wo er auf echte Zahlen gestützt ist.
2. **Zwei Aufklappbereiche statt eines gemeinsamen.** Die Antwort steht dort, wo die Frage
   entsteht — ein einzelner Hilfeblock am Ende hätte den Weg von Frage zu Antwort verlängert.
3. **Die App vergleicht selbst, statt Zahlen im Text zu nennen.** Ein Hilfetext mit „7 bzw. 10"
   veraltet still; ein Vergleich gegen den tatsächlich gemeldeten Wert sagt dem Nutzer außerdem
   etwas über seinen eigenen Zustand, nicht nur über die Theorie.
4. **Zusicherungen nur, wo sie belegt sind.** Die Liste dessen, was auch mit Schreibzugriff
   unmöglich bleibt, folgt den drei tatsächlich registrierten Schreib-Werkzeugen — nicht einer
   Absichtserklärung.
