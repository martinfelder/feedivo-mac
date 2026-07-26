# iCloud Sync Phase 3: Feld-Ebene-Konfliktauflösung + Merge-Dialog bei Erst-Aktivierung — Design-Spec

**Datum:** 2026-07-26
**Status:** Design abgeschlossen, bereit für Implementierungsplan
**Baut auf:** Phase 1 (`CKSyncEngine`-Fundament, nur Tags), Phase 2a (Feeds/Ordner/Regeln/
benutzerdefinierte Intelligente Ordner), Phase 2b (Artikelstatus — Gelesen/Stern) — alle drei
auf `main` implementiert, Push-Richtung und Löschpropagierung für alle Tabellen live gegen
CloudKit verifiziert (2026-07-26). Konfliktauflösung ist bisher reines Ganz-Record-
Last-Write-Wins (`CloudSyncEngine.handleFailedSave`).

---

## 1. Ziel & Scope

Phase 3 bündelt zwei Bausteine, die denselben Kernmechanismus teilen, aber an unterschiedlichen
Stellen im Sync-Lebenszyklus greifen:

1. **Laufende Feld-Ebene-Konfliktauflösung** — ersetzt das aktuelle Ganz-Record-LWW für die
   7 „strukturierten" Tabellen (`Tag`, `Feed`, `FeedFolder`, `Rule`, `RuleCondition`,
   `SmartFolder`, `SmartFolderCondition`) durch einen präzisen Mechanismus, der nur die
   tatsächlich lokal geänderten Felder schützt, statt bei einem Konflikt die komplette
   verlierende Seite zu verwerfen. `ArticleStatus` bekommt eine eigene, einfachere Regel
   (Abschnitt 4) und nutzt den generischen Mechanismus nicht.
2. **Merge-Dialog bei Erst-Aktivierung** — ein einmaliger Analyse- und Entscheidungsschritt
   beim Umlegen des iCloud-Sync-Schalters, wenn bereits lokale Daten existieren. Erkennt aktiv
   Namensduplikate zwischen lokalem und Cloud-Stand bei `Tag` und `FeedFolder` und legt sie dem
   Nutzer zur Entscheidung vor — löst direkt das bereits dokumentierte Risiko aus dem
   Phase-2a-Whole-Branch-Review (`FeedFolderStore.materializeImplicitFolders()` kann bei
   Multi-Geräte-Pull doppelte, gleichnamige Ordner erzeugen).

**Explizit NICHT im Scope dieser Phase:**
- Struktur-Konflikte wie „Regel auf Gerät A gelöscht, während ihre Bedingung auf Gerät B
  gerade bearbeitet wird" — hier gewinnt weiterhin einfach die Löschung (bestehende
  Kaskaden-Logik über Fremdschlüssel), kein aktives Erkennen dieser Race.
- Duplikat-Erkennung für `Rule`/`SmartFolder` bei Erst-Aktivierung — zwei gleichnamige Regeln
  bedeuten nicht zwangsläufig „dasselbe", anders als bei den rein namensbasierten, flachen
  Entitäten `Tag`/`FeedFolder`.
- Mehr-als-zwei-Geräte-Konflikte als eigener Sonderfall — werden wie ein normaler
  Zwei-Seiten-Konflikt behandelt (der jeweils zeitlich zweite Konflikt reiht sich hinter dem
  ersten ein), keine spezielle 3-Wege-Logik.
- Pull-Richtung bleibt weiterhin app-weit ungetestet mangels Zweitgerät — Phase 3 baut die
  Mechanik dafür, verifiziert sie aber nur so weit, wie das mit einem einzigen Gerät (siehe
  Abschnitt 8) möglich ist.

## 2. Kernmechanismus: Touched-Fields-Tracking

**Grundproblem:** `CKSyncEngine` liefert bei einem Konflikt (`.serverRecordChanged`) nur den
kompletten Server-Record, keinen Feld-Diff. Um zu wissen, *welche* Felder eine lokale Mutation
tatsächlich geändert hat, muss die App das selbst mitführen.

