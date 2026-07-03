# NSTableView Article List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this side conversation, subagents are intentionally not used.

**Goal:** Replace the middle article SwiftUI `List` with an isolated `NSTableView` bridge while preserving Feedivo's current visual article-row design and SQLite snapshot data flow.

**Architecture:** `SQLiteFeedArticleListView` remains the SwiftUI shell for search, toolbar, filtering, sorting, empty states, and state loading. A new `NSViewRepresentable` owns `NSScrollView` + `NSTableView`, renders `ArticleListSnapshot` rows through native AppKit cells, and syncs selection back to `selectedArticleID`. Status actions still flow through existing `SQLiteFeedArticleListState` methods.

**Tech Stack:** SwiftUI, AppKit, `NSViewRepresentable`, `NSTableView`, SQLite/GRDB snapshots, existing `ArticleListSnapshot`/`SQLiteFeedArticleListState`.

---

## File Structure

- Create: `Feedivo/Views/ArticleList/SQLiteArticleTableView.swift`
  - SwiftUI/AppKit bridge, coordinator, data source, delegate, context menu, star/read/archive action callbacks.
- Create: `Feedivo/Views/ArticleList/FeedivoArticleTableCellView.swift`
  - Native AppKit row view that mirrors `ArticleRowView` layout.
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`
  - Replace `List(selection:)` with the table bridge while keeping search, sort/filter, empty states, toolbar, sheet, and load behavior.
- Modify: `AGENTS.md`
  - Record that the product article list is now a hybrid SwiftUI/AppKit `NSTableView`.
- Modify: `FEATURES.md`
  - Record the PowerUser list architecture decision and verification status.

## Task 1: Add Native AppKit Article Row Cell

**Files:**
- Create: `Feedivo/Views/ArticleList/FeedivoArticleTableCellView.swift`

- [ ] **Step 1: Create the AppKit cell view**

Create `Feedivo/Views/ArticleList/FeedivoArticleTableCellView.swift`:

```swift
import AppKit

final class FeedivoArticleTableCellView: NSTableCellView {
    var onToggleStarred: (() -> Void)?

    private let previewView = NSView()
    private let previewImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let unreadIndicator = NSView()
    private let offlineIndicator = NSImageView()
    private let starButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(with row: ArticleListSnapshot) {
        titleLabel.stringValue = row.title
        titleLabel.font = .systemFont(ofSize: 14, weight: row.isRead ? .regular : .semibold)
        titleLabel.textColor = row.isRead ? .secondaryLabelColor : .labelColor

        metadataLabel.stringValue = [
            row.feedTitle,
            row.publishedAt?.feedivoRelativeDisplay
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }
        .joined(separator: " · ")

        summaryLabel.stringValue = row.summary ?? ""
        summaryLabel.isHidden = (row.summary ?? "").isEmpty
        summaryLabel.textColor = row.isRead ? .tertiaryLabelColor : .secondaryLabelColor

        unreadIndicator.isHidden = row.isRead
        configureOfflineIndicator(row.offlineState)
        configureStar(row.isStarred)
        configurePreviewPlaceholder()
    }

