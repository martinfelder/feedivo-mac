# iCloud Sync — Phase 1 (Fundament) Design

## Ziel

Feedivo bekommt eine funktionierende, minimale Ende-zu-Ende-Sync-Pipeline über CloudKit —
beschränkt auf eine einzige, einfache Tabelle (`tags`) als Beweis, dass Mechanismus,
Architektur und Settings-Integration tragen. Das ist Phase 1 eines mehrphasigen Vorhabens:

- **Phase 1 (diese Spec):** CloudKit-Grundgerüst + End-to-End-Sync für `tags` + Settings-Toggle
- **Phase 2:** restliche Tabellen (Feeds, Ordner, Regeln, Intelligente Ordner, Artikelstatus)
- **Phase 3:** Konfliktverhalten verfeinern (Feld-Ebene statt Record-Ebene) + Merge-Dialog bei
  Erst-Aktivierung auf einem Gerät mit bereits vorhandenen lokalen Daten
- **Phase 4:** Härtung, Edge-Cases, breitere Testabdeckung

Phase 2–4 werden als eigene Brainstorming/Plan-Zyklen behandelt, sobald Phase 1 steht.

## Kontext

Der ursprüngliche Branch `codex/icloud-sync-beta` (letzter Commit 2026-07-01, `820a566c`,
Spec siehe `docs/superpowers/specs/2026-07-01-icloud-sync-beta-design.md`) basierte
vollständig auf SwiftData + CloudKit über `ModelConfiguration(cloudKitDatabase:)`. Dieser
Ansatz ist seit der vollständigen SwiftData-Entfernung (ADR-007, 2026-07-07) komplett
hinfällig — GRDB/SQLite hat keinen eingebauten CloudKit-Sync-Mechanismus wie SwiftData ihn
hatte. Der alte Code ist nicht wiederverwendbar; einzelne Produktentscheidungen aus der
damaligen Spec (Sync-Umfang, kein Konfliktdialog in v1) fließen aber in dieses Design ein.
Die alte Spec bleibt als historisches Dokument stehen, wird nicht überschrieben.

Auf `main` ist `CloudSyncSettings.isAvailable` aktuell hart auf `false` gesetzt — reiner
UI-Platzhalter ohne Funktion. Die CloudKit-Entitlements (`iCloud.ch.martin.Feedivo`,
`com.apple.developer.icloud-services: CloudKit`) sind in `Feedivo/Feedivo.entitlements`
bereits vorhanden — ein Überbleibsel des alten Branches, das offenbar beim SwiftData-Rückbau
nicht entfernt wurde. Das spart einen Einrichtungsschritt.

`TagRecord.id` ist bereits ein `String` (UUID-String) — passt direkt als `CKRecord.ID`-
`recordName`, keine zusätzliche ID-Übersetzung nötig.

## Produktentscheidungen (aus dem Brainstorming)

- **Primäres Ziel:** Architektur soll plattformneutral sein, um eine künftige iOS-Version von
  Feedivo anbinden zu können — nicht nur Mac-zu-Mac.
- **Sync-Umfang (Gesamtprojekt):** Struktur + Status (Feeds, Ordner, Tags, Regeln,
  Intelligente Ordner, Artikelstatus). Artikel-Volltexte/Caches/Bilder werden NICHT
  synchronisiert — jedes Gerät lädt Artikelinhalte weiterhin selbst per RSS-Refresh.
- **Konfliktstrategie:** Last-Write-Wins (zeitlich neuere Änderung gewinnt), kein manueller
  Konfliktdialog.
- **Toggle-Verhalten:** Sync-Ein-/Ausschalten wirkt sofort, kein App-Neustart nötig (Unterschied
  zum alten SwiftData-Plan, möglich weil die GRDB-Datenbank unabhängig von CloudKit bereits
  offen ist).
- **Erst-Aktivierung auf zweitem Gerät mit vorhandenen lokalen Daten:** Warnhinweis mit
  Wahlmöglichkeit (lokale Daten behalten + mergen, oder Cloud-Stand übernehmen) — Umsetzung
  dieses Dialogs ist Teil von Phase 3, in Phase 1 mangels zweiter Tabelle/relevanter Datenmenge
  noch nicht spürbar.
- **Testumgebung:** Ein Gerät verfügbar. Push-Richtung wird über das CloudKit-Dashboard im
  Browser verifiziert. Pull-Richtung bleibt bis zur Verfügbarkeit eines zweiten Geräts
  ungetestet — wird explizit als offener Punkt geführt, nicht stillschweigend als erledigt
  behandelt.