**Schema-Änderung (Migration `v27_add_changed_fields_to_pending_changes`):** Neue, optionale
Spalte `cloud_sync_pending_changes.changedFields: String?` — eine JSON-codierte Liste von
Feldnamen (z. B. `["name"]` oder `["isNotificationEnabled","folderName"]`). `NULL`-Default,
kein Backfill: bestehende Pending-Changes ohne dieses Feld (und alle `.delete`-Einträge, für
die Feld-Ebene ohnehin keinen Sinn ergibt) fallen weiterhin auf das bisherige Ganz-Record-LWW
zurück — rein additive Erweiterung, kein Verhaltensbruch für Bestandscode.

**Wer befüllt die Spalte:** Jede Store-Mutationsmethode, die aktuell einen Pending-Change
enqueued (z. B. `TagStore.rename`, `FeedFolderStore.renameFolder`,
`SQLiteFeedActionService.updateNotificationEnabled`, `SQLiteRuleStore.save`), übergibt ab jetzt
zusätzlich die Namen der von ihr geänderten Spalten:
- Methoden, die ohnehin nur ein Feld ändern (z. B. `updateNotificationEnabled`): feste
  Konstante.
- Methoden mit mehreren Feldern (z. B. ein voller `Rule`-Speichervorgang aus dem
  Regel-Editor): Vergleich alt/neu vor dem Schreiben, nur tatsächlich veränderte Feldnamen
  landen in der Liste.

**Konfliktauflösung in `CloudSyncEngine.handleFailedSave`:** Erweitert den bestehenden Ablauf
(Zeile ~473–510 in `CloudSyncEngine.swift`) um einen neuen Zweig, der nur greift, wenn die
zugehörige Pending-Change-Zeile ein nicht-leeres `changedFields` hat:

1. Server-Record als Basis nehmen.
2. Für jedes Feld in `changedFields`: lokalen Wert mit Server-Wert vergleichen.
   - Gleich → kein echter Konflikt auf diesem Feld, nichts zu tun.
   - Unterschiedlich UND Feld ist laut Tabellen-Policy (Abschnitt 3) „auto" → lokalen Wert auf
     den Server-Record überlagern.
   - Unterschiedlich UND Feld ist laut Tabellen-Policy „fragen" → als offenen Konflikt in
     `pending_sync_conflicts` (Abschnitt 5) vermerken, NICHT automatisch auflösen.
3. Für alle Felder NICHT in `changedFields`: immer Server-Wert übernehmen (kein lokales
   Änderungsinteresse an diesem Feld).
4. Gab es mindestens ein „fragen"-Feld: der Datensatz bleibt lokal auf seinem aktuellen
   Vor-Konflikt-Stand stehen (keine Überschreibung durch den Server, aber auch kein erneuter
   automatischer Upload-Versuch), bis der Nutzer entscheidet. Gab es nur „auto"-Felder: der
   gemergte Record wird sofort über den normalen `save`-Pfad gespeichert, exakt wie beim
   bisherigen Last-Write-Wins.

Pending-Changes ohne `changedFields` (alte Warteschlangen-Einträge, Lösch-Operationen)
durchlaufen unverändert die bestehende Ganz-Record-LWW-Logik.

## 3. Pro-Tabelle-Policies

Grundregel über alle 7 strukturierten Tabellen: **freie Text-/Namensfelder** (das, was ein
Nutzer bewusst formuliert hat) lösen bei einem echten Feld-Konflikt den Dialog aus. **Alles
andere** (Booleans, Zahlen, Sortierindizes, Enum-artige Werte) wird bei einem Konflikt
automatisch per bestehender Ganz-Record-LWW-Logik aufgelöst — kein Dialog. Das hält die Anzahl
der Dialoge klein und auf die Fälle beschränkt, wo tatsächlich Inhalt verloren gehen könnte.