    private func setupViews() {
        wantsLayer = true

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 6
        previewView.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor

        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .systemFont(ofSize: 11)
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = .systemFont(ofSize: 13)
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 2

        unreadIndicator.translatesAutoresizingMaskIntoConstraints = false
        unreadIndicator.wantsLayer = true
        unreadIndicator.layer?.cornerRadius = 4
        unreadIndicator.layer?.backgroundColor = NSColor.systemBlue.cgColor

        offlineIndicator.translatesAutoresizingMaskIntoConstraints = false
        offlineIndicator.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        offlineIndicator.contentTintColor = .systemGreen

        starButton.translatesAutoresizingMaskIntoConstraints = false
        starButton.isBordered = false
        starButton.target = self
        starButton.action = #selector(toggleStarred)
        starButton.setButtonType(.momentaryChange)

        let textStack = NSStackView(views: [titleLabel, metadataLabel, summaryLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let statusStack = NSStackView(views: [unreadIndicator, offlineIndicator, NSView(), starButton])
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusStack.orientation = .vertical
        statusStack.alignment = .centerX
        statusStack.spacing = 6

        addSubview(previewView)
        previewView.addSubview(previewImageView)
        addSubview(textStack)
        addSubview(statusStack)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            previewView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            previewView.widthAnchor.constraint(equalToConstant: 56),
            previewView.heightAnchor.constraint(equalToConstant: 56),

            previewImageView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            previewImageView.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            previewImageView.widthAnchor.constraint(equalToConstant: 24),
            previewImageView.heightAnchor.constraint(equalToConstant: 24),

            textStack.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -7),

            statusStack.leadingAnchor.constraint(equalTo: textStack.trailingAnchor, constant: 8),
            statusStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            statusStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            statusStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            statusStack.widthAnchor.constraint(equalToConstant: 28),

            unreadIndicator.widthAnchor.constraint(equalToConstant: 8),
            unreadIndicator.heightAnchor.constraint(equalToConstant: 8),
            offlineIndicator.widthAnchor.constraint(equalToConstant: 16),
            offlineIndicator.heightAnchor.constraint(equalToConstant: 16),
            starButton.widthAnchor.constraint(equalToConstant: 24),
            starButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func configurePreviewPlaceholder() {
        previewImageView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        previewImageView.contentTintColor = .secondaryLabelColor
    }

    private func configureOfflineIndicator(_ state: ArticleOfflineState) {
        switch state {
        case .fullText, .feedContent:
            offlineIndicator.isHidden = false
            offlineIndicator.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            offlineIndicator.contentTintColor = .systemGreen
        case .failed:
            offlineIndicator.isHidden = false
            offlineIndicator.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            offlineIndicator.contentTintColor = .systemOrange
        case .none:
            offlineIndicator.isHidden = true
            offlineIndicator.image = nil
        }
    }

    private func configureStar(_ isStarred: Bool) {
        starButton.image = NSImage(
            systemSymbolName: isStarred ? "star.fill" : "star",
            accessibilityDescription: nil
        )
        starButton.contentTintColor = isStarred ? .systemYellow : .secondaryLabelColor
    }

    @objc private func toggleStarred() {
        onToggleStarred?()
    }
}
```

- [ ] **Step 2: Build to catch type mismatches**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Expected: The build may still fail because the new cell is not integrated, but it must not fail due to syntax errors in `FeedivoArticleTableCellView.swift`.

- [ ] **Step 3: Commit the cell skeleton**

```bash
git add Feedivo/Views/ArticleList/FeedivoArticleTableCellView.swift
git commit -m "Add AppKit article table cell"
```

## Task 2: Add NSTableView SwiftUI Bridge

**Files:**
- Create: `Feedivo/Views/ArticleList/SQLiteArticleTableView.swift`

- [ ] **Step 1: Create bridge and coordinator**

Create `Feedivo/Views/ArticleList/SQLiteArticleTableView.swift`:

```swift
import AppKit
import SwiftUI

struct SQLiteArticleTableView: NSViewRepresentable {
    var rows: [ArticleListSnapshot]
    @Binding var selectedArticleID: String?
    var hasAvailableTags: Bool
    var onToggleRead: (ArticleListSnapshot) -> Void
    var onToggleStarred: (ArticleListSnapshot) -> Void
    var onToggleArchived: (ArticleListSnapshot) -> Void
    var onRequestAssignTag: (ArticleListSnapshot) -> Void
    var onCreateRule: (ArticleListSnapshot) -> Void
    var onCopyLink: (ArticleListSnapshot) -> Void
    var onOpenOriginal: (ArticleListSnapshot) -> Void
    var onShareOriginal: (ArticleListSnapshot) -> Void
    var onOpenInWindow: (ArticleListSnapshot) -> Void
    var onExport: (ArticleListSnapshot) -> Void
    var onSaveOrRemoveOffline: (ArticleListSnapshot) -> Void
    var onDelete: (ArticleListSnapshot) -> Void
    var onMarkAllRead: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 88
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.openSelectedArticleInWindow)

        let column = NSTableColumn(identifier: Coordinator.articleColumnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.reload(parent: self)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else {
            return
        }
        context.coordinator.reload(parent: self)
        tableView.reloadData()
        context.coordinator.syncSelection()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let articleColumnIdentifier = NSUserInterfaceItemIdentifier("article")

        private var parent: SQLiteArticleTableView
        weak var tableView: NSTableView?

        init(parent: SQLiteArticleTableView) {
            self.parent = parent
        }

        func reload(parent: SQLiteArticleTableView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rows.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row rowIndex: Int
        ) -> NSView? {
            guard parent.rows.indices.contains(rowIndex) else {
                return nil
            }

            let identifier = NSUserInterfaceItemIdentifier("FeedivoArticleTableCellView")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? FeedivoArticleTableCellView
                ?? FeedivoArticleTableCellView()
            cell.identifier = identifier

            let row = parent.rows[rowIndex]
            cell.configure(with: row)
            cell.onToggleStarred = { [weak self] in
                self?.parent.onToggleStarred(row)
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else {
                return
            }

            let selectedRow = tableView.selectedRow
            guard parent.rows.indices.contains(selectedRow) else {
                parent.selectedArticleID = nil
                return
            }

            parent.selectedArticleID = parent.rows[selectedRow].id
        }

        func tableView(
            _ tableView: NSTableView,
            menuForRows rows: IndexSet
        ) -> NSMenu? {
            guard let rowIndex = rows.first, parent.rows.indices.contains(rowIndex) else {
                return nil
            }

            let snapshot = parent.rows[rowIndex]
            let menu = NSMenu()
            menu.addItem(item(
                title: snapshot.isRead ? String(localized: "article.row.markUnread") : String(localized: "article.row.markRead"),
                action: #selector(toggleReadFromMenu(_:)),
                snapshot: snapshot
            ))
            menu.addItem(item(
                title: snapshot.isStarred ? String(localized: "article.row.star.remove") : String(localized: "article.row.star.add"),
                action: #selector(toggleStarredFromMenu(_:)),
                snapshot: snapshot
            ))
            menu.addItem(.separator())
            menu.addItem(item(
                title: snapshot.isArchived ? String(localized: "article.unarchive.command") : String(localized: "article.archive.command"),
                action: #selector(toggleArchivedFromMenu(_:)),
                snapshot: snapshot
            ))
            let assignTagItem = item(
                title: String(localized: "article.assignTag.command"),
                action: #selector(assignTagFromMenu(_:)),
                snapshot: snapshot
            )
            assignTagItem.isEnabled = parent.hasAvailableTags
            menu.addItem(assignTagItem)
            menu.addItem(item(title: String(localized: "article.createRule.command"), action: #selector(createRuleFromMenu(_:)), snapshot: snapshot))
            menu.addItem(.separator())
            menu.addItem(item(title: String(localized: "article.openInWindow.command"), action: #selector(openInWindowFromMenu(_:)), snapshot: snapshot))
            menu.addItem(item(title: String(localized: "article.copyLink.command"), action: #selector(copyLinkFromMenu(_:)), snapshot: snapshot))
            menu.addItem(item(title: String(localized: "article.openOriginal.command"), action: #selector(openOriginalFromMenu(_:)), snapshot: snapshot))
            menu.addItem(item(title: String(localized: "article.share.command"), action: #selector(shareOriginalFromMenu(_:)), snapshot: snapshot))
            menu.addItem(item(title: String(localized: "article.export.command"), action: #selector(exportFromMenu(_:)), snapshot: snapshot))
            menu.addItem(item(
                title: snapshot.offlineState.isAvailable ? String(localized: "reader.offline.remove") : String(localized: "reader.offline.save"),
                action: #selector(saveOrRemoveOfflineFromMenu(_:)),
                snapshot: snapshot
            ))
            menu.addItem(.separator())
            menu.addItem(item(title: String(localized: "article.delete.command"), action: #selector(deleteFromMenu(_:)), snapshot: snapshot))
            menu.addItem(.separator())
            let markAllRead = NSMenuItem(title: String(localized: "article.markAllRead.command"), action: #selector(markAllReadFromMenu(_:)), keyEquivalent: "")
            markAllRead.target = self
            menu.addItem(markAllRead)
            return menu
        }

        func syncSelection() {
            guard let tableView else {
                return
            }

            guard let selectedArticleID = parent.selectedArticleID,
                  let rowIndex = parent.rows.firstIndex(where: { $0.id == selectedArticleID })
            else {
                tableView.deselectAll(nil)
                return
            }

            if tableView.selectedRow != rowIndex {
                tableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
                tableView.scrollRowToVisible(rowIndex)
            }
        }

        @objc func openSelectedArticleInWindow() {
            guard let snapshot = selectedSnapshot else {
                return
            }
            parent.onOpenInWindow(snapshot)
        }

        @objc private func toggleReadFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onToggleRead)
        }

        @objc private func toggleStarredFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onToggleStarred)
        }

        @objc private func toggleArchivedFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onToggleArchived)
        }

        @objc private func assignTagFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onRequestAssignTag)
        }

        @objc private func createRuleFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onCreateRule)
        }

        @objc private func copyLinkFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onCopyLink)
        }

        @objc private func openOriginalFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onOpenOriginal)
        }

        @objc private func shareOriginalFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onShareOriginal)
        }

        @objc private func openInWindowFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onOpenInWindow)
        }

