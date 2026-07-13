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