| Tabelle | Felder | „Fragen"-Felder | „Auto"-Felder |
|---|---|---|---|
| `Tag` | name, colorHex, sortIndex | `name` | colorHex, sortIndex |
| `Feed` | title, folderName, sortIndex, refreshIntervalMinutes, isNotificationEnabled, 4× Retention-Felder | `title` | alles andere; die 4 Retention-Felder als **eine Gruppe** behandelt (bei Konflikt: ganze Gruppe auto, nicht einzeln) |
| `FeedFolder` | name, sortIndex | `name` | sortIndex |
| `Rule` | name, isActive, matchMode/groupIndex, actionType, actionTagID | `name` | alles andere |
| `RuleCondition` | field, operator, value, groupIndex, sortOrder | `value` | field, operator, groupIndex, sortOrder |
| `SmartFolder` | name, appearance (icon/farbe), matchMode | `name` | appearance, matchMode |
| `SmartFolderCondition` | field, operator, value, groupIndex, sortOrder | `value` | field, operator, groupIndex, sortOrder |

Die konkrete Zuordnung Feld → „fragen"/„auto" lebt als statische Property je
`CloudSyncRecordMapping`-Konformer (analog zu `recordType`), damit `handleFailedSave` generisch
bleibt und nicht pro Tabelle verzweigen muss.

## 4. Sonderfall `ArticleStatus`

`ArticleStatus` braucht das generische Touched-Fields-Tracking aus Abschnitt 2 nicht — die
Tabelle hat mit `readAt`/`starredAt` bereits echte Pro-Feld-Zeitstempel (aus Phase 2b). Neue,
eigenständige Regel direkt in `handleFailedSave`, nur für diese Tabelle: `isRead` und
`isStarred` werden **unabhängig voneinander** per eigenem Zeitstempel aufgelöst — wer `readAt`
bzw. `starredAt` neuer hat, gewinnt für genau dieses Feld. Kein Dialog: ein falsch stehender
Gelesen-/Stern-Status hat geringe Tragweite und ist mit einem Klick korrigiert, im Gegensatz zu
einem verlorenen, bewusst formulierten Namen.

## 5. UI für laufende Konflikte

**Neue Tabelle `pending_sync_conflicts`** (Migration `v28_create_pending_sync_conflicts`,
rein lokal, wird selbst nicht synchronisiert): `id` (Primärschlüssel), `recordType`,
`recordName` (lokale ID bzw. `syncStableID`), `fieldName`, `localValue`, `serverValue`,
`detectedAt`. Eine Zeile pro offenem „Fragen"-Feld-Konflikt aus Abschnitt 2, Schritt 2.

