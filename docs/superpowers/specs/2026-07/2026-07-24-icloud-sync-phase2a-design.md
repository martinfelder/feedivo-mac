# iCloud Sync — Phase 2a (Struktur-Daten) Design

## Ziel

Phase 1 (siehe `docs/superpowers/specs/2026-07-24-icloud-sync-phase1-design.md`) hat das
`CKSyncEngine`-Fundament gebaut und ausschließlich die `tags`-Tabelle gesynct — live gegen
echtes CloudKit verifiziert (Anlegen + Löschen). Phase 2a erweitert den Sync auf die
restlichen **Struktur-Daten**: Feeds, Feed-Ordner, Regeln (+ Bedingungen), Intelligente Ordner
(nur benutzerdefinierte, + Bedingungen).

**Artikelstatus ist bewusst NICHT Teil dieser Phase** (eigene Phase 2b): `articles.id` ist eine
rein lokal per Gerät erzeugte `UUID()` (`ArticleStore.swift:416`, `UUID().uuidString` bei
jedem Insert) — auf zwei Geräten hat „derselbe" Artikel unterschiedliche IDs. Ein Sync von
`article_statuses` (Primärschlüssel `articleID`) direkt über diese ID wäre bedeutungslos. Der
tatsächlich stabile Schlüssel für einen Artikel ist `(feedID, sourceID ODER link)`
(`ArticleStore.findExistingArticleID`) — und `feedID` wird erst durch den in dieser Phase
gebauten Feed-Sync geräteübergreifend stabil. Phase 2b (Artikelstatus) braucht deshalb
zusätzlich eine Identitäts-Brücke zwischen der lokalen `articles.id` und einem stabilen,
`(feedID, sourceID/link)`-basierten Schlüssel für die CloudKit-Seite — das ist ein eigener
Brainstorming-Zyklus, kein Anhängsel an diese Phase.

## Kontext

Phase 1 hat folgende Bausteine geliefert, auf denen diese Phase direkt aufbaut:

- `Feedivo/Services/CloudSync/CloudSyncEngine.swift` — `@MainActor`-Wrapper um `CKSyncEngine`,
  aktuell **hart auf Tags verdrahtet** (`applyIncomingRecord`/`applyIncomingDeletion`/
  `handleFailedSave`/`record(forPendingChange:)` kennen ausschließlich die `tags`-Tabelle).
- `Feedivo/Services/CloudSync/CloudSyncTagMapping.swift` — reine Mapping-Funktionen
  `TagRecord ↔ CKRecord`, eigene `"FeedivoZone"`.
- `Feedivo/Stores/CloudSyncPendingChangeStore.swift` — App-eigene, durable Warteschlange
  (`cloud_sync_pending_changes`, Migration v21). `CloudSyncPendingChangeRecord` führt bereits
  ein generisches `recordType`-Feld (aktuell immer `"tag"`) — für Mehrtabellen-Dispatch
  vorbereitet, aber noch ungenutzt.
- `Feedivo/Services/CloudSync/CloudSyncStatus.swift` — `@Observable` Sync-Status für die
  Settings-UI.
- `TagStore`-Mutationen markieren betroffene IDs via `enqueuePendingSync(...)` innerhalb
  derselben `database.write`-Transaktion und rufen anschließend
  `CloudSyncEngine.notifyPendingChangesAvailable(database:)` auf, damit eine laufende Engine
  sofort sendet statt nur beim nächsten `start()`.
- Letzter Migrations-Stand: `v21_create_cloud_sync_pending_changes`
  (`FeedivoDatabaseMigrator.swift`).

## Sync-Umfang pro Tabelle

