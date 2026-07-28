# Artikel drucken (Feature 25.1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nativer macOS-Druck (⌘P) für Artikel, der der aktuellen Reader-Ansicht folgt (native Darstellung oder Original-Webseite) — ersetzt den nie erreichbaren, qualitativ schlechten alten PDF-Export-Renderer.

**Architektur:** Neuer Shortcut `.articlePrint` (⌘P) + Druck-Button in `SQLiteReaderView`s Toolbar. Im Web-Modus wird die sichtbare `WKWebView` direkt gedruckt (`printOperation(with:)`). Im nativen Modus wird die bestehende Export-HTML (`ArticlePDFExportRenderer.html(...)`) in eine unsichtbare, retained `WKWebView` geladen und nach `didFinish` gedruckt. Der alte `NSAttributedString`/`CGContext`-basierte PDF-Renderer wird entfernt (macOS' natives "Als PDF sichern" im Druckdialog übernimmt PDF-Export künftig).

**Tech Stack:** SwiftUI (macOS), AppKit (`NSPrintOperation`, `NSPrintInfo`), WebKit (`WKWebView`, `WKNavigationDelegate`), Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Druckinhalt folgt der aktuellen Reader-Ansicht (nativ vs. Web) — kein zusätzlicher Umschalter im Druckdialog.
- Aktivierungsbedingung für Button/Shortcut: nur wenn ein Artikel ausgewählt ist (`state.snapshot != nil`), identisch zum bestehenden Export-Button.
- Kein Sonderfall für einen Ladefehler in der Web-Ansicht — gedruckt wird, was gerade sichtbar ist.
- Native Ansicht druckt immer mit Metadaten (`includesMetadata: true`), kein Metadaten-Toggle im Druckdialog.
- DOCX-Export (Feature 18.1c) und das `.pdf`-Format im Export-Sheet bleiben vollständig unangetastet — PDF kommt ausschließlich über den Druckdialog.
- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).

**Wichtige Abweichung von der Design-Spec (verifiziert, siehe Task 3):** Die Spec
(`docs/superpowers/specs/2026-07-17-artikel-drucken-design.md`) behauptet, der alte
CGContext-PDF-Renderer habe „0% Testabdeckung". Das stimmt nicht mehr — es existieren 5
Tests, die genau diesen Codepfad direkt testen (siehe Task 3). Task 3 entfernt/passt diese
Tests explizit an, statt sie stillschweigend zu übernehmen.

---

### Task 1: `CustomizableShortcut`-Erweiterung um `.articlePrint`

**Files:**
- Modify: `Feedivo/Models/CustomizableShortcut.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Test: `FeedivoTests/FeedivoTests.swift`

**Interfaces:**
- Produces: `CustomizableShortcut.articlePrint` (Kategorie `.article`, `defaultSpec ==
  KeyboardShortcutSpec(key: "p", modifiers: [.command])`, `titleKey == L10n.shortcutsLabelArticlePrint`),
  `L10n.articlePrintCommand: String` (Button-Tooltip-Text).
- Consumes: nichts aus anderen Tasks.

- [ ] **Step 1: Neuen Test schreiben (schlägt zunächst mit Compile-Fehler fehl)**

In `FeedivoTests/FeedivoTests.swift` den bestehenden Test `customizableShortcutEnthaeltAchtNeueFaelleOhneDefault`
(erwartet aktuell `CustomizableShortcut.allCases.count == 20`) wie folgt ändern und direkt
danach einen neuen Test ergänzen:

```swift
    @Test func customizableShortcutEnthaeltAchtNeueFaelleOhneDefault() {
        let newCases: [CustomizableShortcut] = [
            .feedImportOPML, .feedExportOPML, .feedOrganizerOpen,
            .articleToggleArchived, .articleCopyLink, .articleOpenOriginal,
            .articleShareOriginal, .articleExport
        ]

        for shortcut in newCases {
            #expect(shortcut.defaultSpec == nil, "\(shortcut.rawValue) sollte keinen Default-Shortcut haben")
        }

        #expect(CustomizableShortcut.feedImportOPML.category == .feed)
        #expect(CustomizableShortcut.feedExportOPML.category == .feed)
        #expect(CustomizableShortcut.feedOrganizerOpen.category == .feed)
        #expect(CustomizableShortcut.articleToggleArchived.category == .article)
        #expect(CustomizableShortcut.articleCopyLink.category == .article)
        #expect(CustomizableShortcut.articleOpenOriginal.category == .article)
        #expect(CustomizableShortcut.articleShareOriginal.category == .article)
        #expect(CustomizableShortcut.articleExport.category == .article)

        #expect(CustomizableShortcut.allCases.count == 21)
    }

    @Test func customizableShortcutArticlePrintHatKategorieArtikelUndDefaultCommandP() {
        #expect(CustomizableShortcut.articlePrint.category == .article)
        #expect(CustomizableShortcut.articlePrint.defaultSpec == KeyboardShortcutSpec(key: "p", modifiers: [.command]))
    }
