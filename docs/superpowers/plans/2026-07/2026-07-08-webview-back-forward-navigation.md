# Original-Ansicht Vor-/Zurück-Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In der Original-Ansicht (WKWebView) Vor-/Zurück-Buttons in der Reader-
Toolbar plus `Cmd+[`/`Cmd+]` ergänzen, damit der User nach einem In-Page-
Linkklick wieder zur vorherigen Seite derselben Website zurückkommt — begrenzt
auf den aktuellen Artikel (kein Leak in den vorherigen Artikel bei
Artikelwechsel).

**Architecture:** Ein neuer `@Observable`-Typ `WebNavigationController` wird von
`SQLiteReaderView` als `@State` gehalten und bis zu `WebContentView`
durchgereicht. Der bestehende `WebContentView.Coordinator` meldet
`canGoBack`/`canGoForward` nach jedem `didFinish` an den Controller, geklemmt
über eine reine Helper-Funktion `WebNavigationBoundary.canGoBack(...)`, die
verhindert, dass "Zurück" über die Artikel-Grenze hinaus in den vorherigen
Artikel führt (siehe Spec, Abschnitt "Neue technische Erkenntnis").

**Tech Stack:** SwiftUI (macOS), WebKit (`WKWebView`/`WKBackForwardListItem`),
Swift Testing (`@Test`/`#expect`), `L10n.swift` + `Localizable.xcstrings`
(de/en/fr/it).

## Global Constraints

- Buttons bleiben immer sichtbar in der Reader-Toolbar, sind aber deaktiviert
  wenn native Ansicht aktiv ist oder kein Verlauf vorhanden ist (kein
  Ein-/Ausblenden, damit die Toolbar nicht springt).
- Tastaturkürzel `Cmd+[` (zurück) / `Cmd+]` (vor), analog zu Safari.
- Wechsel zwischen Nativ- und Original-Ansicht setzt den Verlauf zurück
  (bereits akzeptiertes Verhalten, ergibt sich automatisch aus der bestehenden
  `if readerDisplayMode == .web`-Bedingung, die `WebContentView` neu erzeugt).
- Kein Leak über Artikelgrenzen hinweg: "Zurück" darf nie in einen anderen
  Artikel als den aktuell angezeigten führen (siehe Boundary-Item-Ansatz).
- Keine private WebKit-API, kein Neubau der WKWebView pro Artikelwechsel
  (bestehende Performance-Optimierung aus Commit `eca556f93` bleibt erhalten).
- Kommentare im Code auf Deutsch (Projekt-Konvention).
- SourceKit-Diagnosen in der IDE sind oft veraltet/falsch — verlässlich ist nur
  ein echter `xcodebuild build`-Lauf.
- Volle Testsuite (`xcodebuild test` ohne `-only-testing`) hängt bekanntermaßen
  — immer gezielt mit `-only-testing:FeedivoTests/<SuiteName>` testen.

---

### Task 1: Reiner Boundary-Helper + Test

**Files:**
- Create: `Feedivo/Views/Reader/WebNavigationBoundary.swift`
- Test: `FeedivoTests/WebNavigationBoundaryTests.swift`

**Interfaces:**
- Produces: `WebNavigationBoundary.canGoBack(webViewCanGoBack: Bool, isAtBoundary: Bool) -> Bool`

- [ ] **Step 1: Schreibe den fehlschlagenden Test**

Erstelle `FeedivoTests/WebNavigationBoundaryTests.swift`:

```swift
import Testing
@testable import Feedivo

struct WebNavigationBoundaryTests {

    @Test func canGoBackIstFalseAnDerArtikelGrenze() {
        #expect(WebNavigationBoundary.canGoBack(webViewCanGoBack: true, isAtBoundary: true) == false)
    }

    @Test func canGoBackIstFalseOhneWebViewVerlauf() {
        #expect(WebNavigationBoundary.canGoBack(webViewCanGoBack: false, isAtBoundary: false) == false)
    }

    @Test func canGoBackIstTrueNachInPageNavigation() {
        #expect(WebNavigationBoundary.canGoBack(webViewCanGoBack: true, isAtBoundary: false) == true)
    }
}
```

