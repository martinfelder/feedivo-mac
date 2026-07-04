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

    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @AppStorage("markArticleReadOnSelection") private var markArticleReadOnSelection = true
    @AppStorage(BackgroundRefreshSettings.isEnabledKey) private var isBackgroundRefreshEnabled = false
    @AppStorage(BackgroundRefreshSettings.intervalMinutesKey) private var backgroundRefreshIntervalMinutes = BackgroundRefreshSettings.defaultIntervalMinutes

    let feedViewModel: FeedViewModel
    let onSkip: () -> Void
    let onComplete: () -> Void

    // Bestehende Ordnernamen aus SQLite für das Folder-Dropdown. Der Duplikat-
    // Check läuft in `opmlImportPreviewRows` SQLite-basiert; eine SwiftData-
    // `Feed`-Liste braucht dieser Wizard nicht mehr.
    private var existingFolderNames: [String] {
        guard let feedivoDatabase else { return [] }
        return (try? FeedStore(database: feedivoDatabase).feeds())?
            .compactMap { $0.folderName?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    @State private var step: Step = .welcome
    @State private var inputStep: Step = .addFeed
    @State private var feedURLString = ""
    @State private var completionSummary: FirstRunCompletionSummary?
    @State private var previewController = OPMLImportPreviewController(configuration: .firstRun)

    private var tableBodyHeight: CGFloat {
        usesCompactEmptyImportPreview ? 170 : 280
    }

    private var usesCompactEmptyImportPreview: Bool {
        step == .importOPML && previewController.rows.isEmpty && !previewController.isPreparingPreview
    }

    private var selectedCountText: String {
        String.localizedStringWithFormat(String(localized: "firstRun.selectedCount"),
                                         previewController.selectedImportRows.count,
                                         previewController.rows.count)
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
            isPresented: $previewController.isFileImporterPresented,
            allowedContentTypes: [.opml, .xml]
        ) { result in
            inputStep = .importOPML
            previewController.loadOPML(
                from: result,
                existingFeeds: [],
                sqliteDatabase: feedivoDatabase,
                feedViewModel: feedViewModel
            )
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $previewController.isDropTargeted) { providers in
            previewController.handleDroppedFiles(
                providers,
                existingFeeds: [],
                sqliteDatabase: feedivoDatabase,
                feedViewModel: feedViewModel
            ) { _ in
                step = .importOPML
                inputStep = .importOPML
            }
        }
        .onChange(of: previewController.allowsDuplicates) {
            previewController.applyToggleSelectionToRows()
        }
        .onChange(of: previewController.allowsUnreachable) {
            previewController.applyToggleSelectionToRows()
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

            Text(L10n.firstRunTitlebarTitle)
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
            L10n.firstRunStepWelcomeTitle
        case .addFeed:
            L10n.firstRunStepAddFeedTitle
        case .importOPML:
            L10n.firstRunStepImportOPMLTitle
        case .review:
            L10n.firstRunStepReviewTitle
        case .defaults:
            L10n.firstRunStepDefaultsTitle
        case .finish:
            L10n.firstRunStepFinishTitle
        }
    }

    private var stepLead: String {
        switch step {
        case .welcome:
            L10n.firstRunStepWelcomeLead
        case .addFeed:
            L10n.firstRunStepAddFeedLead
        case .importOPML:
            L10n.firstRunStepImportOPMLLead
        case .review:
            L10n.firstRunStepReviewLead
        case .defaults:
            L10n.firstRunStepDefaultsLead
        case .finish:
            L10n.firstRunStepFinishLead
        }
    }

    private var stepItems: [FirstRunStepItem] {
        [
            FirstRunStepItem(index: 1, step: .welcome, title: L10n.firstRunRailStartTitle, subtitle: L10n.firstRunRailStartSubtitle),
            FirstRunStepItem(index: 2, step: .addFeed, title: L10n.firstRunRailFeedTitle, subtitle: L10n.firstRunRailFeedSubtitle),
            FirstRunStepItem(index: 3, step: .importOPML, title: L10n.firstRunRailOPMLTitle, subtitle: L10n.firstRunRailOPMLSubtitle),
            FirstRunStepItem(index: 4, step: .review, title: L10n.firstRunRailReviewTitle, subtitle: L10n.firstRunRailReviewSubtitle),
            FirstRunStepItem(index: 5, step: .defaults, title: L10n.firstRunRailDefaultsTitle, subtitle: L10n.firstRunRailDefaultsSubtitle),
            FirstRunStepItem(index: 6, step: .finish, title: L10n.firstRunRailFinishTitle, subtitle: L10n.firstRunRailFinishSubtitle)
        ]
    }

    private var welcomeStep: some View {
        HStack(spacing: 14) {
            FirstRunChoiceCard(
                iconName: "plus.circle.fill",
                title: L10n.firstRunCardAddFeedTitle,
                subtitle: L10n.firstRunCardAddFeedSubtitle
            ) {
                resetPreview()
                inputStep = .addFeed
                step = .addFeed
            }

            FirstRunChoiceCard(
                iconName: "tray.and.arrow.down.fill",
                title: L10n.firstRunCardImportOPMLTitle,
                subtitle: L10n.firstRunCardImportOPMLSubtitle
            ) {
                resetPreview()
                inputStep = .importOPML
                step = .importOPML
            }

            FirstRunChoiceCard(
                iconName: "clock.fill",
                title: L10n.firstRunCardLaterTitle,
                subtitle: L10n.firstRunCardLaterSubtitle
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
                    .disabled(previewController.isPreparingPreview)

                Button(L10n.firstRunFeedCheck) {
                    prepareSingleFeedPreview()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(feedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || previewController.isPreparingPreview)
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
            if !previewController.rows.isEmpty {
                reviewToolbar
            }

            feedTable
        }
    }

    private var opmlImportOptions: some View {
        HStack(spacing: 18) {
            Toggle(L10n.opmlImportAllowDuplicates, isOn: $previewController.allowsDuplicates)
                .toggleStyle(.checkbox)

            Toggle(L10n.opmlImportAllowUnreachable, isOn: $previewController.allowsUnreachable)
                .toggleStyle(.checkbox)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .disabled(previewController.isPreparingPreview)
    }

    @ViewBuilder
    private var opmlSourceControl: some View {
        if previewController.rows.isEmpty && !previewController.isPreparingPreview {
            opmlDropZone
        } else {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
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

                Button(L10n.firstRunOtherOPML) {
                    previewController.isFileImporterPresented = true
                }
                .disabled(previewController.isPreparingPreview)
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
            previewController.isFileImporterPresented = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 22, weight: .semibold))
                Text(L10n.firstRunDropHere)
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.firstRunDropHint)
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
                    title: L10n.firstRunSettingsMarkReadTitle,
                    subtitle: L10n.firstRunSettingsMarkReadSubtitle
                ) {
                    Toggle("", isOn: $markArticleReadOnSelection)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                FirstRunSettingsLine(
                    title: L10n.firstRunSettingsAutoRefreshTitle,
                    subtitle: L10n.firstRunSettingsAutoRefreshSubtitle
                ) {
                    Toggle("", isOn: $isBackgroundRefreshEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                FirstRunSettingsLine(
                    title: L10n.firstRunSettingsIntervalTitle,
                    subtitle: L10n.firstRunSettingsIntervalSubtitle
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
        Picker(L10n.firstRunSettingsIntervalTitle, selection: $backgroundRefreshIntervalMinutes) {
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
                Picker(L10n.firstRunStatusfilter, selection: $previewController.statusFilter) {
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
                Button(L10n.firstRunSelectAll) {
                    previewController.selectAllImportableRows()
                }
                .disabled(previewController.rows.isEmpty || previewController.isPreparingPreview)

                Button(L10n.firstRunDeselectAll) {
                    previewController.deselectVisibleRows()
                }
                .disabled(previewController.rows.isEmpty || previewController.isPreparingPreview)

                TextField(L10n.opmlImportNewFolder, text: $previewController.newFolderName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
                    .disabled(previewController.isPreparingPreview)

                Button(L10n.firstRunCreateFolder) {
                    previewController.createFolder()
                }
                .disabled(previewController.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || previewController.isPreparingPreview)
            }
        }
    }

    private var previewSummaryText: String {
        let rows = previewController.rows.count
        let dups = previewController.duplicateCount
        let unreach = previewController.unreachableCount
        let selected = previewController.selectedImportRows.count
        return "\(rows) \(L10n.opmlImportSummaryFeedsChecked) · \(dups) \(L10n.opmlImportSummaryDuplicates) · \(unreach) \(L10n.opmlImportSummaryUnreachable) · \(selected) \(L10n.opmlImportSummarySelected)"
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
                    Text(L10n.firstRunImportSummaryTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Text(L10n.firstRunImportSummaryDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(L10n.firstRunEditSelection) {
                    step = inputStep
                }
                .buttonStyle(.link)
                .disabled(previewController.isPreparingPreview || feedViewModel.isLoading)
            }

            LazyVGrid(columns: summaryMetricColumns, spacing: 10) {
                reviewSummaryMetric(value: "\(previewController.selectedImportRows.count)", label: L10n.firstRunMetricSelectedFeeds)
                reviewSummaryMetric(value: "\(previewController.folderCount)", label: L10n.firstRunMetricFolders)
                reviewSummaryMetric(value: "\(previewController.duplicateCount)", label: L10n.firstRunMetricDuplicates)
                reviewSummaryMetric(value: "\(previewController.unreachableCount)", label: L10n.firstRunMetricUnreachable)
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
                        Text(completionSummary.hasProblems ? L10n.firstRunFinishProblemsTitle : L10n.firstRunFinishOkTitle)
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.firstRunFinishDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: summaryMetricColumns, spacing: 10) {
                    reviewSummaryMetric(value: "\(completionSummary.importedFeeds)", label: L10n.firstRunMetricFeedsImported)
                    reviewSummaryMetric(value: "\(completionSummary.folderCount)", label: L10n.firstRunMetricFoldersUsed)
                    reviewSummaryMetric(value: "\(completionSummary.importedDuplicates)", label: L10n.firstRunMetricDuplicatesImported)
                    reviewSummaryMetric(value: "\(completionSummary.importedUnreachable)", label: L10n.firstRunMetricUnreachableImported)
                }

                if !completionSummary.problemMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.firstRunHintsTitle)
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
                title: L10n.firstRunNoImportTitle,
                subtitle: L10n.firstRunNoImportSubtitle,
                showsProgress: false
            )
        }
    }

    private var feedTable: some View {
        VStack(spacing: 0) {
            if previewController.isPreparingPreview {
                previewProgressRow
            } else {
                tableHeader

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if previewController.rows.isEmpty {
                            centeredTableMessage(
                                title: L10n.firstRunEmptyPreviewTitle,
                                subtitle: L10n.firstRunEmptyPreviewSubtitle
                            )
                        } else if previewController.visibleRowIDs.isEmpty {
                            centeredTableMessage(
                                title: L10n.firstRunEmptyFilterTitle,
                                subtitle: L10n.firstRunEmptyFilterSubtitle
                            )
                        } else {
                            ForEach($previewController.rows) { $row in
                                if previewController.visibleRowIDs.contains(row.id) {
                                    OPMLImportFeedRow(
                                        row: $row,
                                        selectionOptions: previewController.selectionOptions,
                                        availableFolders: previewController.availableFolders(existingFolderNames: existingFolderNames),
                                        layout: .firstRun
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
                Text(L10n.firstRunPreparingTitle)
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
        .frame(maxWidth: .infinity, minHeight: tableBodyHeight + 34, alignment: .center)
        .padding(.horizontal, 24)
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Text("")
                .frame(width: 34, alignment: .leading)
            Text(L10n.firstRunTableHeaderFeed)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.firstRunTableHeaderFolder)
                .frame(width: 140, alignment: .leading)
            Text(L10n.firstRunTableHeaderStatus)
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
                title: L10n.firstRunRefreshAfterTitle,
                subtitle: L10n.firstRunRefreshAfterSubtitle
            ) {
                Toggle("", isOn: $previewController.refreshAfterImport)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .frame(maxWidth: 620)
    }

    @ViewBuilder
    private var resultBox: some View {
        if let resultMessage = previewController.resultMessage {
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
        if let errorMessage = previewController.errorMessage {
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
        if previewController.isDropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, lineWidth: 3)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 26, weight: .semibold))
                        Text(L10n.firstRunDropOverlayTitle)
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.firstRunDropOverlayHint)
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

            Button(L10n.firstRunLater) {
                onSkip()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(previewController.isPreparingPreview || feedViewModel.isLoading)

            Button(L10n.firstRunBack) {
                goBack()
            }
            .disabled(step == .welcome || previewController.isPreparingPreview || feedViewModel.isLoading)

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
            L10n.firstRunPrimaryWelcome
        case .addFeed, .importOPML:
            L10n.firstRunPrimaryCheck
        case .review:
            L10n.firstRunPrimarySettings
        case .defaults:
            previewController.selectedImportRows.isEmpty ? L10n.firstRunPrimaryFinishShow : L10n.firstRunPrimaryImport
        case .finish:
            L10n.firstRunPrimaryStart
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        switch step {
        case .welcome:
            true
        case .addFeed, .importOPML:
            previewController.rows.isEmpty || previewController.isPreparingPreview
        case .review:
            previewController.selectedImportRows.isEmpty || previewController.isPreparingPreview
        case .defaults:
            feedViewModel.isLoading
        case .finish:
            false
        }
    }

    private var importSummaryText: String {
        let rows = previewController.rows.count
        let dups = previewController.duplicateCount
        let unreach = previewController.unreachableCount
        let selected = previewController.selectedImportRows.count
        return "\(rows) \(L10n.opmlImportSummaryFeedsChecked) · \(dups) \(L10n.opmlImportSummaryDuplicates) · \(unreach) \(L10n.opmlImportSummaryUnreachable) · \(selected) \(L10n.opmlImportSummarySelected)"
    }

    private func intervalTitle(_ interval: Int) -> String {
        String.localizedStringWithFormat(String(localized: "firstRun.intervalMinutes"), interval)
    }

    private func filterButtonTitle(_ filter: OPMLImportStatusFilter) -> String {
        switch filter {
        case .all:
            L10n.firstRunFilterAll
        case .available:
            L10n.firstRunFilterNew
        case .duplicates:
            L10n.firstRunFilterDuplicates
        case .unreachable:
            L10n.firstRunFilterUnreachable
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
        previewController.preparePreview(
            feeds: [feed],
            existingFeeds: [],
            sqliteDatabase: feedivoDatabase,
            feedViewModel: feedViewModel,
            sourceText: L10n.firstRunFeedAddressChecking
        )
    }

    private func importSelectedFeedsAndComplete() {
        Task {
            do {
                previewController.errorMessage = nil
                previewController.resultMessage = nil
                let selectedRows = previewController.selectedImportRows
                let selectedFeeds = selectedRows.map(\.feed)
                let importedDuplicateCount = selectedRows.filter { $0.status == .duplicate }.count
                let importedUnreachableCount = selectedRows.filter { $0.status == .unreachable }.count
                let result = try await feedViewModel.importOPMLFeeds(
                    selectedFeeds,
                    existingFeeds: [],
                    allowsDuplicates: previewController.allowsDuplicates,
                    refreshAfterImport: previewController.refreshAfterImport,
                    refreshIntervalMinutes: backgroundRefreshIntervalMinutes,
                    sqliteDatabase: feedivoDatabase
                )
                completionSummary = FirstRunCompletionSummary(
                    importedFeeds: result.imported,
                    folderCount: previewController.folderCount,
                    skippedDuplicates: result.skippedDuplicates,
                    importedDuplicates: importedDuplicateCount,
                    importedUnreachable: importedUnreachableCount,
                    refreshAfterImport: previewController.refreshAfterImport,
                    refreshProblemMessage: feedViewModel.errorMessage
                )
                previewController.resultMessage = nil
                step = .finish
            } catch {
                completionSummary = FirstRunCompletionSummary(
                    importedFeeds: 0,
                    folderCount: previewController.folderCount,
                    skippedDuplicates: 0,
                    importedDuplicates: 0,
                    importedUnreachable: 0,
                    refreshAfterImport: previewController.refreshAfterImport,
                    refreshProblemMessage: error.localizedDescription
                )
                previewController.errorMessage = nil
                step = .finish
            }
        }
    }

    private func resetPreview() {
        previewController.reset()
        completionSummary = nil
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
            messages.append(String.localizedStringWithFormat(L10n.firstRunProblemSkippedDuplicates, skippedDuplicates))
        }

        if !refreshAfterImport {
            messages.append(L10n.firstRunProblemNotRefreshed)
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
