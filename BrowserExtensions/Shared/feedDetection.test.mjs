import { test } from "node:test";
import assert from "node:assert/strict";
import {
    detectFeedsFromLinkTags,
    probeFallbackFeedPaths,
    detectFeeds,
    resolveFeedTitles,
    extractFeedTitleFromXML,
    extractFeedTitleFromJSON,
    extractFeedTitleFromContent
} from "./feedDetection.mjs";

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
