# Browser-Erweiterung (Safari + Chrome) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safari- und Chrome-Erweiterungen bauen, die RSS/Atom-Feeds auf der
aktuell geöffneten Seite erkennen und per Klick über `feedivo://add?url=...`
direkt zu Feedivo hinzufügen (Feature 27, FEATURES.md Abschnitt 27.1/27.2).

**Architecture:** Eine reine, Node-testbare Erkennungslogik
(`BrowserExtensions/Shared/feedDetection.mjs`) dient als getestete
Referenzimplementierung. Da MV3-`content_scripts` in der Manifest-Deklaration
keine ES-Module unterstützen, wird dieselbe Logik zusätzlich als klassisches,
nicht-Modul-Script (`content.js`) in beide Erweiterungsordner kopiert — mit
Kommentar-Verweis auf die getestete Quelle. `content.js` meldet erkannte Feeds
per `chrome.runtime.sendMessage` an `background.js` (Service Worker), der pro
Tab merkt, ob Feeds gefunden wurden, und darüber das Action-Icon
aktiviert/deaktiviert (`chrome.action.enable`/`disable`). `popup.js` fragt
beim Öffnen die für den aktiven Tab gemerkten Feeds ab und rendert sie mit
je einem "Hinzufügen"-Button, der `feedivo://add?url=...` öffnet. Safari
unterstützt sowohl `browser.*` als auch `chrome.*` — durchgehend `chrome.*`
verwenden, damit `background.js`/`content.js`/`popup.*` zwischen beiden
Browsern **wortwörtlich identisch** sind (nur `manifest.json` unterscheidet
sich leicht: Safari braucht `_locales`/`__MSG_*__`, Chrome nicht).

**Tech Stack:** Manifest V3 (WebExtension-API, `chrome.*`-Namespace), Node.js
eingebauter Test-Runner (`node --test`, keine npm-Abhängigkeit), Xcode Safari
Web Extension Target (bereits angelegt, siehe Prerequisite unten), `sips`
(macOS-Bordmittel) zur Icon-Ableitung aus dem bestehenden App-Icon.

## Global Constraints

- Feed-Erkennung: `<link rel="alternate" type="application/rss+xml|atom+xml|json">`
  im `<head>`; Fallback-Heuristik auf `/feed`, `/rss`, `/atom.xml` relativ zur
  Origin, nur falls keine `<link>`-Tags gefunden wurden.
- Toolbar-/Action-Icon: inaktiv ohne erkannten Feed, aktiv sobald mindestens
  einer gefunden wurde. Klick auf ein inaktives Icon tut nichts (kein Popup).
- Klick auf aktives Icon öffnet Popup mit Liste aller gefundenen Feeds, je
  Eintrag ein "Zu Feedivo hinzufügen"-Button.
- Klick auf "Hinzufügen" öffnet `feedivo://add?url=...` (Feature 23.2, bereits
  umgesetzt und verifiziert) — zeigt die bestehende Vorschau vor dem
  Abonnieren (Feature 12.4). Keine eigene Subscribe-Logik in der Erweiterung.
- Chrome-Verteilung vorerst nur unsigned/Entwicklermodus (lokal geladen);
  Chrome-Web-Store-Veröffentlichung ist expliziter, späterer, nicht Teil
  dieser Umsetzung.
- **Prerequisite bereits erfüllt:** Safari-Web-Extension-Target
  `FeedivoSafariExtension` wurde manuell in Xcode angelegt (Embed in
  Feedivo.app), Bundle-ID `ch.martin.Feedivo.FeedivoSafariExtension`, Ordner
  `FeedivoSafariExtension/` mit Standard-Template-Dateien vorhanden.
- Projekt nutzt Xcode-16-File-System-Synchronized-Groups — neue/geänderte
  Dateien im `FeedivoSafariExtension/Resources/`-Ordner werden automatisch
  vom Target erfasst, keine manuelle `project.pbxproj`-Registrierung nötig.
- Kommentare im Code auf Deutsch (Projekt-Konvention).
- SourceKit-Diagnosen in der IDE sind oft veraltet/falsch — verlässlich ist
  nur ein echter `xcodebuild build`-Lauf (gilt für die Swift-Seite; die
  JS-Dateien haben kein SourceKit-Äquivalent).

