# Suchfenster Split-View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Das Artikel-Suchfenster (`ArticleSearchWindowView`) wird zweispaltig (Liste + Reader-Vorschau) und lässt Treffer per Klick/Doppelklick ansehen, ohne die App zu verlassen.

**Architecture:** Reine SwiftUI-Änderung an einer bestehenden View. Die Vorschau ist eine leichtgewichtige, neue private Subview, die nur bereits geladene Daten (`ArticleListSnapshot`) anzeigt — kein neues Reader-Rendering. "Vollständig öffnen" nutzt den bereits produktiven `openWindow(value: ArticleWindowRequest(articleID:))`-Mechanismus.

**Tech Stack:** SwiftUI (macOS), bestehende `ArticleListSnapshot`/`ArticleWindowRequest`-Typen, `tools/l10n_inject.py` für xcstrings-Pflege.

## Global Constraints

- Fenstergröße: `minWidth` steigt von 620 auf 900, `minHeight` bleibt bei 460.
- Vorschau zeigt nur vorhandene Felder (Titel, Feed, Datum, `summary`) — kein neues HTML-/Content-Parsing.
- "Vollständig im Reader öffnen" ruft exakt `openWindow(value: ArticleWindowRequest(articleID: uuid))`, denselben Aufruf wie `ContentView.openSQLiteArticleInWindow(articleID:)` (`Feedivo/Views/ContentView.swift:418-427`).
- Einfacher Klick wählt aus und lädt die Vorschau; Doppelklick öffnet zusätzlich direkt das Reader-Fenster.
- Bestehender "Original öffnen"-Safari-Button pro Zeile bleibt unverändert erhalten.
- Der zweizeilige Header-Block (Icon+Titel+Beschreibungstext) entfällt; der jetzt ungenutzte L10n-Key `article.search.window.description` wird entfernt.
- Neue Strings ausschließlich über `tools/l10n_inject.py` in `Feedivo/Resources/Localizable.xcstrings` einpflegen (Projekt-Standardwerkzeug), nicht per Hand editieren.

---

### Task 1: L10n-Keys für Vorschau ergänzen, ungenutzten Key entfernen

**Files:**
- Create (temporär, nicht committen): `/tmp/l10n-search-preview.tsv`
- Modify: `Feedivo/Resources/Localizable.xcstrings` (per Skript + gezielte Löschung)
- Modify: `Feedivo/Resources/L10n.swift:343` (Key-Zeile ersetzen/ergänzen)

**Interfaces:**
- Produces: `L10n.articleSearchOpenInReader: String`, `L10n.articleSearchPreviewEmptyTitle: String`, `L10n.articleSearchPreviewEmptyDescription: String` — von Task 3 konsumiert.

- [ ] **Step 1: TSV mit den drei neuen Keys anlegen**

Datei `/tmp/l10n-search-preview.tsv` mit exakt diesem Inhalt (Tab-getrennt, Header-Zeile Pflicht):

```
key	de	en	fr	it
article.search.openInReader	Vollständig im Reader öffnen	Open fully in Reader	Ouvrir entièrement dans le lecteur	Apri completamente nel Reader
article.search.preview.emptyTitle	Kein Artikel ausgewählt	No article selected	Aucun article sélectionné	Nessun articolo selezionato
article.search.preview.emptyDescription	Wähle einen Treffer aus der Liste, um ihn hier anzusehen.	Select a result from the list to view it here.	Sélectionnez un résultat dans la liste pour l'afficher ici.	Seleziona un risultato dall'elenco per visualizzarlo qui.
```

- [ ] **Step 2: Keys injizieren**

Run (von `/Users/martinfelder/Developer/FeedivoMac` aus):
```bash
python3 tools/l10n_inject.py --mode plain --table /tmp/l10n-search-preview.tsv
```
Expected: `plain: 3 Keys injiziert -> Feedivo/Resources/Localizable.xcstrings`

- [ ] **Step 3: Ungenutzten Key `article.search.window.description` entfernen**

Run:
```bash
python3 -c "
import json
path = 'Feedivo/Resources/Localizable.xcstrings'
with open(path, encoding='utf-8') as f:
    doc = json.load(f)
del doc['strings']['article.search.window.description']
doc['strings'] = dict(sorted(doc['strings'].items()))
with open(path, 'w', encoding='utf-8') as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write('\n')
print('removed article.search.window.description')
"
```
Expected: `removed article.search.window.description`

