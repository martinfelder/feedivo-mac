# Browser-Erweiterung Popup-UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Popup der Browser-Erweiterung zeigt echte, unterscheidbare Feed-Namen, weiß ob ein Feed schon in Feedivo abonniert ist, gibt eine echte Erfolgs-/Fehlerrückmeldung beim Hinzufügen und wirkt visuell aufgeräumter (Favicon, URL-Zweitzeile).

**Architecture:** Zwei unabhängige, aber zusammenspielende Teile: (1) Die Browser-Erweiterung (`BrowserExtensions/Chrome/`, geteilt mit Safari) löst echte Feed-Titel per Fetch+Parse aus dem Feed-Inhalt selbst auf, statt Seiten-Titel-Heuristiken zu vertrauen. (2) Die Feedivo-App startet einen minimalen, nur auf `127.0.0.1` lauschenden HTTP-Server (`Network.framework`/`NWListener`), den das Popup abfragt, um Abo-Status zu prüfen und Feeds direkt hinzuzufügen — mit echtem Erfolgs-/Fehler-Feedback statt des bisherigen Fire-and-Forget-Deep-Links. Läuft die App nicht, fällt die Erweiterung automatisch auf das bisherige `feedivo://add`-Verhalten zurück.

**Tech Stack:** JavaScript (Manifest V3, `node:test` für Unit-Tests), Swift 6 / `Network.framework` (kein neues SPM-Package), Swift Testing (kein XCTest).

## Global Constraints

- UI-Strings und Code-Kommentare auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- Keine neuen SwiftPM-Abhängigkeiten — nur `Network.framework` (Systemframework) für den lokalen Server.
- Swift-Tests ausschließlich mit **Swift Testing** (`import Testing`, `@Test func`), kein XCTest.
- Swift-Tests laufen gezielt per `-only-testing:FeedivoTests/<SuiteName>` (voller Testlauf hängt bekanntermaßen, siehe CLAUDE.md-Gotchas).
- `xcodebuild build` ist die einzig verlässliche Fehlerquelle für Swift-Code — SourceKit-Diagnosen im Editor können veraltet/falsch sein, nicht danach urteilen.
- `content.js` (Chrome/Safari, MV3-Content-Scripts unterstützen keine ES-Module) und `BrowserExtensions/Shared/feedDetection.mjs` (Node-getestet) müssen bei jeder Logikänderung synchron gehalten werden — das ist eine bestehende, bewusste Duplizierung, keine zu behebende Altlast.
- Lokaler Server bindet ausschließlich an `127.0.0.1`, niemals `0.0.0.0`.
- Spec: `docs/superpowers/specs/2026-07-13-browser-erweiterung-ux-design.md`

---

### Task 1: Echte Feed-Titel aus Feed-Inhalt extrahieren (reine Funktionen)

**Files:**
- Modify: `BrowserExtensions/Shared/feedDetection.mjs`
- Test: `BrowserExtensions/Shared/feedDetection.test.mjs`

**Interfaces:**
- Produces: `extractFeedTitleFromXML(xmlText: string): string | null`, `extractFeedTitleFromJSON(jsonText: string): string | null`, `extractFeedTitleFromContent(feedText: string): string | null` — alle als benannte Exporte aus `feedDetection.mjs`. Task 2 ruft `extractFeedTitleFromContent` auf.

RSS (`<channel><title>…</title>`) und Atom (`<feed><title>…</title>`) haben beide ihren Kanal-/Feed-Titel als ERSTES `<title>`-Tag im Dokument (vor jedem `<item>`/`<entry>`-Titel) — ein simpler "erstes `<title>`-Tag"-Regex-Match reicht deshalb für beide Formate, ganz ohne `DOMParser` (der in Node nicht existiert und die Testbarkeit erschweren würde).

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Füge am Ende von `BrowserExtensions/Shared/feedDetection.test.mjs` hinzu (Import-Zeile oben anpassen):

```javascript
import {
    detectFeedsFromLinkTags,
    probeFallbackFeedPaths,
    detectFeeds,
    extractFeedTitleFromXML,
    extractFeedTitleFromJSON,
    extractFeedTitleFromContent
} from "./feedDetection.mjs";
```

Und ans Dateiende:

```javascript
test("extractFeedTitleFromXML liest den Kanal-Titel aus RSS", () => {
    const xml = "<rss><channel><title>Mein RSS-Feed</title><item><title>Artikel</title></item></channel></rss>";
    assert.equal(extractFeedTitleFromXML(xml), "Mein RSS-Feed");
});

test("extractFeedTitleFromXML liest den Feed-Titel aus Atom", () => {
    const xml = "<feed><title>Mein Atom-Feed</title><entry><title>Artikel</title></entry></feed>";
    assert.equal(extractFeedTitleFromXML(xml), "Mein Atom-Feed");
});

test("extractFeedTitleFromXML entfernt CDATA-Wrapper", () => {
    const xml = "<rss><channel><title><![CDATA[Feed & Co.]]></title></channel></rss>";
    assert.equal(extractFeedTitleFromXML(xml), "Feed & Co.");
});

test("extractFeedTitleFromXML dekodiert XML-Entities", () => {
    const xml = "<rss><channel><title>Tom &amp; Jerry &#39;Show&#39;</title></channel></rss>";
    assert.equal(extractFeedTitleFromXML(xml), "Tom & Jerry 'Show'");
});

test("extractFeedTitleFromXML liefert null ohne title-Tag", () => {
    assert.equal(extractFeedTitleFromXML("<rss><channel></channel></rss>"), null);
});

test("extractFeedTitleFromJSON liest das title-Feld eines JSON Feed", () => {
    const json = JSON.stringify({ version: "https://jsonfeed.org/version/1.1", title: "Mein JSON Feed" });
    assert.equal(extractFeedTitleFromJSON(json), "Mein JSON Feed");
});

test("extractFeedTitleFromJSON liefert null bei kaputtem JSON", () => {
    assert.equal(extractFeedTitleFromJSON("{kaputt"), null);
});

test("extractFeedTitleFromJSON liefert null ohne title-Feld", () => {
    assert.equal(extractFeedTitleFromJSON(JSON.stringify({ version: "1" })), null);
});

test("extractFeedTitleFromContent erkennt XML-Inhalt", () => {
    const xml = "<rss><channel><title>XML-Feed</title></channel></rss>";
    assert.equal(extractFeedTitleFromContent(xml), "XML-Feed");
});

test("extractFeedTitleFromContent faellt auf JSON zurueck, wenn kein title-Tag existiert", () => {
    const json = JSON.stringify({ title: "JSON-Feed" });
    assert.equal(extractFeedTitleFromContent(json), "JSON-Feed");
});

test("extractFeedTitleFromContent liefert null bei unbekanntem Inhalt", () => {
    assert.equal(extractFeedTitleFromContent("weder xml noch json"), null);
});
```

- [ ] **Step 2: Tests laufen lassen — müssen fehlschlagen**