---

### Task 1: Geteilte Feed-Erkennungslogik + Node-Tests

**Files:**
- Create: `BrowserExtensions/Shared/feedDetection.mjs`
- Test: `BrowserExtensions/Shared/feedDetection.test.mjs`

**Interfaces:**
- Produces: `detectFeedsFromLinkTags(doc = document) -> Array<{title: string, url: string}>`
- Produces: `probeFallbackFeedPaths(originURL: string, fetchImpl = fetch) -> Promise<Array<{title: string, url: string}>>`
- Produces: `detectFeeds(doc = document, fetchImpl = fetch) -> Promise<Array<{title: string, url: string}>>`
- Konsumiert von Task 2/3: `content.js` dupliziert dieselbe Logik als
  klassisches Script (siehe Architecture-Absatz oben) — dieses Modul ist die
  getestete Referenz, nicht direkt von den Erweiterungen importiert.

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Erstelle `BrowserExtensions/Shared/feedDetection.test.mjs`:

```js
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
```

- [ ] **Step 2: Test laufen lassen, um das Fehlschlagen zu bestätigen**

Run: `node --test BrowserExtensions/Shared/feedDetection.test.mjs`
Expected: FAIL — `Cannot find module './feedDetection.mjs'`

- [ ] **Step 3: Implementiere die Erkennungslogik**

Erstelle `BrowserExtensions/Shared/feedDetection.mjs`:

```js
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
```

- [ ] **Step 4: Test laufen lassen, um das Bestehen zu bestätigen**

Run: `node --test BrowserExtensions/Shared/feedDetection.test.mjs`
Expected: PASS (8 Tests grün)

- [ ] **Step 5: Commit**

```bash
git add BrowserExtensions/Shared/feedDetection.mjs BrowserExtensions/Shared/feedDetection.test.mjs
git commit -m "Browser-Erweiterung: geteilte Feed-Erkennungslogik + Node-Tests"
```

---

### Task 2: Chrome-Erweiterung (Manifest, Background, Popup, Icons)

**Files:**
- Create: `BrowserExtensions/Chrome/manifest.json`
- Create: `BrowserExtensions/Chrome/content.js`
- Create: `BrowserExtensions/Chrome/background.js`
- Create: `BrowserExtensions/Chrome/popup.html`
- Create: `BrowserExtensions/Chrome/popup.js`
- Create: `BrowserExtensions/Chrome/popup.css`
- Create: `BrowserExtensions/Chrome/images/icon-48.png`, `icon-96.png`, `icon-128.png`

**Interfaces:**
- Konsumiert: dupliziert die Logik aus Task 1s `feedDetection.mjs` (siehe
  Kommentar in `content.js`)
- Produces: vollständige, ladbare Chrome-Erweiterung unter `BrowserExtensions/Chrome/`

- [ ] **Step 1: Icons aus dem bestehenden App-Icon ableiten**

```bash
mkdir -p BrowserExtensions/Chrome/images
sips -z 48 48 Feedivo/Assets.xcassets/AppIcon.appiconset/1024.png --out BrowserExtensions/Chrome/images/icon-48.png
sips -z 96 96 Feedivo/Assets.xcassets/AppIcon.appiconset/1024.png --out BrowserExtensions/Chrome/images/icon-96.png
sips -z 128 128 Feedivo/Assets.xcassets/AppIcon.appiconset/1024.png --out BrowserExtensions/Chrome/images/icon-128.png
```

Expected: drei PNG-Dateien in `BrowserExtensions/Chrome/images/` mit den
jeweiligen Pixelmaßen (per `sips -g pixelWidth -g pixelHeight <datei>` prüfbar).

- [ ] **Step 2: `manifest.json` erstellen**

Erstelle `BrowserExtensions/Chrome/manifest.json`:

```json
{
    "manifest_version": 3,
    "name": "Feedivo",
    "description": "Fügt RSS-/Atom-Feeds der aktuellen Seite direkt zu Feedivo hinzu.",
    "version": "1.0",

    "icons": {
        "48": "images/icon-48.png",
        "96": "images/icon-96.png",
        "128": "images/icon-128.png"
    },

    "background": {
        "service_worker": "background.js"
    },

    "content_scripts": [{
        "matches": ["http://*/*", "https://*/*"],
        "js": ["content.js"],
        "run_at": "document_idle"
    }],

    "action": {
        "default_popup": "popup.html",
        "default_icon": {
            "48": "images/icon-48.png",
            "96": "images/icon-96.png",
            "128": "images/icon-128.png"
        }
    },

    "permissions": ["tabs"]
}
```

