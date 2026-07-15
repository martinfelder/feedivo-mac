# Code- & App-Qualitäts-Review — 2026-07-11

> Entstanden aus einem 3-Agenten-Parallel-Review (Korrektheit/Fehlerbehandlung,
> Code-Qualität/Wartbarkeit, App-Funktions-/UX-Qualität) über den gesamten
> Feedivo-Codebase. Dieses Dokument ist als eigenständiger Ausgangspunkt für eine
> **neue Session** geschrieben — keine Vorkenntnis der ursprünglichen Review-
> Session nötig.

**Ziel dieses Dokuments:** Handoff-fähige Fund-Liste, aus der eine neue Session
direkt einen Umsetzungsplan bauen kann (z. B. via `superpowers:writing-plans` +
`superpowers:subagent-driven-development`, wie es dieses Projekt bereits für
das Performance-Hardening-Programm vom 2026-07-11 genutzt hat, siehe
`docs/superpowers/plans/2026-07-11-performance-hardening-phase1.md` als
Referenz-Vorlage für Struktur/Stil).

**Empfohlenes Vorgehen für die neue Session:** nicht alle 28 Funde auf einmal
umsetzen. Mit Priorität Hoch (Abschnitt 1) starten, dabei die "Empfohlene
Reihenfolge" am Ende dieses Dokuments befolgen — die gruppiert zusammengehörige
Funde, damit ein Fix nicht mehrfach denselben Code anfasst.

---

## Drei wiederkehrende Muster (Kontext für alle Funde)

1. **Fehler werden berechnet, aber nie angezeigt.** Mehrfach unabhängig
   gefunden: ein `errorMessage`/`loadState` wird im ViewModel/State korrekt
   gesetzt, aber keine View liest es je — der Nutzer sieht nur einen
   leeren/unveränderten Zustand ohne jede Erklärung.
2. **Lokalisierung wird an mehreren zentralen Stellen komplett umgangen.**
   Nicht nur unübersetzt, sondern strukturell *nie übersetzbar* (`Text(String)`
   statt `Text(LocalizedStringKey)`/`L10n`-Key), ausgerechnet in sehr häufig
   sichtbaren Zuständen (leere Artikelliste, DB-Fehler).
3. **Dieselbe SQL-/HTML-Logik ist mehrfach unabhängig kopiert** — exakt das
   Muster, das im Juli 2026 bereits einen echten Produktionsbug verursacht hat
   (fehlende `faviconURL`-Spalte, siehe CLAUDE.md-Gotcha zu
   "Duplizierte SQL-SELECT-Listen"), diesmal aber noch tiefer (7-fache
   SQL-Kopie, 3-fache sicherheitsrelevante HTML-Escaping-Kopie, davon ein Teil
   komplett ungetestet).

---

## 1. Priorität Hoch

### 1.1 Artikel löschen hat keine Bestätigung
**Datei:** `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:781-798`
Ausgelöst von: `Feedivo/Views/ArticleList/ArticleRowView.swift:153-155`
**Szenario:** `deleteArticle(_:)` führt sofort ein permanentes
`DELETE FROM articles WHERE id = ?` aus, direkt aus dem Kontextmenü-Button
(`role: .destructive`), ohne `.confirmationDialog`. Feed-Löschen
(`ContentView.swift:199`), Tag-Löschen (`TagManagerView.swift:32`),
Regel-Löschen (`RuleSettingsView.swift:47`), Ordner-/Smart-Folder-Löschen
(`SidebarView.swift:101/124`) haben alle eine Bestätigung — Artikel-Löschen
ist die einzige Ausnahme. Ein Fehlklick im Kontextmenü (direkt neben
"Exportieren"/"Teilen") löscht einen Artikel unwiderruflich.
**Fix:** `.confirmationDialog` analog zu den anderen Lösch-Pfaden ergänzen.

### 1.2 Fehler beim Artikel-Löschen wird verschluckt
**Datei:** `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:795-797`
```swift
} catch {
    reload()
}
```
**Szenario:** Schlägt das SQL-DELETE fehl (DB-Fehler), passiert für den
Nutzer nichts sichtbares außer einem Reload — keine Fehlermeldung, kein
Hinweis, dass die Löschung nicht geklappt hat.
**Fix:** Fehler mindestens in ein sichtbares `errorMessage`-State schreiben,
analog zu `SQLiteFeedArticleListState.mutateStatus` (setzt bereits korrekt
`state.loadState = .failed(...)`).