Run: `node --test BrowserExtensions/Shared/feedDetection.test.mjs`
Expected: FAIL — `extractFeedTitleFromXML is not a function` (o. ä. für die anderen beiden Funktionen)

- [ ] **Step 3: Implementiere die drei Funktionen**

Füge in `BrowserExtensions/Shared/feedDetection.mjs` VOR `detectFeedsFromLinkTags` ein:

```javascript
function decodeXMLEntities(value) {
    return value
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, "\"")
        .replace(/&apos;/g, "'")
        .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
        .replace(/&amp;/g, "&");
}

// Liefert den Inhalt des ERSTEN <title>-Tags im Dokument. Sowohl RSS
// (<channel><title>) als auch Atom (<feed><title>) haben ihren Kanal-Titel
// vor jedem Artikel-<title> — kein DOMParser noetig (existiert in Node nicht
// und wuerde die Testbarkeit erschweren), ein simpler erster Treffer reicht.
export function extractFeedTitleFromXML(xmlText) {
    const match = xmlText.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    if (!match) {
        return null;
    }

    let raw = match[1].trim();
    const cdataMatch = raw.match(/^<!\[CDATA\[([\s\S]*?)\]\]>$/);
    raw = cdataMatch ? cdataMatch[1].trim() : decodeXMLEntities(raw);

    return raw.length > 0 ? raw : null;
}

export function extractFeedTitleFromJSON(jsonText) {
    try {
        const parsed = JSON.parse(jsonText);
        const title = typeof parsed?.title === "string" ? parsed.title.trim() : "";
        return title.length > 0 ? title : null;
    } catch {
        return null;
    }
}

// Versucht zuerst XML (RSS/Atom), dann JSON Feed. Ein "erstes <title>-Tag"-
// Regex auf JSON-Text matched nie, faellt also automatisch sauber durch.
export function extractFeedTitleFromContent(feedText) {
    return extractFeedTitleFromXML(feedText) ?? extractFeedTitleFromJSON(feedText);
}
```

- [ ] **Step 4: Tests laufen lassen — müssen bestehen**

Run: `node --test BrowserExtensions/Shared/feedDetection.test.mjs`
Expected: PASS — alle Tests grün (19 Tests: 8 bestehende + 11 neue)

- [ ] **Step 5: Commit**

```bash
git add BrowserExtensions/Shared/feedDetection.mjs BrowserExtensions/Shared/feedDetection.test.mjs
git commit -m "Feature: Echte Feed-Titel aus RSS/Atom/JSON-Feed-Inhalt extrahieren"
```

---

### Task 2: Echte Titel in die Feed-Erkennung einhängen (mjs + content.js)

**Files:**
- Modify: `BrowserExtensions/Shared/feedDetection.mjs`
- Modify: `BrowserExtensions/Shared/feedDetection.test.mjs`
- Modify: `BrowserExtensions/Chrome/content.js`

**Interfaces:**
- Consumes: `extractFeedTitleFromContent` aus Task 1.
- Produces: `resolveFeedTitles(feeds: {title,url}[], fetchImpl?): Promise<{title,url}[]>`, aktualisiertes `detectFeeds(doc?, fetchImpl?): Promise<{title,url}[]>` — löst jetzt IMMER echte Titel auf, bevor es zurückkehrt. Task 6/7 (Popup) konsumieren `detectFeeds`-Ergebnisse unverändert über den bestehenden `background.js`/`popup.js`-Message-Kanal (keine Signaturänderung dort nötig).

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

In `BrowserExtensions/Shared/feedDetection.test.mjs`: ERSETZE die beiden bestehenden Tests
`"detectFeeds bevorzugt Link-Tags vor der Fallback-Heuristik"` und
`"detectFeeds nutzt die Fallback-Heuristik, wenn keine Link-Tags gefunden wurden"`
durch:

```javascript
test("detectFeeds bevorzugt Link-Tags vor der Fallback-Pfad-Heuristik, loest aber trotzdem echte Titel auf", async () => {
    const doc = fakeDocument({
        links: [{ type: "application/rss+xml", href: "/feed.xml", title: "Linktitel" }]
    });
    const fetchImpl = async (url) => {
        assert.equal(url, "https://example.com/feed.xml");
        return {
            ok: true,
            text: async () => "<rss><channel><title>Echter Feed-Titel</title></channel></rss>"
        };
    };

    assert.deepEqual(await detectFeeds(doc, fetchImpl), [
        { title: "Echter Feed-Titel", url: "https://example.com/feed.xml" }
    ]);
});

test("detectFeeds nutzt die Fallback-Heuristik und loest danach echte Titel auf", async () => {
    const doc = fakeDocument({ links: [] });
    const fetchImpl = async (url) => ({
        ok: url.endsWith("/rss"),
        text: async () => "<rss><channel><title>Gefundener Feed</title></channel></rss>"
    });

    assert.deepEqual(await detectFeeds(doc, fetchImpl), [
        { title: "Gefundener Feed", url: "https://example.com/rss" }
    ]);
});

test("resolveFeedTitles behaelt den alten Titel bei fehlgeschlagenem Fetch", async () => {
    const feeds = [{ title: "Alter Titel", url: "https://example.com/feed.xml" }];
    const fetchImpl = async () => {
        throw new Error("Netzwerkfehler");
    };

    assert.deepEqual(await resolveFeedTitles(feeds, fetchImpl), feeds);
});

test("resolveFeedTitles behaelt den alten Titel bei nicht-ok Response", async () => {
    const feeds = [{ title: "Alter Titel", url: "https://example.com/feed.xml" }];
    const fetchImpl = async () => ({ ok: false });

    assert.deepEqual(await resolveFeedTitles(feeds, fetchImpl), feeds);
});

test("resolveFeedTitles behaelt den alten Titel, wenn der Inhalt nicht parsbar ist", async () => {
    const feeds = [{ title: "Alter Titel", url: "https://example.com/feed.xml" }];
    const fetchImpl = async () => ({ ok: true, text: async () => "weder xml noch json" });

    assert.deepEqual(await resolveFeedTitles(feeds, fetchImpl), feeds);
});
```

Passe den Import am Dateianfang an:

```javascript
import {
    detectFeedsFromLinkTags,
    probeFallbackFeedPaths,
    detectFeeds,
    resolveFeedTitles,
    extractFeedTitleFromXML,
    extractFeedTitleFromJSON,
    extractFeedTitleFromContent
} from "./feedDetection.mjs";
```

- [ ] **Step 2: Tests laufen lassen — müssen fehlschlagen**

Run: `node --test BrowserExtensions/Shared/feedDetection.test.mjs`
Expected: FAIL — `resolveFeedTitles is not a function`, plus die zwei ersetzten `detectFeeds`-Tests schlagen fehl (alte Erwartung ohne Titel-Fetch)

- [ ] **Step 3: Implementiere `resolveFeedTitles` und hänge es in `detectFeeds` ein**

In `BrowserExtensions/Shared/feedDetection.mjs`, füge NACH `extractFeedTitleFromContent` (Task 1) ein:

