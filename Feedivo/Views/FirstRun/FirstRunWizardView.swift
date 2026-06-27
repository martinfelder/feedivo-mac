import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct FirstRunWizardView: View {
    enum Step {
        case welcome
        case addFeed
        case importOPML
        case review
        case defaults
        case finish
    }

    @Environment(\.modelContext) private var modelContext
    @AppStorage("markArticleReadOnSelection") private var markArticleReadOnSelection = true
    @AppStorage(BackgroundRefreshSettings.isEnabledKey) private var isBackgroundRefreshEnabled = false
    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey) private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

    let feeds: [Feed]
    let feedViewModel: FeedViewModel
    let onSkip: () -> Void
    let onComplete: () -> Void

    @State private var step: Step = .welcome
    @State private var inputStep: Step = .addFeed
    @State private var feedURLString = ""
    @State private var selectedFileName = "Keine OPML-Datei ausgewählt"
    @State private var sourceDescription = "Wähle aus, wie du deine ersten Feeds hinzufügen möchtest."
    @State private var previewProgressText = "Noch keine Feeds geprüft."
    @State private var rows: [OPMLImportPreviewRow] = []
    @State private var isPreparingPreview = false
    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    @State private var allowsDuplicates = false
    @State private var allowsUnreachable = false
    @State private var refreshAfterImport = true
    @State private var statusFilter: OPMLImportStatusFilter = .all
    @State private var newFolderName = ""
    @State private var customFolders: [String] = []
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var completionSummary: FirstRunCompletionSummary?

    private var tableBodyHeight: CGFloat {
        usesCompactEmptyImportPreview ? 170 : 280
    }

    private var usesCompactEmptyImportPreview: Bool {
        step == .importOPML && rows.isEmpty && !isPreparingPreview
    }

    private var selectionOptions: OPMLImportSelectionOptions {
        OPMLImportSelectionOptions(
            allowsDuplicates: allowsDuplicates,
            allowsUnreachable: allowsUnreachable
        )
    }

    private var selectedImportRows: [OPMLImportPreviewRow] {
        rows.filter { $0.isSelected && selectionOptions.canImport($0.status) }
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

    private var selectedCountText: String {
        "Ausgewählt: \(selectedImportRows.count) von \(rows.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar

            HStack(spacing: 0) {
                stepRail

                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        stepContent
                    }
                    footer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 980, height: 680)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.70),
                    Color(nsColor: .controlBackgroundColor).opacity(0.76)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.72))
        )
        .shadow(color: .black.opacity(0.16), radius: 34, y: 20)
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
        .interactiveDismissDisabled()
    }

    private var titlebar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                FirstRunTrafficDot(color: Color(red: 1.0, green: 0.38, blue: 0.35))
                FirstRunTrafficDot(color: Color(red: 1.0, green: 0.74, blue: 0.18))
                FirstRunTrafficDot(color: Color(red: 0.16, green: 0.78, blue: 0.25))
            }

            Text("Feedivo einrichten")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.trailing, 57)
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.14))
                .frame(height: 1)
        }
    }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(stepItems) { item in
                FirstRunStepRow(
                    index: item.index,
                    title: item.title,
                    subtitle: item.subtitle,
                    isActive: item.step == step
                )
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(width: 230)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 1)
        }
    }

    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(stepTitle)
                    .font(.system(size: 28, weight: .bold))
                    .lineSpacing(0)
                Text(stepLead)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.top, 8)
            }

            Group {
                switch step {
                case .welcome:
                    welcomeStep
                case .addFeed:
                    addFeedStep
                case .importOPML:
                    importOPMLStep
                case .review:
                    reviewStep
                case .defaults:
                    defaultsStep
                case .finish:
                    finishStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 34)
        .padding(.top, 30)
        .padding(.bottom, 18)
    }

    private var stepTitle: String {
        switch step {
        case .welcome:
            "Willkommen in Feedivo."
        case .addFeed:
            "Feed hinzufügen."
        case .importOPML:
            "OPML importieren."
        case .review:
            "Auswahl prüfen."
        case .defaults:
            "Start-Einstellungen wählen."
        case .finish:
            "Feedivo ist bereit."
        }
    }

    private var stepLead: String {
        switch step {
        case .welcome:
            "Wähle, wie du starten möchtest. Du kannst einen einzelnen Feed hinzufügen, viele Feeds aus einer OPML-Datei übernehmen oder Feedivo erst einmal leer öffnen."
        case .addFeed:
            "Gib die Adresse eines RSS- oder Atom-Feeds ein. Feedivo prüft die Quelle, zeigt den Status und lässt dich direkt einen Ordner zuweisen."
        case .importOPML:
            "Lege eine OPML- oder XML-Datei ab oder wähle sie aus. Danach siehst du alle gefundenen Feeds, Ordner, Duplikate und nicht erreichbare Quellen, bevor etwas gespeichert wird."
        case .review:
            "Kontrolliere die vorbereitete Auswahl. Die vollständige Feed-Liste kannst du bei Bedarf noch einmal öffnen und ändern."
        case .defaults:
            "Lege die wichtigsten Startwerte fest. Diese Einstellungen kannst du später jederzeit in den Einstellungen ändern."
        case .finish:
            "Prüfe die Zusammenfassung des Imports. Feedivo öffnet sich erst, wenn du aktiv auf Starten klickst."
        }
    }

    private var stepItems: [FirstRunStepItem] {
        [
            FirstRunStepItem(index: 1, step: .welcome, title: "Start", subtitle: "Was möchtest du tun?"),
            FirstRunStepItem(index: 2, step: .addFeed, title: "Feed", subtitle: "Adresse prüfen"),
            FirstRunStepItem(index: 3, step: .importOPML, title: "OPML", subtitle: "Datei einlesen"),
            FirstRunStepItem(index: 4, step: .review, title: "Prüfen", subtitle: "Auswahl bestätigen"),
            FirstRunStepItem(index: 5, step: .defaults, title: "Einstellungen", subtitle: "Lesen und Refresh"),
            FirstRunStepItem(index: 6, step: .finish, title: "Fertig", subtitle: "Direkt loslegen")
        ]
    }

    private var welcomeStep: some View {
        HStack(spacing: 14) {
            FirstRunChoiceCard(
                iconName: "plus.circle.fill",
                title: "Feed hinzufügen",
                subtitle: "Eine RSS-Adresse prüfen, optional einem Ordner zuweisen und importieren."
            ) {
                resetPreview()
                inputStep = .addFeed
                step = .addFeed
            }

            FirstRunChoiceCard(
                iconName: "tray.and.arrow.down.fill",
                title: "OPML importieren",
                subtitle: "Viele Feeds und vorhandene Ordner aus einem anderen RSS-Reader übernehmen."
            ) {
                resetPreview()
                inputStep = .importOPML
                step = .importOPML
            }

            FirstRunChoiceCard(
                iconName: "clock.fill",
                title: "Später einrichten",
                subtitle: "Feedivo ohne Feeds öffnen. Du kannst später jederzeit neue Feeds hinzufügen."
            ) {
                onSkip()
            }
        }
        .padding(.top, 28)
    }

    private var addFeedStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                TextField("https://example.com/feed.xml", text: $feedURLString)
                    .textFieldStyle(.roundedBorder)
                    .frame(height: 38)
                    .disabled(isPreparingPreview)

                Button("Feed prüfen") {
                    prepareSingleFeedPreview()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(feedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPreparingPreview)
            }
            .padding(.top, 26)

            importPreviewArea
            errorBox
        }
    }

    private var importOPMLStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            opmlSourceControl
                .padding(.top, 26)

            importPreviewArea
            errorBox
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            reviewSummaryCard
            optionToggles
            resultBox
            errorBox
        }
        .padding(.top, 22)
    }

    private var importPreviewArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !rows.isEmpty {
                reviewToolbar
            }

            feedTable
        }
    }

    private var opmlImportOptions: some View {
        HStack(spacing: 18) {
            Toggle("Duplikate importieren", isOn: $allowsDuplicates)
                .toggleStyle(.checkbox)

            Toggle("Nicht erreichbare importieren", isOn: $allowsUnreachable)
                .toggleStyle(.checkbox)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .disabled(isPreparingPreview)
    }

    @ViewBuilder
    private var opmlSourceControl: some View {
        if rows.isEmpty && !isPreparingPreview {
            opmlDropZone
        } else {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedFileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(sourceDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                Button("Andere OPML wählen") {
                    isFileImporterPresented = true
                }
                .disabled(isPreparingPreview)
            }
            .padding(10)
            .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.secondary.opacity(0.16))
            )
        }
    }

    private var opmlDropZone: some View {
        Button {
            isFileImporterPresented = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 22, weight: .semibold))
                Text("OPML oder XML hier ablegen")
                    .font(.system(size: 14, weight: .semibold))
                Text("oder Datei auswählen. Feedivo zeigt dir danach zuerst eine Vorschau.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color(red: 0.94, green: 0.97, blue: 1.0).opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.18, green: 0.44, blue: 0.78).opacity(0.42), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }

    private var defaultsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                FirstRunSettingsLine(
                    title: "Artikel beim Öffnen als gelesen markieren",
                    subtitle: "Wenn du einen Artikel auswählst, verschwindet er automatisch aus Ungelesen."
                ) {
                    Toggle("", isOn: $markArticleReadOnSelection)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                FirstRunSettingsLine(
                    title: "Automatisch aktualisieren",
                    subtitle: "Feedivo prüft deine Feeds regelmäßig, solange die App laufen darf."
                ) {
                    Toggle("", isOn: $isBackgroundRefreshEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                FirstRunSettingsLine(
                    title: "Refresh-Intervall",
                    subtitle: "Gibt an, wie oft Feedivo nach neuen Artikeln suchen soll."
                ) {
                    refreshIntervalPicker
                }
            }
            .padding(.top, 28)

            Text(importSummaryText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            resultBox
            errorBox
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            finishSummaryCard
            resultBox
            errorBox
        }
        .padding(.top, 30)
    }

    private var refreshIntervalPicker: some View {
        Picker("Refresh-Intervall", selection: $backgroundRefreshIntervalMinutes) {
            ForEach(BackgroundRefreshSettings.allowedIntervalMinutes, id: \.self) { interval in
                Text(intervalTitle(interval)).tag(interval)
            }
        }
        .disabled(!isBackgroundRefreshEnabled)
        .frame(width: 280, alignment: .leading)
    }

    private var reviewToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Statusfilter", selection: $statusFilter) {
                    ForEach(OPMLImportStatusFilter.allCases) { filter in
                        Text(filterButtonTitle(filter)).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160, alignment: .leading)

                Text(previewSummaryText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }

            HStack(spacing: 8) {
                Button("Alle auswählen") {
                    selectAllImportableRows()
                }
                .disabled(rows.isEmpty || isPreparingPreview)

                Button("Alle abwählen") {
                    deselectVisibleRows()
                }
                .disabled(rows.isEmpty || isPreparingPreview)

                TextField("Neuer Ordner", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
                    .disabled(isPreparingPreview)

                Button("Ordner erstellen") {
                    createFolder()
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPreparingPreview)
            }
        }
    }

    private var previewSummaryText: String {
        "\(rows.count) Feeds geprüft · \(duplicateCount) Duplikate · \(unreachableCount) nicht erreichbar · \(selectedImportRows.count) ausgewählt"
    }

    private var reviewSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Import-Zusammenfassung")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Diese Feeds werden gespeichert, wenn du fortfährst. Über „Auswahl bearbeiten“ kommst du zurück zur Liste.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button("Auswahl bearbeiten") {
                    step = inputStep
                }
                .buttonStyle(.link)
                .disabled(isPreparingPreview || feedViewModel.isLoading)
            }

            LazyVGrid(columns: summaryMetricColumns, spacing: 10) {
                reviewSummaryMetric(value: "\(selectedImportRows.count)", label: "ausgewählte Feeds")
                reviewSummaryMetric(value: "\(folderCount)", label: "Ordner")
                reviewSummaryMetric(value: "\(duplicateCount)", label: "Duplikate erkannt")
                reviewSummaryMetric(value: "\(unreachableCount)", label: "nicht erreichbar")
            }
        }
        .padding(16)
        .frame(maxWidth: 680, alignment: .leading)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.16))
        )
    }

    private func reviewSummaryMetric(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 30, alignment: .bottom)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .center)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }

    private var summaryMetricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10), count: 4)
    }

    @ViewBuilder
    private var finishSummaryCard: some View {
        if let completionSummary {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: completionSummary.hasProblems ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(completionSummary.hasProblems ? .orange : Color.accentColor)
                        .frame(width: 42, height: 42)
                        .background(
                            (completionSummary.hasProblems ? Color.orange : Color.accentColor).opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 9)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(completionSummary.hasProblems ? "Import abgeschlossen mit Hinweisen" : "Import abgeschlossen")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Die ausgewählten Feeds wurden gespeichert. Hinweise zeigen dir, was noch Aufmerksamkeit braucht.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: summaryMetricColumns, spacing: 10) {
                    reviewSummaryMetric(value: "\(completionSummary.importedFeeds)", label: "Feeds importiert")
                    reviewSummaryMetric(value: "\(completionSummary.folderCount)", label: "Ordner angelegt/verwendet")
                    reviewSummaryMetric(value: "\(completionSummary.importedDuplicates)", label: "Duplikate importiert")
                    reviewSummaryMetric(value: "\(completionSummary.importedUnreachable)", label: "nicht erreichbare importiert")
                }

                if !completionSummary.problemMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hinweise")
                            .font(.system(size: 13, weight: .semibold))

                        ForEach(completionSummary.problemMessages, id: \.self) { message in
                            Label(message, systemImage: "exclamationmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.22))
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .leading)
            .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.16))
            )
        } else {
            centeredMessage(
                title: "Noch kein Import gestartet.",
                subtitle: "Gehe zurück und starte den Import oder öffne Feedivo ohne Feeds.",
                showsProgress: false
            )
        }
    }

    private var feedTable: some View {
        VStack(spacing: 0) {
            if isPreparingPreview {
                previewProgressRow
            } else {
                tableHeader

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if rows.isEmpty {
                            centeredTableMessage(
                                title: "Noch keine Feeds geprüft.",
                                subtitle: "Gib eine Feed-Adresse ein oder wähle eine OPML-Datei aus."
                            )
                        } else if visibleRowIDs.isEmpty {
                            centeredTableMessage(
                                title: "Keine Feeds für diesen Status.",
                                subtitle: "Wähle im Filter einen anderen Status, um weitere Feeds zu sehen."
                            )
                        } else {
                            ForEach($rows) { $row in
                                if visibleRowIDs.contains(row.id) {
                                    FirstRunImportFeedRow(
                                        row: $row,
                                        selectionOptions: selectionOptions,
                                        availableFolders: availableFolders
                                    )
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(height: tableBodyHeight)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.secondary.opacity(0.18))
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
        .frame(maxWidth: .infinity, minHeight: tableBodyHeight + 34, alignment: .center)
        .padding(.horizontal, 24)
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Text("")
                .frame(width: 34, alignment: .leading)
            Text("Feed")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Ordner")
                .frame(width: 140, alignment: .leading)
            Text("Status")
                .frame(width: 110, alignment: .leading)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .frame(height: 34)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.76))
    }

    private var optionToggles: some View {
        VStack(spacing: 10) {
            FirstRunSettingsLine(
                title: "Feeds nach Import direkt aktualisieren",
                subtitle: "Lädt direkt Titel, Favicons und erste Artikel. Das dauert etwas länger."
            ) {
                Toggle("", isOn: $refreshAfterImport)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .frame(maxWidth: 620)
    }

    @ViewBuilder
    private var resultBox: some View {
        if let resultMessage {
            Text(resultMessage)
                .font(.callout)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var errorBox: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
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

    private var footer: some View {
        HStack {
            if step == .importOPML {
                opmlImportOptions
            }

            Spacer()

            Button("Später") {
                onSkip()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isPreparingPreview || feedViewModel.isLoading)

            Button("Zurück") {
                goBack()
            }
            .disabled(step == .welcome || isPreparingPreview || feedViewModel.isLoading)

            Button(primaryButtonTitle) {
                primaryAction()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPrimaryButtonDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.secondary.opacity(0.14))
                .frame(height: 1)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:
            "Weiter"
        case .addFeed:
            "Auswahl prüfen"
        case .importOPML:
            "Auswahl prüfen"
        case .review:
            "Einstellungen wählen"
        case .defaults:
            selectedImportRows.isEmpty ? "Fertig anzeigen" : "Import starten"
        case .finish:
            "Starten"
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        switch step {
        case .welcome:
            true
        case .addFeed, .importOPML:
            rows.isEmpty || isPreparingPreview
        case .review:
            selectedImportRows.isEmpty || isPreparingPreview
        case .defaults:
            feedViewModel.isLoading
        case .finish:
            false
        }
    }

    private var importSummaryText: String {
        "\(selectedImportRows.count) Feeds werden gespeichert. \(folderCount) Ordner werden verwendet. \(refreshAfterImport ? "Feedivo lädt danach direkt die ersten Artikel." : "Die Artikel werden später manuell aktualisiert.")"
    }

    private func intervalTitle(_ interval: Int) -> String {
        "\(interval) Minuten"
    }

    private func filterButtonTitle(_ filter: OPMLImportStatusFilter) -> String {
        switch filter {
        case .all:
            "Alle"
        case .available:
            "Neu"
        case .duplicates:
            "Duplikate"
        case .unreachable:
            "Nicht erreichbar"
        }
    }

    private func centeredMessage(title: String, subtitle: String, showsProgress: Bool) -> some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .padding(.horizontal, 18)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.16))
        )
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

    private func primaryAction() {
        switch step {
        case .welcome:
            break
        case .addFeed, .importOPML:
            step = .review
        case .review:
            step = .defaults
        case .defaults:
            importSelectedFeedsAndComplete()
        case .finish:
            onComplete()
        }
    }

    private func goBack() {
        switch step {
        case .welcome:
            break
        case .addFeed, .importOPML:
            step = .welcome
        case .review:
            step = inputStep
        case .defaults:
            step = .review
        case .finish:
            step = .defaults
        }
    }

    private func prepareSingleFeedPreview() {
        let cleanedURL = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            return
        }

        let title = URL(string: cleanedURL)?.host(percentEncoded: false) ?? cleanedURL
        let feed = OPMLFeed(title: title, xmlURL: cleanedURL, htmlURL: nil, folderName: nil)
        inputStep = .addFeed
        preparePreview(
            feedsToPreview: [feed],
            sourceText: "Feed-Adresse wird geprüft..."
        )
    }

    private func loadOPML(from result: Result<URL, Error>) {
        Task {
            do {
                let url = try result.get()
                inputStep = .importOPML
                let canAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if canAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                selectedFileName = url.lastPathComponent
                sourceDescription = "Datei wird gelesen..."
                previewProgressText = "OPML-Datei wird gelesen und vorbereitet."
                errorMessage = nil
                resultMessage = nil
                rows = []
                isPreparingPreview = true

                let data = try Data(contentsOf: url)
                let opmlFeeds = try OPMLService.parseFeeds(from: data)
                sourceDescription = "\(opmlFeeds.count) Feeds erkannt. Feed-Adressen werden geprüft..."
                previewProgressText = "\(opmlFeeds.count) Feeds erkannt. Prüfung startet..."
                rows = await feedViewModel.opmlImportPreviewRows(
                    for: opmlFeeds,
                    existingFeeds: feeds,
                    onProgress: { progress in
                        previewProgressText = progress.displayText
                        sourceDescription = progress.displayText
                    }
                )
                sourceDescription = "\(rows.count) Feeds erkannt · \(Set(rows.map { trimmedFolderName($0.feed.folderName) ?? "Ohne Ordner" }).count) Ordner · \(url.lastPathComponent)"
                previewProgressText = "Prüfung abgeschlossen."
                isPreparingPreview = false
            } catch {
                isPreparingPreview = false
                rows = []
                errorMessage = error.localizedDescription
                sourceDescription = "Die Datei konnte nicht gelesen werden."
                previewProgressText = "Die Datei konnte nicht gelesen werden."
            }
        }
    }

    private func preparePreview(feedsToPreview: [OPMLFeed], sourceText: String) {
        Task {
            errorMessage = nil
            resultMessage = nil
            rows = []
            sourceDescription = sourceText
            previewProgressText = sourceText
            isPreparingPreview = true

            rows = await feedViewModel.opmlImportPreviewRows(
                for: feedsToPreview,
                existingFeeds: feeds,
                onProgress: { progress in
                    previewProgressText = progress.displayText
                    sourceDescription = progress.displayText
                }
            )

            sourceDescription = "\(rows.count) Feeds geprüft."
            previewProgressText = "Prüfung abgeschlossen."
            isPreparingPreview = false
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

                step = .importOPML
                loadOPML(from: .success(url))
            }
        }

        return true
    }

    private func importSelectedFeedsAndComplete() {
        Task {
            do {
                errorMessage = nil
                resultMessage = nil
                let selectedFeeds = selectedImportRows.map(\.feed)
                let importedDuplicateCount = selectedImportRows.filter { $0.status == .duplicate }.count
                let importedUnreachableCount = selectedImportRows.filter { $0.status == .unreachable }.count
                let result = try await feedViewModel.importOPMLFeeds(
                    selectedFeeds,
                    existingFeeds: feeds,
                    allowsDuplicates: allowsDuplicates,
                    refreshAfterImport: refreshAfterImport,
                    refreshIntervalMinutes: backgroundRefreshIntervalMinutes,
                    context: modelContext
                )
                completionSummary = FirstRunCompletionSummary(
                    importedFeeds: result.imported,
                    folderCount: folderCount,
                    skippedDuplicates: result.skippedDuplicates,
                    importedDuplicates: importedDuplicateCount,
                    importedUnreachable: importedUnreachableCount,
                    refreshAfterImport: refreshAfterImport,
                    refreshProblemMessage: feedViewModel.errorMessage
                )
                resultMessage = nil
                step = .finish
            } catch {
                completionSummary = FirstRunCompletionSummary(
                    importedFeeds: 0,
                    folderCount: folderCount,
                    skippedDuplicates: 0,
                    importedDuplicates: 0,
                    importedUnreachable: 0,
                    refreshAfterImport: refreshAfterImport,
                    refreshProblemMessage: error.localizedDescription
                )
                errorMessage = nil
                step = .finish
            }
        }
    }

    private func selectAllImportableRows() {
        for index in rows.indices {
            guard visibleRowIDs.contains(rows[index].id) else {
                continue
            }

            rows[index].isSelected = selectionOptions.canImport(rows[index].status)
        }
    }

    private func deselectVisibleRows() {
        for index in rows.indices where visibleRowIDs.contains(rows[index].id) {
            rows[index].isSelected = false
        }
    }

    private func resetPreview() {
        rows = []
        errorMessage = nil
        resultMessage = nil
        completionSummary = nil
        sourceDescription = "Wähle aus, wie du deine ersten Feeds hinzufügen möchtest."
        previewProgressText = "Noch keine Feeds geprüft."
        statusFilter = .all
        allowsDuplicates = false
        allowsUnreachable = false
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

private struct FirstRunChoiceCard: View {
    let iconName: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 46)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                HStack {
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.16))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FirstRunImportFeedRow: View {
    @Binding var row: OPMLImportPreviewRow
    let selectionOptions: OPMLImportSelectionOptions
    let availableFolders: [String]

    private var isSelectable: Bool {
        selectionOptions.canImport(row.status)
    }

    private var folderBinding: Binding<String> {
        Binding(
            get: {
                trimmedFolderName(row.feed.folderName) ?? "Ohne Ordner"
            },
            set: { newValue in
                let folderName = newValue == "Ohne Ordner" ? nil : newValue
                row.feed = OPMLFeed(
                    title: row.feed.title,
                    xmlURL: row.feed.xmlURL,
                    htmlURL: row.feed.htmlURL,
                    folderName: folderName
                )
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $row.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!isSelectable)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.feed.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(row.feed.xmlURL)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: folderBinding) {
                Text("Ohne Ordner").tag("Ohne Ordner")
                ForEach(availableFolders, id: \.self) { folder in
                    Text(folder).tag(folder)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 140, alignment: .leading)

            statusBadge
                .frame(width: 110, alignment: .leading)
        }
        .frame(height: 42)
        .padding(.horizontal, 12)
        .background(rowBackground)
        .onChange(of: row.isSelected) {
            if !isSelectable {
                row.isSelected = false
            }
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.16)))
            .lineLimit(1)
    }

    private var rowBackground: Color {
        switch row.status {
        case .available:
            return .clear
        case .duplicate:
            return Color(nsColor: .controlBackgroundColor).opacity(0.74)
        case .unreachable:
            return Color.orange.opacity(0.08)
        }
    }

    private var statusText: String {
        switch row.status {
        case .available:
            "Neu"
        case .duplicate:
            "Duplikat"
        case .unreachable:
            "Nicht erreichbar"
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .available:
            .green
        case .duplicate:
            .red
        case .unreachable:
            .orange
        }
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

private struct FirstRunStepItem: Identifiable {
    let index: Int
    let step: FirstRunWizardView.Step
    let title: String
    let subtitle: String

    var id: Int { index }
}

private struct FirstRunCompletionSummary: Equatable {
    let importedFeeds: Int
    let folderCount: Int
    let skippedDuplicates: Int
    let importedDuplicates: Int
    let importedUnreachable: Int
    let refreshAfterImport: Bool
    let refreshProblemMessage: String?

    var hasProblems: Bool {
        !problemMessages.isEmpty
    }

    var problemMessages: [String] {
        var messages: [String] = []

        if skippedDuplicates > 0 {
            messages.append("\(skippedDuplicates) doppelte Feeds wurden nicht importiert.")
        }

        if !refreshAfterImport {
            messages.append("Feeds wurden importiert, aber noch nicht aktualisiert.")
        }

        if let refreshProblemMessage,
           !refreshProblemMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(refreshProblemMessage)
        }

        return messages
    }
}

private struct FirstRunTrafficDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct FirstRunStepRow: View {
    let index: Int
    let title: String
    let subtitle: String
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isActive ? .white : .secondary)
                .frame(width: 22, height: 22)
                .background(isActive ? Color.accentColor : Color.white.opacity(0.72), in: Circle())
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.22))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isActive ? .primary : .secondary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FirstRunSettingsLine<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            accessory()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14))
        )
    }
}

private struct FirstRunSegmentButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isActive ? .white : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                isActive
                    ? Color(red: 0.18, green: 0.44, blue: 0.78).opacity(configuration.isPressed ? 0.82 : 1)
                    : Color.white.opacity(configuration.isPressed ? 0.55 : 0.72),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isActive ? Color(red: 0.18, green: 0.44, blue: 0.78) : Color.secondary.opacity(0.14))
            )
    }
}
