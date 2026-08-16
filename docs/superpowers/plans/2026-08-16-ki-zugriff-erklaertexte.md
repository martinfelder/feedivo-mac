# Erklärtexte im Tab „KI-Zugriff" — Implementierungsplan

> **Für agentische Worker:** REQUIRED SUB-SKILL: Nutze superpowers:subagent-driven-development (empfohlen) oder superpowers:executing-plans, um diesen Plan Task für Task umzusetzen. Schritte nutzen Checkbox-Syntax (`- [ ]`).

**Goal:** Der Tab „KI-Zugriff" beantwortet, was zu tun ist: ein dauerhafter Neustart-Satz an beiden Schaltern, zwei Aufklappbereiche mit den ausführlichen Erklärungen, und eine Statuszeile, die meldet, wenn ein laufender Client noch auf einer veralteten Werkzeugliste sitzt.

**Architecture:** Ein neuer geteilter Baustein `MCPToolInventory` hält die erwartete Werkzeug-Anzahl; `MCPConnectionStatusText` bekommt eine reine, testbare Abgleichfunktion; die View bekommt zwei `DisclosureGroup` und die Statuszeile. Der Serverprozess prüft seine tatsächliche Liste gegen die Konstante und warnt auf stderr, falls sie driftet.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), Swift Testing, `Localizable.xcstrings`.

## Global Constraints

- Code-Kommentare und Testnamen auf **Deutsch** (Projektkonvention). UI-Texte laufen ausschließlich über `L10n`-Konstanten bzw. `String(localized:)`, nie als rohe String-Literale in der View.
- **Keine Zusicherung ohne Beleg.** Die Liste dessen, was auch mit Schreibzugriff unmöglich bleibt, folgt den drei tatsächlich registrierten Schreib-Werkzeugen (`update_article_status`, `assign_tag`, `remove_tag`). Kein Task darf sie erweitern.
- **Der Abgleich läuft nur gegen laufende Sitzungen**, nie gegen den letzten Verbindungsvermerk — ohne verbundenen Client holt der nächste Start ohnehin die aktuelle Liste, ein „starte ihn neu" wäre falscher Rat.
- **Die Serverliste in `main.swift` bleibt die Wahrheit**, `MCPToolInventory` ist ihr Spiegel. Eine Abweichung darf den Serverstart nie verhindern.
- Tests immer gezielt mit **Suiten**-Selektoren (`-only-testing:FeedivoTests/<SuiteName>`) und `-parallel-testing-enabled NO`. Ein unscoped `xcodebuild test` deadlockt in diesem Projekt; ein Einzelmethoden-Selektor kann „TEST SUCCEEDED" bei `totalTestCount: 0` melden.
- Nach jedem Task müssen **beide** Schemes bauen: `Feedivo` und `FeedivoMCPServer`.
- SourceKit-/IDE-Diagnosen sind hier notorisch falsch („No such module 'Testing'", „Cannot find 'L10n' in scope"). Nur echte `xcodebuild`-Läufe zählen.
- Neue `L10n`-Keys erzeugen **keinen** automatischen Eintrag in `Localizable.xcstrings`; jeder Key muss manuell ergänzt und per `grep -c` verifiziert werden (muss > 0 sein).
- `Localizable.xcstrings` **niemals** per `json.load`/`json.dump` roundtripen. Nur Text-Einfügung am Anker `  "strings" : {`, danach `git diff --stat` prüfen: fast ausschließlich Insertions. Erscheinen Tausende geänderte Zeilen, hat Xcode die Datei zwischenzeitlich umformatiert — dann `git checkout -- Feedivo/Resources/Localizable.xcstrings`, Einfügung wiederholen, erneut prüfen.
- Alle `settings.mcpServer.*`-Keys haben vier Sprachen (de/en/fr/it) — neue Keys ebenso anlegen.

## Dateistruktur

| Datei | Verantwortung |
|---|---|
| `Feedivo/Services/MCPToolInventory.swift` (neu) | Erwartete Werkzeug-Anzahl je Schalterstand, geteilt mit dem Server-Target |
| `FeedivoMCPServer/main.swift` | Prüft die tatsächliche Liste gegen die Konstante, warnt auf stderr |
| `Feedivo/Services/MCPConnectionStatusText.swift` | Zusätzlich: Abgleichzeile aus laufenden Sitzungen |
| `Feedivo/Views/Settings/SettingsView.swift` | Neustart-Sätze, zwei `DisclosureGroup`, Statuszeile |
| `Feedivo/Resources/L10n.swift` + `Localizable.xcstrings` | Neue Texte |
| `Feedivo.xcodeproj/project.pbxproj` | Target-Membership der neuen geteilten Datei |

---

### Task 1: Erwartete Werkzeug-Anzahl als geteilte Konstante

**Files:**
- Create: `Feedivo/Services/MCPToolInventory.swift`
- Modify: `Feedivo.xcodeproj/project.pbxproj` (eine Zeile, zwischen Zeile 170 und 171)
- Modify: `FeedivoMCPServer/main.swift` (nach dem Aufbau von `availableTools`)
- Test: `FeedivoTests/Services/MCPToolInventoryTests.swift` (neu)

