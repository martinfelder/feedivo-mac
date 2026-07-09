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

    async function detectFeeds() {
        const linkFeeds = detectFeedsFromLinkTags();
        if (linkFeeds.length > 0) {
            return linkFeeds;
        }

        return probeFallbackFeedPaths();
    }

    detectFeeds().then((feeds) => {
        chrome.runtime.sendMessage({ type: "feedivo-feeds-detected", feeds });
    });
})();