### 1.3 "Alle als gelesen markieren" scheitert komplett stumm
**Datei:** `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:679-691`
(`markRowsRead`)
**Szenario:** Nutzer wählt "Alle als gelesen markieren" für einen ganzen
Feed/Ordner/Smart-Folder. `TimelineStore.markRead(...)` wirft (DB gesperrt,
Platte voll, korrupter Zustand) → `catch { reload() }` liest nur neu und
kehrt zurück. Kein `errorMessage`/`loadState`-Update, kein Log. Vergleiche
mit `requestExportArticle` (Zeile 732) und `SQLiteFeedArticleListState.
mutateStatus` (Zeile 312-314), die beide korrekt
`state.loadState = .failed(error.localizedDescription)` setzen — Inkonsistenz,
keine bewusste Design-Entscheidung.
**Fix:** `catch { state.loadState = .failed(error.localizedDescription) }`,
danach optional weiterhin `reload()`.

### 1.4 "Alle Feeds aktualisieren" scheitert komplett stumm
**Datei:** `Feedivo/ViewModels/FeedViewModel.swift:314` (`refreshAllFeeds`)
```swift
let snapshots = (try? service.refreshSnapshots()) ?? []
guard !snapshots.isEmpty else { return }
```
**Szenario:** Wirft `FeedStore.feeds()` (DB-Fehler), wird `snapshots` zu
`[]`, die Funktion kehrt ohne `errorMessage` zurück, `isLoading` wird nie
umgeschaltet. Der Einzel-Feed-Refresh `refreshFeed(feedID:)` direkt darüber
(Zeile 298-302) fängt Fehler dagegen korrekt ab und setzt `errorMessage`. Ein
Klick auf "Alle aktualisieren" im Toolbar/Menü gibt bei diesem Fehlerpfad
null Feedback — wirkt, als wäre nichts passiert.
**Fix:** `try?` durch echtes `do/catch` ersetzen, das vor dem Return
`errorMessage` setzt.

### 1.5 Ungültige Regex in Regel-Bedingung matcht dauerhaft nichts, ohne Warnung
**Dateien:** `Feedivo/Services/RuleEngine.swift:267-276`,
`Feedivo/Views/Rules/RuleWizardView.swift:646-707`
**Szenario:** `RuleWizardView.save()` lässt den Nutzer `.regex` als
Bedingungs-Operator wählen und speichert jeden beliebigen String als
`RuleConditionRecord.value` ohne Muster-Validierung. Beim Matching macht
`RuleEngine.regularExpression(for:pattern:)` `try? NSRegularExpression(
pattern: pattern, ...)` (Zeile 275) — ein ungültiges Muster (z. B.
unbalanciertes `(`) liefert still `nil`, und `matches(condition:article:)`
(Zeile 240-243) gibt danach für jeden Artikel `false` zurück, für immer. Die
Live-Vorschau im Wizard (`previewMatchingCount`, Catch-Block Zeile 640-643)
setzt bei jedem Fehler ebenfalls `previewMatchingCount = 0` — selbst der
"N Artikel matchen"-Hinweis im Editor kann nicht zwischen "wirklich 0
Treffer" und "Regex kaputt" unterscheiden.
**Fix:** Muster mit `NSRegularExpression(pattern:)` schon beim Speichern in
`RuleWizardView.save()`/`SQLiteRuleStore.save` validieren, bei Fehler einen
sichtbaren Validierungsfehler zeigen. `RuleEngine.regularExpression` könnte
zusätzlich ungültige Muster loggen statt bedingungslos `nil` zurückzugeben.

