# Native Artikelliste (NSTableView-Migration) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beide Artikellisten der App (Hauptliste `SQLiteFeedArticleListView` und
Suchfenster-Ergebnisliste `ArticleSearchWindowView`) bekommen eine NSTableView-basierte,
reine-AppKit-Zellen-Implementierung als Alternative zur bisherigen SwiftUI `List`, hinter
einem gemeinsamen Settings-Schalter, der auch im Release-Build funktioniert.

**Architecture:** Neue, eigenständige Dateien unter `Feedivo/Views/ArticleList/Native/`
(kein `#if DEBUG`). Reine AppKit-Zellen (`NSTableCellView`-Subklassen) statt gehosteter
SwiftUI-Views — sichert den Performance-Zweck der Migration. Kontextmenüs über
`NSMenuDelegate` + `tableView.clickedRow`. Der bestehende Render-Benchmark-Spike
(`Feedivo/Views/ArticleList/RenderBenchmark/`, `#if DEBUG`) bleibt unangetastet und dient
weiterhin als Regressionswächter für sich selbst — die neue Produktivimplementierung ist
komplett eigenständiger Code, der an einigen Stellen bewusst denselben, bereits
reviewten Bauplan (`NativeArticleImageLoadGuard`, Cell-Reuse-Pattern) wiederverwendet.

**Tech Stack:** Swift, AppKit (`NSTableView`, `NSTableCellView`, `NSMenu`), SwiftUI
(`NSViewRepresentable`), Swift Testing (`@Test`/`#expect`, kein XCTest), GRDB/SQLite
(unverändert, keine Datenschicht-Änderung in diesem Plan).

## Global Constraints

- Mindest-macOS 14.0 Sonoma (CLAUDE.md Tech-Stack) — keine APIs verwenden, die neuer sind.
- Deutsche Kommentare im Code, nur wo das WARUM nicht aus dem Code selbst hervorgeht
  (CLAUDE.md Entwickler-Kontext).
- Swift Testing (`@Test`, `#expect`), kein XCTest. Jede Testsuite, die eine echte
  `NSTableView`/`NSWindow`/`NSView`-Instanz konstruiert oder `reloadData()`/
  `selectRowIndexes`/`deselectAll` aufruft, MUSS `@MainActor` auf der `@Suite`-Struct
  tragen — das `FeedivoTests`-Target hat kein `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  (siehe CLAUDE.md-Gotcha, exakt wie `NativeArticleTableViewCoordinatorTests`).
- Volle Testsuite (`xcodebuild test` ohne `-only-testing`) hängt reproduzierbar — jeder
  Testlauf in diesem Plan verwendet gezielt `-only-testing:FeedivoTests/<SuiteName>` und
  `-parallel-testing-enabled NO`.
- Neue `L10n.swift`-Konstanten, die nur indirekt referenziert werden (nicht als direktes
  String-Literal in `Text(...)`), werden von Xcodes Build NICHT automatisch in
  `Localizable.xcstrings` gestubt — jeder solche neue Key wird in diesem Plan manuell per
  Text-Segment-Einfügung direkt nach dem `"strings" : {`-Anker ergänzt (kein
  `json.load`/`json.dump`-Roundtrip der Gesamtdatei) und per `grep -c` verifiziert.
- Der bestehende Render-Benchmark-Spike unter `Feedivo/Views/ArticleList/RenderBenchmark/`
  (inkl. seiner Tests) bleibt in diesem Plan vollständig unangetastet.
- Die bestehende SwiftUI-`List`-Implementierung in `SQLiteFeedArticleListView.swift` und
  `ArticleSearchWindowView.swift` wird NICHT gelöscht — beide Pfade koexistieren hinter
  dem neuen Schalter.
- Branch `feature/native-article-list-nstableview` ist bereits erstellt und ausgecheckt,
  die Spec ist dort bereits committet. Jeder Task in diesem Plan endet mit einem eigenen
  Commit auf diesem Branch.
- Neuer Produktivcode liegt unter `Feedivo/Views/ArticleList/Native/` (kein `#if DEBUG`).

---

## Task 1: Settings-Schalter für die native Artikelliste

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Views/Settings/SettingsView.swift:677-682` (nach dem bestehenden
  `restoreReaderTabsOnLaunch`-Toggle in `ArticleListSettingsView`)
- Test: `FeedivoTests/ViewModels/ArticleListDisplaySettingsTests.swift`

**Interfaces:**
- Produces: `NativeArticleListSettings.isEnabledKey: String` (UserDefaults-Key),
  `NativeArticleListSettings.defaultIsEnabled: Bool` (= `false`) — wird von Task 5 und
  Task 8 gelesen (`@AppStorage(NativeArticleListSettings.isEnabledKey)`).

- [ ] **Step 1: Settings-Enum ergänzen**

In `Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift`, am Dateiende ergänzen:

```swift
/// Ob die Hauptartikelliste und die Suchfenster-Ergebnisliste über eine
/// NSTableView-basierte, reine-AppKit-Implementierung statt der
/// SwiftUI-`List` gerendert werden (siehe docs/superpowers/specs/2026-08/
/// 2026-08-04-native-article-list-nstableview-design.md). Ein gemeinsamer
/// Schalter für beide Listen, Standard AUS bis zur Live-Verifikation.
enum NativeArticleListSettings {
    static let isEnabledKey = "articleList.usesNativeTableView"
    static let defaultIsEnabled = false
}
```

- [ ] **Step 2: L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach der Zeile mit
`settingsArticleListRestoreTabsOnLaunchTitle` (Zeile 335) ergänzen:

```swift
    static let settingsArticleListUsesNativeTableViewTitle = LocalizedStringKey("settings.articleList.usesNativeTableView.title")
    static let settingsArticleListUsesNativeTableViewDescription = LocalizedStringKey("settings.articleList.usesNativeTableView.description")
```

- [ ] **Step 3: Localizable.xcstrings-Einträge ergänzen**

In `Feedivo/Resources/Localizable.xcstrings` direkt nach der Zeile `"strings" : {`
(Zeile 3) folgenden Text-Block einfügen (reine Text-Segment-Einfügung, KEIN
`json.load`/`json.dump`-Roundtrip der Gesamtdatei — siehe Global Constraints):

```json
    "settings.articleList.usesNativeTableView.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Native Artikelliste (Beta)"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Native Article List (Beta)"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Liste d'articles native (bêta)"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Elenco articoli nativo (beta)"
          }
        }
      }
    },
    "settings.articleList.usesNativeTableView.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Rendert die Artikelliste über eine schnellere, native AppKit-Ansicht statt der bisherigen SwiftUI-Liste. Beta — bei Problemen einfach wieder deaktivieren."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Renders the article list using a faster, native AppKit view instead of the current SwiftUI list. Beta — just turn it off again if something looks wrong."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Affiche la liste d'articles via une vue AppKit native plus rapide au lieu de la liste SwiftUI actuelle. Bêta — désactivez-la simplement en cas de problème."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Visualizza l'elenco articoli tramite una vista AppKit nativa più veloce invece dell'attuale elenco SwiftUI. Beta — disattivala semplicemente in caso di problemi."
          }
        }
      }
    },
```

- [ ] **Step 4: Einträge verifizieren**

Run: `grep -c '"settings.articleList.usesNativeTableView.title"' Feedivo/Resources/Localizable.xcstrings`
Expected: `1`

Run: `grep -c '"settings.articleList.usesNativeTableView.description"' Feedivo/Resources/Localizable.xcstrings`
Expected: `1`

Run: `git diff --stat Feedivo/Resources/Localizable.xcstrings`
Expected: nur Insertions (keine oder kaum Deletions) — bestätigt, dass keine
versehentliche Gesamtformatierung der Datei stattgefunden hat.

- [ ] **Step 5: Toggle in den Einstellungen ergänzen**

In `Feedivo/Views/Settings/SettingsView.swift`, `ArticleListSettingsView` (Zeile 602 ff.):
neue `@AppStorage`-Property direkt nach der bestehenden
`restoreReaderTabsOnLaunch`-Property (nach Zeile 622) ergänzen:

```swift
    @AppStorage(NativeArticleListSettings.isEnabledKey)
    private var usesNativeArticleList = NativeArticleListSettings.defaultIsEnabled
