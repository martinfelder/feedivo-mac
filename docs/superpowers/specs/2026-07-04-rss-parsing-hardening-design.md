# Spec A — RSS-Parsing-Härtung

**Datum:** 2026-07-04
**Status:** Entworfen, wartet auf Review
**Vorgänger:** Vergleichs-Analyse NetNewsWire vs. Feedivo (RSS-Parsing)
**Nachfolger:** Spec B — Podcast-Player (separat, später)

## Ziel

Den bestehenden RSS-Parsing-Pfad (`FeedService` → `SQLiteFeedRefreshService` → `ArticleStore`) an den Stand von NetNewsWire angleichen, ohne neue Persistenz-Entities einzuführen. Vier unabhängige, aufeinander abgestimmte Härtungen:

1. Author-Parsing (bisher ungenutzt)
2. Synthetische Artikel-Identität bei fehlendem guid/link
3. Vollständige HTTP-Härtung (429, Cache-Control, Redirects, 4xx, Conditional-GET-Dropping, „definitely not feed"-Abbruch, per-Host User-Agent, Connections-Limit)
4. Zukunfts-Datum-Clamp

Nicht in Spec A: Attachment/Media-Support und Podcast-Player → Spec B.

## Nicht-Ziele (YAGNI)

- Keine strukturierte Author-Speicherung (nur Anzeigename).
- Kein eigenes XML-Parsing (FeedKit bleibt).
- Kein eigener DateParser (FeedKit-Datumsparsing bleibt).
- Keine UI für Autoren-Anzeige in Spec A (nur Parsing + Persistenz).
- Keine Sync-Account-Pfade (Feedbin/Feedly-Äquivalente) — Feedivo hat nur lokale Feeds.

## Architektur-Überblick

```
FeedHTTPClient  ──(URLRequest + Policy)──▶  URLSession (ephemeral)
        │
        ▼
FeedService.fetchFeedConditionally  ──▶  parseFeed (FeedKit)
        │                                       │
        │                                       ├─ author extrahieren
        │                                       ├─ synthetische sourceID bei guid+link == nil
        │                                       └─ publishedAt > now+24h → nil
        ▼
SQLiteFeedRefreshService ──▶ ArticleStore.upsert (author + sourceID werden genutzt)
        │
        └─ FeedHTTPPolicy: 429/Retry-After, 4xx-Blacklist, Redirect-Cache,
           „definitely not feed", Conditional-GET-Dropping nach 8 Tagen,
           Cache-Control max-age (5h gedeckelt) im Coordinator
```

## Komponenten

### 1. Author-Parsing

**Zustand:** `ParsedArticle` hat kein `author`-Feld; `ArticleUpsertInput.author` existiert und die `articles.author`-Spalte existiert, wird aber nie aus dem Feed gefüllt.

**Änderung:**

- `ParsedArticle` (FeedService.swift:28) erhält `let author: String?` plus init-Parameter.
- RSS (`parseRSSFeed`): `author` aus `<author>` (E-Mail-Form → Namensanteil vor `@`) oder `<dc:creator>` (Klartext). Leere Strings → `nil`.
- Atom (`parseAtomFeed`): `<author><name>`; falls Entry keinen Autor hat, Root-Feed-Autor-Override anwenden (wie NetNewsWire AtomParser.swift:60-65).
- JSON Feed (`parseJSONFeed`): `authors[].name` bzw. legacy `author.name`; erstes Element.
- `SQLiteFeedRefreshService` mapt `article.author` in `ArticleUpsertInput(author:)` (Zeile ~107).
- `ArticleStore.upsert` schreibt `author` bereits (Zeilen 383, 399) — keine Änderung nötig.

**UI:** entfällt in Spec A. Anzeige in `ArticleRowView`/`ReaderView` ist ein separater kleiner Folgeschritt.

### 2. Synthetische Identität

**Problem:** `ArticleStore.findExistingArticleID` (ArticleStore.swift:448) matched nur über `sourceID` (guid) oder `link`. Ist beides `nil`/leer, wird bei jedem Refresh ein neuer Artikel eingefügt (Status wird via `article_identity_history.titleHash` wiederhergestellt, aber die `articles`-Tabelle sammelt Duplikate).

**Änderung:** In jeder `parseXxxFeed` wird, falls `sourceID == nil` UND `link == nil` (jeweils `trimmedNonEmpty`), eine synthetische ID erzeugt:

```
sourceID = "synth:" + sha256(title + "|" + ISO8601(publishedAt ?? feedRefreshedAt))
```

- Präfix `"synth:"` trennt von echten guids, vermeidet Kollisionen, erleichtert Debugging.
- Algorithmus SHA-256 via CryptoKit (bereits Dependency, siehe `contentHash`).
- `feedRefreshedAt` ist `Date()`-Äquivalent im Parser-Kontext — da `Date()` in Workflows gesperrt wäre, hier über Test-injizierbaren Zeitpunkt (siehe unten).
- `ArticleStore.findExistingArticleID` matcht dann über `sourceID` und updated statt inserts.
- Bestehende `article_identity_history`-titleHash-Logik bleibt unverändert als Safety-Net für Status-Wilderung.

**Injizierbare Uhr:** `parseFeed(data:sourceURL:now:)` erhält optionalen `now: () -> Date = Date.init`-Parameter, damit der synthetische Hash deterministisch testbar ist.

### 3. HTTP-Härtung (vollständig)

**Neue Dateien** in `Feedivo/Services/`:

#### 3a. `FeedHTTPClient.swift`

Kapselt eine `URLSession` mit:

- `URLSessionConfiguration.ephemeral`
- `reloadIgnoringLocalCacheData`
- `httpCookieStorage = nil`, `urlCache = nil`
- `httpMaximumConnectionsPerHost = 1`
- `timeoutIntervalForRequest = 15`, `timeoutIntervalForResource = 30`
- Per-Host User-Agent via statischem `UserAgent.headers()` (Default) + `addSpecialCaseUserAgentIfNeeded(host:)`.

Exponiert:

- `func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)` (wirft `FeedServiceError.httpError(statusCode)` für 4xx/5xx, außer policy-gesteuerte Pfade).
- Hält eine `FeedHTTPPolicy`-Instanz.

#### 3b. `FeedHTTPPolicy.swift`

In-memory Zustand (pro App-Lebensdauer, nicht persistiert):

- **429:** `Retry-After`-Header parsen (Sekunden oder HTTP-Date), Default 10 Min. Host wird für diese Dauer gesperrt; laufende Tasks des Hosts werden gecancelt; neue Requests des Hosts werden sofort mit `.httpError(429)` (oder spezifisch `.tooManyRequests`) abgewiesen.
- **4xx (außer 429):** URL kommt auf eine Blacklist für konfigurierbare Dauer (Default 1 h). Folgerequests der URL werden übersprungen (`.httpError(statusCode)` an Aufrufer, der es im Refresh als „überspringen" behandeln kann).
- **Redirects (301/302/307/308):** Ziel-URL cachen (Map originURL → finalURL); künftige Requests direkt ans Ziel bauen. „Disallowed redirects" filtern via Heuristik: Domain-Wechsel zu bekannter Werbe/Login-Domain (vereinfachte Liste) → ignorieren, origin bleibt.
- **„definitely not feed":** Vorzeitiger Abbruch im Data-Stream, wenn Daten eindeutig HTML sind (`<!DOCTYPE html` oder `<html` als Prefix nach Whitespace-Trim, ohne Feed-Root wie `<rss`/`<feed`/`{`). Wirft `.parsingFailed`.

#### 3c. Conditional-GET-Dropping

In `SQLiteFeedRefreshService` bzw. `SQLiteFeedRefreshCoordinator`:

- Bezugspunkt ist das `Last-Modified`-Datum des Feeds (HTTP-Header, in `FeedHTTPValidators.lastModified` als String gespeichert). Ist `now - parsedLastModifiedDate > 8 Tage` UND der letzte Fetch war 304, werden ETag/Last-Modified für den nächsten Fetch gedropped (`FeedHTTPValidators` mit `eTag = nil, lastModified = nil`). Bei erfolgreichem 200-Fetch werden sie neu gesetzt und der 8-Tage-Zähler resettet.
- Kann `Last-Modified` nicht geparst werden, fällt der Mechanismus auf ETag-only zurück und nutzt als Bezugspunkt eine neue `feeds`-Spalte `conditionalGetSetAt DATE` (Zeitpunkt, an dem der aktuelle ETag erstmals gesetzt wurde).
- Persistiert wird `conditionalGetSetAt DATE` (neue `feeds`-Spalte). `conditionalGetDroppedAt` entfällt zugunsten von `conditionalGetSetAt = nil` als „gedroppt"-Indikator.
- Ausnahmen: Hosts `openrss.org`, `rachelbythebay.com` — dort nie droppen (wie NetNewsWire).

#### 3d. Cache-Control

- `FeedHTTPValidators` erhält `cacheControlMaxAge: Int?`.
- Neue `feeds`-Spalte `cacheControlMaxAge INTEGER`.
- `Cache-Control: max-age=N` aus HTTP-Response parsen; auf `5 * 3600` deckeln.
- `SQLiteFeedRefreshCoordinator` überspringt Feeds, deren `now - lastRefresh < cacheControlMaxAge` (auer bei manueller Refresh-Aktion).

#### 3e. Integration in FeedService

- `FeedService.fetchFeedConditionally` nutzt `FeedHTTPClient` statt `URLSession.shared`.
- `FeedHTTPValidators` wird um `cacheControlMaxAge: Int?` und `conditionalGetSetAt: Date?` ergänzt.
- Bestehende Tests mit injiziertem `dataLoader` bleiben kompatibel, weil `FeedHTTPClient` hinter demselben `FeedRequestDataLoader`-Closure-Typ injizierbar bleibt (Default wechselt zu `FeedHTTPClient`, Tests können `URLProtocol`-Mock setzen).

### 4. Zukunfts-Datum-Clamp

- In jeder `parseXxxFeed`: `publishedAt` clamps — ist `publishedAt > now + 24 h`, wird `nil` zugewiesen.
- Konstante `maximumFutureInterval: TimeInterval = 24 * 3600`.
- Nutzt denselben injizierbaren `now`-Parameter wie Komponente 2.
- Verhindert Sortier-Sprünge bei fehlerhaften Feeds.

## Datenmodell / Migration

- `articles.author` — bereits vorhanden (Migrator v1 oder früher), keine Änderung.
- `feeds`-Neue Spalten via `v11_add_feed_http_hardening_fields`:

  - `cacheControlMaxAge INTEGER`
  - `conditionalGetSetAt DATE`

- Keine neuen Entities, keine CloudKit-Relevanz (Feeds sind SQLite-only).

## Testing (TDD)

Pro Komponente Tests zuerst, dann Implementierung:

- **`FeedServiceTests`**:
  - Author-Extraktion RSS (`<author>` E-Mail, `<dc:creator>`), Atom (`<author><name>`, Root-Fallback), JSON Feed (`authors[].name`, legacy `author`).
  - Synthetische sourceID bei guid+link == nil (deterministisch via injiziertem `now`); keine synthetische ID, wenn guid oder link vorhanden.
  - Zukunfts-Clamp: `publishedAt = now + 48 h` → `nil`; `publishedAt = now + 12 h` → erhalten.
- **`FeedHTTPClientTests`** (mit `URLProtocol`-Mock):
  - 429 + `Retry-After: 60` sperrt Host; Folge-Request wirft `tooManyRequests`.
  - 404 blacklisted URL für 1 h.
  - 301 → Redirect-Cache; zweiter Request geht direkt ans Ziel.
  - „definitely not feed" (`<html>...`) wirft `.parsingFailed`.
  - 304 nach 8 Tagen → ETag/Last-Modified werden nicht mehr gesendet (Dropping).
- **`ArticleStoreTests`**:
  - Upsert mit synthetischer sourceID updated existierenden Artikel statt neu anzulegen.
  - Author-Spalte wird geschrieben und gelesen.
- **`SQLiteFeedRefreshCoordinatorTests`**:
  - Feed mit `cacheControlMaxAge`-aktivem Fenster wird bei Auto-Refresh übersprungen, bei manueller Refresh nicht.
- Bestehende Testsuite bleibt grün (351+ Tests).

## Risiko / Offen

- **Heuristik „disallowed redirects":** vereinfachte Domain-Liste; kann legitime Redirects fälschlich filtern. Mit Logging; bei Fehlalarmen Liste anpassen.
- **429-Host-Sperrung im Background-Refresh:** muss sich mit bestehendem `BackgroundRefreshService` koordinieren (Tasks cancellen). Klein.
- **Conditional-GET-Dropping:** kann kurzfristig mehr Traffic erzeugen, wenn 304-Server plötzlich full responses liefern — gewollt.
- **Author-Anzeige:** out-of-scope in Spec A; Folge-Ticket.

## Abnahme

- Alle oben genannten Tests grün.
- Build grün.
- Manueller Smoke-Test: Feed ohne guid/link wird bei Refresh aktualisiert statt dupliziert; Feed mit 429 wird pausiert; Feed mit `publishedAt` in Zukunft erscheint mit korrektem (keinem) Datum.