| Tabelle | Sync? | Details |
|---|---|---|
| `feeds` | ✅ nur Konfigurationsfelder | `url`, `title`, `originalTitle`, `websiteURL`, `faviconURL`, `folderName`, `sortIndex`, `refreshIntervalMinutes`, `isNotificationEnabled`, sowie die 5 Retention-Overrides (`articleRetentionOverridesGlobalSetting`, `articleRetentionIsEnabled`, `articleRetentionDays`, `articleRetentionMinimumArticles`, `articleRetentionIncludesProtectedArticles`). **Bleibt lokal:** `lastRefreshedAt`, `lastETag`, `lastModified`, `lastBodyHash`, `lastHTTPStatusCode` (Refresh-Metadaten, gerätespezifisch, bei jedem Refresh neu ermittelt), `unreadCount` (denormalisiert, hängt an Artikelstatus — Phase 2b) |
| `feed_folders` | ✅ vollständig | wie Tags: `id`, `name`, `sortIndex`, `updatedAt` |
| `rules` | ✅ vollständig | inkl. `assignTagID` — reine String-Referenz auf `tags.id`, löst sich von selbst auf, sobald der referenzierte Tag lokal existiert (kein enforced FK über CloudKit nötig) |
| `rule_conditions` | ✅ vollständig, + neues `updatedAt` (Migration v22) | eigener CKRecord pro Zeile (Entscheidung: separate Records statt eingebettetem JSON-Array im Regel-Record — 1:1 zum bestehenden Tag-Muster) |
| `smart_folders` | ✅ **nur `isDefault == false`** | eingebaute Ordner (`isDefault == true`, identifiziert über `defaultKey`, z. B. „Ungelesen"/„Mit Stern") werden **nie gesynct** — sie werden pro Gerät via `SQLiteSmartFolderStore.restoreDefaultFolders()` mit einer **zufälligen, pro Gerät unterschiedlichen** `UUID()` neu angelegt. Würden sie trotzdem gesynct, entstünden Duplikate in der Sidebar, da beide Geräte für z. B. „Ungelesen" unterschiedliche IDs hätten |
| `smart_folder_conditions` | ✅ nur für nicht-Default-Ordner, + neues `updatedAt` (Migration v22) | analog zu Rule Conditions |

## Architektur

`CloudSyncEngine` wird von einer Tag-spezifischen Klasse zu einer generischen,
Registry-basierten Engine umgebaut:

### Neues Protokoll `CloudSyncRecordMapping`

Kapselt pro Tabelle:
- `recordType: String` (Konstante, z. B. `"Feed"`, `"FeedFolder"`, `"Rule"`, `"RuleCondition"`,
  `"SmartFolder"`, `"SmartFolderCondition"` — `"Tag"` bleibt als bestehender Typ erhalten)
- `recordID(forLocalID:) -> CKRecord.ID` (gleiche Zone `"FeedivoZone"` für alle Typen)
- `makeCKRecord(fromLocalID:database:) -> CKRecord?` — lädt die aktuelle Zeile und mapped sie
  (Pendant zu `record(forPendingChange:)`)
- `applyIncoming(_ record: CKRecord, database:)` — Upsert der eingehenden Zeile
- `applyIncomingDeletion(recordID:database:)` — Löschung der lokalen Zeile
- `localUpdatedAt(forLocalID:database:) -> Date?` — für die Last-Write-Wins-Konfliktauflösung
  in `handleFailedSave`

### `CloudSyncEngine`-Umbau

- Hält eine Registry `[String: any CloudSyncRecordMapping]`, Schlüssel = `recordType`.
- `applyIncomingRecord`/`applyIncomingDeletion`/`handleFailedSave`/`record(forPendingChange:)`
  lesen den `recordType` aus dem jeweiligen `CKRecord`/`CloudSyncPendingChangeRecord` und
  dispatchen an die passende Registry-Instanz, statt (wie bisher) hart `TagStore` anzusprechen.
- Alle Typen bleiben in derselben `"FeedivoZone"` — kein Grund für separate Zonen, `CKSyncEngine`
  unterscheidet Records ohnehin über `recordType` + `recordID`.
- Jede Tabelle bekommt eine eigene, reine Mapping-Datei nach dem bestehenden
  `CloudSyncTagMapping`-Vorbild (`CloudSyncFeedMapping`, `CloudSyncFeedFolderMapping`,
  `CloudSyncRuleMapping`, `CloudSyncRuleConditionMapping`, `CloudSyncSmartFolderMapping`,
  `CloudSyncSmartFolderConditionMapping`).

## Migration

**`v22_add_updated_at_to_rule_and_smart_folder_conditions`:** fügt `updatedAt` (NOT NULL,
Default = Zeitpunkt des Migrationslaufs) zu `rule_conditions` und `smart_folder_conditions`
hinzu. Bestehende Zeilen bekommen den Migrationszeitpunkt als Startwert — unkritisch für die
Last-Write-Wins-Logik, da beim allerersten Sync-Zyklus einer Bedingungszeile ohnehin kein
Konflikt vorliegt (die Zeile existiert noch nicht in CloudKit).

