# Restposten Code-Qualitäts-Review — Gruppe C (UI-Feedback-Konsistenz) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die letzten drei offenen UI-Feedback-Findings aus dem Code-Qualitäts-Review vom
2026-07-11 (`docs/superpowers/reviews/2026-07-11-code-quality-review.md`, Finding 2.10 +
zwei Funde aus Abschnitt 3) beheben — fehlendes Ladefeedback beim OPML-Import-Button,
fehlende lokale URL-Syntax-Validierung beim OPML-Parsen (Netzwerk-Roundtrip für offensichtlich
kaputte URLs wird verschwendet) und die nicht unterscheidbare Anzeige von "0 Treffer" vs.
"Fehler beim Laden der Vorschau" in der Regel-Vorschau.

**Architecture:** Alle drei Fixes sind lokal begrenzte Änderungen an bestehenden Dateien, keine
neuen Typen/Abstraktionen. Task 1 und 3 sind reine SwiftUI-View-Rendering-Änderungen (kein
automatisierter Test möglich, da weder `OPMLImportReviewView.swift` noch `RuleWizardView.swift`
existierende Test-Dateien haben — Verifikation über Build + manuelle Sichtprüfung, analog zum
bereits etablierten Muster für reine View-Änderungen in diesem Projekt, z. B. Dark-Mode-Arbeit).
Task 2 hat testbare Logik auf Service-Ebene (`SQLiteFeedSubscriptionService.previewOPMLFeeds`)
und wird strikt per TDD umgesetzt.

**Tech Stack:** SwiftUI (macOS 14+), GRDB/SQLite, Swift Testing (kein XCTest).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- Neue `L10n.swift`-Einträge folgen der bestehenden Cluster-Konvention (siehe Task-Details) —
  keine neuen Plural-Inline-Ausnahmen anlegen, außer explizit gefordert.
- Neue `Localizable.xcstrings`-Einträge müssen alle vier Sprachen enthalten (`de`, `en`, `fr`,
  `it`) und an der alphabetisch korrekten Stelle im JSON stehen (Datei ist strikt alphabetisch
  nach Key sortiert).
- Build-Verifikation ausschließlich über `xcodebuild build` — SourceKit-Diagnosen in der IDE
  sind unzuverlässig (siehe CLAUDE.md-Gotcha).
- Tests ausschließlich gezielt mit `-only-testing:FeedivoTests/<SuiteName>` ausführen — die
  volle Testsuite hängt reproduzierbar.
- Keine SwiftData-Wiedereinführung, keine neuen Abstraktionen für diese drei kleinen,
  unabhängigen Fixes (YAGNI).

---

## Task 1: OPML-Import-Button zeigt Ladefeedback während des Imports

**Files:**
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift:460-464`
- Modify: `Feedivo/Resources/L10n.swift:672` (neue Zeile danach einfügen)
- Modify: `Feedivo/Resources/Localizable.xcstrings` (neuer Key `opml.import.button.importing`,
  alphabetisch zwischen `opml.import.button.import` und `opml.import.cancel`, also nach
  Zeile 12291 `},` und vor Zeile 12292 `"opml.import.cancel" : {`)

**Interfaces:**
- Konsumiert: `feedViewModel.isLoading: Bool` (bereits vorhanden, `FeedViewModel.swift:82`,
  wird schon für `.disabled(...)` an derselben Stelle genutzt).
- Produziert: nichts, das andere Tasks brauchen (eigenständige View-Änderung).

**Kontext:** Der Import-Button (`OPMLImportReviewView.swift:460-464`) wird während
`feedViewModel.isLoading` nur `.disabled(...)`, das Label bleibt aber statisch
("N Feeds importieren"). Bei vielen ausgewählten Feeds kann das wie ein nicht reagierender
Button wirken (Finding 2.10 im Review). Fix: Spinner + Statustext im Button-Label, solange
`feedViewModel.isLoading == true`.

- [ ] **Step 1: Neuen L10n-Key `opml.import.button.importing` in `Localizable.xcstrings` anlegen**

Füge in `Feedivo/Resources/Localizable.xcstrings` zwischen dem Ende von
`"opml.import.button.import"` (endet mit `},` kurz vor `"opml.import.cancel" : {`) folgenden
Block ein:

```json
    "opml.import.button.importing" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Wird importiert..."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Importing..."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Importation en cours..."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Importazione in corso..."
          }
        }
      }
    },
