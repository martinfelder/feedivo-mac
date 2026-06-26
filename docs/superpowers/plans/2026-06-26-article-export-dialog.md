# Article Export Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Feature 18.1a: a two-step article export sheet with Markdown, Plain Text, and HTML output, optional metadata, preview, and a Reader toolbar entry point.

**Architecture:** Keep the file exporter owned by `ContentView` through the existing stable sheet path, but change the request from a prebuilt Markdown document to a primitive `ArticleExportSnapshot`. Move format, options, generated text, filename, and UTType decisions into the export service so the UI remains mostly state and presentation.

**Tech Stack:** SwiftUI, SwiftData snapshots, Swift Testing, SwiftUI `FileDocument`, `UniformTypeIdentifiers`, localized strings through `L10n` and `Localizable.xcstrings`.

---

## File Structure

- Modify `Feedivo/Services/ArticleExportService.swift`
  - Add `ArticleExportFormat`, `ArticleExportOptions`, and format-aware export generation.
  - Extend `ArticleExportSnapshot` with `author`, `feedTitle`, and `tagNames`.
  - Keep HTML conversion regex-only; do not introduce AppKit/WebKit importers.
- Rename `Feedivo/Services/ArticleMarkdownDocument.swift` to `Feedivo/Services/ArticleExportDocument.swift`
  - Keep a tiny `FileDocument` wrapper for already-generated text.
  - Support `.md`, `.txt`, and `.html` content types.
- Modify `Feedivo/Views/ArticleList/ArticleExportSheet.swift`
  - Replace the current one-button presentation anchor with the approved two-step Variant B flow.
  - Compute preview, filename, document, and content type from `ArticleExportService`.
- Modify `Feedivo/Views/ContentView.swift`
  - Build `ArticleExportRequest(snapshot:)` from the selected article.
  - Pass the export action to `ReaderView`.
- Modify `Feedivo/Views/Reader/ReaderView.swift`
  - Add a toolbar export button using `square.and.arrow.up`.
- Modify `Feedivo/Resources/L10n.swift` and `Feedivo/Resources/Localizable.xcstrings`
  - Add all labels and descriptions needed by the two-step sheet.
- Modify `FeedivoTests/ArticleExportServiceTests.swift`
  - Add tests for format output, metadata on/off, filenames, feed/tag metadata, and HTML escaping.
- Modify `FEATURES.md` and `AGENTS.md`
  - Record that Feature 18.1a is implemented as Markdown/Text/HTML with preview, while PDF/DOCX remain later slices.

## Task 1: Export Domain And Tests

**Files:**
- Modify: `FeedivoTests/ArticleExportServiceTests.swift`
- Modify: `Feedivo/Services/ArticleExportService.swift`

- [ ] **Step 1: Write failing tests for format-aware export**

Append these tests to `FeedivoTests/ArticleExportServiceTests.swift`:

```swift
@Test func markdownExportKannMetadatenAusblenden() {
    let article = Article(
        title: "Swift & RSS",
        link: "https://example.com/swift-rss",
        summary: "Kurze Zusammenfassung",
        content: "<p>Artikeltext</p>",
        publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let text = ArticleExportService.text(
        for: ArticleExportSnapshot(article: article),
        options: ArticleExportOptions(format: .markdown, includesMetadata: false)
    )

    #expect(text.contains("# Swift & RSS"))
    #expect(text.contains("Artikeltext"))
    #expect(!text.contains("Link:"))
    #expect(!text.contains("Veröffentlicht:"))
}

@Test func plainTextExportEnthaeltKeineMarkdownSyntax() {
    let article = Article(
        title: "Swift & RSS",
        link: "https://example.com/swift-rss",
        summary: "Kurze Zusammenfassung",
        content: "<h2>Untertitel</h2><p>Ein <strong>lesbarer</strong> Absatz.</p>"
    )

    let text = ArticleExportService.text(
        for: ArticleExportSnapshot(article: article),
        options: ArticleExportOptions(format: .plainText, includesMetadata: true)
    )

    #expect(text.contains("Swift & RSS"))
    #expect(text.contains("Untertitel"))
    #expect(text.contains("Ein lesbarer Absatz."))
    #expect(!text.contains("# Swift & RSS"))
    #expect(!text.contains("<strong>"))
}

@Test func htmlExportEscapedTitelUndMetadaten() {
    let article = Article(
        title: "Swift <RSS>",
        link: "https://example.com/swift-rss",
        summary: "Kurze Zusammenfassung",
        content: "<p>Ein <strong>lesbarer</strong> Absatz.</p>"
    )

    let html = ArticleExportService.text(
        for: ArticleExportSnapshot(article: article),
        options: ArticleExportOptions(format: .html, includesMetadata: true)
    )

    #expect(html.contains("<!doctype html>"))
    #expect(html.contains("<title>Swift &lt;RSS&gt;</title>"))
    #expect(html.contains("<h1>Swift &lt;RSS&gt;</h1>"))
    #expect(html.contains("<p>Link: <a href=\"https://example.com/swift-rss\">https://example.com/swift-rss</a></p>"))
    #expect(html.contains("<strong>lesbarer</strong>"))
}

@Test func metadatenEnthaltenAutorFeedUndTags() {
    let feed = Feed(url: "https://example.com/feed.xml", title: "Example Feed")
    let article = Article(
        title: "Metadaten",
        link: "https://example.com/a",
        author: "Ada",
        feed: feed
    )
    article.tags = [
        Tag(name: "Swift"),
        Tag(name: "RSS")
    ]

    let markdown = ArticleExportService.text(
        for: ArticleExportSnapshot(article: article),
        options: ArticleExportOptions(format: .markdown, includesMetadata: true)
    )

    #expect(markdown.contains("Autor: Ada"))
    #expect(markdown.contains("Feed: Example Feed"))
    #expect(markdown.contains("Tags: RSS, Swift"))
}

@Test func defaultFilenameNutztGewaehltesFormat() {
    let snapshot = ArticleExportSnapshot(article: Article(title: "Swift/RSS: Was ist neu?"))

    #expect(ArticleExportService.defaultFilename(for: snapshot, format: .markdown) == "Swift-RSS- Was ist neu.md")
    #expect(ArticleExportService.defaultFilename(for: snapshot, format: .plainText) == "Swift-RSS- Was ist neu.txt")
    #expect(ArticleExportService.defaultFilename(for: snapshot, format: .html) == "Swift-RSS- Was ist neu.html")
}
```

- [ ] **Step 2: Run the focused tests and confirm they fail**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportServiceTests
```

Expected: FAIL because `ArticleExportOptions`, `ArticleExportFormat`, and format-aware overloads do not exist yet.

- [ ] **Step 3: Implement export formats and options**

In `Feedivo/Services/ArticleExportService.swift`, add these public helper types above `ArticleExportSnapshot`:

```swift
import UniformTypeIdentifiers

enum ArticleExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case plainText
    case html

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .markdown:
            "md"
        case .plainText:
            "txt"
        case .html:
            "html"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown:
            .markdownText
        case .plainText:
            .plainText
        case .html:
            .html
        }
    }
}

struct ArticleExportOptions: Equatable {
    var format: ArticleExportFormat = .markdown
    var includesMetadata = true
}
```

Extend `ArticleExportSnapshot`:

```swift
struct ArticleExportSnapshot {
    let title: String
    let link: String?
    let summary: String?
    let content: String?
    let author: String?
    let publishedAt: Date?
    let feedTitle: String?
    let tagNames: [String]
    let offlineState: ArticleOfflineState
    let offlineContent: String?

    init(article: Article) {
        self.title = article.title
        self.link = article.link
        self.summary = article.summary
        self.content = article.content
        self.author = article.author
        self.publishedAt = article.publishedAt
        self.feedTitle = article.feed?.title
        self.tagNames = article.tags.map(\.name).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        self.offlineState = article.offlineState
        self.offlineContent = article.offlineContent
    }
}
```

Then refactor the service API so the old Markdown calls still work:

```swift
enum ArticleExportService {
    static func markdown(for article: Article) -> String {
        markdown(for: ArticleExportSnapshot(article: article))
    }