- [ ] **Step 3: `content.js` erstellen**

Erstelle `BrowserExtensions/Chrome/content.js`:

```js
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
```

- [ ] **Step 4: `background.js` erstellen**

Erstelle `BrowserExtensions/Chrome/background.js`:

```js
// Merkt sich die zuletzt von content.js gemeldeten Feeds pro Tab, damit
// popup.js sie ohne erneuten Seiten-Scan anzeigen kann.
const feedsByTabId = new Map();

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message?.type === "feedivo-feeds-detected" && sender.tab?.id) {
        const tabId = sender.tab.id;
        const feeds = message.feeds ?? [];
        feedsByTabId.set(tabId, feeds);

        if (feeds.length > 0) {
            chrome.action.enable(tabId);
        } else {
            chrome.action.disable(tabId);
        }
        return;
    }

    if (message?.type === "feedivo-get-feeds-for-tab") {
        sendResponse({ feeds: feedsByTabId.get(message.tabId) ?? [] });
        return true;
    }
});

chrome.tabs.onRemoved.addListener((tabId) => {
    feedsByTabId.delete(tabId);
});

// Beim Navigieren auf eine neue Seite im selben Tab: alten Stand verwerfen
// und Icon deaktivieren, bis content.js für die neue Seite erneut meldet.
// Verhindert, dass das Icon kurzzeitig den Zustand der vorherigen Seite zeigt.
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
    if (changeInfo.status === "loading") {
        feedsByTabId.delete(tabId);
        chrome.action.disable(tabId);
    }
});
```

- [ ] **Step 5: `popup.html`, `popup.js`, `popup.css` erstellen**

Erstelle `BrowserExtensions/Chrome/popup.html`:

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <link rel="stylesheet" href="popup.css">
</head>
<body>
    <strong>Feeds auf dieser Seite</strong>
    <div id="feed-list"></div>
    <script src="popup.js"></script>
</body>
</html>
```

Erstelle `BrowserExtensions/Chrome/popup.js`:

```js
const NO_FEEDS_TEXT = "Kein Feed auf dieser Seite gefunden.";

async function loadFeedsForActiveTab() {
    const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!activeTab?.id) {
        return [];
    }

    const response = await chrome.runtime.sendMessage({
        type: "feedivo-get-feeds-for-tab",
        tabId: activeTab.id
    });

    return response?.feeds ?? [];
}

function renderFeeds(feeds) {
    const list = document.getElementById("feed-list");
    list.innerHTML = "";

    if (feeds.length === 0) {
        const empty = document.createElement("p");
        empty.textContent = NO_FEEDS_TEXT;
        list.appendChild(empty);
        return;
    }

    for (const feed of feeds) {
        const row = document.createElement("div");
        row.className = "feed-row";

        const label = document.createElement("span");
        label.className = "feed-title";
        label.textContent = feed.title;

        const button = document.createElement("button");
        button.textContent = "Zu Feedivo hinzufügen";
        button.addEventListener("click", () => {
            chrome.tabs.create({ url: `feedivo://add?url=${encodeURIComponent(feed.url)}` });
            window.close();
        });

        row.appendChild(label);
        row.appendChild(button);
        list.appendChild(row);
    }
}

loadFeedsForActiveTab().then(renderFeeds);
```

Erstelle `BrowserExtensions/Chrome/popup.css`:

```css
:root {
    color-scheme: light dark;
}

body {
    width: 260px;
    padding: 12px;
    font-family: system-ui;
}

.feed-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-top: 8px;
}

.feed-title {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13px;
}

button {
    font: inherit;
    padding: 4px 8px;
    cursor: pointer;
}
```

- [ ] **Step 6: Manuell in Chrome laden und auf Ladefehler prüfen**

`chrome://extensions` öffnen, Entwicklermodus aktivieren, "Entpackte
Erweiterung laden" → `BrowserExtensions/Chrome/` auswählen.
Expected: Erweiterung erscheint ohne Fehlermeldung in der Liste, Icon (aus
Task-1-Icons) sichtbar in der Toolbar.

