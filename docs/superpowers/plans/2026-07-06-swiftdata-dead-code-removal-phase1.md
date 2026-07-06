# Toten SwiftData-Code entfernen — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Den nachweislich unerreichbaren SwiftData-Baum (Legacy-Reader/-Artikelliste/-Inspector, ihre ViewModels und sechs tote Backfill/Cleanup-Services) vollständig aus dem Produktivcode entfernen, ohne den aktiven SQLite-Pfad anzufassen.

**Architecture:** Reine Lösch-Operation. Zwei Typen (`ArticleInspectorTypography`, `FlowLayout`), die in einer sonst toten Datei stecken, werden zuerst in eigene Dateien verschoben, weil aktive Views sie mitbenutzen. Danach werden 13 Produktivdateien und 4 zugehörige Testdateien gelöscht, in einer Reihenfolge, die sicherstellt, dass niemals eine Datei gelöscht wird, während noch etwas anderes sie referenziert.

**Tech Stack:** Swift, SwiftUI, Swift Testing (`@Test`/`#expect`), xcodebuild.

## Global Constraints

- Kein `.modelContainer(...)` existiert mehr in der App — jeder gelöschte Code ist bereits vor dieser Änderung unerreichbar, es wird kein Nutzerverhalten verändert.
- Nach jedem Task muss der Build grün sein, bevor der nächste Task beginnt — niemals mit rotem Build weiterarbeiten.
- `ArticleListQuery.swift`, `ArticleListItemSnapshot.swift`, `TagViewModel.swift`, `ArticleRetentionCleanupService.swift`, `SidebarUnreadCount.swift`, `ReaderPreparedArticle.swift` werden NICHT angefasst — sie enthalten noch aktiven Code (spätere Phase).
- Die 9 `@Model`-Klassen selbst bleiben unangetastet (spätere Phase).

---

### Task 1: `ArticleInspectorTypography`/`FlowLayout` extrahieren, `LegacyArticleMetadataInspectorView.swift` + `ReaderView.swift` löschen

**Files:**
- Create: `Feedivo/Views/Reader/ArticleInspectorTypography.swift`
- Create: `Feedivo/Views/Reader/FlowLayout.swift`
- Delete: `Feedivo/Views/Reader/LegacyArticleMetadataInspectorView.swift`
- Delete: `Feedivo/Views/Reader/ReaderView.swift`

**Interfaces:**
- Produces: `ArticleInspectorTypography` (enum, unveränderte API) und `FlowLayout` (struct, unveränderte API) — von `ArticleMetadataInspectorView.swift`, `SQLiteReaderView.swift`, `FeedPropertiesView.swift` weiterhin über dieselben Namen konsumiert, jetzt aus den neuen Dateien statt aus `LegacyArticleMetadataInspectorView.swift`.

`LegacyArticleMetadataInspectorView.swift` enthält aktuell zwei Typen, die aktiv von anderen (nicht toten) Dateien genutzt werden: `ArticleInspectorTypography` (genutzt von `ReaderView.swift` UND `ArticleMetadataInspectorView.swift`) und `FlowLayout` (genutzt von `SQLiteReaderView.swift`, `ArticleMetadataInspectorView.swift`, `FeedPropertiesView.swift`). Beide müssen vor dem Löschen der Datei in eigene Dateien verschoben werden. `ReaderView.swift` (enthält `LegacyReaderView`) ist der einzige Aufrufer von `struct LegacyArticleMetadataInspectorView` selbst — beide Dateien werden deshalb im selben Task gelöscht.

- [ ] **Step 1: `ArticleInspectorTypography` in eigene Datei verschieben**

Neue Datei `Feedivo/Views/Reader/ArticleInspectorTypography.swift`:

```swift
enum ArticleInspectorTypography {
    static let titleFontSize = 15.0
    static let sectionTitleFontSize = 13.0
    static let primaryValueFontSize = 12.0
    static let controlFontSize = 11.5
    static let labelFontSize = 11.0
    static let secondaryFontSize = 11.0
    static let chipFontSize = 11.0
    static let iconFontSize = 12.0
}
```

- [ ] **Step 2: `FlowLayout` in eigene Datei verschieben**

Neue Datei `Feedivo/Views/Reader/FlowLayout.swift`:

```swift
import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 0
        cache.computedWidth = width
        cache.rows = rows(in: width, subviews: subviews)
        return CGSize(
            width: width,
            height: cache.rows.reduce(0) { $0 + $1.height } + CGFloat(max(cache.rows.count - 1, 0)) * spacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        // rows wurde in sizeThatFits berechnet und im Cache abgelegt — hier nur
        // noch platzieren, statt die Zeilen ein zweites Mal aufzubauen.
        let rows = bounds.width == cache.computedWidth ? cache.rows : rows(in: bounds.width, subviews: subviews)
        var origin = bounds.origin
        for row in rows {
            origin.x = bounds.minX
            for element in row.elements {
                element.subview.place(
                    at: origin,
                    proposal: ProposedViewSize(element.size)
                )
                origin.x += element.size.width + spacing
            }
            origin.y += row.height + spacing
        }
    }

    struct Cache {
        var computedWidth: CGFloat = -1
        var rows: [Row] = []
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRow.width + size.width > width, !currentRow.elements.isEmpty {
                rows.append(currentRow)
                currentRow = Row()
            }

            currentRow.add(subview: subview, size: size, spacing: spacing)
        }

        if !currentRow.elements.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    struct Row {
        var elements: [(subview: LayoutSubview, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func add(subview: LayoutSubview, size: CGSize, spacing: CGFloat) {
            if !elements.isEmpty {
                width += spacing
            }
            elements.append((subview, size))
            width += size.width
            height = max(height, size.height)
        }
    }
}
```

