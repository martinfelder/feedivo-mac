# iCloud Sync Status-Übersicht in den Einstellungen — Design

## Ziel

Der Sync-Tab in den Einstellungen zeigt aktuell nur einen einzigen Umschalter — keine Aussage
darüber, ob der letzte iCloud-Sync tatsächlich funktioniert hat oder wann er zuletzt lief. Diese
Spec ergänzt einen Status-Block, der beides beantwortet: eine globale Statuszeile
("Synchron"/"Ausstehend (N)"/"Fehler: …" + Zeitpunkt) plus eine aufklappbare Aufschlüsselung
nach Datenart (Tags/Feeds/Ordner/Regeln/Intelligente Ordner).

## Kontext

`CloudSyncStatus` (`Feedivo/Services/CloudSync/CloudSyncStatus.swift`) ist ein rein
In-Memory-`@Observable`-Objekt mit `State` (`.idle`/`.syncing`/`.accountUnavailable`/
`.error(String)`). `.syncing` wird im gesamten Code nirgends tatsächlich gesetzt (verifiziert
per Grep) — de facto gibt es nur `.idle`/`.accountUnavailable`/`.error(...)`, und der Zustand
geht bei jedem App-Neustart verloren. Es existiert **keine** persistente Historie darüber, wann
zuletzt ein echter Sende-/Abrufversuch stattfand oder ob er erfolgreich war.

`cloud_sync_pending_changes` (`CloudSyncPendingChangeRecord`) trackt bereits jede noch nicht
hochgeladene Änderung mit `recordType` (String-Schlüssel, identisch zu
`CloudSyncRecordMapping.recordType` — siehe `CloudSyncEngine.registry`, 7 Einträge: `Tag`,
`Feed`, `FeedFolder`, `Rule`, `RuleCondition`, `SmartFolder`, `SmartFolderCondition`). Diese
Tabelle liefert live und ohne neue Persistenz, wie viele Änderungen pro Datenart noch
ausstehen.

`SyncSettingsView` (`SettingsView.swift`) rendert den Toggle bereits über `SettingsBlock`/
`SettingsRow` — dasselbe Baukasten-Muster wie der bestehende Feed-Aktualisierungsstatus-Block
und der Bereinigungsstatus-Block (`RefreshSettingsView`/`CleanupSettingsView`).

## Produktentscheidungen

- **Erfolgsdefinition ("hat funktioniert"):** Warteschlange (`cloud_sync_pending_changes`)
  aktuell vollständig leer UND der letzte tatsächliche Sende-/Abrufversuch war fehlerfrei.
  Bewusst strenger als "letzter Versuch war ok" — sagt ehrlich "gerade nichts offen", nicht nur
  "hat mal geklappt".
- **Umfang:** Global (eine kompakte Statuszeile) UND aufklappbare Details pro Datenart. Die
  Details zeigen **nur** den aktuellen Live-Zähler ausstehender Änderungen je Kategorie, keinen
  eigenen Zeitstempel pro Kategorie — das würde zusätzlichen persistenten Zustand ohne klaren
  Mehrwert erfordern (siehe Datenmodell unten).
- **Kategorien-Mapping:** Die 7 rohen `recordType`-Werte werden auf 5 nutzerverständliche
  Kategorien zusammengefasst, da die beiden Bedingungs-Tabellen für den Nutzer keine eigene
  Identität haben:

  | Angezeigte Kategorie | Summiert `recordType`(s) |
  |---|---|
  | Tags | `Tag` |
  | Feeds | `Feed` |
  | Ordner | `FeedFolder` |
  | Regeln | `Rule` + `RuleCondition` |
  | Intelligente Ordner | `SmartFolder` + `SmartFolderCondition` |

- **Platzierung:** Erweiterung des bestehenden Sync-Tabs (kein neues Fenster) — direkt unter dem
  vorhandenen Sync-Toggle, im selben `SettingsBlock`-Stil wie Feed-Aktualisierungsstatus/
  Bereinigungsstatus.
- **Server-Konflikte zählen nicht als Fehler:** Ein `.serverRecordChanged`-Konflikt wird von
  `CloudSyncEngine` bereits automatisch aufgelöst (Last-Write-Wins, siehe `handleFailedSave`) —
  das ist normaler Multi-Geräte-Betrieb, kein Fehlerzustand. Nur echte, nicht automatisch
  aufgelöste Fehlschläge zählen für die Statuszeile als Fehler.

## Architektur

### 1. Neuer persistenter Status: `CloudSyncActivityStatus`

Neue Datei `Feedivo/Services/CloudSync/CloudSyncActivityStatus.swift`, UserDefaults-backed nach
dem Muster des bestehenden `AutomaticCleanupStatus`:

```swift
enum CloudSyncActivityStatus {
    static func lastRunAt() -> Date?
    static func lastRunSucceeded() -> Bool?      // nil = noch nie ein Versuch gelaufen
    static func lastErrorMessage() -> String?    // nur aussagekräftig, wenn lastRunSucceeded == false

    static func recordSuccess(at date: Date)
    static func recordFailure(_ message: String, at date: Date)
}
```

