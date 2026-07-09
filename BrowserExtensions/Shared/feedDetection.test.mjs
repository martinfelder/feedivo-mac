import { test } from "node:test";
import assert from "node:assert/strict";
import { detectFeedsFromLinkTags, probeFallbackFeedPaths, detectFeeds } from "./feedDetection.mjs";

function fakeDocument({ title = "Beispiel-Seite", baseURI = "https://example.com/artikel", links = [] } = {}) {
    return {
        title,
        baseURI,
        querySelectorAll(selector) {
            assert.equal(selector, 'link[rel="alternate"]');
            return links.map((attrs) => ({
                getAttribute(name) {
                    return attrs[name] ?? null;
                }
            }));
        }
    };
}

test("detectFeedsFromLinkTags erkennt einen RSS-Feed-Link", () => {
    const doc = fakeDocument({
        links: [
            { type: "application/rss+xml", href: "/feed.xml", title: "Mein Feed" }
        ]
    });

    assert.deepEqual(detectFeedsFromLinkTags(doc), [
        { title: "Mein Feed", url: "https://example.com/feed.xml" }
    ]);
});

test("detectFeedsFromLinkTags ignoriert Links mit falschem Typ", () => {
    const doc = fakeDocument({
        links: [{ type: "text/css", href: "/style.css" }]
    });

    assert.deepEqual(detectFeedsFromLinkTags(doc), []);
});

test("detectFeedsFromLinkTags nutzt den Seitentitel, wenn kein title-Attribut vorhanden ist", () => {
    const doc = fakeDocument({
        title: "Fallback-Titel",
        links: [{ type: "application/atom+xml", href: "/atom.xml" }]
    });

    assert.deepEqual(detectFeedsFromLinkTags(doc), [
        { title: "Fallback-Titel", url: "https://example.com/atom.xml" }
    ]);
});

test("detectFeedsFromLinkTags liefert eine leere Liste ohne Links", () => {
    assert.deepEqual(detectFeedsFromLinkTags(fakeDocument()), []);
});

test("probeFallbackFeedPaths findet erreichbare Pfade", async () => {
    const fakeFetch = async (url) => ({ ok: url.endsWith("/feed") });

    assert.deepEqual(
        await probeFallbackFeedPaths("https://example.com/artikel", fakeFetch),
        [{ title: "/feed", url: "https://example.com/feed" }]
    );
});

test("probeFallbackFeedPaths ignoriert Netzwerkfehler still", async () => {
    const fakeFetch = async () => {
        throw new Error("Netzwerkfehler");
    };

    assert.deepEqual(
        await probeFallbackFeedPaths("https://example.com/artikel", fakeFetch),
        []
    );
});

test("detectFeeds bevorzugt Link-Tags vor der Fallback-Heuristik", async () => {
    const doc = fakeDocument({
        links: [{ type: "application/rss+xml", href: "/feed.xml", title: "Feed" }]
    });
    const fetchImpl = async () => {
        throw new Error("sollte nicht aufgerufen werden");
    };

    assert.deepEqual(await detectFeeds(doc, fetchImpl), [
        { title: "Feed", url: "https://example.com/feed.xml" }
    ]);
});

test("detectFeeds nutzt die Fallback-Heuristik, wenn keine Link-Tags gefunden wurden", async () => {
    const doc = fakeDocument({ links: [] });
    const fetchImpl = async (url) => ({ ok: url.endsWith("/rss") });

    assert.deepEqual(await detectFeeds(doc, fetchImpl), [
        { title: "/rss", url: "https://example.com/rss" }
    ]);
});