**Interfaces:**
- Consumes: nichts
- Produces:
  - `static let MCPToolInventory.readOnlyToolCount: Int` (7)
  - `static let MCPToolInventory.writeToolCount: Int` (3)
  - `static func MCPToolInventory.expectedToolCount(isWriteAccessEnabled: Bool) -> Int`

- [ ] **Schritt 1: Failing Test schreiben**

Neue Datei `FeedivoTests/Services/MCPToolInventoryTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

@Suite("MCPToolInventory")
struct MCPToolInventoryTests {
    @Test("Ohne Schreibzugriff sind es die sieben lesenden Werkzeuge")
    func ohneSchreibzugriff() {
        #expect(MCPToolInventory.expectedToolCount(isWriteAccessEnabled: false) == 7)
    }

    @Test("Mit Schreibzugriff kommen drei Werkzeuge dazu")
    func mitSchreibzugriff() {
        #expect(MCPToolInventory.expectedToolCount(isWriteAccessEnabled: true) == 10)
    }

    @Test("Die Summe ergibt sich aus den beiden Teilmengen")
    func summeIstKonsistent() {
        // Haelt die beiden Konstanten und die Rechenfunktion aneinander gebunden: Wer eine
        // Zahl aendert, ohne die andere zu pruefen, faellt hier auf.
        #expect(
            MCPToolInventory.expectedToolCount(isWriteAccessEnabled: true)
                == MCPToolInventory.readOnlyToolCount + MCPToolInventory.writeToolCount
        )
    }
}
```

- [ ] **Schritt 2: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPToolInventoryTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „cannot find 'MCPToolInventory' in scope".

- [ ] **Schritt 3: Konstante anlegen**

Neue Datei `Feedivo/Services/MCPToolInventory.swift`:

```swift
import Foundation

/// Wie viele Werkzeuge der MCP-Server bei welchem Schalterstand anbietet.
///
/// **Die Wahrheit steht in `FeedivoMCPServer/main.swift`**, wo `availableTools` tatsächlich
/// aufgebaut wird — diese Konstante ist nur ihr Spiegel für die App, die den Serverprozess nicht
/// befragen kann. Kommt dort ein Werkzeug dazu, MUSS die passende Zahl hier mitwachsen;
/// `main.swift` meldet eine Abweichung beim Start auf stderr.
///
/// Ein automatisierter Test dieser Übereinstimmung ist nicht möglich: `FeedivoMCPServerTests` läuft
/// in diesem Projekt strukturell nie, und kein `xcodebuild`-Aufruf kompiliert auch nur eine Datei
/// dieses Testziels.
enum MCPToolInventory {
    /// `list_feeds`, `list_folders`, `list_tags`, `search_articles`, `get_article`,
    /// `list_smart_folders`, `get_smart_folder_articles`.
    static let readOnlyToolCount = 7

    /// `update_article_status`, `assign_tag`, `remove_tag` — nur bei aktivem Schreibzugriff.
    static let writeToolCount = 3

    static func expectedToolCount(isWriteAccessEnabled: Bool) -> Int {
        isWriteAccessEnabled ? readOnlyToolCount + writeToolCount : readOnlyToolCount
    }
}
```

- [ ] **Schritt 4: Target-Membership für den Server ergänzen**

Die Datei muss auch dem Target `FeedivoMCPServer` gehören. In `Feedivo.xcodeproj/project.pbxproj`
steht die alphabetisch sortierte Ausnahmeliste; Zeile 170 lautet
`				Services/MCPClientNameResolver.swift,`, Zeile 171
`				Services/MCPWriteNotificationName.swift,`. Dazwischen einfügen (führende Tabs
beibehalten, exakt wie die Nachbarzeilen):

```
				Services/MCPToolInventory.swift,
```

Kontrolle — muss genau eine hinzugefügte Zeile zeigen:

```bash
git diff --stat Feedivo.xcodeproj/project.pbxproj
```

- [ ] **Schritt 5: Absicherung im Server ergänzen**

In `FeedivoMCPServer/main.swift` steht nach dem Aufbau der Liste:

```swift
FeedivoMCPServerConnectionRecorder.record(toolCount: availableTools.count)
```

Direkt **davor** einfügen:

```swift
// Spiegel-Kontrolle: `MCPToolInventory` sagt dem Einstellungen-Tab, wie viele Werkzeuge zu
// erwarten sind. Driftet die Zahl von dieser Liste ab, zeigt der Tab etwas Falsches an — der
// Start scheitert deswegen aber NICHT, ein nicht startender Server waere der groessere Schaden.
let erwarteteWerkzeuge = MCPToolInventory.expectedToolCount(
    isWriteAccessEnabled: writableDatabase != nil
)
if availableTools.count != erwarteteWerkzeuge {
    FileHandle.standardError.write(Data("""
    Warnung: \(availableTools.count) Werkzeuge registriert, MCPToolInventory erwartet \
    \(erwarteteWerkzeuge). Bitte MCPToolInventory anpassen.

    """.utf8))
}
```

- [ ] **Schritt 6: Tests grün und beide Builds prüfen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPToolInventoryTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | head -4
```

Erwartet: PASS (3 Tests).

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Debug 2>&1 | tail -2
```