`recordSuccess`/`recordFailure` schreiben jeweils alle drei zugehörigen UserDefaults-Werte in
einem Rutsch (Zeitpunkt, Erfolgsflag, Fehlertext — Fehlertext wird bei `recordSuccess` auf `nil`
zurückgesetzt).

### 2. Wann wird geschrieben?

In `CloudSyncEngine.handleEvent(_:syncEngine:)` (`Feedivo/Services/CloudSync/CloudSyncEngine.swift`),
an den bereits bestehenden Fällen, die einen tatsächlich abgeschlossenen Sync-Versuch markieren:

- **`.sentRecordZoneChanges`:** Nach der bestehenden Verarbeitung (Dequeue erfolgreicher
  Saves/Deletes, `handleFailedSave` für Fehlschläge) wird `CloudSyncActivityStatus` aktualisiert:
  Erfolg, falls kein `failedSave` ein echter (nicht `.serverRecordChanged`) Fehler war; sonst
  Fehler mit der ersten entsprechenden Fehlermeldung.
- **`.fetchedRecordZoneChanges`:** Nach der bestehenden Verarbeitung (`applyIncomingRecord`/
  `applyIncomingDeletion`) wird `CloudSyncActivityStatus.recordSuccess(at:)` aufgerufen — ein
  Abruf hat in dieser Codebasis keinen granularen Fehlerpfad pro Record; scheitert der Abruf
  als Ganzes, kommt das Ereignis gar nicht erst hier an.

Bewusst **nicht** aktualisiert bei: `.stateUpdate` (feuert für interne Buchhaltung zu oft, keine
inhaltliche "Sync ist gelaufen"-Aussage), `start()`/`stop()` selbst (kein Sync-Versuch), und
`.accountChange` (Vorzustand, kein abgeschlossener Versuch).

### 3. Pro-Datenart-Zähler: neue Store-Methode

Auf `CloudSyncPendingChangeStore` (`Feedivo/Stores/CloudSyncPendingChangeStore.swift`):

```swift
static func pendingCounts(_ db: Database) throws -> [String: Int]  // recordType -> Anzahl
```

Reines `SELECT recordType, COUNT(*) AS count FROM cloud_sync_pending_changes GROUP BY
recordType`. Läuft synchron gegen eine typischerweise sehr kleine Tabelle, kein Caching nötig.

Die Zuordnung roher `recordType`-Strings zu den 5 Anzeige-Kategorien (Tabelle oben) lebt als
kleine, reine, isoliert testbare Funktion, z. B. `CloudSyncActivityCategory.swift`:

```swift
enum CloudSyncActivityCategory: CaseIterable {
    case tags, feeds, folders, rules, smartFolders

    var recordTypes: [String] { ... }           // z. B. .rules -> ["Rule", "RuleCondition"]
    var localizedTitle: LocalizedStringKey { ... }

    static func pendingCount(for category: Self, in counts: [String: Int]) -> Int {
        category.recordTypes.reduce(0) { $0 + (counts[$1] ?? 0) }
    }
}
```

### 4. Datenfluss zur UI

`SyncSettingsView` liest bei jedem Erscheinen sowie bei Änderung von
`SQLiteDataInvalidation.statusVersionKey` (bestehender Invalidierungs-Mechanismus — jede
Sync-relevante Mutation läuft durch normale Store-Writes, die diesen Zähler bumpen) einmalig neu
ein:
- `CloudSyncActivityStatus.lastRunAt()` / `.lastRunSucceeded()` / `.lastErrorMessage()`
- `CloudSyncPendingChangeStore.pendingCounts(_:)` über die injizierte `\.feedivoDatabase`

Kein Live-Polling, keine neue Observation-Infrastruktur — folgt demselben Muster wie der
bestehende Bereinigungsstatus-Block.

### 5. UI in `SyncSettingsView`

Neuer Block direkt unter dem Sync-Toggle, `SettingsBlock`/`SettingsRow`-Stil:

**Globale Statuszeile**, drei Zustände (nur wenn Sync aktiviert UND Konto verfügbar):
- **Synchron** (Häkchen, Erfolgsfarbe) — Summe aller `pendingCounts` ist `0` UND
  `lastRunSucceeded() == true`.
- **Ausstehend (N)** (neutral) — Summe aller `pendingCounts` ist `> 0`, kein Fehler.
- **Fehler: {message}** (`theme.destructiveText`) — `lastRunSucceeded() == false`.

Darunter: "Zuletzt synchronisiert: {Datum, Uhrzeit}" (`date.formatted(date:time:)`, absoluter
Zeitpunkt, kein "vor X Minuten" — Konvention aus dem bestehenden Feed-Status-Block) bzw. "Noch
nie synchronisiert", falls `lastRunAt() == nil`.

Ist der Sync-Toggle aus oder der Kontostatus `.accountUnavailable`: der Block bleibt sichtbar,
aber gedämpft (reduzierte Opazität) mit Ersatztext ("Sync ist deaktiviert" /
"iCloud-Konto nicht verfügbar") statt der drei Zustände oben — der zuletzt bekannte
`CloudSyncActivityStatus`-Stand bleibt dabei unverändert im Hintergrund erhalten.

