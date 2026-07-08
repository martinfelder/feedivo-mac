import SwiftUI

struct OPMLExportSheet: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme

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

    /// SQLite-only Initializer für ContentView: Die Export-Feeds werden beim
    /// Erscheinen des Sheets aus `FeedStore.opmlFeedsForExport()` geladen
    /// (siehe `.task`/`loadExportFeeds`).
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        _opmlFeeds = State(initialValue: [])
    }

    init(opmlFeeds: [OPMLFeed], onClose: @escaping () -> Void) {
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

    var body: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            header(theme: theme)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            bodyContent(theme: theme)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            footer(theme: theme)
        }
        .frame(width: 660)
        .background(theme.bg)
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

    private func header(theme: RuleDialogTheme) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.opmlExportTitle)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(theme.text)

                Text(L10n.opmlExportDescription)
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 430, alignment: .leading)
            }

            Spacer(minLength: 0)

            Text(L10n.opmlExportFeedCount(feedCount))
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(RuleDialogTheme.thenBadgeText)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Color(hex: 0x34C759).opacity(0.14), in: Capsule())
                .fixedSize()
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private func bodyContent(theme: RuleDialogTheme) -> some View {
        HStack(alignment: .top, spacing: 20) {
            optionList(theme: theme)
                .frame(maxWidth: .infinity, alignment: .leading)

            summaryPanel(theme: theme)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }

    private func optionList(theme: RuleDialogTheme) -> some View {
        VStack(spacing: 0) {
            OPMLExportOptionRow(
                title: L10n.opmlExportFeedsAndTitles,
                description: L10n.opmlExportFeedsAndTitlesDescription,
                isOn: true,
                isLocked: true,
                showTopBorder: false,
                theme: theme,
                onToggle: {}
            )

            OPMLExportOptionRow(
                title: L10n.opmlExportFolders,
                description: L10n.opmlExportFoldersDescription,
                isOn: includesFolders,
                isLocked: false,
                showTopBorder: true,
                theme: theme,
                onToggle: { includesFolders.toggle() }
            )

            OPMLExportOptionRow(
                title: L10n.opmlExportTags,
                description: L10n.opmlExportTagsDescription,
                isOn: includesTags,
                isLocked: false,
                showTopBorder: true,
                theme: theme,
                onToggle: { includesTags.toggle() }
            )

            OPMLExportOptionRow(
                title: L10n.opmlExportDescriptions,
                description: L10n.opmlExportDescriptionsDescription,
                isOn: includesDescriptions,
                isLocked: false,
                showTopBorder: true,
                theme: theme,
                onToggle: { includesDescriptions.toggle() }
            )
        }
    }

    private func summaryPanel(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.opmlExportSummaryTitle)
                .font(.system(size: 14, weight: .bold))
                .tracking(-0.1)
                .foregroundStyle(theme.text)

            VStack(spacing: 0) {
                summaryRow(theme: theme, label: L10n.opmlExportSummaryFeeds, value: "\(feedCount)", showTopBorder: false)
                summaryRow(theme: theme, label: L10n.opmlExportSummaryFolders, value: includesFolders ? L10n.opmlExportFolderCount(folderCount) : L10n.commonOff, showTopBorder: true)
                summaryRow(theme: theme, label: L10n.opmlExportSummaryTags, value: includesTags ? L10n.opmlExportTagCount(tagCount) : L10n.commonOff, showTopBorder: true)
                summaryRow(theme: theme, label: L10n.opmlExportSummaryDescriptions, value: includesDescriptions ? L10n.commonOn : L10n.commonOff, showTopBorder: true)
            }
            .padding(.top, 12)

            Text(OPMLService.defaultExportFilename())
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(theme.text2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
                .padding(.top, 14)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func summaryRow(theme: RuleDialogTheme, label: String, value: String, showTopBorder: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme.text2)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.text)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            if showTopBorder {
                Rectangle().fill(theme.border).frame(height: 1)
            }
        }
    }

    private func footer(theme: RuleDialogTheme) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(L10n.opmlExportFooterNote)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.text2)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button {
                    onClose()
                } label: {
                    Text(L10n.commonCancel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.card2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(theme.border, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                }
                .buttonStyle(.plain)

                Button {
                    // P8: XML erst hier beim Speichern generieren (mit aktuellen
                    // Optionen), nicht bei jedem Render.
                    exportDocument = OPMLDocument(text: OPMLService.exportFeeds(opmlFeeds, options: options))
                    isExporting = true
                } label: {
                    Text(L10n.opmlExportSaveButton)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.accent)
                        )
                        .shadow(color: theme.accent.opacity(0.45), radius: 1.5, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(feedCount == 0)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
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
        // Bereits vorbelegte opmlFeeds (SettingsView via init(opmlFeeds:))
        // werden nicht überschrieben.
        guard opmlFeeds.isEmpty else {
            return
        }

        if let feedivoDatabase {
            opmlFeeds = (try? FeedStore(database: feedivoDatabase).opmlFeedsForExport()) ?? []
        }
    }
}

// MARK: - Options-Zeile mit Checkbox (die erste Option "Feed-URLs und Titel"
// ist per Design immer aktiv und lässt sich nicht abwählen).

private struct OPMLExportOptionRow: View {
    let title: String
    let description: String
    let isOn: Bool
    let isLocked: Bool
    let showTopBorder: Bool
    let theme: RuleDialogTheme
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 13) {
                OPMLExportCheckbox(isOn: isOn, isLocked: isLocked, theme: theme)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-0.1)
                        .foregroundStyle(theme.text)

                    Text(description)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                if showTopBorder {
                    Rectangle().fill(theme.border).frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }
}

// MARK: - Checkbox mit gesperrtem Zustand (gedämpfte Akzentfarbe, kein Toggle)

private struct OPMLExportCheckbox: View {
    let isOn: Bool
    let isLocked: Bool
    let theme: RuleDialogTheme

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(borderColor, lineWidth: isLocked ? 0 : 1)
            )
            .overlay {
                if isOn {
                    Text("✓")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            .shadow(color: shadowColor, radius: isOn && !isLocked ? 1 : 0.5, x: 0, y: 1)
            .padding(.top, 1)
            .animation(.easeInOut(duration: 0.12), value: isOn)
    }

    private var fillColor: Color {
        guard isOn else {
            return theme.input
        }

        return isLocked ? theme.accent.opacity(0.4) : theme.accent
    }

    private var borderColor: Color {
        isOn && !isLocked ? theme.accent : theme.border
    }

    private var shadowColor: Color {
        isOn && !isLocked ? theme.accent.opacity(0.35) : .black.opacity(0.04)
    }
}
