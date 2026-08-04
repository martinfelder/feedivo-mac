# Feed-Refresh: Optimierungsliste

Stand: 2026-08-03

> Eigenständige, abarbeitbare Liste — getrennt vom großen Erzähl-Vergleich in
> `docs/performance/netnewswire-feedivo-mechanik-vergleich.md` (Abschnitt 6
> „Refresh und Feed-Skip-Logik" dort deckt v. a. die 9-Minuten-Drossel und die
> Feed-Skip-Logik ab, Stand 2026-07-15/28). Diese Liste hier entstand aus einem
> gezielten Nutzer-Eindruck („Feed-Aktualisierung fühlt sich langsam an",
> 2026-08-03) und einem direkten Codevergleich gegen NetNewsWires echtes
> GitHub-Repo (lokaler Klon: `/Users/martinfelder/Developer/NetNewsWire-main`,
> Stand des Klons: Juli 2026 — bei Bedarf vor erneuter Nutzung gegen
> `github.com/Ranchero-Software/NetNewsWire` auf Aktualität prüfen, der Klon
> ist kein Git-Repo und lässt sich nicht per `git pull` aktualisieren).

Abhaken, sobald eine Maßnahme umgesetzt UND live verifiziert ist (nicht schon
bei reiner Implementierung — siehe Gotcha-Kultur in `CLAUDE.md`: „Behauptung
erst nach echter Verifikation", vgl. Memory `verify-dont-infer-from-timing`).

---

## Erkenntnisse (Codevergleich 2026-08-03)

Betroffene Feedivo-Dateien: [`SQLiteFeedRefreshCoordinator.swift`](../../Feedivo/Services/SQLiteFeedRefreshCoordinator.swift),
[`SQLiteFeedRefreshService.swift`](../../Feedivo/Services/SQLiteFeedRefreshService.swift),
[`FeedService.swift`](../../Feedivo/Services/FeedService.swift),
[`FeedRefreshThrottle.swift`](../../Feedivo/Services/FeedRefreshThrottle.swift).
Vergleichsquellen NetNewsWire: `Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift`,
`Modules/RSWeb/Sources/RSWeb/DownloadSession.swift`, `Shared/Timer/AccountRefreshTimer.swift`.

1. **Feste, sequentielle 6er-Batches statt echter Warteschlange.**
   `SQLiteFeedRefreshCoordinator.refreshAllFeeds` teilt alle fälligen Feeds in
   Batches à `FeedViewModel.maxConcurrentFeedRefreshes` (6) und wartet mit
   `await withTaskGroup` auf den **kompletten** Batch, bevor der nächste
   startet. Ein einzelner langsamer/hängender Feed in Batch 3 blockiert damit
   nicht nur seinen eigenen Slot, sondern hält 5 bereits fertige Nachbarn UND
   den Start von Batch 4 auf. NetNewsWires `DownloadSession` nutzt stattdessen
   eine echte Warteschlange (bis zu 500 gleichzeitig pending) — sobald ein
   Task fertig ist, rückt sofort der nächste nach (`addDataTaskFromQueueIfNecessary`).

2. **`URLSession.shared` mit Default-Timeout (60s) statt dedizierter Session.**
   Feed-Fetch (`FeedService.fetchFeedConditionally`), Favicon-Discovery und
   Bild-Anreicherung laufen alle über dieselbe geteilte `URLSession.shared`
   ohne eigene Konfiguration. NetNewsWires `DownloadSession` baut pro
   Refresh-Lauf eine eigene ephemere Session mit `timeoutIntervalForRequest =
   15.0`, `httpMaximumConnectionsPerHost = 1`, ohne Cookie-/URL-Cache — ein
   toter Host blockiert dort max. 15s statt 60s, und andere Feeds konkurrieren
   nicht um denselben Connection-Pool.

3. **Bild-Anreicherung ist Teil des kritischen Refresh-Pfads.**
   `SQLiteFeedActionService` setzt `enrichArticleImages` produktiv auf
   `FeedService.enrichArticleImagesIfNeeded` — für JEDEN neuen Artikel ohne
   `imageURL` im RSS wird zusätzlich die Artikelseite selbst per HTTP geholt
   (bis zu 4 gleichzeitig, ebenfalls `URLSession.shared`), BEVOR der
   Feed-Refresh als abgeschlossen gilt. Bei 6 parallelen Feeds im selben
   Batch macht das potenziell bis zu 24 zusätzliche gleichzeitige Requests.
   NetNewsWire hat kein Äquivalent im Refresh-Pfad — Bildladen ist dort reine
   UI-Angelegenheit beim Anzeigen, nicht Teil des netzwerkkritischen Pfads.

4. **Kein Backoff für 429/wiederholte 4xx-Fehler.**
   Ein Feed, der beim letzten Refresh-All mit 429 oder 404 geantwortet hat,
   wird beim nächsten Durchlauf ganz normal wieder angefragt. NetNewsWires
   `DownloadSession` merkt sich 429-Hosts (mit Retry-After-Zeitpunkt) und
   4xx-URLs (53h Sperre) und überspringt sie aktiv.

5. **Bereits umgesetzt, nicht Teil dieser Liste** (zur Einordnung, aus der
   2026-07-27er Session, siehe `CLAUDE.md` „Letzte Änderungen"): 9-Minuten-
   Mindestabstand pro Feed (`FeedRefreshThrottle`, 1:1 von NetNewsWires
   `minimumTimeBetweenChecks` übernommen), Favicon-Single-Flight-Dedup
   (`FaviconDiscoveryCoordinator`), gebündelte Regel-Anwendung in einer
   Transaktion statt N Einzeltransaktionen, `rebuildAllFeedUnreadCounts()`
   auf gruppierte CTE umgestellt.

---

## Maßnahmen (priorisiert nach erwartetem Effekt/Aufwand)

- [x] **1. Batches → echte Warteschlange statt fester 6er-Gruppen.** *(erledigt 2026-08-04)*
      Feeds sollen starten, sobald ein Slot frei wird (z. B. über einen
      einfachen Semaphor-/Pool-Mechanismus mit `withThrowingTaskGroup`, der
      kontinuierlich nachfüllt, statt in festen Gruppen zu warten), analog
      NetNewsWires `DownloadSession`-Warteschlangen-Prinzip. Vermutlich
      größter Hebel bei vielen Feeds (>20). Betrifft primär
      `SQLiteFeedRefreshCoordinator.refreshAllFeeds`.
      **Achtung bei Umsetzung:** bestehende Tests, die sich auf feste
      Batch-Grenzen verlassen (falls vorhanden), müssen mitgeprüft werden.
      **Umsetzung:** `SQLiteFeedRefreshCoordinator.refreshAllFeeds` nutzt jetzt
      einen einzigen `withTaskGroup`-Lauf mit kontinuierlichem Nachfüllen
      (`addNextTaskIfAvailable()`, aufgerufen initial `min(batchSize, count)`-mal
      und danach nach jedem `group.next()`) statt `for batch in batches(...)`;
      die private `batches<T>(_:size:)`-Hilfsfunktion wurde entfernt (unbenutzt).
      TDD: neuer Regressionstest
      `refreshAllFeedsFuelltFreieSlotsSofortNachStattAufGanzenBatchZuWarten`
      (`FeedivoTests/Services/SQLiteFeedRefreshCoordinatorTests.swift`) — schlug
      gegen den alten Batch-Code nachweislich fehl (vierter Feed startete nach
      216ms statt sofort), ist gegen den neuen Code grün. Komplette
      `SQLiteFeedRefreshCoordinatorTests`-Suite (6/6) und `FeedViewModelTests`
      (15/15, inkl. der beiden bekannten flaky-unter-Last-Tests) grün, Debug-Build
      grün. **Noch offen:** manuelle Live-Verifikation mit vielen echten Feeds
      (spürbar kürzere Gesamtdauer bei „Alle Feeds aktualisieren"?) sowie Punkt 5
      dieser Liste (Vorher/Nachher-Zeitmessung) — bislang nur durch den
      synthetischen Timing-Test belegt, nicht durch eine echte Messung am
      Nutzer-Datenbestand.

- [x] **2. Dedizierte URLSession mit kürzerem Timeout für Feed-Fetches.** *(erledigt 2026-08-04)*
      Eigene `URLSessionConfiguration` (z. B. 15–20s `timeoutIntervalForRequest`)
      statt `.shared` für `FeedService.fetchFeedConditionally`. Reduziert die
      maximale Blockierzeit pro totem/langsamem Feed von 60s auf ~15-20s.
      **Vorsicht:** `URLSession.shared` wird aktuell auch von Favicon-Discovery
      und Bild-Anreicherung genutzt — beim Umbau klären, ob eine gemeinsame
      dedizierte Session für alle drei sinnvoll ist oder getrennte Sessions
      pro Zweck (NetNewsWire trennt: `DownloadSession` nur für Feed-Downloads).
      **Umsetzung:** neue `FeedService.makeFeedDownloadSessionConfiguration()`
      (ephemer, `timeoutIntervalForRequest = 20`, `requestCachePolicy =
      .reloadIgnoringLocalCacheData`) + private `feedDownloadSession`, genutzt
      als Default-`dataLoader` der 2-Parameter-Überladung von
      `fetchFeedConditionally(urlString:validators:)`. Bewusst NUR dort — analog
      NetNewsWires eigener Trennung bleiben Favicon-Discovery
      (`FaviconService`/`FaviconDiscoveryCoordinator`) und Bild-Anreicherung
      (`enrichArticleImagesIfNeeded`) vorerst auf `URLSession.shared`; Letztere
      ist ohnehin Gegenstand von Punkt 3. TDD: neuer Konfigurationstest
      `feedDownloadSessionConfigurationNutztKuerzerenTimeoutAlsDenSharedDefault`
      (`FeedivoTests/Services/FeedServiceConditionalFetchTests.swift`) — prüft
      die Timeout-/Cache-Policy-Werte direkt statt eines echten, 20s dauernden
      Netzwerk-Timeout-Tests. Alle bestehenden `fetchFeedConditionally`-Tests
      nutzen ohnehin die injizierbare `dataLoader:`-Überladung und sind von der
      Session-Änderung unberührt. Verifiziert: `FeedServiceConditionalFetchTests`
      (4/4), `SQLiteFeedRefreshCoordinatorTests` (6/6), `FeedViewModelTests`
      (15/15), `SQLiteFeedRefreshServiceTests` (9/9) grün, Debug-Build grün.
      **Nebenbei behoben:** Der neue Punkt-1-Regressionstest
      (`refreshAllFeedsFuelltFreieSlotsSofortNachStattAufGanzenBatchZuWarten`)
      flackerte beim gemeinsamen Lauf mit anderen Suiten (Wanduhrzeit-basiert,
      Swift-Testing-Nebenläufigkeit verzögerte „sofortige" Tasks um über 2s) —
      auf ein deterministisches Gate-Muster umgestellt (siehe Kommentar im Test),
      seither auch unter Last stabil grün.
      **Noch offen:** Live-Verifikation, dass ein tatsächlich totes/sehr
      langsames Feed jetzt nach ~20s statt ~60s abbricht (nicht praktikabel
      automatisiert zu testen).

- [x] **3. Bild-Anreicherung aus dem synchronen Refresh-Pfad lösen.** *(erledigt 2026-08-04)*
      Statt blockierend während `SQLiteFeedRefreshService.refresh(feedID:)`
      zu laufen, entweder (a) lazy beim tatsächlichen Anzeigen der
      Artikelliste/des Readers nachladen (asynchron, außerhalb des
      Refresh-Zyklus), oder (b) als eigener, dem Refresh nachgelagerter
      Hintergrund-Batch-Job mit eigenem, großzügigerem Zeitbudget. Braucht
      vermutlich eigenen Brainstorming/Spec-Durchgang, da UI-Verhalten
      (wann erscheint das Bild?) betroffen ist — kein reiner Perf-Fix.
      **Umsetzung:** Variante (b) gewählt (Brainstorming-Entscheidung des
      Nutzers). Neue Artikel werden sofort mit dem feed-eigenen Bild (oder
      ohne) gespeichert; ein nicht-awaiteter Hintergrund-`Task` je Feed holt
      fehlende Bilder danach nach und schreibt nur die `imageURL`-Spalte
      gezielt zurück (neue `ArticleStore.updateImageURL(articleID:imageURL:)`,
      statt vollem Upsert). Kandidaten-Ermittlung nutzt den bereits
      bestehenden Spotlight-Snapshot-Abruf mit (kein zusätzlicher DB-Zugriff).
      Umgesetzt via Brainstorming→Spec→Plan→Subagent-Driven-Development
      (2 Tasks: `ArticleStore.updateImageURL`,
      `SQLiteFeedRefreshService`-Umbau). Spec:
      `docs/superpowers/specs/2026-08/2026-08-04-feed-refresh-bild-anreicherung-hintergrund-design.md`,
      Plan:
      `docs/superpowers/plans/2026-08/2026-08-04-feed-refresh-bild-anreicherung-hintergrund.md`.
      **Zwei echte Funde unterwegs, beide behoben:** (1) Task 2s Implementer
      widersprach zurecht dem im Plan ursprünglich vorgesehenen ersten Test —
      dieser prüfte „direkt nach `refresh()` noch kein Bild" per Wanduhrzeit-
      Vergleich, was unter diesem Projekt (`SWIFT_DEFAULT_ACTOR_ISOLATION =
      MainActor`) deterministisch falsch lag, da `refresh()` und der neue
      Hintergrund-Task dieselbe MainActor-Warteschlange teilen und Letzterer
      durch einen späteren `await`-Punkt in `refresh()` (Favicon-Discovery)
      bereits fertig sein kann, bevor `refresh()` selbst zurückkehrt — auf ein
      deterministisches Timeout-Rennen umgestellt. (2) **Finaler Whole-Branch-
      Review fand einen echten Critical-Bug, den keine der beiden Einzel-Task-
      Reviews sehen konnte** (zeigt sich erst über zwei Refresh-Zyklen hinweg):
      da Anreicherung jetzt nur noch für neu eingefügte Artikel läuft, hätte
      `ArticleStore.upsert`s weiterhin hartes `imageURL = ?` im Update-Zweig
      ein vom Hintergrund-Task gefundenes Bild beim nächsten Refresh desselben
      Artikels **garantiert und dauerhaft** auf `NULL` zurückgesetzt (keine
      erneute Anreicherung mehr, da der Artikel nicht mehr „neu" ist) —
      ursprünglich in der Spec fälschlich als „behoben nebenbei" statt „neu
      eingeführt" dokumentiert. Fix: `imageURL = COALESCE(?, imageURL)` statt
      hartem Overwrite, plus Regressionstests auf beiden Ebenen (Store direkt,
      und End-to-End über zwei `refresh()`-Aufrufe). Zusätzlich im selben Fund
      behoben: der Timeout-Test aus (1) nutzte ein nicht-cancellation-aware
      Gate — bei einer künftigen Regression hätte das die Testsuite hängen
      lassen statt sauber nach 2s fehlzuschlagen (bekanntes, in `CLAUDE.md`
      dokumentiertes Schmerzthema in diesem Projekt) — auf cancellable
      `Task.sleep` umgestellt. Whole-Branch-Review nach Fix-Runde: „Ready to
      merge" (alle Findings adressiert, keine neuen Regressionen).
      **Bewusst zurückgestellt (dokumentiert, nicht blockierend):** ein
      Write pro angereichertem Artikel statt gebündelter Transaktion (gleiche
      Fehlerklasse, die der Refresh-Throttling-Nachzügler vom 2026-07-27 für
      `applyRules` bereits behoben hat — hier weniger kritisch, da im nicht-
      blockierenden Hintergrund-Task); kein feedübergreifendes Concurrency-
      Limit für die Hintergrund-Anreicherung (bewusste Scope-Entscheidung,
      siehe Spec); versteckte (regelbasiert ausgeblendete) Artikel bekommen
      kein Bild-Backfill (Verhaltensänderung ggü. altem Code, nicht explizit
      spezifiziert). **Noch offen:** Live-Verifikation im laufenden Betrieb
      (Bild erscheint nach kurzer Verzögerung nach dem Refresh, verschwindet
      NICHT beim nächsten Refresh desselben Artikels mehr).

- [ ] **4. Einfaches 429-/4xx-Backoff analog `DownloadSession`.**
      Neue, leichtgewichtige In-Memory- oder persistente Sperre pro Host
      (429 → Retry-After respektieren, sonst Default-Backoff; wiederholte
      4xx → befristete Sperre). Geringerer Alltags-Impact als 1–3, aber
      schützt vor Ausreißern bei kaputten/blockierenden Feeds.

- [ ] **5. Messung vor/nach.** Vor Umsetzung von 1–3 eine einfache Zeitmessung
      des kompletten „Alle Feeds aktualisieren"-Durchlaufs bei der
      tatsächlichen Feed-Anzahl des Nutzers festhalten (z. B. per
      `CFAbsoluteTimeGetCurrent()`-Log um `refreshAllFeeds(...)`), damit der
      Effekt jeder Maßnahme belegbar ist statt nur gefühlt — passend zur
      etablierten Projektkultur „Verifikation vor Behauptung".

---

## Offene Fragen für die Umsetzung

- Punkt 1 und 2 lassen sich vermutlich unabhängig voneinander umsetzen und
  einzeln live verifizieren (kleinere, überprüfbare Schritte statt eines
  großen Umbaus).
- Punkt 3 hat einen UI-Anteil (Bild erscheint ggf. verzögert nach dem
  Refresh) — vor Umsetzung kurz abstimmen, ob das gewünschte Verhalten ist.
- Reihenfolge ist ein Vorschlag, kein Zwang — bei Bedarf einzelne Punkte
  vorziehen oder überspringen.
