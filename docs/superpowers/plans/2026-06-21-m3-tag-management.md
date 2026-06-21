# M3 Tag Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first M3 block: central tag management for creating, renaming, recoloring, and deleting tags, plus Reader Inspector pills that use saved tag colors.

**Architecture:** Add a focused `TagViewModel` for validation and SwiftData mutations, then build a compact `TagManagerView` sheet that uses it. Keep the existing `Tag` model unchanged and make `ArticleMetadataInspectorView` reuse the saved `Tag.colorHex` for visual consistency.

**Tech Stack:** SwiftUI, SwiftData, `@Observable`, Swift Testing, macOS 14+, String Catalog localization.

---

## File Structure

- Create `Feedivo/ViewModels/TagViewModel.swift`
  - Owns tag name normalization, duplicate detection, create/rename/color/delete mutations, and user-facing error messages.
- Create `Feedivo/Views/Tags/TagManagerView.swift`
  - Native macOS sheet-style UI for listing, editing, recoloring, creating, and deleting tags.
- Create `Feedivo/Views/Tags/TagColorPalette.swift`
  - Small reusable palette and color conversion helper for `Tag.colorHex`.
- Modify `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift`
  - Use `TagColorPalette.color(for:)` for tag pills instead of hard-coded green.
- Modify `Feedivo/Views/Sidebar/SidebarView.swift`
  - Add a compact Tags section header action to open `TagManagerView`. This does not implement tag filtering yet.
- Modify `Feedivo/Resources/L10n.swift`
  - Add keys needed by the tag manager.
- Modify `Feedivo/Resources/Localizable.xcstrings`
  - Add German, English, French, and Italian strings for new UI and error messages.
- Create `FeedivoTests/TagViewModelTests.swift`
  - Unit coverage for normalization, duplicate prevention, create, rename, color update, and delete.
- Modify `FeedivoTests/ArticleMetadataEditorTests.swift`
  - Assert newly created tags keep the default color and reused tags keep their existing color.
- Modify `AGENTS.md` and `docs/FEATURES.md`
  - Mark M3 tag management as implemented as basis after code is complete.

---

## Task 1: Add TagViewModel Tests

**Files:**
- Create: `FeedivoTests/TagViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

Create `FeedivoTests/TagViewModelTests.swift`:

```swift
import SwiftData
import Testing
@testable import Feedivo

struct TagViewModelTests {

    @MainActor
    @Test func normalizedTagNameTrimmtUndVerwirftLeereNamen() {
        #expect(TagViewModel.normalizedTagName("  Swift  ") == "Swift")
        #expect(TagViewModel.normalizedTagName("   ") == nil)
        #expect(TagViewModel.normalizedTagName(nil) == nil)
    }

