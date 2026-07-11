import AppKit
import SwiftUI

struct SQLiteReaderView: View {
    @Environment(\.feedivoDatabase) private var database
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @Environment(\.openWindow) private var openWindow

    let articleID: String?
    let canSelectPreviousArticle: Bool
    let canSelectNextArticle: Bool
    let selectPreviousArticle: () -> Void
    let selectNextArticle: () -> Void
    let onSnapshotChange: (ArticleReaderSnapshot?) -> Void
    let onCreateRule: (ArticleReaderSnapshot) -> Void

    @State private var state = SQLiteReaderState()
    @State private var isAppearancePopoverPresented = false
    @State private var isMetadataInspectorPresented = false
    @State private var articleExportRequest: ArticleExportRequest?
    @State private var webContentLoadFailed = false
    @State private var webNavigationController = WebNavigationController()

    @AppStorage(ReaderTypographySettings.titleFontPresetKey)
    private var titleFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage(ReaderTypographySettings.bodyFontPresetKey)
    private var bodyFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage(ReaderTypographySettings.titleFontIsBoldKey)
    private var readerTitleFontIsBold = ReaderTypography.defaultTitleFontIsBold

    @AppStorage(ReaderTypographySettings.bodyFontIsBoldKey)
    private var readerBodyFontIsBold = ReaderTypography.defaultBodyFontIsBold

    @AppStorage(ReaderTypographySettings.bodyFontSizeKey)
    private var readerBodyFontSize = ReaderTypography.defaultBodyFontSize

    @AppStorage(ReaderTypographySettings.lineSpacingKey)
    private var readerLineSpacing = ReaderTypography.defaultLineSpacing

    @AppStorage(ReaderTypographySettings.titleLineSpacingKey)
    private var readerTitleLineSpacing = ReaderTypography.defaultTitleLineSpacing

    @AppStorage(ReaderTypographySettings.contentWidthKey)
    private var readerContentWidth = ReaderTypography.defaultContentWidth

    @AppStorage(ReaderTypographySettings.showsArticleImagesKey)
    private var readerShowsArticleImages = ReaderTypography.defaultShowsArticleImages

    @AppStorage(ReaderDisplayMode.storageKey)
    private var readerDisplayModeRawValue = ReaderDisplayMode.defaultMode.rawValue

    @AppStorage(ArticleInAppWebProfile.storageKey)
    private var articleInAppWebProfileRawValue = ArticleInAppWebProfile.defaultProfile.rawValue

    @AppStorage(KeyboardShortcutOverrides.storageKey)
    private var shortcutOverridesRawValue = KeyboardShortcutOverrides().rawValue

    private var shortcutOverrides: KeyboardShortcutOverrides {
        KeyboardShortcutOverrides.resolved(from: shortcutOverridesRawValue)
    }

    init(
        articleID: String?,
        canSelectPreviousArticle: Bool = false,
        canSelectNextArticle: Bool = false,
        selectPreviousArticle: @escaping () -> Void = {},
        selectNextArticle: @escaping () -> Void = {},
        onSnapshotChange: @escaping (ArticleReaderSnapshot?) -> Void = { _ in },
        onCreateRule: @escaping (ArticleReaderSnapshot) -> Void = { _ in }
    ) {
        self.articleID = articleID
        self.canSelectPreviousArticle = canSelectPreviousArticle
        self.canSelectNextArticle = canSelectNextArticle
        self.selectPreviousArticle = selectPreviousArticle
        self.selectNextArticle = selectNextArticle
        self.onSnapshotChange = onSnapshotChange
        self.onCreateRule = onCreateRule
    }