**Sichtbarkeit:** Im bestehenden Sync-Tab der Einstellungen, direkt unter der schon
vorhandenen Sync-Status-Zeile („Synchron"/„Ausstehend (N)"/„Fehler: …"), ein neuer Zustand:
„Konflikte: N" (oranges Icon), erscheint nur wenn `pending_sync_conflicts` nicht leer ist.
Klick öffnet ein neues Sheet `SyncConflictResolutionView`.

**Das Sheet:** Liste aller offenen Konflikte, gruppiert nach betroffenem Datensatz (z. B.
„Regel *Intune Artikel*" als Gruppen-Header, darunter die konkret betroffenen Felder). Pro
Feld: zwei Buttons nebeneinander — „Dieses Gerät" (lokaler Wert, zeigt den aktuellen Text) und
„Anderes Gerät" (Server-Wert, mit Zeitstempel „zuletzt geändert am …"). Nutzer klickt eine
Seite pro Feld; nach der Auswahl wird der gemergte Record sofort gespeichert und die Zeile aus
`pending_sync_conflicts` entfernt.

**Grund für „Dieses/Anderes Gerät" statt „Beide behalten":** Hier kollidiert eine einzelne
Eigenschaft eines bereits existierenden Datensatzes — anders als bei Duplikaten in Abschnitt 6,
wo zwei ganze, unabhängig entstandene Objekte kollidieren. Ein Textfeld lässt sich nicht
sinnvoll in „beide Varianten gleichzeitig" auflösen.

## 6. Erst-Aktivierungs-Merge-Dialog + Duplikat-Erkennung

**Auslöser:** Der Nutzer legt den bestehenden „iCloud Sync"-Schalter in den Einstellungen um.
Bisher startet `CloudSyncEngine.start()` sofort den normalen Backfill
(`backfillAllExistingRecords`). Neu: **vor** diesem Backfill ein zusätzlicher, einmaliger
Analyse-Schritt.

**Neue Komponente `CloudSyncFirstActivationAnalyzer`:**
1. Fragt per `CKQuery` alle bereits in `FeedivoZone` vorhandenen `Tag`- und `FeedFolder`-
   Records ab (leere Ergebnisliste, falls die Zone noch komplett unbefüllt ist — dann entfällt
   der ganze Dialog automatisch, siehe unten).
2. Vergleicht Namen (case-insensitive, gleiche Normalisierung wie der bestehende
   Duplikat-Check in `FeedFolderStore.renameFolder`) gegen die lokal vorhandenen
   `tags`/`feed_folders`-Zeilen.
3. Baut eine Liste von Kollisionen: `{ typ: .tag/.feedFolder, name, localID, cloudRecordID }`.

**Der Dialog (`CloudSyncFirstActivationView`, neues Sheet, erscheint direkt beim Umlegen des
Schalters):**
- Keine Kollisionen gefunden → Sheet zeigt nur eine kurze Zusammenfassung („5 lokale Tags,
  3 lokale Ordner werden mit der Cloud abgeglichen") mit einem „Fortfahren"-Button, kein
  Entscheidungsbedarf.
- Kollisionen gefunden → pro Kollision eine Zeile mit Namen und zwei Optionen:
  - **„Zusammenführen"** (empfohlen, vorausgewählt): die lokale Zeile wird auf die
    Cloud-`recordID` umgebogen (referenzierende Fremdschlüssel wie `feeds.folderName` bleiben
    über den Namen ohnehin stabil, betrifft nur die interne `feed_folders.id`/`tags.id`), die
    alte lokale Zeile geht in der zusammengeführten auf.
  - **„Beide behalten"**: lokale Zeile bekommt automatisch einen disambiguierenden
    Namenszusatz (z. B. „Technik (2)"), bleibt als eigenständige Zeile bestehen und wird
    regulär als neuer Cloud-Record hochgeladen.
- Erst nach Bestätigung des Dialogs (auch im „keine Kollisionen"-Fall) startet der eigentliche
  Backfill/Erstabgleich.

**Wichtig:** Dieser Analyse-Schritt läuft nur einmal, beim Umschalten von aus→an. Ein späteres
Aus- und wieder Einschalten (oder ein Soft-/Hard-Reset über die bestehende Reset-UI) triggert
ihn erneut, da dann wieder ein „frischer" lokal-vs-Cloud-Abgleich ansteht.

## 7. Datenfluss-Beispiele

**Szenario A — laufender Konflikt (Rule-Umbenennung auf zwei Geräten):** Gerät A benennt Regel
„Alt" → „Neu-A" um → Pending-Change mit `changedFields: ["name"]`. Gerät B benennt dieselbe
Regel zeitgleich → „Neu-B" um, synct zuerst erfolgreich. Gerät A versucht zu senden →
`.serverRecordChanged`. `handleFailedSave`: `name` ist ein „Fragen"-Feld, lokal („Neu-A") ≠
Server („Neu-B") → Eintrag in `pending_sync_conflicts`, Rule bleibt lokal auf „Neu-A" stehen,
kein automatischer Push/Pull mehr für diesen Datensatz bis zur Nutzerentscheidung. Sync-Status
zeigt „Konflikte: 1". Nutzer öffnet das Sheet, wählt „Neu-B" (anderes Gerät) → Record wird mit
„Neu-B" gespeichert, aus der Konfliktliste entfernt, normaler Sync läuft weiter.

**Szenario B — Erst-Aktivierung mit Duplikat:** Gerät A hat bereits längere Zeit Sync aktiv,
u. a. Tag „Intune" existiert in der Cloud. Gerät B (bisher ohne Sync) hat unabhängig ebenfalls
einen Tag „Intune" angelegt. Nutzer aktiviert Sync auf Gerät B →
`CloudSyncFirstActivationAnalyzer` findet die Namensgleichheit → Dialog zeigt „Intune" mit
„Zusammenführen" vorausgewählt → Nutzer bestätigt → Gerät B's lokale `tags`-Zeile wird auf die
Cloud-`recordID` umgebogen, kein doppelter Tag „Intune" in der Sidebar.

## 8. Fehlerbehandlung & bewusste Grenzen

- Schreibfehler beim Speichern eines aufgelösten Konflikts (z. B. DB-Fehler) → Konflikt bleibt
  in `pending_sync_conflicts` stehen, Fehler wird geloggt (bestehendes
  `AppLogger.dataAccess`-Muster), Nutzer kann die Entscheidung erneut treffen.
- `CKQuery` beim Erst-Aktivierungs-Check schlägt fehl (z. B. kein Netz) → Dialog überspringt
  die Duplikat-Erkennung, zeigt nur die einfache Zusammenfassung, Backfill läuft trotzdem
  normal weiter (Duplikat-Erkennung ist ein Komfort-Feature, kein Sync-Gate).
- Siehe Abschnitt 1 für die vollständige Liste der bewusst nicht abgedeckten Fälle
  (Struktur-Konflikte, Rule/SmartFolder-Duplikat-Erkennung, Mehr-als-zwei-Geräte-Konflikte).

## 9. Testing-Strategie

Da laut CLAUDE.md kein Zweitgerät zur Verfügung steht, folgt die Teststrategie dem bereits
etablierten Muster aus der ArticleStatus-Stable-Identity-Fix-Lehre (Phase 2b): **zwei
unabhängige In-Memory-Datenbanken** simulieren zwei Geräte, ein gemeinsam gehaltenes
`CKRecord`-Objekt simuliert den Server-Stand.

Unit-Tests pro Tabelle:
1. Unterschiedliche Felder auf beiden Seiten geändert → beide überleben gemergt.
2. Gleiches „Fragen"-Feld unterschiedlich geändert → landet in `pending_sync_conflicts`,
   keine Seite wird automatisch verworfen.
3. Gleiches „Auto"-Feld unterschiedlich geändert → bestehende LWW-Regel greift wie bisher.

Für `ArticleStatus`: `isRead`/`isStarred` unabhängig mit unterschiedlichen
`readAt`/`starredAt`-Zeitstempeln → jedes Feld löst für sich per eigenem Zeitstempel auf.

Für den Erst-Aktivierungs-Analyzer: Tests gegen eine gemockte `CKQuery`-Antwort (Duplikat
gefunden / kein Duplikat / Query-Fehler), sowie ein End-to-End-Test für „Zusammenführen"
(Fremdschlüssel-Konsistenz nach dem ID-Umbiegen) und „Beide behalten" (disambiguierender
Namenszusatz, keine Kollision mehr).

Live-Verifikation gegen echtes CloudKit bleibt wie bei den Vorphasen nur mit echten zwei
Geräten sauber vollständig möglich — zumindest die Push-Seite eines künstlich erzwungenen
Konflikts (schnelles Hintereinander-Ändern auf demselben Gerät, analog zum bereits
dokumentierten Live-Test-Muster aus Phase 2a/2b) ist im Nachgang manuell antestbar.

## 10. Migrations-Übersicht

| Migration | Inhalt |
|---|---|
| `v27_add_changed_fields_to_pending_changes` | `cloud_sync_pending_changes.changedFields: String?`, nullable, kein Default |
| `v28_create_pending_sync_conflicts` | Neue Tabelle `pending_sync_conflicts` (Abschnitt 5) |