Beide: BUILD SUCCEEDED. Scheitert der Server-Build mit „cannot find 'MCPToolInventory' in scope",
wurde Schritt 4 nicht wirksam — Einrückung und Position der eingefügten Zeile prüfen.

- [ ] **Schritt 7: Committen**

```bash
git add Feedivo/Services/MCPToolInventory.swift FeedivoTests/Services/MCPToolInventoryTests.swift Feedivo.xcodeproj/project.pbxproj FeedivoMCPServer/main.swift
git commit -m "feat(settings): erwartete Werkzeug-Anzahl als geteilte Konstante"
```

---

### Task 2: Statuszeile für veraltete Werkzeuglisten

**Files:**
- Modify: `Feedivo/Services/MCPConnectionStatusText.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (Statusbereich in `body`)
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Test: `FeedivoTests/Services/MCPConnectionStatusTextTests.swift`

**Interfaces:**
- Consumes: `MCPToolInventory.expectedToolCount(isWriteAccessEnabled:)` (Task 1); `MCPServerSession` (vorhanden, Felder: `pid: Int`, `clientName: String`, `startedAt: Date`, `toolCount: Int`, `lastHeartbeatAt: Date`)
- Produces: `static func MCPConnectionStatusText.staleToolListLine(sessions: [MCPServerSession], isAccessEnabled: Bool, isWriteAccessEnabled: Bool) -> String?`

- [ ] **Schritt 1: Katalogeintrag anlegen**

Ein neuer Schlüssel, per Text-Einfügung am Anker `  "strings" : {` in
`Feedivo/Resources/Localizable.xcstrings`, im Format der Nachbareinträge (`"key" : {` →
`"localizations"` → je Sprache `"stringUnit"` mit `"state" : "translated"` und `"value"`):

| Schlüssel | de | en | fr | it |
|---|---|---|---|---|
| `settings.mcpServer.status.staleToolList` | `Der verbundene Client kennt %1$d von %2$d Werkzeugen — starte ihn neu.` | `The connected client knows %1$d of %2$d tools — restart it.` | `Le client connecté connaît %1$d outils sur %2$d — redémarrez-le.` | `Il client connesso conosce %1$d strumenti su %2$d — riavvialo.` |

Verifizieren:

```bash
grep -c 'settings.mcpServer.status.staleToolList"' Feedivo/Resources/Localizable.xcstrings; git diff --stat Feedivo/Resources/Localizable.xcstrings
```

Erwartet: `1`, und im Diff ausschließlich Insertions.

- [ ] **Schritt 2: Failing Tests schreiben**

An `FeedivoTests/Services/MCPConnectionStatusTextTests.swift` anhängen — **innerhalb** der
bestehenden Suite-Struct, also vor deren schließender Klammer (nicht danach, sonst stehen die
Tests außerhalb der Suite):

```swift
    private func sitzung(toolCount: Int, pid: Int = 1) -> MCPServerSession {
        MCPServerSession(
            pid: pid,
            clientName: "Claude",
            startedAt: Date(timeIntervalSince1970: 0),
            toolCount: toolCount,
            lastHeartbeatAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("Ohne laufende Sitzung gibt es nichts zu melden")
    func ohneSitzungKeineZeile() {
        // Ohne verbundenen Client holt der naechste Start ohnehin die aktuelle Liste — ein
        // "starte ihn neu" waere hier schlicht falscher Rat.
        let zeile = MCPConnectionStatusText.staleToolListLine(
            sessions: [],
            isAccessEnabled: true,
            isWriteAccessEnabled: true
        )

        #expect(zeile == nil)
    }

    @Test("Bei ausgeschaltetem Zugriff wird nicht verglichen")
    func ohneZugriffKeineZeile() {
        // Dann laeuft kein Server, gegen den sich vergleichen liesse.
        let zeile = MCPConnectionStatusText.staleToolListLine(
            sessions: [sitzung(toolCount: 7)],
            isAccessEnabled: false,
            isWriteAccessEnabled: true
        )

        #expect(zeile == nil)
    }

    @Test("Passende Werkzeug-Anzahl ergibt keine Zeile")
    func passendeAnzahlKeineZeile() {
        let zeile = MCPConnectionStatusText.staleToolListLine(
            sessions: [sitzung(toolCount: 7)],
            isAccessEnabled: true,
            isWriteAccessEnabled: false
        )

        #expect(zeile == nil)
    }

    @Test("Abweichende Anzahl nennt beide Zahlen")
    func abweichendeAnzahlNenntBeideZahlen() {
        // Der reale Fall vom 2026-08-15: Schreibzugriff eingeschaltet, Client nicht neu gestartet.
        let zeile = MCPConnectionStatusText.staleToolListLine(
            sessions: [sitzung(toolCount: 7)],
            isAccessEnabled: true,
            isWriteAccessEnabled: true
        )

        #expect(zeile?.contains("7") == true)
        #expect(zeile?.contains("10") == true)
    }

    @Test("Bei mehreren Sitzungen zaehlt die niedrigste abweichende")
    func mehrereSitzungenNiedrigsteAbweichende() {
        // Am 2026-08-16 liefen unbemerkt zwei Serverprozesse gleichzeitig.
        let zeile = MCPConnectionStatusText.staleToolListLine(
            sessions: [sitzung(toolCount: 10, pid: 1), sitzung(toolCount: 7, pid: 2)],
            isAccessEnabled: true,
            isWriteAccessEnabled: true
        )

        #expect(zeile?.contains("7") == true)
    }
```

- [ ] **Schritt 3: Test ausführen, Fehlschlag bestätigen**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPConnectionStatusTextTests 2>&1 | grep -E "error:|Test run with" | head -5
```

Erwartet: Compile-Fehler „type 'MCPConnectionStatusText' has no member 'staleToolListLine'".

- [ ] **Schritt 4: Funktion implementieren**

In `Feedivo/Services/MCPConnectionStatusText.swift` vor der schließenden Klammer des `enum`
einfügen:

```swift
    /// Meldet, wenn ein LAUFENDER Client noch auf einer veralteten Werkzeugliste sitzt.
    ///
    /// Verglichen wird bewusst nur gegen laufende Sitzungen, nie gegen den letzten
    /// Verbindungsvermerk: Ohne verbundenen Client holt der nächste Start ohnehin die aktuelle
    /// Liste, ein „starte ihn neu" wäre dann falscher Rat. Bei ausgeschaltetem Zugriff läuft gar
    /// kein Server, gegen den zu vergleichen wäre.
    ///
    /// Laufen mehrere Sitzungen, zählt die niedrigste abweichende Anzahl — sie gehört zum
    /// Prozess, dem am meisten fehlt.
    static func staleToolListLine(
        sessions: [MCPServerSession],
        isAccessEnabled: Bool,
        isWriteAccessEnabled: Bool
    ) -> String? {
        guard isAccessEnabled, !sessions.isEmpty else { return nil }

        let erwartet = MCPToolInventory.expectedToolCount(isWriteAccessEnabled: isWriteAccessEnabled)
        guard let niedrigste = sessions.map(\.toolCount).filter({ $0 != erwartet }).min() else {
            return nil
        }

        return String(
            format: String(localized: "settings.mcpServer.status.staleToolList"),
            niedrigste,
            erwartet
        )
    }
```

- [ ] **Schritt 5: Tests grün**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPConnectionStatusTextTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | head -4
```

Erwartet: PASS, Anzahl = bisherige Tests der Suite + 5.

- [ ] **Schritt 6: Zeile in der View anzeigen**

In `Feedivo/Views/Settings/SettingsView.swift`, im Statusbereich von `MCPServerSettingsView.body`,
steht der Block

```swift
                        } else {
                            ForEach(zeilen, id: \.self) { zeile in
                                connectionStatusLine(text: zeile, isConnected: true)
                            }
                        }
                    }
                }
```

Ersetzen durch:

```swift
                        } else {
                            ForEach(zeilen, id: \.self) { zeile in
                                connectionStatusLine(text: zeile, isConnected: true)
                            }
                        }

                        if let hinweis = MCPConnectionStatusText.staleToolListLine(
                            sessions: activeSessions,
                            isAccessEnabled: isEnabled,
                            isWriteAccessEnabled: isWriteAccessEnabled
                        ) {
                            Text(verbatim: hinweis)
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                    }
                }
