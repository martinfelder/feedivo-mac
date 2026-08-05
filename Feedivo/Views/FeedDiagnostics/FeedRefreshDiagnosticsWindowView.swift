import AppKit
import SwiftUI

/// Eigenständiges Fenster: listet alle Feeds, deren letzter Aktualisierungs-
/// versuch fehlgeschlagen ist, mit echtem Fehlergrund aus `feed_logs` (statt
/// des flüchtigen `FeedViewModel.refreshItems`-Panels unten rechts in
/// `ContentView.swift`, das nur den zuletzt laufenden "Alle aktualisieren"-
/// Vorgang abdeckt). Optik/Aktionen folgen dem Konzept-A-Dialogsystem
/// (`RuleDialogTheme`) — alle fünf Aktionen, die vorher nur im Rechtsklick-
/// Kontextmenü erreichbar waren, sitzen jetzt fest sichtbar in der Zeile. Siehe
/// docs/superpowers/specs/2026-08/2026-08-05-feed-refresh-diagnose-fenster-design.md
/// und docs/superpowers/specs/2026-08/2026-08-05-feed-status-tabellenansicht-design.md.
struct FeedRefreshDiagnosticsWindowView: View {
    static let windowID = "feed-refresh-diagnostics-window"

    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme

    @State private var diagnostics: [FeedFailureDiagnostic] = []
    @State private var feedViewModel = FeedViewModel()
    @State private var feedShowingProperties: FeedFailureDiagnostic?
    @State private var feedPendingDeletion: FeedFailureDiagnostic?
    @State private var isBusy = false
    @State private var searchText = ""
    @State private var lastReloadedAt: Date?

    private var theme: RuleDialogTheme {
        RuleDialogTheme(colorScheme: colorScheme)
    }

