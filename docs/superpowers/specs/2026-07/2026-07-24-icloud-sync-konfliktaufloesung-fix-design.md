# iCloud Sync Konfliktauflösung reparieren — Design

## Ziel

Beim Live-Testen der Sync-Status-Übersicht (2026-07-24) wurde per echtem CKSyncEngine-Log
verifiziert, dass praktisch jeder bereits serverseitig existierende Datensatz beim Senden mit
`CKError` Code 14 (`.serverRecordChanged`, "record to insert already exists") scheitert — und
danach **dauerhaft** scheitert, ohne je erfolgreich zu synchronisieren. Diese Spec behebt die
zugrunde liegende, in Phase 1 nie vollständig verdrahtete Konfliktauflösung.

## Kontext

`CloudSyncEngine.handleFailedSave(_:)` (`Feedivo/Services/CloudSync/CloudSyncEngine.swift:355`)
implementiert bereits eine Last-Write-Wins-Entscheidung (neuerer Zeitstempel gewinnt), aber die
"lokal gewinnt"-Seite reiht das Element nur erneut zum Senden ein, ohne die vom Server
zurückgegebenen Systemfelder (Change-Tag) zu übernehmen. Der nächste Sendeversuch läuft über
`record(forPendingChange:)` → `mapping.makeCKRecord(fromLocalID:database:)`, das bei JEDEM
Aufruf ein komplett neues `CKRecord(recordType:recordID:)` baut — für einen bereits auf dem
Server existierenden Datensatz garantiert wieder ein Konflikt, in einer Endlosschleife.

Alle 7 `CloudSyncRecordMapping`-Typen (`CloudSyncTagMapping`, `CloudSyncFeedMapping`,
`CloudSyncFeedFolderMapping`, `CloudSyncRuleMapping`, `CloudSyncRuleConditionMapping`,
`CloudSyncSmartFolderMapping`, `CloudSyncSmartFolderConditionMapping`) haben bereits identisch
einen vorbereiteten, aber nie tatsächlich für Konflikt-Retries genutzten `existing: CKRecord? =
nil`-Parameter auf ihrem internen `makeCKRecord(from:existing:)`-Baustein (Dokumentiert als
genau für diesen Zweck gedacht, siehe Kommentar in `CloudSyncTagMapping.swift:20-24`).

Zusätzlich ruft `handleFailedSave` in KEINEM der beiden Auflösungspfade
`dequeuePendingChange(recordName:)` auf — der lokale "Ausstehend"-Zähler (aus der gerade
gebauten Sync-Status-Übersicht, `CloudSyncPendingChangeStore.pendingCounts()`) bleibt deshalb
für jedes einmal in Konflikt geratene Element für immer stehen, selbst wenn CloudKit den
Konflikt korrekt auflöst (Server gewinnt).