```javascript
// Holt fuer jeden Feed-Kandidaten den echten Titel aus dem Feed-Inhalt selbst
// (gleiche Origin wie die Seite, keine neue Extension-Permission noetig).
// Schlaegt der Abruf fehl oder ist der Inhalt nicht parsbar, bleibt der
// bisherige (heuristische) Titel unveraendert erhalten.
export async function resolveFeedTitles(feeds, fetchImpl = fetch) {
    return Promise.all(feeds.map(async (feed) => {
        try {
            const response = await fetchImpl(feed.url);
            if (!response.ok) {
                return feed;
            }
            const text = await response.text();
            const realTitle = extractFeedTitleFromContent(text);
            return realTitle ? { title: realTitle, url: feed.url } : feed;
        } catch {
            return feed;
        }
    }));
}
```

Ersetze die bestehende `detectFeeds`-Funktion:

```javascript
export async function detectFeeds(doc = document, fetchImpl = fetch) {
    const linkFeeds = detectFeedsFromLinkTags(doc);
    const feeds = linkFeeds.length > 0
        ? linkFeeds
        : await probeFallbackFeedPaths(doc.baseURI, fetchImpl);

    return resolveFeedTitles(feeds, fetchImpl);
}
```

- [ ] **Step 4: Tests laufen lassen — müssen bestehen**

Run: `node --test BrowserExtensions/Shared/feedDetection.test.mjs`
Expected: PASS — alle Tests grün (22 Tests)

- [ ] **Step 5: Spiegle die Aenderung nach `content.js`**

`content.js` unterstützt keine ES-Module (MV3-Content-Script-Einschränkung) — dieselbe Logik wird dupliziert. Ersetze den kompletten Inhalt von `BrowserExtensions/Chrome/content.js`:

```javascript
(() => {
    // Spiegelt die getestete Logik aus BrowserExtensions/Shared/feedDetection.mjs
    // (Node-Tests dort) — hier als klassisches, nicht-Modul-Script dupliziert,
    // weil MV3 content_scripts in der Manifest-Deklaration keine ES-Module
    // unterstützen. Bei Änderungen an der Erkennungslogik beide Stellen
    // synchron halten.
    const FEED_MIME_TYPES = new Set([
        "application/rss+xml",
        "application/atom+xml",
        "application/json",
        "application/feed+json"
    ]);

    function detectFeedsFromLinkTags() {
        const links = Array.from(document.querySelectorAll('link[rel="alternate"]'));
        const feeds = [];

        for (const link of links) {
            const type = (link.getAttribute("type") || "").toLowerCase();
            if (!FEED_MIME_TYPES.has(type)) {
                continue;
            }

            const href = link.getAttribute("href");
            if (!href) {
                continue;
            }

            feeds.push({
                title: link.getAttribute("title") || document.title || href,
                url: new URL(href, document.baseURI).href
            });
        }

        return feeds;
    }

    async function probeFallbackFeedPaths() {
        const origin = new URL(document.baseURI).origin;
        const paths = ["/feed", "/rss", "/atom.xml"];
        const found = [];

        for (const path of paths) {
            const candidateURL = origin + path;
            try {
                const response = await fetch(candidateURL, { method: "HEAD" });
                if (response.ok) {
                    found.push({ title: path, url: candidateURL });
                }
            } catch {
                // Netzwerkfehler oder CORS-Block: Pfad einfach überspringen.
            }
        }

        return found;
    }

    function decodeXMLEntities(value) {
        return value
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .replace(/&apos;/g, "'")
            .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
            .replace(/&amp;/g, "&");
    }

    function extractFeedTitleFromXML(xmlText) {
        const match = xmlText.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
        if (!match) {
            return null;
        }

        let raw = match[1].trim();
        const cdataMatch = raw.match(/^<!\[CDATA\[([\s\S]*?)\]\]>$/);
        raw = cdataMatch ? cdataMatch[1].trim() : decodeXMLEntities(raw);

        return raw.length > 0 ? raw : null;
    }

    function extractFeedTitleFromJSON(jsonText) {
        try {
            const parsed = JSON.parse(jsonText);
            const title = typeof parsed?.title === "string" ? parsed.title.trim() : "";
            return title.length > 0 ? title : null;
        } catch {
            return null;
        }
    }

    function extractFeedTitleFromContent(feedText) {
        return extractFeedTitleFromXML(feedText) ?? extractFeedTitleFromJSON(feedText);
    }

    async function resolveFeedTitles(feeds) {
        return Promise.all(feeds.map(async (feed) => {
            try {
                const response = await fetch(feed.url);
                if (!response.ok) {
                    return feed;
                }
                const text = await response.text();
                const realTitle = extractFeedTitleFromContent(text);
                return realTitle ? { title: realTitle, url: feed.url } : feed;
            } catch {
                return feed;
            }
        }));
    }

    async function detectFeeds() {
        const linkFeeds = detectFeedsFromLinkTags();
        const feeds = linkFeeds.length > 0 ? linkFeeds : await probeFallbackFeedPaths();
        return resolveFeedTitles(feeds);
    }

    detectFeeds().then((feeds) => {
        chrome.runtime.sendMessage({ type: "feedivo-feeds-detected", feeds });
    });
})();
```

- [ ] **Step 6: Manuell verifizieren, dass `content.js` gültiges JavaScript ist**

Run: `node --check BrowserExtensions/Chrome/content.js`
Expected: kein Output, Exit-Code 0 (nur Syntax-Check, kein DOM-/chrome-API vorhanden — echte Verifikation folgt in Task 8 im echten Browser)

- [ ] **Step 7: Commit**

```bash
git add BrowserExtensions/Shared/feedDetection.mjs BrowserExtensions/Shared/feedDetection.test.mjs BrowserExtensions/Chrome/content.js
git commit -m "Feature: Feed-Erkennung loest jetzt immer echte Titel aus dem Feed-Inhalt auf"
```

---

### Task 3: HTTP-Request-Parser (rein, ohne Netzwerk)

**Files:**
- Create: `Feedivo/Services/LocalExtensionBridge/HTTPRequest.swift`
- Test: `FeedivoTests/HTTPRequestParserTests.swift`

