# iCloud Sync Phase 2b: Artikelstatus-Sync (Gelesen/Stern) — Design-Spec

**Datum:** 2026-07-25
**Status:** Design abgeschlossen, bereit für Implementierungsplan
**Baut auf:** Phase 1 (`CKSyncEngine`-Fundament, nur Tags), Phase 2a (Feeds/Ordner/Regeln/
benutzerdefinierte Intelligente Ordner) — beide auf `main` implementiert.

---

## 1. Ziel & Scope

Synchronisiert den Gelesen- und Stern-Status von Artikeln (`article_statuses.isRead`,
`article_statuses.isStarred`) über CloudKit zwischen Geräten desselben iCloud-Accounts,
über die bestehende Registry-basierte `CloudSyncEngine`-Architektur (`CloudSyncRecordMapping`-
Protokoll, ein Mapping-Typ pro syncbarer Tabelle, gemeinsame CloudKit-Zone `"FeedivoZone"`,
Last-Write-Wins-Konfliktauflösung).

**Explizit NICHT im Scope dieser Phase:**
- `isArchived` und `isHidden` bleiben rein lokal/gerätespezifisch. `isHidden` wird
  ausschließlich durch die lokale `RuleEngine` (`RuleAction.hideArticle`) gesetzt — verifiziert:
  `RuleAction` kennt keine automatische "als gelesen markieren"/"mit Stern markieren"-Aktion,
  `isRead`/`isStarred` sind also ausschließlich nutzergetrieben (UI-Klick), nie durch Regeln
  oder Feed-Refresh-Automatik gesetzt. Das ist die Grundannahme, auf der der in Abschnitt 3
  beschriebene Sparse-Sync-Ansatz aufbaut.
- Artikel-Inhalte selbst (Titel, Body, Metadaten) werden in keiner Phase synchronisiert —
  Artikel entstehen ausschließlich lokal durch Feed-Refresh auf jedem Gerät unabhängig.
- Feld-Ebene-Konfliktauflösung (gleichzeitiges Lesen auf Gerät A und Stern auf Gerät B)
  bleibt der bereits in der Roadmap vorgesehenen Phase 3 vorbehalten (siehe Abschnitt 6).

## 2. Datenmodell

### Migration `v24_add_article_status_sync_updated_at`

Neue, **nullable** Spalte `article_statuses.statusSyncUpdatedAt` (`Date?`, kein Default,
kein `.notNull()`).

Diese Spalte übernimmt zwei Rollen gleichzeitig:
1. **Backfill-/Sync-Eligibility-Filter:** `NULL` bedeutet „dieser Status wurde vom Nutzer nie
   bewusst verändert" — bleibt komplett außerhalb jeder Sync-Betrachtung (siehe Abschnitt 3).
2. **Last-Write-Wins-Zeitstempel:** dient als `localUpdatedAt` für die bestehende
   Konfliktauflösung in `CloudSyncEngine.handleFailedSave`, analog zu `feeds.configUpdatedAt`
   aus Phase 2a.

**Warum nullable ohne Default statt `.defaults(to: Date())`:** Ein konkretes Default-Datum
würde bei der Migration ALLE Bestandszeilen (auch nie berührte) auf "jetzt" setzen und sie
damit fälschlich als "berührt" markieren — das würde den Sparse-Ansatz aus Abschnitt 3 sofort
unterlaufen. Eine nullable Spalte ohne Default umgeht das vollständig und umgeht nebenbei auch
den bekannten `CURRENT_TIMESTAMP`-Migrationscrash-Gotcha (`NULL` ist immer ein gültiges
Konstanten-Default, unabhängig von der Zeilenzahl der Tabelle).

`ArticleStatusStore.setRead(_:articleID:at:)` und `.setStarred(_:articleID:at:)` setzen
`statusSyncUpdatedAt` ab sofort bei **jedem** Aufruf auf `Date()` — unabhängig vom
resultierenden Bool-Wert. Auch ein Revert (z. B. "wieder auf ungelesen zurücksetzen") zählt
als Berührung, sonst würde dieser Revert nicht zu anderen Geräten propagiert werden.
`setArchived(_:articleID:at:)` und `.setHidden(_:articleID:at:)` fassen die Spalte nicht an.

### Migration `v25_create_orphaned_article_status_updates`

Neue Tabelle `orphaned_article_status_updates`:

```
articleID   TEXT PRIMARY KEY   -- KEIN Fremdschlüssel auf articles.id (genau der Fall, den
                                -- diese Tabelle abfängt)
isRead      BOOLEAN NOT NULL
isStarred   BOOLEAN NOT NULL
readAt      DATETIME
starredAt   DATETIME
receivedAt  DATETIME NOT NULL  -- Zeitpunkt des Empfangs, Grundlage für spätere Bereinigung
```

Siehe Abschnitt 4 für die Verwendung.

## 3. Sparse-Sync-Mechanismus (`CloudSyncArticleStatusMapping`)

Neuer Mapping-Typ, konform zu `CloudSyncRecordMapping`, `recordType = "ArticleStatus"`,
registriert in `CloudSyncEngine`s Registry (8. Eintrag neben Tag/Feed/FeedFolder/Rule/
RuleCondition/SmartFolder/SmartFolderCondition).

Der zentrale Unterschied zu allen bisherigen Mappings: `article_statuses` bekommt bei
**jedem** Artikel-Insert automatisch eine Zeile (`ArticleStore.upsert()`) — bei Testdatensätzen
von bis zu 100.000 Artikeln wäre ein vollständiger 1:1-Sync wie bei Tags/Feeds/Regeln (kleine,
zweistellige bis niedrig-dreistellige Admin-Tabellen) nicht tragbar: `CloudSyncEngine.
backfillAllExistingRecords()` läuft bei **jedem** `start()` (App-Start bei aktiviertem Sync,
oder Toggle ein) und würde bei einem vollen 1:1-Ansatz bei jedem Start zehntausende Zeilen neu
in die Sync-Warteschlange einreihen — Risiko für CloudKit-429-Drosselung (bereits einmal live
beobachtet, siehe Phase-2a-Konfliktfix-Dokumentation) und unnötiger Bandbreiten-/Akku-Verbrauch.

**Lösung — Sparse Sync:** Nur Status-Zeilen, die der Nutzer tatsächlich je bewusst verändert
hat, werden überhaupt betrachtet. Kosten skalieren mit Nutzeraktivität statt mit
Gesamt-Artikelanzahl.

- **`allLocalIDs(database:)`** — `SELECT articleID FROM article_statuses WHERE
  statusSyncUpdatedAt IS NOT NULL`. Einzige Abweichung vom bisherigen "alle Zeilen"-Muster.
- **`makeCKRecord(fromLocalID:existing:database:)`** — liest `isRead`, `isStarred`, `readAt`,
  `starredAt` aus `article_statuses`, schreibt sie als `CKRecordValue`s in den `CKRecord`.
