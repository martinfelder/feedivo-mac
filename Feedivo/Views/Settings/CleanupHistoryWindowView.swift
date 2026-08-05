import SwiftUI

// Eigenständiges Fenster für den Bereinigungsverlauf (Feature 17.3a, 2. Nachtrag) —
// löst die zuvor in den Einstellungen eingebettete History-Liste ab. Rendering-Logik
// 1:1 aus der bisherigen CleanupSettingsView übernommen.
struct CleanupHistoryWindowView: View {
    static let windowID = "cleanup-history-window"

    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @State private var cleanupHistory: [CleanupRunRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.cleanupHistoryDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if cleanupHistory.isEmpty {
                Text(L10n.cleanupHistoryEmpty)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 5) {
                    ForEach(cleanupHistory, id: \.id) { run in
                        cleanupHistoryRow(run)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .onAppear(perform: loadCleanupHistory)
        .onChange(of: SQLiteDataInvalidation.shared.statusVersion) {
            loadCleanupHistory()
        }
    }

    private func cleanupHistoryRow(_ run: CleanupRunRecord) -> some View {
        HStack {
            Text(run.executedAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.tertiary)
            Text(cleanupTriggerLabel(run.triggerSource))
                .foregroundStyle(.tertiary)
            Spacer()
            if run.succeeded {
                Text("\(run.deletedCount)")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(run.errorMessage ?? "")
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .frame(minHeight: 26)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cleanupTriggerLabel(_ rawValue: String) -> LocalizedStringKey {
        switch CleanupRunTrigger(rawValue: rawValue) {
        case .manual, nil:
            L10n.cleanupHistoryTriggerManual
        case .appStart:
            L10n.cleanupHistoryTriggerAppStart
        case .schedule:
            L10n.cleanupHistoryTriggerSchedule
        case .onQuit:
            L10n.cleanupHistoryTriggerOnQuit
        case .settingsChange:
            L10n.cleanupHistoryTriggerSettingsChange
        }
    }

    private func loadCleanupHistory() {
        guard let feedivoDatabase else {
            cleanupHistory = []
            return
        }
        cleanupHistory = (try? CleanupRunHistoryStore(database: feedivoDatabase).recentRuns()) ?? []
    }
}
