# Feed-Refresh: Bild-Anreicherung aus dem synchronen Pfad lösen — Design

Stand: 2026-08-04

## Kontext und Motivation

Punkt 3 der Optimierungsliste
`docs/performance/feed-refresh-optimierungsliste.md` (NetNewsWire-Vergleich,
2026-08-03), Fortsetzung von Punkt 1 (echte Warteschlange statt fester
Batches, `SQLiteFeedRefreshCoordinator`) und Punkt 2 (dedizierte URLSession
mit kürzerem Timeout, `FeedService`), beide bereits umgesetzt (Commit
`b585acc`).

`SQLiteFeedRefreshService.refresh(feedID:)` reichert aktuell **vor** dem
Einfügen neuer Artikel in die Datenbank deren fehlende Bilder an
(`enrichArticleImages(parsedFeed.articles)`, produktiv
`FeedService.enrichArticleImagesIfNeeded` — lädt für jeden Artikel ohne
`imageURL` zusätzlich dessen Artikelseite per HTTP, um `og:image`/
`twitter:image` zu extrahieren, bis zu 4 gleichzeitig). Ein Feed gilt für die
Warteschlange aus Punkt 1 erst dann als „fertig", wenn ALLE diese
zusätzlichen Seiten-Downloads abgeschlossen sind — bei vielen neuen,
bildlosen Artikeln kann das den Refresh spürbar verlängern, obwohl das
eigentliche Feed selbst längst geladen und geparst ist.

Vergleich mit NetNewsWire: deren Mac-Timeline zeigt gar keine
Artikel-Vorschaubilder (nur Feed-Icon und Autor-Avatar,
`TimelineViewController.swift`), es gibt dort also keine Referenzlösung für
dieses konkrete Problem — es ist eine reine Feedivo-Produktentscheidung.

## Ziel

Der Refresh eines Feeds soll abgeschlossen sein, sobald der Feed-Inhalt
selbst geladen, geparst und gespeichert ist — unabhängig davon, ob noch
Bilder für einzelne Artikel fehlen. Fehlende Bilder werden weiterhin
automatisch nachgeladen, aber **nicht mehr blockierend**.

## Lösung

### 1. Kein synchrones Enrichment mehr vor dem Insert

`SQLiteFeedRefreshService.refresh(feedID:)` baut `ArticleUpsertInput`s
künftig direkt aus `parsedFeed.articles` (unverändert inkl. der bestehenden,
umfangreichen Fallback-Logik beim Parsen selbst — `media:content`,
`itunes:image`, Enclosures, eingebettete `<img>`-Tags im Content/Description,
siehe `FeedService.parseRSSFeed`/`parseAtomFeed`/`parseJSONFeed`). Der
bisherige `let enrichedArticles = await enrichArticleImages(parsedFeed.articles)`-
Aufruf vor `articleStore.upsert(inputs)` entfällt.

### 2. Kandidaten-Ermittlung über den bestehenden Spotlight-Snapshot-Abruf

Direkt nach dem Insert holt `refresh()` bereits für die
Spotlight-Indexierung die frisch eingefügten Artikel als
`[ArticleListSnapshot]` (`ArticleDatabase(database:).fetchArticles(
articleIDs: Set(upsertResult.insertedArticleIDs), includeHidden: false)`).
Dieser Abruf wird aus dem bisherigen `logIfThrows`-Block herausgezogen und
für zwei Zwecke wiederverwendet — kein zusätzlicher DB-Zugriff:

```swift
if !upsertResult.insertedArticleIDs.isEmpty {
    logIfThrows(context: "Snapshot-Abruf für neu eingefügte Artikel nach Feed-Refresh") {
        let insertedSnapshots = try ArticleDatabase(database: database).fetchArticles(
            articleIDs: Set(upsertResult.insertedArticleIDs),
            includeHidden: false
        )
        indexForSpotlight(insertedSnapshots)
        scheduleDeferredImageEnrichmentIfNeeded(for: insertedSnapshots)
    }
}
```