```

- [ ] **Schritt 7: Build prüfen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | grep -E "error:|BUILD" | tail -3
```

Meldet der Compiler „unable to type-check this expression in reasonable time", den Statusbereich in
eine eigene private `@ViewBuilder`-Property `statusSection` auslagern und im `body` nur diese
aufrufen — dasselbe Vorgehen wie beim bereits ausgelagerten `setupSection`.

- [ ] **Schritt 8: Committen**

```bash
git add Feedivo/Services/MCPConnectionStatusText.swift FeedivoTests/Services/MCPConnectionStatusTextTests.swift Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat(settings): Hinweis auf veraltete Werkzeugliste im Statusbereich"
```

---

### Task 3: Neustart-Satz und Aufklappbereich beim Zugriff

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`MCPServerSettingsView`)

**Interfaces:**
- Consumes: nichts aus früheren Tasks
- Produces: nichts für spätere Tasks

- [ ] **Schritt 1: L10n-Konstanten anlegen**

In `Feedivo/Resources/L10n.swift` nach `settingsMCPServerStepRun` einfügen:

```swift
    static let settingsMCPServerRestartHint = LocalizedStringKey("settings.mcpServer.restartHint")
    static let settingsMCPServerPermissionsDisclosure = LocalizedStringKey("settings.mcpServer.permissionsDisclosure")
    static let settingsMCPServerPermissionsAlways = LocalizedStringKey("settings.mcpServer.permissions.always")
    static let settingsMCPServerPermissionsWithWrite = LocalizedStringKey("settings.mcpServer.permissions.withWrite")
    static let settingsMCPServerPermissionsNever = LocalizedStringKey("settings.mcpServer.permissions.never")
    static let settingsMCPServerPermissionsRevoke = LocalizedStringKey("settings.mcpServer.permissions.revoke")
```

- [ ] **Schritt 2: Katalogeinträge anlegen**

Sechs neue Schlüssel per Text-Einfügung am Anker `  "strings" : {`, alle vier Sprachen.

Deutsch:

| Schlüssel | Wert |
|---|---|
| `settings.mcpServer.restartHint` | `Wirkt erst, wenn du den KI-Client danach neu startest.` |
| `settings.mcpServer.permissionsDisclosure` | `Was die KI genau darf` |
| `settings.mcpServer.permissions.always` | `Immer: Feeds, Ordner, Tags und Artikel lesen — samt Gelesen- und Stern-Status. Suchen und Intelligente Ordner abrufen.` |
| `settings.mcpServer.permissions.withWrite` | `Mit Schreibzugriff zusätzlich: Gelesen, Stern und Versteckt setzen. Bestehende Tags zuweisen und entfernen.` |
| `settings.mcpServer.permissions.never` | `Auch mit Schreibzugriff unmöglich: Feeds abonnieren oder löschen, Ordner, Regeln und Intelligente Ordner ändern, Tags anlegen oder löschen, Artikeltexte ändern, Artikel löschen.` |
| `settings.mcpServer.permissions.revoke` | `Rückgängig: Schalter ausschalten und den KI-Client neu starten.` |

Englisch:

| Schlüssel | Wert |
|---|---|
| `settings.mcpServer.restartHint` | `Takes effect only after you restart the AI client.` |
| `settings.mcpServer.permissionsDisclosure` | `What the AI is allowed to do` |
| `settings.mcpServer.permissions.always` | `Always: read feeds, folders, tags and articles — including read and star status. Search and retrieve smart folders.` |
| `settings.mcpServer.permissions.withWrite` | `With write access additionally: set read, star and hidden. Assign and remove existing tags.` |
| `settings.mcpServer.permissions.never` | `Impossible even with write access: subscribing to or deleting feeds, changing folders, rules and smart folders, creating or deleting tags, editing article text, deleting articles.` |
| `settings.mcpServer.permissions.revoke` | `To revoke: turn the switch off and restart the AI client.` |

Französisch:

| Schlüssel | Wert |
|---|---|
| `settings.mcpServer.restartHint` | `Prend effet seulement après le redémarrage du client IA.` |
| `settings.mcpServer.permissionsDisclosure` | `Ce que l'IA est autorisée à faire` |
| `settings.mcpServer.permissions.always` | `Toujours : lire les flux, dossiers, tags et articles — y compris les statuts lu et favori. Rechercher et consulter les dossiers intelligents.` |
| `settings.mcpServer.permissions.withWrite` | `Avec l'accès en écriture, en plus : définir lu, favori et masqué. Attribuer et retirer des tags existants.` |
| `settings.mcpServer.permissions.never` | `Impossible même avec l'accès en écriture : s'abonner à des flux ou les supprimer, modifier dossiers, règles et dossiers intelligents, créer ou supprimer des tags, modifier le texte des articles, supprimer des articles.` |
| `settings.mcpServer.permissions.revoke` | `Pour révoquer : désactiver l'interrupteur et redémarrer le client IA.` |

Italienisch:

| Schlüssel | Wert |
|---|---|
| `settings.mcpServer.restartHint` | `Ha effetto solo dopo aver riavviato il client IA.` |
| `settings.mcpServer.permissionsDisclosure` | `Cosa può fare l'IA` |
| `settings.mcpServer.permissions.always` | `Sempre: leggere feed, cartelle, tag e articoli — inclusi gli stati letto e preferito. Cercare e consultare le cartelle intelligenti.` |
| `settings.mcpServer.permissions.withWrite` | `Con l'accesso in scrittura, in più: impostare letto, preferito e nascosto. Assegnare e rimuovere tag esistenti.` |
| `settings.mcpServer.permissions.never` | `Impossibile anche con l'accesso in scrittura: abbonarsi a feed o eliminarli, modificare cartelle, regole e cartelle intelligenti, creare o eliminare tag, modificare il testo degli articoli, eliminare articoli.` |
| `settings.mcpServer.permissions.revoke` | `Per revocare: disattiva l'interruttore e riavvia il client IA.` |

- [ ] **Schritt 3: Bestehende Schreibzugriff-Beschreibung präzisieren**

Der Schlüssel `settings.mcpServer.writeAccessToggleDescription` existiert bereits; nur die vier
`value`-Zeilen ersetzen, die Struktur unangetastet lassen:

| Sprache | neuer Wert |
|---|---|
| de | `Erlaubt einer verbundenen KI, Gelesen-, Stern- und Versteckt-Status zu ändern und bestehende Tags zuzuweisen oder zu entfernen. Neue Tags anlegen kann sie nicht. Erfordert vorher aktivierten KI-Zugriff.` |
| en | `Lets a connected AI change read, star and hidden status and assign or remove existing tags. It cannot create new tags. Requires AI access to be enabled first.` |
| fr | `Permet à une IA connectée de modifier les statuts lu, favori et masqué, et d'attribuer ou retirer des tags existants. Elle ne peut pas créer de tags. Nécessite l'accès IA activé au préalable.` |
| it | `Consente a un'IA connessa di modificare gli stati letto, preferito e nascosto e di assegnare o rimuovere tag esistenti. Non può creare nuovi tag. Richiede l'accesso IA già attivato.` |

Verifizieren:

```bash
for k in restartHint permissionsDisclosure permissions.always permissions.withWrite permissions.never permissions.revoke; do echo -n "$k: "; grep -c "settings.mcpServer.$k\"" Feedivo/Resources/Localizable.xcstrings; done; git diff --stat Feedivo/Resources/Localizable.xcstrings
```