```

- [ ] **Step 2: Build/Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -quiet`

Expected: FAIL (Compile-Fehler `type 'CustomizableShortcut' has no member 'articlePrint'` —
in diesem Projekt das etablierte Muster für einen neuen Enum-Fall, siehe z. B. Task 6 von
Feature 19.8 in `.superpowers/sdd/`).

- [ ] **Step 3: `.articlePrint`-Fall in `CustomizableShortcut.swift` ergänzen**

In `Feedivo/Models/CustomizableShortcut.swift`:

```swift
    case articleExport
    case articlePrint
    case readerWebBack
    case readerWebForward
```

(ersetzt die bestehenden 3 Zeilen `case articleExport` / `case readerWebBack` / `case readerWebForward`)

```swift
        case .articleSelectPrevious, .articleSelectNext, .articleSearch,
             .articleToggleRead, .articleToggleStarred, .articleToggleArchived,
             .articleOpenInWindow, .articleCopyLink, .articleOpenOriginal,
             .articleShareOriginal, .articleExport, .articlePrint:
            .article
```

(ersetzt den bestehenden `category`-Switch-Fall für `.article`, der aktuell ohne
`.articlePrint` endet)

```swift
        case .articleExport: L10n.shortcutsLabelArticleExport
        case .articlePrint: L10n.shortcutsLabelArticlePrint
        case .readerWebBack: L10n.shortcutsLabelReaderWebBack
```

(ergänzt im `titleKey`-Switch eine neue Zeile zwischen `articleExport` und `readerWebBack`)

```swift
        case .articleOpenInWindow:
            KeyboardShortcutSpec(key: SpecialKey.return.rawValue, modifiers: [.command])
        case .articlePrint:
            KeyboardShortcutSpec(key: "p", modifiers: [.command])
        case .readerWebBack:
```

(ergänzt im `defaultSpec`-Switch eine neue Zeile zwischen `articleOpenInWindow` und `readerWebBack`)

- [ ] **Step 4: L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach der Zeile
`static let shortcutsLabelArticleExport = LocalizedStringKey("shortcuts.label.articleExport")`:

```swift
    static let shortcutsLabelArticlePrint = LocalizedStringKey("shortcuts.label.articlePrint")
```

Direkt nach der Zeile
`static let articleExportCommand = String(localized: "article.export.command")`:

```swift
    static let articlePrintCommand = String(localized: "article.print.command")
```

- [ ] **Step 5: Katalogeinträge in `Localizable.xcstrings` ergänzen**

**Wichtig (siehe CLAUDE.md-Gotcha):** NIEMALS `json.load`/`json.dump` auf die ganze Datei
anwenden — nur per gezielter Textsegment-Einfügung an einem eindeutigen Anker arbeiten, dann
`git diff --stat` prüfen (nur Insertions, keine/kaum Deletions).

Erster Anker — in `Feedivo/Resources/Localizable.xcstrings` den Block von
`"shortcuts.label.articleExport"` bis `"shortcuts.modifierFree.warning"` suchen:

```json
    "shortcuts.label.articleExport" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Exportieren"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Export"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Exporter"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Esporta"
          }
        }
      }
    },
    "shortcuts.modifierFree.warning" : {
```

Ersetzen durch (neuer Block zwischen beiden eingefügt, sonst unverändert):

```json
    "shortcuts.label.articleExport" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Exportieren"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Export"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Exporter"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Esporta"
          }
        }
      }
    },
    "shortcuts.label.articlePrint" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Drucken"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Print"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Imprimer"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Stampa"
          }
        }
      }
    },
    "shortcuts.modifierFree.warning" : {
```

Zweiter Anker — den Block von `"article.previous.command"` bis `"article.search.clear"` suchen:

```json
    "article.previous.command" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Vorheriger Artikel"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Previous article"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Article précédent"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Articolo precedente"
          }
        }
      }
    },
    "article.search.clear" : {
```

Ersetzen durch:

```json
    "article.previous.command" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Vorheriger Artikel"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Previous article"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Article précédent"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Articolo precedente"
          }
        }
      }
    },
    "article.print.command" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Drucken..."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Print..."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Imprimer..."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Stampa..."
          }
        }
      }
    },
    "article.search.clear" : {
```

Danach: `git diff --stat Feedivo/Resources/Localizable.xcstrings` ausführen — erwartet werden
nur Insertions (2 neue Blöcke à ~26 Zeilen), keine Deletions.

- [ ] **Step 6: Build/Test ausführen, Erfolg bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -quiet`

Expected: PASS (alle Tests in `FeedivoTests.swift` grün, insbesondere die beiden geänderten/neuen).

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Models/CustomizableShortcut.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings FeedivoTests/FeedivoTests.swift
git commit -m "Feature: Shortcut .articlePrint (Cmd+P) fuer Artikel drucken ergaenzt"
```

---

### Task 2: Druck-Button + Druck-Logik in `SQLiteReaderView`