### 1.6 Sidebar-Ladefehler wird berechnet, aber nirgends angezeigt
**Dateien:** `Feedivo/ViewModels/SQLiteSidebarState.swift:39-82`,
`Feedivo/Views/Sidebar/SidebarView.swift`
**Szenario:** `load(...)`'s Catch-Block setzt korrekt
`errorMessage = error.localizedDescription` (Zeile 81), aber `errorMessage`
auf `SQLiteSidebarState` (genutzt als `sqliteSidebarState` in
`SidebarView.swift:47`) wird in `SidebarView.swift` nirgends gelesen
(verifiziert per Grep). Schlägt die Sidebar-Query fehl (transienter
DB-Fehler, korrupte Smart-Folder-Bedingung → SQL-Fehler), sieht der Nutzer
nur eine leere Sidebar (Feeds/Tags/Ordner alle auf `[]` zurückgesetzt) —
nicht unterscheidbar von "du hast noch keine Feeds".
**Fix:** `sqliteSidebarState.errorMessage` an eine sichtbare
`Text`/Banner-Anzeige in `SidebarView.swift` binden, analog zum bereits
existierenden Muster für `viewModel.errorMessage` (Zeile 835).

### 1.7 Leerer-Artikelliste-Text ist strukturell nie lokalisierbar
**Datei:** `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:418-441`
```swift
private var emptyDescription: String {
    ...
    case .feed: return "Für diesen Feed sind noch keine SQLite-Artikel gespeichert."
    ...
}
private var emptyTitle: String {
    isSearching ? L10n.articleSearchNoResultsTitle : "Keine Artikel"
}
```
**Szenario:** Beide sind als `String` (nicht `LocalizedStringKey`) typisiert;
der Aufruf `Text(emptyDescription)` (Zeile 195) nutzt Swifts wörtliches
`Text(String)`-Init, das grundsätzlich **nie** lokalisiert — unabhängig vom
Katalog-Inhalt. In `Localizable.xcstrings` fehlen "Keine Artikel" und "Für
diesen Feed sind noch keine SQLite-Artikel gespeichert." komplett (kein
Stub, kein Eintrag). Englische/französische/italienische Nutzer sehen hier
dauerhaft deutschen Text — einer der am häufigsten sichtbaren Zustände der
App (jeder Feed/Tag/Filter/Ordner ohne Artikel).
**Fix:** `emptyTitle`/`emptyDescription` über `L10n`-Keys (analog
`L10n.articleListEmptyTitle`/`-Description`) für jeden `scope`-Fall führen.

### 1.8 `ArticleListSnapshot`-SQL-Projektion 7-fach dupliziert
**Dateien:** `Feedivo/Stores/ArticleStore.swift:119, 230, 260, 302, 394`,
`Feedivo/Stores/TimelineStore.swift:87-104`,
`Feedivo/Stores/ArticleDatabase.swift:280-296`
**Szenario:** Der identische 16-Spalten-`SELECT` (`a.id … f.faviconURL …
COALESCE(o.state,'none') AS offlineStateRaw` über `articles JOIN feeds JOIN
article_statuses LEFT JOIN article_offline`) ist wörtlich 5× allein in
`ArticleStore.swift` sowie je 1× in `TimelineStore.swift` und
`ArticleDatabase.swift` kopiert. Genau diese Duplikation hat bereits den
dokumentierten `faviconURL`-Bug verursacht (siehe CLAUDE.md-Gotcha) — der
damalige Fix hat nur die zwei betroffenen Stellen geflickt, nicht die
Ursache. Es existieren weiterhin 6 weitere unabhängige Kopien.
**Fix:** Gemeinsame SQL-Fragment-Konstante (z. B.
`static let articleListSelectColumns`) einführen, die alle Stores
referenzieren.