Erwartet: jeweils `1`; im Diff überwiegend Insertions plus die geänderte Beschreibung (vier
Insertions und vier Deletions).

- [ ] **Schritt 4: View umbauen**

In `MCPServerSettingsView.body` steht:

```swift
                GeneralSettingsHelp(L10n.settingsMCPServerToggleDescription)

                Toggle(isOn: isWriteAccessEnabledBinding) {
```

Ersetzen durch:

```swift
                GeneralSettingsHelp(L10n.settingsMCPServerToggleDescription)
                GeneralSettingsHelp(L10n.settingsMCPServerRestartHint)

                Toggle(isOn: isWriteAccessEnabledBinding) {
```

Und weiter unten:

```swift
                GeneralSettingsHelp(L10n.settingsMCPServerWriteAccessToggleDescription)
                    .padding(.leading, 20)
```

Ersetzen durch:

```swift
                GeneralSettingsHelp(L10n.settingsMCPServerWriteAccessToggleDescription)
                    .padding(.leading, 20)
                GeneralSettingsHelp(L10n.settingsMCPServerRestartHint)
                    .padding(.leading, 20)

                permissionsSection
```

- [ ] **Schritt 5: Aufklappbereich als eigene Property ergänzen**

Neben `setupSection` in `MCPServerSettingsView` einfügen:

```swift
    /// Was die KI mit und ohne Schreibzugriff tatsächlich darf.
    ///
    /// Die Liste des Unmöglichen folgt den drei registrierten Schreib-Werkzeugen
    /// (`update_article_status`, `assign_tag`, `remove_tag`) — kommt dort eines dazu, muss dieser
    /// Text mitwachsen, sonst sichert er etwas zu, das nicht mehr stimmt.
    @ViewBuilder
    private var permissionsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.settingsMCPServerPermissionsAlways)
                Text(L10n.settingsMCPServerPermissionsWithWrite)
                Text(L10n.settingsMCPServerPermissionsNever)
                Text(L10n.settingsMCPServerPermissionsRevoke)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Text(L10n.settingsMCPServerPermissionsDisclosure)
                .font(.system(size: 11))
        }
    }
```

- [ ] **Schritt 6: Build prüfen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | grep -E "error:|BUILD" | tail -3
```

- [ ] **Schritt 7: Committen**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat(settings): Neustart-Hinweis und Aufklappbereich zu den Berechtigungen"
```

---

### Task 4: Aufklappbereich bei der Einrichtung

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`setupSection`)

**Interfaces:**
- Consumes: nichts aus früheren Tasks
- Produces: nichts für spätere Tasks

- [ ] **Schritt 1: L10n-Konstanten anlegen**

In `Feedivo/Resources/L10n.swift` nach den in Task 3 ergänzten Konstanten einfügen:

```swift
    static let settingsMCPServerTroubleshootDisclosure = LocalizedStringKey("settings.mcpServer.troubleshootDisclosure")
    static let settingsMCPServerTroubleshootMissingFile = LocalizedStringKey("settings.mcpServer.troubleshoot.missingFile")
    static let settingsMCPServerTroubleshootExistingEntries = LocalizedStringKey("settings.mcpServer.troubleshoot.existingEntries")
    static let settingsMCPServerTroubleshootBackup = LocalizedStringKey("settings.mcpServer.troubleshoot.backup")
    static let settingsMCPServerTroubleshootNoAutoEntry = LocalizedStringKey("settings.mcpServer.troubleshoot.noAutoEntry")
```

- [ ] **Schritt 2: Katalogeinträge anlegen**

Fünf neue Schlüssel per Text-Einfügung am Anker `  "strings" : {`, alle vier Sprachen.

Deutsch:

| Schlüssel | Wert |
|---|---|
| `settings.mcpServer.troubleshootDisclosure` | `Wenn etwas nicht passt` |
| `settings.mcpServer.troubleshoot.missingFile` | `Datei gibt es noch nicht: Der Knopf Automatisch eintragen… legt sie an. Beim Kopieren legst du sie selbst an, mit dem Schnipsel als vollständigem Inhalt.` |
| `settings.mcpServer.troubleshoot.existingEntries` | `Datei enthält schon Einträge: Nur den inneren feedivo-Block in das vorhandene mcpServers einsortieren — die Datei nicht ersetzen.` |
| `settings.mcpServer.troubleshoot.backup` | `Vor jedem automatischen Eintrag legt Feedivo eine Sicherungskopie neben der Datei an (Endung .feedivo-backup).` |
| `settings.mcpServer.troubleshoot.noAutoEntry` | `Kein Eintragen-Knopf bei VS Code, Zed und Claude Code: Die ersten beiden erlauben Kommentare in ihren Dateien, die ein automatischer Eintrag löschen würde. Claude Code hat keine Konfigurationsdatei, sondern einen Terminal-Befehl.` |

Englisch:

| Schlüssel | Wert |
|---|---|
| `settings.mcpServer.troubleshootDisclosure` | `If something doesn't fit` |
| `settings.mcpServer.troubleshoot.missingFile` | `File doesn't exist yet: the Enter automatically… button creates it. When copying, create it yourself with the snippet as the complete content.` |
| `settings.mcpServer.troubleshoot.existingEntries` | `File already has entries: insert only the inner feedivo block into the existing mcpServers — do not replace the file.` |
| `settings.mcpServer.troubleshoot.backup` | `Before each automatic entry, Feedivo places a backup next to the file (suffix .feedivo-backup).` |
| `settings.mcpServer.troubleshoot.noAutoEntry` | `No entry button for VS Code, Zed and Claude Code: the first two allow comments in their files, which an automatic entry would delete. Claude Code has no configuration file, only a terminal command.` |

Französisch:

| Schlüssel | Wert |
|---|---|
| `settings.mcpServer.troubleshootDisclosure` | `Si quelque chose ne va pas` |
| `settings.mcpServer.troubleshoot.missingFile` | `Le fichier n'existe pas encore : le bouton Saisir automatiquement… le crée. En copiant, créez-le vous-même avec l'extrait comme contenu complet.` |
| `settings.mcpServer.troubleshoot.existingEntries` | `Le fichier contient déjà des entrées : insérez uniquement le bloc feedivo dans le mcpServers existant — ne remplacez pas le fichier.` |
| `settings.mcpServer.troubleshoot.backup` | `Avant chaque saisie automatique, Feedivo place une copie de sauvegarde à côté du fichier (extension .feedivo-backup).` |
| `settings.mcpServer.troubleshoot.noAutoEntry` | `Pas de bouton de saisie pour VS Code, Zed et Claude Code : les deux premiers autorisent les commentaires dans leurs fichiers, qu'une saisie automatique supprimerait. Claude Code n'a pas de fichier de configuration, mais une commande de terminal.` |

Italienisch:

| Schlüssel | Wert |
|---|---|
| `settings.mcpServer.troubleshootDisclosure` | `Se qualcosa non torna` |
| `settings.mcpServer.troubleshoot.missingFile` | `Il file non esiste ancora: il pulsante Inserisci automaticamente… lo crea. Copiando, crealo tu stesso con il frammento come contenuto completo.` |
| `settings.mcpServer.troubleshoot.existingEntries` | `Il file contiene già voci: inserisci solo il blocco feedivo nel mcpServers esistente — non sostituire il file.` |
| `settings.mcpServer.troubleshoot.backup` | `Prima di ogni inserimento automatico, Feedivo crea una copia di backup accanto al file (estensione .feedivo-backup).` |
| `settings.mcpServer.troubleshoot.noAutoEntry` | `Nessun pulsante di inserimento per VS Code, Zed e Claude Code: i primi due consentono commenti nei loro file, che un inserimento automatico eliminerebbe. Claude Code non ha un file di configurazione, ma un comando da terminale.` |

Verifizieren:

```bash
for k in troubleshootDisclosure troubleshoot.missingFile troubleshoot.existingEntries troubleshoot.backup troubleshoot.noAutoEntry; do echo -n "$k: "; grep -c "settings.mcpServer.$k\"" Feedivo/Resources/Localizable.xcstrings; done; git diff --stat Feedivo/Resources/Localizable.xcstrings
```

Erwartet: jeweils `1`, im Diff ausschließlich Insertions.

- [ ] **Schritt 3: Aufklappbereich in `setupSection` ergänzen**

In `Feedivo/Views/Settings/SettingsView.swift` endet `setupSection` mit:

```swift
            if let enterResultMessage {
                Text(verbatim: enterResultMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
```

Ersetzen durch:

```swift
            if let enterResultMessage {
                Text(verbatim: enterResultMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.settingsMCPServerTroubleshootMissingFile)
                    Text(L10n.settingsMCPServerTroubleshootExistingEntries)
                    Text(L10n.settingsMCPServerTroubleshootBackup)
                    Text(L10n.settingsMCPServerTroubleshootNoAutoEntry)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } label: {
                Text(L10n.settingsMCPServerTroubleshootDisclosure)
                    .font(.system(size: 11))
            }
        }
    }
```

- [ ] **Schritt 4: Build prüfen**

```bash
xcodebuild build -scheme Feedivo -configuration Debug 2>&1 | grep -E "error:|BUILD" | tail -3
```

- [ ] **Schritt 5: Committen**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat(settings): Aufklappbereich mit Hilfe zur Einrichtung"
```

---

### Task 5: Abschluss

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Schritt 1: Regressionslauf**

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeedivoTests/MCPToolInventoryTests -only-testing:FeedivoTests/MCPConnectionStatusTextTests -only-testing:FeedivoTests/MCPClientDetectorTests -only-testing:FeedivoTests/MCPClientConfigSnippetTests -only-testing:FeedivoTests/MCPConfigMergerTests -only-testing:FeedivoTests/MCPConfigWriterTests -only-testing:FeedivoTests/MCPClientNameResolverTests -only-testing:FeedivoTests/MCPServerSessionStoreTests 2>&1 | grep -E "Test run with|recorded an issue" | head -3
```

Erwartet: alle grün.

- [ ] **Schritt 2: Release-Builds**

```bash
xcodebuild build -scheme Feedivo -configuration Release 2>&1 | tail -2 && xcodebuild build -scheme FeedivoMCPServer -configuration Release 2>&1 | tail -2
```