`scheduleDeferredImageEnrichmentIfNeeded` filtert auf
`imageURL == nil && link != nil` — nur diese Artikel sind Enrichment-
Kandidaten. `ArticleListSnapshot` trägt bereits `id`, `link`, `imageURL`
(siehe `Feedivo/Snapshots/ArticleListSnapshot.swift`).

### 3. Hintergrund-Task, nicht awaitet

```swift
private func scheduleDeferredImageEnrichmentIfNeeded(for snapshots: [ArticleListSnapshot]) {
    let candidates = snapshots.filter { $0.imageURL == nil && $0.link != nil }
    guard !candidates.isEmpty else { return }

    let enrichArticleImages = self.enrichArticleImages
    let database = self.database
    let onComplete = self.onDeferredImageEnrichmentComplete

    Task {
        await Self.enrichAndPersistImages(
            candidates: candidates,
            database: database,
            enrichArticleImages: enrichArticleImages
        )
        onComplete?()
    }
}
```

`refresh()` selbst `await`et diesen `Task` nicht — er läuft unabhängig
weiter, analog zum bereits etablierten Spotlight-Backfill-Muster
(„Aufrufer feuert die Funktion seither über ein einfaches `Task { }` ab,
ohne auf den Abschluss zu warten", siehe Gotcha zu
`SWIFT_DEFAULT_ACTOR_ISOLATION` in `CLAUDE.md`). Kein `Task.detached` nötig
— reines Fire-and-Forget, keine Reentrancy-Problematik wie beim
`CKSyncEngine`-Gotcha.

### 4. `enrichAndPersistImages` — Fetch + gezieltes Update

Die bestehende Seiten-Fetch-Logik (`enrichArticleImages`, unverändert,
Signatur `([ParsedArticle]) async -> [ParsedArticle]`) wird mit
Platzhalter-`ParsedArticle`s aufgerufen, die nur `link` aus den Kandidaten
tragen (Titel/Summary/Content werden für diesen Zweck nicht gebraucht — die
Fetch-Logik nutzt ausschließlich `.link` und schreibt nur `.imageURL` über
`.copy(imageURL:)` zurück, siehe `FeedService.enrichArticleImagesIfNeeded`).
Für jeden Treffer wird **nur die `imageURL`-Spalte** des betroffenen
Artikels aktualisiert (kein voller Upsert):

```swift
private static func enrichAndPersistImages(
    candidates: [ArticleListSnapshot],
    database: FeedivoDatabase,
    enrichArticleImages: ArticleImageEnricher
) async {
    let placeholders = candidates.map { candidate in
        ParsedArticle(title: "", link: candidate.link, summary: nil, content: nil, publishedAt: nil, imageURL: nil)
    }
    let enriched = await enrichArticleImages(placeholders)

    let articleStore = ArticleStore(database: database)
    var didUpdateAny = false
    for (candidate, result) in zip(candidates, enriched) {
        guard let imageURL = result.imageURL else { continue }
        do {
            try articleStore.updateImageURL(articleID: candidate.id, imageURL: imageURL)
            didUpdateAny = true
        } catch {
            AppLogger.dataAccess.error("Nachträgliche Bild-Anreicherung: Speichern für Artikel \(candidate.id, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }
    if didUpdateAny {
        SQLiteDataInvalidation.bumpStatusVersion()
    }
}
```

`zip(candidates, enriched)` ist sicher, da `enrichArticleImagesIfNeeded`
Ein- und Ausgabe-Array garantiert gleich lang und index-gleich hält (bereits
bestehendes Verhalten, unverändert).

### 5. Neue `ArticleStore`-Methode

```swift
func updateImageURL(articleID: String, imageURL: String) throws {
    try database.write { db in
        try db.execute(
            sql: "UPDATE articles SET imageURL = ? WHERE id = ?",
            arguments: [imageURL, articleID]
        )
    }
}
```

