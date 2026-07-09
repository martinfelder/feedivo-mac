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