    private var visibleDiagnostics: [FeedFailureDiagnostic] {
        FeedStatusTableLogic.filtered(diagnostics, matching: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let errorMessage = feedViewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.destructiveText)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 8)
            }

            if diagnostics.isEmpty {
                emptyState
            } else {
                Rectangle()
                    .fill(theme.border)
                    .frame(height: 1)
                    .padding(.horizontal, 26)

                searchField

                if visibleDiagnostics.isEmpty {
                    noSearchResultsState
                } else {
                    table
                }

                footer
            }
        }
        .background(theme.bg)
        .frame(minWidth: 700, minHeight: 420)
        .task {
            await reload()
        }
        .sheet(item: $feedShowingProperties) { diagnostic in
            FeedPropertiesView(feedID: diagnostic.feedID)
        }
        .confirmationDialog(
            L10n.feedDeleteConfirmationTitle,
            isPresented: Binding(
                get: { feedPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        feedPendingDeletion = nil
                    }
                }
            ),
            presenting: feedPendingDeletion
        ) { diagnostic in
            Button(L10n.feedDeleteConfirmButton, role: .destructive) {
                delete(diagnostic)
            }

            Button(L10n.commonCancel, role: .cancel) {
                feedPendingDeletion = nil
            }
        } message: { diagnostic in
            Text(L10n.feedDeleteConfirmationMessage(feedTitle: diagnostic.feedTitle))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.feedRefreshDiagnosticsWindowTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.text)

                Text(L10n.feedRefreshDiagnosticsDescription)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.text2)
            }

            Spacer()

            RuleDialogButton(
                titleKey: L10n.feedRefreshDiagnosticsReloadListButton,
                style: .secondary,
                theme: theme,
                systemImage: "arrow.clockwise"
            ) {
                Task {
                    await reload()
                }
            }
            .disabled(isBusy)

            if !diagnostics.isEmpty {
                RuleDialogButton(
                    titleKey: L10n.feedRefreshDiagnosticsRetryAllButton,
                    style: .primary,
                    theme: theme
                ) {
                    Task {
                        await retryAll()
                    }
                }
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Suche

    private var searchField: some View {
        RuleDialogTextField(
            placeholder: L10n.feedRefreshDiagnosticsSearchPlaceholder,
            text: $searchText,
            theme: theme
        )
        .frame(width: 240)
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
    }

    // MARK: - Tabelle

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            tableHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleDiagnostics.enumerated()), id: \.element.id) { index, diagnostic in
                        FeedStatusTableRow(
                            diagnostic: diagnostic,
                            theme: theme,
                            isRetryDisabled: isBusy,
                            onRetry: {
                                Task {
                                    await retry(diagnostic)
                                }
                            },
                            onShowProperties: {
                                feedShowingProperties = diagnostic
                            },
                            onOpenWebsite: openWebsiteAction(for: diagnostic),
                            onCopyXMLAddress: {
                                copyXMLAddress(diagnostic)
                            },
                            onDelete: {
                                feedPendingDeletion = diagnostic
                            }
                        )

                        if index < visibleDiagnostics.count - 1 {
                            Rectangle()
                                .fill(theme.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .background(theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .padding(.horizontal, 26)
    }

    private var tableHeader: some View {
        HStack(spacing: 14) {
            Text(L10n.feedRefreshDiagnosticsColumnFeed)
                .frame(width: 170, alignment: .leading)

            Text(L10n.feedRefreshDiagnosticsColumnError)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(L10n.feedRefreshDiagnosticsColumnLastAttempt)
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 3) {
                Text(L10n.feedRefreshDiagnosticsColumnFailureCount)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(theme.accent)
            .frame(width: 118, alignment: .leading)

            Text(L10n.feedRefreshDiagnosticsColumnActions)
                .frame(width: 150, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold))
        .textCase(.uppercase)
        .foregroundStyle(theme.text2)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.card)
    }

    // MARK: - Leerzustände

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(RuleDialogTheme.switchOn)

            Text(L10n.feedRefreshDiagnosticsEmptyTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)

            Text(L10n.feedRefreshDiagnosticsEmptyDescription)
                .font(.system(size: 11))
                .foregroundStyle(theme.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private var noSearchResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(theme.text2)

            Text(L10n.feedRefreshDiagnosticsSearchNoResultsTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)

            Text(L10n.feedRefreshDiagnosticsSearchNoResultsDescription(searchText: searchText))
                .font(.system(size: 11))
                .foregroundStyle(theme.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 26)
    }

    // MARK: - Fußzeile

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: 0xFF9F0A))
                .frame(width: 6, height: 6)

            Text(footerStatusText)

            Spacer()
        }
        .font(.system(size: 11.5))
        .foregroundStyle(theme.text2)
        .padding(.horizontal, 26)
        .padding(.vertical, 11)
    }

    private var footerStatusText: String {
        let feedCountText = L10n.feedRefreshDiagnosticsFooterFeedCount(diagnostics.count)
        guard let lastReloadedAt else {
            return feedCountText
        }
        let lastCheckedText = L10n.feedRefreshDiagnosticsFooterLastChecked(lastReloadedAt.feedivoRelativeDisplay)
        return "\(feedCountText) · \(lastCheckedText)"
    }

    // MARK: - Aktionen

    private func openWebsiteAction(for diagnostic: FeedFailureDiagnostic) -> (() -> Void)? {
        guard let url = FeedPropertiesFormatter.linkURL(diagnostic.feedWebsiteURL ?? diagnostic.feedURL) else {
            return nil
        }
        return {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyXMLAddress(_ diagnostic: FeedFailureDiagnostic) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostic.feedURL, forType: .string)
    }

    private func reload() async {
        guard let feedivoDatabase else {
            diagnostics = []
            lastReloadedAt = Date()
            return
        }
        let loaded = (try? await FeedLogStore(database: feedivoDatabase).failureDiagnosticsAsync()) ?? []
        diagnostics = FeedStatusTableLogic.sortedByFailureCountDescending(loaded)
        lastReloadedAt = Date()
    }

    private func retry(_ diagnostic: FeedFailureDiagnostic) async {
        guard let feedivoDatabase else {
            return
        }
        await feedViewModel.refreshFeed(feedID: diagnostic.feedID, sqliteDatabase: feedivoDatabase)
        await reload()
    }

    /// Läuft sequenziell (kein `TaskGroup`) — `FeedViewModel.refreshFeed`
    /// guardet intern gegen Reentrancy über `isLoading`; parallele Aufrufe
    /// auf derselben Instanz würden alle bis auf den ersten silently no-op
    /// lassen (siehe Global Constraints im Plan).
    private func retryAll() async {
        guard let feedivoDatabase else {
            return
        }
        isBusy = true
        defer {
            isBusy = false
        }
        for diagnostic in diagnostics {
            await feedViewModel.refreshFeed(feedID: diagnostic.feedID, sqliteDatabase: feedivoDatabase)
        }
        await reload()
    }

    private func delete(_ diagnostic: FeedFailureDiagnostic) {
        // Dialog-Dismiss ist unabhängig vom Ausgang — schließt nur das
        // confirmationDialog, behauptet keinen Erfolg.
        feedPendingDeletion = nil
        guard let feedivoDatabase else {
            return
        }
        feedViewModel.deleteFeed(feedID: diagnostic.feedID, sqliteDatabase: feedivoDatabase)
        // `deleteFeed` wirft nicht — ein Fehlschlag landet nur in
        // `feedViewModel.errorMessage` (siehe Fehlerbanner oben). Die Zeile darf
        // deshalb nur bei tatsächlichem Erfolg entfernt werden, sonst würde die
        // UI einen gelöschten Feed vortäuschen, der in Wahrheit noch existiert.
        if feedViewModel.errorMessage == nil {
            diagnostics.removeAll { $0.feedID == diagnostic.feedID }
        }
    }
}