Bewusst ein schlankes, gezieltes `UPDATE` statt eines vollen Upserts — der
Artikel existiert bereits vollständig, nur `imageURL` ändert sich.

### 6. Enrichment nur für neu eingefügte Artikel — braucht COALESCE-Schutz gegen Bild-Reset

**Korrektur (2026-08-04, gefunden im finalen Whole-Branch-Review, als
Critical eingestuft und behoben — Commit `7d5e3ee`):** Diese Sektion ging
ursprünglich davon aus, dass die Umstellung auf „nur neu eingefügte Artikel
anreichern" einen bestehenden Bug nebenbei behebt. Das Gegenteil war der
Fall: **Heute** (vor dieser Änderung) läuft `enrichArticleImages` auf
**alle** aktuell im Feed enthaltenen Artikel (`parsedFeed.articles`), nicht
nur auf neu eingefügte — jeder erneute Refresh eines bereits bekannten
Artikels ohne RSS-Bildangabe versucht erneut, dessen `og:image` zu laden,
und schreibt das Ergebnis (Treffer oder `nil`) über das harte
`imageURL = ?` im Update-Zweig von `ArticleStore.upsert` zurück — ein
bereits gefundenes Bild kann so nur bei einem fehlschlagenden
Wiederholungsversuch verloren gehen (Netzwerk-Hänger, Seite geändert),
nicht garantiert.

Die ursprünglich geplante neue Version, die **ausschließlich**
`upsertResult.insertedArticleIDs` anreichert, hätte diesen Fall massiv
verschlimmert statt behoben: Sobald ein Artikel einmal „nicht mehr neu" ist
(jeder Refresh ab dem zweiten Mal, in dem der Artikel noch im Feed steht),
wird `enrichArticleImages` für ihn nie wieder aufgerufen — ein vom
Hintergrund-Task gefundenes Bild würde durch das weiterhin harte
`imageURL = ?` im Update-Zweig beim nächsten Refresh **garantiert und
dauerhaft** auf `NULL` zurückgesetzt, da kein weiterer Versuch mehr folgt,
es erneut zu finden. **Tatsächliche Lösung:** `ArticleStore.upsert`s
Update-Zweig nutzt jetzt `imageURL = COALESCE(?, imageURL)` (statt eines
harten Overwrites) — ein `nil`-Wert aus dem Feed-Parse überschreibt ein
bereits vorhandenes Bild nicht mehr, ein vom Feed tatsächlich geliefertes
Bild überschreibt weiterhin normal. Erst dadurch ist die Umstellung auf
„nur neu eingefügte Artikel anreichern" sicher. Siehe
`Feedivo/Stores/ArticleStore.swift` (Update-Zweig von `upsert(_:db:)`) sowie
den neuen Regressionstest in `SQLiteArticleStoreTests.swift`
(`upsertUeberschreibtBestehendesBildNichtMitNullBeiErneutemUpsertOhneBild`)
und den Zwei-Refresh-Regressionstest in `SQLiteFeedRefreshServiceTests.swift`
(`refreshBehaeltImHintergrundGefundenesBildBeiZweitemRefreshOhneFeedEigenesBild`).

### 7. Testbarkeit ohne Wanduhrzeiten

Lehre aus Punkt 1 (siehe `docs/performance/feed-refresh-optimierungsliste.md`):
Tests, die auf `Task.sleep`/Wanduhrzeiten warten, flackern unter Last durch
andere gleichzeitig laufende Testsuiten. Neuer, optionaler Test-Hook:

```swift
typealias DeferredImageEnrichmentObserver = @Sendable () -> Void

private let onDeferredImageEnrichmentComplete: DeferredImageEnrichmentObserver?
```