**Files:**
- Modify: `Feedivo/Views/Reader/WebContentView.swift`
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift`

**Interfaces:**
- Consumes: `CustomizableShortcut.articlePrint` + `L10n.shortcutsLabelArticlePrint`/`L10n.articlePrintCommand`
  (Task 1), `ArticlePDFExportRenderer.html(for:options:style:assets:) -> String` (bestehend,
  bleibt unverändert durch Task 3), `ArticleExportSnapshot.init(sqliteSnapshot:tagNames:)` (bestehend).
- Produces: `WebNavigationController.webView: WKWebView?` (jetzt `internal` statt `fileprivate`,
  lesbar für `SQLiteReaderView`), `private func printCurrentArticle()` in `SQLiteReaderView`.

**Kein automatisierter Test möglich** (wie bei den bestehenden `readerWebBack`/`readerWebForward`-
Buttons: kein ViewInspector, kein programmatischer Zugriff auf den echten `NSPrintOperation`-Dialog
aus Unit-Tests) — Verifikation über Build + die manuelle Live-Checkliste am Ende dieses Tasks.

- [ ] **Step 1: `WebNavigationController.webView` auf `internal` anheben**

In `Feedivo/Views/Reader/WebContentView.swift`:

```swift
    fileprivate weak var webView: WKWebView?
```

ersetzen durch:

```swift
    weak var webView: WKWebView?
```

- [ ] **Step 2: `import WebKit` in `SQLiteReaderView.swift` ergänzen**

In `Feedivo/Views/Reader/SQLiteReaderView.swift`, ganz oben:

```swift
import AppKit
import SwiftUI
```

ersetzen durch:

```swift
import AppKit
import SwiftUI
import WebKit
```

- [ ] **Step 3: Neue `@State`-Properties für die Offscreen-Druck-WebView ergänzen**

In `Feedivo/Views/Reader/SQLiteReaderView.swift`, direkt nach der bestehenden Zeile
`@State private var webNavigationController = WebNavigationController()`:

```swift
    @State private var webNavigationController = WebNavigationController()
    // Haelt die unsichtbare WKWebView fuer den nativen Druck-Modus fest, bis der
    // Druckvorgang abgeschlossen ist (siehe printCurrentArticle()/ArticlePrintCoordinator
    // unten) — sonst wuerde ARC sie vorzeitig freigeben, bevor WKNavigationDelegate.
    // didFinish feuert.
    @State private var offscreenPrintWebView: WKWebView?
    @State private var articlePrintCoordinator: ArticlePrintCoordinator?