        @objc private func exportFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onExport)
        }

        @objc private func saveOrRemoveOfflineFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onSaveOrRemoveOffline)
        }

        @objc private func deleteFromMenu(_ sender: NSMenuItem) {
            perform(sender, parent.onDelete)
        }

        @objc private func markAllReadFromMenu(_ sender: NSMenuItem) {
            parent.onMarkAllRead()
        }

        private var selectedSnapshot: ArticleListSnapshot? {
            guard let tableView, parent.rows.indices.contains(tableView.selectedRow) else {
                return nil
            }
            return parent.rows[tableView.selectedRow]
        }

        private func item(
            title: String,
            action: Selector,
            snapshot: ArticleListSnapshot
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = snapshot.id
            return item
        }

        private func perform(
            _ sender: NSMenuItem,
            _ action: (ArticleListSnapshot) -> Void
        ) {
            guard let articleID = sender.representedObject as? String,
                  let snapshot = parent.rows.first(where: { $0.id == articleID })
            else {
                return
            }
            action(snapshot)
        }
    }
}
```

- [ ] **Step 2: Build to catch API issues**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Expected: Any failures are limited to missing localized keys or type names. If localized key strings do not match actual String Catalog keys, replace the `String(localized:)` calls with existing `L10n` string values before committing.

- [ ] **Step 3: Commit bridge**

```bash
git add Feedivo/Views/ArticleList/SQLiteArticleTableView.swift
git commit -m "Add NSTableView bridge for SQLite article list"
```

## Task 3: Replace SwiftUI List Usage

**Files:**
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`

