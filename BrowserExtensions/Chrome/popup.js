const NO_FEEDS_TEXT = "Kein Feed auf dieser Seite gefunden.";
const LOCAL_SERVER_BASE_URL = "http://127.0.0.1:51823";
const STATUS_CHECK_TIMEOUT_MS = 300;
const ADD_FEED_TIMEOUT_MS = 5000;

// Fragt direkt das Content-Script der aktiven Seite statt den Cache im
// Hintergrund-Service-Worker: MV3 beendet Service Worker nach kurzer
// Inaktivitaet automatisch und verwirft dabei jeden In-Memory-Zustand,
// waehrend das Content-Script so lange lebt wie die Seite selbst.
async function loadFeedsForActiveTab() {
    const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!activeTab?.id) {
        return { feeds: [], favIconUrl: undefined };
    }

    try {
        const response = await chrome.tabs.sendMessage(activeTab.id, { type: "feedivo-get-feeds" });
        return { feeds: response?.feeds ?? [], favIconUrl: activeTab.favIconUrl };
    } catch {
        // Kein Content-Script in diesem Tab (z. B. chrome://-Seiten, PDF-
        // Viewer) oder Seite gerade erst geladen.
        return { feeds: [], favIconUrl: activeTab.favIconUrl };
    }
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
            `${LOCAL_SERVER_BASE_URL}/status?url=${encodeURIComponent(feedURL)}`,
            { headers: { "X-Feedivo-Extension": "1" } }
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
            headers: { "Content-Type": "application/json", "X-Feedivo-Extension": "1" },
            body: JSON.stringify({ url: feedURL })
        }, ADD_FEED_TIMEOUT_MS);
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