**Aufklappbare Details** (`DisclosureGroup`, "Details anzeigen"/"Details ausblenden"): 5 Zeilen
(eine je `CloudSyncActivityCategory`), jeweils Name + "Synchron" oder "N ausstehend" — ohne
eigenen Zeitstempel.

Neue L10n-Keys (Statuszeilen-Texte, Kategorie-Namen, Ersatztexte) werden wie gewohnt manuell in
`Localizable.xcstrings` ergänzt (Auto-Stub-Mechanismus greift bei indirekten `L10n`-Keys nicht,
siehe bestehender Gotcha in `CLAUDE.md`).

## Edge Cases

- **Noch nie gesynct** (`lastRunAt() == nil`): "Noch nie synchronisiert", keine Erfolg/Fehler-
  Badge. Die Detailzeilen zeigen trotzdem live die aktuellen Pending-Counts (können bereits > 0
  sein, z. B. direkt nach Aktivieren + Backfill, bevor der erste echte Sende-Event durch ist).
- **Sync aus → an:** Der alte `CloudSyncActivityStatus`-Stand bleibt unverändert erhalten (kein
  Reset beim Toggle) — wird beim ersten echten Event nach dem nächsten `start()` einfach
  überschrieben.
- **`.accountUnavailable`:** Überschreibt nur die Anzeige (Ersatztext), ändert den persistierten
  `CloudSyncActivityStatus` nicht — das ist ein Vorzustand, kein abgeschlossener Sync-Versuch.
- **Serverkonflikt (`.serverRecordChanged`):** Zählt nicht als Fehler (siehe
  Produktentscheidungen) — sonst würde die Statuszeile bei jeder normalen
  Multi-Geräte-Konfliktauflösung fälschlich rot aufblitzen.
- **Bekannte Limitation — einzelne fehlgeschlagene eingehende Records bei `.fetchedRecordZoneChanges`:**
  `applyIncomingRecord`/`applyIncomingDeletion` (bestehender Code) schlucken Fehler beim
  Übernehmen eines einzelnen eingehenden Records bereits heute nur mit `AppLogger`-Logging, ohne
  sie an den Aufrufer zurückzumelden. Der neue `recordSuccess(at:)`-Aufruf nach
  `.fetchedRecordZoneChanges` markiert den Abruf deshalb auch dann als "erfolgreich", wenn ein
  einzelner Record dabei nicht übernommen werden konnte — konsistent mit dem bestehenden
  Fehlerbehandlungsstil dieser beiden Funktionen, aber bewusst als Grenze dieser Spec
  dokumentiert statt stillschweigend übergangen. Eine echte Pro-Record-Fehlerpropagation wäre
  eine größere, unabhängige Änderung an `applyIncomingRecord`/`applyIncomingDeletion` selbst und
  liegt außerhalb des Scopes dieser Status-Übersicht.

## Tests

- `CloudSyncActivityStatus`: `recordSuccess`/`recordFailure` schreiben und lesen korrekt zurück,
  inklusive Persistenz über eine frische Instanz hinweg (echtes UserDefaults-Verhalten,
  isolierte Suite pro Test wie im Projekt üblich); `recordSuccess` nach vorherigem
  `recordFailure` setzt `lastErrorMessage()` zurück auf `nil`.
- `CloudSyncPendingChangeStore.pendingCounts`: leere Tabelle → leeres Dictionary; mehrere
  `recordType`s mit unterschiedlicher Anzahl → korrekte Gruppierung/Zählung.
- `CloudSyncActivityCategory.pendingCount(for:in:)`: `RuleCondition`-Einträge fließen in
  `.rules` ein, `SmartFolderCondition` in `.smartFolders` — reiner Logiktest ohne DB.
- `CloudSyncEngine`-Integrationstest für die beiden neuen Update-Stellen (`.sentRecordZoneChanges`
  mit/ohne Fehlschlag, `.fetchedRecordZoneChanges`), sofern die bestehende Testinfrastruktur
  `CKSyncEngine`-Events sauber simulieren lässt (bereits bestehendes Muster in den
  Phase-1/2a-Tests prüfen) — andernfalls wird das im Implementierungsplan explizit als "nur
  manuell/live verifizierbar" markiert, analog zu den bereits bekannten Grenzen bei
  `CKSyncEngine` in diesem Projekt.

## Live-Verifikation

Nach Implementierung: Sync aktivieren, einen Feed/Tag/Regel anlegen → Statuszeile zeigt kurz
"Ausstehend (1)", nach erfolgreichem Senden "Synchron" mit aktuellem Zeitpunkt. Details
aufklappen → betroffene Kategorie zeigt während des ausstehenden Zustands den Zähler. Sync
deaktivieren → Block dämpft sich, letzter Stand bleibt sichtbar. Netzwerk trennen (oder
ungültigen Container simulieren) + Änderung vornehmen → Fehlerzustand wird sichtbar und bleibt
über einen App-Neustart hinweg erhalten (Beweis der Persistenz).