Standard `nil`, produktiv ungenutzt (kein Verhalten geändert). Tests
übergeben eine Closure, die eine `CheckedContinuation` auflöst, und können
so deterministisch auf das Ende des Hintergrund-Tasks warten, statt eine
feste Wartezeit zu raten.

**Parameterreihenfolge im Initializer:** `enrichArticleImages` muss laut
bestehendem Kommentar in `SQLiteFeedRefreshService.swift` vor `fetcher`
stehen, `fetcher` muss der letzte Parameter bleiben (bestehende Tests nutzen
dafür Trailing-Closure-Syntax). `onDeferredImageEnrichmentComplete` wird
direkt nach `enrichArticleImages` eingefügt, weiterhin vor `fetcher`.

## Scope-Entscheidungen

- **Kein globales Concurrency-Limit über mehrere Feeds hinweg.** Jeder Feed
  startet seinen eigenen Hintergrund-Task unabhängig (weiterhin max. 4
  gleichzeitige Seiten-Fetches *pro Feed*, wie heute). Bei einem
  Refresh-All mit vielen Feeds könnten kurzzeitig mehrere solcher Tasks
  parallel laufen — bewusst kein Problem, da kein Nutzer aktiv darauf
  wartet und die meisten Feeds ohnehin wenige oder keine bildlosen Artikel
  haben. Bei Bedarf später nachrüstbar, analog zum bestehenden
  `FaviconDiscoveryCoordinator`-Muster (Punkt 1/2).
- **`SQLiteFeedActionService` (Feed manuell hinzufügen) und
  `SQLiteFeedSubscriptionService` (OPML-Import) bleiben unverändert
  synchron.** Das sind einmalige Aktionen, nicht der wiederkehrende
  „Alle Feeds aktualisieren"-Pfad, um den es in dieser Optimierungsliste
  geht.
- **Keine UI-Anzeige eines „Bild wird noch geladen"-Zustands.** Die Zeile
  zeigt einfach kein Bild, bis `SQLiteDataInvalidation.bumpStatusVersion()`
  die Liste zum Neuladen anstößt (bestehender Mechanismus, kein neuer
  Ladeindikator).

## Testing

- **Neuer Test:** direkt nach `refresh()` hat ein neu eingefügter,
  RSS-seitig bildloser Artikel `imageURL == nil` in der DB — beweist, dass
  die Anreicherung nicht mehr synchron blockiert.
- **Neuer Test:** mit `onDeferredImageEnrichmentComplete`-Hook + einer
  `CheckedContinuation` deterministisch auf den Hintergrund-Task warten,
  danach `imageURL` in der DB als gesetzt verifizieren.
- **Bestehender Test `refreshRuftEnrichArticleImagesAufUndSpeichertDerenErgebnis`**
  wird umgeschrieben — er prüft aktuell synchrones Verhalten
  (`storedArticle?.imageURL` direkt nach `refresh()`), das nicht mehr
  zutrifft. Wird durch die beiden obigen Tests ersetzt bzw. entsprechend
  angepasst.
- **`ArticleStore.updateImageURL`** — eigener Unit-Test (bestehenden
  Artikel anlegen, `updateImageURL` aufrufen, per `article(id:)`
  gegenlesen).
- Bestehende Tests, die `enrichArticleImages` mit dem No-Op-Default
  (`{ $0 }`) laufen lassen, bleiben unberührt (keine Kandidaten, kein
  Hintergrund-Task wird überhaupt gestartet).

## Nicht-Ziele

- Kein globales, feedübergreifendes Concurrency-Limit für die
  Hintergrund-Anreicherung (siehe Scope-Entscheidungen).
- Keine Änderung an `SQLiteFeedActionService`/`SQLiteFeedSubscriptionService`.
- Kein neuer UI-Ladezustand für „Bild lädt noch nach".
- Keine Änderung an der bestehenden Fallback-Logik beim Feed-Parsen selbst
  (`media:content`, Enclosures, eingebettete `<img>`-Tags) — die bleibt
  exakt wie heute.