**Interfaces:**
- Produces: `struct HTTPRequest { var method: String; var path: String; var queryItems: [String: String]; var headers: [String: String]; var body: Data }`, `enum HTTPRequestParser { static func parse(_ buffer: Data) -> HTTPRequest? }`. `nil` bedeutet "noch nicht vollständig, weitere Bytes nötig" — kein Fehlerfall. Task 4 konsumiert `HTTPRequest` als Router-Eingabe. Task 5 konsumiert `HTTPRequestParser.parse` in der Socket-Empfangsschleife.

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Erstelle `FeedivoTests/HTTPRequestParserTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct HTTPRequestParserTests {
    @Test func parstEinenGETRequestMitQueryString() {
        let raw = "GET /status?url=https%3A%2F%2Fexample.com%2Ffeed.xml HTTP/1.1\r\nHost: 127.0.0.1:51823\r\n\r\n"
        let request = HTTPRequestParser.parse(Data(raw.utf8))

        #expect(request?.method == "GET")
        #expect(request?.path == "/status")
        #expect(request?.queryItems["url"] == "https://example.com/feed.xml")
        #expect(request?.headers["host"] == "127.0.0.1:51823")
        #expect(request?.body.isEmpty == true)
    }

    @Test func liefertNilWennHeaderEndeNochNichtErreicht() {
        let raw = "GET /status HTTP/1.1\r\nHost: 127.0.0.1"
        #expect(HTTPRequestParser.parse(Data(raw.utf8)) == nil)
    }

    @Test func parstEinenPOSTRequestMitJSONBody() {
        let body = "{\"url\":\"https://example.com/feed.xml\"}"
        let raw = "POST /add HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let request = HTTPRequestParser.parse(Data(raw.utf8))

        #expect(request?.method == "POST")
        #expect(request?.path == "/add")
        #expect(request?.headers["content-type"] == "application/json")
        #expect(request?.body == Data(body.utf8))
    }

    @Test func liefertNilWennBodyNochUnvollstaendigIst() {
        let raw = "POST /add HTTP/1.1\r\nContent-Length: 40\r\n\r\n{\"url\":\"https://example.com\""
        #expect(HTTPRequestParser.parse(Data(raw.utf8)) == nil)
    }

    @Test func headerNamenWerdenKleingeschriebenAbgeglichen() {
        let raw = "POST /add HTTP/1.1\r\nCONTENT-LENGTH: 0\r\n\r\n"
        let request = HTTPRequestParser.parse(Data(raw.utf8))
        #expect(request?.headers["content-length"] == "0")
    }
}
```

- [ ] **Step 2: Tests laufen lassen — müssen fehlschlagen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/HTTPRequestParserTests`
Expected: BUILD FAILED — `HTTPRequestParser`/`HTTPRequest` existieren noch nicht

- [ ] **Step 3: Implementiere `HTTPRequest` und `HTTPRequestParser`**

Erstelle `Feedivo/Services/LocalExtensionBridge/HTTPRequest.swift`:

```swift
import Foundation

struct HTTPRequest: Equatable {
    var method: String
    var path: String
    var queryItems: [String: String]
    var headers: [String: String]
    var body: Data
}

// Minimaler HTTP/1.1-Request-Parser für den lokalen Erweiterungs-Server
// (Feature: Browser-Erweiterung Popup-UX). Bewusst kein allgemeiner
// HTTP-Parser — nur so viel wie für kleine, lokale JSON-Requests von der
// eigenen Browser-Erweiterung nötig ist (kein Chunked Encoding, keine
// Multipart-Bodies).
enum HTTPRequestParser {
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    // `nil` bedeutet: `buffer` enthält noch keinen vollständigen Request
    // (Header-Ende \r\n\r\n fehlt noch, oder der Body ist kürzer als
    // Content-Length) — der Aufrufer muss weitere Bytes nachliefern, das
    // ist KEIN Fehlerfall.
    static func parse(_ buffer: Data) -> HTTPRequest? {
        guard let headerEndRange = buffer.range(of: headerTerminator) else {
            return nil
        }

        let headerData = buffer[..<headerEndRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }

        let requestLineParts = requestLine.split(separator: " ")
        guard requestLineParts.count >= 2 else {
            return nil
        }

        let method = String(requestLineParts[0])
        let (path, queryItems) = splitPathAndQuery(String(requestLineParts[1]))
        let headers = parseHeaders(lines.dropFirst())

        let bodyStart = headerEndRange.upperBound
        let expectedBodyLength = headers["content-length"].flatMap(Int.init) ?? 0
        let availableBody = buffer[bodyStart...]

        guard availableBody.count >= expectedBodyLength else {
            return nil
        }

        let body = Data(availableBody.prefix(expectedBodyLength))
        return HTTPRequest(method: method, path: path, queryItems: queryItems, headers: headers, body: body)
    }

    private static func parseHeaders(_ lines: ArraySlice<String>) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let separatorIndex = line.firstIndex(of: ":") else {
                continue
            }
            let name = line[line.startIndex..<separatorIndex]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = line[line.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return headers
    }

    private static func splitPathAndQuery(_ fullPath: String) -> (String, [String: String]) {
        guard let questionMarkIndex = fullPath.firstIndex(of: "?") else {
            return (fullPath, [:])
        }

        let path = String(fullPath[fullPath.startIndex..<questionMarkIndex])
        let queryString = String(fullPath[fullPath.index(after: questionMarkIndex)...])

        var queryItems: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let rawName = parts.first else {
                continue
            }
            let name = String(rawName).removingPercentEncoding ?? String(rawName)
            let value = parts.count > 1
                ? (String(parts[1]).removingPercentEncoding ?? String(parts[1]))
                : ""
            queryItems[name] = value
        }