- [ ] **Step 3: Bauen — die zwei neuen Dateien müssen kompilieren, bevor die alte Datei verschwindet**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **` (Duplikat-Definitionsfehler sind an dieser Stelle normal/erwartbar, da die alten Definitionen noch in `LegacyArticleMetadataInspectorView.swift` existieren — falls der Build deswegen fehlschlägt, sofort mit Step 4 fortfahren, bevor erneut gebaut wird)

- [ ] **Step 4: `LegacyArticleMetadataInspectorView.swift` und `ReaderView.swift` löschen**

```bash
git rm Feedivo/Views/Reader/LegacyArticleMetadataInspectorView.swift
git rm Feedivo/Views/Reader/ReaderView.swift
```

- [ ] **Step 5: Bauen und volle Testsuite laufen lassen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Reader/ArticleInspectorTypography.swift Feedivo/Views/Reader/FlowLayout.swift
git commit -m "ArticleInspectorTypography/FlowLayout extrahiert; LegacyReaderView + LegacyArticleMetadataInspectorView entfernt"
```

---

### Task 2: `ArticleListView.swift` (`LegacyArticleListView`) löschen

**Files:**
- Delete: `Feedivo/Views/ArticleList/ArticleListView.swift`

**Interfaces:**
- Consumes: nichts aus Task 1.
- Produces: nichts — reine Löschung, unabhängig vom Rest des Baums (kein Cross-Reference zu `ReaderView`/`LegacyArticleMetadataInspectorView` gefunden).

- [ ] **Step 1: Datei löschen**

```bash
git rm Feedivo/Views/ArticleList/ArticleListView.swift
```

- [ ] **Step 2: Bauen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "LegacyArticleListView (ArticleListView.swift) entfernt"
```

---

### Task 3: `ArticleViewModel`/`ArticleNavigationState` löschen

**Files:**
- Delete: `Feedivo/ViewModels/ArticleViewModel.swift`
- Delete: `Feedivo/ViewModels/ArticleNavigationState.swift`
- Delete: `FeedivoTests/ArticleViewModelTests.swift`

**Interfaces:**
- Consumes: Voraussetzung ist, dass Task 1 (`ReaderView.swift`, `LegacyArticleMetadataInspectorView.swift`) und Task 2 (`ArticleListView.swift`) bereits gelöscht sind — das waren die einzigen drei Aufrufer von `ArticleViewModel`.
- Produces: nichts.

- [ ] **Step 1: Dateien löschen**

```bash
git rm Feedivo/ViewModels/ArticleViewModel.swift
git rm Feedivo/ViewModels/ArticleNavigationState.swift
git rm FeedivoTests/ArticleViewModelTests.swift
```

- [ ] **Step 2: Bauen und Tests laufen lassen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "ArticleViewModel/ArticleNavigationState entfernt (nur vom toten View-Baum genutzt)"
```

---

### Task 4: `ArticleMetadataEditor` löschen

**Files:**
- Delete: `Feedivo/ViewModels/ArticleMetadataEditor.swift`
- Delete: `FeedivoTests/ArticleMetadataEditorTests.swift`

**Interfaces:**
- Consumes: Voraussetzung ist, dass Task 1 und Task 2 bereits gelöscht sind — das waren die einzigen drei Aufrufer von `ArticleMetadataEditor`.
- Produces: nichts.

- [ ] **Step 1: Dateien löschen**

```bash
git rm Feedivo/ViewModels/ArticleMetadataEditor.swift
git rm FeedivoTests/ArticleMetadataEditorTests.swift
```

- [ ] **Step 2: Bauen und Tests laufen lassen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "ArticleMetadataEditor entfernt (nur vom toten View-Baum genutzt)"
```

---

### Task 5: `SmartFolderViewModel` löschen

**Files:**
- Delete: `Feedivo/ViewModels/SmartFolderViewModel.swift`
- Delete: `FeedivoTests/SmartFolderViewModelTests.swift`

**Interfaces:**
- Consumes: nichts aus vorherigen Tasks (`SmartFolderViewModel` wird nirgends instanziiert, unabhängig vom übrigen Baum).
- Produces: nichts.

- [ ] **Step 1: Dateien löschen**

```bash
git rm Feedivo/ViewModels/SmartFolderViewModel.swift
git rm FeedivoTests/SmartFolderViewModelTests.swift
```

- [ ] **Step 2: Bauen und Tests laufen lassen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "SmartFolderViewModel entfernt (nirgends instanziiert)"
```

---

