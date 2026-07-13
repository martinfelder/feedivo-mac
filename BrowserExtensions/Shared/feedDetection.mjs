const FEED_MIME_TYPES = new Set([
    "application/rss+xml",
    "application/atom+xml",
    "application/json",
    "application/feed+json"
]);

const FALLBACK_PATHS = ["/feed", "/rss", "/atom.xml"];

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

// Durchsucht das <head> der aktuellen Seite nach <link rel="alternate">-Tags
// mit einem RSS/Atom/JSON-Feed-Typ. `doc` ist injizierbar für Tests (Standard:
// globales `document`, verfügbar im Content-Script-Kontext der Erweiterung).
export function detectFeedsFromLinkTags(doc = document) {
    const links = Array.from(doc.querySelectorAll('link[rel="alternate"]'));
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
            title: link.getAttribute("title") || doc.title || href,
            url: new URL(href, doc.baseURI).href
        });
    }

    return feeds;
}

// Fallback-Heuristik, falls keine <link>-Tags gefunden wurden: prüft gängige
// Feed-Pfade relativ zur aktuellen Origin per HEAD-Request. `fetchImpl`
// injizierbar für Tests.
export async function probeFallbackFeedPaths(originURL, fetchImpl = fetch) {
    const origin = new URL(originURL).origin;
    const found = [];

    for (const path of FALLBACK_PATHS) {
        const candidateURL = origin + path;
        try {
            const response = await fetchImpl(candidateURL, { method: "HEAD" });
            if (response.ok) {
                found.push({ title: path, url: candidateURL });
            }
        } catch {
            // Netzwerkfehler oder CORS-Block: Pfad einfach überspringen.
        }
    }

    return found;
}

// Kombiniert beide Erkennungswege: <link>-Tags zuerst, Fallback-Heuristik nur
// wenn nichts gefunden wurde.
export async function detectFeeds(doc = document, fetchImpl = fetch) {
    const linkFeeds = detectFeedsFromLinkTags(doc);
    if (linkFeeds.length > 0) {
        return linkFeeds;
    }

    return probeFallbackFeedPaths(doc.baseURI, fetchImpl);
}
