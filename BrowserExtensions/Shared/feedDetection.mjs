const FEED_MIME_TYPES = new Set([
    "application/rss+xml",
    "application/atom+xml",
    "application/json",
    "application/feed+json"
]);

const FALLBACK_PATHS = ["/feed", "/rss", "/atom.xml"];

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