### Task 6: `FeedPropertiesQuery` löschen

**Files:**
- Delete: `Feedivo/Views/Sidebar/FeedPropertiesQuery.swift`
- Delete: `FeedivoTests/FeedPropertiesQueryTests.swift`

**Interfaces:**
- Consumes: nichts aus vorherigen Tasks (`FeedPropertiesQuery` hat null externe Aufrufer, unabhängig vom übrigen Baum — `FeedPropertiesView.swift` nutzt bereits `ArticleStore.feedPropertiesMetrics`).
- Produces: nichts.

- [ ] **Step 1: Dateien löschen**

```bash
git rm Feedivo/Views/Sidebar/FeedPropertiesQuery.swift
git rm FeedivoTests/FeedPropertiesQueryTests.swift
```

- [ ] **Step 2: Bauen und Tests laufen lassen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "FeedPropertiesQuery entfernt (null externe Aufrufer)"
```

---

### Task 7: Tote Backfill/Cleanup-Services löschen + Abschlussverifikation

**Files:**
- Delete: `Feedivo/Services/ArticleFeedIDBackfillService.swift`
- Delete: `Feedivo/Services/FeedTagBackfillService.swift`
- Delete: `Feedivo/Services/FeedUnreadCountBackfillService.swift`
- Delete: `Feedivo/Services/OrphanedArticleCleanupService.swift`
- Delete: `Feedivo/Services/SQLiteAdminDefinitionBackfillService.swift`
- Delete: `Feedivo/Services/FeedBackgroundRefreshService.swift`

**Interfaces:**
- Consumes: nichts aus vorherigen Tasks (alle sechs sind unabhängig voneinander und vom View-Baum, null externe Aufrufer, keine eigenen Testdateien).
- Produces: nichts — letzter Task dieser Phase.

- [ ] **Step 1: Dateien löschen**

```bash
git rm Feedivo/Services/ArticleFeedIDBackfillService.swift
git rm Feedivo/Services/FeedTagBackfillService.swift
git rm Feedivo/Services/FeedUnreadCountBackfillService.swift
git rm Feedivo/Services/OrphanedArticleCleanupService.swift
git rm Feedivo/Services/SQLiteAdminDefinitionBackfillService.swift
git rm Feedivo/Services/FeedBackgroundRefreshService.swift
```

- [ ] **Step 2: Bauen und volle Testsuite laufen lassen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Verifizieren, dass `import SwiftData` aus allen 13 Zieldateien verschwunden ist**

Run: `grep -rl "import SwiftData" Feedivo --include="*.swift" | grep -E "ArticleViewModel|ArticleNavigationState|SmartFolderViewModel|ArticleMetadataEditor|FeedPropertiesQuery|ArticleListView\.swift|ReaderView\.swift|LegacyArticleMetadataInspectorView|ArticleFeedIDBackfillService|FeedTagBackfillService|FeedUnreadCountBackfillService|OrphanedArticleCleanupService|SQLiteAdminDefinitionBackfillService|FeedBackgroundRefreshService"`
Expected: kein Treffer (leere Ausgabe) — alle 13 Dateien existieren nicht mehr.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Tote Backfill/Cleanup-Services entfernt (ArticleFeedIDBackfillService, FeedTagBackfillService, FeedUnreadCountBackfillService, OrphanedArticleCleanupService, SQLiteAdminDefinitionBackfillService, FeedBackgroundRefreshService)"
```

---

## Self-Review

**Spec coverage:** Die Spec fordert (1) `FlowLayout`-Extraktion vor dem Löschen — Task 1 Steps 1-4 decken das inkl. `ArticleInspectorTypography` (zusätzlich zur Spec identifiziert, siehe unten) ab. (2) Die 13 vollständig toten Produktivdateien + 4 Testdateien — Tasks 1-7 löschen jede einzeln auf. (3) Build/Testsuite bleibt nach jedem Schritt grün — jeder Task endet mit Build+Test. (4) `ArticleListQuery.swift` etc. bleiben unangetastet — keine dieser Dateien taucht in irgendeinem Task auf.

**Ergänzung gegenüber der Spec:** Beim Vorbereiten des Plans wurde ein zweiter aktiv genutzter Typ in `LegacyArticleMetadataInspectorView.swift` gefunden: `ArticleInspectorTypography` (genutzt von `ArticleMetadataInspectorView.swift`, nicht nur von `ReaderView.swift`). Die Spec nannte nur `FlowLayout` explizit — Task 1 extrahiert beide, da sonst der Build nach dem Löschen der Datei bräche. Dies ist eine notwendige Präzisierung, kein Scope-Wechsel.

**Placeholder-Scan:** Keine TBD/TODO, vollständiger Code in jedem Schritt, exakte Lösch-Kommandos statt Prosa-Beschreibungen.

**Typ-Konsistenz:** `ArticleInspectorTypography`/`FlowLayout` behalten exakt ihre bisherigen öffentlichen Signaturen (keine Umbenennung) — bestehende Konsumenten (`ArticleMetadataInspectorView.swift`, `SQLiteReaderView.swift`, `FeedPropertiesView.swift`) brauchen keine Anpassung.
