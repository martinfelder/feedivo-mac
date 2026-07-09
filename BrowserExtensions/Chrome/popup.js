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