    static func markdown(for snapshot: ArticleExportSnapshot) -> String {
        text(for: snapshot, options: ArticleExportOptions(format: .markdown, includesMetadata: true))
    }

    static func text(for snapshot: ArticleExportSnapshot, options: ArticleExportOptions) -> String {
        switch options.format {
        case .markdown:
            markdownText(for: snapshot, includesMetadata: options.includesMetadata)
        case .plainText:
            plainText(for: snapshot, includesMetadata: options.includesMetadata)
        case .html:
            htmlText(for: snapshot, includesMetadata: options.includesMetadata)
        }
    }

    static func previewText(for snapshot: ArticleExportSnapshot, options: ArticleExportOptions) -> String {
        let lines = text(for: snapshot, options: options)
            .components(separatedBy: .newlines)
            .prefix(40)
        return lines.joined(separator: "\n")
    }

    static func defaultFilename(for article: Article) -> String {
        defaultFilename(for: ArticleExportSnapshot(article: article), format: .markdown)
    }

    static func defaultFilename(for snapshot: ArticleExportSnapshot) -> String {
        defaultFilename(for: snapshot, format: .markdown)
    }

    static func defaultFilename(for snapshot: ArticleExportSnapshot, format: ArticleExportFormat) -> String {
        "\(defaultFilenameBase(forTitle: snapshot.title)).\(format.fileExtension)"
    }
}
```

Keep the existing regex helpers, but split the body generation into these functions:

```swift
private static func markdownText(for snapshot: ArticleExportSnapshot, includesMetadata: Bool) -> String
private static func plainText(for snapshot: ArticleExportSnapshot, includesMetadata: Bool) -> String
private static func htmlText(for snapshot: ArticleExportSnapshot, includesMetadata: Bool) -> String
private static func plainBodyLines(from htmlOrText: String?) -> [String]
private static func escapedHTML(_ text: String) -> String
private static func metadataLines(for snapshot: ArticleExportSnapshot) -> [String]
```

Implementation rules:
- `markdownText` keeps the current `# Titel`, metadata block, `---`, and `markdownBodyLines`.
- `plainText` uses title as the first line, a blank line, optional metadata lines, another blank line, then `plainBodyLines`.
- `htmlText` emits a small complete HTML document with escaped title/metadata and body content. Strip scripts/styles before inserting article content. Existing feed HTML may be preserved for simple tags like `<p>`, `<strong>`, `<em>`, lists, headings, and links.
- `metadataLines` appends `Autor`, `Veröffentlicht`, `Feed`, `Link`, and `Tags` when present.

- [ ] **Step 4: Run the focused tests and confirm they pass**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add Feedivo/Services/ArticleExportService.swift FeedivoTests/ArticleExportServiceTests.swift
git commit -m "Add article export formats"
```

## Task 2: Generic Export Document

**Files:**
- Rename: `Feedivo/Services/ArticleMarkdownDocument.swift` -> `Feedivo/Services/ArticleExportDocument.swift`
- Modify: `Feedivo.xcodeproj/project.pbxproj` if Xcode does not track the rename automatically

- [ ] **Step 1: Rename the document file**

Run:

```bash
git mv Feedivo/Services/ArticleMarkdownDocument.swift Feedivo/Services/ArticleExportDocument.swift
```

- [ ] **Step 2: Replace the document type**

In `Feedivo/Services/ArticleExportDocument.swift`, replace the struct with:

```swift
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(filenameExtension: "md") ?? .plainText
}