```

- [ ] **Step 2: L10n-Accessor in `L10n.swift` ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach Zeile 672
(`static let opmlImportAllowUnreachable = String(localized: "opml.import.allowUnreachable")`)
und vor `static let opmlImportCancel = ...` einfügen:

```swift
    static let opmlImportButtonImporting = String(localized: "opml.import.button.importing")
```

- [ ] **Step 3: Button-Label in `OPMLImportReviewView.swift` um Ladezustand erweitern**

Ersetze in `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift` (aktuell Zeilen 460-464):

```swift
            Button(importButtonTitle) {
                importSelectedFeeds()
            }
            .buttonStyle(OPMLPrimaryButtonStyle(theme: theme))
            .disabled(previewController.selectedImportRows.isEmpty || previewController.isPreparingPreview || feedViewModel.isLoading)
```

durch:

```swift
            Button {
                importSelectedFeeds()
            } label: {
                if feedViewModel.isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text(L10n.opmlImportButtonImporting)
                    }
                } else {
                    Text(importButtonTitle)
                }
            }
            .buttonStyle(OPMLPrimaryButtonStyle(theme: theme))
            .disabled(previewController.selectedImportRows.isEmpty || previewController.isPreparingPreview || feedViewModel.isLoading)
```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build 2>&1 | tail -30`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: `git status`/`git diff --stat` auf `Localizable.xcstrings` prüfen**

Stelle sicher, dass der Build keine zusätzlichen automatischen Stub-Einträge in
`Localizable.xcstrings` hinzugefügt hat (bekannter Gotcha, siehe CLAUDE.md). Falls doch, den
Stub bewusst mitcommitten.

- [ ] **Step 6: Manuelle Sichtprüfung (kein automatisierter Test möglich)**

`OPMLImportReviewView.swift` hat keine Test-Datei — die Änderung ist reines View-Rendering.
Notiere im Task-Report, dass eine manuelle visuelle Verifikation (Import mit vielen Feeds
starten, Spinner + "Wird importiert..." beobachten) noch aussteht, analog zu anderen reinen
UI-Änderungen in diesem Projekt.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/OPMLImport/OPMLImportReviewView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Fix: OPML-Import-Button zeigt Spinner + Statustext während des Imports (Finding 2.10)"
```

---

## Task 2: OPML-Parsing validiert URL-Syntax lokal statt nur per Netzwerk-Roundtrip

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift:344-365` (Phase-1-Schleife in
  `previewOPMLFeeds`), neue private Helper-Funktion nahe `normalizedFeedURL` (aktuell Zeile 484)
- Test: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift` (neuer Test nach
  `previewMarkiertDuplikateUndNichtErreichbareFeeds`, aktuell endet bei Zeile 439)

**Interfaces:**
- Konsumiert: `OPMLImportFeedStatus` (bereits vorhanden, `.available`/`.duplicate`/
  `.unreachable`, `SQLiteFeedSubscriptionService.swift:40-44`), `OPMLImportPreviewRow`
  (bereits vorhanden, `SQLiteFeedSubscriptionService.swift:46-50`).
- Produziert: private Helper `isSyntacticallyValidFeedURL(_ urlString: String) -> Bool` —
  nur intern in `SQLiteFeedSubscriptionService` genutzt, kein anderer Task braucht die Signatur.

**Kontext:** `previewOPMLFeeds` prüft Erreichbarkeit ausschließlich über einen echten
Netzwerk-Fetch (`fetchFeed(item.cleanedURL)`, Zeile 382). Offensichtlich syntaktisch kaputte
URLs (Leerzeichen, fehlendes Schema) laufen trotzdem durch den vollen Netzwerk-Roundtrip, bevor
sie als `.unreachable` erkannt werden — unnötige Latenz und Netzwerklast bei einer rein lokal
erkennbaren Eigenschaft (Review Abschnitt 3, `OPMLService.swift:200-233`-Fund). Fix: Phase 1
(die bereits sequenziell über alle Feeds läuft und Duplikate lokal erkennt) bekommt zusätzlich
eine lokale URL-Syntax-Prüfung; nur syntaktisch plausible URLs werden für den Netzwerk-Fetch in
Phase 2 vorgemerkt.

**Wichtig:** Der bestehende Test `previewParalleelisiertBehaeltReihenfolgeUndStatus`
(`SQLiteFeedSubscriptionServiceTests.swift:476-508`) nutzt bewusst `xmlURL: "fail://broken"`
als Platzhalter für eine URL, die *syntaktisch gültig* ist (Schema `fail`, Host `broken`), aber
beim eigentlichen Fetch fehlschlägt. Die neue Prüfung darf `fail://broken` NICHT als ungültig
markieren, sonst bricht dieser Test semantisch (er würde weiterhin `.unreachable` liefern, aber
nicht mehr über den gemockten `fetchFeed`-Aufruf, was die Testabsicht unterläuft). Die Prüfung
verlangt daher nur `scheme != nil && host != nil`, keine Beschränkung auf `http`/`https`.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Füge in `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift` direkt nach
`previewMarkiertDuplikateUndNichtErreichbareFeeds` (nach der schließenden `}` bei Zeile 439)
ein:

```swift
    @MainActor
    @Test func previewMarkiertSyntaktischUngueltigeURLsSofortAlsNichtErreichbarOhneNetzwerkAufruf() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        var fetchCallCount = 0
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { urlString in
                fetchCallCount += 1
                return ParsedFeed(sourceURL: urlString, title: "OK", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        let rows = await service.previewOPMLFeeds(for: [
            OPMLFeed(title: "Mit Leerzeichen", xmlURL: "not a valid url", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "Ohne Schema", xmlURL: "example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "Gueltig", xmlURL: "https://example.com/feed.xml", htmlURL: nil, folderName: nil)
        ])

        #expect(rows.map(\.status) == [.unreachable, .unreachable, .available])
        #expect(rows.map(\.isSelected) == [false, false, true])
        #expect(fetchCallCount == 1)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests 2>&1 | tail -60`
Expected: `previewMarkiertSyntaktischUngueltigeURLsSofortAlsNichtErreichbarOhneNetzwerkAufruf`
schlägt fehl — `fetchCallCount` ist `3` statt `1` (alle drei URLs lösen aktuell einen
Netzwerk-Fetch aus), `rows[0].status`/`rows[1].status` sind `.available` statt `.unreachable`
(der Mock gibt für jede URL erfolgreich ein `ParsedFeed` zurück).

- [ ] **Step 3: `isSyntacticallyValidFeedURL`-Helper implementieren**

Füge in `Feedivo/Services/SQLiteFeedSubscriptionService.swift` direkt vor
`private func normalizedFeedURL(_ urlString: String) -> String {` (aktuell Zeile 484) ein:

```swift
    /// Lokale Syntax-Prüfung für OPML-`xmlUrl`-Werte, bevor ein Netzwerk-Fetch versucht
    /// wird. Verlangt nur Schema + Host (kein `http`/`https`-Zwang), damit z. B. Test-
    /// Platzhalter wie `fail://broken` weiterhin über den echten Fetch-Pfad laufen und
    /// nicht schon hier als "ungültig" abgefangen werden.
    private func isSyntacticallyValidFeedURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let scheme = url.scheme, !scheme.isEmpty, url.host != nil else {
            return false
        }
        return true
    }

```

- [ ] **Step 4: Phase-1-Schleife in `previewOPMLFeeds` um die Prüfung erweitern**

Ersetze in `Feedivo/Services/SQLiteFeedSubscriptionService.swift` (aktuell Zeilen 356-364):

```swift
            if isDuplicate {
                rowsByIndex[index] = OPMLImportPreviewRow(
                    feed: opmlFeed,
                    status: .duplicate,
                    isSelected: false
                )
            } else {
                pending.append(PendingFeed(index: index, cleanedURL: cleanedURL))
            }
