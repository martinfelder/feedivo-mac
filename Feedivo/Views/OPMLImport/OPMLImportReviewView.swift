import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct OPMLImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let tableBodyHeight: CGFloat = 336

    let feeds: [Feed]
    let feedViewModel: FeedViewModel

    // Einziger OPML-State: Controller hält rows, Toggles, Picker, Import-Status etc.
    @State private var previewController = OPMLImportPreviewController(configuration: .importSheet)

    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey)
    private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

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
            isPresented: $previewController.isFileImporterPresented,
            allowedContentTypes: [.opml, .xml]
        ) { result in
            previewController.loadOPML(from: result, existingFeeds: feeds, feedViewModel: feedViewModel)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $previewController.isDropTargeted) { providers in
            previewController.handleDroppedFiles(providers, existingFeeds: feeds, feedViewModel: feedViewModel)
        }
        .onChange(of: previewController.allowsDuplicates) {
            for index in previewController.rows.indices where previewController.rows[index].status == .duplicate {
                previewController.rows[index].isSelected = previewController.allowsDuplicates
            }
        }
        .onChange(of: previewController.allowsUnreachable) {
            for index in previewController.rows.indices where previewController.rows[index].status == .unreachable {
                previewController.rows[index].isSelected = previewController.allowsUnreachable
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
            return "Keine Datei"
        }

        var parts: [String] = []
        if previewController.duplicateCount > 0 {
            parts.append("\(previewController.duplicateCount) Duplikat\(previewController.duplicateCount == 1 ? "" : "e")")
        }
        if previewController.unreachableCount > 0 {
            parts.append("\(previewController.unreachableCount) nicht erreichbar")
        }

        return parts.isEmpty ? "Bereit" : parts.joined(separator: " · ")
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

            Button("Datei auswählen...") {
                previewController.isFileImporterPresented = true
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            .disabled(previewController.isPreparingPreview)

            Button("Entfernen") {
                resetFile()
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            .disabled(previewController.rows.isEmpty && previewController.errorMessage == nil)
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

            Picker("Status", selection: $previewController.statusFilter) {
                ForEach(OPMLImportStatusFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 142)

            Button("Alle auswählen") {
                previewController.selectAllImportableRows()
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            .disabled(previewController.rows.isEmpty)

            Button("Alle abwählen") {
                previewController.deselectVisibleRows()
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            .disabled(previewController.rows.isEmpty)

            Divider()
                .frame(height: 18)

            TextField("Neuer Ordner", text: $previewController.newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            Button("Ordner erstellen") {
                previewController.createFolder()
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            .disabled(previewController.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var feedTable: some View {
        VStack(spacing: 0) {
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
                                    availableFolders: previewController.availableFolders(existingFeeds: feeds),
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
        HStack(spacing: 16) {
            Toggle("Feeds nach Import direkt aktualisieren", isOn: $previewController.refreshAfterImport)
                .toggleStyle(.checkbox)
            Toggle("Duplikate importieren", isOn: $previewController.allowsDuplicates)
                .toggleStyle(.checkbox)
            Toggle("Nicht erreichbare Feeds importieren", isOn: $previewController.allowsUnreachable)
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
            .disabled(previewController.selectedImportRows.isEmpty || previewController.isPreparingPreview || feedViewModel.isLoading)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
    }

    private var importButtonTitle: String {
        let count = previewController.selectedImportRows.count
        return count == 1 ? "1 Feed importieren" : "\(count) Feeds importieren"
    }

    // View-Chrome: Zusammenfassungstext bleibt in der View, liest vom Controller.
    private var selectionSummaryText: String {
        if previewController.statusFilter == .all {
            return "Ausgewählt: \(previewController.selectedImportRows.count) von \(previewController.rows.count)"
        }

        return "Ausgewählt: \(previewController.selectedImportRows.count) von \(previewController.visibleRowCount) sichtbar"
    }

    /// Setzt den Controller zurück und zeigt den Leer-String für die Datei-Auswahl an.
    private func resetFile() {
        previewController.reset()
        previewController.selectedFileName = "Keine OPML-Datei ausgewählt"
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
                    existingFeeds: feeds,
                    allowsDuplicates: previewController.allowsDuplicates,
                    refreshAfterImport: previewController.refreshAfterImport,
                    refreshIntervalMinutes: backgroundRefreshIntervalMinutes,
                    context: modelContext
                )
                let importedDuplicateCount = selectedRows.filter { $0.status == .duplicate }.count
                let duplicateText = importedDuplicateCount > 0
                    ? "\(importedDuplicateCount) Duplikate bewusst importiert"
                    : "\(previewController.duplicateCount) Duplikate angezeigt und übersprungen"
                let importedUnreachableCount = selectedRows.filter { $0.status == .unreachable }.count
                let unreachableText = importedUnreachableCount > 0
                    ? "\(importedUnreachableCount) nicht erreichbare Feeds bewusst importiert"
                    : "\(previewController.unreachableCount) nicht erreichbare Feeds angezeigt und übersprungen"
                previewController.resultMessage = "Import abgeschlossen: \(result.imported) Feeds importiert, \(duplicateText), \(unreachableText), \(previewController.folderCount) Ordner verwendet. \(previewController.refreshAfterImport ? "Direktes Aktualisieren ist aktiv." : "Aktualisierung erfolgt später manuell.")"
            } catch {
                previewController.errorMessage = error.localizedDescription
            }
        }
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