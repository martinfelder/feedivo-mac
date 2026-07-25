# iCloud Sync zurücksetzen — Design-Spec

**Datum:** 2026-07-25
**Status:** Zur Review

## Problem

iCloud Sync (Phase 1 + 2a, siehe CLAUDE.md) hat aktuell keine Möglichkeit, den Sync-Zustand
gezielt zurückzusetzen. Bei Problemen (hängende `stateSerialization`, veraltete
Konflikt-Zwischenstände, dauerhaft nicht sinkendes "Ausstehend (N)") bleibt dem Nutzer nur ein
manuelles Toggle-Aus/An, das den lokalen `CKSyncEngine`-Zustand NICHT löscht (`state.
serialization` bleibt in `UserDefaults` erhalten, siehe `CloudSyncEngine.stop()`).

## Ziel

Zwei selbstbedienbare Reset-Optionen direkt in den Sync-Einstellungen, jeweils mit klarer
Erklärung der Konsequenzen im Bestätigungsdialog:

1. **Soft Reset** — nur lokaler Sync-Zustand, CloudKit-Daten bleiben unangetastet
2. **Hard Reset** — zusätzlich die komplette CloudKit-Zone löschen und aus dem lokalen Stand neu
   aufbauen

## Architektur

Zwei neue Methoden direkt auf `CloudSyncEngine` (`Feedivo/Services/CloudSync/CloudSyncEngine.swift`),
da sie mit den privaten `UserDefaults`-Keys der Engine (`stateSerializationKey`,
`hasCreatedZoneKey`) arbeiten müssen — kein separater Service-Typ nötig.

### `resetLocalState(database:)` — synchron, Soft Reset

1. `stop()` — laufende Engine anhalten
2. `UserDefaults.standard.removeObject(forKey:)` für `cloudSync.stateSerialization` und
   `cloudSync.hasCreatedZone`
3. `CloudSyncPendingChangeStore.deleteAll()` (neue Methode: `DELETE FROM
   cloud_sync_pending_changes`)
4. `OrphanedArticleStatusUpdateStore.deleteAll()` (neue Methode: `DELETE FROM
   orphaned_article_status_updates`, analog zur bestehenden `deleteOlderThan(_:)`)
5. `CloudSyncActivityStatus.reset()` (neue Methode: löscht `lastRunDate`/`status`/
   `lastErrorMessage`-Keys)
6. Falls `CloudSyncSettings.isEnabled()`: `start()` erneut aufrufen — löst automatisch
   `backfillAllExistingRecords` aus (läuft bei jedem `start()`, kein einmaliges Flag), reiht
   dadurch alle lokalen Zeilen aller 8 registrierten Tabellen erneut als `.save` ein. Da
   `hasCreatedZoneKey` gelöscht wurde, wird zusätzlich erneut `saveZone` ausgelöst (harmlos,
   falls die Zone serverseitig noch existiert).

Ergebnis: Feedivo verhält sich sync-seitig wie direkt nach Erstaktivierung, pusht aber den
kompletten aktuellen lokalen Stand erneut hoch. Die CloudKit-Zone und ihre Records bleiben
unverändert bestehen — dieser Reset behebt rein app-seitig hängende Zustände (z. B. den
`knownServerRecordsByID`-Zwischenspeicher, veraltete State-Serialization), ändert aber nichts an
bereits kaputten/verwaisten Server-Records.

### `resetCloudZoneAndLocalState(database:) async throws` — Hard Reset

1. `let wasRunning = syncEngine != nil`, dann `stop()`
2. Löscht die Zone via `CKContainer(identifier: CloudSyncSettings.cloudKitContainerIdentifier)
   .privateCloudDatabase.deleteRecordZone(withID: CloudSyncTagMapping.zoneID())` — eigener,
   von der (gestoppten) `syncEngine`-Instanz unabhängiger Container-Zugriff
3. Fehlerbehandlung:
   - `CKError.zoneNotFound` wird geschluckt (Zone war schon weg, kein Nutzer-Fehler)
   - jeder andere Fehler wird weitergeworfen; bei `wasRunning == true` wird die Engine vorher
     wieder gestartet (ursprünglicher Zustand bleibt erhalten), lokaler Zustand bleibt
     unangetastet — Nutzer sieht eine Fehlermeldung und kann erneut versuchen
4. Bei Erfolg: ruft `resetLocalState(database:)` auf. Die Engine erzeugt beim nächsten `start()`
   die Zone frisch (`saveZone`) und pusht den kompletten lokalen Stand als Erstbefüllung hinein.