struct ArticleExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownText, .plainText, .html] }
    static var writableContentTypes: [UTType] { [.markdownText, .plainText, .html] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else {
            self.text = ""
            return
        }

        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
```

- [ ] **Step 3: Replace references**

Run:

```bash
rg -n "ArticleMarkdownDocument|ArticleExportDocument" Feedivo FeedivoTests
```

Expected before edits: old references in `ArticleExportSheet.swift` or `ContentView.swift`.

Change every `ArticleMarkdownDocument` reference to `ArticleExportDocument`.

- [ ] **Step 4: Build to verify the rename**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add Feedivo/Services/ArticleExportDocument.swift Feedivo.xcodeproj/project.pbxproj
git add -u Feedivo/Services/ArticleMarkdownDocument.swift
git commit -m "Rename article export document"
```

## Task 3: Two-Step Export Sheet

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleExportSheet.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [ ] **Step 1: Replace request model and add sheet state**

Change `ArticleExportRequest` to store primitives:

```swift
struct ArticleExportRequest: Identifiable {
    let id = UUID()
    let snapshot: ArticleExportSnapshot
}
```

Add private state and computed values inside `ArticleExportSheet`:

```swift
private enum ArticleExportStep {
    case prepare
    case preview
}

@State private var step: ArticleExportStep = .prepare
@State private var selectedFormat: ArticleExportFormat = .markdown
@State private var includesMetadata = true
@State private var isExporting = false

private var options: ArticleExportOptions {
    ArticleExportOptions(format: selectedFormat, includesMetadata: includesMetadata)
}

private var exportText: String {
    ArticleExportService.text(for: request.snapshot, options: options)
}

private var previewText: String {
    ArticleExportService.previewText(for: request.snapshot, options: options)
}

private var defaultFilename: String {
    ArticleExportService.defaultFilename(for: request.snapshot, format: selectedFormat)
}

private var document: ArticleExportDocument {
    ArticleExportDocument(text: exportText)
}
```

- [ ] **Step 2: Implement the prepare step UI**

Use this structure for the first step:

```swift
private var prepareStep: some View {
    VStack(alignment: .leading, spacing: 18) {
        sheetHeader(
            title: L10n.articleExportPrepareTitle,
            message: L10n.articleExportPrepareMessage
        )

        VStack(spacing: 0) {
            ForEach(ArticleExportFormat.allCases) { format in
                ArticleExportFormatRow(
                    format: format,
                    isSelected: selectedFormat == format
                ) {
                    selectedFormat = format
                }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }

        Toggle(isOn: $includesMetadata) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.articleExportMetadataToggle)
                Text(L10n.articleExportMetadataDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)

        HStack {
            Spacer()
            Button(L10n.commonCancel) { onClose() }
            Button(L10n.commonNext) { step = .preview }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }
}
```

Add `ArticleExportFormatRow` in the same file. It should use a selected/unselected circle system image, the localized format name, extension, and description.

- [ ] **Step 3: Implement the preview step UI**

Use this structure for the second step:

```swift
private var previewStep: some View {
    VStack(alignment: .leading, spacing: 18) {
        sheetHeader(
            title: L10n.articleExportPreviewTitle,
            message: L10n.articleExportPreviewMessage
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedFormat.localizedTitle)
                    .font(.headline)
                Spacer()
                Text(defaultFilename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(previewText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }

        VStack(alignment: .leading, spacing: 6) {
            exportSummaryRow(label: L10n.articleExportSummaryFormat, value: selectedFormat.localizedTitle)
            exportSummaryRow(label: L10n.articleExportSummaryMetadata, value: includesMetadata ? L10n.commonOn : L10n.commonOff)
            exportSummaryRow(label: L10n.articleExportSummarySource, value: contentSourceLabel)
        }

        HStack {
            Button(L10n.commonBack) { step = .prepare }
            Spacer()
            Button(L10n.commonCancel) { onClose() }
            Button(L10n.articleExportSaveButton) { isExporting = true }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }
}
```

Keep `.fileExporter` on the outer sheet:

```swift
.fileExporter(
    isPresented: $isExporting,
    document: document,
    contentType: selectedFormat.contentType,
    defaultFilename: defaultFilename
) { _ in
    onClose()
}
```

- [ ] **Step 4: Add localization accessors**

Add these accessors to `Feedivo/Resources/L10n.swift` near the existing export keys:

```swift
static var articleExportPrepareTitle: String { String(localized: "article.export.prepare.title") }
static var articleExportPrepareMessage: String { String(localized: "article.export.prepare.message") }
static var articleExportPreviewTitle: String { String(localized: "article.export.preview.title") }
static var articleExportPreviewMessage: String { String(localized: "article.export.preview.message") }
static var articleExportFormatMarkdown: String { String(localized: "article.export.format.markdown") }
static var articleExportFormatMarkdownDescription: String { String(localized: "article.export.format.markdown.description") }
static var articleExportFormatPlainText: String { String(localized: "article.export.format.plainText") }
static var articleExportFormatPlainTextDescription: String { String(localized: "article.export.format.plainText.description") }
static var articleExportFormatHTML: String { String(localized: "article.export.format.html") }
static var articleExportFormatHTMLDescription: String { String(localized: "article.export.format.html.description") }
static var articleExportMetadataToggle: String { String(localized: "article.export.metadata.toggle") }
static var articleExportMetadataDescription: String { String(localized: "article.export.metadata.description") }
static var articleExportSummaryFormat: String { String(localized: "article.export.summary.format") }
static var articleExportSummaryMetadata: String { String(localized: "article.export.summary.metadata") }
static var articleExportSummarySource: String { String(localized: "article.export.summary.source") }
static var articleExportSourceOffline: String { String(localized: "article.export.source.offline") }
static var articleExportSourceFeedContent: String { String(localized: "article.export.source.feedContent") }
static var articleExportSourceSummary: String { String(localized: "article.export.source.summary") }
```

If `common.next`, `common.back`, `common.on`, or `common.off` do not exist yet, add `L10n.commonNext`, `L10n.commonBack`, `L10n.commonOn`, and `L10n.commonOff` too.

- [ ] **Step 5: Add String Catalog keys**

Add German source values and translations for the new keys in `Feedivo/Resources/Localizable.xcstrings`. German source text:

```text
article.export.prepare.title = Export vorbereiten
article.export.prepare.message = Wähle Dateiformat und enthaltene Informationen.
article.export.preview.title = Export prüfen
article.export.preview.message = Feedivo zeigt eine Vorschau, bevor der macOS-Speichern-Dialog geöffnet wird.
article.export.format.markdown = Markdown
article.export.format.markdown.description = Für Notizen und portable Textarchive.
article.export.format.plainText = Plain Text
article.export.format.plainText.description = Reiner lesbarer Text ohne Formatierung.
article.export.format.html = HTML
article.export.format.html.description = Behält Artikelstruktur und Links.
article.export.metadata.toggle = Metadaten einschließen
article.export.metadata.description = Titel, Autor, Datum, Feed, URL und Tags.
article.export.summary.format = Format
article.export.summary.metadata = Metadaten
article.export.summary.source = Inhalt
article.export.source.offline = Gespeicherte Offline-Kopie
article.export.source.feedContent = Feed-Inhalt
article.export.source.summary = Zusammenfassung
common.next = Weiter
common.back = Zurück
common.on = Ein
common.off = Aus
```

Keep existing export keys for compatibility or remove them only after confirming no call sites remain.

- [ ] **Step 6: Build the UI**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
git add Feedivo/Views/ArticleList/ArticleExportSheet.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Add article export preview sheet"
```

## Task 4: ContentView And Reader Toolbar Entry

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Views/Reader/ReaderView.swift`

- [ ] **Step 1: Update `ContentView` request creation**

Replace `requestExportArticle(_:)` with:

```swift
private func requestExportArticle(_ article: Article) {
    let request = ArticleExportRequest(snapshot: ArticleExportSnapshot(article: article))

    // Der Export kommt oft aus einem Kontextmenü. Der nächste Main-Runloop verhindert,
    // dass das Export-Sheet noch während der Menüaktion präsentiert wird.
    DispatchQueue.main.async {
        articleExportRequest = request
    }
}
```

- [ ] **Step 2: Pass export action into ReaderView**

Where `ReaderView` is created in `ContentView`, add:

```swift
onRequestExportArticle: requestExportArticle,
```

next to the existing `onRequestCreateRuleFromArticle` callback.

- [ ] **Step 3: Add ReaderView callback property**

In `Feedivo/Views/Reader/ReaderView.swift`, add:

```swift
let onRequestExportArticle: (Article) -> Void
```

to the view properties and initializer, defaulting to `{ _ in }` if previews or call sites need it.

- [ ] **Step 4: Add toolbar button**

In the Reader toolbar next to the existing article actions, add:

```swift
Button {
    onRequestExportArticle(article)
} label: {
    Label(L10n.articleExportCommand, systemImage: "square.and.arrow.up")
}
.help(L10n.articleExportCommand)
```

Keep the existing article-row context menu export entry unchanged; both entry points should present the same sheet.

- [ ] **Step 5: Build to verify call sites**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 6: Commit Task 4**

Run:

```bash
git add Feedivo/Views/ContentView.swift Feedivo/Views/Reader/ReaderView.swift
git commit -m "Add reader article export action"
```

## Task 5: Documentation And Roadmap Memory

**Files:**
- Modify: `FEATURES.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Update `FEATURES.md`**

In `FEATURES.md`, update Feature 18.1 to record the first slice:

```markdown
### 18.1 Einzelnen Artikel exportieren
- **Status:** 🔨 Erster Slice umgesetzt / weiter ausbaubar
- **Umgesetzt 18.1a:**
  - Einzelartikel-Export über Kontextmenü und Reader-Toolbar.
  - Zweistufiger Export-Dialog nach Variante B: Format wählen, Metadaten-Option, dann Vorschau und `Sichern...`.
  - Formate: Markdown (`.md`), Plain Text (`.txt`), HTML (`.html`).
  - Optional einschließbare Metadaten: Titel, Autor, Veröffentlichungsdatum, Feed, URL, Tags.
  - Export bevorzugt gespeicherten Offline-Inhalt, fällt sonst auf Feed-Inhalt oder Summary zurück.
- **Später:** PDF, DOCX, Bilder-Optionen, Share Sheet und Batch-Export bleiben eigene Slices.
```

- [ ] **Step 2: Update `AGENTS.md` project memory**

Update these places:
- Project structure entry: `ArticleExportDocument.swift` instead of `ArticleMarkdownDocument.swift`.
- `ArticleExportService.swift` description: Markdown/Text/HTML with options and preview.
- `ArticleExportSheet.swift` description: two-step Variant B sheet.
- “Letzte Änderungen”: add a dated note for Feature 18.1a.
- “Aktuell in Arbeit”: mark 18.1a complete and PDF/DOCX/share as remaining later slices.

- [ ] **Step 3: Commit Task 5**

Run:

```bash
git add FEATURES.md AGENTS.md
git commit -m "Document article export slice"
```

## Task 6: Final Verification

**Files:**
- No code files expected unless verification exposes a bug.

- [ ] **Step 1: Run focused export tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleExportServiceTests
```

Expected: PASS.

- [ ] **Step 2: Run full unit tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests
```

Expected: PASS. If a known unrelated UI-test issue appears only outside `FeedivoTests`, document it but do not treat it as a failure of this slice.

- [ ] **Step 3: Build the app**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 4: Manual UI check**

Run the app from Xcode or with the project’s existing build workflow, then verify:
- Article row context menu `Exportieren...` opens `Export vorbereiten`.
- Reader toolbar export button opens the same sheet.
- `Weiter` shows `Export prüfen`.
- `Zurück` preserves selected format and metadata option.
- Markdown, Plain Text, and HTML change preview text and filename extension.
- `Sichern...` opens the native save dialog.

- [ ] **Step 5: Review git diff**

Run:

```bash
git status --short --branch
git diff --stat
git diff -- Feedivo/Services/ArticleExportService.swift Feedivo/Views/ArticleList/ArticleExportSheet.swift Feedivo/Views/Reader/ReaderView.swift
```

Expected: only intentional changes plus the existing local Xcode `UserInterfaceState.xcuserstate` modification, which should not be committed.

## Self-Review

- Spec coverage: Variant B with second-step preview is implemented in Task 3; Markdown/Text/HTML and metadata toggle in Task 1; Reader toolbar entry in Task 4; stable root-level file exporter path preserved through `ContentView`; PDF/DOCX explicitly remain later in Task 5.
- Placeholder scan: no `TBD`, `TODO`, “similar to”, or undefined later-only type remains in this plan.
- Type consistency: `ArticleExportFormat`, `ArticleExportOptions`, `ArticleExportSnapshot`, `ArticleExportDocument`, and `ArticleExportRequest(snapshot:)` are introduced before use in later tasks.