- [ ] **Step 1: Replace `articleList` implementation**

In `SQLiteFeedArticleListView`, replace the current `articleList` property body with:

```swift
private var articleList: some View {
    Group {
        if filteredRows.isEmpty {
            List {
                articleListEmptyState(isSearching: isSearching)
            }
        } else {
            VStack(spacing: 0) {
                SQLiteArticleTableView(
                    rows: visibleRows,
                    selectedArticleID: $selectedArticleID,
                    hasAvailableTags: hasAvailableTags,
                    onToggleRead: { row in
                        toggleRead(row)
                    },
                    onToggleStarred: { row in
                        toggleStarred(row)
                    },
                    onToggleArchived: { row in
                        toggleArchived(row)
                    },
                    onRequestAssignTag: { row in
                        requestAssignTag(row)
                    },
                    onCreateRule: { row in
                        createRule(row)
                    },
                    onCopyLink: { row in
                        copyLink(row)
                    },
                    onOpenOriginal: { row in
                        openOriginal(row)
                    },
                    onShareOriginal: { row in
                        shareOriginal(row)
                    },
                    onOpenInWindow: { row in
                        openInWindow(row)
                    },
                    onExport: { row in
                        exportArticle(row)
                    },
                    onSaveOrRemoveOffline: { row in
                        saveOrRemoveOffline(row)
                    },
                    onDelete: { row in
                        deleteArticle(row)
                    },
                    onMarkAllRead: {
                        markAllRead(visibleRows)
                    }
                )

                if shouldShowReadArticlesButton {
                    showReadArticlesButton(count: hiddenReadRowCount)
                }
            }
        }
    }
}
```

If helper method names differ, map each closure to the existing methods currently passed into `ArticleRowView` inside `articleRow(_:visibleRows:)`. Do not change the data flow.

- [ ] **Step 2: Remove now-unused SwiftUI row path only if build proves it unused**

If `articleRow(_:visibleRows:)` becomes unused and no other local code references it, remove that private method from `SQLiteFeedArticleListView`. Keep `ArticleRowView.swift` because legacy or other views may still use it.

Verify with:

```bash
rg -n "articleRow\\(" Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
rg -n "ArticleRowView" Feedivo
```

Expected: `ArticleRowView` may still exist; only the private method in `SQLiteFeedArticleListView` should be removed if unused.

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Expected: Build succeeds. If helper names differ, update only the closure mapping in `articleList`.

- [ ] **Step 4: Commit integration**

```bash
git add Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift Feedivo/Views/ArticleList/SQLiteArticleTableView.swift Feedivo/Views/ArticleList/FeedivoArticleTableCellView.swift
git commit -m "Use NSTableView for SQLite article list"
```

## Task 4: Preserve Commands, Selection, and Navigation