- [ ] **Step 7: Commit**

```bash
git add BrowserExtensions/Chrome/
git commit -m "Browser-Erweiterung: Chrome-Erweiterung (Manifest, Background, Popup, Icons)"
```

---

### Task 3: Safari-Erweiterung (Template-Dateien ersetzen)

**Files:**
- Modify: `FeedivoSafariExtension/Resources/manifest.json`
- Modify: `FeedivoSafariExtension/Resources/content.js`
- Modify: `FeedivoSafariExtension/Resources/background.js`
- Modify: `FeedivoSafariExtension/Resources/popup.html`
- Modify: `FeedivoSafariExtension/Resources/popup.js`
- Modify: `FeedivoSafariExtension/Resources/popup.css`
- Modify: `FeedivoSafariExtension/Resources/_locales/en/messages.json`
- Modify: `FeedivoSafariExtension/Resources/images/icon-48.png`, `icon-96.png`,
  `icon-128.png`, `icon-256.png`, `icon-512.png`

**Interfaces:**
- Konsumiert: identischer Inhalt wie Task 2s Chrome-Dateien (Safari
  unterstützt `chrome.*` als Alias zu `browser.*`)

- [ ] **Step 1: Icons aus dem bestehenden App-Icon ableiten (überschreibt Xcodes Platzhalter)**

```bash
sips -z 48 48 Feedivo/Assets.xcassets/AppIcon.appiconset/1024.png --out FeedivoSafariExtension/Resources/images/icon-48.png
sips -z 96 96 Feedivo/Assets.xcassets/AppIcon.appiconset/1024.png --out FeedivoSafariExtension/Resources/images/icon-96.png
sips -z 128 128 Feedivo/Assets.xcassets/AppIcon.appiconset/1024.png --out FeedivoSafariExtension/Resources/images/icon-128.png
sips -z 256 256 Feedivo/Assets.xcassets/AppIcon.appiconset/1024.png --out FeedivoSafariExtension/Resources/images/icon-256.png
sips -z 512 512 Feedivo/Assets.xcassets/AppIcon.appiconset/1024.png --out FeedivoSafariExtension/Resources/images/icon-512.png
```

`images/toolbar-icon.svg` (Xcodes generisches Monochrom-Symbol für die
Toolbar) bewusst unverändert lassen — ein sauberes Vektor-Icon daraus
abzuleiten ist Bild-/Design-Arbeit, kein Code-Task; als bekannte, rein
kosmetische Lücke in FEATURES.md vermerken (Task 5).

- [ ] **Step 2: `manifest.json` ersetzen**

Ersetze den Inhalt von `FeedivoSafariExtension/Resources/manifest.json`
(aktuell Xcodes Template mit `"matches": ["*://example.com/*"]` und ohne
`permissions`) durch:

```json
{
    "manifest_version": 3,
    "default_locale": "en",

    "name": "__MSG_extension_name__",
    "description": "__MSG_extension_description__",
    "version": "1.0",

    "icons": {
        "48": "images/icon-48.png",
        "96": "images/icon-96.png",
        "128": "images/icon-128.png",
        "256": "images/icon-256.png",
        "512": "images/icon-512.png"
    },

    "background": {
        "scripts": [ "background.js" ],
        "type": "module"
    },

    "content_scripts": [{
        "matches": [ "http://*/*", "https://*/*" ],
        "js": [ "content.js" ],
        "run_at": "document_idle"
    }],

    "action": {
        "default_popup": "popup.html",
        "default_icon": "images/toolbar-icon.svg"
    },

    "permissions": [ "tabs" ]
}
```

- [ ] **Step 3: `content.js`, `background.js`, `popup.html`, `popup.js`, `popup.css` ersetzen**

Ersetze jeweils den kompletten Inhalt der 5 Dateien mit exakt dem Inhalt der
gleichnamigen Dateien aus `BrowserExtensions/Chrome/` (Task 2, Steps 3-5) —
wortwörtlich identisch, keine Anpassungen nötig.

- [ ] **Step 4: `_locales/en/messages.json` aktualisieren**

Ersetze `FeedivoSafariExtension/Resources/_locales/en/messages.json`:

```json
{
    "extension_name": {
        "message": "Feedivo",
        "description": "The display name for the extension."
    },
    "extension_description": {
        "message": "Fügt RSS-/Atom-Feeds der aktuellen Seite direkt zu Feedivo hinzu.",
        "description": "Description of what the extension does."
    }
}
```

- [ ] **Step 5: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **` (Scheme bleibt `Feedivo`, nicht das
Extension-Scheme — die Extension wird als Teil des Haupt-Targets mitgebaut).

- [ ] **Step 6: Commit**

```bash
git add FeedivoSafariExtension/
git commit -m "Browser-Erweiterung: Safari-Extension-Template durch echte Logik ersetzt"
```

---

### Task 4: Manuelle End-to-End-Verifikation (Safari + Chrome)

**Files:**
- Modify: `FEATURES.md:1294-1334` (Abschnitt `## 27. Browser-Erweiterung`,
  Status auf ✔️ Fertig)

**Interfaces:**
- Konsumiert: gebaute Feedivo.app mit eingebetteter Safari-Extension (Task 3)
  und geladene Chrome-Erweiterung (Task 2)

- [ ] **Step 1: Safari-Erweiterung aktivieren**

Feedivo.app einmal starten (registriert die Extension bei Safari). Dann in
Safari: **Safari → Einstellungen → Erweiterungen** (bzw. auf neueren
macOS-Versionen: **Systemeinstellungen → Allgemein → Anmeldeobjekte &
Erweiterungen → Safari-Erweiterungen**) → "Feedivo" aktivieren.

- [ ] **Step 2: Safari — Feed-Erkennung testen**

In Safari `https://daringfireball.net/feeds/main` sichtbar als Feed-Quelle
öffnen, dazu am besten `https://daringfireball.net` (die Website selbst,
nicht die Feed-URL direkt) besuchen. Screenshot: Icon soll aktiv sein, Klick
öffnet Popup mit gefundenem Feed. Klick auf "Zu Feedivo hinzufügen":
Feedivo aktiviert sich, Add-Feed-Sheet öffnet mit vorausgefüllter URL und
automatisch geladener Vorschau (Feature 23.2 + 12.4).

- [ ] **Step 3: Safari — Seite ohne Feed testen**

Eine Seite ohne erkennbaren Feed öffnen (z. B. `https://example.com`).
Screenshot: Icon soll inaktiv bleiben, Klick öffnet kein Popup.

- [ ] **Step 4: Chrome — Erweiterung laden und testen**

Falls noch nicht aus Task 2 Step 6 geladen: `chrome://extensions` →
Entwicklermodus → "Entpackte Erweiterung laden" → `BrowserExtensions/Chrome/`.
Dieselben zwei Szenarien wie Step 2/3 wiederholen (Feed-Seite → Icon aktiv,
Popup, Hinzufügen-Flow; Seite ohne Feed → Icon inaktiv), jeweils mit
Screenshot bestätigen.

- [ ] **Step 5: FEATURES.md Status aktualisieren**

Im Abschnitt `## 27. Browser-Erweiterung (RSS-Feed hinzufügen)`:
- `### 27.1 Safari-Erweiterung`: Status von
  `✅ Entschieden — bereit zur Implementierung` auf `✔️ Fertig` ändern,
  Bullet ergänzen:
  `**Umgesetzt 2026-07-09:** Xcode-Target FeedivoSafariExtension, geteilte
  Erkennungslogik (BrowserExtensions/Shared/feedDetection.mjs, Node-getestet),
  Popup + Background-Service-Worker; bekannte kosmetische Lücke:
  toolbar-icon.svg bleibt Xcodes generisches Platzhalter-Symbol`
- `### 27.2 Chrome-Erweiterung`: Status auf `✔️ Fertig`, Bullet ergänzen:
  `**Umgesetzt 2026-07-09:** BrowserExtensions/Chrome/, identischer Code wie
  Safari (chrome.*-Namespace funktioniert in beiden Browsern), vorerst nur
  unsigned/Entwicklermodus geladen — Chrome-Web-Store-Veröffentlichung offen`

- [ ] **Step 6: Commit**

```bash
git add FEATURES.md
git commit -m "FEATURES.md: Feature 27 (Browser-Erweiterung) als erledigt markiert"
```