```

Direkt nach dem bestehenden `restoreReaderTabsOnLaunch`-Toggle-Block (Zeilen 677-682,
vor der schließenden `}` von `GeneralSettingsSection` in Zeile 684) ergänzen:

```swift

                Toggle(isOn: $usesNativeArticleList) {
                    Text(L10n.settingsArticleListUsesNativeTableViewTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                GeneralSettingsHelp(L10n.settingsArticleListUsesNativeTableViewDescription)
```

- [ ] **Step 6: Test ergänzen**

In `FeedivoTests/ViewModels/ArticleListDisplaySettingsTests.swift`, am Ende der
bestehenden `struct ArticleListDisplaySettingsTests { ... }` (vor der schließenden `}`)
ergänzen:

```swift

    @Test func nativeArticleListSettingsDefaultIstAus() {
        #expect(NativeArticleListSettings.defaultIsEnabled == false)
        #expect(NativeArticleListSettings.isEnabledKey == "articleList.usesNativeTableView")
    }
```

- [ ] **Step 7: Build + Test ausführen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListDisplaySettingsTests -parallel-testing-enabled NO`
Expected: alle Tests grün, inkl. der neuen `nativeArticleListSettingsDefaultIstAus`.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift \
  Feedivo/Resources/L10n.swift \
  Feedivo/Resources/Localizable.xcstrings \
  Feedivo/Views/Settings/SettingsView.swift \
  FeedivoTests/ViewModels/ArticleListDisplaySettingsTests.swift
git commit -m "feat: Settings-Schalter für native Artikelliste (Beta)"
```

---

## Task 2: Produktiv-Zelle für die Hauptartikelliste (`NativeArticleRowCellView`)

**Files:**
- Create: `Feedivo/Views/ArticleList/Native/NativeArticleRowCellView.swift`
- Test: `FeedivoTests/Views/ArticleList/Native/NativeArticleRowCellViewTests.swift`

**Interfaces:**
- Consumes: `ArticleListSnapshot` (`Feedivo/Snapshots/ArticleListSnapshot.swift`),
  `InterfaceTextSize` (`.scaled(_ value: CGFloat) -> CGFloat`,
  `Feedivo/Resources/InterfaceTextSize.swift`), `ArticleListImagePosition`,
  `ArticleListFeedNamePosition`, `ArticleDateDisplayMode`
  (`Feedivo/Views/ArticleList/ArticleListDisplaySettings.swift`),
  `Date.feedivoDisplay(mode: ArticleDateDisplayMode) -> String`
  (`Feedivo/Extensions/Date+RelativeDisplay.swift`), `ImageCacheService.shared.image(for:targetPixelSize:)`
  und `.image(for:)` (async), `NativeArticleImageLoadGuard.shouldApplyLoadedImage(requestedToken:currentToken:)`
  (`Feedivo/Views/ArticleList/RenderBenchmark/NativeArticleImageLoadGuard.swift`,
  bleibt unverändert, wird nur importiert/aufgerufen), `L10n.articleRowUnreadText`,
  `L10n.articleRowStarredText`, `L10n.articleRowStarAdd`, `L10n.articleRowStarRemove`
  (`Feedivo/Resources/L10n.swift`).
- Produces: `NativeArticleRowCellView` (finale Klasse, `NSTableCellView`-Subklasse) mit
  `func configure(with snapshot: ArticleListSnapshot, interfaceTextSize: InterfaceTextSize,
  imagePosition: ArticleListImagePosition, feedNamePosition: ArticleListFeedNamePosition,
  showsFeedName: Bool, summaryLineCount: Int, dateDisplayMode: ArticleDateDisplayMode,
  onToggleStarred: @escaping () -> Void)`. Statische, pure Hilfsfunktionen
  `static func metadataText(feedTitle: String?, publishedAt: Date?, showsFeedNameAndFavicon: Bool, dateDisplayMode: ArticleDateDisplayMode) -> String`
  und `static func accessibilityLabel(for snapshot: ArticleListSnapshot) -> String` —
  Task 3 (Coordinator) ruft nur `configure(...)` auf, keine weiteren Details nötig.

**Hinweis zur Testbarkeit:** Analog zum bereits reviewten Spike-Muster bleiben die
Subviews (`titleField`, `previewImageView`, etc.) `private` — volle visuelle Parität
(Bildposition/Feedname-Position/Zusammenfassungszeilen tatsächlich sichtbar richtig
platziert) wird gemäß Spec manuell live verifiziert, nicht headless (siehe
Testing-Strategie der Spec: "Kein Anspruch, SwiftUI-List-Rendering selbst zu
vergleichen — unmöglich headless"). Automatisiert getestet werden ausschließlich die
beiden reinen, isolierten Formatierungsfunktionen `metadataText` und
`accessibilityLabel`.

- [ ] **Step 1: Fehlschlagende Tests für die reinen Formatierungsfunktionen schreiben**

Neue Datei `FeedivoTests/Views/ArticleList/Native/NativeArticleRowCellViewTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct NativeArticleRowCellViewTests {
    @Test func metadataTextKombiniertFeednameUndDatumMitTrennzeichen() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let text = NativeArticleRowCellView.metadataText(
            feedTitle: "Beispiel-Feed",
            publishedAt: date,
            showsFeedNameAndFavicon: true,
            dateDisplayMode: .absolute
        )
        #expect(text == "Beispiel-Feed · \(date.feedivoDisplay(mode: .absolute))")
    }

    @Test func metadataTextLaesstFeednameWegWennNichtGezeigt() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let text = NativeArticleRowCellView.metadataText(
            feedTitle: "Beispiel-Feed",
            publishedAt: date,
            showsFeedNameAndFavicon: false,
            dateDisplayMode: .absolute
        )
        #expect(text == date.feedivoDisplay(mode: .absolute))
    }

    @Test func metadataTextIstLeerOhneFeednameUndDatum() {
        let text = NativeArticleRowCellView.metadataText(
            feedTitle: nil,
            publishedAt: nil,
            showsFeedNameAndFavicon: true,
            dateDisplayMode: .relative
        )
        #expect(text == "")
    }

    @Test func accessibilityLabelEnthaeltUngelesenUndSternHinweise() {
        let snapshot = ArticleListSnapshot(
            id: "1", feedID: "f1", feedTitle: "Feed", title: "Titel",
            summary: nil, link: nil, imageURL: nil, publishedAt: nil,
            arrivedAt: Date(), estimatedReadingMinutes: nil,
            isRead: false, isStarred: true, isArchived: false,
            isHidden: false, faviconURL: nil
        )
        let label = NativeArticleRowCellView.accessibilityLabel(for: snapshot)
        #expect(label == "Titel, \(L10n.articleRowUnreadText), \(L10n.articleRowStarredText)")
    }

    @Test func accessibilityLabelIstNurTitelWennGelesenUndOhneStern() {
        let snapshot = ArticleListSnapshot(
            id: "1", feedID: "f1", feedTitle: "Feed", title: "Titel",
            summary: nil, link: nil, imageURL: nil, publishedAt: nil,
            arrivedAt: Date(), estimatedReadingMinutes: nil,
            isRead: true, isStarred: false, isArchived: false,
            isHidden: false, faviconURL: nil
        )
        let label = NativeArticleRowCellView.accessibilityLabel(for: snapshot)
        #expect(label == "Titel")
    }
}
```

- [ ] **Step 2: Testlauf verifizieren, dass er fehlschlägt (Typ existiert noch nicht)**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleRowCellViewTests -parallel-testing-enabled NO`
Expected: FAIL — `Cannot find 'NativeArticleRowCellView' in scope` (Compile-Fehler).

- [ ] **Step 3: `NativeArticleRowCellView` implementieren**

Neue Datei `Feedivo/Views/ArticleList/Native/NativeArticleRowCellView.swift`:

```swift
import AppKit

/// Reine AppKit-Zelle für die native Hauptartikelliste (Produktiv-Pendant zum
/// `#if DEBUG`-Render-Benchmark-Spike unter `RenderBenchmark/`, bewusst als
/// eigenständige Klasse — kein Umbau des Spike-Codes). Volle Parität mit
/// `ArticleRowView` (SwiftUI-Baseline): Bildposition, Feedname-Position,
/// variable Zusammenfassungszeilen, Datumsanzeige-Modus, Barrierefreiheit.
final class NativeArticleRowCellView: NSTableCellView {
    private let unreadIndicator = NSView()
    private let previewImageView = NSImageView()
    private let faviconImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let metadataField = NSTextField(labelWithString: "")
    private let summaryField = NSTextField(labelWithString: "")
    private let starButton = NSButton(image: NSImage(), target: nil, action: nil)

    private lazy var metadataRow = NSStackView(views: [faviconImageView, metadataField])
    private lazy var textStack = NSStackView(views: [titleField, metadataRow, summaryField])
    private lazy var rootStack = NSStackView(views: [unreadIndicator, previewImageView, textStack, starButton])

    private var previewImageWidthConstraint: NSLayoutConstraint!
    private var previewImageHeightConstraint: NSLayoutConstraint!
    private var faviconWidthConstraint: NSLayoutConstraint!
    private var faviconHeightConstraint: NSLayoutConstraint!
    private var starButtonWidthConstraint: NSLayoutConstraint!
    private var starButtonHeightConstraint: NSLayoutConstraint!

    /// Erhöht sich bei jedem `configure(...)`-Aufruf — dient
    /// `NativeArticleImageLoadGuard` als "aktueller Stand dieser Zelle".
    private var currentLoadToken = 0
    private var starButtonAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    private func configureLayout() {
        rootStack.orientation = .horizontal
        rootStack.alignment = .top
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 6
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)

        metadataRow.orientation = .horizontal
        metadataRow.alignment = .centerY
        metadataRow.spacing = 4

        unreadIndicator.wantsLayer = true
        unreadIndicator.layer?.cornerRadius = 4
        NSLayoutConstraint.activate([
            unreadIndicator.widthAnchor.constraint(equalToConstant: 8),
            unreadIndicator.heightAnchor.constraint(equalToConstant: 8)
        ])

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageWidthConstraint = previewImageView.widthAnchor.constraint(equalToConstant: 56)
        previewImageHeightConstraint = previewImageView.heightAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([previewImageWidthConstraint, previewImageHeightConstraint])

        faviconImageView.imageScaling = .scaleProportionallyUpOrDown
        faviconWidthConstraint = faviconImageView.widthAnchor.constraint(equalToConstant: 11)
        faviconHeightConstraint = faviconImageView.heightAnchor.constraint(equalToConstant: 11)
        NSLayoutConstraint.activate([faviconWidthConstraint, faviconHeightConstraint])

        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingTail

        metadataField.font = .systemFont(ofSize: 11)
        metadataField.textColor = .secondaryLabelColor

        summaryField.font = .systemFont(ofSize: 13)
        summaryField.textColor = .secondaryLabelColor
        summaryField.lineBreakMode = .byTruncatingTail