- **Apple Developer Account:** vorhanden, Nutzer kann die iCloud/CloudKit-Capability in Xcode
  (Signing & Capabilities) selbst einrichten — das ist ein GUI-Schritt, den Claude Code nicht
  automatisieren kann.

## Architekturentscheidung

**Gewählter Ansatz: `CKSyncEngine`** (Apples Sync-Engine, verfügbar seit macOS 14/iOS 17 —
passt zum bestehenden Minimum-Deployment-Target). Übernimmt Change-Tracking, Batching,
Retry/Backoff und Token-Verwaltung automatisch; die App liefert nur die Mapping-Schicht
(GRDB-Zeile ↔ `CKRecord`) und eine kleine Warteschlange für noch nicht hochgeladene
Änderungen.

**Verworfene Alternativen:**
- *Klassisches CloudKit* (`CKDatabase`-Operations + `CKQuerySubscription` von Hand, der
  Pre-2023-Weg) — deutlich mehr Boilerplate für dasselbe Ergebnis, `CKSyncEngine` nimmt genau
  diese Arbeit ab.
- *Datei-basierter Sync über iCloud Drive/Ubiquity-Container* — schlecht geeignet für
  relationale Mehrtabellen-Daten mit feingranularer Konfliktauflösung, Risiko einer
  korrumpierten SQLite-Datei bei echtem Gleichzeitig-Schreiben zweier Geräte.

`CKSyncEngine` läuft identisch auf macOS und iOS — passt damit am saubersten zum genannten
Hauptziel (spätere iOS-Anbindung).

## Architektur & Komponenten

Neuer Ordner `Feedivo/Services/CloudSync/`:

### `CloudSyncEngine`
`@MainActor`-Klasse, wrappt `CKSyncEngine` gegen die private CloudKit-Datenbank, eigene
Record-Zone `"FeedivoZone"` (keine Default-Zone — Default-Zone unterstützt keine atomaren
Batch-Operationen zuverlässig). Bietet `start()`/`stop()` für das Live-Umschalten ohne
Neustart. Implementiert `CKSyncEngineDelegate`:
- liefert ausstehende lokale Änderungen als `CKRecord`-Batches (`nextRecordZoneChangeBatch`)
- verarbeitet eingehende Events (`handleEvent`): empfangene Änderungen, gesendete Änderungen
  (inkl. Konfliktfälle), Konten-Status-Änderungen

### `CloudSyncTagMapping`
Reine, isoliert testbare Mapping-Funktionen `TagRecord → CKRecord` und
`CKRecord → TagRecord`. Gemappte Felder: `name`, `colorHex`, `sortIndex`. `recordName` =
`TagRecord.id`.

### `CloudSyncPendingChanges`
Neue GRDB-Tabelle (Migration `v21_create_cloud_sync_pending_changes`) hält:
- die ID-Warteschlange „diese Tag-IDs müssen noch hochgeladen werden"
- die von `CKSyncEngine` gelieferte opake State-Serialisierung (`Data`), damit nach einem
  App-Neustart nicht bei null angefangen werden muss

### `CloudSyncStatus`
Kleines `@Observable`, hält Sync-Status (`.idle`, `.syncing`, `.error(String)`,
`.accountUnavailable`) für die Settings-UI — analog zum bestehenden
`recentRefreshStatus`-Muster beim Feed-Refresh.

## Datenfluss

**Raus (lokal → Cloud):** `TagStore`-Mutationen (`save`, `renameTag`, `move`, `updateColor`,
`deleteTag`) markieren zusätzlich die betroffene ID in `CloudSyncPendingChanges` — ein neuer,
expliziter Aufruf an diesen Stellen, analog zum bestehenden `bumpStatusVersion()`-Muster.
`CKSyncEngine` fragt bei Gelegenheit `nextRecordZoneChangeBatch` ab, die App liefert die
gemappten `CKRecord`s.

**Rein (Cloud → lokal):** `CKSyncEngine`-Delegate erhält `.fetchedRecordZoneChanges`-Event,
die App upsertet/löscht die entsprechenden `tags`-Zeilen per GRDB und ruft anschließend
`SQLiteDataInvalidation.bumpStatusVersion()` — nutzt den bestehenden UI-Reload-Mechanismus,
keine neue Beobachtungs-Infrastruktur nötig.