Drittens ruft `handleEvent`s `.sentRecordZoneChanges`-Fall `Self.notifyPendingChangesAvailable`
aktuell einmal PRO fehlgeschlagenem Element auf (innerhalb der Schleife über
`changes.failedRecordSaves`) — bei den live beobachteten 94 gleichzeitigen Konflikten wären das
94 nahezu zeitgleiche, redundante `sendChanges()`-Aufrufe. Das ist eine plausible Mit-Ursache
für die ebenfalls live beobachtete CloudKit-429-Drosselung ("Operation throttled ... Retry
after 7.9 seconds", eskalierend auf 16.3s) in dieser Session.

## Produktentscheidungen

- **Umfang:** Der Fix gilt einheitlich für alle 7 `CloudSyncRecordMapping`-Typen — die
  Struktur ist überall identisch, ein Teilfix würde nur eine neue Inkonsistenz schaffen.
- **Last-Write-Wins bleibt unverändert:** Diese Spec ändert NICHT die bestehende
  Konfliktentscheidung (neuerer Zeitstempel gewinnt) — nur WIE die "lokal gewinnt"-Seite
  danach tatsächlich erfolgreich resendet und WIE die "Server gewinnt"-Seite korrekt aus der
  lokalen Warteschlange verschwindet.
- **Kein Persistieren der Server-Systemfelder:** Ein reiner In-Memory-Cache (kein neues
  DB-Feld/keine Migration) genügt — nach einem App-Neustart mitten in einem offenen Konflikt
  liefert der nächste Sendeversuch ohnehin erneut den aktuellen Server-Stand über einen neuen
  `.serverRecordChanged`-Fehler; kein Datenverlust, nur ein zusätzlicher Roundtrip.
- **Gebündelter Resend-Trigger:** `notifyPendingChangesAvailable` wird pro
  `.sentRecordZoneChanges`-Batch höchstens einmal aufgerufen, nicht mehr pro einzelnem
  fehlgeschlagenem Element.

## Architektur

### 1. Protokolländerung: `existing:`-Parameter durchreichen

`Feedivo/Services/CloudSync/CloudSyncRecordMapping.swift`, geänderte Anforderung:

```swift
static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord?
```

Jeder der 7 Typen ändert seine bestehende Implementierung nur um die Durchreichung, z. B.
`CloudSyncTagMapping.swift`:

```swift
static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
    let tags = try TagStore(database: database).tags()
    guard let tag = tags.first(where: { $0.id == id }) else { return nil }
    return makeCKRecord(from: tag, existing: existing)
}
```

Analog für die übrigen 6 Typen (jeweils ihr eigenes `makeCKRecord(from:existing:)` statt einer
Tag-spezifischen Signatur).

### 2. Kurzzeit-Cache in `CloudSyncEngine`

```swift
/// Kurzlebiger Zwischenspeicher für Server-Records aus aufgelösten Konflikten — wird von
/// `handleFailedSave` beim "lokal gewinnt"-Pfad befüllt und von `record(forPendingChange:)`
/// konsultiert, damit der nächste Sendeversuch die korrekten Server-Systemfelder
/// (Change-Tag) wiederverwendet, statt erneut ein jungfräuliches CKRecord zu bauen (das sonst
/// garantiert wieder mit `.serverRecordChanged` scheitern würde). Rein In-Memory, bewusst
/// nicht persistiert.
private var knownServerRecordsByID: [CKRecord.ID: CKRecord] = [:]
```

`record(forPendingChange:)` (bestehende Methode) konsultiert den Cache zuerst, entfernt den
Eintrag nach Gebrauch:

```swift
private func record(forPendingChange recordID: CKRecord.ID) async -> CKRecord? {
    guard
        let pendingChange = try? pendingChangeStore.pendingChange(recordName: recordID.recordName),
        let mapping = Self.mapping(forRecordType: pendingChange.recordType)
    else {
        return nil
    }
    do {
        let existing = knownServerRecordsByID[recordID]
        let record = try mapping.makeCKRecord(fromLocalID: recordID.recordName, existing: existing, database: database)
        knownServerRecordsByID.removeValue(forKey: recordID)
        return record
    } catch {
        AppLogger.dataAccess.error("iCloud Sync: CKRecord fuer ausstehende Aenderung konnte nicht gebaut werden: \(error.localizedDescription, privacy: .public)")
        return nil
    }
}
```

### 3. `applyIncomingRecord` meldet Erfolg zurück

Bestehende Methode ändert ihre Signatur von `-> Void` auf `-> Bool` (liefert `true`, wenn das
Anwenden tatsächlich gelang), damit der Konfliktpfad nur bei echtem Erfolg dequeued (siehe
unten) — ein DB-Fehler beim Anwenden darf das Element nicht stillschweigend aus der
Warteschlange verschwinden lassen, ohne dass irgendein Stand (Server ODER lokal) tatsächlich
durchgesetzt wurde:

```swift
private func applyIncomingRecord(_ record: CKRecord) async -> Bool {
    guard let mapping = Self.mapping(forRecordType: record.recordType) else { return false }
    do {
        try mapping.applyIncoming(record, database: database)
    } catch {
        AppLogger.dataAccess.error("iCloud Sync: Eingehender \(record.recordType, privacy: .public)-Record konnte nicht gespeichert werden: \(error.localizedDescription, privacy: .public)")
        return false
    }
    SQLiteDataInvalidation.bumpStatusVersion()
    return true
}
```

Der bestehende Aufrufer in `.fetchedRecordZoneChanges` (normale eingehende Änderungen, kein
Konflikt) ignoriert den Rückgabewert weiterhin (`await applyIncomingRecord(modification)`,
ohne Zuweisung) — dort ändert sich nichts am Verhalten.

### 4. `handleFailedSave` liefert jetzt `Bool` (braucht Resend?)

```swift
private func handleFailedSave(_ failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) async -> Bool {
    guard failedSave.error.code == .serverRecordChanged else {
        status.state = .error(failedSave.error.localizedDescription)
        AppLogger.dataAccess.error("iCloud Sync: Record-Save fehlgeschlagen: \(failedSave.error.localizedDescription, privacy: .public)")
        return false
    }

    guard let serverRecord = failedSave.error.serverRecord,
          let mapping = Self.mapping(forRecordType: failedSave.record.recordType)
    else { return false }

    let localUpdatedAt: Date?
    do {
        localUpdatedAt = try mapping.localUpdatedAt(forLocalID: failedSave.record.recordID.recordName, database: database)
    } catch {
        AppLogger.dataAccess.error("iCloud Sync: Lokaler Stand fuer Konfliktaufloesung konnte nicht geladen werden: \(error.localizedDescription, privacy: .public)")
        return false
    }

    let serverIsNewer = (serverRecord.modificationDate ?? .distantPast) > (localUpdatedAt ?? .distantPast)

    if serverIsNewer {
        let applied = await applyIncomingRecord(serverRecord)
        if applied {
            dequeuePendingChange(recordName: failedSave.record.recordID.recordName)
        }
        return false
    } else {
        knownServerRecordsByID[failedSave.record.recordID] = serverRecord
        do {
            try pendingChangeStore.enqueue(recordType: mapping.recordType, recordName: failedSave.record.recordID.recordName, changeType: .save)
            return true
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Erneuter Sync-Versuch nach Konflikt konnte nicht eingeplant werden: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
```

### 5. Gebündelter Resend-Trigger in `handleEvent`

```swift
case .sentRecordZoneChanges(let changes):
    for saved in changes.savedRecords {
        dequeuePendingChange(recordName: saved.recordID.recordName)
    }
    for deletedID in changes.deletedRecordIDs {
        dequeuePendingChange(recordName: deletedID.recordName)
    }
    var needsResend = false
    for failedSave in changes.failedRecordSaves {
        if await handleFailedSave(failedSave) {
            needsResend = true
        }
    }
    if needsResend {
        Self.notifyPendingChangesAvailable(database: database)
    }
    recordSyncActivityOutcome(failedRecordSaves: changes.failedRecordSaves)
```

## Edge Cases

- **Mehrere aufeinanderfolgende Konflikte für dieselbe ID:** Jeder `handleFailedSave`-Aufruf
  überschreibt den Cache-Eintrag mit dem jeweils neuesten `serverRecord` — der nächste
  Sendeversuch nutzt immer den aktuellsten bekannten Stand.
- **Cache-Wachstum:** Der Eintrag wird nach Gebrauch in `record(forPendingChange:)` entfernt,
  unabhängig vom Ausgang des erneuten Versuchs — verhindert unbegrenztes Wachstum über eine
  lange Sync-Session hinweg.
- **Lokal zwischenzeitlich gelöschte ID:** Unverändertes Verhalten — bestehende Nil-Guards
  (`pendingChangeStore.pendingChange`, `mapping.makeCKRecord` liefert `nil` bei unbekannter
  ID) decken das bereits ab.
- **App-Neustart mitten in einem offenen Konflikt:** Cache ist leer nach Neustart — der nächste
  Sendeversuch baut wieder ein jungfräuliches `CKRecord`, bekommt erneut denselben Konflikt mit
  dem aktuellen `serverRecord` zurück, füllt den Cache erneut. Ein zusätzlicher Roundtrip, aber
  kein Datenverlust und keine dauerhafte Blockade.

## Tests

- Für jeden der 7 Mapping-Typen: neuer Test, dass `makeCKRecord(fromLocalID:existing:database:)`
  bei übergebenem `existing`-Record dessen Systemfelder (Objektidentität/`recordID`) erhält und
  trotzdem die aktuellen lokalen Feldwerte einträgt — sowie ein Test, dass `existing: nil`
  weiterhin ein frisches `CKRecord` liefert (bestehendes Verhalten, Regressionsschutz).
- `CloudSyncEngine.handleFailedSave`/`.sentRecordZoneChanges`-Verhalten ist wegen der
  `CKSyncEngine.Event`-Framework-Typen nicht automatisiert testbar (bereits bekannte,
  dokumentierte Grenze aus einem früheren Task dieser Session — kein Mock/keine Konstruktion
  synthetischer `CKSyncEngine.Event`-Werte möglich). Verifikation über volle Kompilierung +
  bestehende CloudSync-Regressionssuite (keine Signatur-Regression) sowie manuelle
  Live-Verifikation.

## Live-Verifikation

Nach Implementierung: mit den aktuell in der lokalen Datenbank hängenden 94 Elementen (bereits
per direkter SQLite-Abfrage verifiziert, Stand dieser Session) erneut synchronisieren — die
zuvor dauerhaft mit `.serverRecordChanged` scheiternden Sendeversuche sollten jetzt entweder
erfolgreich das lokale Feld-Update durchsetzen (falls lokal neuer) oder den Server-Stand
übernehmen und sofort aus der lokalen Warteschlange verschwinden (falls Server neuer) — der
"Ausstehend"-Zähler der Sync-Status-Übersicht sollte danach auf 0 sinken, nicht mehr dauerhaft
hängen bleiben.