- [ ] **Schritt 3: Eintrag unter „Aktuell in Arbeit" in `CLAUDE.md`**

Inhalt: dass beide Schalter dauerhaft den Neustart-Hinweis tragen und warum dauerhaft statt
zustandsabhängig (beim ersten Einrichten hätte ein zustandsabhängiger Hinweis noch nicht
ausgelöst); dass zwei Aufklappbereiche die ausführlichen Erklärungen tragen; dass der
Statusabgleich **nur gegen laufende Sitzungen** läuft und warum (ohne verbundenen Client holt der
nächste Start die aktuelle Liste ohnehin, ein „starte ihn neu" wäre falscher Rat) — ebenso, dass
bei ausgeschaltetem Zugriff gar nicht verglichen wird und bei mehreren Sitzungen die niedrigste
abweichende Anzahl zählt; dass `MCPToolInventory` die erwartete Anzahl hält, die Serverliste in
`main.swift` aber die Wahrheit bleibt und eine Abweichung nur eine stderr-Warnung auslöst, weil ein
nicht startender Server der größere Schaden wäre; dass genau diese Übereinstimmung **nicht**
automatisiert prüfbar ist (`FeedivoMCPServerTests` läuft strukturell nie); und dass die Liste des
mit Schreibzugriff Unmöglichen den drei registrierten Schreib-Werkzeugen folgt und mitwachsen muss,
wenn dort eines dazukommt.

Ausstehende manuelle Verifikation:

1. Unter beiden Schaltern steht dauerhaft der Neustart-Satz.
2. Beide Aufklappbereiche öffnen und schließen; die Inhalte stimmen.
3. Bei laufendem, verbundenem Client den Schreibzugriff einschalten und den Client **nicht** neu
   starten → der Statusbereich meldet die abweichende Werkzeug-Anzahl (7 von 10), orange.
4. Client neu starten → die Hinweiszeile verschwindet.
5. Client beenden → die Hinweiszeile erscheint nicht erneut, obwohl der letzte Vermerk noch die
   alte Anzahl trägt.

- [ ] **Schritt 4: Committen**

```bash
git add CLAUDE.md
git commit -m "docs: Erklaertexte im KI-Zugriff-Tab dokumentiert"
```

- [ ] **Schritt 5: Push-Entscheidung vorlegen**

Laut Projektkonvention **nie ohne ausdrückliche Bestätigung** pushen. Dem Nutzer die Commit-Anzahl
und die fünf offenen Verifikationspunkte melden.

---

## Self-Review

**Spec-Abdeckung:** Dauerhafter Neustart-Satz an beiden Schaltern → Task 3, Schritt 4 ✔; präzisere
Schreibzugriff-Beschreibung („bestehende Tags", „kann keine neuen anlegen") → Task 3, Schritt 3 ✔;
Aufklappbereich „Was die KI genau darf" mit allen vier Zeilen → Task 3, Schritte 2 und 5 ✔;
Aufklappbereich „Wenn etwas nicht passt" mit allen vier Punkten → Task 4 ✔; Statusabgleich nur
gegen laufende Sitzungen, nicht bei ausgeschaltetem Zugriff, niedrigste abweichende Anzahl bei
mehreren Sitzungen → Task 2, Schritte 2 und 4 ✔; `MCPToolInventory` als geteilte Quelle samt
Target-Membership → Task 1, Schritte 3 und 4 ✔; stderr-Warnung bei Drift, ohne den Start zu
verhindern → Task 1, Schritt 5 ✔; kein Task prüft die Existenz einer fremden Datei ✔; kein Task
startet einen fremden Prozess ✔; kein Task fügt Werkzeuge oder Schalter hinzu ✔.

**Placeholder-Scan:** Keine „TBD"/„später"-Verweise; alle Codeblöcke vollständig; alle UI-Texte im
Wortlaut in allen vier Sprachen; für das vorhersehbare Problem (Typprüfungs-Timeout im großen
`body`) steht die konkrete Ausweichlösung in Task 2, Schritt 7.

**Typ-Konsistenz:** `MCPToolInventory.expectedToolCount(isWriteAccessEnabled:)` (Task 1) wird in
Task 2, Schritt 4 mit genau dieser Signatur aufgerufen. `MCPConnectionStatusText.staleToolListLine(
sessions:isAccessEnabled:isWriteAccessEnabled:)` (Task 2, Schritt 4) wird in Task 2, Schritt 6 mit
denselben drei Argumentnamen verwendet. `MCPServerSession` wird im Testhelfer mit allen fünf
tatsächlich vorhandenen Feldern konstruiert (`pid`, `clientName`, `startedAt`, `toolCount`,
`lastHeartbeatAt`). Die in Task 3 und 4 angelegten `L10n`-Konstanten tragen dieselben Namen, unter
denen die Views sie lesen.

**Bekannte Einschränkung:** Dass `MCPToolInventory` zur tatsächlichen Serverliste passt, lässt sich
in diesem Projekt nicht automatisiert prüfen — `FeedivoMCPServerTests` läuft strukturell nie, und
kein `xcodebuild`-Aufruf kompiliert auch nur eine Datei dieses Testziels. Abgesichert ist es durch
die stderr-Warnung beim Serverstart, Kommentare an beiden Stellen und den Vermerk in CLAUDE.md.