```

- [ ] **Step 4: Druck-Button in die Toolbar einfügen**

In `Feedivo/Views/Reader/SQLiteReaderView.swift`, in `readerToolbarContent`, direkt nach der
bestehenden Web-Navigations-`ControlGroup` (vor dem `Picker(L10n.readerDisplayModePicker, ...)`):

```swift
                ControlGroup {
                    Button {
                        webNavigationController.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .help(L10n.readerWebBackCommand)
                    .customizableKeyboardShortcut(.readerWebBack, overrides: shortcutOverrides)
                    .disabled(readerDisplayMode != .web || !webNavigationController.canGoBack)

                    Button {
                        webNavigationController.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .help(L10n.readerWebForwardCommand)
                    .customizableKeyboardShortcut(.readerWebForward, overrides: shortcutOverrides)
                    .disabled(readerDisplayMode != .web || !webNavigationController.canGoForward)
                }

                Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
```

ersetzen durch:

```swift
                ControlGroup {
                    Button {
                        webNavigationController.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .help(L10n.readerWebBackCommand)
                    .customizableKeyboardShortcut(.readerWebBack, overrides: shortcutOverrides)
                    .disabled(readerDisplayMode != .web || !webNavigationController.canGoBack)

                    Button {
                        webNavigationController.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .help(L10n.readerWebForwardCommand)
                    .customizableKeyboardShortcut(.readerWebForward, overrides: shortcutOverrides)
                    .disabled(readerDisplayMode != .web || !webNavigationController.canGoForward)
                }

                ControlGroup {
                    Button {
                        printCurrentArticle()
                    } label: {
                        Image(systemName: "printer")
                    }
                    .help(L10n.articlePrintCommand)
                    .customizableKeyboardShortcut(.articlePrint, overrides: shortcutOverrides)
                    .disabled(state.snapshot == nil)
                }

                Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
```

- [ ] **Step 5: `printCurrentArticle()` implementieren**

In `Feedivo/Views/Reader/SQLiteReaderView.swift`, direkt nach der bestehenden Funktion
`requestExportArticle()` (vor der schließenden `}` der `struct SQLiteReaderView`):

```swift
    private func requestExportArticle() {
        guard let snapshot = state.snapshot,
              let database
        else {
            return
        }

        do {
            let tagNames = try TagStore(database: database).exportTagNames(
                articleID: snapshot.id,
                feedID: snapshot.feedID
            )
            articleExportRequest = ArticleExportRequest(
                snapshot: ArticleExportSnapshot(sqliteSnapshot: snapshot, tagNames: tagNames)
            )
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}
```

ersetzen durch:

```swift
    private func requestExportArticle() {
        guard let snapshot = state.snapshot,
              let database
        else {
            return
        }

        do {
            let tagNames = try TagStore(database: database).exportTagNames(
                articleID: snapshot.id,
                feedID: snapshot.feedID
            )
            articleExportRequest = ArticleExportRequest(
                snapshot: ArticleExportSnapshot(sqliteSnapshot: snapshot, tagNames: tagNames)
            )
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    // Druckinhalt folgt der aktuellen Reader-Ansicht (kein Umschalter im Druckdialog,
    // siehe Design-Spec 2026-07-17-artikel-drucken-design.md). Im Web-Modus wird die
    // tatsaechlich sichtbare WKWebView 1:1 gedruckt (inkl. Original-Layout). Im nativen
    // Modus gibt es keine dauerhaft lebende WKWebView zum Drucken — deshalb wird die
    // bestehende Export-HTML (identisch zum HTML-Export) offscreen geladen und nach
    // vollstaendigem Laden gedruckt (ArticlePrintCoordinator unten).
    private func printCurrentArticle() {
        switch readerDisplayMode {
        case .web:
            guard let webView = webNavigationController.webView else {
                return
            }

            let operation = webView.printOperation(with: .shared)
            operation.run()

        case .native:
            guard let snapshot = state.snapshot else {
                return
            }

            let html = ArticlePDFExportRenderer.html(
                for: ArticleExportSnapshot(sqliteSnapshot: snapshot, tagNames: snapshot.tags.map(\.name)),
                options: ArticleExportOptions(format: .html, includesMetadata: true),
                style: .default,
                assets: []
            )

            // 816x1056pt entspricht ungefaehr US Letter bei 96dpi — ausreichend breit,
            // damit die Export-CSS (max-width: 680px, siehe ArticlePDFExportStyle.default)
            // beim Layout nicht kollabiert, obwohl die WebView nie sichtbar wird.
            let printWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 816, height: 1056))
            let coordinator = ArticlePrintCoordinator {
                offscreenPrintWebView = nil
                articlePrintCoordinator = nil
            }
            printWebView.navigationDelegate = coordinator
            offscreenPrintWebView = printWebView
            articlePrintCoordinator = coordinator
            printWebView.loadHTMLString(html, baseURL: nil)
        }
    }
}
```

- [ ] **Step 6: `ArticlePrintCoordinator`-Hilfsklasse ergänzen**

In `Feedivo/Views/Reader/SQLiteReaderView.swift`, ganz am Ende der Datei (nach der
bestehenden `private struct FullScreenTransitionObserver { ... }`, die mit der schließenden
`}` in der letzten Zeile endet):

```swift
/// Rendert die native Reader-Export-HTML in einer unsichtbaren WKWebView und startet den
/// nativen Druckvorgang, sobald das Laden abgeschlossen ist — WKWebView.printOperation(with:)
/// liefert vor didFinish kein sinnvolles Ergebnis. SQLiteReaderView haelt die zugehoerige
/// WKWebView per @State fest, bis onFinished() aufgerufen wird (sonst wuerde ARC sie
/// vorzeitig freigeben, analog zum bestehenden WebContentView.Coordinator-Muster).
private final class ArticlePrintCoordinator: NSObject, WKNavigationDelegate {
    private let onFinished: () -> Void

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        super.init()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let operation = webView.printOperation(with: .shared)
        operation.run()
        onFinished()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFinished()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFinished()
    }
}
```

- [ ] **Step 7: Build ausführen, Erfolg bestätigen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`

Expected: `BUILD SUCCEEDED` (SourceKit-Fehleranzeigen in der IDE vor einem echten Build
sind laut CLAUDE.md-Gotcha unzuverlässig — nur der echte `xcodebuild build`-Lauf zählt).

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/Reader/WebContentView.swift Feedivo/Views/Reader/SQLiteReaderView.swift
git commit -m "Feature: Artikel drucken (Cmd+P) - nativer Druckdialog fuer Reader- und Web-Ansicht"
```

**Manuelle Live-Verifikationscheckliste (aus der Design-Spec, hier nicht dupliziert
ausgeführt — nach Abschluss des gesamten Plans einmal komplett durchgehen):**
1. Artikel in nativer Ansicht auswählen, ⌘P drücken (oder Drucken-Button klicken) —
   nativer macOS-Druckdialog erscheint mit demselben Layout wie die HTML-Export-Vorschau.
2. Im Druckdialog unten links „PDF" → „Als PDF sichern…" — erzeugt eine lesbare PDF-Datei
   mit korrekten Fonts/Bildgrößen.
3. Artikel zur Web-Ansicht wechseln, ⌘P drücken — Druckdialog zeigt die tatsächliche
   Originalseite, nicht die Reader-Aufbereitung.
4. Kein Artikel ausgewählt: Drucken-Button/Shortcut deaktiviert.
5. Shortcut ⌘P ist über die Shortcuts-Einstellungsseite umbenennbar/deaktivierbar.
6. Mehrseitiger Artikel (langer Text): Druckvorschau zeigt korrekte Seitenumbrüche.

---

### Task 3: Alten CGContext-PDF-Renderer entfernen

**Files:**
- Modify: `Feedivo/Services/ArticleDocumentExportRenderers.swift`
- Modify: `Feedivo/Services/ArticleExportService.swift`
- Modify: `Feedivo/Services/ArticleExportPackageBuilder.swift`
- Test: `FeedivoTests/ArticleExportServiceTests.swift`

**Interfaces:**
- Consumes: nichts aus Task 1/2 (unabhängig, könnte auch vor Task 1/2 laufen).
- Produces: `ArticleExportService.data(for:options:)`'s `.pdf`-Fall liefert ab jetzt `Data()`
  (leer) statt einer echten PDF — dokumentiert über einen neuen Regressionstest.

**Verifizierte Abweichung von der Design-Spec:** Die Spec behauptet, der zu entfernende Code
habe „0% Testabdeckung — keine Tests zu entfernen". Das ist falsch: `FeedivoTests/ArticleExportServiceTests.swift`
enthält 5 Tests, die genau die zu entfernenden Funktionen direkt testen
(`pdfExportErzeugtGueltigePDFDaten`, `pdfPaketLaedtArtikelbilderAutomatischUndBleibtEinPDFDokument`,
`pdfExportPaginatesLangeArtikelUeberMehrereSeiten`, `pdfExportBehältLesereihenfolgeUndStartetObenAufErsterSeite`,
`packageBuilderGibtPDFAlsNormalesDokumentZurueck`). Dieser Task entfernt sie explizit als Teil
der Aufräumarbeit, statt sie unangetastet zu lassen.

Ebenfalls verifiziert: `ArticlePDFExportRenderer.data(fromHTML:)` (eine der laut Spec zu
entfernenden Funktionen) wird tatsächlich noch von `ArticleExportPackageBuilder.swift`
(PDF-Paket-Zweig, Zeile 65–99) aufgerufen — dieser Zweig muss mitentfernt werden, sonst
bricht der Build. Die `html(...)`-Funktionsfamilie (inkl. der Convenience-Überladung
`html(fromExportedHTML:style:assets:)`) bleibt unverändert bestehen, wie in der Spec
festgelegt — sie wird weiterhin von 3 Tests und vom Druck-Feature (Task 2) sowie von
`ArticleExportSheet.swift`s PDF-Vorschau genutzt.

- [ ] **Step 1: Neuen Regressionstest für den `.pdf`-Fall schreiben (schlägt zunächst fehl)**

In `FeedivoTests/ArticleExportServiceTests.swift`, direkt vor der bestehenden Funktion
`@Test func docxExportErzeugtOpenXMLDokumentMitArtikeltext()` einen neuen Test ergänzen:

```swift
    @Test func pdfFormatIstUeberDialogUnerreichbarUndLiefertLeereDaten() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "PDF", content: "<p>Text</p>")
        )

        let data = ArticleExportService.data(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: true)
        )

        #expect(data.isEmpty)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportServiceTests/pdfFormatIstUeberDialogUnerreichbarUndLiefertLeereDaten -quiet`