### 1.9 HTML-Escaping/Link-Filterung für Export 3-fach kopiert, PDF/DOCX ungetestet
**Dateien:** `Feedivo/Services/ArticleExportService.swift:559
(isSafeLinkTarget), 642 (escapedHTML), 863 (escapedHTML, 2. Kopie im selben
File), 283 (publishedDateFormatter)`,
`Feedivo/Services/ArticleDocumentExportRenderers.swift:403 (escapedHTML), 415
(isSafeLinkTarget), 425 (publishedDateFormatter)`
**Szenario:** `isSafeLinkTarget` (Link-Schema-Allowlist `http/https/mailto`)
und `escapedHTML`/`escapedHTMLAttribute` sind byte-identisch an 3 Stellen
implementiert — sogar innerhalb von `ArticleExportService.swift` selbst
zweimal. Da es sich um Escaping/Link-Filterung für exportiertes HTML/PDF/DOCX
handelt, ist unabhängiges Auseinanderlaufen (z. B. vergessenes Schema beim
Nachpflegen einer Stelle) ein reales Sicherheitsrisiko. Zusätzlich:
`Feedivo/Services/ArticleDocumentExportRenderers.swift` (526 Zeilen, aktiv
genutzt aus `ArticleExportService.swift:106+108`,
`ArticleExportPackageBuilder.swift:77-85`, `ArticleExportSheet.swift:337`)
hat **0 Testdateien** unter `FeedivoTests/` — der komplette PDF/DOCX-Pfad
inkl. der HTML-Sanitization läuft ungetestet, während der verwandte Code in
`ArticleExportService.swift` über `ArticleExportServiceTests.swift`
abgedeckt ist.
**Fix:** Gemeinsamen `HTMLSanitizing`-Helfer (Struct/Enum) extrahieren, von
allen drei Stellen nutzen. Danach Tests für `isSafeLinkTarget`,
`escapedHTML`, `ArticlePDFExportRenderer.data(for:options:)` und
`ArticleDOCXExportRenderer.data(for:options:)` ergänzen.

---

## 2. Priorität Mittel

### 2.1 Kein Feed-Fehler-Badge in der Sidebar
**Dateien:** `Feedivo/Snapshots/FeedSidebarSnapshot.swift:3-10` (kein
Error-/Status-Feld), `Feedivo/Views/Sidebar/FeedRowView.swift` (kein
Warn-Icon)
**Szenario:** `FEATURES.md` Feature 20.1 fordert ein ⚠️-Badge beim Feed in
der Sidebar bei Nichterreichbarkeit — Status laut Doku "✅ Entschieden,
bereit zur Implementierung", also geplant, aber nicht umgesetzt.
`FeedSidebarSnapshot` transportiert keinerlei Fehlerstatus, `FeedRowView`
zeigt nichts dergleichen. Ein dauerhaft fehlschlagender Feed ist für den
Nutzer unsichtbar, außer er öffnet aktiv die Feed-Eigenschaften und prüft den
Log.

### 2.2 Keine "Erneut versuchen"-Buttons in Fehler-/Leerzuständen
**Dateien:** `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:168-196`,
`Feedivo/Views/Reader/SQLiteReaderView.swift:244-254`
**Szenario:** Alle `ContentUnavailableView`-Aufrufe im Projekt (per Grep
verifiziert) nutzen ausschließlich `title`/`systemImage`/`description` —
nirgends den `actions:`-Trailing-Closure für einen Button. Feature 20.1/20.2
fordert explizit "Erneut versuchen"/"Feed aktualisieren"-Buttons; diese
fehlen durchgängig, auch im `.failed(let message)`-Fall (Zeile 179-184), wo
ein Retry am naheliegendsten wäre.

### 2.3 Mehrere Fehlerzustands-Strings nur als leere Stubs im Katalog
**Dateien:** `Feedivo/Views/Reader/ArticleWindowView.swift:71`,
`Feedivo/Views/Reader/SQLiteReaderView.swift:245-247, 265, 830-833`,
`Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:169-181`
**Szenario:** Diese Strings gehen zwar technisch über den
`LocalizedStringKey`-Mechanismus, aber in `Localizable.xcstrings` existieren
sie nur als leere Auto-Stub-Einträge (`localizations: {}`) ohne
de/en/fr/it-Übersetzung: "SQLite nicht verfügbar", "Die lokale
Artikeldatenbank konnte nicht geöffnet werden.", "Feed noch nicht in
SQLite", "Artikel nicht gefunden", "Noch kein Artikel geladen".
`SQLiteReaderView.swift:833` (`state.errorMessage ?? "Der Artikel ist nicht
mehr in der lokalen Datenbank vorhanden."`) fehlt sogar komplett im Katalog,
da die Fallback-Kette den `String`-Init von `Text` erzwingt (wie 1.7). Bei
nicht-deutscher App-Sprache bleiben diese zentralen Fehlerpfade auf Deutsch.