- [ ] **Step 2: Test laufen lassen, um das Fehlschlagen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/WebNavigationBoundaryTests`
Expected: FAIL — `Cannot find 'WebNavigationBoundary' in scope`

- [ ] **Step 3: Minimale Implementierung schreiben**

Erstelle `Feedivo/Views/Reader/WebNavigationBoundary.swift`:

```swift
import Foundation

/// Entscheidet, ob der "Zurück"-Button in der Original-Ansicht aktiv sein darf.
/// `WebContentView` behält seine WKWebView bewusst über Artikelwechsel hinweg
/// bei (siehe Commit eca556f93 — Fix für den Reader-Spinner-Flash), daher
/// enthält `webView.backForwardList` nach einem Artikelwechsel weiterhin
/// Einträge des vorherigen Artikels. `isAtBoundary` markiert, ob der aktuelle
/// `WKBackForwardListItem` noch der beim Laden des aktuellen Artikels
/// gemerkte Startpunkt ist — solange das der Fall ist, hat der User innerhalb
/// dieses Artikels noch nicht weiternavigiert, und "Zurück" bleibt gesperrt,
/// auch wenn WKWebView selbst `canGoBack == true` meldet (weil älterer
/// Verlauf aus einem anderen Artikel existiert).
enum WebNavigationBoundary {
    static func canGoBack(webViewCanGoBack: Bool, isAtBoundary: Bool) -> Bool {
        webViewCanGoBack && !isAtBoundary
    }
}
```

- [ ] **Step 4: Test laufen lassen, um das Bestehen zu bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/WebNavigationBoundaryTests`
Expected: PASS (alle drei Tests grün)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Reader/WebNavigationBoundary.swift FeedivoTests/WebNavigationBoundaryTests.swift
git commit -m "Original-Ansicht: WebNavigationBoundary-Helper für Artikelgrenzen-Klemmung"
```

---

### Task 2: `WebNavigationController` + Coordinator-Verdrahtung in `WebContentView`

**Files:**
- Modify: `Feedivo/Views/Reader/WebContentView.swift`

**Interfaces:**
- Consumes: `WebNavigationBoundary.canGoBack(webViewCanGoBack:isAtBoundary:)` (Task 1)
- Produces: `WebNavigationController` (Klasse, `@Observable`, Properties
  `canGoBack: Bool`, `canGoForward: Bool` read-only von außen, Methoden
  `goBack()`, `goForward()`), neuer `WebContentView`-Parameter
  `navigationController: WebNavigationController`

Kein separater Unit-Test für diesen Task: `WKWebView`/`WKBackForwardListItem`
haben keine öffentlichen Initializer und lassen sich nicht faken (siehe Spec,
Abschnitt "Testing"). Verifikation erfolgt am Ende manuell in Task 4.

- [ ] **Step 1: `WebNavigationController` ergänzen**

Füge in `Feedivo/Views/Reader/WebContentView.swift` direkt nach dem
`import`-Block (nach `import OSLog`) folgenden neuen Typ ein:

```swift

/// Bündelt den Vor-/Zurück-Zustand der Original-Ansicht für die Reader-
/// Toolbar. Bleibt über Artikelwechsel hinweg als `@State` in
/// `SQLiteReaderView` bestehen — passend zur WKWebView, die aus
/// Performance-Gründen ebenfalls über Artikelwechsel hinweg weiterlebt
/// (siehe Commit eca556f93).
@Observable
final class WebNavigationController {
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    fileprivate weak var webView: WKWebView?

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    fileprivate func updateState(canGoBack: Bool, canGoForward: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }
}
```

- [ ] **Step 2: `WebContentView` um den neuen Parameter erweitern**

In derselben Datei die bestehende `struct WebContentView`-Deklaration und den
`init` ersetzen:

```swift
struct WebContentView: NSViewRepresentable {
    let url: URL
    let inAppProfile: ArticleInAppWebProfile
    let navigationController: WebNavigationController
    let onLoadFailure: () -> Void