// MARK: - Zeile

private struct FeedStatusTableRow: View {
    let diagnostic: FeedFailureDiagnostic
    let theme: RuleDialogTheme
    let isRetryDisabled: Bool
    let onRetry: () -> Void
    let onShowProperties: () -> Void
    let onOpenWebsite: (() -> Void)?
    let onCopyXMLAddress: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            feedColumn
            errorColumn

            Text(diagnostic.lastAttemptAt.feedivoRelativeDisplay)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.text2)
                .frame(width: 90, alignment: .leading)

            FeedFailureSeverityBadge(count: diagnostic.consecutiveFailureCount, theme: theme)
                .frame(width: 118, alignment: .leading)

            actionsColumn
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var feedColumn: some View {
        HStack(spacing: 9) {
            faviconView

            VStack(alignment: .leading, spacing: 1) {
                Text(diagnostic.feedTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(diagnostic.feedURL)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(width: 170, alignment: .leading)
    }

    private var errorColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let httpStatusCode = diagnostic.httpStatusCode {
                Text("HTTP \(httpStatusCode)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(theme.border, lineWidth: 1)
                    )
            }

            Text(diagnostic.errorMessage)
                .font(.system(size: 12))
                .foregroundStyle(theme.destructiveText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionsColumn: some View {
        HStack(spacing: 2) {
            FeedStatusRowActionButton(
                systemImage: "arrow.clockwise",
                accessibilityLabel: L10n.feedRefreshCommand,
                theme: theme,
                action: onRetry
            )
            .disabled(isRetryDisabled)

            FeedStatusRowActionButton(
                systemImage: "info.circle",
                accessibilityLabel: L10n.feedPropertiesCommand,
                theme: theme,
                action: onShowProperties
            )

            if let onOpenWebsite {
                FeedStatusRowActionButton(
                    systemImage: "safari",
                    accessibilityLabel: L10n.feedRefreshDiagnosticsOpenWebsiteButton,
                    theme: theme,
                    action: onOpenWebsite
                )
            }

            FeedStatusRowActionButton(
                systemImage: "doc.on.doc",
                accessibilityLabel: L10n.feedPropertiesCopyXMLAddress,
                theme: theme,
                action: onCopyXMLAddress
            )

            FeedStatusRowActionButton(
                systemImage: "trash",
                accessibilityLabel: L10n.feedDeleteCommand,
                theme: theme,
                isDestructive: true,
                action: onDelete
            )
        }
        .frame(width: 150, alignment: .trailing)
    }

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURLString = diagnostic.feedFaviconURL, let url = URL(string: faviconURLString) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } placeholder: {
                fallbackIcon
            }
            .frame(width: 20, height: 20)
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 13))
            .foregroundStyle(theme.destructiveText)
            .frame(width: 20, height: 20)
    }
}

// MARK: - Schweregrad-Badge

private struct FeedFailureSeverityBadge: View {
    let count: Int
    let theme: RuleDialogTheme

    private var severity: FeedFailureSeverity {
        FeedFailureSeverity.forConsecutiveFailureCount(count)
    }

    private var label: String {
        switch severity {
        case .new:
            L10n.feedRefreshDiagnosticsSeverityNew
        case .warning, .critical:
            L10n.feedRefreshDiagnosticsConsecutiveFailures(count)
        }
    }

    private var foreground: Color {
        switch severity {
        case .new:
            theme.text2
        case .warning:
            Color(hex: 0xC76A00)
        case .critical:
            theme.destructiveText
        }
    }

    private var background: Color {
        switch severity {
        case .new:
            theme.card
        case .warning:
            Color(hex: 0xFF9F0A).opacity(0.14)
        case .critical:
            theme.destructiveTint
        }
    }

    private var border: Color {
        switch severity {
        case .new:
            theme.border
        case .warning:
            Color(hex: 0xFF9F0A).opacity(0.38)
        case .critical:
            theme.destructiveBorder
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(background)
            )
            .overlay(
                Capsule().stroke(border, lineWidth: 1)
            )
    }
}

// MARK: - Icon-Aktions-Button

private struct FeedStatusRowActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let theme: RuleDialogTheme
    var isDestructive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var foreground: Color {
        guard isHovering else {
            return theme.text2
        }
        return isDestructive ? theme.destructiveText : theme.text
    }

    private var background: Color {
        guard isHovering else {
            return .clear
        }
        return isDestructive ? theme.destructiveTint : theme.card
    }
}