- [ ] **Step 4: `L10n.swift` anpassen**

In `Feedivo/Resources/L10n.swift` die Zeile 343 ersetzen:

```swift
    static let articleSearchWindowDescription = LocalizedStringKey("article.search.window.description")
```

durch:

```swift
    static let articleSearchOpenInReader = String(localized: "article.search.openInReader")
    static let articleSearchPreviewEmptyTitle = String(localized: "article.search.preview.emptyTitle")
    static let articleSearchPreviewEmptyDescription = String(localized: "article.search.preview.emptyDescription")
```

- [ ] **Step 5: Bauen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **` (der Build schlägt fehl, falls `Localizable.xcstrings` kein valides JSON mehr ist oder ein referenzierter Key fehlt — das ist der Test für diesen Task)

- [ ] **Step 6: Temporäre TSV löschen und committen**

```bash
rm /tmp/l10n-search-preview.tsv
git add Feedivo/Resources/Localizable.xcstrings Feedivo/Resources/L10n.swift
git commit -m "L10n: Suchfenster-Vorschau-Strings ergaenzen, ungenutzten Header-Key entfernen"
```

---

### Task 2: Header kompakter machen, Fenster verbreitern

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift:46` (frame)
- Modify: `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift:70-142` (`searchHeader`)

**Interfaces:**
- Consumes: `L10n.articleSearchPlaceholder`, `L10n.articleSearchClear`, `L10n.articleSearchMatchCount(_:)` (bereits vorhanden, unverändert)
- Produces: nichts, reine Layout-Änderung

- [ ] **Step 1: Fensterbreite anpassen**

In `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift` Zeile 46 ersetzen:

```swift
        .frame(minWidth: 620, minHeight: 460)
```

durch:

```swift
        .frame(minWidth: 900, minHeight: 460)
```

- [ ] **Step 2: `searchHeader` kompakter machen**

Den gesamten `searchHeader`-Body (aktuell Zeilen 70–142) ersetzen:

```swift
    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
                    .background(.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.articleSearchCommand)
                        .font(.headline)

                    Text(L10n.articleSearchWindowDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(L10n.articleSearchMatchCount(snapshots.count))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.blue.opacity(0.13), in: Capsule())
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(L10n.articleSearchPlaceholder, text: $searchState.searchText)
                    .textFieldStyle(.plain)

                if !searchState.searchText.isEmpty || searchState.query.filters.isActive {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(L10n.articleSearchClear)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.background, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.separator.opacity(0.5), lineWidth: 1)
            }

            HStack(spacing: 8) {
                searchFieldPicker
                searchFeedPicker
                searchTagPicker
                searchDatePicker
                searchStatusPicker
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Color.blue.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
```

durch:

```swift
    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(L10n.articleSearchPlaceholder, text: $searchState.searchText)
                    .textFieldStyle(.plain)

                if !searchState.searchText.isEmpty || searchState.query.filters.isActive {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(L10n.articleSearchClear)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.background, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.separator.opacity(0.5), lineWidth: 1)
            }

            HStack(spacing: 8) {
                searchFieldPicker
                searchFeedPicker
                searchTagPicker
                searchDatePicker
                searchStatusPicker
                Spacer(minLength: 0)

                Text(L10n.articleSearchMatchCount(snapshots.count))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.blue.opacity(0.13), in: Capsule())
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color.blue.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
```

Hinweis: Diese neue Version referenziert `L10n.articleSearchWindowDescription` **nicht mehr** — das ist beabsichtigt, dieser Key wurde in Task 1 entfernt. Falls Task 1 noch nicht gelaufen ist, schlägt der Build hier fehl; die Tasks müssen in Reihenfolge 1→2→3 ausgeführt werden.

- [ ] **Step 3: Bauen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manuell verifizieren**