    var body: some View {
        Group {
            if let database, let articleID {
                readerContent(articleID: articleID, database: database)
            } else if database == nil {
                ContentUnavailableView(
                    "SQLite nicht verfügbar",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Die lokale Artikeldatenbank konnte nicht geöffnet werden.")
                )
            } else {
                ContentUnavailableView(
                    L10n.contentNoArticleSelectedTitle,
                    systemImage: "doc.text",
                    description: Text(L10n.contentNoArticleSelectedDescription)
                )
            }
        }
        .navigationTitle(state.snapshot?.title ?? "")
        .inspector(isPresented: $isMetadataInspectorPresented) {
            if let snapshot = state.snapshot {
                ArticleMetadataInspectorView(snapshot: snapshot, close: {
                    isMetadataInspectorPresented = false
                })
                .inspectorColumnWidth(min: 280, ideal: 318, max: 360)
            } else {
                Text("Noch kein Artikel geladen")
                    .padding()
            }
        }
        .onChange(of: state.snapshot) { _, snapshot in
            onSnapshotChange(snapshot)
        }
        .onDisappear {
            onSnapshotChange(nil)
        }
        .sheet(item: $articleExportRequest) { request in
            ArticleExportSheet(request: request) {
                articleExportRequest = nil
            }
        }
        .toolbar {
            // Jede Gruppe als EIGENES ToolbarItem/ToolbarItemGroup statt einer
            // einzigen, alles umfassenden ToolbarItemGroup: Eine ToolbarItemGroup
            // wird von NSToolbar als EIN unteilbares Element behandelt ("always
            // displayed together" laut Apple-Doku) — bei ~15 Controls in einer
            // einzigen Gruppe kann NSToolbar dem zugehörigen NSToolbarItem nach
            // bestimmten Fenster-Lebenszyklus-Übergängen (Schliessen/Wiederöffnen,
            // Vollbild) eine zu schmale, veraltete Breite zuweisen — der
            // eingebettete SwiftUI-Inhalt ist dann breiter als das zugewiesene
            // NSToolbarItem und überlappt sichtbar benachbarte Toolbar-Bereiche
            // (Nutzer-Report 2026-07-11: Icons oberhalb des Artikels überlappen
            // nach Schliessen/Wiederöffnen/Vollbild). Mehrere kleinere, unabhängige
            // Toolbar-Items lässt macOS bei Platzmangel einzeln ins "»"-Overflow-
            // Menü kollabieren, statt ein einziges, zu breites Element starr
            // darzustellen.
            ToolbarItem(placement: .primaryAction) {
                Spacer()
            }

            ToolbarItemGroup(placement: .primaryAction) {
                ControlGroup {
                    Button {
                        openWindow(id: ArticleSearchWindowView.windowID)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help(L10n.articleSearchCommand)

                    Button {
                        openOriginal()
                    } label: {
                        Image(systemName: "safari")
                    }
                    .help(L10n.articleOpenOriginalCommand)
                    .disabled(originalURL == nil)
                }
            }

            // Status-Gruppe: Regel erstellen / Stern / Archivieren / Ungelesen
            ToolbarItemGroup(placement: .primaryAction) {
                ControlGroup {
                    Button {
                        if let snapshot = state.snapshot {
                            onCreateRule(snapshot)
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help(L10n.articleCreateRuleCommand)
                    .disabled(state.snapshot == nil)

                    Button {
                        if let database {
                            state.toggleStarred(database: database)
                        }
                    } label: {
                        Image(systemName: state.snapshot?.isStarred == true ? "star.fill" : "star")
                    }
                    .help(state.snapshot?.isStarred == true ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
                    .disabled(state.snapshot == nil)

                    Button {
                        if let database {
                            state.toggleArchived(database: database)
                        }
                    } label: {
                        Image(systemName: state.snapshot?.isArchived == true ? "archivebox.fill" : "archivebox")
                    }
                    .help(state.snapshot?.isArchived == true ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand)
                    .disabled(state.snapshot == nil)

                    Button {
                        if let database {
                            state.toggleRead(database: database)
                        }
                    } label: {
                        Image(systemName: state.snapshot?.isRead == true ? "circle" : "circle.fill")
                    }
                    .help(state.snapshot?.isRead == true ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead)
                    .disabled(state.snapshot == nil)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                ControlGroup {
                    Button {
                        copyLink()
                    } label: {
                        Image(systemName: "link")
                    }
                    .help(L10n.articleCopyLinkCommand)
                    .disabled(originalURL == nil)

                    Button {
                        requestExportArticle()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help(L10n.articleExportCommand)
                    .disabled(state.snapshot == nil)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
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
            }

            ToolbarItem(placement: .primaryAction) {
                Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
                    ForEach(ReaderDisplayMode.allCases) { mode in
                        Text(mode.titleKey)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .help(L10n.readerDisplayModeToggleHelp)
                .disabled(originalURL == nil)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAppearancePopoverPresented.toggle()
                } label: {
                    Image(systemName: "textformat")
                }
                .help(L10n.readerAppearanceButton)
                .popover(isPresented: $isAppearancePopoverPresented, arrowEdge: .bottom) {
                    readerAppearancePopover
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isMetadataInspectorPresented.toggle()
                } label: {
                    Label(L10n.readerInspectorButton, systemImage: "sidebar.right")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .symbolVariant(isMetadataInspectorPresented ? .fill : .none)
                .help(L10n.readerInspectorButton)
            }
        }
    }

    private var titleFontPreset: ReaderFontPreset {
        ReaderFontPreset.resolved(from: titleFontPresetRawValue)
    }

    private var bodyFontPreset: ReaderFontPreset {
        ReaderFontPreset.resolved(from: bodyFontPresetRawValue)
    }

    private var titleFontWeight: Font.Weight {
        readerTitleFontIsBold ? .bold : .semibold
    }

    private var bodyFontWeight: Font.Weight {
        readerBodyFontIsBold ? .bold : .regular
    }

    private var contentHeadingFontWeight: Font.Weight {
        readerBodyFontIsBold ? .bold : .semibold
    }

    private var clampedBodyFontSize: CGFloat {
        CGFloat(ReaderTypography.clampedBodyFontSize(readerBodyFontSize))
    }

    private var clampedLineSpacing: CGFloat {
        CGFloat(ReaderTypography.clampedLineSpacing(readerLineSpacing))
    }

    private var clampedTitleLineSpacing: CGFloat {
        CGFloat(ReaderTypography.clampedTitleLineSpacing(readerTitleLineSpacing))
    }

    private var clampedContentWidth: CGFloat {
        CGFloat(ReaderTypography.clampedContentWidth(readerContentWidth))
    }

    private var contentBlockSpacing: CGFloat {
        CGFloat(ReaderTypography.contentBlockSpacing)
    }

    private var imageTextDividerSpacing: CGFloat {
        CGFloat(ReaderTypography.imageTextDividerSpacing)
    }

    private var articleTopPadding: CGFloat {
        CGFloat(ReaderTypography.articleTopPadding)
    }

    private var articleBottomPadding: CGFloat {
        CGFloat(ReaderTypography.articleBottomPadding)
    }

    private var headerSpacing: CGFloat {
        CGFloat(ReaderTypography.headerSpacing)
    }

    private var footerTopPadding: CGFloat {
        CGFloat(ReaderTypography.footerTopPadding)
    }

    private var metadataFontSize: CGFloat {
        CGFloat(ReaderTypography.metadataFontSize(forBodyFontSize: readerBodyFontSize))
    }

    private var originalURL: URL? {
        guard let link = state.snapshot?.link else {
            return nil
        }

        return URL(string: link)
    }

    private var readerDisplayMode: ReaderDisplayMode {
        ReaderDisplayMode.resolved(from: readerDisplayModeRawValue)
    }

    private var articleInAppWebProfile: ArticleInAppWebProfile {
        ArticleInAppWebProfile.resolved(from: articleInAppWebProfileRawValue)
    }

    private func readerContent(articleID: String, database: FeedivoDatabase) -> some View {
        ReaderModeContent(
            articleID: articleID,
            database: database,
            state: state,
            readerDisplayMode: readerDisplayMode,
            articleInAppWebProfile: articleInAppWebProfile,
            webContentLoadFailed: $webContentLoadFailed,
            webNavigationController: webNavigationController,
            originalURL: originalURL,
            clampedContentWidth: clampedContentWidth,
            showsArticleImages: readerShowsArticleImages,
            contentBlockSpacing: contentBlockSpacing,
            imageTextDividerSpacing: imageTextDividerSpacing,
            articleTopPadding: articleTopPadding,
            articleBottomPadding: articleBottomPadding,
            readerHeader: { AnyView(readerHeader($0)) },
            contentBlock: { AnyView(contentBlock($0)) },
            readerFooter: { AnyView(readerFooter($0)) },
            readerSectionDivider: AnyView(readerSectionDivider),
            shouldShowImageTextDivider: shouldShowImageTextDivider
        )
    }

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

    @ViewBuilder
    private func readerArticleMetadata(_ snapshot: ArticleReaderSnapshot) -> some View {
        let folderName = FeedFolderOrganizer.normalizedFolderName(snapshot.folderName)
        if folderName != nil || !snapshot.tags.isEmpty {
            FlowLayout(spacing: 8) {
                if let folderName {
                    readerFolderChip(folderName)
                }

                ForEach(snapshot.tags) { tag in
                    readerTagChip(tag)
                }
            }
            .padding(.top, 2)
        }
    }

    private var readerMetadataChipHeight: CGFloat {
        interfaceTextSize.scaled(26)
    }

    private func readerFolderChip(_ folderName: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.caption2)

            Text(folderName)
                .lineLimit(1)
        }
        .font(interfaceTextSize.font(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: readerMetadataChipHeight)
        .background(.secondary.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private func readerTagChip(_ tag: ReaderArticleTagMetadata) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return Text("#\(tag.name)")
            .lineLimit(1)
            .font(interfaceTextSize.font(size: 12, weight: .semibold))
            .foregroundStyle(tagColor)
            .padding(.horizontal, 10)
            .frame(height: readerMetadataChipHeight)
            .background(tagColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tagColor.opacity(0.24), lineWidth: 1)
            }
    }

    @ViewBuilder
    private func readerFooter(_ snapshot: ArticleReaderSnapshot) -> some View {
        if let link = snapshot.link, let url = URL(string: link) {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                Button {
                    ArticleOriginalBrowserLauncher.open(url)
                } label: {
                    Label(L10n.readerOpenOriginal, systemImage: "arrow.up.right")
                        .font(bodyFontPreset.font(size: max(metadataFontSize, 13), relativeTo: .callout))
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .help(L10n.readerOpenOriginal)
            }
            .padding(.top, footerTopPadding)
        }
    }

    @ViewBuilder
    // `.textSelection(.enabled)` stand hier frueher an JEDEM einzelnen Text-Block.
    // Per Heap-Dump (heap <pid>) verifiziert: in Kombination mit dem wiederholten
    // Neu-Layout der Lazy-Stack beim Scrollen leakte das massenhaft AppKit-
    // Textfeld-Objekte (NSTextFieldBezelConfiguration u.a., ~1,9 Mio. Instanzen,
    // mehrere GB RAM). Deshalb komplett entfernt — der Artikeltitel bleibt ueber
    // readerHeader() separat auswaehlbar, da der nur einmal pro Artikel-Laden
    // entsteht statt bei jedem Scroll-Tick.
    private func contentBlock(_ block: ReaderContentBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                .fontWeight(bodyFontWeight)
                .lineSpacing(clampedLineSpacing)
        case .heading(let text):
            Text(text)
                .font(bodyFontPreset.font(
                    size: min(clampedBodyFontSize + 5, CGFloat(ReaderTypography.defaultTitleFontSize - 2)),
                    relativeTo: .title3,
                    weight: contentHeadingFontWeight
                ))
                .fontWeight(contentHeadingFontWeight)
                .lineSpacing(clampedLineSpacing)
        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 3)

                Text(text)
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineSpacing(clampedLineSpacing)
            }
            .padding(.vertical, 2)
        case .listItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "•")
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .lineSpacing(clampedLineSpacing)
            }
        case .image(let urlString):
            CachedRemoteImageView(url: URL(string: urlString), targetPixelSize: readerImageTargetPixelSize) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(height: 180)
            }
        }
    }

    // Artikel-Bilder aus dem Web koennen deutlich groesser sein als die Breite, in der
    // sie im Reader dargestellt werden (z. B. 6000px breite Fotos). Ohne Begrenzung
    // decodiert ImageCacheService jedes Bild in voller Aufloesung — bei bildreichen
    // Artikeln fuehrt das beim Scrollen zu massiver CPU-/Speicherlast bis hin zum
    // Einfrieren der App. `clampedContentWidth` ist die maximale Darstellungsbreite,
    // Faktor 2 deckt Retina-Displays ab.
    private var readerImageTargetPixelSize: CGSize {
        let retinaScale: CGFloat = 2
        let side = clampedContentWidth * retinaScale
        return CGSize(width: side, height: side)
    }

    private var readerSectionDivider: some View {
        Rectangle()
            .fill(.secondary.opacity(ReaderTypography.readerDividerOpacity))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private func shouldShowImageTextDivider(after index: Int, in blocks: [ReaderContentBlock]) -> Bool {
        guard blocks.indices.contains(index), isImageBlock(blocks[index]) else {
            return false
        }

        let nextIndex = blocks.index(after: index)
        guard blocks.indices.contains(nextIndex) else {
            return false
        }

        return !isImageBlock(blocks[nextIndex])
    }

    private func isImageBlock(_ block: ReaderContentBlock) -> Bool {
        if case .image = block {
            return true
        }

        return false
    }

    private var readerAppearancePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.readerAppearanceTitle)
                .font(.headline)

            Picker(L10n.readerTitleFontPicker, selection: $titleFontPresetRawValue) {
                ForEach(ReaderFontPreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)

            Toggle(L10n.readerTitleFontBoldToggle, isOn: $readerTitleFontIsBold)

            Picker(L10n.readerBodyFontPicker, selection: $bodyFontPresetRawValue) {
                ForEach(ReaderFontPreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)

            Toggle(L10n.readerBodyFontBoldToggle, isOn: $readerBodyFontIsBold)

            typographySlider(
                L10n.readerBodyFontSizeSlider,
                value: $readerBodyFontSize,
                range: ReaderTypography.bodyFontSizeRange,
                displayedValue: ReaderTypography.clampedBodyFontSize(readerBodyFontSize)
            )

            typographySlider(
                L10n.readerTitleLineSpacingSlider,
                value: $readerTitleLineSpacing,
                range: ReaderTypography.titleLineSpacingRange,
                displayedValue: ReaderTypography.clampedTitleLineSpacing(readerTitleLineSpacing)
            )

            typographySlider(
                L10n.readerLineSpacingSlider,
                value: $readerLineSpacing,
                range: ReaderTypography.lineSpacingRange,
                displayedValue: ReaderTypography.clampedLineSpacing(readerLineSpacing)
            )

            typographySlider(
                L10n.readerContentWidthSlider,
                value: $readerContentWidth,
                range: ReaderTypography.contentWidthRange,
                displayedValue: ReaderTypography.clampedContentWidth(readerContentWidth),
                step: ReaderTypography.contentWidthStep
            )

            Toggle(L10n.readerShowsArticleImagesToggle, isOn: $readerShowsArticleImages)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func typographySlider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        displayedValue: Double,
        step: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(displayedValue.formatted(.number.precision(.fractionLength(0))))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)

            Slider(value: value, in: range, step: step)
        }
    }

