import AppKit
import PDFKit
import SwiftUI
import WebKit

struct SQLiteReaderView: View {
    @Environment(\.feedivoDatabase) private var database
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var isTagAssignmentPopoverPresented = false
    @State private var articleExportRequest: ArticleExportRequest?
    @State private var webContentLoadFailed = false
    @State private var webNavigationController = WebNavigationController()
    // Haelt die unsichtbare WKWebView fuer den nativen Druck-Modus fest, bis der
    // Druckvorgang abgeschlossen ist (siehe printCurrentArticle()/ArticlePrintCoordinator
    // unten) — sonst wuerde ARC sie vorzeitig freigeben, bevor WKNavigationDelegate.
    // didFinish feuert.
    @State private var offscreenPrintWebView: WKWebView?
    @State private var articlePrintCoordinator: ArticlePrintCoordinator?
    // Erzwingt einen kompletten Neuaufbau der Toolbar-Inhaltsgruppe bei jedem
    // Vollbild-Wechsel (siehe FullScreenTransitionObserver) — Fix für einen
    // Toolbar-Icon-Überlapp-Bug, der nach Fenster-Schliessen/App-Neustart/
    // Vollbild reproduzierbar auftrat (Nutzer-Report 2026-07-11).
    @State private var toolbarRebuildGeneration = 0

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

    @AppStorage(ReaderToolbarLayout.storageKey)
    private var readerToolbarLayoutRawValue = ReaderToolbarLayout().rawValue

    // Der Artikelinfo-Inspector (ArticleMetadataInspectorView) mutiert Tags UND Ordner
    // direkt in SQLite (Tags -> SidebarBadgeInvalidation, Ordner -> SQLiteDataInvalidation)
    // und bumpt anschliessend den jeweiligen Zaehler, aktualisiert dabei aber nur seine
    // eigene lokale Snapshot-Kopie — nicht den `state.snapshot` dieser View, aus dem
    // readerArticleMetadata sowohl Tag-Chips als auch Ordnername im Artikel-Header
    // rendert. Ohne diese Beobachtung blieben Aenderungen im Reader unsichtbar, bis ein
    // Artikelwechsel `state.load(...)` erneut ausloest (Nutzer-Report 2026-07-12).
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0

    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0

    private var shortcutOverrides: KeyboardShortcutOverrides {
        KeyboardShortcutOverrides.resolved(from: shortcutOverridesRawValue)
    }

    private var readerToolbarLayout: ReaderToolbarLayout {
        ReaderToolbarLayout.resolved(from: readerToolbarLayoutRawValue)
    }

    private func bumpToolbarRebuildGeneration() {
        toolbarRebuildGeneration += 1
    }

    // TEMP-DEBUG-Fund (2026-07-17, automatischer Feed-Sprung): benutzte
    // vorher state.snapshot?.id (den ZULETZT geladenen Artikel) statt
    // self.articleID (den AKTUELL ausgewaehlten). Beim Feed-Sprung feuert
    // .onChange(of: sqliteStatusVersion) (ausgeloest durch das Markieren-
    // als-gelesen des Zielartikels) fast zeitgleich mit dem regulaeren
    // .task(id: articleID)-Ladevorgang fuer den neuen Artikel — state.snapshot
    // zeigt zu diesem Zeitpunkt noch auf den ALTEN Artikel, wurde also ein
    // force:true-Reload fuer den falschen (alten) Artikel ausgeloest, der je
    // nach Timing den korrekten Ladevorgang ueberholen und ueberschreiben
    // konnte ("mal geht's, mal nicht"). self.articleID ist immer die
    // korrekte, aktuell ausgewaehlte ID.
    private func reloadCurrentArticleSnapshot() {
        guard let database, let articleID else {
            return
        }

        state.load(articleID: articleID, database: database, force: true)
    }

