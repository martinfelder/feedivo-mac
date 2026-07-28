# Regex-Validierung bei Regeln — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finding 1.5 beheben — eine ungültige Regex in einer Regel-Bedingung
(`.regex`-Operator) wird aktuell klaglos gespeichert und matcht danach für
immer nichts, ohne dass der Nutzer je erfährt, dass sein Muster kaputt ist.
`RuleWizardView.save()` soll das Muster vor dem Speichern validieren und bei
einem ungültigen Muster einen klaren, sichtbaren Fehler zeigen statt die
Regel stillschweigend zu persistieren.

**Architecture:** Es existiert bereits ein passender, aber ungenutzter
Baustein: `RuleConditionOperator.isValidRegexPattern(_:)`
(`Feedivo/Models/RuleConditionOperator.swift:31-33`), aktuell nur von der
toten `RuleViewModel.normalizedConditions(from:)` verwendet
(`Feedivo/ViewModels/RuleViewModel.swift:246`). Dieser Plan macht ihn zum
ersten Mal produktiv nutzbar: eine neue, pure, testbare Hilfsfunktion
`RuleConditionOperator.firstInvalidRegexValue(in:)` prüft eine Liste von
`RuleConditionDraft`s (bereits vorhandener, reiner Struct-Typ,
`Feedivo/ViewModels/RuleViewModel.swift:8-13`, wird auch vom produktiven
`RuleWizardView` genutzt) auf das erste ungültige Regex-Muster.
`RuleWizardView.save()` ruft sie vor dem eigentlichen Speichern auf.

**Tech Stack:** SwiftUI, Foundation `NSRegularExpression`, Swift Testing
(`@testable import Feedivo`).

## Global Constraints

- Arbeitsweise für diese Gruppe: Commits direkt auf `main` (Nutzerentscheid
  für diese Gruppe, keine generelle Regel).
- Kommentare im Code auf Deutsch (Projektkonvention laut CLAUDE.md).
- Kein Logging von ungültigen Mustern in `RuleEngine.regularExpression`
  ergänzen — das war im Original-Finding nur als optionale Zusatzidee
  ("könnte zusätzlich") markiert, nicht als geforderter Fix, und würde eine
  DB-Schreibabhängigkeit in eine aktuell reine Berechnungsfunktion
  einführen. Bewusst nicht Teil dieser Gruppe.
- Die Live-Vorschau-Ambiguität (`previewMatchingCount = 0` unterscheidet
  nicht zwischen "wirklich 0 Treffer" und "Regex kaputt",
  `RuleWizardView.swift:630-644`) ist ebenfalls NICHT Teil dieser Gruppe —
  sobald ungültige Muster beim Speichern abgelehnt werden, kann eine
  bereits gespeicherte Regel gar kein ungültiges Muster mehr enthalten;
  die Ambiguität besteht nur noch während des Tippens vor dem Speichern.
- Volle Testsuite hängt (CLAUDE.md-Gotcha) — immer gezielt mit
  `-only-testing:FeedivoTests/<SuiteName>` testen.

---

### Task 1: Regex-Validierung beim Speichern einer Regel

**Files:**
- Modify: `Feedivo/Models/RuleConditionOperator.swift` (neue Hilfsfunktion)
- Modify: `Feedivo/Resources/L10n.swift` (neuer Fehler-Key)
- Modify: `Feedivo/Resources/Localizable.xcstrings` (de/en/fr/it)
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift:646-707` (`save()`)
- Test: `FeedivoTests/RuleConditionOperatorTests.swift` (neu)

**Interfaces:**
- Produces: `RuleConditionOperator.firstInvalidRegexValue(in drafts: [RuleConditionDraft]) -> String?`
  — `nil`, wenn alle `.regex`-Bedingungen ein gültiges Muster haben (oder
  keine `.regex`-Bedingung existiert), sonst der Wert (das rohe
  Musterstring) der ERSTEN Bedingung mit ungültigem Muster.
- Produces: `L10n.ruleRegexInvalidError(pattern: String) -> String`.
- Consumes: `RuleConditionOperator.isValidRegexPattern(_:) -> Bool`
  (bereits vorhanden, `Feedivo/Models/RuleConditionOperator.swift:31-33`,
  unverändert), `RuleConditionDraft` (bereits vorhanden,
  `Feedivo/ViewModels/RuleViewModel.swift:8-13`, unverändert).

**Vorher** (`Feedivo/Views/Rules/RuleWizardView.swift:646-673`):
```swift
    private func save() {
        guard let database = feedivoDatabase else {
            ruleError = L10n.feedPropertiesUnavailable
            return
        }

        let drafts = mode == .simple ? Array(conditionDrafts.prefix(1)) : conditionDrafts
        let normalizedDrafts = drafts.compactMap { draft -> RuleConditionDraft? in
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return RuleConditionDraft(
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: value
            )
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !normalizedDrafts.isEmpty,
              action != .assignTag || selectedTag != nil
        else {
            ruleError = L10n.ruleValidationError
            return
        }

        let ruleID = rule?.id ?? UUID().uuidString
        // ... (Rest unveraendert)
```

- [ ] **Step 1: Failing Test schreiben**

Neue Datei `FeedivoTests/RuleConditionOperatorTests.swift` anlegen:

```swift
import Foundation
import Testing
@testable import Feedivo

struct RuleConditionOperatorTests {
    @Test func firstInvalidRegexValueIstNilWennAlleMusterGueltigSind() {
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "Swift"),
            RuleConditionDraft(field: .summary, conditionOperator: .regex, value: "^Foo.*Bar$")
        ]

        #expect(RuleConditionOperator.firstInvalidRegexValue(in: drafts) == nil)
    }

    @Test func firstInvalidRegexValueIstNilWennKeineRegexBedingungExistiert() {
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "("),
            RuleConditionDraft(field: .summary, conditionOperator: .equals, value: "[")
        ]

        #expect(RuleConditionOperator.firstInvalidRegexValue(in: drafts) == nil)
    }

    @Test func firstInvalidRegexValueLiefertDasErsteUngueltigeMuster() {
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .regex, value: "gueltig.*"),
            RuleConditionDraft(field: .summary, conditionOperator: .regex, value: "("),
            RuleConditionDraft(field: .author, conditionOperator: .regex, value: "[")
        ]

        #expect(RuleConditionOperator.firstInvalidRegexValue(in: drafts) == "(")
    }
}
```

- [ ] **Step 2: Test laufen lassen, RED verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleConditionOperatorTests -parallel-testing-enabled NO`
Expected: Compile-Fehler — `firstInvalidRegexValue(in:)` existiert auf
`RuleConditionOperator` noch nicht.