Expected: FAIL (`data.isEmpty` ist `false` — der alte Renderer liefert noch echte PDF-Bytes).

- [ ] **Step 3: Alte Renderer-Funktionen aus `ArticleDocumentExportRenderers.swift` entfernen**

In `Feedivo/Services/ArticleDocumentExportRenderers.swift`, den `import AppKit` entfernen
(nach Entfernen der untenstehenden Funktionen wird kein AppKit-Typ mehr in dieser Datei
benötigt — `import Foundation` bleibt):

```swift
import AppKit
import Foundation
```

ersetzen durch:

```swift
import Foundation
```

Die Funktion `data(for:options:style:assets:)` entfernen:

```swift
enum ArticlePDFExportRenderer {
    static func data(
        for snapshot: ArticleExportSnapshot,
        options: ArticleExportOptions,
        style: ArticlePDFExportStyle = .default,
        assets: [ArticleExportPackageAsset] = []
    ) -> Data {
        data(
            fromHTML: html(
                for: snapshot,
                options: options,
                style: style,
                assets: assets
            )
        )
    }

    static func html(
```

ersetzen durch:

```swift
enum ArticlePDFExportRenderer {
    static func html(
```

Die Funktionen `data(fromHTML:)`, `attributedString(fromHTML:)` und `pdfData(from:)` entfernen:

```swift
    static func data(fromHTML html: String) -> Data {
        let attributedString = attributedString(fromHTML: html)
        return pdfData(from: attributedString)
    }

    private static func attributedString(fromHTML html: String) -> NSAttributedString {
        let data = Data(html.utf8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        return (try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        )) ?? NSAttributedString(string: html)
    }

    private static func pdfData(from attributedString: NSAttributedString) -> Data {
        let pageSize = CGSize(width: 595, height: 842)
        let pageInsets = NSEdgeInsets(top: 54, left: 54, bottom: 54, right: 54)
        let contentRect = CGRect(
            x: pageInsets.left,
            y: pageInsets.top,
            width: pageSize.width - pageInsets.left - pageInsets.right,
            height: pageSize.height - pageInsets.top - pageInsets.bottom
        )

        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureGlyphs(forCharacterRange: NSRange(location: 0, length: attributedString.length))

        var pageRanges: [NSRange] = []
        var glyphLocation = 0

        while glyphLocation < layoutManager.numberOfGlyphs {
            let textContainer = NSTextContainer(containerSize: contentRect.size)
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            guard glyphRange.length > 0 else {
                break
            }

            pageRanges.append(glyphRange)
            glyphLocation = NSMaxRange(glyphRange)
        }

        if pageRanges.isEmpty {
            pageRanges.append(NSRange(location: 0, length: 0))
        }

        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            return Data()
        }

        for glyphRange in pageRanges {
            context.beginPDFPage(nil)
            context.saveGState()
            NSGraphicsContext.saveGraphicsState()

            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = graphicsContext

            NSColor.white.setFill()
            CGRect(origin: .zero, size: pageSize).fill()

            layoutManager.drawBackground(forGlyphRange: glyphRange, at: contentRect.origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: contentRect.origin)

            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return output as Data
    }

    private static func bodyHTML(from html: String) -> String {
```

ersetzen durch:

```swift
    private static func bodyHTML(from html: String) -> String {
```

- [ ] **Step 4: `ArticleExportService.data(for:options:)`s `.pdf`-Fall anpassen**

In `Feedivo/Services/ArticleExportService.swift`:

```swift
    static func data(for snapshot: ArticleExportSnapshot, options: ArticleExportOptions) -> Data {
        switch options.format {
        case .markdown, .plainText, .html:
            Data(text(for: snapshot, options: options).utf8)
        case .pdf:
            ArticlePDFExportRenderer.data(for: snapshot, options: options)
        case .docx:
            ArticleDOCXExportRenderer.data(for: snapshot, options: options)
        }
    }
```

ersetzen durch:

```swift
    static func data(for snapshot: ArticleExportSnapshot, options: ArticleExportOptions) -> Data {
        switch options.format {
        case .markdown, .plainText, .html:
            Data(text(for: snapshot, options: options).utf8)
        case .pdf:
            // .pdf ist nicht in ArticleExportFormat.dialogFormats enthalten und ueber die
            // UI nie erreichbar (Feature 25.1 "Drucken" ersetzt PDF-Export durch nativen
            // Druckdialog samt "Als PDF sichern"). Der alte NSAttributedString/CGContext-
            // Renderer wurde entfernt — dieser Fall dient nur noch der Exhaustivitaet.
            Data()
        case .docx:
            ArticleDOCXExportRenderer.data(for: snapshot, options: options)
        }
    }
```

- [ ] **Step 5: `ArticleExportPackageBuilder.swift`s PDF-Zweig entfernen**

In `Feedivo/Services/ArticleExportPackageBuilder.swift`:

```swift
    static func package(
        for snapshot: ArticleExportSnapshot,
        options: ArticleExportOptions,
        includesOfflineImages: Bool,
        imageLoader: ArticleExportImageDataLoading = URLSessionArticleExportImageDataLoader(),
        pdfStyle: ArticlePDFExportStyle = .default,
        progress: @MainActor @escaping (ArticleExportPackageProgress) -> Void = { _ in }
    ) async -> ArticleExportPackage {
        progress(.preparingDocument)

        let originalText = ArticleExportService.text(for: snapshot, options: options)
        let documentFilename = ArticleExportService.defaultFilename(for: snapshot, format: options.format)

        if options.format == .pdf {
            let sourceHTML = ArticleExportService.text(
                for: snapshot,
                options: ArticleExportOptions(format: .html, includesMetadata: options.includesMetadata)
            )
            let imagePackage = await imagePackage(
                from: sourceHTML,
                imageLoader: imageLoader,
                progress: progress
            )
            let rewrittenHTML = textByReplacingImageURLs(in: sourceHTML, replacements: imagePackage.replacements)
            progress(.creatingArchive)
            let pdfData = ArticlePDFExportRenderer.data(
                fromHTML: ArticlePDFExportRenderer.html(
                    fromExportedHTML: rewrittenHTML,
                    style: pdfStyle,
                    assets: imagePackage.assets
                )
            )

            let previewHTML = ArticlePDFExportRenderer.html(
                fromExportedHTML: rewrittenHTML,
                style: pdfStyle,
                assets: imagePackage.assets
            )

            return ArticleExportPackage(
                filename: documentFilename,
                contentType: .document,
                text: previewHTML,
                assets: imagePackage.assets,
                failedImageURLs: imagePackage.failedImageURLs,
                archiveData: pdfData
            )
        }

        guard includesOfflineImages, options.format.supportsOfflineImagePackage else {
```