        starButton.imagePosition = .imageOnly
        starButton.isBordered = false
        starButton.target = self
        starButton.action = #selector(starButtonTapped)
        starButtonWidthConstraint = starButton.widthAnchor.constraint(equalToConstant: 24)
        starButtonHeightConstraint = starButton.heightAnchor.constraint(equalToConstant: 24)
        NSLayoutConstraint.activate([starButtonWidthConstraint, starButtonHeightConstraint])
    }

    func configure(
        with snapshot: ArticleListSnapshot,
        interfaceTextSize: InterfaceTextSize,
        imagePosition: ArticleListImagePosition,
        feedNamePosition: ArticleListFeedNamePosition,
        showsFeedName: Bool,
        summaryLineCount: Int,
        dateDisplayMode: ArticleDateDisplayMode,
        onToggleStarred: @escaping () -> Void
    ) {
        currentLoadToken += 1
        let loadToken = currentLoadToken
        starButtonAction = onToggleStarred

        previewImageWidthConstraint.constant = interfaceTextSize.scaled(56)
        previewImageHeightConstraint.constant = interfaceTextSize.scaled(56)
        faviconWidthConstraint.constant = interfaceTextSize.scaled(11)
        faviconHeightConstraint.constant = interfaceTextSize.scaled(11)
        starButtonWidthConstraint.constant = interfaceTextSize.scaled(24)
        starButtonHeightConstraint.constant = interfaceTextSize.scaled(24)

        unreadIndicator.layer?.backgroundColor = snapshot.isRead
            ? NSColor.clear.cgColor
            : NSColor.controlAccentColor.cgColor

        titleField.stringValue = snapshot.title
        titleField.font = .systemFont(ofSize: interfaceTextSize.scaled(14), weight: snapshot.isRead ? .regular : .semibold)
        titleField.textColor = snapshot.isRead ? .secondaryLabelColor : .labelColor

        let showsFeedNameAndFavicon = showsFeedName && (snapshot.feedTitle.isEmpty == false)
        metadataField.font = .systemFont(ofSize: interfaceTextSize.scaled(11))
        metadataField.stringValue = Self.metadataText(
            feedTitle: snapshot.feedTitle,
            publishedAt: snapshot.publishedAt,
            showsFeedNameAndFavicon: showsFeedNameAndFavicon,
            dateDisplayMode: dateDisplayMode
        )
        metadataRow.isHidden = metadataField.stringValue.isEmpty
        faviconImageView.isHidden = !showsFeedNameAndFavicon

        summaryField.font = .systemFont(ofSize: interfaceTextSize.scaled(13))
        summaryField.maximumNumberOfLines = summaryLineCount
        if let summary = snapshot.summary, !summary.isEmpty, summaryLineCount > 0 {
            summaryField.stringValue = summary
            summaryField.isHidden = false
        } else {
            summaryField.stringValue = ""
            summaryField.isHidden = true
        }

        // Reihenfolge Titel/Metadaten-Zeile im Textstapel spiegeln
        // ArticleListFeedNamePosition (vor/nach dem Titel) — identisch zu
        // `ArticleRowView`s `feedNamePosition == .beforeTitle`-Verzweigung.
        textStack.removeArrangedSubview(titleField)
        textStack.removeArrangedSubview(metadataRow)
        textStack.removeArrangedSubview(summaryField)
        if feedNamePosition == .beforeTitle {
            textStack.addArrangedSubview(metadataRow)
            textStack.addArrangedSubview(titleField)
        } else {
            textStack.addArrangedSubview(titleField)
            textStack.addArrangedSubview(metadataRow)
        }
        textStack.addArrangedSubview(summaryField)

        // Bildposition links/rechts/aus spiegeln ArticleListImagePosition —
        // identisch zu `ArticleRowView`s `imagePosition == .left`-Verzweigung.
        rootStack.removeArrangedSubview(unreadIndicator)
        rootStack.removeArrangedSubview(previewImageView)
        rootStack.removeArrangedSubview(textStack)
        rootStack.removeArrangedSubview(starButton)
        previewImageView.isHidden = imagePosition == .hidden
        switch imagePosition {
        case .left:
            rootStack.addArrangedSubview(previewImageView)
            rootStack.addArrangedSubview(textStack)
        case .right, .hidden:
            rootStack.addArrangedSubview(textStack)
            if imagePosition == .right {
                rootStack.addArrangedSubview(previewImageView)
            }
        }
        rootStack.addArrangedSubview(starButton)
        rootStack.insertArrangedSubview(unreadIndicator, at: 0)

        starButton.image = NSImage(
            systemSymbolName: snapshot.isStarred ? "star.fill" : "star",
            accessibilityDescription: snapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd
        )

        previewImageView.image = nil
        faviconImageView.image = nil

        if imagePosition != .hidden, let imageURLString = snapshot.imageURL, let imageURL = URL(string: imageURLString) {
            let side = interfaceTextSize.scaled(56)
            Task { [weak self] in
                let image = await ImageCacheService.shared.image(
                    for: imageURL,
                    targetPixelSize: CGSize(width: side * 2, height: side * 2)
                )
                guard let self,
                      NativeArticleImageLoadGuard.shouldApplyLoadedImage(
                          requestedToken: loadToken,
                          currentToken: self.currentLoadToken
                      )
                else { return }
                self.previewImageView.image = image
            }
        }

        if showsFeedNameAndFavicon, let faviconURLString = snapshot.faviconURL, let faviconURL = URL(string: faviconURLString) {
            Task { [weak self] in
                let image = await ImageCacheService.shared.image(for: faviconURL)
                guard let self,
                      NativeArticleImageLoadGuard.shouldApplyLoadedImage(
                          requestedToken: loadToken,
                          currentToken: self.currentLoadToken
                      )
                else { return }
                self.faviconImageView.image = image
            }
        }

        setAccessibilityLabel(Self.accessibilityLabel(for: snapshot))
    }

    static func metadataText(
        feedTitle: String?,
        publishedAt: Date?,
        showsFeedNameAndFavicon: Bool,
        dateDisplayMode: ArticleDateDisplayMode
    ) -> String {
        let feedNamePart = showsFeedNameAndFavicon ? feedTitle : nil
        return [feedNamePart, publishedAt?.feedivoDisplay(mode: dateDisplayMode)]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    static func accessibilityLabel(for snapshot: ArticleListSnapshot) -> String {
        var parts = [snapshot.title]
        if !snapshot.isRead {
            parts.append(L10n.articleRowUnreadText)
        }
        if snapshot.isStarred {
            parts.append(L10n.articleRowStarredText)
        }
        return parts.joined(separator: ", ")
    }

    @objc private func starButtonTapped() {
        starButtonAction?()
    }
}
```

- [ ] **Step 4: Testlauf verifizieren, dass alle Tests grün sind**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleRowCellViewTests -parallel-testing-enabled NO`
Expected: alle 5 Tests grün.

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/ArticleList/Native/NativeArticleRowCellView.swift \
  FeedivoTests/Views/ArticleList/Native/NativeArticleRowCellViewTests.swift
git commit -m "feat: NativeArticleRowCellView — Produktiv-Zelle mit voller ArticleRowView-Parität"
```

---

## Task 3: Coordinator für die Hauptartikelliste (`NativeArticleListCoordinator`)

**Files:**
- Create: `Feedivo/Views/ArticleList/Native/NativeArticleListCoordinator.swift`
- Create: `Feedivo/Views/ArticleList/Native/NativeArticleListTrailingRowCellViews.swift`
- Test: `FeedivoTests/Views/ArticleList/Native/NativeArticleListCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ArticleListSnapshot`, `ArticleOriginalURLResolver.hasUsableWebLink(_ link: String?) -> Bool`
  (`Feedivo/ViewModels/ArticleURLHelpers.swift`), `NativeArticleRowCellView.configure(...)`
  (Task 2), `L10n.articleRowMarkUnread/.articleRowMarkRead/.articleRowStarRemove/
  .articleRowStarAdd/.articleUnarchiveCommand/.articleArchiveCommand/
  .articleAssignTagCommand/.articleCreateRuleCommand/.articleOpenInNewTabCommand/
  .articleOpenInWindowCommand/.articleCopyLinkCommand/.articleOpenOriginalCommand/
  .articleShareCommand/.articleExportCommand/.articleDeleteCommand/
  .articleMarkAllReadCommand/.articleListShowReadButtonFormat` (alle bereits vorhanden
  in `Feedivo/Resources/L10n.swift`, identisch zu `ArticleRowView.contextMenu`).
- Produces: `NativeArticleListCoordinator` (finale Klasse, `NSObject`,
  `NSTableViewDataSource`, `NSTableViewDelegate`, `NSMenuDelegate`) mit öffentlichen
  Properties `rows: [ArticleListSnapshot]`, `hasMoreIndicatorVisible: Bool`,
  `showReadArticlesButtonCount: Int?` (nil = Button nicht anzeigen),
  `hasAvailableTags: Bool`, `interfaceTextSize: InterfaceTextSize`,
  `imagePosition: ArticleListImagePosition`, `feedNamePosition: ArticleListFeedNamePosition`,
  `showsFeedName: Bool`, `summaryLineCount: Int`, `dateDisplayMode: ArticleDateDisplayMode`,
  `onSelectionChanged: ((String?) -> Void)?` und je ein optionaler Closure pro Aktion
  (`onToggleRead`, `onToggleStarred`, `onToggleArchived`, `onRequestAssignTag`,
  `onOpenInNewTab`, `onOpenInWindow`, `onExport`: alle `((String) -> Void)?`;
  `onCreateRule`, `onCopyLink`, `onOpenOriginal`, `onShareOriginal`, `onDelete`: alle
  `((ArticleListSnapshot) -> Void)?`; `onMarkAllRead`, `onLoadMore`,
  `onShowReadArticles`: alle `(() -> Void)?`). Öffentliche, pure Methode
  `func buildContextMenu(for snapshot: ArticleListSnapshot) -> NSMenu` — direkt testbar
  ohne Klick-Simulation. Enum `TrailingRowKind: Equatable { case loadMoreIndicator,
  showReadArticlesButton(count: Int) }` und Methode
  `func rowKind(atRow row: Int) -> RowKind` mit `enum RowKind: Equatable { case content(ArticleListSnapshot), trailing(TrailingRowKind) }`
  — Task 4 (`NativeArticleListTableView`) setzt die Properties und liest nur
  `numberOfRows(in:)`/`tableView(_:viewFor:row:)` über die Standard-Delegate-Protokolle.

- [ ] **Step 1: Fehlschlagende Tests schreiben**

Neue Datei `FeedivoTests/Views/ArticleList/Native/NativeArticleListCoordinatorTests.swift`:

```swift
import AppKit
import Testing
@testable import Feedivo

// @MainActor zwingend nötig — echte NSTableView-Instanzen, siehe Global Constraints.
@Suite("NativeArticleListCoordinator")
@MainActor
struct NativeArticleListCoordinatorTests {
    private func makeSnapshot(id: String = "a1", link: String? = "https://example.com", isRead: Bool = false, isStarred: Bool = false, isArchived: Bool = false) -> ArticleListSnapshot {
        ArticleListSnapshot(
            id: id, feedID: "f1", feedTitle: "Feed", title: "Titel \(id)",
            summary: nil, link: link, imageURL: nil, publishedAt: nil,
            arrivedAt: Date(), estimatedReadingMinutes: nil,
            isRead: isRead, isStarred: isStarred, isArchived: isArchived,
            isHidden: false, faviconURL: nil
        )
    }

