// Aktiviert/deaktiviert nur noch das Symbol in der Symbolleiste je nachdem,
// ob content.js auf der aktuellen Seite Feeds gefunden hat. Die Feeds selbst
// werden hier NICHT mehr zwischengespeichert: MV3 beendet diesen Service
// Worker nach kurzer Inaktivitaet automatisch und wuerde jeden In-Memory-
// Cache verwerfen — ein zweites Oeffnen des Popups kurz nach dem ersten fand
// dann faelschlich keine Feeds mehr (Nutzer-Report 2026-07-13). popup.js
// fragt die Feeds deshalb direkt beim Content-Script der aktiven Seite ab
// (das so lange lebt wie die Seite selbst), nicht mehr hier.
chrome.runtime.onMessage.addListener((message, sender) => {
    if (message?.type === "feedivo-feeds-detected" && sender.tab?.id) {
        const tabId = sender.tab.id;
        const feeds = message.feeds ?? [];

        if (feeds.length > 0) {
            chrome.action.enable(tabId);
        } else {
            chrome.action.disable(tabId);
        }
    }
});

// Beim Navigieren auf eine neue Seite im selben Tab: Icon deaktivieren, bis
// content.js für die neue Seite erneut meldet. Verhindert, dass das Icon
// kurzzeitig den Zustand der vorherigen Seite zeigt.
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
    if (changeInfo.status === "loading") {
        chrome.action.disable(tabId);
    }
});