**Wichtige Konsequenz (im UI-Warntext zu nennen):** Dies betrifft alle Geräte des Nutzers
gemeinsam. Jedes andere Gerät hat danach einen `stateSerialization`-Zustand gegenüber einer nicht
mehr existierenden Zone und muss sich beim nächsten eigenen Sync-Versuch eigenständig neu
einrichten (aktuell nur durch denselben Reset auf jenem Gerät selbst lösbar) — eine bekannte
Grenze, die im Dialogtext transparent gemacht wird, aber für dieses Feature nicht weiter
automatisiert wird (Multi-Geräte-Koordination ist außerhalb des Scopes).

## UI (Settings → Sync)

Neuer `SettingsBlock` "Sync zurücksetzen" in `SyncSettingsView`, unterhalb des bestehenden
`CloudSyncActivityStatusBlock`:

- **Soft-Reset-Button** ("Lokalen Sync-Zustand zurücksetzen") → normaler
  `.confirmationDialog`/Alert mit Erklärtext ("Setzt den Sync-Zustand auf diesem Gerät zurück und
  lädt alle lokalen Daten erneut zu iCloud hoch. Die iCloud-Daten selbst bleiben unverändert.") +
  Bestätigen/Abbrechen.
- **Hard-Reset-Button** ("iCloud-Daten komplett zurücksetzen", visuell als destruktiv markiert)
  → eigenes Sheet mit:
  - Ausführlichem Warntext (inkl. Multi-Geräte-Hinweis aus dem Abschnitt oben)
  - Textfeld, das exakt `ZURÜCKSETZEN` erwarten muss — Bestätigen-Button bleibt inaktiv, bis der
    Text exakt übereinstimmt
  - Bestätigen-Button (destruktiv gefärbt) + Abbrechen

Beide Buttons sind deaktiviert, während bereits ein Reset läuft (`@State private var
isResetting: Bool`, Spinner analog zum bestehenden OPML-Import-Button-Muster). Nach Abschluss:
Erfolgs-/Fehler-Rückmeldung inline im Block. Scheitert der Hard Reset, bleibt der Dialog offen
mit sichtbarer Fehlermeldung statt sich kommentarlos zu schließen.

Der Soft-Reset-Bestätigungsdialog verlangt **keine** Tipp-Bestätigung (normales
Bestätigen/Abbrechen, Analogie: Feed löschen) — nur der Hard Reset verlangt das Eintippen von
`ZURÜCKSETZEN`, da er irreversibel ist und alle Geräte betrifft.

## Fehlerbehandlung

- Soft Reset: rein lokale Operationen (UserDefaults + SQLite-DELETEs), praktisch nicht
  fehlschlagend — trotzdem wie überall im Projekt über `AppLogger.dataAccess` geloggt statt
  stiller `try?`.
- Hard Reset: einziger Fehlerpfad ist `deleteRecordZone`. Siehe Fehlerbehandlung oben.

## Tests

Neue Unit-Tests:
- `CloudSyncPendingChangeStoreTests`: `deleteAll()` leert die Tabelle vollständig
- `OrphanedArticleStatusUpdateStoreTests` (oder passende bestehende Suite): `deleteAll()` leert
  die Tabelle vollständig
- `CloudSyncActivityStatusTests`: `reset()` löscht alle drei Keys, `lastRunAt`/
  `lastRunSucceeded`/`lastErrorMessage` liefern danach wieder `nil`
- `CloudSyncEngineTests` (oder neue Suite): `resetLocalState(database:)` verifiziert — beide
  UserDefaults-Keys weg, `cloud_sync_pending_changes` und `orphaned_article_status_updates` leer,
  bei aktiviertem Sync wird nach dem Aufruf erneut ein vollständiger Backfill eingereiht

`resetCloudZoneAndLocalState` selbst ist nicht sinnvoll automatisiert testbar (echter
CloudKit-Netzwerkaufruf) — bleibt wie der übrige Live-CloudKit-Verkehr auf manuelle
Verifikation angewiesen.

## Manuelle Live-Verifikationscheckliste (für den Plan)

1. Soft Reset bei aktivem Sync auslösen — sichtbarer Re-Push aller Daten im CloudKit-Dashboard
   ("Ausstehend" steigt kurz an und sinkt dann wieder auf 0)
2. Hard-Reset-Dialog öffnen, Text falsch/unvollständig eintippen — Bestätigen-Button bleibt
   inaktiv
3. Hard Reset mit exaktem `ZURÜCKSETZEN` bestätigen — Zone im CloudKit-Dashboard verschwindet
   und erscheint kurz danach mit frischen Records wieder
4. Hard Reset bei simuliertem Netzwerkfehler (z. B. Flugmodus) — Engine-Zustand bleibt wie vor
   dem Versuch, Fehlermeldung sichtbar, kein lokaler Datenverlust