    @Test func numberOfRowsZaehltInhaltUndTrailingRowsZusammen() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.rows = [makeSnapshot(id: "a1"), makeSnapshot(id: "a2")]
        coordinator.hasMoreIndicatorVisible = true
        coordinator.showReadArticlesButtonCount = 5

        #expect(coordinator.numberOfRows(in: NSTableView()) == 4)
    }

    @Test func rowKindLiefertContentFuerInhaltsZeilen() {
        let coordinator = NativeArticleListCoordinator()
        let snapshot = makeSnapshot(id: "a1")
        coordinator.rows = [snapshot]

        #expect(coordinator.rowKind(atRow: 0) == .content(snapshot))
    }

    @Test func rowKindLiefertLoadMoreVorShowReadButton() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.rows = [makeSnapshot(id: "a1")]
        coordinator.hasMoreIndicatorVisible = true
        coordinator.showReadArticlesButtonCount = 3

        #expect(coordinator.rowKind(atRow: 1) == .trailing(.loadMoreIndicator))
        #expect(coordinator.rowKind(atRow: 2) == .trailing(.showReadArticlesButton(count: 3)))
    }

    @Test func rowKindOhneTrailingRowsIstNilAusserhalbDerRows() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.rows = [makeSnapshot(id: "a1")]

        #expect(coordinator.rowKind(atRow: 1) == nil)
    }

    @Test func tableViewSelectionDidChangeMeldetAusgewaehlteID() {
        let coordinator = NativeArticleListCoordinator()
        let snapshots = [makeSnapshot(id: "a1"), makeSnapshot(id: "a2"), makeSnapshot(id: "a3")]
        coordinator.rows = snapshots
        var reportedID: String?
        coordinator.onSelectionChanged = { reportedID = $0 }

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        coordinator.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: tableView)
        )

        #expect(reportedID == "a2")
    }

    @Test func tableViewSelectionDidChangeIgnoriertAuswahlAufTrailingRow() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.rows = [makeSnapshot(id: "a1")]
        coordinator.hasMoreIndicatorVisible = true
        var reportedID: String? = "vorher-gesetzt"
        coordinator.onSelectionChanged = { reportedID = $0 }

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        coordinator.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: tableView)
        )

        #expect(reportedID == nil)
    }

    @Test func buildContextMenuHatZwoelfEintraegePlusDreiTrenner() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.hasAvailableTags = true
        let menu = coordinator.buildContextMenu(for: makeSnapshot())

        #expect(menu.items.count == 16)
        #expect(menu.items.filter(\.isSeparatorItem).count == 3)
    }

    @Test func buildContextMenuZeigtGelesenMarkierenBeiUngelesenemArtikel() {
        let coordinator = NativeArticleListCoordinator()
        let menu = coordinator.buildContextMenu(for: makeSnapshot(isRead: false))

        #expect(menu.items[0].title == L10n.articleRowMarkRead)
    }

    @Test func buildContextMenuZeigtUngelesenMarkierenBeiGelesenemArtikel() {
        let coordinator = NativeArticleListCoordinator()
        let menu = coordinator.buildContextMenu(for: makeSnapshot(isRead: true))

        #expect(menu.items[0].title == L10n.articleRowMarkUnread)
    }

    @Test func buildContextMenuDeaktiviertTagZuweisenOhneVerfuegbareTags() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.hasAvailableTags = false
        let menu = coordinator.buildContextMenu(for: makeSnapshot())

        let tagItem = menu.items.first { $0.title == L10n.articleAssignTagCommand }
        #expect(tagItem?.isEnabled == false)
    }

    @Test func buildContextMenuDeaktiviertLinkAktionenOhneOriginalURL() {
        let coordinator = NativeArticleListCoordinator()
        let menu = coordinator.buildContextMenu(for: makeSnapshot(link: nil))

        let copyLinkItem = menu.items.first { $0.title == L10n.articleCopyLinkCommand }
        let openOriginalItem = menu.items.first { $0.title == L10n.articleOpenOriginalCommand }
        let shareItem = menu.items.first { $0.title == L10n.articleShareCommand }
        #expect(copyLinkItem?.isEnabled == false)
        #expect(openOriginalItem?.isEnabled == false)
        #expect(shareItem?.isEnabled == false)
    }

    @Test func buildContextMenuAktionenRufenDieRichtigenClosuresAuf() {
        let coordinator = NativeArticleListCoordinator()
        let snapshot = makeSnapshot(id: "a1")
        var toggledReadID: String?
        coordinator.onToggleRead = { toggledReadID = $0 }
        let menu = coordinator.buildContextMenu(for: snapshot)

        let readItem = menu.items[0]
        _ = readItem.target?.perform(readItem.action, with: readItem)

        #expect(toggledReadID == "a1")
    }
}
```

- [ ] **Step 2: Testlauf verifizieren, dass er fehlschlägt**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleListCoordinatorTests -parallel-testing-enabled NO`
Expected: FAIL — `Cannot find 'NativeArticleListCoordinator' in scope`.

- [ ] **Step 3: Trailing-Row-Zellen implementieren**

Neue Datei `Feedivo/Views/ArticleList/Native/NativeArticleListTrailingRowCellViews.swift`:

```swift
import AppKit

/// Feste Höhe für beide Trailing-Row-Typen (Pagination-Indikator,
/// "N gelesene Artikel anzeigen"-Button) — unabhängig von
/// `ArticleRowHeightMetrics`, da diese Zeilen keinen Artikelinhalt zeigen.
enum NativeArticleListTrailingRowMetrics {
    static let height: CGFloat = 44
}

/// Zelle für die Pagination-Trailing-Row — ersetzt die SwiftUI-`ProgressView`
/// samt `onAppear`-Ladeauslöser aus der bisherigen `List`-Implementierung.
final class NativeArticleListLoadMoreCellView: NSTableCellView {
    private let indicator = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    private func configureLayout() {
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.startAnimation(nil)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

/// Zelle für die "N gelesene Artikel anzeigen"-Trailing-Row — ersetzt den
/// SwiftUI-`Button` aus der bisherigen `List`-Implementierung.
final class NativeArticleListShowReadButtonCellView: NSTableCellView {
    private let button = NSButton(title: "", target: nil, action: nil)
    private var buttonAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    private func configureLayout() {
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = #selector(buttonTapped)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(count: Int, onTap: @escaping () -> Void) {
        button.title = String.localizedStringWithFormat(L10n.articleListShowReadButtonFormat, count)
        buttonAction = onTap
    }

    @objc private func buttonTapped() {
        buttonAction?()
    }
}
```

- [ ] **Step 4: `NativeArticleListCoordinator` implementieren**

Neue Datei `Feedivo/Views/ArticleList/Native/NativeArticleListCoordinator.swift`:

```swift
import AppKit

final class NativeArticleListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    enum TrailingRowKind: Equatable {
        case loadMoreIndicator
        case showReadArticlesButton(count: Int)
    }

    enum RowKind: Equatable {
        case content(ArticleListSnapshot)
        case trailing(TrailingRowKind)
    }

    private static let contentIdentifier = NSUserInterfaceItemIdentifier("NativeArticleRowCellView")
    private static let loadMoreIdentifier = NSUserInterfaceItemIdentifier("NativeArticleListLoadMoreCellView")
    private static let showReadButtonIdentifier = NSUserInterfaceItemIdentifier("NativeArticleListShowReadButtonCellView")

    var rows: [ArticleListSnapshot] = []
    var hasMoreIndicatorVisible = false
    var showReadArticlesButtonCount: Int?
    var hasAvailableTags = false
    var interfaceTextSize: InterfaceTextSize = .standard
    var imagePosition: ArticleListImagePosition = .left
    var feedNamePosition: ArticleListFeedNamePosition = .afterTitle
    var showsFeedName = true
    var summaryLineCount = ArticleListSummaryLineCount.defaultValue
    var dateDisplayMode: ArticleDateDisplayMode = .relative

    var onSelectionChanged: ((String?) -> Void)?
    var onToggleRead: ((String) -> Void)?
    var onToggleStarred: ((String) -> Void)?
    var onToggleArchived: ((String) -> Void)?
    var onRequestAssignTag: ((String) -> Void)?
    var onCreateRule: ((ArticleListSnapshot) -> Void)?
    var onCopyLink: ((ArticleListSnapshot) -> Void)?
    var onOpenOriginal: ((ArticleListSnapshot) -> Void)?
    var onShareOriginal: ((ArticleListSnapshot) -> Void)?
    var onOpenInNewTab: ((String) -> Void)?
    var onOpenInWindow: ((String) -> Void)?
    var onExport: ((String) -> Void)?
    var onDelete: ((ArticleListSnapshot) -> Void)?
    var onMarkAllRead: (() -> Void)?
    var onLoadMore: (() -> Void)?
    var onShowReadArticles: (() -> Void)?

    private var trailingRowKinds: [TrailingRowKind] {
        var kinds: [TrailingRowKind] = []
        if hasMoreIndicatorVisible {
            kinds.append(.loadMoreIndicator)
        }
        if let count = showReadArticlesButtonCount {
            kinds.append(.showReadArticlesButton(count: count))
        }
        return kinds
    }

    func rowKind(atRow row: Int) -> RowKind? {
        if row < rows.count {
            return .content(rows[row])
        }
        let trailingIndex = row - rows.count
        let kinds = trailingRowKinds
        guard trailingIndex >= 0, trailingIndex < kinds.count else {
            return nil
        }
        return .trailing(kinds[trailingIndex])
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count + trailingRowKinds.count
    }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rowKind(atRow: row) {
        case let .content(snapshot):
            let cell = (tableView.makeView(withIdentifier: Self.contentIdentifier, owner: self) as? NativeArticleRowCellView)
                ?? NativeArticleRowCellView(frame: .zero)
            cell.identifier = Self.contentIdentifier
            cell.configure(
                with: snapshot,
                interfaceTextSize: interfaceTextSize,
                imagePosition: imagePosition,
                feedNamePosition: feedNamePosition,
                showsFeedName: showsFeedName,
                summaryLineCount: summaryLineCount,
                dateDisplayMode: dateDisplayMode
            ) { [weak self] in
                self?.onToggleStarred?(snapshot.id)
            }
            return cell

        case .trailing(.loadMoreIndicator):
            // Diese Zeile wird nur angefragt, wenn sie tatsächlich sichtbar wird
            // (NSTableView ruft `viewFor` ausschließlich für sichtbare/bald
            // sichtbare Zeilen auf) — genau das ersetzt SwiftUIs
            // `.onAppear`-Trigger für `state.loadMore()`.
            onLoadMore?()
            let cell = (tableView.makeView(withIdentifier: Self.loadMoreIdentifier, owner: self) as? NativeArticleListLoadMoreCellView)
                ?? NativeArticleListLoadMoreCellView(frame: .zero)
            cell.identifier = Self.loadMoreIdentifier
            return cell

        case let .trailing(.showReadArticlesButton(count)):
            let cell = (tableView.makeView(withIdentifier: Self.showReadButtonIdentifier, owner: self) as? NativeArticleListShowReadButtonCellView)
                ?? NativeArticleListShowReadButtonCellView(frame: .zero)
            cell.identifier = Self.showReadButtonIdentifier
            cell.configure(count: count) { [weak self] in
                self?.onShowReadArticles?()
            }
            return cell

        case nil:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rowKind(atRow: row) {
        case .content:
            ArticleRowHeightMetrics.height(
                interfaceTextSize: interfaceTextSize,
                imagePosition: imagePosition,
                summaryLineCount: summaryLineCount
            )
        case .trailing, nil:
            NativeArticleListTrailingRowMetrics.height
        }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        // Trailing-Rows sind nicht selektierbar — kein Artikel dahinter.
        if case .content = rowKind(atRow: row) {
            return true
        }
        return false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, case let .content(snapshot) = rowKind(atRow: selectedRow) else {
            onSelectionChanged?(nil)
            return
        }
        onSelectionChanged?(snapshot.id)
    }

    // MARK: NSMenuDelegate

    /// Vom `NSViewRepresentable`-Wrapper (Task 4) gesetzt — `NSMenuDelegate`
    /// selbst hat keinen direkten Zugriff auf die zugehörige `NSTableView`.
    weak var weakTableView: NSTableView?

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let tableView = weakTableView,
              case let .content(snapshot) = rowKind(atRow: tableView.clickedRow)
        else {
            return
        }
        for item in buildContextMenu(for: snapshot).items {
            menu.addItem(item)
        }
    }

    // MARK: Kontextmenü (pure, direkt testbar)

    func buildContextMenu(for snapshot: ArticleListSnapshot) -> NSMenu {
        let menu = NSMenu()
        let hasOriginalURL = ArticleOriginalURLResolver.hasUsableWebLink(snapshot.link)

        menu.addItem(makeItem(
            title: snapshot.isRead ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead
        ) { [weak self] in self?.onToggleRead?(snapshot.id) })

        menu.addItem(makeItem(
            title: snapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd
        ) { [weak self] in self?.onToggleStarred?(snapshot.id) })

        menu.addItem(.separator())

        menu.addItem(makeItem(
            title: snapshot.isArchived ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand
        ) { [weak self] in self?.onToggleArchived?(snapshot.id) })

        menu.addItem(makeItem(
            title: L10n.articleAssignTagCommand,
            isEnabled: hasAvailableTags
        ) { [weak self] in self?.onRequestAssignTag?(snapshot.id) })

        menu.addItem(makeItem(title: L10n.articleCreateRuleCommand) { [weak self] in
            self?.onCreateRule?(snapshot)
        })

        menu.addItem(.separator())

        menu.addItem(makeItem(title: L10n.articleOpenInNewTabCommand) { [weak self] in
            self?.onOpenInNewTab?(snapshot.id)
        })

        menu.addItem(makeItem(title: L10n.articleOpenInWindowCommand) { [weak self] in
            self?.onOpenInWindow?(snapshot.id)
        })

        menu.addItem(makeItem(
            title: L10n.articleCopyLinkCommand,
            isEnabled: hasOriginalURL
        ) { [weak self] in self?.onCopyLink?(snapshot) })

        menu.addItem(makeItem(
            title: L10n.articleOpenOriginalCommand,
            isEnabled: hasOriginalURL
        ) { [weak self] in self?.onOpenOriginal?(snapshot) })

        menu.addItem(makeItem(
            title: L10n.articleShareCommand,
            isEnabled: hasOriginalURL
        ) { [weak self] in self?.onShareOriginal?(snapshot) })

        menu.addItem(makeItem(title: L10n.articleExportCommand) { [weak self] in
            self?.onExport?(snapshot.id)
        })

        menu.addItem(makeItem(title: L10n.articleDeleteCommand) { [weak self] in
            self?.onDelete?(snapshot)
        })

        menu.addItem(.separator())

        menu.addItem(makeItem(title: L10n.articleMarkAllReadCommand) { [weak self] in
            self?.onMarkAllRead?()
        })

        return menu
    }

    private func makeItem(title: String, isEnabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.isEnabled = isEnabled
        return item
    }
}

/// `NSMenuItem`-Subklasse, die ihre Aktion als Closure statt als
/// Target/Selector-Paar trägt — vermeidet einen separaten `@objc`-Handler
/// pro Menüeintrag (13 Aktions-Einträge).
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        self.target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) wird nicht unterstützt")
    }

    @objc private func invoke() {
        handler()
    }
}
```

- [ ] **Step 5: Testlauf verifizieren, dass alle Tests grün sind**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleListCoordinatorTests -parallel-testing-enabled NO`
Expected: alle 12 Tests grün.

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/ArticleList/Native/NativeArticleListCoordinator.swift \
  Feedivo/Views/ArticleList/Native/NativeArticleListTrailingRowCellViews.swift \
  FeedivoTests/Views/ArticleList/Native/NativeArticleListCoordinatorTests.swift
git commit -m "feat: NativeArticleListCoordinator — DataSource/Delegate/Kontextmenü"
```

---

## Task 4: `NSViewRepresentable`-Wrapper für die Hauptliste (`NativeArticleListTableView`)

**Files:**
- Create: `Feedivo/Views/ArticleList/Native/NativeArticleListTableView.swift`
- Test: `FeedivoTests/Views/ArticleList/Native/NativeArticleListTableViewTests.swift`

**Interfaces:**
- Consumes: `NativeArticleListCoordinator` (Task 3), `ArticleListImagePosition`,
  `ArticleListFeedNamePosition`, `ArticleListFeedNameVisibilitySettings`,
  `ArticleListSummaryLineCount`, `ArticleDateDisplayMode` (alle
  `ArticleListDisplaySettings.swift`, per `@AppStorage` gelesen — identisch zum Muster
  in `ArticleRowView`/dem Spike).
- Produces: `NativeArticleListTableView: NSViewRepresentable` mit Initializer
  `init(rows: [ArticleListSnapshot], hasMore: Bool, hiddenReadRowCount: Int,
  showsReadArticles: Bool, selectedArticleID: Binding<String?>, hasAvailableTags: Bool,
  onToggleRead: @escaping (String) -> Void, onToggleStarred: @escaping (String) -> Void,
  onToggleArchived: @escaping (String) -> Void, onRequestAssignTag: @escaping (String) -> Void,
  onCreateRule: @escaping (ArticleListSnapshot) -> Void, onCopyLink: @escaping (ArticleListSnapshot) -> Void,
  onOpenOriginal: @escaping (ArticleListSnapshot) -> Void, onShareOriginal: @escaping (ArticleListSnapshot) -> Void,
  onOpenInNewTab: @escaping (String) -> Void, onOpenInWindow: @escaping (String) -> Void,
  onExport: @escaping (String) -> Void, onDelete: @escaping (ArticleListSnapshot) -> Void,
  onMarkAllRead: @escaping () -> Void, onLoadMore: @escaping () -> Void,
  onShowReadArticles: @escaping () -> Void)` — Task 5 konsumiert genau diese
  Signatur.

- [ ] **Step 1: Fehlschlagenden Test für die reine Reload-Entscheidung schreiben**

Neue Datei `FeedivoTests/Views/ArticleList/Native/NativeArticleListTableViewTests.swift`:

```swift
import Testing
@testable import Feedivo

struct NativeArticleListTableViewTests {
    private func makeSnapshot(id: String) -> ArticleListSnapshot {
        ArticleListSnapshot(
            id: id, feedID: "f1", feedTitle: "Feed", title: "Titel \(id)",
            summary: nil, link: nil, imageURL: nil, publishedAt: nil,
            arrivedAt: Date(), estimatedReadingMinutes: nil,
            isRead: false, isStarred: false, isArchived: false,
            isHidden: false, faviconURL: nil
        )
    }

    @Test func needsReloadIstFalseBeiIdentischenSnapshots() {
        let rows = [makeSnapshot(id: "a1"), makeSnapshot(id: "a2")]
        #expect(NativeArticleListTableView.needsReload(current: rows, previous: rows) == false)
    }

    @Test func needsReloadIstTrueBeiUnterschiedlicherReihenfolge() {
        let a = makeSnapshot(id: "a1")
        let b = makeSnapshot(id: "a2")
        #expect(NativeArticleListTableView.needsReload(current: [a, b], previous: [b, a]) == true)
    }

    @Test func needsReloadIstTrueBeiZusaetzlicherZeile() {
        let a = makeSnapshot(id: "a1")
        let b = makeSnapshot(id: "a2")
        #expect(NativeArticleListTableView.needsReload(current: [a, b], previous: [a]) == true)
    }
}
```

- [ ] **Step 2: Testlauf verifizieren, dass er fehlschlägt**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleListTableViewTests -parallel-testing-enabled NO`
Expected: FAIL — `Cannot find 'NativeArticleListTableView' in scope`.

- [ ] **Step 3: `NativeArticleListTableView` implementieren**

Neue Datei `Feedivo/Views/ArticleList/Native/NativeArticleListTableView.swift`:

```swift
import AppKit
import SwiftUI