ersetzen durch:

```swift
    static func package(
        for snapshot: ArticleExportSnapshot,
        options: ArticleExportOptions,
        includesOfflineImages: Bool,
        imageLoader: ArticleExportImageDataLoading = URLSessionArticleExportImageDataLoader(),
        // Nicht mehr im Funktionskoerper verwendet, seit der PDF-spezifische Zweig unten
        // entfernt wurde (Feature 25.1 "Drucken" ersetzt den alten CGContext-PDF-Renderer
        // durch nativen Druck; .pdf ist ueber ArticleExportFormat.dialogFormats ohnehin nie
        // erreichbar). Bleibt fuer Aufrufkompatibilitaet mit ArticleExportSheet.swift stehen.
        pdfStyle: ArticlePDFExportStyle = .default,
        progress: @MainActor @escaping (ArticleExportPackageProgress) -> Void = { _ in }
    ) async -> ArticleExportPackage {
        progress(.preparingDocument)

        let originalText = ArticleExportService.text(for: snapshot, options: options)
        let documentFilename = ArticleExportService.defaultFilename(for: snapshot, format: options.format)

        guard includesOfflineImages, options.format.supportsOfflineImagePackage else {
```

- [ ] **Step 6: Die 5 nun ungültigen PDF-Renderer-Tests + verwaisten Helper entfernen**

In `FeedivoTests/ArticleExportServiceTests.swift` den `import PDFKit` entfernen (wird nach
Entfernen der untenstehenden Tests nirgends mehr benötigt):

```swift
import Foundation
import PDFKit
import Testing
@testable import Feedivo
```

ersetzen durch:

```swift
import Foundation
import Testing
@testable import Feedivo
```

Test `pdfExportErzeugtGueltigePDFDaten` entfernen:

```swift
    @Test func pdfExportErzeugtGueltigePDFDaten() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "PDF Export",
                link: "https://example.com/pdf",
                content: "<h2>Untertitel</h2><p>Ein lesbarer Absatz.</p>"
            )
        )

        let data = ArticleExportService.data(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: true)
        )

        #expect(data.starts(with: Data("%PDF".utf8)))
        #expect(data.count > 500)
    }

    @Test func pdfHTMLVerwendetReaderTypografieUndEingebetteteBilder() {
```

ersetzen durch:

```swift
    @Test func pdfHTMLVerwendetReaderTypografieUndEingebetteteBilder() {
```

Test `pdfPaketLaedtArtikelbilderAutomatischUndBleibtEinPDFDokument` entfernen:

```swift
    @Test func pdfPaketLaedtArtikelbilderAutomatischUndBleibtEinPDFDokument() async throws {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "PDF Bilder",
                content: #"<p>Intro</p><img src="https://example.com/photo.png"><p>Outro</p>"#
            )
        )
        let imageURL = try #require(URL(string: "https://example.com/photo.png"))
        var progressEvents: [ArticleExportPackageProgress] = []

        let package = await ArticleExportPackageBuilder.package(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: false),
            includesOfflineImages: false,
            imageLoader: StubArticleExportImageLoader(payloads: [
                imageURL: Data([0x01, 0x02, 0x03])
            ]),
            progress: { progressEvents.append($0) }
        )

        #expect(package.filename == "PDF Bilder.pdf")
        #expect(package.contentType == .document)
        #expect(package.archiveData.starts(with: Data("%PDF".utf8)))
        #expect(package.assets.map(\.path) == ["Pictures/image-1.png"])
        #expect(package.failedImageURLs.isEmpty)
        #expect(progressEvents == [
            .preparingDocument,
            .downloadingImage(current: 1, total: 1),
            .creatingArchive
        ])
    }

    @Test func pdfExportPaginatesLangeArtikelUeberMehrereSeiten() {
        let paragraphs = (1 ... 180)
            .map { "<p>Absatz \($0): Dies ist bewusst langer Exporttext für die PDF-Paginierung.</p>" }
            .joined()
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "Langer PDF Export", content: paragraphs)
        )

        let data = ArticleExportService.data(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: false)
        )

        #expect(pdfPageCount(in: data) > 1)
    }

    @Test func pdfExportBehältLesereihenfolgeUndStartetObenAufErsterSeite() throws {
        let paragraphs = (1 ... 120)
            .map { "<p>Absatz-\($0) Lesereihenfolge im PDF Export.</p>" }
            .joined()
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "PDF Reihenfolge", content: paragraphs)
        )
        let data = ArticleExportService.data(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: false)
        )
        let document = try #require(PDFDocument(data: data))
        let firstPage = try #require(document.page(at: 0))
        let lastPage = try #require(document.page(at: document.pageCount - 1))
        let firstPageText = firstPage.string ?? ""
        let lastPageText = lastPage.string ?? ""
        let titleSelection = try #require(document.findString("PDF Reihenfolge", withOptions: []).first)
        let titleBounds = titleSelection.bounds(for: firstPage)
        let pageBounds = firstPage.bounds(for: .mediaBox)

        #expect(firstPageText.contains("PDF Reihenfolge"))
        #expect(firstPageText.contains("Absatz-1"))
        #expect(!firstPageText.contains("Absatz-120"))
        #expect(lastPageText.contains("Absatz-120"))
        #expect(titleBounds.midY > pageBounds.height * 0.65)
    }

    @Test func docxExportErzeugtOpenXMLDokumentMitArtikeltext() {
```

