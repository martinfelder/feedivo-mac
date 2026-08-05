import AppKit
import SwiftUI

/// Eigenständiges Fenster: listet alle Feeds, deren letzter Aktualisierungs-
/// versuch fehlgeschlagen ist, mit echtem Fehlergrund aus `feed_logs` (statt
/// des flüchtigen `FeedViewModel.refreshItems`-Panels unten rechts in
/// `ContentView.swift`, das nur den zuletzt laufenden "Alle aktualisieren"-
/// Vorgang abdeckt). Siehe
/// docs/superpowers/specs/2026-08/2026-08-05-feed-refresh-diagnose-fenster-design.md.
struct FeedRefreshDiagnosticsWindowView: View {
    static let windowID = "feed-refresh-diagnostics-window"

    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @State private var diagnostics: [FeedFailureDiagnostic] = []
    @State private var feedViewModel = FeedViewModel()
    @State private var feedShowingProperties: FeedFailureDiagnostic?
    @State private var feedPendingDeletion: FeedFailureDiagnostic?
    @State private var isBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // Zeigt einen stillen `FeedViewModel.deleteFeed`/`refreshFeed`-Fehlschlag
            // sichtbar an — beide Methoden werfen nicht, sondern setzen nur
            // `errorMessage`, das dieses Fenster sonst nirgends konsumiert hätte.
            if let errorMessage = feedViewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if diagnostics.isEmpty {
                emptyState
            } else {
                List(diagnostics) { diagnostic in
                    FeedFailureDiagnosticRow(diagnostic: diagnostic)
                        .contextMenu {
                            rowActions(for: diagnostic)
                        }
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 360)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.feedRefreshDiagnosticsWindowTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(L10n.feedRefreshDiagnosticsDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L10n.feedRefreshDiagnosticsReloadListButton) {
                Task {
                    await reload()
                }
            }
            .disabled(isBusy)

            if !diagnostics.isEmpty {
                Button(L10n.feedRefreshDiagnosticsRetryAllButton) {
                    Task {
                        await retryAll()
                    }
                }
                .disabled(isBusy)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.green)

            Text(L10n.feedRefreshDiagnosticsEmptyTitle)
                .font(.system(size: 13, weight: .semibold))

            Text(L10n.feedRefreshDiagnosticsEmptyDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func rowActions(for diagnostic: FeedFailureDiagnostic) -> some View {
        Button(L10n.feedRefreshCommand) {
            Task {
                await retry(diagnostic)
            }
        }
        .disabled(isBusy)

        Button(L10n.feedPropertiesCommand) {
            feedShowingProperties = diagnostic
        }

        if let url = FeedPropertiesFormatter.linkURL(diagnostic.feedWebsiteURL ?? diagnostic.feedURL) {
            Button(L10n.feedRefreshDiagnosticsOpenWebsiteButton) {
                NSWorkspace.shared.open(url)
            }
        }

        Button(L10n.feedPropertiesCopyXMLAddress) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diagnostic.feedURL, forType: .string)
        }

        Divider()

        Button(L10n.feedDeleteCommand, role: .destructive) {
            feedPendingDeletion = diagnostic
        }
    }

    private func reload() async {
        guard let feedivoDatabase else {
            diagnostics = []
            return
        }
        diagnostics = (try? await FeedLogStore(database: feedivoDatabase).failureDiagnosticsAsync()) ?? []
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

private struct FeedFailureDiagnosticRow: View {
    let diagnostic: FeedFailureDiagnostic

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            faviconView

            VStack(alignment: .leading, spacing: 3) {
                Text(diagnostic.feedTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(diagnostic.errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(diagnostic.lastAttemptAt.formatted(date: .abbreviated, time: .shortened))

                    if let httpStatusCode = diagnostic.httpStatusCode {
                        Text("HTTP \(httpStatusCode)")
                    }

                    Text(L10n.feedRefreshDiagnosticsConsecutiveFailures(diagnostic.consecutiveFailureCount))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                Text(diagnostic.feedURL)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURLString = diagnostic.feedFaviconURL, let url = URL(string: faviconURLString) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
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
            .font(.system(size: 14))
            .foregroundStyle(.red)
            .frame(width: 20, height: 20)
    }
}
