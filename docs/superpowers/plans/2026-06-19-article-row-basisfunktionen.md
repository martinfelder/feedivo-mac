# ArticleRow Basisfunktionen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die Artikelliste bekommt eine echte reichhaltige `ArticleRowView` mit optionalem Bild, Ungelesen-Punkt rechts oben, Stern rechts unten, Statusaktionen und einer Benutzereinstellung fuer automatisches Gelesen-Markieren beim Oeffnen.

**Architecture:** SwiftUI/macOS mit bestehendem MVVM-Stil. Statuslogik liegt in einem kleinen `@Observable` `ArticleViewModel`, UI bleibt in `ArticleRowView` und `ArticleListView`, die Einstellung wird via `@AppStorage("markArticleReadOnSelection")` gespeichert und im macOS-Settings-Fenster angeboten.

**Tech Stack:** SwiftUI, SwiftData `@Model`, `@Observable`, `@AppStorage`, Swift Testing, Xcode 26.

---

## Task 1: ArticleViewModel Statuslogik testen und implementieren

- [ ] In `FeedivoTests/ArticleViewModelTests.swift` Tests fuer `toggleRead`, `toggleStarred` und `markReadIfNeeded` anlegen.
- [ ] In `Feedivo/ViewModels/ArticleViewModel.swift` ein `@Observable` ViewModel erstellen.
- [ ] Keine Persistenz-API direkt im ViewModel noetig; SwiftData beobachtet die `@Model`-Aenderungen.

Erwartete Implementierung:

```swift
import Observation

@Observable
class ArticleViewModel {
    func toggleRead(_ article: Article) {
        article.isRead.toggle()
    }

    func toggleStarred(_ article: Article) {
        article.isStarred.toggle()
    }

    func markReadIfNeeded(_ article: Article?, isEnabled: Bool) {
        guard isEnabled, let article, !article.isRead else {
            return
        }

        article.isRead = true
    }
}
```

## Task 2: Datumshilfe fuer Artikelzeilen

- [ ] In `Feedivo/Extensions/Date+RelativeDisplay.swift` eine kleine Extension anlegen.
- [ ] Ausgabe soll fuer heute relative Zeit zeigen und sonst ein kurzes Datum.
- [ ] Kein neuer Formatter-Stack in jeder Zeile.

Erwartete Implementierung:

```swift
import Foundation

extension Date {
    var feedivoRelativeDisplay: String {
        if Calendar.current.isDateInToday(self) {
            return Self.relativeFormatter.localizedString(for: self, relativeTo: .now)
        }

        return Self.shortDateFormatter.string(from: self)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}
```

## Task 3: ArticleRowView bauen

- [ ] `Feedivo/Views/ArticleList/ArticleRowView.swift` erstellen.
- [ ] Layout: optionales Bild links, Inhalt mittig, rechte Statusspalte mit Punkt oben und Stern unten.
- [ ] Stern als Button mit `star` / `star.fill`, Tooltip und plain button style.
- [ ] Kontextmenue mit "Als gelesen markieren" oder "Als ungelesen markieren".
- [ ] Gelesene Artikel optisch ruhiger darstellen.

## Task 4: ArticleListView integrieren

- [ ] Inline-`VStack` durch `ArticleRowView` ersetzen.
- [ ] Lokales `@State private var viewModel = ArticleViewModel()` verwenden.
- [ ] `@AppStorage("markArticleReadOnSelection") private var markArticleReadOnSelection = true` einbauen.
- [ ] Bei Auswahlwechsel `viewModel.markReadIfNeeded(selectedArticle, isEnabled: markArticleReadOnSelection)` ausfuehren.

## Task 5: SettingsView und App-Settings-Szene

- [ ] `Feedivo/Views/Settings/SettingsView.swift` erstellen.
- [ ] Toggle fuer "Artikel beim Oeffnen als gelesen markieren" via `@AppStorage`.
- [ ] In `Feedivo/App/FeedivoApp.swift` eine `Settings { SettingsView() }` Szene ergaenzen.

## Task 6: Dokumentation nachfuehren

- [ ] `docs/FEATURES.md` aktualisieren: Entscheidung ist nicht mehr offen.
- [ ] `AGENTS.md` aktualisieren: aktueller Stand, implementierte Dateien, Gotcha/Entscheidung.
- [ ] `docs/superpowers/specs/2026-06-19-article-row-basisfunktionen-design.md` bleibt die fachliche Quelle fuer die gewaehlte UI-Richtung.

## Task 7: Verifikation

- [ ] `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'` ausfuehren.
- [ ] `git status --short --branch` pruefen.
- [ ] Nur eigene Aenderungen committen; bestehende Xcode-User-State-Datei nicht versehentlich bereinigen.