/// `NSViewRepresentable`-Wrapper für die native Hauptartikelliste — ersetzt
/// `SQLiteFeedArticleListView.articleList` bei aktiviertem
/// `NativeArticleListSettings.isEnabledKey`-Schalter. Die komplette
/// State-/Sticky-Row-/Filter-/Sortier-Logik bleibt unverändert in
/// `SQLiteFeedArticleListView`/`SQLiteArticleListDisplayState` — dieser
/// Wrapper bekommt nur das bereits fertig aufbereitete `rows`-Array.
struct NativeArticleListTableView: NSViewRepresentable {
    let rows: [ArticleListSnapshot]
    let hasMore: Bool
    let hiddenReadRowCount: Int
    let showsReadArticles: Bool
    @Binding var selectedArticleID: String?
    let hasAvailableTags: Bool
    let onToggleRead: (String) -> Void
    let onToggleStarred: (String) -> Void
    let onToggleArchived: (String) -> Void
    let onRequestAssignTag: (String) -> Void
    let onCreateRule: (ArticleListSnapshot) -> Void
    let onCopyLink: (ArticleListSnapshot) -> Void
    let onOpenOriginal: (ArticleListSnapshot) -> Void
    let onShareOriginal: (ArticleListSnapshot) -> Void
    let onOpenInNewTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onExport: (String) -> Void
    let onDelete: (ArticleListSnapshot) -> Void
    let onMarkAllRead: () -> Void
    let onLoadMore: () -> Void
    let onShowReadArticles: () -> Void

    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @AppStorage(ArticleListImagePosition.storageKey)
    private var imagePositionRawValue = ArticleListImagePosition.defaultPosition.rawValue

    @AppStorage(ArticleListFeedNameVisibilitySettings.showsFeedNameKey)
    private var showsFeedName = ArticleListFeedNameVisibilitySettings.defaultShowsFeedName

    @AppStorage(ArticleListFeedNamePosition.storageKey)
    private var feedNamePositionRawValue = ArticleListFeedNamePosition.defaultPosition.rawValue

    @AppStorage(ArticleListSummaryLineCount.storageKey)
    private var summaryLineCountRawValue = ArticleListSummaryLineCount.defaultValue

    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var dateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue

    /// Reine Vergleichsfunktion: entscheidet, ob `reloadData()` nötig ist.
    /// `ArticleListSnapshot` ist `Equatable` — ein Array-Vergleich reicht,
    /// identisch zum bereits reviewten Spike-Muster in
    /// `NativeArticleTableView.updateNSView`.
    static func needsReload(current: [ArticleListSnapshot], previous: [ArticleListSnapshot]) -> Bool {
        current != previous
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = false
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.menu = NSMenu()
        tableView.menu?.delegate = context.coordinator
        context.coordinator.weakTableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelectionChanged = { selectedArticleID = $0 }
        coordinator.onToggleRead = onToggleRead
        coordinator.onToggleStarred = onToggleStarred
        coordinator.onToggleArchived = onToggleArchived
        coordinator.onRequestAssignTag = onRequestAssignTag
        coordinator.onCreateRule = onCreateRule
        coordinator.onCopyLink = onCopyLink
        coordinator.onOpenOriginal = onOpenOriginal
        coordinator.onShareOriginal = onShareOriginal
        coordinator.onOpenInNewTab = onOpenInNewTab
        coordinator.onOpenInWindow = onOpenInWindow
        coordinator.onExport = onExport
        coordinator.onDelete = onDelete
        coordinator.onMarkAllRead = onMarkAllRead
        coordinator.onLoadMore = onLoadMore
        coordinator.onShowReadArticles = onShowReadArticles

        coordinator.hasAvailableTags = hasAvailableTags
        coordinator.interfaceTextSize = interfaceTextSize
        coordinator.imagePosition = ArticleListImagePosition.resolved(from: imagePositionRawValue)
        coordinator.feedNamePosition = ArticleListFeedNamePosition.resolved(from: feedNamePositionRawValue)
        coordinator.showsFeedName = showsFeedName
        coordinator.summaryLineCount = ArticleListSummaryLineCount.resolved(from: summaryLineCountRawValue)
        coordinator.dateDisplayMode = ArticleDateDisplayMode.resolved(from: dateDisplayModeRawValue)
        coordinator.hasMoreIndicatorVisible = hasMore
        coordinator.showReadArticlesButtonCount = (!showsReadArticles && hiddenReadRowCount > 0) ? hiddenReadRowCount : nil

        guard let tableView = nsView.documentView as? NSTableView else { return }

        tableView.rowHeight = ArticleRowHeightMetrics.height(
            interfaceTextSize: interfaceTextSize,
            imagePosition: coordinator.imagePosition,
            summaryLineCount: coordinator.summaryLineCount
        )

        if Self.needsReload(current: rows, previous: coordinator.rows) {
            coordinator.rows = rows
            tableView.reloadData()
        } else {
            coordinator.rows = rows
        }

        if let selectedArticleID, let index = rows.firstIndex(where: { $0.id == selectedArticleID }) {
            if tableView.selectedRow != index {
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        } else if tableView.selectedRow != -1 {
            tableView.deselectAll(nil)
        }
    }

    func makeCoordinator() -> NativeArticleListCoordinator {
        NativeArticleListCoordinator()
    }
}
```

- [ ] **Step 4: Testlauf verifizieren, dass alle Tests grün sind**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleListTableViewTests -parallel-testing-enabled NO`
Expected: alle 3 Tests grün.

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/ArticleList/Native/NativeArticleListTableView.swift \
  FeedivoTests/Views/ArticleList/Native/NativeArticleListTableViewTests.swift
git commit -m "feat: NativeArticleListTableView — NSViewRepresentable-Wrapper für die Hauptliste"
```

---

## Task 5: Hauptliste hinter dem Schalter verdrahten

**Files:**
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:415-445` (Property
  `articleList`)

**Interfaces:**
- Consumes: `NativeArticleListTableView` (Task 4), `NativeArticleListSettings`
  (Task 1), alle bereits bestehenden privaten Methoden von `SQLiteFeedArticleListView`
  (`toggleRead`, `toggleStarred`, `toggleArchived`, `requestRuleCreation`, `copyLink`,
  `openOriginal`, `shareOriginal`, `requestExportArticle`, `requestDeleteArticle`,
  `markRowsRead`).

- [ ] **Step 1: `@AppStorage` für den Schalter ergänzen**

In `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`, direkt nach der
bestehenden `@AppStorage("markArticleReadOnSelection")`-Property (Zeile 36-37)
ergänzen:

```swift
    @AppStorage(NativeArticleListSettings.isEnabledKey)
    private var usesNativeArticleList = NativeArticleListSettings.defaultIsEnabled
```

- [ ] **Step 2: `articleList` auf eine bedingte Verzweigung umstellen**

Die bestehende `articleList`-Property (Zeilen 415-445) ersetzen durch:

```swift
    @ViewBuilder
    private var articleList: some View {
        let currentDisplayState = displayState

        if usesNativeArticleList {
            NativeArticleListTableView(
                rows: currentDisplayState.visibleRows,
                hasMore: state.hasMore,
                hiddenReadRowCount: currentDisplayState.hiddenReadRowCount,
                showsReadArticles: showsReadArticles,
                selectedArticleID: $selectedArticleID,
                hasAvailableTags: database != nil,
                onToggleRead: toggleRead,
                onToggleStarred: toggleStarred,
                onToggleArchived: toggleArchived,
                onRequestAssignTag: { articleID in
                    tagAssignmentRequest = ArticleTagAssignmentRequest(articleID: articleID)
                },
                onCreateRule: requestRuleCreation,
                onCopyLink: copyLink,
                onOpenOriginal: openOriginal,
                onShareOriginal: shareOriginal,
                onOpenInNewTab: { articleID in
                    readerTabsState.openInNewBackgroundTab(articleID: articleID)
                },
                onOpenInWindow: { articleID in
                    guard let uuid = UUID(uuidString: articleID) else { return }
                    openWindow(value: ArticleWindowRequest(articleID: uuid))
                },
                onExport: requestExportArticle,
                onDelete: requestDeleteArticle,
                onMarkAllRead: { markRowsRead(.allVisible) },
                onLoadMore: { state.loadMore() },
                onShowReadArticles: { showsReadArticles = true }
            )
        } else {
            List(selection: $selectedArticleID) {
                if currentDisplayState.filteredRows.isEmpty {
                    articleListEmptyState(isSearching: isSearching)
                } else {
                    ForEach(currentDisplayState.visibleRows) { row in
                        articleRow(row)
                            .tag(row.id)
                    }

                    if state.hasMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .onAppear {
                            state.loadMore()
                        }
                    }

                    if !showsReadArticles, currentDisplayState.hiddenReadRowCount > 0 {
                        showReadArticlesButton(count: currentDisplayState.hiddenReadRowCount)
                    }
                }
            }
        }
    }
```

**Hinweis:** `currentDisplayState.filteredRows.isEmpty` (der SwiftUI-Leerzustand
innerhalb der `List`) ist für den nativen Pfad nicht relevant — bei komplett leeren
`visibleRows` verzweigt bereits `articleContent`s äußere
`case .loaded where effectiveRows.isEmpty`-Prüfung (Zeile 308) VOR `articleListContainer`
in den `ContentUnavailableView`-Leerzustand, die `Native*TableView` wird in diesem Fall
gar nicht erst konstruiert — identisch zum bisherigen Verhalten.

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Gezielten Regressionslauf für die Hauptliste ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -only-testing:FeedivoTests/ArticleListQueryTests -parallel-testing-enabled NO`
Expected: alle Tests grün, keine Regression (die State-/Query-Schicht wurde nicht
verändert, nur die Darstellung).

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
git commit -m "feat: Hauptartikelliste hinter native-Schalter verdrahten"
```

---

## Task 6: Zelle für die Suchfenster-Ergebnisliste (`NativeArticleSearchResultCellView`)

**Files:**
- Create: `Feedivo/Views/ArticleList/Native/NativeArticleSearchResultCellView.swift`
- Test: `FeedivoTests/Views/ArticleList/Native/NativeArticleSearchResultCellViewTests.swift`

**Interfaces:**
- Consumes: `ArticleListSnapshot`, `ReaderContentRenderer.htmlToPlainText(_:)`
  (bereits vorhanden, genutzt von `ArticleSearchResultRow`), `L10n.articleOpenOriginalCommand`.
- Produces: `NativeArticleSearchResultCellView` (finale Klasse, `NSTableCellView`-
  Subklasse) mit `func configure(with snapshot: ArticleListSnapshot,
  onOpenOriginal: @escaping () -> Void)`. Statische, pure Funktion
  `static func summaryText(from summary: String?) -> String?` — Task 7 ruft nur
  `configure(...)` auf.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Neue Datei
`FeedivoTests/Views/ArticleList/Native/NativeArticleSearchResultCellViewTests.swift`:

```swift
import Testing
@testable import Feedivo

struct NativeArticleSearchResultCellViewTests {
    @Test func summaryTextWandeltHTMLZuPlainTextUm() {
        let text = NativeArticleSearchResultCellView.summaryText(from: "<p>Hallo <b>Welt</b></p>")
        #expect(text == ReaderContentRenderer.htmlToPlainText("<p>Hallo <b>Welt</b></p>"))
    }

    @Test func summaryTextIstNilOhneSummary() {
        #expect(NativeArticleSearchResultCellView.summaryText(from: nil) == nil)
    }

    @Test func summaryTextIstNilBeiLeererSummary() {
        #expect(NativeArticleSearchResultCellView.summaryText(from: "") == nil)
    }
}
```

- [ ] **Step 2: Testlauf verifizieren, dass er fehlschlägt**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleSearchResultCellViewTests -parallel-testing-enabled NO`
Expected: FAIL — `Cannot find 'NativeArticleSearchResultCellView' in scope`.

- [ ] **Step 3: `NativeArticleSearchResultCellView` implementieren**

Neue Datei
`Feedivo/Views/ArticleList/Native/NativeArticleSearchResultCellView.swift`:

```swift
import AppKit

/// Reine AppKit-Zelle für die native Suchfenster-Ergebnisliste — schlankeres
/// Pendant zu `NativeArticleRowCellView`, nach dem Vorbild der SwiftUI-
/// Baseline `ArticleSearchResultRow` (kein Kontextmenü, kein Stern-Button,
/// dafür ein "Original öffnen"-Button).
final class NativeArticleSearchResultCellView: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let metadataField = NSTextField(labelWithString: "")
    private let summaryField = NSTextField(labelWithString: "")
    private let openOriginalButton = NSButton(image: NSImage(), target: nil, action: nil)