### 2.4 Fehlerdarstellung app-weit inkonsistent
**Dateien:** `Feedivo/Views/ContentView.swift:214-220, 441-444`,
`Feedivo/Views/Sidebar/SidebarView.swift:835-836, 1159-1160`
**Szenario:** Im gesamten `Views/`-Baum gibt es genau 2 Dateien mit
`.alert(` (`ContentView.swift`, `ArticleWindowView.swift`). Der dort
verwendete `opmlAlert`-State wird sowohl für OPML-Fehler als auch für
DB-Init-Fehler *und* für Artikel-Export-Fehler (Zeile 441-444) wiederverwendet
— ein generischer Alert-Mechanismus für mehrere unabhängige Fehlerdomänen.
Gleichzeitig werden vergleichbar schwere Fehler wie "Feed hinzufügen
fehlgeschlagen" oder "Ordner-Name doppelt" (`SidebarView.swift`) nur als
Inline-`Text(errorMessage)` neben dem jeweiligen Formularfeld angezeigt. Es
gibt keine erkennbare Regel, wann ein Fehler die App per Modal unterbricht
und wann er nur unauffällig inline erscheint.

### 2.5 OPML-Import-Refresh-Fehler: konkreter Grund wird verworfen
**Datei:** `Feedivo/Services/SQLiteFeedSubscriptionService.swift:283-293`
```swift
} catch {
    failedFeedTitles.append(title)
}
```
**Szenario:** Nur der Feed-Titel bleibt erhalten; der tatsächliche `error`
(Netzwerk-Timeout vs. Parse-Fehler vs. HTTP 404 etc.) wird verworfen und nie
in `FeedLogStore` protokolliert, anders als jeder andere Fehlerpfad in
dieser Datei (die einen `FeedLogRecord` mit `level: "error"` anhängen). Nach
einem OPML-Import mit "sofort aktualisieren" bekommt ein Nutzer mit
mehreren fehlgeschlagenen Feeds nur eine Titel-Liste ohne Diagnosemöglichkeit.
**Fix:** `FeedLogRecord(level: "error", message: error.localizedDescription,
...)` für `feedID` anhängen, bevor die Schleife weiterläuft.

### 2.6 Automatisches Retention-Cleanup verschluckt Fehler
**Dateien:** `Feedivo/App/FeedivoApp.swift:210-218`,
`Feedivo/Views/Sidebar/FeedPropertiesView.swift:748-755`
**Szenario:** Beide Aufrufstellen nutzen `_ = try?
ArticleRetentionCleanupService.removeExpiredSQLiteArticles(...)`, verwerfen
jeden geworfenen Fehler ohne Logging. Der manuelle "Jetzt aufräumen"-Button
(`SettingsView.swift:1140`) macht dagegen `removedCount = try
ArticleRetentionCleanupService.removeExpiredSQLiteArticles(...)` und kann
Erfolg/Fehlschlag melden. Schlägt der automatische Pfad (App-Start, nach
Ändern der Retention-Einstellungen) dauerhaft fehl, wachsen
Aufbewahrungslimits unbemerkt unbegrenzt weiter.
**Fix:** Fehler mindestens loggen (z. B. `FeedLogStore`), statt bloßem
`try?`.

### 2.7 Inkonsistente, unbenannte Fetch-Limits (500/1000/200)
**Dateien:** `Feedivo/ViewModels/SQLiteFeedArticleListState.swift:376`
(`limit: 500`), `Feedivo/Views/Reader/ArticleWindowView.swift:159`
(`limit: 1000`, Scope `.all`), `Feedivo/Views/ArticleList/
ArticleSearchWindowView.swift:357` (`limit: 200`)
**Szenario:** Drei strukturell ähnliche "lade Artikel für Liste/Navigation"-
Aufrufe verwenden drei verschiedene hartcodierte Limits ohne gemeinsame
Konstante oder Begründung. `ArticleWindowView.loadNavigation`
(Vor/Zurück-Navigation im Popout-Fenster, Scope `.all`, `includeHidden:
true`) bricht bei mehr als 1000 Artikeln in der DB die Navigationskette
still ab, ohne Hinweis für den Nutzer.
**Fix:** Zentrale, benannte Konstanten je Anwendungsfall (z. B.
`TimelineStore.defaultNavigationLimit`), Grenzverhalten dokumentieren oder
Pagination erwägen.

