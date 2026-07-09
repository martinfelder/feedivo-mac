import SwiftUI
import UniformTypeIdentifiers

struct OPMLImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme

    private let tableBodyHeight: CGFloat = 336

    let feedViewModel: FeedViewModel

    // Bestehende Ordnernamen aus SQLite — für das Folder-Dropdown im Import-
    // Sheet. Duplikat-Check läuft in `opmlImportPreviewRows` bereits SQLite-basiert.
    private var existingFolderNames: [String] {
        guard let feedivoDatabase else { return [] }
        return (try? FeedStore(database: feedivoDatabase).feeds())?
            .compactMap { $0.folderName?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    // Einziger OPML-State: Controller hält rows, Toggles, Picker, Import-Status etc.
    @State private var previewController = OPMLImportPreviewController(configuration: .importSheet)

    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(RuleDialogTheme(colorScheme: colorScheme).border)
                .frame(height: 1)
            content
            Rectangle()
                .fill(RuleDialogTheme(colorScheme: colorScheme).border)
                .frame(height: 1)
            footer
        }
        .background(RuleDialogTheme(colorScheme: colorScheme).bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 1080, height: 680)
        .overlay(dropOverlay)
        .fileImporter(
            isPresented: $previewController.isFileImporterPresented,
            allowedContentTypes: [.opml, .xml]
        ) { result in
            previewController.loadOPML(
                from: result,
                sqliteDatabase: feedivoDatabase,
                feedViewModel: feedViewModel
            )
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $previewController.isDropTargeted) { providers in
            previewController.handleDroppedFiles(
                providers,
                sqliteDatabase: feedivoDatabase,
                feedViewModel: feedViewModel
            )
        }
        .onChange(of: previewController.allowsDuplicates) {
            previewController.applyToggleSelectionToRows()
        }
        .onChange(of: previewController.allowsUnreachable) {
            previewController.applyToggleSelectionToRows()
        }
    }

    private var header: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.opmlImportTitle)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(theme.text)
                Text(L10n.opmlImportDescription)
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.text2)
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(statusColor.opacity(0.18)))
    }

    // View-Chrome: liest vom Controller, bleibt hier weil Darstellung.
    private var statusColor: Color {
        if previewController.unreachableCount > 0 {
            return .red
        }

        if previewController.duplicateCount > 0 {
            return .orange
        }

        if previewController.rows.isEmpty {
            return .secondary
        }

        return .green
    }

    private var statusText: String {
        if previewController.rows.isEmpty {
            return L10n.opmlImportStatusNoFile
        }

        var parts: [String] = []
        if previewController.duplicateCount > 0 {
            parts.append(String.localizedStringWithFormat(String(localized: "opml.import.status.duplicate"), previewController.duplicateCount))
        }
        if previewController.unreachableCount > 0 {
            parts.append(String.localizedStringWithFormat(String(localized: "opml.import.status.unreachable"), previewController.unreachableCount))
        }

        return parts.isEmpty ? L10n.opmlImportStatusReady : parts.joined(separator: " · ")
    }

    private var content: some View {
        VStack(spacing: 14) {
            filePicker
            toolbar
            feedTable

            if let resultMessage = previewController.resultMessage {
                Text(resultMessage)
                    .font(.callout)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if let errorMessage = previewController.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if previewController.isDropTargeted {
            let accent = RuleDialogTheme(colorScheme: colorScheme).accent

            RoundedRectangle(cornerRadius: 12)
                .stroke(accent, lineWidth: 3)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 26, weight: .semibold))
                        Text(L10n.opmlImportDropOverlayTitle)
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.opmlImportDropOverlayHint)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(accent)
                )
                .allowsHitTesting(false)
        }
    }

    private var filePicker: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        return HStack(spacing: 12) {
            Text("OPML")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(theme.accent.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(previewController.selectedFileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(previewController.sourceDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button(L10n.opmlImportChooseFile) {
                previewController.isFileImporterPresented = true
            }
            .buttonStyle(OPMLSecondaryButtonStyle(theme: theme))
            .disabled(previewController.isPreparingPreview)

            Button(L10n.opmlImportRemoveFile) {
                resetFile()
            }
            .buttonStyle(OPMLSecondaryButtonStyle(theme: theme))
            .disabled(previewController.rows.isEmpty && previewController.errorMessage == nil)
        }
        .padding(12)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.border)
        )
    }

    private var toolbar: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                Text(selectionSummaryText)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.border)
            )

            Spacer()

            Picker(L10n.opmlImportStatusLabel, selection: $previewController.statusFilter) {
                ForEach(OPMLImportStatusFilter.allCases) { filter in
                    Text(filter.localizedTitle).tag(filter)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 142)

            Button(L10n.opmlImportSelectAll) {
                previewController.selectAllImportableRows()
            }
            .buttonStyle(OPMLSecondaryButtonStyle(theme: theme))
            .disabled(previewController.rows.isEmpty)

            Button(L10n.opmlImportDeselectAll) {
                previewController.deselectVisibleRows()
            }
            .buttonStyle(OPMLSecondaryButtonStyle(theme: theme))
            .disabled(previewController.rows.isEmpty)

            Divider()
                .frame(height: 18)

            TextField(L10n.opmlImportNewFolder, text: $previewController.newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            Button(L10n.opmlImportCreateFolder) {
                previewController.createFolder()
            }
            .buttonStyle(OPMLSecondaryButtonStyle(theme: theme))
            .disabled(previewController.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var feedTable: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        return VStack(spacing: 0) {
            tableHeader

            ScrollView {
                LazyVStack(spacing: 0) {
                    if previewController.isPreparingPreview {
                        previewProgressRow
                    } else if previewController.rows.isEmpty {
                        emptyRow
                    } else if previewController.visibleRowIDs.isEmpty {
                        emptyFilterRow
                    } else {
                        ForEach($previewController.rows) { $row in
                            if previewController.visibleRowIDs.contains(row.id) {
                                OPMLImportFeedRow(
                                    row: $row,
                                    selectionOptions: previewController.selectionOptions,
                                    availableFolders: previewController.availableFolders(existingFolderNames: existingFolderNames),
                                    layout: .importSheet
                                )
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(height: tableBodyHeight)
        }
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(theme.border)
        )
    }

    private var tableHeader: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        return HStack(spacing: 10) {
            Text("")
                .frame(width: 34, alignment: .leading)
            Text(L10n.opmlImportTableHeaderFeed)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.opmlImportTableHeaderWebsite)
                .frame(width: 180, alignment: .leading)
            Text(L10n.opmlImportTableHeaderFolder)
                .frame(width: 154, alignment: .leading)
            Text(L10n.opmlImportTableHeaderStatus)
                .frame(width: 108, alignment: .leading)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(theme.text2)
        .textCase(.uppercase)
        .frame(height: 34)
        .padding(.horizontal, 12)
        .background(theme.card)
    }

    private var emptyRow: some View {
        centeredTableMessage(
            title: L10n.opmlImportEmptyTitle,
            subtitle: L10n.opmlImportEmptySubtitle
        )
    }

    private var emptyFilterRow: some View {
        centeredTableMessage(
            title: L10n.opmlImportEmptyFilterTitle,
            subtitle: L10n.opmlImportEmptyFilterSubtitle
        )
    }

    private var previewProgressRow: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(spacing: 5) {
                Text(L10n.opmlImportPreparing)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(previewController.previewProgressText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: tableBodyHeight, alignment: .center)
        .padding(.horizontal, 24)
    }

    private func centeredTableMessage(title: String, subtitle: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: tableBodyHeight, alignment: .center)
        .padding(.horizontal, 24)
    }

    private var footer: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        return HStack(spacing: 16) {
            Button {
                previewController.refreshAfterImport.toggle()
            } label: {
                HStack(spacing: 8) {
                    RuleDialogCheckbox(isOn: previewController.refreshAfterImport, theme: theme)
                    Text(L10n.opmlImportRefreshAfter)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text)
                }
            }
            .buttonStyle(.plain)

            Button {
                previewController.allowsDuplicates.toggle()
            } label: {
                HStack(spacing: 8) {
                    RuleDialogCheckbox(isOn: previewController.allowsDuplicates, theme: theme)
                    Text(L10n.opmlImportAllowDuplicates)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text)
                }
            }
            .buttonStyle(.plain)

            Button {
                previewController.allowsUnreachable.toggle()
            } label: {
                HStack(spacing: 8) {
                    RuleDialogCheckbox(isOn: previewController.allowsUnreachable, theme: theme)
                    Text(L10n.opmlImportAllowUnreachable)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(L10n.opmlImportCancel) {
                dismiss()
            }
            .buttonStyle(OPMLSecondaryButtonStyle(theme: theme))
            Button(importButtonTitle) {
                importSelectedFeeds()
            }
            .buttonStyle(OPMLPrimaryButtonStyle(theme: theme))
            .disabled(previewController.selectedImportRows.isEmpty || previewController.isPreparingPreview || feedViewModel.isLoading)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }

    private var importButtonTitle: String {
        String.localizedStringWithFormat(String(localized: "opml.import.button.import"),
                                         previewController.selectedImportRows.count)
    }

    // View-Chrome: Zusammenfassungstext bleibt in der View, liest vom Controller.
    private var selectionSummaryText: String {
        if previewController.statusFilter == .all {
            return String.localizedStringWithFormat(L10n.opmlImportSelectionAll,
                                                    previewController.selectedImportRows.count,
                                                    previewController.rows.count)
        }

        return String.localizedStringWithFormat(L10n.opmlImportSelectionVisible,
                                                 previewController.selectedImportRows.count,
                                                 previewController.visibleRowCount)
    }

    /// Setzt den Controller zurück. `selectedFileName` wird von `reset()` selbst
    /// auf `configuration.initialSelectedFileName` zurückgesetzt (siehe Controller).
    private func resetFile() {
        previewController.reset()
    }

    /// Importiert die ausgewählten Feeds. Bleibt in der View, weil die
    /// resultMessage hier pro View divergiert (andere Formatierung/Texte).
    private func importSelectedFeeds() {
        Task {
            do {
                previewController.errorMessage = nil
                previewController.resultMessage = nil
                let selectedRows = previewController.selectedImportRows
                let selectedFeeds = selectedRows.map(\.feed)
                let result = try await feedViewModel.importOPMLFeeds(
                    selectedFeeds,
                    allowsDuplicates: previewController.allowsDuplicates,
                    refreshAfterImport: previewController.refreshAfterImport,
                    refreshIntervalMinutes: backgroundRefreshIntervalMinutes,
                    sqliteDatabase: feedivoDatabase
                )
                let importedDuplicateCount = selectedRows.filter { $0.status == .duplicate }.count
                let duplicateText = importedDuplicateCount > 0
                    ? String.localizedStringWithFormat(L10n.opmlImportResultDuplicatesImported, importedDuplicateCount)
                    : String.localizedStringWithFormat(L10n.opmlImportResultDuplicatesSkipped, previewController.duplicateCount)
                let importedUnreachableCount = selectedRows.filter { $0.status == .unreachable }.count
                let unreachableText = importedUnreachableCount > 0
                    ? String.localizedStringWithFormat(L10n.opmlImportResultUnreachableImported, importedUnreachableCount)
                    : String.localizedStringWithFormat(L10n.opmlImportResultUnreachableSkipped, previewController.unreachableCount)
                let foldersText = String.localizedStringWithFormat(L10n.opmlImportResultFoldersUsed, previewController.folderCount)
                let refreshText = previewController.refreshAfterImport ? L10n.opmlImportResultRefreshOn : L10n.opmlImportResultRefreshOff
                let importedCountBaustein = String.localizedStringWithFormat(String(localized: "opml.export.feedCount"), result.imported)
                previewController.resultMessage = "\(L10n.opmlImportResultComplete): \(importedCountBaustein), \(duplicateText), \(unreachableText), \(foldersText). \(refreshText)"
            } catch {
                previewController.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct OPMLSecondaryButtonStyle: ButtonStyle {
    let theme: RuleDialogTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                (configuration.isPressed ? theme.card : theme.card2),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(theme.border)
            )
            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct OPMLPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let theme: RuleDialogTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                (isEnabled ? theme.accent : Color.secondary.opacity(0.45))
                    .opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .shadow(color: theme.accent.opacity(isEnabled ? 0.45 : 0), radius: 1.5, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