        return (path, queryItems)
    }
}
```

- [ ] **Step 4: Tests laufen lassen — müssen bestehen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/HTTPRequestParserTests`
Expected: TEST SUCCEEDED — alle 5 Tests grün

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/LocalExtensionBridge/HTTPRequest.swift FeedivoTests/HTTPRequestParserTests.swift
git commit -m "Feature: Minimaler HTTP-Request-Parser fuer lokalen Erweiterungs-Server"
```

---

### Task 4: HTTP-Response + Router (rein, ohne Netzwerk/DB)

**Files:**
- Create: `Feedivo/Services/LocalExtensionBridge/HTTPResponse.swift`
- Create: `Feedivo/Services/LocalExtensionBridge/LocalExtensionBridgeRouter.swift`
- Test: `FeedivoTests/LocalExtensionBridgeRouterTests.swift`

**Interfaces:**
- Consumes: `HTTPRequest` aus Task 3.
- Produces: `struct HTTPResponse { var statusCode: Int; var statusText: String; var body: Data; var contentType: String; func serialize() -> Data; static func json(statusCode:statusText:object:) -> HTTPResponse }`, `enum LocalExtensionBridgeAddResult: Equatable { case added, alreadyExists, error(String) }`, `struct LocalExtensionBridgeRouter { typealias StatusChecker = @Sendable (String) async -> Bool; typealias FeedAdder = @Sendable (String) async -> LocalExtensionBridgeAddResult; init(checkSubscribed: @escaping StatusChecker, addFeed: @escaping FeedAdder); func handle(_ request: HTTPRequest) async -> HTTPResponse }`. Task 5 instanziiert `LocalExtensionBridgeRouter` mit echten DB-Closures und ruft `.handle(_:)` aus der Socket-Empfangsschleife.

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Erstelle `FeedivoTests/LocalExtensionBridgeRouterTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct LocalExtensionBridgeRouterTests {
    private func decodeJSONObject(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @Test func statusMitBekannterURLLiefertSubscribedTrue() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { url in url == "https://example.com/feed.xml" },
            addFeed: { _ in .error("sollte nicht aufgerufen werden") }
        )
        let request = HTTPRequest(
            method: "GET",
            path: "/status",
            queryItems: ["url": "https://example.com/feed.xml"],
            headers: [:],
            body: Data()
        )

        let response = await router.handle(request)

        #expect(response.statusCode == 200)
        #expect(decodeJSONObject(response.body)["subscribed"] as? Bool == true)
    }

    @Test func statusOhneURLParameterLiefert400() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in true },
            addFeed: { _ in .error("sollte nicht aufgerufen werden") }
        )
        let request = HTTPRequest(method: "GET", path: "/status", queryItems: [:], headers: [:], body: Data())

        let response = await router.handle(request)

        #expect(response.statusCode == 400)
    }

    @Test func addMitGueltigerURLRuftAddFeedAufUndLiefertAdded() async {
        var receivedURL: String?
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in false },
            addFeed: { url in
                receivedURL = url
                return .added
            }
        )
        let body = Data("{\"url\":\"https://example.com/feed.xml\"}".utf8)
        let request = HTTPRequest(method: "POST", path: "/add", queryItems: [:], headers: [:], body: body)

        let response = await router.handle(request)

        #expect(receivedURL == "https://example.com/feed.xml")
        #expect(response.statusCode == 200)
        #expect(decodeJSONObject(response.body)["result"] as? String == "added")
    }

    @Test func addMitBereitsVorhandenemFeedLiefertAlreadyExists() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in false },
            addFeed: { _ in .alreadyExists }
        )
        let body = Data("{\"url\":\"https://example.com/feed.xml\"}".utf8)
        let request = HTTPRequest(method: "POST", path: "/add", queryItems: [:], headers: [:], body: body)

        let response = await router.handle(request)

        #expect(response.statusCode == 200)
        #expect(decodeJSONObject(response.body)["result"] as? String == "alreadyExists")
    }

    @Test func addMitFehlerLiefert500MitNachricht() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in false },
            addFeed: { _ in .error("Netzwerkfehler") }
        )
        let body = Data("{\"url\":\"https://example.com/feed.xml\"}".utf8)
        let request = HTTPRequest(method: "POST", path: "/add", queryItems: [:], headers: [:], body: body)

        let response = await router.handle(request)

        #expect(response.statusCode == 500)
        #expect(decodeJSONObject(response.body)["message"] as? String == "Netzwerkfehler")
    }

    @Test func addMitUngueltigemBodyLiefert400() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in false },
            addFeed: { _ in .error("sollte nicht aufgerufen werden") }
        )
        let request = HTTPRequest(method: "POST", path: "/add", queryItems: [:], headers: [:], body: Data("kein json".utf8))

        let response = await router.handle(request)

        #expect(response.statusCode == 400)
    }

    @Test func unbekannteRouteLiefert404() async {
        let router = LocalExtensionBridgeRouter(
            checkSubscribed: { _ in false },
            addFeed: { _ in .error("sollte nicht aufgerufen werden") }
        )
        let request = HTTPRequest(method: "GET", path: "/unbekannt", queryItems: [:], headers: [:], body: Data())

        let response = await router.handle(request)

        #expect(response.statusCode == 404)
    }
}
```

- [ ] **Step 2: Tests laufen lassen — müssen fehlschlagen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/LocalExtensionBridgeRouterTests`
Expected: BUILD FAILED — `LocalExtensionBridgeRouter`/`LocalExtensionBridgeAddResult` existieren noch nicht

- [ ] **Step 3: Implementiere `HTTPResponse`**

Erstelle `Feedivo/Services/LocalExtensionBridge/HTTPResponse.swift`:

```swift
import Foundation

struct HTTPResponse {
    var statusCode: Int
    var statusText: String
    var body: Data
    var contentType: String = "application/json"

    static func json(statusCode: Int, statusText: String, object: [String: Any]) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return HTTPResponse(statusCode: statusCode, statusText: statusText, body: body)
    }

    func serialize() -> Data {
        var head = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"

        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}
```

- [ ] **Step 4: Implementiere `LocalExtensionBridgeRouter` und `LocalExtensionBridgeAddResult`**

Erstelle `Feedivo/Services/LocalExtensionBridge/LocalExtensionBridgeRouter.swift`:

```swift
import Foundation

enum LocalExtensionBridgeAddResult: Equatable {
    case added
    case alreadyExists
    case error(String)
}

// Reine Routing-/Verarbeitungslogik fuer den lokalen Erweiterungs-Server,
// bewusst getrennt von der NWListener-Socket-Verdrahtung (siehe
// LocalExtensionBridgeServer) — dadurch ohne echten Netzwerk-Bind testbar.
struct LocalExtensionBridgeRouter {
    typealias StatusChecker = @Sendable (String) async -> Bool
    typealias FeedAdder = @Sendable (String) async -> LocalExtensionBridgeAddResult

    private let checkSubscribed: StatusChecker
    private let addFeed: FeedAdder

    init(checkSubscribed: @escaping StatusChecker, addFeed: @escaping FeedAdder) {
        self.checkSubscribed = checkSubscribed
        self.addFeed = addFeed
    }

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/status"):
            return await handleStatus(request)
        case ("POST", "/add"):
            return await handleAdd(request)
        default:
            return .json(statusCode: 404, statusText: "Not Found", object: [
                "result": "error",
                "message": "Unbekannte Route"
            ])
        }
    }

    private func handleStatus(_ request: HTTPRequest) async -> HTTPResponse {
        guard let url = request.queryItems["url"], !url.isEmpty else {
            return .json(statusCode: 400, statusText: "Bad Request", object: [
                "result": "error",
                "message": "Fehlender url-Parameter"
            ])
        }

        let subscribed = await checkSubscribed(url)
        return .json(statusCode: 200, statusText: "OK", object: ["subscribed": subscribed])
    }

    private func handleAdd(_ request: HTTPRequest) async -> HTTPResponse {
        guard
            let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
            let url = json["url"] as? String,
            !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .json(statusCode: 400, statusText: "Bad Request", object: [
                "result": "error",
                "message": "Fehlender oder ungültiger url-Wert"
            ])
        }

        switch await addFeed(url) {
        case .added:
            return .json(statusCode: 200, statusText: "OK", object: ["result": "added"])
        case .alreadyExists:
            return .json(statusCode: 200, statusText: "OK", object: ["result": "alreadyExists"])
        case let .error(message):
            return .json(statusCode: 500, statusText: "Internal Server Error", object: [
                "result": "error",
                "message": message
            ])
        }
    }
}
```

- [ ] **Step 5: Tests laufen lassen — müssen bestehen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/LocalExtensionBridgeRouterTests`
Expected: TEST SUCCEEDED — alle 7 Tests grün

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/LocalExtensionBridge/HTTPResponse.swift Feedivo/Services/LocalExtensionBridge/LocalExtensionBridgeRouter.swift FeedivoTests/LocalExtensionBridgeRouterTests.swift
git commit -m "Feature: Router fuer lokalen Erweiterungs-Server (/status, /add)"
```

---

### Task 5: DB-Anbindung (Abo-Status, Feed hinzufügen) + NWListener-Server