App starten, Suchfenster öffnen (Cmd+F oder Lupe-Icon):
- Fenster ist deutlich breiter, kein doppelzeiliger Erklärtext mehr oben.
- Treffer-Zähler steht jetzt rechts neben den Filtern.
- Suchfeld und Filter funktionieren wie zuvor.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleSearchWindowView.swift
git commit -m "Suchfenster: Header kompakter, Fenster verbreitert"
```

---

### Task 3: Split-View mit Reader-Vorschau, Doppelklick öffnet Reader-Fenster

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift` (state, `body`, `resultList`, neue `previewPanel`/`openInReaderWindow`, neue `ArticleSearchPreviewView`, Dedup der Datumsformatierung)

**Interfaces:**
- Consumes: `L10n.articleSearchOpenInReader`, `L10n.articleSearchPreviewEmptyTitle`, `L10n.articleSearchPreviewEmptyDescription` (aus Task 1), `ArticleWindowRequest(articleID: UUID)` (`Feedivo/Views/Reader/ArticleWindowView.swift:3-9`), `ArticleListSnapshot` (`Feedivo/Snapshots/ArticleListSnapshot.swift`, Felder `id: String`, `title: String`, `feedTitle: String`, `summary: String?`, `link: String?`, `publishedAt: Date?`)
- Produces: nichts weiter, terminale UI-Änderung

- [ ] **Step 1: `@Environment(\.openWindow)` und Auswahl-State ergänzen**

In `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift` nach Zeile 6 (`@Environment(\.feedivoDatabase) private var database`) einfügen:

```swift
    @Environment(\.openWindow) private var openWindow
```

Nach der Deklaration von `@State private var loadErrorMessage: String?` (aktuell Zeile 17) einfügen:

```swift
    @State private var selectedResultID: String?
```

- [ ] **Step 2: `body` auf Split-View umstellen**

Den `body` (aktuell Zeilen 34–68) ersetzen — nur der `if snapshots.isEmpty`-Zweig ändert sich, der Rest bleibt:

```swift
    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Divider()

            if snapshots.isEmpty {
                emptyState
            } else {
                HSplitView {
                    resultList

                    previewPanel
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 460)
        // P4: Debounce des Suchtextes. `.task(id:)` bricht die vorherige Aufgabe
        // ab, sobald sich der Text ändert — committet nur nach 250 ms ohne
        // weiteren Tastendruck. Leeres Feld wird sofort committet (kein Lag beim
        // Löschen/Freimachen).
        .task(id: searchState.searchText) {
            if searchState.searchText.isEmpty {
                debouncedSearchText = ""
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !Task.isCancelled {
                debouncedSearchText = searchState.searchText
            }
        }
        .task(id: searchLoadToken) {
            loadSnapshots()
        }
        .task(id: sqliteStatusVersion) {
            loadFeeds()
            loadTags()
        }
    }
```

- [ ] **Step 3: `resultList` auf Auswahl + Doppelklick umstellen**

`resultList` (aktuell Zeilen 198–205) ersetzen:

```swift
    private var resultList: some View {
        List(snapshots) { snapshot in
            ArticleSearchResultRow(snapshot: snapshot) {
                openOriginal(snapshot)
            }
        }
        .listStyle(.inset)
    }
```

durch:

```swift
    private var resultList: some View {
        List(snapshots, selection: $selectedResultID) { snapshot in
            ArticleSearchResultRow(snapshot: snapshot) {
                openOriginal(snapshot)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                openInReaderWindow(snapshot)
            }
        }
        .listStyle(.inset)
        .frame(minWidth: 260, idealWidth: 340)
    }
```

- [ ] **Step 4: Vorschau-Panel und `openInReaderWindow` ergänzen**

Nach `resultList` (nach dem in Step 3 geänderten Block) einfügen:

```swift
    @ViewBuilder
    private var previewPanel: some View {
        if let selectedSnapshot {
            ArticleSearchPreviewView(
                snapshot: selectedSnapshot,
                onOpenInReader: { openInReaderWindow(selectedSnapshot) },
                onOpenOriginal: { openOriginal(selectedSnapshot) }
            )
        } else {
            ContentUnavailableView(
                L10n.articleSearchPreviewEmptyTitle,
                systemImage: "doc.text.magnifyingglass",
                description: Text(L10n.articleSearchPreviewEmptyDescription)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedSnapshot: ArticleListSnapshot? {
        snapshots.first { $0.id == selectedResultID }
    }

    private func openInReaderWindow(_ snapshot: ArticleListSnapshot) {
        guard let uuid = UUID(uuidString: snapshot.id) else {
            return
        }

        openWindow(value: ArticleWindowRequest(articleID: uuid))
    }
```