    private func openOriginal() {
        guard let originalURL else {
            return
        }

        ArticleOriginalBrowserLauncher.open(originalURL)
    }

    private func copyLink() {
        guard let link = state.snapshot?.link?.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.isEmpty
        else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

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

// Eigenstaendige View-Struct statt @ViewBuilder-Funktion: verhindert, dass
// SwiftUI diesen Teilbaum (inkl. WebContentView + .task(id:)) bei jedem
// Body-Durchlauf von SQLiteReaderView als "neue" Identitaet behandelt.
private struct ReaderModeContent: View {
    let articleID: String
    let database: FeedivoDatabase
    let state: SQLiteReaderState
    let readerDisplayMode: ReaderDisplayMode
    let articleInAppWebProfile: ArticleInAppWebProfile
    @Binding var webContentLoadFailed: Bool
    let webNavigationController: WebNavigationController
    let originalURL: URL?
    let clampedContentWidth: CGFloat
    let showsArticleImages: Bool
    let contentBlockSpacing: CGFloat
    let imageTextDividerSpacing: CGFloat
    let articleTopPadding: CGFloat
    let articleBottomPadding: CGFloat
    let readerHeader: (ArticleReaderSnapshot) -> AnyView
    let contentBlock: (ReaderContentBlock) -> AnyView
    let readerFooter: (ArticleReaderSnapshot) -> AnyView
    let readerSectionDivider: AnyView
    let shouldShowImageTextDivider: (Int, [ReaderContentBlock]) -> Bool

    // Bilder aus dem Artikeltext (separat von den Vorschaubildern der Artikelliste,
    // Feature 19.1) lassen sich hier ausblenden. Die Filterung passiert bewusst erst
    // beim Rendern statt beim Parsen in ReaderContentRenderer, damit contentBlocks
    // unabhängig vom Anzeige-Toggle bleibt.
    private var displayedContentBlocks: [ReaderContentBlock] {
        guard !showsArticleImages else {
            return state.preparedArticle.contentBlocks
        }

        return state.preparedArticle.contentBlocks.filter { block in
            if case .image = block {
                return false
            }

            return true
        }
    }

    var body: some View {
        Group {
            if readerDisplayMode == .web, let originalURL, !webContentLoadFailed {
                WebContentView(
                    url: originalURL,
                    inAppProfile: articleInAppWebProfile,
                    navigationController: webNavigationController,
                    onLoadFailure: {
                        webContentLoadFailed = true
                    }
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    // Bewusst KEIN LazyVStack: per Live-Sample (sample <pid>) belegt,
                    // dass SwiftUIs LazySubviewPlacements/_LazyLayoutViewCache nach
                    // laengerem Scrollen auf macOS 26.5.2 in eine echte Endlosschleife
                    // laeuft (2,5+ Minuten ununterbrochen ~100% CPU, kein Konvergieren)
                    // — reproduzierbar mit UND ohne .textSelection(.enabled), also
                    // unabhaengig vom Speicherleck-Fix. Artikel haben hier typischerweise
                    // nur ein paar Dutzend Bloecke — fuer diese Groessenordnung bringt Lazy-
                    // Laden ohnehin keinen Vorteil. Ein normales VStack rendert einmalig
                    // eager und vermeidet den kompletten Code-Pfad, in dem die Schleife
                    // nachweislich sitzt.
                    VStack(alignment: .leading, spacing: contentBlockSpacing) {
                        if let snapshot = state.snapshot {
                            readerHeader(snapshot)

                            ForEach(ReaderContentBlockEntry.entries(from: displayedContentBlocks)) { entry in
                                VStack(alignment: .leading, spacing: imageTextDividerSpacing) {
                                    contentBlock(entry.block)

                                    if shouldShowImageTextDivider(entry.index, displayedContentBlocks) {
                                        readerSectionDivider
                                    }
                                }
                            }

                            readerFooter(snapshot)
                        } else if state.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)
                        } else {
                            ContentUnavailableView(
                                "Artikel nicht gefunden",
                                systemImage: "doc.text.magnifyingglass",
                                description: Text(state.errorMessage ?? "Der Artikel ist nicht mehr in der lokalen Datenbank vorhanden.")
                            )
                        }
                    }
                    // KEIN .textSelection(.enabled) hier: per Heap-Dump verifiziert
                    // (heap <pid>), dass diese Kombination aus .textSelection(.enabled)
                    // und der bei jedem Scroll-Tick neu layoutenden LazyVStack auf
                    // dieser macOS-Version (26.5.2) massenhaft AppKit-Textfeld-Objekte
                    // (NSTextFieldBezelConfiguration, NSCompositeAppearance,
                    // NSConcreteAttributedString, ...) leakt — 1,9+ Millionen Instanzen
                    // bei einem 40-Block-Artikel, mehrere GB RAM. Weder pro-Block noch
                    // einmalig auf dem Container angewendet macht das sicher. Bis es
                    // einen Weg ohne Leck gibt, bleibt Body-Text hier nicht auswaehlbar;
                    // der Artikeltitel (readerHeader) ist davon nicht betroffen, da er
                    // nur einmal pro Artikel-Laden entsteht, nicht pro Scroll-Tick.
                    .frame(maxWidth: clampedContentWidth, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, articleTopPadding)
                    .padding(.bottom, articleBottomPadding)
                }
                // Nur die ScrollView bekommt pro Artikel eine neue Identitaet, damit
                // beim Wechsel wieder oben gestartet wird. Der uebergeordnete
                // SQLiteReaderView (und sein SQLiteReaderState) bleibt bewusst
                // erhalten — sonst wuerde snapshot bei jedem Wechsel neu auf nil
                // starten und der ProgressView-Flash zurueckkehren.
                .id(articleID)
            }
        }
        .task(id: articleID) {
            webContentLoadFailed = false
            state.load(articleID: articleID, database: database)
        }
        .onChange(of: readerDisplayMode) { _, newValue in
            if newValue == .web {
                webContentLoadFailed = false
            }
        }
    }
}