**Files:**
- Create: `Feedivo/Services/LocalExtensionBridge/LocalExtensionBridgeServer.swift`
- Test: `FeedivoTests/LocalExtensionBridgeServerTests.swift`
- Modify: `Feedivo/Feedivo.entitlements`

**Interfaces:**
- Consumes: `LocalExtensionBridgeRouter`, `LocalExtensionBridgeAddResult`, `HTTPRequestParser` (Tasks 3+4); `FeedStore`, `SQLiteFeedActionService`, `SQLiteFeedSubscriptionError`, `BackgroundRefreshSettings.defaultIntervalMinutes`, `SQLiteDataInvalidation.bumpStatusVersion()`, `AppLogger.dataAccess` (bestehender Code).
- Produces: `@MainActor final class LocalExtensionBridgeServer { static let defaultPort: UInt16; init(database: FeedivoDatabase, port: UInt16 = defaultPort); func start(); static func isSubscribed(_ urlString: String, database: FeedivoDatabase) async -> Bool; static func addFeed(_ urlString: String, database: FeedivoDatabase, fetchFeed: @escaping @Sendable (String) async throws -> ParsedFeed = FeedService.fetchFeed) async -> LocalExtensionBridgeAddResult }`. Task 6 ruft `LocalExtensionBridgeServer(database:).start()` in `FeedivoApp.init()` auf.

**Hinweis zur `NWListener`-API:** `Network.framework` ist im Projekt bisher ungenutzt — die Signaturen unten sind nach bestem Wissen korrekt, aber Schritt 5 (Build) ist die eigentliche Verifikation. Kompilierfehler rund um `NWListener`/`NWParameters`/`NWEndpoint` in Schritt 5 sind erwartetes Debugging, kein Zeichen für einen falschen Plan — anhand der Xcode-Fehlermeldung korrigieren (z. B. exakte Parameter-Reihenfolge, `on:`-Label) und weitermachen.

- [ ] **Step 1: Schreibe die fehlschlagenden Tests für die DB-Anbindung**

Erstelle `FeedivoTests/LocalExtensionBridgeServerTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct LocalExtensionBridgeServerTests {
    @MainActor
    @Test func isSubscribedLiefertTrueFuerBekannteURL() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(
            FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed 1")
        )

        let subscribed = await LocalExtensionBridgeServer.isSubscribed(
            "https://example.com/feed.xml",
            database: database
        )

        #expect(subscribed == true)
    }

    @MainActor
    @Test func isSubscribedVergleichtGetrimmtUndOhneGrossKleinschreibung() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(
            FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed 1")
        )

        let subscribed = await LocalExtensionBridgeServer.isSubscribed(
            "  HTTPS://EXAMPLE.COM/FEED.XML  ",
            database: database
        )

        #expect(subscribed == true)
    }

    @MainActor
    @Test func isSubscribedLiefertFalseFuerUnbekannteURL() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let subscribed = await LocalExtensionBridgeServer.isSubscribed(
            "https://example.com/unbekannt.xml",
            database: database
        )

        #expect(subscribed == false)
    }

    @MainActor
    @Test func addFeedFuegtNeuenFeedHinzu() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let result = await LocalExtensionBridgeServer.addFeed(
            "https://example.com/feed.xml",
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Test-Feed", description: nil, articles: [])
            }
        )

        #expect(result == .added)
        let feeds = try FeedStore(database: database).feeds()
        #expect(feeds.count == 1)
        #expect(feeds.first?.url == "https://example.com/feed.xml")
    }

    @MainActor
    @Test func addFeedLiefertAlreadyExistsBeiDuplikat() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let fetchFeed: @Sendable (String) async throws -> ParsedFeed = { url in
            ParsedFeed(sourceURL: url, title: "Test-Feed", description: nil, articles: [])
        }

        let firstResult = await LocalExtensionBridgeServer.addFeed(
            "https://example.com/feed.xml",
            database: database,
            fetchFeed: fetchFeed
        )
        #expect(firstResult == .added)

        let secondResult = await LocalExtensionBridgeServer.addFeed(
            "https://example.com/feed.xml",
            database: database,
            fetchFeed: fetchFeed
        )
        #expect(secondResult == .alreadyExists)
    }

    @MainActor
    @Test func addFeedLiefertErrorBeiFetchFehler() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let result = await LocalExtensionBridgeServer.addFeed(
            "https://example.com/feed.xml",
            database: database,
            fetchFeed: { _ in
                throw URLError(.notConnectedToInternet)
            }
        )

        guard case .error = result else {
            Issue.record("Erwartete .error, bekam \(result)")
            return
        }
    }
}
```

- [ ] **Step 2: Tests laufen lassen — müssen fehlschlagen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/LocalExtensionBridgeServerTests`
Expected: BUILD FAILED — `LocalExtensionBridgeServer` existiert noch nicht

- [ ] **Step 3: Implementiere `LocalExtensionBridgeServer`**

Erstelle `Feedivo/Services/LocalExtensionBridge/LocalExtensionBridgeServer.swift`:

```swift
import Foundation
import Network
import OSLog

// Minimaler, nur auf 127.0.0.1 lauschender HTTP-Server, den die Browser-
// Erweiterung (BrowserExtensions/Chrome/popup.js) abfragt, um den Abo-Status
// eines Feeds zu prüfen (GET /status) und Feeds direkt hinzuzufügen (POST
// /add) — ohne dass das App-Fenster in den Vordergrund muss. Läuft die App
// nicht, schlagen diese Requests einfach fehl (Connection refused); die
// Erweiterung fällt dann auf den bestehenden feedivo://add-Deep-Link zurück.
// Siehe docs/superpowers/specs/2026-07-13-browser-erweiterung-ux-design.md.
@MainActor
final class LocalExtensionBridgeServer {
    static let defaultPort: UInt16 = 51823

    private let port: UInt16
    private let router: LocalExtensionBridgeRouter
    private var listener: NWListener?

    init(database: FeedivoDatabase, port: UInt16 = LocalExtensionBridgeServer.defaultPort) {
        self.port = port
        self.router = LocalExtensionBridgeRouter(
            checkSubscribed: { urlString in
                await LocalExtensionBridgeServer.isSubscribed(urlString, database: database)
            },
            addFeed: { urlString in
                await LocalExtensionBridgeServer.addFeed(urlString, database: database)
            }
        )
    }