**Konflikte (Phase 1, Record-Ebene):** Speicherpolicy `.ifServerRecordUnchanged`. Bei Konflikt
wird `TagRecord.updatedAt` (lokal) gegen `CKRecord.modificationDate` (Server) verglichen, die
neuere Seite gewinnt — einfache Last-Write-Wins auf Record-Ebene. Feingranulare Feld-Ebene
(z. B. Status-Felder, die im Zweifel den „aktiveren" Zustand behalten) ist Gegenstand von
Phase 3, sobald Artikelstatus synchronisiert wird — für die reine `tags`-Tabelle in Phase 1
gibt es keine solchen Sonderfälle.

## Settings-UI

`CloudSyncSettings.isAvailable` wird von `false` auf `true` umgestellt. Der bestehende
Sync-Tab bekommt einen echten Toggle „iCloud Sync Beta" statt des reinen Platzhaltertexts.
Statuszeile:

- „Lokal gespeichert" — Sync aus
- „iCloud Sync aktiv" — läuft
- „Kein iCloud-Konto angemeldet" — `CKContainer.default().accountStatus()` liefert
  `.noAccount`/`.restricted`; Toggle bleibt aktivierbar, Engine startet aber nicht, Hinweis mit
  Link zu den Systemeinstellungen (Muster wie beim bestehenden
  Benachrichtigungs-Systemeinstellungen-Link)
- „Synchronisierung fehlgeschlagen" + letzter Fehlertext — bei anhaltenden CloudKit-Fehlern
  (Quota, Zonen-Erstellung etc.), geloggt über `AppLogger`, kein Modal-Alert (konsistent mit
  der bestehenden Policy, Fehler nicht-aufdringlich im Status-Bereich zu zeigen statt per
  Alert)

**Bekannte Einschränkung in Phase 1 (bewusst dokumentiert, kein Bug):** Der Toggle heißt
„iCloud Sync Beta", synchronisiert in Phase 1 aber ausschließlich Tags — Feeds/Regeln/
Artikelstatus folgen erst in Phase 2. Für den aktuell einzigen Nutzer unkritisch, wird aber
explizit vermerkt, damit es nicht als Phase-1-Vollständigkeit missverstanden wird.

## Fehlerbehandlung

- Kein iCloud-Konto angemeldet → Sync startet nicht, verständlicher Status-Text, kein Absturz.
- Netzwerkfehler → `CKSyncEngine` übernimmt automatisches Retry/Backoff, die App zeigt nur den
  aktuellen Status.
- CloudKit-Quota/Zonen-Erstellungsfehler → geloggt über `AppLogger` (bestehendes
  `logIfThrows`-Muster), im Status-Bereich reflektiert, kein Modal-Alert.
- Der Toggle selbst darf nie zum Absturz führen, unabhängig vom CloudKit-Kontostatus — analog
  zur bestehenden Anforderung an den Datenbank-Start (`DatabaseLoadState`).

## Tests

- Reine Mapping-Funktionen (`TagRecord ↔ CKRecord`) sind pure Funktionen, direkt unit-testbar
  ohne echtes CloudKit.
- `CloudSyncEngine`-Lifecycle (`start()`/`stop()`, Pending-Changes-Queue-Verwaltung) testbar
  mit einer injizierten, CloudKit-freien Abstraktion — gleiches Prinzip wie beim bestehenden
  `SpotlightIndexWriting`-Protokoll für die Spotlight-Integration. Echtes CloudKit wird in
  Unit-Tests nie berührt.
- **Live-Verifikation (ein Gerät + CloudKit Dashboard):** Push-Richtung wird über das
  CloudKit-Dashboard im Browser bestätigt (Tag lokal anlegen/umbenennen/löschen → Record
  erscheint/verändert sich/verschwindet im Dashboard). Pull-Richtung (Cloud → lokal) bleibt
  zunächst ungetestet, bis ein zweites Gerät verfügbar ist — offener Punkt, wird in der
  Abschlussdokumentation dieser Phase explizit als „nicht live verifiziert" geführt statt
  stillschweigend als erledigt behandelt.

## Manuelle Voraussetzung vor Implementierungsbeginn

In Xcode unter Signing & Capabilities muss die iCloud-Capability mit CloudKit-Service für das
Feedivo-Target aktiviert und der Container `iCloud.ch.martin.Feedivo` im Apple Developer
Portal bestätigt werden. Das ist ein GUI-Schritt, den Claude Code nicht automatisieren kann —
wird als erster Punkt im Implementierungsplan als manueller Vorbereitungsschritt geführt.