- [ ] **Step 5: Datumsformatierung deduplizieren**

In `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift` ganz unten, vor der schließenden `}` der Datei, eine geteilte Hilfsfunktion einfügen:

```swift
private func formattedArticleDate(_ date: Date?) -> String {
    guard let date else {
        return "Unbekannt"
    }

    return date.formatted(date: .abbreviated, time: .omitted)
}
```

In `ArticleSearchResultRow` die bestehende private `formattedDate`-Computed-Property entfernen:

```swift
    private var formattedDate: String {
        guard let publishedAt = snapshot.publishedAt else {
            return "Unbekannt"
        }

        return publishedAt.formatted(date: .abbreviated, time: .omitted)
    }
```

und die eine Verwendungsstelle in `ArticleSearchResultRow.body` (`Text(formattedDate)`) durch `Text(formattedArticleDate(snapshot.publishedAt))` ersetzen.

- [ ] **Step 6: Neue `ArticleSearchPreviewView` anlegen**

Am Ende der Datei `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift` (nach `ArticleSearchResultRow`) einfügen:

```swift
private struct ArticleSearchPreviewView: View {
    let snapshot: ArticleListSnapshot
    let onOpenInReader: () -> Void
    let onOpenOriginal: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(snapshot.title)
                    .font(.title3)
                    .fontWeight(.semibold)

                HStack(spacing: 6) {
                    Text(snapshot.feedTitle)
                    Text("·")
                    Text(formattedArticleDate(snapshot.publishedAt))
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if let summary = snapshot.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(L10n.articleSearchOpenInReader) {
                        onOpenInReader()
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onOpenOriginal()
                    } label: {
                        Label(L10n.articleOpenOriginalCommand, systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    .disabled(snapshot.link == nil)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 7: Bauen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Manuell verifizieren**

App starten, Suchfenster öffnen, nach etwas suchen, das Treffer liefert:
- Liste links, leeres Vorschau-Panel rechts ("Kein Artikel ausgewählt") vor jeder Auswahl.
- Einfacher Klick auf eine Zeile lädt Titel/Feed/Datum/Summary rechts.
- Klick auf "Vollständig im Reader öffnen" öffnet ein natives Reader-Fenster mit dem Artikel.
- Klick auf "Original öffnen" in der Vorschau öffnet den Link im Standardbrowser.
- Doppelklick auf eine Zeile in der Liste öffnet direkt das Reader-Fenster (wie der Button).
- Der bestehende Safari-Icon-Button pro Zeile funktioniert weiterhin wie zuvor.

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleSearchWindowView.swift
git commit -m "Suchfenster: Split-View mit Reader-Vorschau und Doppelklick-Oeffnen"
```

---

## Self-Review

**Spec coverage:** Alle Punkte aus der Spec sind abgedeckt — Task 1 liefert die neuen Strings und entfernt den ungenutzten Key, Task 2 setzt Fensterbreite und kompakten Header um, Task 3 liefert Split-View, Auswahl-State, leichte Vorschau, Doppelklick-Verhalten und die Wiederverwendung von `openWindow(value: ArticleWindowRequest(articleID:))`. Das ausgeklammerte HTML-in-Summary-Problem ist explizit als Nicht-Ziel benannt und hat keine Aufgabe — korrekt, da es außerhalb dieser Spec liegt.

**Placeholder-Scan:** Keine TBD/TODO, vollständiger Code in jedem Schritt.

**Typ-Konsistenz:** `ArticleListSnapshot.id` ist `String` (siehe `Feedivo/Snapshots/ArticleListSnapshot.swift:4`), `selectedResultID` ist `String?` — passt zu `List(_:selection:)`. `ArticleWindowRequest.articleID` ist `UUID` (`Feedivo/Views/Reader/ArticleWindowView.swift:4`), daher `UUID(uuidString: snapshot.id)` in `openInReaderWindow`. `formattedArticleDate` wird in Task 3 einmal definiert und von beiden Views (`ArticleSearchResultRow`, `ArticleSearchPreviewView`) verwendet — keine Dopplung.
