# Original-Ansicht: Browser-Vor-/Zurück-Navigation

## Ziel

Feature 1.12 (FEATURES.md). Wenn die Original-Ansicht (WKWebView) aktiv ist und
der User innerhalb der angezeigten Website auf einen Link klickt, soll er über
neue Vor-/Zurück-Buttons in der Reader-Toolbar (plus `Cmd+[`/`Cmd+]`) wieder zur
vorherigen Seite in derselben WebView zurückkommen können.

## Bereits entschieden (FEATURES.md 1.12)

- Basis bleibt `WebContentView`/WKWebView — keine andere Engine.
- Neue `ControlGroup` mit Vor-/Zurück-Buttons in der bestehenden Reader-Toolbar,
  neben dem Anzeigemodus-Picker (Nativ/Original).
- Buttons bleiben immer sichtbar, sind aber deaktiviert wenn native Ansicht aktiv
  ist oder kein Verlauf vorhanden ist.
- Tastaturkürzel `Cmd+[` / `Cmd+]`.
- Wechsel zwischen Nativ- und Original-Ansicht setzt den Verlauf zurück.

## Neue technische Erkenntnis: Artikelwechsel-Grenze

`WebContentView` behält die WKWebView bewusst über Artikelwechsel hinweg bei
(Commit `eca556f93`, Fix für Reader-Spinner-Flash): Es gibt **kein**
`.id(articleID)` auf `WebContentView`. Beim Wechsel zu einem anderen Artikel
(Vor-/Zurück zwischen Artikeln, siehe Feature 1.2) ruft `Coordinator.loadIfReady()`
lediglich `webView.load(URLRequest(url: pendingURL))` auf einer **bestehenden**
WKWebView auf. Ein normales `load()` hängt an das existierende
`WKBackForwardList` an, statt es zu leeren.

**Konsequenz ohne Gegenmaßnahme:** Klickt der User in Artikel A auf einen Link,
wechselt dann zu Artikel B (weiterhin Original-Ansicht), würde "Zurück" ihn in
Artikel A hineinführen statt nur innerhalb von Artikel B zu navigieren — das
widerspricht dem eigentlichen Zweck des Features (In-Page-Navigation innerhalb
eines Artikels).

**Lösung — Boundary-Item-Ansatz (keine private API, kein WebView-Neubau):**
- Nach jedem **Top-Level-Load** (neuer Artikel oder Profilwechsel, erkennbar am
  bestehenden `hasProfileChange`/`loadedURL != pendingURL`-Pfad in
  `loadIfReady()`) merkt sich der `Coordinator` das dann aktuelle
  `webView.backForwardList.currentItem` als `articleLoadBoundaryItem`.
- `canGoBack` wird NICHT direkt aus `webView.canGoBack` übernommen, sondern über
  eine kleine reine Regel geklemmt:
  `canGoBack = webView.canGoBack && backForwardList.currentItem !== articleLoadBoundaryItem`.
- Solange der User innerhalb des aktuellen Artikels nicht weitergeklickt hat,
  ist `currentItem == articleLoadBoundaryItem` → `canGoBack` bleibt `false`,
  obwohl WKWebView intern noch ältere Einträge (aus vorherigen Artikeln) im
  Verlauf hätte.
- Klickt der User weiter (neuer `currentItem`), wird `canGoBack` `true`. Geht er
  zurück bis exakt zum `articleLoadBoundaryItem`, klemmt die Regel erneut auf
  `false` — ein weiteres "Zurück" (das in den vorherigen Artikel führen würde)
  ist über den Button nicht mehr erreichbar.
- `canGoForward` braucht keine eigene Klammerung: Ein Top-Level-`load()` während
  eines bestehenden Forward-Verlaufs verwirft laut WKWebView-Standardverhalten
  ohnehin den alten Forward-Zweig (wie bei jedem Browser), der neue
  Artikel-Load ist danach der neueste Eintrag ohne Forward-Ziel.

Diese Klemm-Entscheidung selbst (`a && !b`) wird als reine, testbare Funktion
extrahiert (`WebNavigationBoundary.canGoBack(webViewCanGoBack:isAtBoundary:)`),
da `WKBackForwardListItem`/`WKWebView` selbst nicht sinnvoll fakebar sind (keine
öffentlichen Initializer, nur aus einer echten WKWebView beziehbar). Die
Verdrahtung mit der echten WKWebView bleibt manuell zu verifizieren.