ersetzen durch:

```swift
    @Test func docxExportErzeugtOpenXMLDokumentMitArtikeltext() {
```

Test `packageBuilderGibtPDFAlsNormalesDokumentZurueck` entfernen:

```swift
    @Test func packageBuilderGibtPDFAlsNormalesDokumentZurueck() async {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "PDF Paket", content: "<p>Artikeltext</p>")
        )

        let package = await ArticleExportPackageBuilder.package(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: false),
            includesOfflineImages: true
        )

        #expect(package.filename == "PDF Paket.pdf")
        #expect(package.contentType == .document)
        #expect(package.archiveData.starts(with: Data("%PDF".utf8)))
    }

    @Test func packageBuilderGibtDOCXAlsNormalesDokumentZurueck() async {
```

ersetzen durch:

```swift
    @Test func packageBuilderGibtDOCXAlsNormalesDokumentZurueck() async {
```

Verwaisten Helper `pdfPageCount(in:)` am Dateiende entfernen:

```swift
private func pdfPageCount(in data: Data) -> Int {
    String(decoding: data, as: UTF8.self)
        .components(separatedBy: "/Type /Page")
        .count - 1
}
```

(diese Funktion und ihre schließende `}` komplett löschen — falls sie nicht die letzten
Zeilen der Datei sind, nur den gezeigten Block entfernen, nichts danach anfassen)

- [ ] **Step 7: Vollständigen Testlauf für beide betroffenen Test-Suiten ausführen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportServiceTests -quiet`

Expected: PASS (alle verbleibenden Tests in `ArticleExportServiceTests.swift` grün,
insbesondere `pdfFormatIstUeberDialogUnerreichbarUndLiefertLeereDaten`,
`pdfHTMLVerwendetReaderTypografieUndEingebetteteBilder`,
`pdfHTMLEnthaeltReaderHeaderUndSichtbareMetadaten`,
`pdfHTMLRendertUnsichereMetadatenLinksNurAlsText`,
`docxExportErzeugtOpenXMLDokumentMitArtikeltext`,
`packageBuilderGibtDOCXAlsNormalesDokumentZurueck`).

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -quiet`

Expected: `BUILD SUCCEEDED` (stellt sicher, dass `ArticleExportSheet.swift`s weiterhin
bestehende Aufrufe von `ArticlePDFExportRenderer.html(...)` und `pdfStyle` unverändert kompilieren).

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/ArticleDocumentExportRenderers.swift Feedivo/Services/ArticleExportService.swift Feedivo/Services/ArticleExportPackageBuilder.swift FeedivoTests/ArticleExportServiceTests.swift
git commit -m "Refactor: Alten CGContext-PDF-Renderer entfernt (abgeloest durch nativen Druck, Feature 25.1)"
```

---

### Task 4: `FEATURES.md` aktualisieren

**Files:**
- Modify: `FEATURES.md`

**Interfaces:**
- Consumes: nichts (reine Dokumentation).
- Produces: nichts (kein Code).

- [ ] **Step 1: Feature-25.1-Eintrag aktualisieren**

In `FEATURES.md`:

```markdown
### 25.1 Artikel drucken
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - `Cmd+P` druckt den aktuellen Artikel
  - Im Druckdialog wählt der User: Reader-Darstellung oder Original-Webseite
  - Metadaten (Datum, Feed-Name, URL) im Druckbild optional
```

ersetzen durch:

```markdown
### 25.1 Artikel drucken
- **Status:** ✅ Umgesetzt (2026-07-17)
- **Umgesetzt:**
  - `Cmd+P` druckt den aktuellen Artikel über den nativen macOS-Druckdialog
  - Druckinhalt folgt automatisch der aktuellen Reader-Ansicht (nativ oder Original-
    Webseite) — kein zusätzlicher Umschalter im Druckdialog (Nutzerentscheidung,
    siehe `docs/superpowers/specs/2026-07-17-artikel-drucken-design.md`)
  - Native Ansicht druckt immer mit Metadaten, kein Metadaten-Toggle im Druckdialog
  - PDF-Export läuft ausschließlich über den Standard-PDF-Button jedes macOS-
    Druckdialogs (kein eigener PDF-Renderer mehr — der alte, qualitativ
    eingeschränkte `NSAttributedString`/`CGContext`-basierte Renderer wurde entfernt)
```

- [ ] **Step 2: Commit**

```bash
git add FEATURES.md
git commit -m "Docs: Feature 25.1 (Artikel drucken) als umgesetzt markiert"
```