- **`applyIncoming(_:database:)`** — siehe Abschnitt 4 (muss zwischen "Artikel existiert
  lokal" und "Artikel existiert lokal noch nicht" unterscheiden).
- **`applyIncomingDeletion(recordID:database:)`** — `DELETE FROM article_statuses WHERE
  articleID = ?` (No-Op falls nicht vorhanden) **plus** vorsichtshalber `DELETE FROM
  orphaned_article_status_updates WHERE articleID = ?`, falls dort noch ein wartender Eintrag
  für dieselbe ID hängt.
- **`localUpdatedAt(forLocalID:)`** — liefert `statusSyncUpdatedAt`.

**Enqueue bei Mutation:** `ArticleStatusStore.setRead()`/`.setStarred()` bekommen (analog zu
`TagStore.enqueuePendingSync`) einen `enqueuePendingSync`-Aufruf, gated auf
`CloudSyncSettings.isEnabled()` zum Mutationszeitpunkt, plus `CloudSyncEngine.
notifyPendingChangesAvailable(database:)` danach — identisches Muster wie bei allen
bisherigen Mappings.

**Bewusst akzeptierte Grenze — Erst-Aktivierungs-Backfill bei Power-Usern:** "Berührt" kann
bei sehr aktiven Bestandsnutzern Jahre an Lesehistorie umfassen (viele tausend Zeilen). Der
erste Backfill nach Sync-Aktivierung bleibt für diese Nutzer potenziell groß — bewusst keine
zusätzliche zeitliche Eingrenzung in dieser Phase (konsistent mit dem etablierten Projektstil
"erst grob liefern, in einer späteren Phase härten"). Dokumentiert als bekannte Grenze, nicht
als Blocker behandelt.

## 4. Verwaiste eingehende Status (Reconciliation)

Da Artikel-Inhalte nie synchronisiert werden (Abschnitt 1), kann ein eingehender Status für eine
`articleID` ankommen, die lokal noch nicht existiert (z. B. Feed auf diesem Gerät noch nicht
aktualisiert, oder frisch abonniert). `article_statuses.articleID` hat einen aktiven
Fremdschlüssel auf `articles.id` (`PRAGMA foreign_keys = ON` ist global aktiv) — ein direkter
Insert würde in diesem Fall scheitern.

**Gewählter Ansatz:** Verwaiste Status werden zwischengespeichert und beim späteren Eintreffen
des zugehörigen Artikels automatisch nachträglich angewendet (robustere Variante gegenüber
stillem Verwerfen).

- **`CloudSyncArticleStatusMapping.applyIncoming(_:database:)`** prüft zuerst per
  `SELECT EXISTS(...)`, ob `articles.id` existiert.
  - Existiert der Artikel: normales Upsert in `article_statuses` (analog zum bestehenden
    Feed-Mapping-Muster: UPDATE falls vorhanden, sonst — kann bei Artikelstatus praktisch
    nicht vorkommen, da `ensureStatus`/`ArticleStore.upsert()` bei Artikel-Existenz immer
    bereits eine Zeile angelegt hat — der UPDATE-Zweig ist der Regelfall).
  - Existiert er nicht: Upsert (`INSERT OR REPLACE`) in `orphaned_article_status_updates`
    statt in `article_statuses` — überschreibt einen ggf. bereits wartenden älteren
    Orphan-Eintrag für dieselbe ID, nur der neueste eingehende Stand zählt.
- **Neuer Hook in `ArticleStore.upsert()`:** direkt nach dem bestehenden `status.insert(db)`
  für einen neu eingefügten Artikel wird `orphaned_article_status_updates` auf eine passende
  `articleID` geprüft. Existiert ein Eintrag, werden `isRead`/`isStarred`/`readAt`/`starredAt`
  direkt in die frisch eingefügte `article_statuses`-Zeile übernommen (inkl. Setzen von
  `statusSyncUpdatedAt`, da dieser Status ja bereits synchronisiert war) und der Orphan-Eintrag wird
  gelöscht. Läuft in derselben Transaktion wie der Artikel-Insert.
- **Bereinigung nie abgeholter Orphan-Einträge** (z. B. der Nutzer hat den Feed längst
  deabonniert, der Artikel wird nie lokal ankommen): `orphaned_article_status_updates` wird in
  die bestehende `ArticleRetentionCleanupService.runAutomaticCleanup(...)`-Bereinigung mit
  aufgenommen. Einträge mit `receivedAt` älter als die konfigurierte Aufbewahrungsfrist (oder
  ein fester Fallback von 90 Tagen, falls Artikel-Retention global deaktiviert ist) werden
  gelöscht, damit die Tabelle nicht unbegrenzt wächst.

## 5. Löschpropagierung

Drei Stellen, an denen `article_statuses`-Zeilen lokal verschwinden können — an jeder wird
**vor** dem eigentlichen Löschen ein `.delete`-Pending-Change enqueued, aber **nur** für
Zeilen mit `statusSyncUpdatedAt IS NOT NULL` (nie synchronisierte Zeilen brauchen kein Delete-Enqueue,
da nie ein passender `CKRecord` existierte):

1. **`ArticleRetentionCleanupService`** — vor dem bestehenden `DELETE FROM article_statuses
   WHERE articleID IN (...)` werden die betroffenen, tatsächlich synchronisierten IDs vorher enqueued.
   Analog zum bereits an derselben Stelle existierenden `deindexForSpotlight`-Hook-Muster
   (injizierbarer Closure-Parameter mit sinnvollem Default).
2. **`SQLiteFeedArticleListState.deleteArticle`** (Einzel-Löschung aus der Artikelliste) —
   gleiches Muster, ebenfalls direkt neben dem bestehenden Spotlight-Deindex-Hook.
3. **Feed-Löschung (`FeedStore.delete`, aufgerufen aus `SQLiteFeedActionService.deleteFeed`)**
   — bisher rein FK-kaskadierend (`feeds` → `articles` → `article_statuses`, beide `ON DELETE
   CASCADE`), keine App-Code-Beteiligung. Neu: vor dem Löschen des `FeedRecord`s werden alle
   `articleID`s dieses Feeds mit `statusSyncUpdatedAt IS NOT NULL` gelesen und als `.delete`
   enqueued — identisches "kaskadenbewusstes Enqueue vor kaskadierendem DELETE"-Muster wie bei
   der Rule→RuleCondition-Kaskade aus Phase 2a Task 6.

## 6. Konfliktauflösung

Bleibt Record-Ebene Last-Write-Wins, exakt wie bei allen sieben bisherigen Mappings
(`localUpdatedAt` = `statusSyncUpdatedAt`, verglichen im bestehenden `handleFailedSave`-Pfad
der `CloudSyncEngine`). Feld-Ebene-Merge (z. B. "Gelesen von Gerät A UND Stern von Gerät B
nahezu gleichzeitig, beides behalten") ist **nicht** Teil dieser Phase — das ist exakt das,
was die Roadmap bereits als eigene, spätere Phase 3 ("Feld-Ebene-Konfliktauflösung +
Merge-Dialog") vorsieht.

**Bekannte, akzeptierte Konsequenz:** Setzen zwei Geräte nahezu gleichzeitig unterschiedliche
Felder desselben Artikelstatus, gewinnt der zeitlich spätere Datensatz komplett — der frühere
geht unter, auch wenn er ein anderes Feld betraf. Konsistent mit dem bestehenden Verhalten
aller anderen Mappings, keine Sonderbehandlung für Artikelstatus.

## 7. Testkonzept

TDD, wie durchgängig in diesem Projekt:

- `CloudSyncArticleStatusMappingTests` — Roundtrip `makeCKRecord`/`applyIncoming`,
  `allLocalIDs`-Filter (nur berührte Zeilen erscheinen), `localUpdatedAt`,
  `applyIncomingDeletion` (inkl. Orphan-Tabellen-Cleanup).
- `ArticleStatusStoreTests`-Erweiterung — `statusSyncUpdatedAt` wird bei `setRead`/
  `setStarred` gesetzt (auch bei Revert auf `false`), bei `setArchived`/`setHidden`
  unverändert gelassen (bleibt `NULL`, falls vorher nie gesetzt).
- Neue Reconciliation-Tests — eingehender Status für unbekannte `articleID` landet in
  `orphaned_article_status_updates`; nachfolgender `ArticleStore.upsert()` für dieselbe ID
  übernimmt ihn korrekt und löscht den Orphan-Eintrag; ein zweiter eingehender Orphan-Status
  für dieselbe noch unbekannte ID überschreibt den ersten statt zu duplizieren.
- Löschpropagierungs-Tests für alle drei Pfade (Retention, Einzel-Löschung,
  Feed-Löschung-Kaskade) — jeweils: synchronisierte Zeile wird enqueued, unsynchronisierte Zeile nicht.
- `CloudSyncEngineRegistryTests`-Erweiterung — 8. Eintrag für `ArticleStatus`.
- Migrationstests für `v24`/`v25`, jeweils gegen eine Tabelle mit mindestens einer
  vorab eingefügten Bestandszeile (nicht nur gegen eine leere Tabelle), wie im bestehenden
  Migrations-Gotcha zu nicht-konstanten Defaults gefordert — hier zusätzlich wichtig, um zu
  verifizieren, dass Bestandszeilen tatsächlich `NULL` statt eines Zeitstempels erhalten.

## 8. Bekannte, bewusst offene Grenzen

Für spätere CLAUDE.md-Dokumentation nach Abschluss:

- Erst-Aktivierungs-Backfill bei Power-Usern mit langer Lesehistorie kann groß ausfallen
  (Abschnitt 3).
- Feld-Ebene-Konflikte (gleichzeitiges Lesen+Stern-Setzen auf zwei Geräten) werden nicht
  gemerged, sondern per Record-LWW entschieden — Phase 3.
- `orphaned_article_status_updates`-Einträge für dauerhaft nie wieder auftauchende Artikel
  (z. B. abbestellter Feed) werden erst mit der nächsten planmäßigen Bereinigung entfernt,
  nicht sofort.
- Wie bei Phase 1/2a: Push-Richtung wird nur automatisiert getestet, Live-Verifikation gegen
  echtes CloudKit-Dashboard sowie Pull-Richtung (zweites Gerät) stehen wie üblich aus.
- Das bereits aus Phase 2a bekannte, dokumentierte Risiko zu `FeedFolderStore.
  materializeImplicitFolders()` (mögliche Ordner-Duplikate bei Multi-Geräte-Pull) ist von
  dieser Phase unberührt, bleibt aber weiterhin offen.
