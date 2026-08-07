# YouTube-Video-Hinweis im nativen Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Im nativen Reader einen Hinweis-Banner einblenden, sobald der aktuell angezeigte
Artikel ein YouTube-Video ist, mit einem Button, der direkt in die Original-Ansicht
(WKWebView) wechselt, wo das Video tatsächlich abspielbar ist.

**Architecture:** Ein reiner, isoliert testbarer Helfer (`YouTubeVideoLink.isVideoURL(_:)`)
erkennt YouTube-Video-Links anhand der bereits vorhandenen Artikel-URL (`originalURL`, exakt
dieselbe, die "Original-Ansicht" und "Im Browser öffnen" schon verwenden). Der native Reader
(`SQLiteReaderView.readerHeader(_:)`) rendert bei einem Treffer einen Info-Banner nach dem
bestehenden `feedErrorBanner`-Muster (Icon + Text + Button, farbiger Hintergrund), dessen
Button den bereits vorhandenen `readerDisplayModeRawValue`-Umschalter auf `.web` setzt.

**Tech Stack:** Swift, SwiftUI, Swift Testing (`@Test`/`#expect`, kein XCTest).

## Global Constraints

- Kein eingebetteter Video-Player im nativen Reader — nur ein Hinweis-Banner mit Umschalt-
  Button in die bestehende Original-Ansicht.
- Kein zusätzlicher Code für YouTube-Login/Session-Verwaltung — `WebContentView.swift:54`
  nutzt bereits den persistenten `WKWebsiteDataStore.default()` ohne eigene Zuweisung.
- Erkennung ausschließlich über den Artikel-Link (`originalURL`/`snapshot.link`) — keine
  Erkennung über die Feed-Quelle oder `yt:videoId`.
- Banner-Stil folgt dem bestehenden `feedErrorBanner`-Muster
  (`SQLiteFeedArticleListView.swift:345`: `HStack` mit Icon, Text, Spacer, Button, farbiger
  Hintergrund bei niedriger Opazität) — hier in Accent- statt Warnfarbe, Icon
  `play.rectangle.fill` statt `exclamationmark.triangle.fill`.
- Exakter Text (DE/EN, siehe Spec):
  - Hinweistext DE: "Dies ist ein YouTube-Video. In der Original-Ansicht kannst du es
    abspielen und dich bei YouTube anmelden."
  - Hinweistext EN: "This is a YouTube video. Switch to the original view to watch it and
    sign in to YouTube."
  - Button DE: "Original-Ansicht öffnen"
  - Button EN: "Open Original View"
- Neue L10n-Keys müssen manuell (nicht per `json.load`/`json.dump`-Roundtrip) in
  `Localizable.xcstrings` ergänzt werden — Xcodes Auto-Stub-Mechanismus greift bei indirekten
  `L10n`-Keys nicht (bestehender CLAUDE.md-Gotcha). Das Projekt lokalisiert in 4 Sprachen
  (de/en/fr/it, siehe bestehende Einträge in `Localizable.xcstrings`) — neue Keys brauchen
  alle vier, sonst ist die Lokalisierung unvollständig gegenüber bestehenden Keys.
- Kein Dismiss/keine Persistenz für den Banner — er erscheint zuverlässig bei jedem
  erkannten Video-Artikel im nativen Modus.
- Kein neuer automatisierter UI-Test für die reine Banner-Platzierung (kein computer-use für
  native macOS-Apps in dieser Umgebung verfügbar) — Build-Verifikation reicht, manuelle
  Live-Verifikation durch den Nutzer am Ende.

---

### Task 1: YouTubeVideoLink-Erkennungshelfer

**Files:**
- Create: `Feedivo/Extensions/YouTubeVideoLink.swift`
- Test: `FeedivoTests/Extensions/YouTubeVideoLinkTests.swift`

**Interfaces:**
- Produces: `enum YouTubeVideoLink { static func isVideoURL(_ url: URL?) -> Bool }` — wird von
  Task 2 in `SQLiteReaderView.readerHeader(_:)` konsumiert (`YouTubeVideoLink.isVideoURL(originalURL)`).

- [ ] **Step 1: Schreibe die fehlschlagenden Tests**