    private lazy var textStack = NSStackView(views: [titleField, metadataField, summaryField])
    private lazy var rootStack = NSStackView(views: [textStack, openOriginalButton])

    private var openOriginalAction: (() -> Void)?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    private func configureLayout() {
        rootStack.orientation = .horizontal
        rootStack.alignment = .top
        rootStack.spacing = 10
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)

        titleField.maximumNumberOfLines = 2
        titleField.font = .boldSystemFont(ofSize: 13)

        metadataField.font = .systemFont(ofSize: 11)
        metadataField.textColor = .secondaryLabelColor

        summaryField.maximumNumberOfLines = 2
        summaryField.font = .systemFont(ofSize: 12)
        summaryField.textColor = .secondaryLabelColor

        openOriginalButton.image = NSImage(systemSymbolName: "safari", accessibilityDescription: L10n.articleOpenOriginalCommand)
        openOriginalButton.imagePosition = .imageOnly
        openOriginalButton.isBordered = false
        openOriginalButton.target = self
        openOriginalButton.action = #selector(openOriginalTapped)
        NSLayoutConstraint.activate([
            openOriginalButton.widthAnchor.constraint(equalToConstant: 22),
            openOriginalButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    func configure(with snapshot: ArticleListSnapshot, onOpenOriginal: @escaping () -> Void) {
        openOriginalAction = onOpenOriginal

        titleField.stringValue = snapshot.title
        metadataField.stringValue = [
            snapshot.feedTitle,
            snapshot.publishedAt.map(Self.dateFormatter.string)
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        if let summary = Self.summaryText(from: snapshot.summary) {
            summaryField.stringValue = summary
            summaryField.isHidden = false
        } else {
            summaryField.stringValue = ""
            summaryField.isHidden = true
        }
    }

    static func summaryText(from summary: String?) -> String? {
        guard let summary, !summary.isEmpty else {
            return nil
        }
        let plainText = ReaderContentRenderer.htmlToPlainText(summary)
        return plainText.isEmpty ? nil : plainText
    }

    @objc private func openOriginalTapped() {
        openOriginalAction?()
    }
}
```

- [ ] **Step 4: Testlauf verifizieren, dass alle Tests grün sind**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleSearchResultCellViewTests -parallel-testing-enabled NO`
Expected: alle 3 Tests grün.

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/ArticleList/Native/NativeArticleSearchResultCellView.swift \
  FeedivoTests/Views/ArticleList/Native/NativeArticleSearchResultCellViewTests.swift
git commit -m "feat: NativeArticleSearchResultCellView — Zelle für die Suchfenster-Liste"
```

---

## Task 7: Coordinator + Wrapper für die Suchfenster-Ergebnisliste (`NativeArticleSearchResultTableView`)

**Files:**
- Create: `Feedivo/Views/ArticleList/Native/NativeArticleSearchResultTableView.swift`
- Test: `FeedivoTests/Views/ArticleList/Native/NativeArticleSearchResultTableViewTests.swift`

**Interfaces:**
- Consumes: `NativeArticleSearchResultCellView` (Task 6), `ArticleListSnapshot`.
- Produces: `NativeArticleSearchResultTableView: NSViewRepresentable` mit Initializer
  `init(snapshots: [ArticleListSnapshot], selectedID: Binding<String?>,
  onOpenOriginal: @escaping (ArticleListSnapshot) -> Void,
  onOpenInReader: @escaping (ArticleListSnapshot) -> Void)` — Task 8 konsumiert genau
  diese Signatur. Interne `NativeArticleSearchResultTableView.Coordinator`
  (`NSTableViewDataSource`, `NSTableViewDelegate`) mit testbarer, öffentlicher
  `func snapshot(atRow row: Int) -> ArticleListSnapshot?`.

- [ ] **Step 1: Fehlschlagende Tests schreiben**

Neue Datei
`FeedivoTests/Views/ArticleList/Native/NativeArticleSearchResultTableViewTests.swift`:

```swift
import AppKit
import Testing
@testable import Feedivo

// @MainActor zwingend nötig — echte NSTableView-Instanzen, siehe Global Constraints.
@Suite("NativeArticleSearchResultTableView")
@MainActor
struct NativeArticleSearchResultTableViewTests {
    private func makeSnapshot(id: String) -> ArticleListSnapshot {
        ArticleListSnapshot(
            id: id, feedID: "f1", feedTitle: "Feed", title: "Titel \(id)",
            summary: nil, link: nil, imageURL: nil, publishedAt: nil,
            arrivedAt: Date(), estimatedReadingMinutes: nil,
            isRead: false, isStarred: false, isArchived: false,
            isHidden: false, faviconURL: nil
        )
    }

    @Test func numberOfRowsEntsprichtAnzahlSnapshots() {
        let coordinator = NativeArticleSearchResultTableView.Coordinator()
        coordinator.snapshots = [makeSnapshot(id: "a1"), makeSnapshot(id: "a2")]

        #expect(coordinator.numberOfRows(in: NSTableView()) == 2)
    }

    @Test func snapshotAtRowLiefertNilAusserhalbDesBereichs() {
        let coordinator = NativeArticleSearchResultTableView.Coordinator()
        coordinator.snapshots = [makeSnapshot(id: "a1")]

        #expect(coordinator.snapshot(atRow: 1) == nil)
        #expect(coordinator.snapshot(atRow: 0) == coordinator.snapshots[0])
    }

    @Test func tableViewSelectionDidChangeMeldetAusgewaehlteID() {
        let coordinator = NativeArticleSearchResultTableView.Coordinator()
        coordinator.snapshots = [makeSnapshot(id: "a1"), makeSnapshot(id: "a2")]
        var reportedID: String?
        coordinator.onSelectionChanged = { reportedID = $0 }

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        coordinator.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: tableView)
        )

        #expect(reportedID == "a2")
    }

    @Test func doubleActionRuftOnOpenInReaderMitAngeklickterZeileAuf() {
        let coordinator = NativeArticleSearchResultTableView.Coordinator()
        let snapshot = makeSnapshot(id: "a1")
        coordinator.snapshots = [snapshot]
        var openedSnapshot: ArticleListSnapshot?
        coordinator.onOpenInReader = { openedSnapshot = $0 }

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        coordinator.handleDoubleClick(tableView)

        #expect(openedSnapshot == snapshot)
    }
}
```

- [ ] **Step 2: Testlauf verifizieren, dass er fehlschlägt**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleSearchResultTableViewTests -parallel-testing-enabled NO`
Expected: FAIL — `Cannot find 'NativeArticleSearchResultTableView' in scope`.

- [ ] **Step 3: `NativeArticleSearchResultTableView` implementieren**

Neue Datei
`Feedivo/Views/ArticleList/Native/NativeArticleSearchResultTableView.swift`:

```swift
import AppKit
import SwiftUI

/// `NSTableView`-Subklasse nur für die Return-Taste — löst denselben
/// Öffnen-Callback wie ein Doppelklick aus (`doubleAction`), reicht alle
/// anderen Tasten unverändert an `super.keyDown` weiter (u. a. die
/// Pfeiltasten, die `NSTableView` bereits nativ für die Zeilennavigation
/// nutzt).
private final class ReturnKeyOpensTableView: NSTableView {
    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 /* Return */ else {
            super.keyDown(with: event)
            return
        }
        guard let action = doubleAction, let target else {
            super.keyDown(with: event)
            return
        }
        _ = target.perform(action, with: self)
    }
}

/// `NSViewRepresentable`-Wrapper für die native Suchfenster-Ergebnisliste —
/// ersetzt `ArticleSearchWindowView.resultList` bei aktiviertem
/// `NativeArticleListSettings.isEnabledKey`-Schalter. Kein Kontextmenü, keine
/// Pagination (Suchergebnisse werden komplett auf einmal geladen).
struct NativeArticleSearchResultTableView: NSViewRepresentable {
    let snapshots: [ArticleListSnapshot]
    @Binding var selectedID: String?
    let onOpenOriginal: (ArticleListSnapshot) -> Void
    let onOpenInReader: (ArticleListSnapshot) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = ReturnKeyOpensTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = true
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelectionChanged = { selectedID = $0 }
        coordinator.onOpenOriginal = onOpenOriginal
        coordinator.onOpenInReader = onOpenInReader

        guard let tableView = nsView.documentView as? NSTableView else { return }

        if coordinator.snapshots.map(\.id) != snapshots.map(\.id) {
            coordinator.snapshots = snapshots
            tableView.reloadData()
        } else {
            coordinator.snapshots = snapshots
        }

        if let selectedID, let index = snapshots.firstIndex(where: { $0.id == selectedID }) {
            if tableView.selectedRow != index {
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        } else if tableView.selectedRow != -1 {
            tableView.deselectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let identifier = NSUserInterfaceItemIdentifier("NativeArticleSearchResultCellView")

        var snapshots: [ArticleListSnapshot] = []
        var onSelectionChanged: ((String?) -> Void)?
        var onOpenOriginal: ((ArticleListSnapshot) -> Void)?
        var onOpenInReader: ((ArticleListSnapshot) -> Void)?

        func snapshot(atRow row: Int) -> ArticleListSnapshot? {
            guard row >= 0, row < snapshots.count else { return nil }
            return snapshots[row]
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            snapshots.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let snapshot = snapshot(atRow: row) else { return nil }
            let cell = (tableView.makeView(withIdentifier: Self.identifier, owner: self) as? NativeArticleSearchResultCellView)
                ?? NativeArticleSearchResultCellView(frame: .zero)
            cell.identifier = Self.identifier
            cell.configure(with: snapshot) { [weak self] in
                self?.onOpenOriginal?(snapshot)
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            onSelectionChanged?(snapshot(atRow: tableView.selectedRow)?.id)
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            guard let snapshot = snapshot(atRow: sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow) else {
                return
            }
            onOpenInReader?(snapshot)
        }
    }
}
```

- [ ] **Step 4: Testlauf verifizieren, dass alle Tests grün sind**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleSearchResultTableViewTests -parallel-testing-enabled NO`
Expected: alle 4 Tests grün.

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/ArticleList/Native/NativeArticleSearchResultTableView.swift \
  FeedivoTests/Views/ArticleList/Native/NativeArticleSearchResultTableViewTests.swift
git commit -m "feat: NativeArticleSearchResultTableView — native Suchfenster-Ergebnisliste"
```

---

## Task 8: Suchfenster hinter dem Schalter verdrahten

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift:242-291` (Property
  `resultList`)

**Interfaces:**
- Consumes: `NativeArticleSearchResultTableView` (Task 7), `NativeArticleListSettings`
  (Task 1), bestehende Methoden `openOriginal(_:)`, `openInReaderWindow(_:)`.

- [ ] **Step 1: `@AppStorage` für den Schalter ergänzen**

In `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift`, direkt nach der
bestehenden `@AppStorage(SQLiteDataInvalidation.statusVersionKey)`-Property (Zeile
15-16) ergänzen:

```swift
    @AppStorage(NativeArticleListSettings.isEnabledKey)
    private var usesNativeArticleList = NativeArticleListSettings.defaultIsEnabled
```

- [ ] **Step 2: `resultList` auf eine bedingte Verzweigung umstellen**

Die bestehende `resultList`-Property (Zeilen 242-291) ersetzen durch:

```swift
    @ViewBuilder
    private var resultList: some View {
        if usesNativeArticleList {
            NativeArticleSearchResultTableView(
                snapshots: snapshots,
                selectedID: $selectedResultID,
                onOpenOriginal: openOriginal,
                onOpenInReader: openInReaderWindow
            )
            .frame(minWidth: 260, idealWidth: 340)
            .task(id: snapshots.map(\.id)) {
                if selectedResultID == nil || !snapshots.contains(where: { $0.id == selectedResultID }) {
                    selectedResultID = snapshots.first?.id
                }
            }
        } else {
            List(snapshots) { snapshot in
                ArticleSearchResultRow(snapshot: snapshot) {
                    openOriginal(snapshot)
                }
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            openInReaderWindow(snapshot)
                        }
                        .exclusively(before: TapGesture(count: 1).onEnded {
                            selectedResultID = snapshot.id
                            isResultListFocused = true
                        })
                )
                .listRowBackground(
                    snapshot.id == selectedResultID
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
                .accessibilityAddTraits(snapshot.id == selectedResultID ? [.isSelected] : [])
            }
            .listStyle(.inset)
            .frame(minWidth: 260, idealWidth: 340)
            .focusable()
            .focused($isResultListFocused)
            .onKeyPress(.downArrow) {
                selectAdjacentResult(offset: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                selectAdjacentResult(offset: -1)
                return .handled
            }
            .onKeyPress(.return) {
                if let selectedSnapshot {
                    openInReaderWindow(selectedSnapshot)
                }
                return .handled
            }
            .task(id: snapshots.map(\.id)) {
                if selectedResultID == nil || !snapshots.contains(where: { $0.id == selectedResultID }) {
                    selectedResultID = snapshots.first?.id
                }
            }
        }
    }
```

**Hinweis:** Das `.task(id:)` für die Initial-/Nachauswahl ist bewusst in BEIDEN
Zweigen identisch dupliziert statt einmalig außerhalb der Verzweigung platziert — ein
`@ViewBuilder`-`if`/`else` erzeugt zwei unterschiedliche View-Identitäten
(`ConditionalContent`), ein Modifier außerhalb der Verzweigung würde bei jedem
Umschalten des Schalters seinen `.task`-Zustand verlieren/neu starten, was hier
unkritisch, aber unnötig verwirrend wäre — die Duplikation macht die Absicht pro Zweig
explizit.

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleSearchWindowView.swift
git commit -m "feat: Suchfenster-Ergebnisliste hinter native-Schalter verdrahten"
```

---

## Task 9: Gezielter Regressionslauf + Release-Build

**Files:**
- Keine Code-Änderung — reine Verifikation.

- [ ] **Step 1: Alle neuen Testsuiten gemeinsam ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListDisplaySettingsTests -only-testing:FeedivoTests/NativeArticleRowCellViewTests -only-testing:FeedivoTests/NativeArticleListCoordinatorTests -only-testing:FeedivoTests/NativeArticleListTableViewTests -only-testing:FeedivoTests/NativeArticleSearchResultCellViewTests -only-testing:FeedivoTests/NativeArticleSearchResultTableViewTests -parallel-testing-enabled NO`
Expected: alle Tests grün.

- [ ] **Step 2: Bestehende, von diesem Plan berührte Suiten erneut laufen lassen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -only-testing:FeedivoTests/ArticleListQueryTests -only-testing:FeedivoTests/ArticleListRenderBenchmarkTests -only-testing:FeedivoTests/NativeArticleTableViewCoordinatorTests -only-testing:FeedivoTests/NativeArticleImageLoadGuardTests -parallel-testing-enabled NO`
Expected: alle Tests grün — insbesondere die beiden Spike-Testsuiten
(`ArticleListRenderBenchmarkTests`, `NativeArticleTableViewCoordinatorTests`) müssen
unverändert grün bleiben, da der Spike-Code in diesem Plan nicht angefasst wurde.

- [ ] **Step 3: Release-Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Release build`
Expected: `BUILD SUCCEEDED` — bestätigt, dass der neue Schalter (kein `#if DEBUG`) auch
im Release-Build tatsächlich verfügbar ist, wie von der Spec verlangt.

- [ ] **Step 4: `git status`/`git diff --stat` gegen den Ausgangszustand des Branches prüfen**

Run: `git status --short`
Expected: keine unerwarteten/unstaged Änderungen außerhalb der neun Task-Commits.

Run: `git log --oneline main..HEAD`
Expected: 8 Commits (Tasks 1–8), einer pro Task.

- [ ] **Step 5: Commit (falls durch die Verifikation selbst noch Dateien geändert wurden)**

Nur falls Step 1–4 tatsächlich Code-Änderungen nötig gemacht haben (z. B. ein in der
Zwischenzeit gefundener Fix) — sonst diesen Schritt überspringen, da Task 9 selbst
keine eigenen Dateiänderungen produziert.

---

## Self-Review-Notizen (bereits eingearbeitet)

- **Spec-Abdeckung:** Alle Spec-Abschnitte sind abgedeckt — Schalter (Task 1),
  Hauptlisten-Zelle+Coordinator+Wrapper+Verdrahtung (Tasks 2–5), Suchfenster-Zelle+
  Coordinator/Wrapper+Verdrahtung (Tasks 6–8), Testing-Strategie (in jedem Task
  eingebettet + Task 9 als Abschluss).
- **Typkonsistenz geprüft:** `NativeArticleListCoordinator`s Closure-Signaturen (Task 3)
  stimmen exakt mit den in Task 5 übergebenen bestehenden Methoden
  (`toggleRead(_ articleID: String)` etc.) überein — keine Wrapper-Closures nötig außer
  den drei Stellen, die tatsächlich eine andere Form brauchen (`onRequestAssignTag`,
  `onOpenInNewTab`, `onOpenInWindow`, `onMarkAllRead`, `onLoadMore`,
  `onShowReadArticles`), identisch zur ursprünglichen `articleRow(_:)`-Closure-Liste in
  `SQLiteFeedArticleListView.swift:468-520`.
- **Kein Platzhalter-Code:** Jeder Schritt enthält vollständigen, kompilierfertigen
  Code — keine "TODO"/"ähnlich wie oben"-Verweise.