```

durch:

```swift
            if isDuplicate {
                rowsByIndex[index] = OPMLImportPreviewRow(
                    feed: opmlFeed,
                    status: .duplicate,
                    isSelected: false
                )
            } else if !isSyntacticallyValidFeedURL(cleanedURL) {
                // Offensichtlich kaputte URLs (Leerzeichen, fehlendes Schema) sofort als
                // nicht erreichbar markieren statt einen Netzwerk-Roundtrip zu verschwenden,
                // der ohnehin fehlschlagen würde.
                rowsByIndex[index] = OPMLImportPreviewRow(
                    feed: opmlFeed,
                    status: .unreachable,
                    isSelected: false
                )
            } else {
                pending.append(PendingFeed(index: index, cleanedURL: cleanedURL))
            }
```

- [ ] **Step 5: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests 2>&1 | tail -60`
Expected: alle Tests in `SQLiteFeedSubscriptionServiceTests` PASS, inkl. des neuen Tests und
inkl. `previewMarkiertDuplikateUndNichtErreichbareFeeds` sowie
`previewParalleelisiertBehaeltReihenfolgeUndStatus` (letzterer bleibt grün, weil
`fail://broken` weiterhin als syntaktisch gültig gilt).

- [ ] **Step 6: Verwandten Test in `FeedViewModelTests.swift` gezielt mitlaufen lassen**

`FeedViewModelTests.swift:590-630` nutzt denselben `fail://broken`-Platzhalter über
`viewModel.opmlImportPreviewRows`, das intern denselben Service-Pfad nutzt. Run:
`xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests 2>&1 | tail -80`
Expected: PASS (bis auf die zwei bereits bekannten, dokumentierten flaky-unter-Last-Tests,
siehe CLAUDE.md-Gotchas — falls die dort fehlschlagen, isoliert erneut laufen lassen).

- [ ] **Step 7: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build 2>&1 | tail -30`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/SQLiteFeedSubscriptionService.swift FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift
git commit -m "Fix: OPML-Import validiert URL-Syntax lokal vor Netzwerk-Fetch (Abschnitt 3, OPMLService-Fund)"
```

---

## Task 3: Regel-Vorschau unterscheidet "0 Treffer" von "Vorschau fehlgeschlagen"

**Files:**
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift:77` (neuer `@State`), `:267-289`
  (Anzeige-Block), `:630-644` (`reloadPreviewCount()`)
- Modify: `Feedivo/Resources/L10n.swift:829` (neuer Eintrag direkt vor
  `static func ruleWizardPreviewMatchCount`)
- Modify: `Feedivo/Resources/Localizable.xcstrings` (neuer Key `ruleWizard.preview.error`,
  alphabetisch zwischen `ruleWizard.notifyAction.hint` (endet vor Zeile 19565) und
  `ruleWizard.preview.matchCount` (Zeile 19565))

**Interfaces:**
- Konsumiert: `theme.destructiveText: Color` (bereits vorhanden,
  `RuleDialogTheme.swift:25`, aktuell u. a. für Lösch-Zustände genutzt).
- Produziert: nichts, das andere Tasks brauchen (eigenständige View-Änderung).

**Kontext:** `reloadPreviewCount()` (`RuleWizardView.swift:630-644`) setzt bei fehlender
Datenbank UND bei jedem Fehler aus `SQLiteRuleEvaluationStore.matchingArticleCount(...)`
identisch `previewMatchingCount = 0` — die Anzeige (Zeile 277,
`Text(L10n.ruleWizardPreviewMatchCount(count: previewMatchingCount))`) zeigt in beiden Fällen
"0 Artikel passen", identisch zu einem echten Null-Treffer-Ergebnis (Review Abschnitt 3-Fund).
Fix: neuer `previewLoadFailed`-State unterscheidet die beiden Fälle visuell (Warnsymbol +
`destructiveText`-Farbe + eigener Text statt Trefferzahl).

- [ ] **Step 1: Neuen L10n-Key `ruleWizard.preview.error` in `Localizable.xcstrings` anlegen**

Füge in `Feedivo/Resources/Localizable.xcstrings` direkt vor dem Block
`"ruleWizard.preview.matchCount" : {` (Zeile 19565) ein:

```json
    "ruleWizard.preview.error" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Vorschau nicht verfügbar"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Preview unavailable"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aperçu indisponible"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Anteprima non disponibile"
          }
        }
      }
    },