    func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            AppLogger.dataAccess.error("LocalExtensionBridgeServer: ungültiger Port \(self.port, privacy: .public)")
            return
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: nwPort
        )

        do {
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { state in
                if case let .failed(error) = state {
                    AppLogger.dataAccess.error("LocalExtensionBridgeServer: Listener fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            AppLogger.dataAccess.error("LocalExtensionBridgeServer: Start fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveLoop(connection: connection, buffer: Data())
    }

    private func receiveLoop(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            var newBuffer = buffer
            if let data, !data.isEmpty {
                newBuffer.append(data)
            }

            if let request = HTTPRequestParser.parse(newBuffer) {
                Task { @MainActor in
                    let response = await self.router.handle(request)
                    connection.send(content: response.serialize(), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
                return
            }

            if error != nil || isComplete {
                connection.cancel()
                return
            }

            self.receiveLoop(connection: connection, buffer: newBuffer)
        }
    }

    // Case-insensitiver, getrimmter Abgleich — bewusst nicht dieselbe private
    // Normalisierung wie SQLiteFeedSubscriptionService.normalizedFeedURL
    // wiederverwendet (dort privat), sondern dieselbe einfache Logik
    // (trim + lowercase) hier dupliziert.
    static func isSubscribed(_ urlString: String, database: FeedivoDatabase) async -> Bool {
        let normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        let feeds = (try? FeedStore(database: database).feeds()) ?? []
        return feeds.contains {
            $0.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    static func addFeed(
        _ urlString: String,
        database: FeedivoDatabase,
        fetchFeed: @escaping @Sendable (String) async throws -> ParsedFeed = FeedService.fetchFeed
    ) async -> LocalExtensionBridgeAddResult {
        let service = SQLiteFeedActionService(database: database, fetchFeed: fetchFeed)
        do {
            try await service.addFeed(
                urlString: urlString,
                refreshIntervalMinutes: BackgroundRefreshSettings.defaultIntervalMinutes
            )
            SQLiteDataInvalidation.bumpStatusVersion()
            return .added
        } catch SQLiteFeedSubscriptionError.duplicateFeed {
            return .alreadyExists
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Entitlement für ausgehenden Server ergänzen**

Öffne `Feedivo/Feedivo.entitlements` und füge NACH dem bestehenden `com.apple.security.network.client`-Eintrag hinzu:

```xml
	<key>com.apple.security.network.server</key>
	<true/>
```

Die Datei sieht danach so aus (Ausschnitt):

```xml
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
```

- [ ] **Step 5: Build + Tests laufen lassen — müssen bestehen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED (bei `NWListener`-API-Fehlern: Fehlermeldung lesen, Signatur/Label korrigieren, erneut bauen — siehe Hinweis oben)

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/LocalExtensionBridgeServerTests`
Expected: TEST SUCCEEDED — alle 6 Tests grün

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/LocalExtensionBridge/LocalExtensionBridgeServer.swift FeedivoTests/LocalExtensionBridgeServerTests.swift Feedivo/Feedivo.entitlements
git commit -m "Feature: Lokaler HTTP-Server fuer Browser-Erweiterung (Abo-Status, Feed hinzufuegen)"
```

---

### Task 6: Server beim App-Start starten

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`

**Interfaces:**
- Consumes: `LocalExtensionBridgeServer(database:)`, `.start()` aus Task 5.

- [ ] **Step 1: Server-Property ergänzen und in `init()` starten**

In `Feedivo/App/FeedivoApp.swift`, füge NACH der bestehenden Property `private let feedivoDatabase: FeedivoDatabase` (Zeile 43) hinzu:

```swift
    private let localExtensionBridgeServer: LocalExtensionBridgeServer
```

Füge in `init()` NACH `self.feedivoDatabase = database` (Zeile 53) hinzu:

```swift
        self.localExtensionBridgeServer = LocalExtensionBridgeServer(database: database)
```

Füge am Ende von `init()`, NACH dem bestehenden `self.appDelegate.configureMenubarController(...)`-Aufruf (Zeile 58), hinzu:

```swift
        self.localExtensionBridgeServer.start()
```

- [ ] **Step 2: Build ausführen — muss erfolgreich sein**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manuell verifizieren, dass der Server tatsächlich lauscht**

Baue und starte die App einmal in Xcode (Cmd+R). Führe dann im Terminal aus:

```bash
curl -s http://127.0.0.1:51823/status?url=https://example.com/nicht-vorhanden.xml
```

Expected: `{"subscribed":false}`

```bash
curl -s -X POST http://127.0.0.1:51823/add -H "Content-Type: application/json" -d '{"url":"nicht-erreichbar"}'
```

Expected: eine JSON-Antwort mit `"result":"error"` (Feed-Fetch schlägt fehl, da `nicht-erreichbar` keine gültige URL ist) — bestätigt, dass Requests tatsächlich beim Server ankommen und verarbeitet werden.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift
git commit -m "Feature: Lokalen Erweiterungs-Server beim App-Start starten"
```

---

### Task 7: Popup-UX (Status-Badges, Hinzufügen-Flow, visuelles Polish)

**Files:**
- Modify: `BrowserExtensions/Chrome/manifest.json`
- Modify: `BrowserExtensions/Chrome/popup.js`
- Modify: `BrowserExtensions/Chrome/popup.css`

**Interfaces:**
- Consumes: `GET http://127.0.0.1:51823/status?url=` → `{subscribed:boolean}`, `POST http://127.0.0.1:51823/add` (`{url}` → `{result:"added"|"alreadyExists"|"error", message?}`) aus Task 5/6. Bestehender `chrome.runtime.sendMessage({type:"feedivo-get-feeds-for-tab", tabId})`-Kanal aus `background.js` (unverändert, Task 2 lieferte bereits echte Titel).

- [ ] **Step 1: Berechtigungen in `manifest.json` ergänzen**

Füge in `BrowserExtensions/Chrome/manifest.json` NACH `"version": "1.0",` hinzu:

```json
    "permissions": ["activeTab"],
    "host_permissions": ["http://127.0.0.1:51823/*"],
```

- [ ] **Step 2: `popup.js` komplett ersetzen**

Ersetze den kompletten Inhalt von `BrowserExtensions/Chrome/popup.js`:

```javascript
const NO_FEEDS_TEXT = "Kein Feed auf dieser Seite gefunden.";
const LOCAL_SERVER_BASE_URL = "http://127.0.0.1:51823";
const STATUS_CHECK_TIMEOUT_MS = 300;

async function loadFeedsForActiveTab() {
    const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!activeTab?.id) {
        return { feeds: [], favIconUrl: undefined };
    }

    const response = await chrome.runtime.sendMessage({
        type: "feedivo-get-feeds-for-tab",
        tabId: activeTab.id
    });

    return { feeds: response?.feeds ?? [], favIconUrl: activeTab.favIconUrl };
}

async function fetchWithTimeout(url, options = {}, timeoutMs = STATUS_CHECK_TIMEOUT_MS) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    try {
        return await fetch(url, { ...options, signal: controller.signal });
    } finally {
        clearTimeout(timeoutId);
    }
}

// Fragt den lokalen Feedivo-Server (siehe LocalExtensionBridgeServer, App-
// seitig). Laeuft die App nicht oder antwortet der Server nicht rechtzeitig,
// wird das still als "nicht abonniert" gewertet - kein Fehlerzustand im Popup.
async function checkSubscribed(feedURL) {
    try {
        const response = await fetchWithTimeout(
            `${LOCAL_SERVER_BASE_URL}/status?url=${encodeURIComponent(feedURL)}`
        );
        if (!response.ok) {
            return false;
        }
        const data = await response.json();
        return data.subscribed === true;
    } catch {
        return false;
    }
}

async function addFeedViaLocalServer(feedURL) {
    try {
        const response = await fetchWithTimeout(`${LOCAL_SERVER_BASE_URL}/add`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ url: feedURL })
        });
        if (!response.ok && response.status !== 500) {
            return { result: "serverUnavailable" };
        }
        return await response.json();
    } catch {
        return { result: "serverUnavailable" };
    }
}

function createFeedRow(feed, favIconUrl, isSubscribed) {
    const row = document.createElement("div");
    row.className = "feed-row";

    if (favIconUrl) {
        const icon = document.createElement("img");
        icon.className = "feed-favicon";
        icon.src = favIconUrl;
        icon.alt = "";
        row.appendChild(icon);
    }

    const textColumn = document.createElement("div");
    textColumn.className = "feed-text";

    const label = document.createElement("span");
    label.className = "feed-title";
    label.textContent = feed.title;
    textColumn.appendChild(label);

    const urlLabel = document.createElement("span");
    urlLabel.className = "feed-url";
    urlLabel.textContent = feed.url;
    textColumn.appendChild(urlLabel);

    row.appendChild(textColumn);

    const button = document.createElement("button");
    row.appendChild(button);

    if (isSubscribed) {
        button.textContent = "Bereits in Feedivo";
        button.disabled = true;
        row.classList.add("feed-row--subscribed");
    } else {
        button.textContent = "Zu Feedivo hinzufügen";
        button.addEventListener("click", () => handleAddClick(feed, button, row));
    }

    return row;
}

async function handleAddClick(feed, button, row) {
    button.disabled = true;
    button.textContent = "Wird hinzugefügt …";

    const outcome = await addFeedViaLocalServer(feed.url);

    if (outcome.result === "added") {
        button.textContent = "✓ Hinzugefügt";
        row.classList.add("feed-row--added");
        setTimeout(() => window.close(), 1500);
        return;
    }

    if (outcome.result === "alreadyExists") {
        button.textContent = "✓ Bereits in Feedivo";
        row.classList.add("feed-row--added");
        setTimeout(() => window.close(), 1500);
        return;
    }

    if (outcome.result === "error") {
        button.disabled = false;
        button.textContent = "Fehler – erneut versuchen";
        return;
    }

    // "serverUnavailable": App laeuft nicht oder Server nicht erreichbar -
    // Fallback aufs bisherige Verhalten (App per Deep-Link starten, die den
    // Feed beim Start selbst hinzufuegt).
    chrome.tabs.create({ url: `feedivo://add?url=${encodeURIComponent(feed.url)}` });
    window.close();
}

async function renderFeeds({ feeds, favIconUrl }) {
    const list = document.getElementById("feed-list");
    list.innerHTML = "";

    if (feeds.length === 0) {
        const empty = document.createElement("p");
        empty.textContent = NO_FEEDS_TEXT;
        list.appendChild(empty);
        return;
    }

    const subscribedFlags = await Promise.all(feeds.map((feed) => checkSubscribed(feed.url)));

    feeds.forEach((feed, index) => {
        list.appendChild(createFeedRow(feed, favIconUrl, subscribedFlags[index]));
    });
}

loadFeedsForActiveTab().then(renderFeeds);
```

- [ ] **Step 3: `popup.css` um visuelles Polish ergänzen**

Füge in `BrowserExtensions/Chrome/popup.css` am Dateiende hinzu:

```css
.feed-favicon {
    width: 16px;
    height: 16px;
    border-radius: 3px;
    flex-shrink: 0;
}

.feed-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
}

.feed-url {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 11px;
    opacity: 0.6;
}

.feed-row--subscribed .feed-title,
.feed-row--added .feed-title {
    opacity: 0.75;
}
```

- [ ] **Step 4: Syntax-Check**

Run: `node --check BrowserExtensions/Chrome/popup.js && python3 -c "import json; json.load(open('BrowserExtensions/Chrome/manifest.json'))" && echo OK`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add BrowserExtensions/Chrome/manifest.json BrowserExtensions/Chrome/popup.js BrowserExtensions/Chrome/popup.css
git commit -m "Feature: Popup zeigt Abo-Status, echte Erfolgsrueckmeldung und Favicon"
```

---

### Task 8: Manuelle End-to-End-Verifikation

**Files:** keine Code-Änderungen — reine QA-Checkliste, da Browser-Interaktionen in dieser Umgebung nicht automatisierbar sind (kein computer-use für Browser-Erweiterungen).

- [ ] **Step 1: App bauen und starten**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

Starte die App danach einmal über Xcode (Cmd+R), damit der lokale Server läuft.

- [ ] **Step 2: Erweiterung in Chrome laden**

`chrome://extensions` öffnen → Entwicklermodus aktivieren → "Entpackt laden" → `BrowserExtensions/Chrome/` auswählen.

- [ ] **Step 3: Seite mit mehreren Feeds besuchen und Titel prüfen**

Eine Seite mit mindestens zwei unterscheidbaren Feeds öffnen (z. B. ein Blog mit "Alle Artikel" + "Kommentare"-Feed), Erweiterungs-Icon anklicken.

Erwartet: Beide Zeilen zeigen unterschiedliche, sinnvolle Namen (nicht mehr identisch mit dem Seitentitel), jeweils mit Favicon und URL-Zweitzeile.

- [ ] **Step 4: Hinzufügen-Flow bei laufender App prüfen**

Auf "Zu Feedivo hinzufügen" bei einem noch nicht abonnierten Feed klicken.

Erwartet: Button zeigt kurz "Wird hinzugefügt …", dann "✓ Hinzugefügt", Popup schließt sich nach ca. 1,5 s automatisch. Feed erscheint in der Feedivo-Sidebar, ohne dass das App-Fenster manuell aktiviert werden musste.

- [ ] **Step 5: Bereits-abonniert-Status prüfen**

Popup auf derselben Seite erneut öffnen.

Erwartet: Der eben hinzugefügte Feed zeigt jetzt "Bereits in Feedivo" (Button deaktiviert), statt erneut "Zu Feedivo hinzufügen" anzubieten.

- [ ] **Step 6: Fallback-Verhalten bei beendeter App prüfen**

Feedivo-App vollständig beenden (Cmd+Q). Popup auf einer Seite mit einem noch nicht abonnierten Feed öffnen und "Zu Feedivo hinzufügen" klicken.

Erwartet: Kein sichtbarer Fehler im Popup — stattdessen öffnet sich Feedivo (per `feedivo://add`-Deep-Link) wie vor diesem Feature, der Feed wird dort wie gehabt über das Hinzufügen-Sheet ergänzt.

- [ ] **Step 7: Ergebnis festhalten**

Bei Abweichungen von den Erwartungen: Befund notieren, betroffenen Task erneut öffnen und Ursache beheben, bevor der Plan als abgeschlossen gilt. Bei vollständigem Erfolg: keine weiteren Schritte nötig, Feature ist bereit für `CLAUDE.md`-Dokumentation (nicht Teil dieses Plans — separater Schritt nach Abschluss).
