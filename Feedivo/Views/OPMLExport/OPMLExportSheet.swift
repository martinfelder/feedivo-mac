import SwiftUI

struct OPMLExportSheet: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    let feeds: [Feed]
    let onClose: () -> Void

    @State private var includesFolders = true
    @State private var includesTags = true
    @State private var includesDescriptions = false
    @State private var isExporting = false

    /// P8: Feedliste einmalig beim Erstellen des Sheets cachen statt pro Render
    /// neu zu mappen (und jedes Mal einen `FeedViewModel` zu instanziieren).
    /// `opmlFeedsForExport` ist rein → static ohne Instanz.
    @State private var opmlFeeds: [OPMLFeed] = []

    /// P8: Das XML-Dokument wird erst beim Speichern generiert, nicht bei jedem
    /// Render. Vorher liefert `document` eine leere Hülle (Exporter ist dann
    /// ohnehin nicht sichtbar).
    @State private var exportDocument: OPMLDocument?

    private var options: OPMLExportOptions {
        OPMLExportOptions(
            includesFolders: includesFolders,
            includesTags: includesTags,
            includesDescriptions: includesDescriptions
        )
    }

    private var document: OPMLDocument {
        exportDocument ?? OPMLDocument(text: "")
    }

    init(feeds: [Feed], onClose: @escaping () -> Void) {
        self.feeds = feeds
        self.onClose = onClose
        _opmlFeeds = State(initialValue: FeedViewModel.opmlFeedsForExport(from: feeds))
    }

    /// SQLite-only Initializer für ContentView: keine SwiftData-`Feed`-Liste
    /// mehr. Die Export-Feeds werden beim Erscheinen des Sheets aus
    /// `FeedStore.opmlFeedsForExport()` geladen (siehe `.task`/`loadExportFeeds`).
    init(onClose: @escaping () -> Void) {
        self.feeds = []
        self.onClose = onClose
        _opmlFeeds = State(initialValue: [])
    }

    init(opmlFeeds: [OPMLFeed], onClose: @escaping () -> Void) {
        self.feeds = []
        self.onClose = onClose
        _opmlFeeds = State(initialValue: opmlFeeds)
    }

    /// Dynamisch aus den geladenen OPML-Feeds — initially 0, nach SQLite-Load
    /// befüllt. Header und Save-Button reagieren so auf den asynchronen Load.
    private var feedCount: Int {
        opmlFeeds.count
    }

    private var folderCount: Int {
        Set(opmlFeeds.compactMap { trimmed($0.folderName) }).count
    }

    private var tagCount: Int {
        Set(opmlFeeds.flatMap(\.tagNames).compactMap(trimmed)).count
    }

    private var descriptionCount: Int {
        opmlFeeds.compactMap { trimmed($0.description) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            bodyContent
            footer
        }
        .frame(width: 720)
        .background(.background)
        .task {
            loadExportFeeds()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: .opml,
            defaultFilename: OPMLService.defaultExportFilename()
        ) { _ in
            onClose()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.opmlExportTitle)
                    .font(.headline)

                Text(L10n.opmlExportDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text(L10n.opmlExportFeedCount(feedCount))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.green.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var bodyContent: some View {
        HStack(alignment: .top, spacing: 16) {
            optionList
            summaryPanel
        }
        .padding(18)
    }

    private var optionList: some View {
        VStack(spacing: 0) {
            OPMLExportOptionRow(
                title: L10n.opmlExportFeedsAndTitles,
                description: L10n.opmlExportFeedsAndTitlesDescription,
                isOn: .constant(true),
                isDisabled: true
            )

            Divider()
                .padding(.leading, 44)

            OPMLExportOptionRow(
                title: L10n.opmlExportFolders,
                description: L10n.opmlExportFoldersDescription,
                isOn: $includesFolders
            )

            Divider()
                .padding(.leading, 44)

            OPMLExportOptionRow(
                title: L10n.opmlExportTags,
                description: L10n.opmlExportTagsDescription,
                isOn: $includesTags
            )

            Divider()
                .padding(.leading, 44)

            OPMLExportOptionRow(
                title: L10n.opmlExportDescriptions,
                description: L10n.opmlExportDescriptionsDescription,
                isOn: $includesDescriptions
            )
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.opmlExportSummaryTitle)
                .font(.caption)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                summaryRow(label: L10n.opmlExportSummaryFeeds, value: "\(feedCount)")
                summaryRow(label: L10n.opmlExportSummaryFolders, value: includesFolders ? L10n.opmlExportFolderCount(folderCount) : L10n.commonOff)
                summaryRow(label: L10n.opmlExportSummaryTags, value: includesTags ? L10n.opmlExportTagCount(tagCount) : L10n.commonOff)
                summaryRow(label: L10n.opmlExportSummaryDescriptions, value: includesDescriptions ? L10n.opmlExportDescriptionCount(descriptionCount) : L10n.commonOff)
            }

            Text(OPMLService.defaultExportFilename())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        }
        .frame(width: 240)
        .padding(13)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(L10n.opmlExportFooterNote)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(L10n.commonCancel) {
                onClose()
            }

            Button(L10n.opmlExportSaveButton) {
                // P8: XML erst hier beim Speichern generieren (mit aktuellen
                // Optionen), nicht bei jedem Render.
                exportDocument = OPMLDocument(text: OPMLService.exportFeeds(opmlFeeds, options: options))
                isExporting = true
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(feedCount == 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func trimmed(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty
        else {
            return nil
        }

        return trimmedValue
    }

    private func loadExportFeeds() {
        // SQLite-only Pfad (ContentView): keine SwiftData-Feeds übergeben →
        // direkt aus `FeedStore.opmlFeedsForExport()` laden. Bereits vorbelegte
        // opmlFeeds (SettingsView via init(opmlFeeds:)) werden nicht überschrieben.
        if feeds.isEmpty && opmlFeeds.isEmpty {
            if let feedivoDatabase {
                opmlFeeds = (try? FeedStore(database: feedivoDatabase).opmlFeedsForExport()) ?? []
            }
            return
        }

        let swiftDataFeeds = FeedViewModel.opmlFeedsForExport(from: feeds)
        guard !feeds.isEmpty else {
            return
        }

        guard let feedivoDatabase else {
            opmlFeeds = swiftDataFeeds
            return
        }

        do {
            let descriptionsByURL = Dictionary(
                uniqueKeysWithValues: swiftDataFeeds.map { ($0.xmlURL, $0.description) }
            )
            opmlFeeds = try FeedStore(database: feedivoDatabase)
                .opmlFeedsForExport()
                .map { feed in
                    OPMLFeed(
                        title: feed.title,
                        xmlURL: feed.xmlURL,
                        htmlURL: feed.htmlURL,
                        folderName: feed.folderName,
                        description: descriptionsByURL[feed.xmlURL] ?? feed.description,
                        tagNames: feed.tagNames
                    )
                }
        } catch {
            opmlFeeds = swiftDataFeeds
        }
    }
}

private struct OPMLExportOptionRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var isDisabled = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(isDisabled)
                .frame(width: 18, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(minHeight: 62)
    }
}