**Files:**
- Modify: `Feedivo/Views/ArticleList/SQLiteArticleTableView.swift`
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`

- [ ] **Step 1: Verify selection propagation**

Run the app and test:

```text
1. Select a feed.
2. Click an article row in the middle list.
3. Confirm the reader loads that article.
4. Use arrow keys in the table.
5. Confirm selection changes and the reader follows.
```

Expected: `selectedArticleID` changes on row selection and `SQLiteReaderView` updates.

- [ ] **Step 2: Add explicit first responder behavior if arrow keys do not work**

If arrow-key navigation does not work after clicking the table, add this to `makeNSView` after assigning `context.coordinator.tableView = tableView`:

```swift
DispatchQueue.main.async {
    scrollView.window?.makeFirstResponder(tableView)
}
```

Expected: The table becomes first responder after creation and supports standard AppKit keyboard navigation.

- [ ] **Step 3: Verify article commands**

Run through:

```text
1. Select article.
2. Use menu/shortcut for mark read.
3. Use menu/shortcut for star.
4. Use next/previous article commands.
```

Expected: Commands still use `selectedArticleID` and `selectedSQLiteArticleSnapshot` from `ContentView`; they must not depend on SwiftUI `List`.

- [ ] **Step 4: Commit only if code changed**

```bash
git add Feedivo/Views/ArticleList/SQLiteArticleTableView.swift Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
git commit -m "Preserve article table selection behavior"
```

If no code changed, do not create an empty commit.

## Task 5: Visual Parity Pass

**Files:**
- Modify: `Feedivo/Views/ArticleList/FeedivoArticleTableCellView.swift`

- [ ] **Step 1: Compare current row appearance**

Run Feedivo and inspect:

```text
1. Unread row title weight.
2. Read row muted colors.
3. Metadata line spacing.
4. Summary truncation.
5. Unread dot.
6. Offline icon.
7. Star button position.
8. Selection background.
```

Expected: The new table reads as the same Feedivo article list, not as a new design.

- [ ] **Step 2: Tune row metrics if needed**

If the cell looks too cramped or too tall, adjust only these constants:

```swift
tableView.rowHeight = 88
previewView.widthAnchor.constraint(equalToConstant: 56)
previewView.heightAnchor.constraint(equalToConstant: 56)
```

Acceptable range:

```text
rowHeight: 84...96
preview side: 52...60
```

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Expected: Build succeeds.

- [ ] **Step 4: Commit visual parity tuning**

```bash
git add Feedivo/Views/ArticleList/FeedivoArticleTableCellView.swift Feedivo/Views/ArticleList/SQLiteArticleTableView.swift
git commit -m "Tune NSTableView article row appearance"
```

If no visual tuning was needed, do not create an empty commit.

## Task 6: Documentation and Final Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`

- [ ] **Step 1: Update `AGENTS.md`**

Add a short note near the ArticleList section:

```markdown
- Die produktive SQLite-Artikelliste nutzt jetzt eine isolierte AppKit-`NSTableView`
  innerhalb von SwiftUI. Sidebar, Reader, Suche, Toolbar und Empty States bleiben
  SwiftUI; nur die heiße Listenfläche wurde für PowerUser-Performance ersetzt.
```

- [ ] **Step 2: Update `FEATURES.md`**

Add the same decision in the SQLite/Performance section:

```markdown
- Artikelliste: PowerUser-Zielarchitektur ist eine hybride `NSTableView` für
  die mittlere Liste, gespeist aus `ArticleListSnapshot`/SQLite. Keine optische
  Neugestaltung; SwiftUI bleibt Shell für Sidebar, Reader und Toolbar.
```

- [ ] **Step 3: Run final build**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Expected: Build succeeds.

- [ ] **Step 4: Run static checks**

Run:

```bash
git diff --check
rg -n "List\\(selection: \\$selectedArticleID\\)" Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift
```

Expected:

```text
git diff --check produces no output.
rg finds no SwiftUI List(selection:) in SQLiteFeedArticleListView.
```

- [ ] **Step 5: Final commit**

```bash
git add AGENTS.md FEATURES.md
git commit -m "Document NSTableView article list migration"
```

If docs were already committed in previous tasks, skip this commit.

## Self-Review

- Spec coverage: The plan covers the isolated `NSTableView` bridge, native row cell, selection binding, context menu/actions, visual parity, build verification, and docs updates.
- Placeholder scan: No unresolved placeholder markers or open-ended implementation placeholders are intended.
- Type consistency: The plan consistently uses `ArticleListSnapshot`, `selectedArticleID`, `SQLiteFeedArticleListView`, `SQLiteArticleTableView`, and `FeedivoArticleTableCellView`.
- Scope check: The plan avoids Sidebar, Reader, database, multi-selection, columns, and drag/drop, matching the design.