## Datenfluss

### Push (lokal → Cloud)

Wie in Phase 1: die jeweilige `*Store`-Mutation markiert die betroffene ID in
`CloudSyncPendingChangeStore` (mit dem passenden `recordType`) innerhalb derselben
`database.write`-Transaktion und ruft anschließend
`CloudSyncEngine.notifyPendingChangesAvailable(database:)` auf. Zusätzliche Requeue-Stellen,
die über die reine 1:1-Wiederholung des Tag-Musters hinausgehen:

- **`FeedFolderStore.renameFolder(from:to:)`** aktualisiert bereits **alle**
  `feeds.folderName`-Werte des umbenannten Ordners in derselben Transaktion (bestehendes
  Verhalten). Muss zusätzlich **jeden betroffenen Feed** als pending-sync markieren, da
  `folderName` nur auf dem Feed-Record selbst lebt, nicht auf einem eigenen Ordner-Feld — sonst
  bliebe der alte Ordnername auf einem zweiten Gerät stehen.
- **`FeedFolderStore.moveFolder(...)`** markiert wie `TagStore.move()` jeden umsortierten
  Ordner einzeln.
- **Löschen einer Regel** enqueued zusätzlich Löschungen für **alle ihre
  `rule_conditions`-Zeilen** (eigene CKRecords). Analog für benutzerdefinierte Intelligente
  Ordner + ihre Bedingungen.
- **Bearbeiten der Bedingungen** einer Regel/eines Intelligenten Ordners (der Editor ersetzt
  typischerweise die komplette Bedingungsliste) enqueued sowohl neue/geänderte als auch
  entfernte (zu löschende) Bedingungszeilen.

### Pull (Cloud → lokal)

Wie Phase 1: Upsert per Mapping (`applyIncoming`) + `SQLiteDataInvalidation.bumpStatusVersion()`.
Zusätzliche Schutzklausel: ein eingehender `SmartFolder`-Record mit `isDefault == true` oder
gesetztem `defaultKey` wird defensiv verworfen (sollte nie vorkommen, da wir solche Records nie
senden, aber billige Absicherung gegen zukünftige Bugs oder fremde Clients in derselben Zone).

### Konflikte

Identisches Last-Write-Wins wie Phase 1 (`.ifServerRecordUnchanged`-Speicherpolicy), jetzt pro
Tabelle mit ihrem jeweiligen `updatedAt`-Feld gegen `CKRecord.modificationDate` verglichen
(`CloudSyncRecordMapping.localUpdatedAt(forLocalID:database:)`).

## Settings-UI

Keine Änderung nötig. Der bestehende „iCloud Sync Beta"-Toggle synct nach dieser Phase
automatisch mehr Tabellen — kein neuer UI-Text. Der in CLAUDE.md dokumentierte Hinweis „synct
aktuell nur Tags" wird beim Abschluss dieser Phase entsprechend aktualisiert.

## Tests

- Reine Mapping-Funktionstests pro neuem Typ (`TagRecord ↔ CKRecord`-Vorbild), kein echtes
  CloudKit.
- Registry-Dispatch-Test in `CloudSyncEngine` (richtige Mapping-Instanz für jeden
  `recordType`).
- Migrationstest für v22 (neue Spalte, Default-Wert für Bestandszeilen).
- Requeue-Tests: Ordner-Umbenennen markiert alle betroffenen Feeds, Ordner-Verschieben markiert
  jeden Ordner einzeln.
- Kaskaden-Test: Regel-/Intelligenter-Ordner-Löschung enqueued auch alle zugehörigen
  Bedingungszeilen zur Löschung.
- Schutzklausel-Test: eingehender `SmartFolder`-Record mit `isDefault`/`defaultKey` wird
  verworfen.

## Live-Verifikation (analog Phase 1)

Push-Richtung über das CloudKit-Dashboard (Anlegen/Ändern/Löschen je eines Feeds, Ordners,
einer Regel mit Bedingungen, eines benutzerdefinierten Intelligenten Ordners mit Bedingungen).
Pull-Richtung bleibt wie in Phase 1 bis zu einem zweiten Testgerät unverifiziert — offener
Punkt, wird explizit als „nicht live verifiziert" geführt, nicht stillschweigend als erledigt
behandelt.