```

- [ ] **Step 2: L10n-Accessor in `L10n.swift` ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt vor
`static func ruleWizardPreviewMatchCount(count: Int) -> String {` (aktuell Zeile 829/830)
einfügen:

```swift
    static let ruleWizardPreviewError = String(localized: "ruleWizard.preview.error")

```

- [ ] **Step 3: `previewLoadFailed`-State in `RuleWizardView.swift` ergänzen**

Direkt nach `@State private var previewMatchingCount = 0` (aktuell Zeile 77) einfügen:

```swift
    @State private var previewLoadFailed = false
```

- [ ] **Step 4: `reloadPreviewCount()` beide Fehlerpfade markieren lassen**

Ersetze in `Feedivo/Views/Rules/RuleWizardView.swift` (aktuell Zeilen 630-644):

```swift
    private func reloadPreviewCount() async {
        guard let database = feedivoDatabase else {
            previewMatchingCount = 0
            return
        }

        do {
            previewMatchingCount = try SQLiteRuleEvaluationStore(database: database).matchingArticleCount(
                conditionDrafts: activeConditionDrafts,
                matchMode: activeMatchMode
            )
        } catch {
            previewMatchingCount = 0
        }
    }
```

durch:

```swift
    private func reloadPreviewCount() async {
        guard let database = feedivoDatabase else {
            previewMatchingCount = 0
            previewLoadFailed = true
            return
        }

        do {
            previewMatchingCount = try SQLiteRuleEvaluationStore(database: database).matchingArticleCount(
                conditionDrafts: activeConditionDrafts,
                matchMode: activeMatchMode
            )
            previewLoadFailed = false
        } catch {
            previewMatchingCount = 0
            previewLoadFailed = true
        }
    }
```

- [ ] **Step 5: Anzeige-Block visuell unterscheiden**

Ersetze in `Feedivo/Views/Rules/RuleWizardView.swift` (aktuell Zeilen 267-289):

```swift
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(theme.accent, lineWidth: 2)
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 3, height: 3)
                }

                Text(L10n.ruleWizardPreviewMatchCount(count: previewMatchingCount))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accent.opacity(0.09))
            )
            .padding(.top, 14)
```

durch:

```swift
            HStack(spacing: 8) {
                let previewTint = previewLoadFailed ? theme.destructiveText : theme.accent

                if previewLoadFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(previewTint)
                } else {
                    ZStack {
                        Circle()
                            .stroke(previewTint, lineWidth: 2)
                            .frame(width: 14, height: 14)
                        Circle()
                            .fill(previewTint)
                            .frame(width: 3, height: 3)
                    }
                }

                Text(previewLoadFailed ? L10n.ruleWizardPreviewError : L10n.ruleWizardPreviewMatchCount(count: previewMatchingCount))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(previewTint)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((previewLoadFailed ? theme.destructiveText : theme.accent).opacity(0.09))
            )
            .padding(.top, 14)
```

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug build 2>&1 | tail -30`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Manuelle Sichtprüfung (kein automatisierter Test möglich)**

`RuleWizardView.swift` hat keine Test-Datei — die Änderung ist reines View-State/Rendering.
Notiere im Task-Report, dass eine manuelle visuelle Verifikation (Regel-Assistent ohne
Datenbank bzw. mit ungültigen Bedingungen öffnen, Warnsymbol + "Vorschau nicht verfügbar"
statt "0 Artikel passen" beobachten) noch aussteht.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/Rules/RuleWizardView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Fix: Regel-Vorschau unterscheidet 0-Treffer von Ladefehler (Abschnitt 3, RuleWizardView-Fund)"
```

---

## Empfohlene Reihenfolge

Die drei Tasks sind unabhängig voneinander (unterschiedliche Dateien, keine gemeinsamen Typen)
und können in beliebiger Reihenfolge umgesetzt werden. Task 2 hat als einziger Task einen
echten automatisierten Test — bei Zeitdruck zuerst umsetzen, da er am eindeutigsten verifizierbar
ist.

## Nach Abschluss aller drei Tasks

- Whole-Branch-Review (Opus) über alle drei Commits, analog zu Gruppe A und B.
- Bei grünem Review: Commits auf `origin/main` pushen (nur nach expliziter Nutzerbestätigung,
  siehe CLAUDE.md "Push-Konvention").
- Damit ist die komplette Restposten-Code-Qualitäts-Review (Gruppen A, B, C) abgeschlossen.