### 2.8 `SettingsView.swift`: "New"-Präfix ohne existierende Alt-Version
**Datei:** `Feedivo/Views/Settings/SettingsView.swift` (gesamte Datei, z. B.
`struct NewSettingsView` Zeile 68, `windowID = "feedivo-settings-new"` Zeile
69)
**Szenario:** Alle 19 Typen der Datei tragen das Präfix `New*`
(`NewSettingsSection`, `NewGeneralSettingsView`, `NewAppearanceSettingsView`,
`NewCleanupSettingsView` …), inklusive der **persistierten** Fenster-ID
`"feedivo-settings-new"`. Es existiert im gesamten Repo keine
`OldSettingsView`/`LegacySettingsView` mehr — erkennbares
Rename-Artefakt einer vergangenen Redesign-Aktion, nie aufgeräumt.
**Fix:** `New`-Präfix in einem eigenen Rename-Commit entfernen — Vorsicht:
`windowID`-String ist persistiert, ggf. Migration nötig oder String bewusst
beibehalten und nur Typnamen bereinigen.

### 2.9 250ms-Debounce zweimal unterschiedlich implementiert
**Dateien:**
`Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:806`
(`Task.sleep(for: .milliseconds(250))`) vs.
`Feedivo/Views/ArticleList/ArticleSearchWindowView.swift:65`
(`Task.sleep(nanoseconds: 250_000_000)`)
**Szenario:** Beide Views implementieren dieselbe "debounce Suchtext, leeres
Feld sofort committen"-Logik eigenständig, mit zwei verschiedenen
`Task.sleep`-Aufrufkonventionen für denselben Wert. Kein gemeinsamer Helfer,
kein benannter `250`-Wert.
**Fix:** Gemeinsamen `debounce(_:delay:)`-Helfer extrahieren; Delay als
benannte Konstante.

### 2.10 Kein sichtbares Ladefeedback während des OPML-Imports
**Datei:** `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift:460-464,
496-526`
**Szenario:** Der Import-Button wird während `feedViewModel.isLoading` nur
`.disabled(...)`; kein Spinner, kein Statustext ("Importiere …") am Button
selbst (Label bleibt statisch, Zeile 470-473). Bei vielen ausgewählten
Feeds (jeder ggf. mit Netzwerk-Validierung) kann das wie ein nicht
reagierender Button wirken.

---

## 3. Priorität Niedrig

- **`(try? TagStore(...).tags()) ?? []` an 4 Stellen** maskiert DB-Fehler als
  "keine Tags vorhanden" — `RuleSettingsView.swift:223`,
  `RuleWizardView.swift:715`, `ArticleSearchWindowView.swift:344`,
  `FeedPropertiesView.swift:638`. Im Rule Wizard verschwindet dadurch sogar
  die "Tag zuweisen"-Option komplett ohne Erklärung.
- **Rollback-Cleanup bei Feed-Add/Import-Fehler ist selbst wieder still** —
  `SQLiteFeedSubscriptionService.swift:186-190, 274-279`
  (`try? cleanupSQLiteSubscription(...)` etc.). Schlägt die Cleanup selbst
  fehl, bleibt eine verwaiste `feed_folders`-Zeile ohne jede Spur zurück
  (sichtbar als leerer Ordner in der Sidebar).
- **Keine URL-Validierung beim OPML-Parsen selbst** —
  `Feedivo/Services/OPMLService.swift:200-233`. Malformte URLs werden erst
  einzeln beim Feed-Abruf erkannt, nicht vorab im Review-Screen.
- **`SettingsView.swift` als 1311-Zeilen-Monolith** mit 12
  Tab-Implementierungen in einer Datei — inkonsistent zum sonstigen
  Aufteilungsmuster (`Views/Rules/`, `Views/SmartFolders/`,
  `Views/OPMLImport/` sind je auf mehrere Dateien verteilt).
- **`FeedRefreshSnapshot.id: UUID` bricht ADR-006** (IDs app-weit als
  `String`) — `Feedivo/Services/FeedRefreshSnapshot.swift:3`,
  `SQLiteFeedActionService.swift:64-75`. Der Round-Trip
  `String → UUID(uuidString:)` in einem `compactMap` verwirft Feeds mit
  ungültigem UUID-Format still aus dem Refresh, ohne Log. Aktuell unkritisch
  (alle IDs sind `UUID().uuidString`), aber unabgesichertes Invariant.