## Architektur

### Neuer Typ: `WebNavigationController`

`@Observable final class WebNavigationController` (Datei
`Feedivo/Views/Reader/WebContentView.swift`, direkt neben `WebContentView`):

```swift
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

- Owned als `@State private var webNavigationController = WebNavigationController()`
  in `SQLiteReaderView`, durchgereicht über `readerContent(articleID:database:)`
  → `ReaderModeContent` → `WebContentView(navigationController:)`.
- Bleibt über Artikelwechsel hinweg bestehen (kein `.id()`), genau wie die
  WKWebView selbst — passend zur bestehenden Architektur.

### `WebContentView` / `Coordinator`-Erweiterung

- Neuer Parameter `let navigationController: WebNavigationController`.
- `Coordinator` erhält `private var articleLoadBoundaryItem: WKBackForwardListItem?`.
- In `loadIfReady()`, direkt vor dem bestehenden `webView.load(URLRequest(url: pendingURL))`-Aufruf,
  bleibt die Logik unverändert; NACH erfolgreichem Laden (in
  `webView(_:didFinish:)`) wird zusätzlich geprüft, ob dieser `didFinish` von
  einem Top-Level-Load stammt (Flag `isAwaitingTopLevelLoadCompletion`, das
  `loadIfReady()` setzt, bevor es `load()` aufruft) — falls ja, wird
  `articleLoadBoundaryItem = webView.backForwardList.currentItem` neu gesetzt.
- Bei JEDEM `didFinish` (Top-Level-Load und In-Page-Navigation gleichermaßen)
  meldet der Coordinator den neuen Navigationszustand über
  `navigationController.updateState(canGoBack:canGoForward:)`, wobei
  `canGoBack` über `WebNavigationBoundary.canGoBack(...)` berechnet wird.
- `makeNSView` setzt `navigationController.webView = webView` einmalig.

### Neuer reiner Helper: `WebNavigationBoundary`

```swift
enum WebNavigationBoundary {
    static func canGoBack(webViewCanGoBack: Bool, isAtBoundary: Bool) -> Bool {
        webViewCanGoBack && !isAtBoundary
    }
}
```

### Toolbar-Erweiterung (`SQLiteReaderView.swift`)

Neue `ControlGroup` direkt vor dem bestehenden `Picker(L10n.readerDisplayModePicker, ...)`
(Zeile ~194):

```swift
ControlGroup {
    Button {
        webNavigationController.goBack()
    } label: {
        Image(systemName: "chevron.left")
    }
    .help(L10n.readerWebBackCommand)
    .keyboardShortcut("[", modifiers: .command)
    .disabled(readerDisplayMode != .web || !webNavigationController.canGoBack)

    Button {
        webNavigationController.goForward()
    } label: {
        Image(systemName: "chevron.right")
    }
    .help(L10n.readerWebForwardCommand)
    .keyboardShortcut("]", modifiers: .command)
    .disabled(readerDisplayMode != .web || !webNavigationController.canGoForward)
}
```

Zwei neue L10n-Keys (`reader.web.back`/`reader.web.forward`, de/en/fr/it) für die
Tooltip-Texte.

## Out of Scope

- Kein Verlaufs-Erhalt über Nativ-/Original-Moduswechsel hinweg (bereits
  entschieden).
- Keine eigene Mini-Browser-Leiste über der WebView (bereits entschieden).
- Keine Änderung an `ArticleWebContentBlocker`, `ArticleInAppWebProfile` oder
  der Load-Watchdog-Logik.

## Testing

- `WebNavigationBoundary.canGoBack(webViewCanGoBack:isAtBoundary:)` ist eine
  reine Funktion → Unit-Test in `FeedivoTests/WebNavigationBoundaryTests.swift`.
- `WebNavigationController.goBack()`/`.goForward()` und die
  Coordinator/WKWebView-Verdrahtung sind nicht sinnvoll unit-testbar
  (`WKBackForwardListItem`/`WKWebView` haben keine öffentlichen Initializer,
  keine Fakes möglich) → manuelle Verifikation in der laufenden App: Original-
  Ansicht öffnen, innerhalb der Seite einen Link anklicken, Zurück-Button prüft
  sich als aktiv, Zurück führt zur Artikel-Startseite und deaktiviert sich dort
  wieder (kein Leak in den vorherigen Artikel bei Artikelwechsel).