    @MainActor
    @Test func createTagSpeichertNormalisiertenNamenUndFarbe() throws {
        let context = try testContext()
        let viewModel = TagViewModel()

        viewModel.createTag(
            name: "  Swift  ",
            colorHex: "#3B82F6",
            availableTags: [],
            context: context
        )

        let tags = try context.fetch(FetchDescriptor<Feedivo.Tag>())
        #expect(tags.count == 1)
        #expect(tags.first?.name == "Swift")
        #expect(tags.first?.colorHex == "#3B82F6")
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func createTagVerhindertLeereUndDoppelteNamen() throws {
        let context = try testContext()
        let existingTag = Tag(name: "Swift", colorHex: "#22C55E")
        context.insert(existingTag)
        try context.save()
        let viewModel = TagViewModel()

        viewModel.createTag(name: " ", colorHex: "#3B82F6", availableTags: [existingTag], context: context)
        #expect(try context.fetch(FetchDescriptor<Feedivo.Tag>()).count == 1)
        #expect(viewModel.errorMessage == L10n.tagManagerEmptyNameError)

        viewModel.createTag(name: "swift", colorHex: "#3B82F6", availableTags: [existingTag], context: context)
        #expect(try context.fetch(FetchDescriptor<Feedivo.Tag>()).count == 1)
        #expect(viewModel.errorMessage == L10n.tagManagerDuplicateNameError)
    }

    @MainActor
    @Test func renameTagAendertNamenUndVerhindertDuplikate() throws {
        let context = try testContext()
        let tag = Tag(name: "Apple", colorHex: "#22C55E")
        let otherTag = Tag(name: "Swift", colorHex: "#3B82F6")
        context.insert(tag)
        context.insert(otherTag)
        try context.save()
        let viewModel = TagViewModel()

        viewModel.renameTag(tag, name: "  Apple News  ", availableTags: [tag, otherTag], context: context)
        #expect(tag.name == "Apple News")
        #expect(tag.colorHex == "#22C55E")
        #expect(viewModel.errorMessage == nil)

        viewModel.renameTag(tag, name: "swift", availableTags: [tag, otherTag], context: context)
        #expect(tag.name == "Apple News")
        #expect(viewModel.errorMessage == L10n.tagManagerDuplicateNameError)
    }

    @MainActor
    @Test func updateColorNormalisiertHexFarbe() throws {
        let context = try testContext()
        let tag = Tag(name: "Swift", colorHex: "#22C55E")
        context.insert(tag)
        try context.save()
        let viewModel = TagViewModel()

        viewModel.updateColor(tag, colorHex: "3b82f6", context: context)

        #expect(tag.colorHex == "#3B82F6")
        #expect(tag.name == "Swift")
    }

    @MainActor
    @Test func deleteTagEntferntNurTagNichtArtikel() throws {
        let context = try testContext()
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        let article = Article(title: "Artikel")
        article.tags = [tag]
        context.insert(tag)
        context.insert(article)
        try context.save()
        let viewModel = TagViewModel()

        viewModel.deleteTag(tag, context: context)

        #expect(try context.fetch(FetchDescriptor<Feedivo.Tag>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Article>()).count == 1)
        #expect(article.tags.isEmpty)
    }

    @MainActor
    private func testContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ModelContext(container)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -only-testing:FeedivoTests/TagViewModelTests
```

Expected: FAIL because `TagViewModel` and new `L10n` keys do not exist.

- [ ] **Step 3: Commit tests**

```bash
git add FeedivoTests/TagViewModelTests.swift
git commit -m "test: add tag view model coverage"
```

---

## Task 2: Implement TagViewModel

**Files:**
- Create: `Feedivo/ViewModels/TagViewModel.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [ ] **Step 1: Add L10n keys**

Add to `Feedivo/Resources/L10n.swift`:

```swift
    static var tagManagerEmptyNameError: String { String(localized: "tagManager.emptyName.error") }
    static var tagManagerDuplicateNameError: String { String(localized: "tagManager.duplicateName.error") }
```

Add these keys to `Feedivo/Resources/Localizable.xcstrings` with values:

```text
tagManager.emptyName.error
de: Tag-Name darf nicht leer sein.
en: Tag name cannot be empty.
fr: Le nom du tag ne peut pas etre vide.
it: Il nome del tag non puo essere vuoto.

tagManager.duplicateName.error
de: Ein Tag mit diesem Namen existiert bereits.
en: A tag with this name already exists.
fr: Un tag portant ce nom existe deja.
it: Esiste gia un tag con questo nome.
```

- [ ] **Step 2: Implement `TagViewModel`**

Create `Feedivo/ViewModels/TagViewModel.swift`:

```swift
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class TagViewModel {
    var errorMessage: String?

    func createTag(
        name: String,
        colorHex: String,
        availableTags: [Tag],
        context: ModelContext
    ) {
        guard let normalizedName = Self.normalizedTagName(name) else {
            errorMessage = L10n.tagManagerEmptyNameError
            return
        }

        guard !Self.containsTag(named: normalizedName, in: availableTags) else {
            errorMessage = L10n.tagManagerDuplicateNameError
            return
        }

        let tag = Tag(
            name: normalizedName,
            colorHex: Self.normalizedColorHex(colorHex)
        )
        context.insert(tag)
        save(context)
    }

    func renameTag(
        _ tag: Tag,
        name: String,
        availableTags: [Tag],
        context: ModelContext
    ) {
        guard let normalizedName = Self.normalizedTagName(name) else {
            errorMessage = L10n.tagManagerEmptyNameError
            return
        }

        guard !Self.containsTag(named: normalizedName, in: availableTags, excluding: tag) else {
            errorMessage = L10n.tagManagerDuplicateNameError
            return
        }

        guard tag.name != normalizedName else {
            errorMessage = nil
            return
        }

        tag.name = normalizedName
        save(context)
    }

    func updateColor(_ tag: Tag, colorHex: String, context: ModelContext) {
        tag.colorHex = Self.normalizedColorHex(colorHex)
        save(context)
    }

    func deleteTag(_ tag: Tag, context: ModelContext) {
        tag.articles.removeAll()
        tag.feeds.removeAll()
        context.delete(tag)
        save(context)
    }

    static func normalizedTagName(_ name: String?) -> String? {
        guard let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty
        else {
            return nil
        }

        return trimmedName
    }

    static func normalizedColorHex(_ colorHex: String) -> String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHash = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard withoutHash.count == 6,
              Int(withoutHash, radix: 16) != nil
        else {
            return "#888888"
        }

        return "#\(withoutHash.uppercased())"
    }

    private static func containsTag(named name: String, in tags: [Tag], excluding excludedTag: Tag? = nil) -> Bool {
        tags.contains { tag in
            if let excludedTag, tag.persistentModelID == excludedTag.persistentModelID {
                return false
            }

            return tag.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 3: Run focused tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -only-testing:FeedivoTests/TagViewModelTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/ViewModels/TagViewModel.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: add tag management view model"
```

---

## Task 3: Add Tag Color Palette

**Files:**
- Create: `Feedivo/Views/Tags/TagColorPalette.swift`
- Test: Add color normalization coverage to `FeedivoTests/TagViewModelTests.swift`

- [ ] **Step 1: Add focused color tests**

Append to `TagViewModelTests`:

```swift
    @Test func normalizedColorHexValidiertUndNormalisiertFarben() {
        #expect(TagViewModel.normalizedColorHex("#22c55e") == "#22C55E")
        #expect(TagViewModel.normalizedColorHex("3B82F6") == "#3B82F6")
        #expect(TagViewModel.normalizedColorHex("not-a-color") == "#888888")
    }
```

- [ ] **Step 2: Create palette helper**

Create `Feedivo/Views/Tags/TagColorPalette.swift`:

```swift
import SwiftUI

enum TagColorPalette {
    static let defaultColorHex = "#888888"

    static let colors = [
        "#3B82F6",
        "#22C55E",
        "#F59E0B",
        "#EF4444",
        "#A855F7",
        "#14B8A6",
        "#64748B"
    ]

    static func color(for colorHex: String?) -> Color {
        let normalized = TagViewModel.normalizedColorHex(colorHex ?? defaultColorHex)
        let hex = String(normalized.dropFirst())

        guard let value = Int(hex, radix: 16) else {
            return Color.gray
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        return Color(red: red, green: green, blue: blue)
    }
}
```

- [ ] **Step 3: Run tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -only-testing:FeedivoTests/TagViewModelTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Tags/TagColorPalette.swift FeedivoTests/TagViewModelTests.swift
git commit -m "feat: add tag color palette"
```

---

## Task 4: Make Reader Inspector Tag Pills Use Tag Colors

**Files:**
- Modify: `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift`
- Modify: `FeedivoTests/ArticleMetadataEditorTests.swift`

- [ ] **Step 1: Add editor color expectation**

In `FeedivoTests/ArticleMetadataEditorTests.swift`, extend `addTagTrimmtNamenUndVerwendetVorhandenenTag` with:

```swift
        #expect(article.tags.first?.colorHex == "#888888")
```

Add a second test:

```swift
    @MainActor
    @Test func addTagBewahrtFarbeVorhandenerTags() throws {
        let context = try testContext()
        let article = Article(title: "Artikel")
        let existingTag = Tag(name: "Swift", colorHex: "#3B82F6")
        context.insert(article)
        context.insert(existingTag)
        try context.save()

        ArticleMetadataEditor.addTag(named: "swift", to: article, availableTags: [existingTag], context: context)

        #expect(article.tags.first?.name == "Swift")
        #expect(article.tags.first?.colorHex == "#3B82F6")
    }
```

- [ ] **Step 2: Update tag pill style**

Replace the hard-coded `.green` styling in `tagPill(_:)` in `ArticleMetadataInspectorView`:

```swift
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        HStack(spacing: 6) {
            Text("#\(tag.name)")
                .lineLimit(1)

            Button {
                ArticleMetadataEditor.removeTag(tag, from: article, context: modelContext)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(tagColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tagColor.opacity(0.12), in: Capsule())
```

- [ ] **Step 3: Run focused tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -only-testing:FeedivoTests/ArticleMetadataEditorTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Reader/ArticleMetadataInspectorView.swift FeedivoTests/ArticleMetadataEditorTests.swift
git commit -m "feat: tint reader tag pills"
```

---

## Task 5: Build TagManagerView Sheet

**Files:**
- Create: `Feedivo/Views/Tags/TagManagerView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [ ] **Step 1: Add localization keys**

Add to `L10n.swift`:

```swift
    static let tagManagerTitle = LocalizedStringKey("tagManager.title")
    static let tagManagerDescription = LocalizedStringKey("tagManager.description")
    static let tagManagerNamePlaceholder = LocalizedStringKey("tagManager.name.placeholder")
    static let tagManagerColor = LocalizedStringKey("tagManager.color")
    static let tagManagerNoTags = LocalizedStringKey("tagManager.noTags")
    static let tagManagerNewTag = LocalizedStringKey("tagManager.newTag")
    static let tagManagerDeleteTitle = LocalizedStringKey("tagManager.delete.title")
    static let tagManagerDeleteMessage = LocalizedStringKey("tagManager.delete.message")
    static let tagManagerDeleteButton = LocalizedStringKey("tagManager.delete.button")
    static let tagManagerManageButton = LocalizedStringKey("tagManager.manage.button")
    static let sidebarTagsSection = LocalizedStringKey("sidebar.tags.section")
```

Add values in `Localizable.xcstrings`:

```text
tagManager.title
de: Tags verwalten
en: Manage Tags
fr: Gerer les tags
it: Gestisci tag

tagManager.description
de: Tags umbenennen, farblich markieren oder loeschen.
en: Rename, color, or delete tags.
fr: Renommer, colorer ou supprimer des tags.
it: Rinomina, colora o elimina i tag.

tagManager.name.placeholder
de: Tag-Name
en: Tag name
fr: Nom du tag
it: Nome tag

tagManager.color
de: Farbe
en: Color
fr: Couleur
it: Colore

tagManager.noTags
de: Noch keine Tags
en: No tags yet
fr: Aucun tag pour le moment
it: Nessun tag

tagManager.newTag
de: Neuer Tag
en: New Tag
fr: Nouveau tag
it: Nuovo tag

tagManager.delete.title
de: Tag loeschen?
en: Delete tag?
fr: Supprimer le tag ?
it: Eliminare il tag?

tagManager.delete.message
de: Das Tag wird von allen Artikeln entfernt. Die Artikel bleiben erhalten.
en: The tag will be removed from all articles. Articles remain unchanged.
fr: Le tag sera retire de tous les articles. Les articles restent conserves.
it: Il tag verra rimosso da tutti gli articoli. Gli articoli restano invariati.

tagManager.delete.button
de: Tag loeschen
en: Delete Tag
fr: Supprimer le tag
it: Elimina tag

tagManager.manage.button
de: Tags verwalten
en: Manage Tags
fr: Gerer les tags
it: Gestisci tag

sidebar.tags.section
de: Tags
en: Tags
fr: Tags
it: Tag
```

- [ ] **Step 2: Create `TagManagerView`**

Create `Feedivo/Views/Tags/TagManagerView.swift`:

```swift
import SwiftData
import SwiftUI

struct TagManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var viewModel = TagViewModel()
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.colors[0]
    @State private var tagPendingDeletion: Tag?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            newTagForm
            tagList
            footer
        }
        .padding(24)
        .frame(width: 520, minHeight: 420)
        .confirmationDialog(
            L10n.tagManagerDeleteTitle,
            isPresented: Binding(
                get: { tagPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        tagPendingDeletion = nil
                    }
                }
            ),
            presenting: tagPendingDeletion
        ) { tag in
            Button(L10n.tagManagerDeleteButton, role: .destructive) {
                viewModel.deleteTag(tag, context: modelContext)
                tagPendingDeletion = nil
            }
            Button(L10n.commonCancel, role: .cancel) {
                tagPendingDeletion = nil
            }
        } message: { _ in
            Text(L10n.tagManagerDeleteMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tagManagerTitle)
                .font(.title2)
                .fontWeight(.semibold)
            Text(L10n.tagManagerDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var newTagForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tagManagerNewTag)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField(L10n.tagManagerNamePlaceholder, text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createTag)

                ColorSwatchPicker(selection: $newTagColorHex)

                Button(L10n.commonAdd) {
                    createTag()
                }
                .buttonStyle(.borderedProminent)
                .disabled(TagViewModel.normalizedTagName(newTagName) == nil)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var tagList: some View {
        Group {
            if tags.isEmpty {
                ContentUnavailableView(L10n.tagManagerNoTags, systemImage: "tag")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List {
                    ForEach(tags) { tag in
                        TagManagerRow(
                            tag: tag,
                            tags: tags,
                            viewModel: viewModel,
                            requestDelete: {
                                tagPendingDeletion = tag
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L10n.commonDone) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func createTag() {
        viewModel.createTag(
            name: newTagName,
            colorHex: newTagColorHex,
            availableTags: tags,
            context: modelContext
        )
        if viewModel.errorMessage == nil {
            newTagName = ""
        }
    }
}

private struct TagManagerRow: View {
    @Environment(\.modelContext) private var modelContext

    let tag: Tag
    let tags: [Tag]
    let viewModel: TagViewModel
    let requestDelete: () -> Void

    @State private var draftName: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(TagColorPalette.color(for: tag.colorHex))
                .frame(width: 12, height: 12)

            TextField(L10n.tagManagerNamePlaceholder, text: $draftName)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    draftName = tag.name
                }
                .onSubmit {
                    viewModel.renameTag(tag, name: draftName, availableTags: tags, context: modelContext)
                }
                .onChange(of: tag.name) {
                    draftName = tag.name
                }

            ColorSwatchPicker(selection: Binding(
                get: { tag.colorHex },
                set: { colorHex in
                    viewModel.updateColor(tag, colorHex: colorHex, context: modelContext)
                }
            ))

            Text("\(tag.articles.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help("Artikel")

            Button(role: .destructive) {
                requestDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

private struct ColorSwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TagColorPalette.colors, id: \.self) { colorHex in
                Button {
                    selection = colorHex
                } label: {
                    Circle()
                        .fill(TagColorPalette.color(for: colorHex))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(selection == colorHex ? Color.primary : Color.clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .help(L10n.tagManagerColor)
            }
        }
    }
}
```

- [ ] **Step 3: Run build**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Tags/TagManagerView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "feat: add tag manager sheet"
```

---

## Task 6: Wire Tag Manager Into Sidebar

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [ ] **Step 1: Add sidebar state**

Add to `SidebarView` state:

```swift
    @State private var isShowingTagManager = false
```

- [ ] **Step 2: Add Tags section to sidebar body**

In the sidebar scroll stack, after `smartFiltersSection` and before `foldersSection`, add:

```swift
                    tagsSection
```

Add this computed property:

```swift
    private var tagsSection: some View {
        SidebarActionSection(
            title: L10n.sidebarTagsSection,
            actionSystemImage: "tag",
            actionHelp: L10n.tagManagerManageButton
        ) {
            isShowingTagManager = true
        } content: {
            EmptyView()
        }
    }
```

Add the sheet:

```swift
        .sheet(isPresented: $isShowingTagManager) {
            TagManagerView()
        }
```

- [ ] **Step 3: Update docs**

In `AGENTS.md`, update:

```text
TagViewModel.swift          # Tags verwalten ✅
TagManagerView.swift        # Tags erstellen, bearbeiten, loeschen ✅
AddTagView.swift            # bleibt vorerst nicht separat noetig; TagManagerView erstellt Tags direkt
```

Add implementation bullets for `TagViewModel.swift` and `TagManagerView.swift`.

In `docs/FEATURES.md`, update section `5.1 Tags verwalten`:

```text
- Status: Fertig als Basis
- Implementiert: Artikel-Tags koennen im Reader-Inspector hinzugefuegt und entfernt
  werden. Tags koennen zentral erstellt, umbenannt, farblich markiert und geloescht
  werden.
- Offen: Feed-Tags und Tags in der Sidebar filtern folgen separat.
```

- [ ] **Step 4: Run full non-UI test suite**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarView.swift AGENTS.md docs/FEATURES.md
git commit -m "feat: expose tag manager from sidebar"
```

---

## Task 7: Final Verification

**Files:**
- No new files. Verify committed changes.

- [ ] **Step 1: Check status**

Run:

```bash
git status --short --branch
```

Expected: only unrelated pre-existing local files remain, or a clean worktree if those were handled separately.

- [ ] **Step 2: Run final verification**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests
```

Expected: TEST SUCCEEDED.

- [ ] **Step 3: Summarize**

Final response should include:

```text
Implemented M3 Block 1 tag management:
- TagViewModel with validation and SwiftData mutations
- TagManagerView sheet
- color swatches and Reader Inspector tag pill colors
- Sidebar entry to open tag management
- documentation updates

Verified with:
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests
```

If tests fail, do not claim completion. Report the failing command and error summary.