Erstelle `FeedivoTests/Extensions/YouTubeVideoLinkTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct YouTubeVideoLinkTests {
    @Test func erkenntWatchURLMitWWWAlsVideo() {
        #expect(YouTubeVideoLink.isVideoURL(URL(string: "https://www.youtube.com/watch?v=abc123")))
    }

    @Test func erkenntWatchURLOhneWWWAlsVideo() {
        #expect(YouTubeVideoLink.isVideoURL(URL(string: "https://youtube.com/watch?v=abc123")))
    }

    @Test func erkenntMobileWatchURLAlsVideo() {
        #expect(YouTubeVideoLink.isVideoURL(URL(string: "https://m.youtube.com/watch?v=abc123")))
    }

    @Test func erkenntShortsURLAlsVideo() {
        #expect(YouTubeVideoLink.isVideoURL(URL(string: "https://www.youtube.com/shorts/abc123")))
    }

    @Test func erkenntYoutuBeKurzlinkAlsVideo() {
        #expect(YouTubeVideoLink.isVideoURL(URL(string: "https://youtu.be/abc123")))
    }

    @Test func erkenntKanalSeiteNichtAlsVideo() {
        #expect(!YouTubeVideoLink.isVideoURL(URL(string: "https://www.youtube.com/@Apple")))
    }

    @Test func erkenntFremdeDomaneMitWatchPfadNichtAlsVideo() {
        #expect(!YouTubeVideoLink.isVideoURL(URL(string: "https://example.com/watch")))
    }

    @Test func erkenntNilNichtAlsVideo() {
        #expect(!YouTubeVideoLink.isVideoURL(nil))
    }
}
```

- [ ] **Step 2: Verifiziere, dass die Tests fehlschlagen (RED)**

Run: `xcodebuild -scheme Feedivo -configuration Debug -only-testing:FeedivoTests/YouTubeVideoLinkTests build-for-testing 2>&1 | grep -E "error:|TEST"`
Expected: Compile-Fehler `cannot find 'YouTubeVideoLink' in scope` (oder `has no member`), da der Typ noch nicht existiert.

- [ ] **Step 3: Implementiere den Helfer**

Erstelle `Feedivo/Extensions/YouTubeVideoLink.swift`:

```swift
import Foundation

/// Erkennt, ob eine URL auf ein einzelnes YouTube-Video zeigt (Watch-Seite, Shorts oder
/// youtu.be-Kurzlink) — genutzt vom Reader, um bei YouTube-Video-Artikeln auf die
/// Original-Ansicht hinzuweisen, wo das Video tatsächlich abspielbar ist.
enum YouTubeVideoLink {
    static func isVideoURL(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else {
            return false
        }

        if host == "youtu.be" {
            return true
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else {
            return false
        }

        let path = url?.path ?? ""
        return path == "/watch" || path.hasPrefix("/shorts/")
    }
}
```

- [ ] **Step 4: Verifiziere, dass die Tests bestehen (GREEN)**

Run: `xcodebuild -scheme Feedivo -configuration Debug -only-testing:FeedivoTests/YouTubeVideoLinkTests test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, alle 8 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Extensions/YouTubeVideoLink.swift FeedivoTests/Extensions/YouTubeVideoLinkTests.swift
git commit -m "feat: YouTube-Video-Link-Erkennung für den Reader-Hinweis"
```

---

### Task 2: Hinweis-Banner im nativen Reader

**Files:**
- Modify: `Feedivo/Resources/L10n.swift:88` (zwei neue Keys nach `readerOpenOriginal`)
- Modify: `Feedivo/Resources/Localizable.xcstrings` (zwei neue Katalogeinträge, 4 Sprachen)
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift:509-536` (`readerHeader(_:)`)

**Interfaces:**
- Consumes: `YouTubeVideoLink.isVideoURL(_ url: URL?) -> Bool` aus Task 1; bestehendes
  `originalURL: URL?` (privater computed var in `SQLiteReaderView`, Zeile 459); bestehendes
  `@AppStorage private var readerDisplayModeRawValue: String` (Zeile 66-67); bestehendes
  `ReaderDisplayMode.web` (Enum-Fall in `ReaderDisplayMode.swift`).

- [ ] **Step 1: L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`, füge nach der Zeile

```swift
    static let readerOpenOriginal = LocalizedStringKey("reader.openOriginal")
```

folgende zwei neuen Zeilen ein (davor, im selben Block, vor `readerAppearanceButton`):

```swift
    static let readerYouTubeVideoHintMessage = LocalizedStringKey("reader.youTubeVideoHint.message")
    static let readerYouTubeVideoHintButton = LocalizedStringKey("reader.youTubeVideoHint.button")
```

- [ ] **Step 2: Lokalisierungskatalog ergänzen**

In `Feedivo/Resources/Localizable.xcstrings`: Finde exakt diesen bestehenden Block (Anker
für die Einfügung, NICHT die Datei per `json.load`/`json.dump` roundtripen — siehe
bestehender CLAUDE.md-Gotcha dazu):

```
    "reader.openOriginal" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Original öffnen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Open original"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ouvrir l'original"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apri originale"
          }
        }
      }
    },
    "reader.readability.error.emptyResult" : {
```

Füge zwischen der schließenden `},` von `reader.openOriginal` und der Zeile
`"reader.readability.error.emptyResult" : {` folgende zwei neuen Katalogeinträge ein:

```
    "reader.youTubeVideoHint.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Original-Ansicht öffnen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Open Original View"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ouvrir la vue originale"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apri visualizzazione originale"
          }
        }
      }
    },
    "reader.youTubeVideoHint.message" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dies ist ein YouTube-Video. In der Original-Ansicht kannst du es abspielen und dich bei YouTube anmelden."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "This is a YouTube video. Switch to the original view to watch it and sign in to YouTube."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ceci est une vidéo YouTube. Passez à la vue originale pour la regarder et vous connecter à YouTube."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Questo è un video di YouTube. Passa alla visualizzazione originale per guardarlo e accedere a YouTube."
          }
        }
      }
    },
```

Danach verifizieren, dass jeder neue Key genau einmal vorkommt und die Datei sich nur um die
neuen Zeilen vergrößert hat:

Run: `grep -c '"reader.youTubeVideoHint.button"\|"reader.youTubeVideoHint.message"' Feedivo/Resources/Localizable.xcstrings`
Expected: `2`

Run: `git diff --stat Feedivo/Resources/Localizable.xcstrings`
Expected: Nur Insertions (ca. 50 Zeilen), keine oder kaum Deletions.

- [ ] **Step 3: Banner in `readerHeader(_:)` einbauen**

In `Feedivo/Views/Reader/SQLiteReaderView.swift`, ersetze die bestehende Funktion (Zeilen
509-536):

```swift
    private func readerHeader(_ snapshot: ArticleReaderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            if !state.preparedArticle.metadataText.isEmpty {
                Text(state.preparedArticle.metadataText)
                    .font(interfaceTextSize.font(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                openOriginal()
            } label: {
                Text(snapshot.title)
                    .font(titleFontPreset.font(
                        size: CGFloat(ReaderTypography.defaultTitleFontSize),
                        relativeTo: .largeTitle,
                        weight: titleFontWeight
                    ))
                    .fontWeight(titleFontWeight)
                    .lineSpacing(clampedTitleLineSpacing)
                    .textSelection(.enabled)
            }
            .buttonStyle(.plain)
            .disabled(originalURL == nil)

            readerArticleMetadata(snapshot)
        }
    }
```

durch:

```swift
    private func readerHeader(_ snapshot: ArticleReaderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            if !state.preparedArticle.metadataText.isEmpty {
                Text(state.preparedArticle.metadataText)
                    .font(interfaceTextSize.font(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                openOriginal()
            } label: {
                Text(snapshot.title)
                    .font(titleFontPreset.font(
                        size: CGFloat(ReaderTypography.defaultTitleFontSize),
                        relativeTo: .largeTitle,
                        weight: titleFontWeight
                    ))
                    .fontWeight(titleFontWeight)
                    .lineSpacing(clampedTitleLineSpacing)
                    .textSelection(.enabled)
            }
            .buttonStyle(.plain)
            .disabled(originalURL == nil)

            if YouTubeVideoLink.isVideoURL(originalURL) {
                youTubeVideoHintBanner
            }

            readerArticleMetadata(snapshot)
        }
    }

    private var youTubeVideoHintBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.rectangle.fill")
                .foregroundStyle(Color.accentColor)

            Text(L10n.readerYouTubeVideoHintMessage)
                .font(interfaceTextSize.font(size: 12))

            Spacer()

            Button(L10n.readerYouTubeVideoHintButton) {
                readerDisplayModeRawValue = ReaderDisplayMode.web.rawValue
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
```

(Die abgerundete Hintergrundform statt einer flachen Streifen-Bar wie bei `feedErrorBanner`
ist eine bewusste kleine Anpassung an die umgebende Reader-Optik, die bereits abgerundete
Ordner-/Tag-Chips direkt darunter verwendet — funktional identisches Icon+Text+Button-Muster.)

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild -scheme Feedivo -configuration Debug build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Bestehende Reader-Tests gegenprüfen (keine Regression)**

Run: `xcodebuild -scheme Feedivo -configuration Debug -only-testing:FeedivoTests/YouTubeVideoLinkTests test 2>&1 | tail -10`
Expected: weiterhin `** TEST SUCCEEDED **` (reiner Regressions-Check, diese Suite ist von
Task 2 inhaltlich nicht betroffen, bestätigt aber, dass der Build insgesamt konsistent bleibt).

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/Reader/SQLiteReaderView.swift
git commit -m "feat: Hinweis-Banner für YouTube-Videos im nativen Reader"
```

**Manuelle Live-Verifikation (nicht automatisierbar, durch den Nutzer):**
1. Einen zuvor abonnierten YouTube-Kanal öffnen, einen Video-Artikel im nativen Lesemodus
   anzeigen — Banner mit Hinweistext und "Original-Ansicht öffnen"-Button ist sichtbar,
   direkt unter dem Titel.
2. Klick auf den Button wechselt in die Original-Ansicht, die echte YouTube-Watch-Seite lädt.
3. Zurück in den nativen Modus wechseln, einen Nicht-Video-Artikel (z. B. aus einem normalen
   Blog-Feed) öffnen — kein Banner sichtbar.
4. Hell-/Dunkelmodus: Banner-Farbe (Accent-Ton) wirkt in beiden Darstellungen stimmig.