- **`FeedRenameView`: dieselbe unlokalisierte Fehlermeldung 3× dupliziert** —
  `Feedivo/Views/Sidebar/FeedRenameView.swift:158, 174, 192`
  (`errorMessage = "SQLite-Datenbank ist nicht verfügbar."`, als `String`,
  nicht über `L10n`).
- **Regel-Vorschau zeigt "0 Treffer" identisch bei echtem 0-Match wie bei
  DB-Fehler** — `Feedivo/Views/Rules/RuleWizardView.swift:630-644`.
- **`RuleViewModel.swift` weiterhin toter Code** (260 Zeilen, bereits beim
  Dead-Code-Cleanup vom 2026-07-10 identifiziert, Löschentscheidung noch
  offen) — `Feedivo/ViewModels/RuleViewModel.swift`. Regressionstest in
  `FeedivoAppSceneConfigurationTests.swift` beweist bereits, dass die Klasse
  absichtlich nicht mehr aus `RuleSettingsView`/`RuleWizardView` verwendet
  werden soll.

---

## Positiv verifiziert (zur Einordnung, keine Funde)

Diese Stellen wurden geprüft und sind sauber implementiert — nicht erneut
anfassen: Leere-URL-Validierung bei Feed hinzufügen
(`FeedViewModel.swift:221-223`), Tag-Name-Validierung inkl.
Duplikat-Erkennung (`TagManagerView.swift:161-198`), Discovery-Ladeindikator
(`SidebarView.swift:786, 855`), Such-ohne-Ergebnis-Empty-State mit
Suchbegriff (`ArticleSearchWindowView.swift:289-305`, korrekt über `L10n`
lokalisiert), Artikel-/Feed-Titel-Fallback bei fehlenden RSS-Feldern
(`FeedService.swift:271-292`), `ImageCacheService.swift`s `try?`-Nutzung
(legitimes Best-Effort-Caching), `FeedDiscoveryService.swift:62` (bewusste
Zwei-Strategien-Fallback-Kette), `FeedivoDatabase.inMemoryForTests()` als
konsistent genutzte Test-Hilfsfunktion,
`FeedViewModel.maxConcurrentFeedRefreshes = 6` als korrekt geteilte
Konstante über 3 Dateien.

---

## Empfohlene Reihenfolge für die Umsetzung

1. **Artikel-Löschen absichern** (1.1 + 1.2) — kleinster Fix, größtes
   unmittelbares Risiko (unwiderruflicher Datenverlust per Fehlklick).
2. **Bulk-Aktionen-/Sidebar-Fehleranzeige** (1.3, 1.4, 1.6) — gemeinsamer
   Fix-Ansatz, da überall dasselbe Muster (State existiert, wird nie
   gebunden).
3. **Regex-Validierung bei Regeln** (1.5) — sonst bleibt eine kaputte Regel
   für den Nutzer dauerhaft unsichtbar.
4. **SQL-/HTML-Duplikation konsolidieren** (1.8 + 1.9) — bevor eine weitere
   Feldänderung erneut divergiert; PDF/DOCX-Tests im selben Rutsch ergänzen.
5. **Lokalisierungslücken** (1.7, 2.3, "FeedRenameView"-Punkt aus Abschnitt
   3) — gemeinsam, da alle über fehlende `L10n`-Anbindung laufen.
6. **Fehler-UX-Konsistenz** (2.1, 2.2, 2.4) — Feature-20-Umsetzung als
   zusammenhängendes Stück (Fehler-Badge, Retry-Buttons, einheitliche
   Alert-vs-Inline-Regel).
7. Rest (2.5–2.10, Abschnitt 3) nach Kapazität.

**Hinweis für die neue Session:** Für Schritte 1-4 lohnt sich vermutlich ein
eigener `writing-plans`-Durchlauf pro Schritt (analog zum
Performance-Hardening-Plan), da jeder Schritt mehrere Dateien anfasst und
TDD-Nachweise braucht. Schritt 5 (Lokalisierung) ist eher mechanisch und
könnte in einem Rutsch ohne granulares TDD erledigt werden, sollte aber am
Ende gegen `Localizable.xcstrings` in allen 4 Sprachen (de/en/fr/it)
verifiziert werden.
