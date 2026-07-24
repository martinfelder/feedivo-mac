# iCloud Sync Phase 2a — Backfill bestehender Einträge Design

## Ziel

iCloud Sync Phase 1 (Tags) und Phase 2a (Feeds/Ordner/Regeln+Bedingungen/benutzerdefinierte
Intelligente Ordner+Bedingungen) syncen bisher ausschließlich **neue Mutationen**, die
NACH der Aktivierung von Sync über eine `*Store`-Methode laufen. Bereits vor der Aktivierung
bestehende Zeilen — oder Zeilen, die bearbeitet wurden, während der Sync-Schalter aus war —
werden nie automatisch nach CloudKit hochgeladen; sie hängen dauerhaft in der Luft, bis der
Nutzer sie zufällig noch einmal anfasst. Diese Spec ergänzt einen Backfill-Mechanismus, der
das behebt.

## Kontext

`CloudSyncSettings.swift` enthält aktuell keinerlei Backfill-Logik. `SettingsView.swift:1122`
ruft beim Umlegen des Schalters nur `cloudSyncEngine?.start()` auf.
`CloudSyncEngine.start()` (siehe `Feedivo/Services/CloudSync/CloudSyncEngine.swift`) prüft den
iCloud-Kontostatus, baut die `CKSyncEngine`-Konfiguration, legt einmalig die `"FeedivoZone"` an
und ruft danach `Self.notifyPendingChangesAvailable(database: database)` auf — das sendet nur,
was **aktuell** in `cloud_sync_pending_changes` steht. Es gibt keinen Schritt, der alle
existierenden Zeilen aus `tags`/`feeds`/`feed_folders`/`rules`/`rule_conditions`/
`smart_folders`/`smart_folder_conditions` einmalig einreiht.

## Produktentscheidungen

- **Trigger:** Backfill läuft bei **jedem** `CloudSyncEngine.start()`-Aufruf (kein neues
  `hasBackfilled`-Flag wie beim Spotlight-Muster). Deckt zuverlässig alle Fälle ab:
  Erst-Aktivierung, Aus/An-Zyklen mit Bearbeitungen dazwischen, Abstürze zwischen Edit und
  Sync-Start. `CKSyncEngine` behandelt ein erneutes `.save` für eine unveränderte, bereits
  synchronisierte Zeile harmlos (Server-Record bleibt inhaltlich identisch,
  `.ifServerRecordUnchanged` greift ohne echten Konflikt).
- **Scope:** Nur das **erneute Einreihen bestehender, aktuell existierender Zeilen** als
  `.save`. Löschungen, die passiert sind, während Sync ausgeschaltet war, werden **NICHT**
  rückwirkend an CloudKit gemeldet — das Backfill kennt nur den aktuellen lokalen Stand, keine
  Historie vergangener Löschungen. Explizit als offene, separate Lücke dokumentiert (passt eher
  zu Phase 3/4 „Härtung" als in diese Ergänzung).
- **Ausschlussregeln bleiben erhalten:** `isDefault`-Intelligente-Ordner (und ihre Bedingungen)
  werden auch im Backfill nie eingereiht — dieselbe Regel wie bei laufenden Mutationen.

## Architektur

Neue Protokollanforderung auf `CloudSyncRecordMapping`:

```swift
static func allLocalIDs(database: FeedivoDatabase) throws -> [String]
```

Jeder der 7 konformen Typen implementiert sie:
- `CloudSyncTagMapping`/`CloudSyncFeedMapping`/`CloudSyncFeedFolderMapping`/
  `CloudSyncRuleMapping`/`CloudSyncRuleConditionMapping`: einfaches
  `SELECT id FROM <table>`.
- `CloudSyncSmartFolderMapping`: `SELECT id FROM smart_folders WHERE isDefault = 0`.
- `CloudSyncSmartFolderConditionMapping`: `SELECT sfc.id FROM smart_folder_conditions sfc JOIN
  smart_folders sf ON sf.id = sfc.smartFolderID WHERE sf.isDefault = 0` (Bedingungen erben den
  Default-Status ihres Elternordners, da sie selbst kein `isDefault`-Feld tragen).

`CloudSyncEngine.start()` bekommt einen neuen privaten Schritt
`backfillAllExistingRecords(database:)`, aufgerufen NACH dem Zonen-Anlegen und VOR
`Self.notifyPendingChangesAvailable(database: database)`: iteriert über `Self.registry.values`,
holt pro Mapping `allLocalIDs(database:)`, enqueued jede ID via
`CloudSyncPendingChangeStore.enqueue(recordType:recordName:changeType: .save)`. Fehler beim
Enumerieren einer einzelnen Tabelle werden geloggt (`AppLogger.dataAccess.error`), brechen aber
nicht die übrigen Tabellen ab (analog zum bestehenden Fehlerbehandlungs-Stil in dieser Datei).

## Tests

- Reine `allLocalIDs`-Tests pro Mapping-Typ (inkl. der beiden Ausschluss-Fälle für
  SmartFolder/SmartFolderCondition).
- Ein Test, der beweist: nach `start()` (bzw. dem neuen internen Backfill-Schritt) landen
  vorher bereits existierende, nie zuvor angefasste Zeilen als `.save` in
  `cloud_sync_pending_changes`.
- Ein Test, der beweist: eine `isDefault`-Intelligente-Ordner-Zeile landet NICHT in der Queue.

## Live-Verifikation

Wie bei Phase 1/2a: Push-Richtung über das CloudKit-Dashboard (bestehende, nie zuvor
gesyncte Feeds/Regeln/Ordner erscheinen nach Aktivieren von Sync im Dashboard). Bleibt bis
zur nächsten Live-Testrunde ausstehend.
