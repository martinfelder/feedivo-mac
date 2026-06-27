import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct OPMLImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let tableBodyHeight: CGFloat = 336

    let feeds: [Feed]
    let feedViewModel: FeedViewModel

    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    @State private var selectedFileName = "Keine OPML-Datei ausgewählt"
    @State private var fileDescription = "Wähle eine .opml- oder .xml-Datei, danach erscheint hier die Import-Vorschau."
    @State private var previewProgressText = "Noch keine Datei ausgewählt."
    @State private var rows: [OPMLImportPreviewRow] = []
    @State private var isPreparingPreview = false
    @State private var allowsDuplicates = false
    @State private var allowsUnreachable = false
    @State private var refreshAfterImport = true
    @State private var newFolderName = ""
    @State private var customFolders: [String] = []
    @State private var statusFilter: OPMLImportStatusFilter = .all
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

    private var selectedImportRows: [OPMLImportPreviewRow] {
        rows.filter { row in
            guard row.isSelected else {
                return false
            }

            return selectionOptions.canImport(row.status)
        }
    }

    private var selectionOptions: OPMLImportSelectionOptions {
        OPMLImportSelectionOptions(
            allowsDuplicates: allowsDuplicates,
            allowsUnreachable: allowsUnreachable
        )
    }

    private var duplicateCount: Int {
        rows.filter { $0.status == .duplicate }.count
    }

    private var unreachableCount: Int {
        rows.filter { $0.status == .unreachable }.count
    }

    private var folderCount: Int {
        Set(selectedImportRows.map { trimmedFolderName($0.feed.folderName) ?? "Ohne Ordner" }).count
    }

    private var availableFolders: [String] {
        let existingFolderNames = feeds.compactMap { trimmedFolderName($0.folderName) }
        let previewFolderNames = rows.compactMap { trimmedFolderName($0.feed.folderName) }
        return Array(Set(existingFolderNames + previewFolderNames + customFolders))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var visibleRowIDs: Set<OPMLImportPreviewRow.ID> {
        Set(statusFilter.filteredRows(from: rows).map(\.id))
    }

    private var visibleRowCount: Int {
        visibleRowIDs.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 1080, height: 680)
        .overlay(dropOverlay)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.opml, .xml]
        ) { result in
            loadOPML(from: result)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDroppedFiles(providers)
        }
        .onChange(of: allowsDuplicates) {
            for index in rows.indices where rows[index].status == .duplicate {
                rows[index].isSelected = allowsDuplicates
            }
        }
        .onChange(of: allowsUnreachable) {
            for index in rows.indices where rows[index].status == .unreachable {
                rows[index].isSelected = allowsUnreachable
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Feeds aus OPML importieren")
                    .font(.system(size: 18, weight: .semibold))
                Text("Prüfe die erkannten Feeds, passe Ordner an und entscheide, ob Feedivo direkt aktualisieren soll.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 17)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.58),
                    Color(nsColor: .controlBackgroundColor).opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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

    private var statusColor: Color {
        if unreachableCount > 0 {
            return .red
        }

        if duplicateCount > 0 {
            return .orange
        }

        if rows.isEmpty {
            return .secondary
        }

        return .green
    }

    private var statusText: String {
        if rows.isEmpty {
            return "Keine Datei"
        }

        var parts: [String] = []
        if duplicateCount > 0 {
            parts.append("\(duplicateCount) Duplikat\(duplicateCount == 1 ? "" : "e")")
        }
        if unreachableCount > 0 {
            parts.append("\(unreachableCount) nicht erreichbar")
        }

        return parts.isEmpty ? "Bereit" : parts.joined(separator: " · ")
    }

    private var content: some View {
        VStack(spacing: 14) {
            filePicker
            toolbar
            feedTable

            if let resultMessage {
                Text(resultMessage)
                    .font(.callout)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if let errorMessage {
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
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, lineWidth: 3)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 26, weight: .semibold))
                        Text("OPML-Datei hier ablegen")
                            .font(.system(size: 15, weight: .semibold))
                        Text(".opml und .xml werden unterstützt")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.accentColor)
                )
                .allowsHitTesting(false)
        }
    }

    private var filePicker: some View {
        HStack(spacing: 12) {
            Text("OPML")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.blue.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedFileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button("Datei auswählen...") {
                isFileImporterPresented = true
            }
            .buttonStyle(OPMLSecondaryButtonStyle())

            Button("Entfernen") {
                resetFile()
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            .disabled(rows.isEmpty && errorMessage == nil)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.74),
                    Color(nsColor: .controlBackgroundColor).opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18))
        )
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
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
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.16))
            )

            Spacer()

            Picker("Status", selection: $statusFilter) {
                ForEach(OPMLImportStatusFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 142)

            Button("Alle auswählen") {
                selectAllImportableRows()
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            .disabled(rows.isEmpty)

            Button("Alle abwählen") {
                deselectVisibleRows()
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            .disabled(rows.isEmpty)

            Divider()
                .frame(height: 18)

            TextField("Neuer Ordner", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            Button("Ordner erstellen") {
                createFolder()
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var feedTable: some View {
        VStack(spacing: 0) {
            tableHeader

            ScrollView {
                LazyVStack(spacing: 0) {
                    if isPreparingPreview {
                        previewProgressRow
                    } else if rows.isEmpty {
                        emptyRow
                    } else if visibleRowIDs.isEmpty {
                        emptyFilterRow
                    } else {
                        ForEach($rows) { $row in
                            if visibleRowIDs.contains(row.id) {
                                OPMLImportFeedRow(
                                    row: $row,
                                    selectionOptions: selectionOptions,
                                    availableFolders: availableFolders,
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
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.secondary.opacity(0.18))
        )
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Text("")
                .frame(width: 34, alignment: .leading)
            Text("Feed")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Website")
                .frame(width: 180, alignment: .leading)
            Text("Ordner")
                .frame(width: 154, alignment: .leading)
            Text("Status")
                .frame(width: 108, alignment: .leading)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .frame(height: 34)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyRow: some View {
        centeredTableMessage(
            title: "Noch keine Datei ausgewählt.",
            subtitle: "Wähle eine OPML-Datei, danach erscheint hier die Import-Vorschau."
        )
    }

    private var emptyFilterRow: some View {
        centeredTableMessage(
            title: "Keine Feeds für diesen Status.",
            subtitle: "Ändere den Statusfilter, um wieder mehr Feeds zu sehen."
        )
    }

    private var previewProgressRow: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(spacing: 5) {
                Text("Import-Vorschau wird vorbereitet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(previewProgressText)
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
        HStack(spacing: 16) {
            Toggle("Feeds nach Import direkt aktualisieren", isOn: $refreshAfterImport)
                .toggleStyle(.checkbox)
            Toggle("Duplikate importieren", isOn: $allowsDuplicates)
                .toggleStyle(.checkbox)
            Toggle("Nicht erreichbare Feeds importieren", isOn: $allowsUnreachable)
                .toggleStyle(.checkbox)

            Spacer()

            Button("Abbrechen") {
                dismiss()
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            Button(importButtonTitle) {
                importSelectedFeeds()
            }
            .buttonStyle(OPMLPrimaryButtonStyle())
            .disabled(selectedImportRows.isEmpty || isPreparingPreview || feedViewModel.isLoading)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
    }

    private var importButtonTitle: String {
        let count = selectedImportRows.count
        return count == 1 ? "1 Feed importieren" : "\(count) Feeds importieren"
    }

    private var selectionSummaryText: String {
        if statusFilter == .all {
            return "Ausgewählt: \(selectedImportRows.count) von \(rows.count)"
        }

        return "Ausgewählt: \(selectedImportRows.count) von \(visibleRowCount) sichtbar"
    }

    private func loadOPML(from result: Result<URL, Error>) {
        Task {
            do {
                let url = try result.get()
                let canAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if canAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                selectedFileName = url.lastPathComponent
                fileDescription = "Datei wird gelesen..."
                previewProgressText = "OPML-Datei wird gelesen und vorbereitet."
                errorMessage = nil
                resultMessage = nil
                rows = []
                isPreparingPreview = true

                let data = try Data(contentsOf: url)
                let opmlFeeds = try OPMLService.parseFeeds(from: data)
                fileDescription = "\(opmlFeeds.count) Feeds erkannt. Feed-Adressen werden geprüft..."
                previewProgressText = "\(opmlFeeds.count) Feeds erkannt. Prüfung startet..."
                rows = await feedViewModel.opmlImportPreviewRows(
                    for: opmlFeeds,
                    existingFeeds: feeds,
                    onProgress: { progress in
                        previewProgressText = progress.displayText
                        fileDescription = progress.displayText
                    }
                )
                fileDescription = "\(rows.count) Feeds erkannt · \(Set(rows.map { trimmedFolderName($0.feed.folderName) ?? "Ohne Ordner" }).count) Ordner · \(url.lastPathComponent)"
                previewProgressText = "Prüfung abgeschlossen."
                isPreparingPreview = false
            } catch {
                isPreparingPreview = false
                rows = []
                errorMessage = error.localizedDescription
                fileDescription = "Die Datei konnte nicht gelesen werden."
                previewProgressText = "Die Datei konnte nicht gelesen werden."
            }
        }
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            DispatchQueue.main.async {
                if let error {
                    errorMessage = error.localizedDescription
                    return
                }

                guard let url = OPMLImportDroppedFile.url(from: item),
                      OPMLImportDroppedFile.isSupported(url)
                else {
                    errorMessage = "Bitte eine OPML- oder XML-Datei ablegen."
                    return
                }

                loadOPML(from: .success(url))
            }
        }

        return true
    }

    private func importSelectedFeeds() {
        Task {
            do {
                errorMessage = nil
                resultMessage = nil
                let selectedFeeds = selectedImportRows.map(\.feed)
                let result = try await feedViewModel.importOPMLFeeds(
                    selectedFeeds,
                    existingFeeds: feeds,
                    allowsDuplicates: allowsDuplicates,
                    refreshAfterImport: refreshAfterImport,
                    refreshIntervalMinutes: backgroundRefreshIntervalMinutes,
                    context: modelContext
                )
                let importedDuplicateCount = selectedImportRows.filter { $0.status == .duplicate }.count
                let duplicateText = importedDuplicateCount > 0
                    ? "\(importedDuplicateCount) Duplikate bewusst importiert"
                    : "\(duplicateCount) Duplikate angezeigt und übersprungen"
                let importedUnreachableCount = selectedImportRows.filter { $0.status == .unreachable }.count
                let unreachableText = importedUnreachableCount > 0
                    ? "\(importedUnreachableCount) nicht erreichbare Feeds bewusst importiert"
                    : "\(unreachableCount) nicht erreichbare Feeds angezeigt und übersprungen"
                resultMessage = "Import abgeschlossen: \(result.imported) Feeds importiert, \(duplicateText), \(unreachableText), \(folderCount) Ordner verwendet. \(refreshAfterImport ? "Direktes Aktualisieren ist aktiv." : "Aktualisierung erfolgt später manuell.")"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func selectAllImportableRows() {
        for index in rows.indices {
            guard visibleRowIDs.contains(rows[index].id) else {
                continue
            }

            let status = rows[index].status
            rows[index].isSelected = selectionOptions.canImport(status)
        }
    }

    private func deselectVisibleRows() {
        for index in rows.indices where visibleRowIDs.contains(rows[index].id) {
            rows[index].isSelected = false
        }
    }

    private func resetFile() {
        rows = []
        selectedFileName = "Keine OPML-Datei ausgewählt"
        fileDescription = "Wähle eine .opml- oder .xml-Datei, danach erscheint hier die Import-Vorschau."
        previewProgressText = "Noch keine Datei ausgewählt."
        errorMessage = nil
        resultMessage = nil
        allowsDuplicates = false
        allowsUnreachable = false
        statusFilter = .all
    }

    private func createFolder() {
        let folderName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderName.isEmpty else {
            return
        }

        if !customFolders.contains(where: { $0.caseInsensitiveCompare(folderName) == .orderedSame }) {
            customFolders.append(folderName)
        }
        newFolderName = ""
    }

    private func trimmedFolderName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }

        return trimmed
    }
}

private struct OPMLSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.white.opacity(configuration.isPressed ? 0.62 : 0.9), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.18))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct OPMLPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                (isEnabled ? Color.accentColor : Color.secondary.opacity(0.45))
                    .opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