    // Als eigene @ToolbarContentBuilder-Property ausgelagert statt inline in
    // body: Der komplette Toolbar-Inhalt (~15 Controls) innerhalb der langen
    // body-Modifier-Kette liess den Swift-Type-Checker irreführende "cannot
    // find X in scope"-Fehler für jede NEUE Referenz am Ende der Kette werfen
    // (verifiziert: sogar ein simpler Methodenaufruf war betroffen — kein
    // Problem mit `toolbarRebuildGeneration` selbst, sondern mit der
    // Gesamtkomplexität der body-Expression). Extraktion in eine separate,
    // eigenständig typgeprüfte Property behebt das (Standard-Workaround für
    // "expression too complex" bei grossen SwiftUI-Toolbars).
    @ToolbarContentBuilder
    private var readerToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Group {
                Spacer()

                ForEach(readerToolbarLayout.visibleOrderedItems) { item in
                    toolbarItemView(for: item)
                }
            }
            .id(toolbarRebuildGeneration)
        }
    }

    // Ehemals 6 fest verdrahtete ControlGroup-Buendel + Picker + 2 Buttons in
    // fester Reihenfolge (siehe Git-Historie). Seit Feature "Toolbar anpassen"
    // (2026-07-18) rendert readerToolbarContent stattdessen dynamisch ueber
    // readerToolbarLayout.visibleOrderedItems — die alte ControlGroup-Buendelung
    // (z. B. Stern+Archivieren+Gelesen als optische Einheit) entfaellt bewusst,
    // da feste Buendelgrenzen bei freier Umsortierung keinen Sinn mehr ergeben.
    // Jeder einzelne Case unten entspricht 1:1 dem vorherigen Button-/Picker-Code
    // (Icon, .help(...), .disabled(...), .customizableKeyboardShortcut(...)
    // unveraendert) — nur die ControlGroup-Klammerung wurde entfernt.
    @ViewBuilder
    private func toolbarItemView(for item: ReaderToolbarItem) -> some View {
        switch item {
        case .search:
            Button {
                openWindow(id: ArticleSearchWindowView.windowID)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help(L10n.articleSearchCommand)

        case .openOriginal:
            Button {
                openOriginal()
            } label: {
                Image(systemName: "safari")
            }
            .help(L10n.articleOpenOriginalCommand)
            .disabled(originalURL == nil)

        case .createRule:
            Button {
                if let snapshot = state.snapshot {
                    onCreateRule(snapshot)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help(L10n.articleCreateRuleCommand)
            .disabled(state.snapshot == nil)

        case .star:
            Button {
                if let database {
                    state.toggleStarred(database: database)
                }
            } label: {
                Image(systemName: state.snapshot?.isStarred == true ? "star.fill" : "star")
            }
            .help(state.snapshot?.isStarred == true ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
            .disabled(state.snapshot == nil)

        case .archive:
            Button {
                if let database {
                    state.toggleArchived(database: database)
                }
            } label: {
                Image(systemName: state.snapshot?.isArchived == true ? "archivebox.fill" : "archivebox")
            }
            .help(state.snapshot?.isArchived == true ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand)
            .disabled(state.snapshot == nil)

        case .toggleRead:
            Button {
                if let database {
                    state.toggleRead(database: database)
                }
            } label: {
                Image(systemName: state.snapshot?.isRead == true ? "circle" : "circle.fill")
            }
            .help(state.snapshot?.isRead == true ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead)
            .disabled(state.snapshot == nil)

        case .copyLink:
            Button {
                copyLink()
            } label: {
                Image(systemName: "link")
            }
            .help(L10n.articleCopyLinkCommand)
            .disabled(originalURL == nil)

        case .export:
            Button {
                requestExportArticle()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help(L10n.articleExportCommand)
            .disabled(state.snapshot == nil)

        case .webBack:
            Button {
                webNavigationController.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .help(L10n.readerWebBackCommand)
            .customizableKeyboardShortcut(.readerWebBack, overrides: shortcutOverrides)
            .disabled(readerDisplayMode != .web || !webNavigationController.canGoBack)

        case .webForward:
            Button {
                webNavigationController.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .help(L10n.readerWebForwardCommand)
            .customizableKeyboardShortcut(.readerWebForward, overrides: shortcutOverrides)
            .disabled(readerDisplayMode != .web || !webNavigationController.canGoForward)

        case .print:
            Button {
                printCurrentArticle()
            } label: {
                Image(systemName: "printer")
            }
            .help(L10n.articlePrintCommand)
            .customizableKeyboardShortcut(.articlePrint, overrides: shortcutOverrides)
            .disabled(state.snapshot == nil)

        case .displayModePicker:
            Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
                ForEach(ReaderDisplayMode.allCases) { mode in
                    Text(mode.titleKey)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .help(L10n.readerDisplayModeToggleHelp)
            .disabled(originalURL == nil)

        case .appearance:
            Button {
                isAppearancePopoverPresented.toggle()
            } label: {
                Image(systemName: "textformat")
            }
            .help(L10n.readerAppearanceButton)
            .popover(isPresented: $isAppearancePopoverPresented, arrowEdge: .bottom) {
                readerAppearancePopover
            }

        case .inspector:
            Button {
                isMetadataInspectorPresented.toggle()
            } label: {
                Label(L10n.readerInspectorButton, systemImage: "sidebar.right")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .symbolVariant(isMetadataInspectorPresented ? .fill : .none)
            .help(L10n.readerInspectorButton)
        }
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
                    L10n.dbUnavailableTitle,
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(L10n.dbUnavailableDescription)
                )
            } else {
                ContentUnavailableView(
                    L10n.contentNoArticleSelectedTitle,
                    systemImage: "doc.text",
                    description: Text(L10n.contentNoArticleSelectedDescription)
                )
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
        .navigationTitle(state.snapshot?.title ?? "")
        .inspector(isPresented: $isMetadataInspectorPresented) {
            if let snapshot = state.snapshot {
                ArticleMetadataInspectorView(snapshot: snapshot, close: {
                    isMetadataInspectorPresented = false
                })
                .inspectorColumnWidth(min: 280, ideal: 318, max: 360)
            } else {
                Text(L10n.readerInspectorNoArticleLoaded)
                    .padding()
            }
        }
        .onChange(of: state.snapshot) { _, snapshot in
            onSnapshotChange(snapshot)
        }
        .onChange(of: directTagVersion) { _, _ in
            reloadCurrentArticleSnapshot()
        }
        .onChange(of: sqliteStatusVersion) { _, _ in
            reloadCurrentArticleSnapshot()
        }
        .onDisappear {
            onSnapshotChange(nil)
        }
        .sheet(item: $articleExportRequest) { request in
            ArticleExportSheet(request: request) {
                articleExportRequest = nil
            }
        }
        // TEMP-DEBUG-Erkenntnis (2026-07-11): Das Aufsplitten dieser Toolbar in
        // mehrere unabhängige ToolbarItem/ToolbarItemGroup-Geschwister (erster
        // Fix-Versuch) wurde per NSToolbar-Item-Frame-Logging als FALSCH
        // verifiziert — zwei der neu entstandenen Items renderten seither
        // dauerhaft mit identischem Frame übereinander. Zurück zur einzelnen
        // ToolbarItemGroup; stattdessen wird die gesamte Toolbar-Inhaltsgruppe
        // gezielt bei jedem Vollbild-Wechsel per `.id(toolbarRebuildGeneration)`
        // komplett neu aufgebaut (siehe `FullScreenTransitionObserver` unten) —
        // das erzwingt eine frische NSToolbarItem-Messung genau an der Stelle,
        // die laut Nutzer-Report reproduzierbar betroffen ist (Fenster
        // verkleinern → App beenden → neu starten → verkleinertes Fenster →
        // Vollbild).
        .background(FullScreenTransitionObserver(generation: $toolbarRebuildGeneration))
        .toolbar {
            readerToolbarContent
        }
        // Vor/Zurück-ControlGroup (readerToolbarContent) wechselt hier zwischen
        // aktiviert/deaktiviert (.disabled(readerDisplayMode != .web || ...)) —
        // ihre effektive Breite ändert sich dabei, ohne dass ein Fenster-Resize
        // passiert. Toolbar gezielt neu aufbauen (Nutzer-Report 2026-07-11:
        // Navigationspfeile für die Webansicht weiterhin überlappend). Korrekt
        // hier in SQLiteReaderViews eigener body-Kette verankert, NICHT im
        // gleichnamigen .onChange(of: readerDisplayMode) von ReaderModeContent
        // weiter unten — das ist eine andere Struct ohne Zugriff auf
        // toolbarRebuildGeneration (Ursache der vorherigen "cannot find in
        // scope"-Fehler).
        .onChange(of: readerDisplayModeRawValue) { _, _ in
            bumpToolbarRebuildGeneration()
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

    // Effektiver Web-Modus, wie er tatsaechlich gerendert wird (siehe ReaderModeContent.body
    // weiter unten) — reines readerDisplayMode == .web reicht nicht: bei fehlendem
    // originalURL oder einem Web-Ladefehler zeigt der Reader die native Ansicht, obwohl der
    // gespeicherte (globale) Modus weiterhin .web ist. printCurrentArticle() muss dieselbe
    // Bedingung nutzen wie das Rendering selbst, sonst druckt es im Zweifel die falsche oder
    // eine leere Ansicht (Whole-Branch-Review-Fund, Feature 25.1).
    private var isShowingWebContent: Bool {
        readerDisplayMode == .web && originalURL != nil && !webContentLoadFailed
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

    private func readerArticleMetadata(_ snapshot: ArticleReaderSnapshot) -> some View {
        let folderName = FeedFolderOrganizer.normalizedFolderName(snapshot.folderName)
        return FlowLayout(spacing: 8) {
            if let folderName {
                readerFolderChip(folderName)
            }

            ForEach(snapshot.tags) { tag in
                readerTagChip(tag)
            }

            readerAddTagButton(snapshot)
        }
        .padding(.top, 2)
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

    private func readerAddTagButton(_ snapshot: ArticleReaderSnapshot) -> some View {
        Button {
            isTagAssignmentPopoverPresented.toggle()
        } label: {
            Image(systemName: "plus")
                .font(interfaceTextSize.font(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(width: readerMetadataChipHeight, height: readerMetadataChipHeight)
        .background(.secondary.opacity(0.08), in: Circle())
        .overlay {
            Circle()
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
        .help(L10n.articleAssignTagCommand)
        .popover(isPresented: $isTagAssignmentPopoverPresented) {
            ArticleTagAssignmentView(articleID: snapshot.id, snapshotTags: snapshot.tags)
                .padding(12)
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
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
        case .paragraph(let runs):
            Text(runs.attributedString(colorScheme: colorScheme))
                .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                .fontWeight(bodyFontWeight)
                .lineSpacing(clampedLineSpacing)
        case .heading(let runs):
            Text(runs.attributedString(colorScheme: colorScheme))
                .font(bodyFontPreset.font(
                    size: min(clampedBodyFontSize + 5, CGFloat(ReaderTypography.defaultTitleFontSize - 2)),
                    relativeTo: .title3,
                    weight: contentHeadingFontWeight
                ))
                .fontWeight(contentHeadingFontWeight)
                .lineSpacing(clampedLineSpacing)
        case .quote(let runs):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 3)

                Text(runs.attributedString(colorScheme: colorScheme))
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineSpacing(clampedLineSpacing)
            }
            .padding(.vertical, 2)
        case .listItem(let runs):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "•")
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .foregroundStyle(.secondary)

                Text(runs.attributedString(colorScheme: colorScheme))
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

    // Druckinhalt folgt der aktuellen Reader-Ansicht (kein Umschalter im Druckdialog,
    // siehe Design-Spec 2026-07-17-artikel-drucken-design.md). Live-Bug-Fund 2026-07-17
    // (lldb-Backtrace): WKWebView.printOperation(with:) stuerzt in AppKits eigener
    // Seitenaufteilungs-Validierung ab ("The NSPrintOperation view's frame was not
    // initialized properly before knowsPageRange: returned") — ein seit Jahren bekanntes,
    // ungeloestes WKWebView/AppKit-Problem, reproduzierbar unabhaengig von WKWebView-
    // Instanz, Fenster-Zuordnung und NSPrintInfo.shared vs. frisch konstruiert. printDocument:
    // (Responder-Chain) ist auf WKWebView auf dieser macOS-Version zudem gar nicht
    // implementiert. Stattdessen: WKWebView.createPDF(...) (Apples separate, dafuer
    // gedachte PDF-Export-API) erzeugt zuverlaessig echte PDF-Daten; ein ganz normaler,
    // laengst bewaehrter PDFKit-Druckvorgang (NSPrintOperation(view: PDFView)) zeigt
    // dafuer den Druckdialog — komplett unabhaengig von WKWebViews kaputter eigener
    // Druck-Integration.
    private func printCurrentArticle() {
        if isShowingWebContent {
            guard let webView = webNavigationController.webView else {
                return
            }

            generatePDF(from: webView) { data in
                presentPrintDialog(forPDFData: data)
            }
        } else {
            guard let snapshot = state.snapshot else {
                return
            }

            let html = ArticlePDFExportRenderer.html(
                for: ArticleExportSnapshot(sqliteSnapshot: snapshot, tagNames: snapshot.tags.map(\.name)),
                options: ArticleExportOptions(format: .html, includesMetadata: true),
                style: .default,
                assets: []
            )

            // 816x1056pt entspricht ungefaehr US Letter bei 96dpi — ausreichend breit,
            // damit die Export-CSS (max-width: 680px, siehe ArticlePDFExportStyle.default)
            // beim Layout nicht kollabiert, obwohl die WebView nie sichtbar wird. Die Hoehe
            // ist nur ein Startwert — generatePDF(from:) ermittelt die tatsaechliche
            // Inhaltshoehe per JavaScript, bevor createPDF(...) aufgerufen wird.
            let printWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 816, height: 1056))
            let coordinator = ArticlePrintCoordinator { finishedWebView in
                generatePDF(from: finishedWebView) { data in
                    presentPrintDialog(forPDFData: data)
                    offscreenPrintWebView = nil
                    articlePrintCoordinator = nil
                }
            }
            printWebView.navigationDelegate = coordinator
            offscreenPrintWebView = printWebView
            articlePrintCoordinator = coordinator
            printWebView.loadHTMLString(html, baseURL: nil)
        }
    }

    // Live-Bug-Fund 2026-07-17: WKPDFConfiguration() erfasst standardmaessig (rect == nil)
    // nur den aktuell sichtbaren Ausschnitt der WebView, nicht das gesamte scrollbare
    // Dokument. Ein einzelner, auf die volle Inhaltshoehe vergroesserter rect behebt zwar
    // das Abschneiden, erzeugt aber nur EINE einzige, ueberlange PDF-Seite — beim Drucken
    // wird diese eine Seite dann auf ein normales Blatt herunterskaliert, wodurch der Text
    // bei laengeren Artikeln praktisch unlesbar klein wird. createPDF(...) paginiert nicht
    // automatisch in mehrere Standard-Seiten; das muss selbst erledigt werden: der Inhalt
    // wird in seitenhohe Abschnitte zerlegt, jeder Abschnitt einzeln per createPDF(...)
    // erfasst und zu einem mehrseitigen PDFDocument zusammengefuegt.
    private func generatePDF(from webView: WKWebView, completion: @escaping (Data) -> Void) {
        webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
            let contentHeight = (result as? NSNumber)?.doubleValue ?? Double(webView.bounds.height)
            let pageHeight = Double(webView.bounds.height)
            let pageWidth = webView.bounds.width

            // Jede Seite bekommt bewusst dieselbe volle pageHeight (auch die letzte, ueber
            // das tatsaechliche Inhaltsende hinaus) — eine kuerzere letzte Seite haette eine
            // abweichende PDF-Seitengroesse zur Folge, was beim Druck zu einer falsch
            // ausgerichteten/anders skalierten letzten Seite fuehrte (Live-Bug-Fund
            // 2026-07-17). Ungenutzter Leerraum am Ende der letzten Seite ist unauffaellig
            // und dem Verhalten normaler paginierter Dokumente entsprechend.
            var pageRects: [CGRect] = []
            var y = 0.0
            while y < contentHeight {
                pageRects.append(CGRect(x: 0, y: y, width: pageWidth, height: pageHeight))
                y += pageHeight
            }

            appendPage(
                from: webView,
                rects: pageRects,
                index: 0,
                into: PDFDocument(),
                completion: completion
            )
        }
    }

    private func appendPage(
        from webView: WKWebView,
        rects: [CGRect],
        index: Int,
        into document: PDFDocument,
        completion: @escaping (Data) -> Void
    ) {
        guard index < rects.count else {
            completion(document.dataRepresentation() ?? Data())
            return
        }

        let configuration = WKPDFConfiguration()
        configuration.rect = rects[index]

        webView.createPDF(configuration: configuration) { result in
            if case .success(let pageData) = result,
               let singlePagePDF = PDFDocument(data: pageData),
               let page = singlePagePDF.page(at: 0) {
                document.insert(page, at: document.pageCount)
            }

            appendPage(from: webView, rects: rects, index: index + 1, into: document, completion: completion)
        }
    }

    // Live-Bug-Fund 2026-07-17: NSPrintOperation(view: pdfView) behandelt die PDFView wie
    // eine gewoehnliche NSView und druckt dadurch nur das, was in ihrem eigenen Rahmen
    // sichtbar ist (Seite 1) — derselbe Fallstrick wie bei WKWebView.printOperation(with:).
    // PDFDocument.printOperation(for:scalingMode:autoRotate:) ist die dafuer vorgesehene
    // PDFKit-API, die die Seitenaufteilung des Dokuments selbst korrekt handhabt.
    private func presentPrintDialog(forPDFData data: Data) {
        guard let pdfDocument = PDFDocument(data: data),
              let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let operation = pdfDocument.printOperation(for: NSPrintInfo(), scalingMode: .pageScaleToFit, autoRotate: true)
        else {
            return
        }

        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
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
                                L10n.readerArticleNotFoundTitle,
                                systemImage: "doc.text.magnifyingglass",
                                description: Text(state.errorMessage ?? L10n.readerArticleNotFoundDescription)
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

/// Beobachtet Vollbild-Übergänge des umschliessenden NSWindow und erhöht
/// `generation` bei jedem Eintritt/Austritt aus dem Vollbildmodus. Genutzt von
/// `SQLiteReaderView`, um die Toolbar-Inhaltsgruppe per `.id(generation)`
/// gezielt neu aufzubauen — Fix für einen Icon-Überlapp-Bug in der Reader-
/// Toolbar, der reproduzierbar nach Fenster-verkleinern → App-Neustart →
/// Vollbild auftrat (Nutzer-Report 2026-07-11). Rein unsichtbares Hilfsview
/// (keine eigene Darstellung), analog zu anderen AppKit-Bridges im Projekt
/// (`WebContentView`, `ShortcutRecorderView`).
private struct FullScreenTransitionObserver: NSViewRepresentable {
    @Binding var generation: Int

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.observe(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.observe(window: nsView.window)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(generation: $generation)
    }

    final class Coordinator {
        private let generation: Binding<Int>
        private weak var observedWindow: NSWindow?
        private var tokens: [NSObjectProtocol] = []

        init(generation: Binding<Int>) {
            self.generation = generation
        }

        func observe(window: NSWindow?) {
            guard let window, window !== observedWindow else { return }
            removeObservers()
            observedWindow = window

            // "Vollbild" per grünem Knopf-Klick ist auf diesem System KEIN
            // echter macOS-Fullscreen-Space-Wechsel (didEnterFullScreenNotification
            // feuerte in der Verifikation nie), sondern ein normales Zoomen/
            // Maximieren des Fensters — das löst didResizeNotification aus.
            // Alle drei Notifications bleiben registriert, falls der Nutzer
            // später doch echten Vollbildmodus (Menü/Strg+Cmd+F) nutzt.
            for name in [
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didResizeNotification
            ] {
                let token = NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [generation] _ in
                    generation.wrappedValue += 1
                }
                tokens.append(token)
            }
        }

        private func removeObservers() {
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens.removeAll()
        }

        deinit {
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}

/// Laedt die native Reader-Export-HTML in einer unsichtbaren WKWebView und erzeugt daraus
/// per createPDF(...) echte PDF-Daten, sobald das Laden abgeschlossen ist (siehe Kommentar
/// bei printCurrentArticle() zur Begruendung dieses Wegs statt WKWebView.printOperation).
/// SQLiteReaderView haelt die zugehoerige WKWebView per @State fest, bis didFinish
/// feuert (sonst wuerde ARC sie vorzeitig freigeben, analog zum bestehenden
/// WebContentView.Coordinator-Muster).
private final class ArticlePrintCoordinator: NSObject, WKNavigationDelegate {
    private let onFinished: (WKWebView) -> Void

    init(onFinished: @escaping (WKWebView) -> Void) {
        self.onFinished = onFinished
        super.init()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinished(webView)
    }
}