- [ ] **Step 3: Minimale Implementierung der Hilfsfunktion**

In `Feedivo/Models/RuleConditionOperator.swift`, direkt nach
`isValidRegexPattern(_:)` (nach Zeile 33, vor der schließenden `}` des
Enums) einfügen:

```swift

    static func firstInvalidRegexValue(in drafts: [RuleConditionDraft]) -> String? {
        drafts.first { draft in
            draft.conditionOperator == .regex && !isValidRegexPattern(draft.value)
        }?.value
    }
```

- [ ] **Step 4: Test laufen lassen, GREEN verifizieren**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleConditionOperatorTests -parallel-testing-enabled NO`
Expected: Alle 3 Tests PASS.

- [ ] **Step 5: L10n-Key ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach `ruleValidationError`
(Zeile 513) einfügen:

```swift
    static func ruleRegexInvalidError(pattern: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "rule.regex.invalidError"),
            pattern
        )
    }
```

In `Feedivo/Resources/Localizable.xcstrings`, per präziser Text-Insertion
(NICHT per `json.dump`-Reserialize — reformatiert bekanntermaßen die
gesamte ~18.600-Zeilen-Datei) den neuen Eintrag `"rule.regex.invalidError"`
alphabetisch korrekt einsortieren (zwischen den bestehenden `"rule.*"`-Keys,
z. B. direkt vor `"rule.settings.description"` oder an passender
alphabetischer Stelle — `"regex"` liegt nach `"operator"` und vor
`"settings"`), mit vollständigen de/en/fr/it-Übersetzungen:
- de: "Das Regex-Muster „%@" ist ungültig."
- en: "The regex pattern \"%@\" is invalid."
- fr: "Le motif d'expression régulière « %@ » n'est pas valide."
- it: "Il modello regex \"%@\" non è valido."

- [ ] **Step 6: Validierung in `RuleWizardView.save()` verdrahten**

In `Feedivo/Views/Rules/RuleWizardView.swift`, direkt nach dem bestehenden
`guard`-Block (aktuell Zeilen 666-673, endet mit `return` im `else`-Zweig)
und VOR `let ruleID = rule?.id ?? UUID().uuidString` (aktuell Zeile 675)
einfügen:

```swift
        if let invalidPattern = RuleConditionOperator.firstInvalidRegexValue(in: normalizedDrafts) {
            ruleError = L10n.ruleRegexInvalidError(pattern: invalidPattern)
            return
        }
```

- [ ] **Step 7: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: JSON-Validität prüfen**

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings'))" && echo OK`
Expected: `OK`

- [ ] **Step 9: `git diff --stat` auf `Localizable.xcstrings` prüfen**

Run: `git diff --stat Feedivo/Resources/Localizable.xcstrings`
Expected: Nur der eine neue Eintrag (ein vollständiger 4-Sprachen-Block),
keine Reformatierung der restlichen Datei.

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Models/RuleConditionOperator.swift FeedivoTests/RuleConditionOperatorTests.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/Rules/RuleWizardView.swift
git commit -m "Fix: Ungueltige Regex in Regel-Bedingungen wird beim Speichern abgelehnt statt dauerhaft nichts zu matchen (Finding 1.5)"
```

---

## Abschluss dieser Gruppe

Nach Task 1: finaler Whole-Group-Review (bei nur einem Task ggf. kombiniert
mit dem Task-Review, je nach Einschätzung während der Umsetzung), dann kurze
Zusammenfassung für den Nutzer (Commits, Testergebnis), dann Rückfrage, ob
mit Gruppe 4 (SQL-/HTML-Duplikation konsolidieren, Findings 1.8 + 1.9)
fortgefahren werden soll — inklusive erneuter Nachfrage main vs. eigener
Branch für diese nächste Gruppe.