    init(
        url: URL,
        inAppProfile: ArticleInAppWebProfile = .defaultProfile,
        navigationController: WebNavigationController,
        onLoadFailure: @escaping () -> Void = {}
    ) {
        self.url = url
        self.inAppProfile = inAppProfile
        self.navigationController = navigationController
        self.onLoadFailure = onLoadFailure
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(navigationController: navigationController, onLoadFailure: onLoadFailure)
    }
```

- [ ] **Step 3: `makeNSView` mit dem Controller verbinden**

Ersetze die bestehende `makeNSView`-Methode:

```swift
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = WKUserContentController()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        navigationController.webView = webView
        ArticleWebContentBlocker.install(into: configuration.userContentController) {
            context.coordinator.contentBlockerDidFinish()
        }
        return webView
    }
```

- [ ] **Step 4: Coordinator um Boundary-Tracking erweitern**

Ersetze die komplette bestehende `final class Coordinator`-Deklaration:

```swift
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?

        private let navigationController: WebNavigationController
        private var pendingURL: URL?
        private var pendingProfile: ArticleInAppWebProfile?
        private var loadedProfile: ArticleInAppWebProfile = .defaultProfile
        private var loadedURL: URL?
        private var isContentBlockerReady = false
        private var loadWatchTask: Task<Void, Never>?
        private var hasLoadSucceeded = false
        private var didNotifyLoadFailure = false
        private let onLoadFailure: () -> Void

        // Wird direkt vor jedem Top-Level-`load()` gesetzt (neuer Artikel
        // oder Profilwechsel) und in `didFinish` konsumiert, um dort den
        // neuen Artikel-Grenzpunkt zu setzen. Unterscheidet einen
        // Top-Level-Load von einer In-Page-Navigation (Linkklick), die
        // `didFinish` ebenfalls auslöst, aber die Grenze nicht verschieben
        // darf.
        private var isAwaitingTopLevelLoadCompletion = false
        private var articleLoadBoundaryItem: WKBackForwardListItem?

        init(navigationController: WebNavigationController, onLoadFailure: @escaping () -> Void) {
            self.navigationController = navigationController
            self.onLoadFailure = onLoadFailure
            super.init()
        }

        func update(url: URL, profile: ArticleInAppWebProfile, in webView: WKWebView) {
            self.webView = webView
            pendingURL = url
            pendingProfile = profile
            didNotifyLoadFailure = false
            loadIfReady()
        }

        func contentBlockerDidFinish() {
            isContentBlockerReady = true
            loadIfReady()
        }

        private func loadIfReady() {
            guard isContentBlockerReady,
                  let pendingURL,
                  let pendingProfile,
                  let webView
            else {
                return
            }

            let hasProfileChange = loadedProfile != pendingProfile
            if hasProfileChange {
                webView.customUserAgent = pendingProfile.customUserAgent
                loadedProfile = pendingProfile
            }

            guard loadedURL != pendingURL || hasProfileChange else {
                return
            }

            loadedURL = pendingURL
            hasLoadSucceeded = false
            didNotifyLoadFailure = false
            isAwaitingTopLevelLoadCompletion = true
            startLoadWatchdog(for: pendingURL)
            webView.load(URLRequest(url: pendingURL))
        }

        private func startLoadWatchdog(for url: URL) {
            loadWatchTask?.cancel()

            let urlInWatch = url
            loadWatchTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 18_000_000_000)

                await MainActor.run {
                    guard
                        let self,
                        self.loadedURL == urlInWatch,
                        !self.hasLoadSucceeded,
                        !self.didNotifyLoadFailure
                    else {
                        return
                    }

                    self.notifyFailure(nil)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasLoadSucceeded = true
            loadWatchTask?.cancel()

            if isAwaitingTopLevelLoadCompletion {
                isAwaitingTopLevelLoadCompletion = false
                articleLoadBoundaryItem = webView.backForwardList.currentItem
            }

            let isAtBoundary = webView.backForwardList.currentItem === articleLoadBoundaryItem
            navigationController.updateState(
                canGoBack: WebNavigationBoundary.canGoBack(
                    webViewCanGoBack: webView.canGoBack,
                    isAtBoundary: isAtBoundary
                ),
                canGoForward: webView.canGoForward
            )
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let _ = error
            notifyFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let _ = error
            notifyFailure(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            notifyFailure(nil)
        }

        private func notifyFailure(_ error: Error?) {
            loadWatchTask?.cancel()
            loadedURL = nil
            if didNotifyLoadFailure {
                return
            }

            didNotifyLoadFailure = true

            onLoadFailure()
        }
    }
}
```

Hinweis: `updateNSView` und `dismantleNSView` bleiben unverändert (`updateNSView`
ruft weiterhin nur `context.coordinator.update(url:profile:in:)` auf).

- [ ] **Step 5: Build laufen lassen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo | tail -40`
Expected: `** BUILD SUCCEEDED **`. Der Build schlägt an dieser Stelle noch fehl,
solange `SQLiteReaderView`/`ReaderModeContent` (Task 3) `WebContentView` noch
mit der alten Signatur (ohne `navigationController:`) aufrufen — das ist
erwartet und wird in Task 3 behoben. Falls der Build aus einem ANDEREN Grund
fehlschlägt (z. B. Tippfehler in dieser Datei), das zuerst beheben, bevor zu
Task 3 übergegangen wird.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Reader/WebContentView.swift
git commit -m "Original-Ansicht: WebNavigationController + Boundary-Tracking im Coordinator"
```

---

### Task 3: Toolbar-Buttons + Verdrahtung in `SQLiteReaderView`

**Files:**
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `WebNavigationController` (Task 2, `Feedivo/Views/Reader/WebContentView.swift`)
- Produces: keine neuen öffentlichen Symbole außerhalb dieser Datei — reine
  View-Verdrahtung

- [ ] **Step 1: Neue L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift` direkt nach Zeile 441
(`static let readerDisplayModeToggleHelp = String(localized: "reader.displayMode.toggle.help")`)
einfügen:

```swift
    static let readerWebBackCommand = String(localized: "reader.web.back.command")
    static let readerWebForwardCommand = String(localized: "reader.web.forward.command")
```

- [ ] **Step 2: Neue Einträge in Localizable.xcstrings ergänzen**

In `Feedivo/Resources/Localizable.xcstrings` direkt vor dem Eintrag
`"refreshStatus.collapse": {` (alphabetisch nach `"reader.titleLineSpacing.slider"`,
vor `"refreshStatus...` — `reader.` < `refresh...`) folgende zwei Einträge
einfügen:

```json
    "reader.web.back.command": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Zurück in der Original-Ansicht"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Back in original view"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Retour dans la vue originale"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Indietro nella vista originale"
          }
        }
      }
    },
    "reader.web.forward.command": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Vor in der Original-Ansicht"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Forward in original view"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Suivant dans la vue originale"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Avanti nella vista originale"
          }
        }
      }
    },
```

- [ ] **Step 3: `@State`-Property für den Controller ergänzen**

In `Feedivo/Views/Reader/SQLiteReaderView.swift` direkt nach Zeile 21
(`@State private var webContentLoadFailed = false`) einfügen:

```swift
    @State private var webNavigationController = WebNavigationController()
```

- [ ] **Step 4: Toolbar-ControlGroup ergänzen**

Direkt VOR dem bestehenden `Picker(L10n.readerDisplayModePicker, ...)`-Block
(aktuell ab Zeile 194) folgende neue `ControlGroup` einfügen:

```swift
                ControlGroup {
                    Button {
                        webNavigationController.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .help(L10n.readerWebBackCommand)
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(readerDisplayMode != .web || !webNavigationController.canGoBack)

                    Button {
                        webNavigationController.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .help(L10n.readerWebForwardCommand)
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(readerDisplayMode != .web || !webNavigationController.canGoForward)
                }

```

- [ ] **Step 5: Controller an `ReaderModeContent` durchreichen**

In derselben Datei die Funktion `readerContent(articleID:database:)` (aktuell
ab Zeile 308) erweitern — im `ReaderModeContent(...)`-Aufruf nach dem
Argument `webContentLoadFailed: $webContentLoadFailed,` folgende Zeile
einfügen:

```swift
            webNavigationController: webNavigationController,
```

- [ ] **Step 6: `ReaderModeContent` um den neuen Parameter erweitern**

Die `private struct ReaderModeContent: View`-Deklaration (aktuell ab Zeile 661)
um eine neue Property erweitern — nach `@Binding var webContentLoadFailed: Bool`
einfügen:

```swift
    let webNavigationController: WebNavigationController
```

- [ ] **Step 7: `WebContentView`-Aufruf in `ReaderModeContent.body` anpassen**

Den bestehenden Aufruf (aktuell ab Zeile 683):

```swift
                WebContentView(
                    url: originalURL,
                    inAppProfile: articleInAppWebProfile,
                    onLoadFailure: {
                        webContentLoadFailed = true
                    }
                )
```

ersetzen durch:

```swift
                WebContentView(
                    url: originalURL,
                    inAppProfile: articleInAppWebProfile,
                    navigationController: webNavigationController,
                    onLoadFailure: {
                        webContentLoadFailed = true
                    }
                )
```

- [ ] **Step 8: Build laufen lassen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo | tail -40`
Expected: `** BUILD SUCCEEDED **`. Ignoriere veraltete SourceKit-Diagnosen in
der IDE (siehe CLAUDE.md Gotchas) — nur der `xcodebuild`-Log zählt.

- [ ] **Step 9: Bestehende Reader-/WebNavigationBoundary-Tests laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/WebNavigationBoundaryTests -only-testing:FeedivoTests/SQLiteReaderStateTests`
Expected: PASS (alle Suiten grün — stellt sicher, dass die Verdrahtung den
bestehenden Reader-State nicht gebrochen hat)

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Views/Reader/SQLiteReaderView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Original-Ansicht: Vor-/Zurück-Buttons in der Reader-Toolbar verdrahtet"
```

---

### Task 4: Manuelle Verifikation in der laufenden App

**Files:** keine (nur Verifikation, keine Code-Änderung)

- [ ] **Step 1: App bauen und starten**

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build | tail -20
```
Expected: `** BUILD SUCCEEDED **`. Danach die gebaute App aus dem
DerivedData-Pfad öffnen (`open .../Build/Products/Debug/Feedivo.app`).

- [ ] **Step 2: Grundverhalten prüfen**

- Einen Artikel mit externem Link öffnen, zur Original-Ansicht wechseln.
- Vor-/Zurück-Buttons sind sichtbar aber deaktiviert (noch kein Verlauf).
- Innerhalb der Original-Ansicht auf einen Link klicken (zu einer Unterseite
  derselben Website navigieren).
- Zurück-Button wird aktiv; Klick (oder `Cmd+[`) führt zur Artikel-Startseite
  zurück und deaktiviert sich dort wieder.
- Vor-Button wird nach "Zurück" aktiv; Klick (oder `Cmd+]`) navigiert wieder
  zur Unterseite.

- [ ] **Step 3: Artikelgrenze prüfen (Kernszenario aus der Spec)**

- Im selben Artikel erneut auf einen Link klicken (Verlauf vorhanden).
- Zu einem ANDEREN Artikel wechseln (Vor-/Zurück zwischen Artikeln, Original-
  Ansicht bleibt aktiv).
- Zurück-Button muss beim neuen Artikel wieder DEAKTIVIERT sein (kein Leak in
  den vorherigen Artikel), obwohl die WKWebView intern weiterlebt.

- [ ] **Step 4: Moduswechsel prüfen**

- Innerhalb eines Artikels in der Original-Ansicht navigieren (Verlauf
  vorhanden, Zurück-Button aktiv).
- Zu Nativ wechseln, dann zurück zu Original.
- Zurück-Button ist wieder deaktiviert (Verlauf-Reset wie entschieden).

- [ ] **Step 5: Abschließender Commit-Check**

```bash
git log --oneline -5
git status --short
```
Expected: Die 3 Task-Commits sichtbar, Arbeitsverzeichnis sauber (abgesehen von
nicht-projektbezogenen Altbeständen).
