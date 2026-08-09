import SwiftUI
import CloudKit
import OSLog

/// Einmaliger Merge-Dialog beim Umlegen des iCloud-Sync-Schalters — erscheint VOR dem
/// eigentlichen Backfill. Zeigt erkannte Namens-Duplikate (Tag/FeedFolder) zur Entscheidung,
/// oder nur eine kurze Zusammenfassung, falls keine gefunden wurden. Siehe Design-Spec
/// `docs/superpowers/specs/2026-07-26-icloud-sync-phase3-design.md`, Abschnitt 6.
///
/// Wichtig für die Aufrufreihenfolge (siehe `SettingsView.swift`, `SyncSettingsView`): dieses
/// Sheet wird gezeigt, BEVOR `CloudSyncEngine.start()` zum ersten Mal läuft — `onContinue()`
/// löst `start()` erst nach `applyDecisions()` aus. Würde die Engine zuerst starten, würde ihr
/// `backfillAllExistingRecords`-Schritt jeden lokalen Datensatz bereits bedingungslos
/// einreihen, bevor die hier getroffenen Merge-/Beide-behalten-Entscheidungen überhaupt
/// angewendet wurden — genau das Problem, das dieser Dialog verhindern soll.
struct CloudSyncFirstActivationView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let onContinue: () -> Void

    @State private var isLoading = true
    @State private var collisions: [CloudSyncFirstActivationAnalyzer.FirstActivationCollision] = []
    @State private var decisions: [String: Bool] = [:] // Schlüssel: cloudRecordID.recordName, true = zusammenführen
    /// Verbesserung nach Nutzer-Feedback zum Dialog: `true`, wenn mindestens eine der beiden
    /// CloudKit-Abfragen in `loadCollisions()` fehlgeschlagen ist (z. B. kein Netz). Ohne dieses
    /// Flag sah der Dialog bei "Prüfung fehlgeschlagen" optisch identisch aus wie bei "Prüfung
    /// erfolgreich, keine Duplikate gefunden" — beides zeigte denselben positiven Text.
    @State private var checkFailed = false
    /// Zweiter Bugfix (Nutzer-Report 2026-08-08, per `/usr/bin/log stream` verifiziert): `true`,
    /// wenn der Fehlschlag konkret der bekannte CloudKit-Schema-Fehler "Field 'recordName' is not
    /// marked queryable" ist (siehe `CloudSyncFirstActivationAnalyzer.isMissingQueryableIndexError`)
    /// — steuert, ob die generische oder die gezielte, actionable Warnung angezeigt wird.
    @State private var checkFailedIsMissingIndex = false
    /// Whole-Branch-Review-Fund (Important 3): nicht-`nil`, sobald mindestens eine
    /// Merge-/Beide-behalten-Entscheidung in `applyDecisions()` fehlgeschlagen ist — zeigt
    /// einen Fehler-Alert, statt (wie zuvor) den Fehler nur zu loggen und trotzdem zu
    /// `start()` weiterzulaufen. Das Sheet bleibt in diesem Fall offen: der Nutzer kann seine
    /// Entscheidung im Picker anpassen (z. B. „Zusammenführen" statt „Beide behalten") und
    /// erneut auf „Weiter" tippen — `applyDecisions()` ist absichtlich idempotent gehalten
    /// (dieselbe, beim Laden einmalig eingefrorene `collision.name` wird bei jedem erneuten
    /// Versuch als Grundlage genutzt), ein erneuter Klick ist deshalb ein echter Retry, keine
    /// Doppel-Anwendung.
    @State private var mergeFailureMessage: String?

    // MARK: - Sheet-Chrome (Konzept A, analog TagManagerView/OPMLExportSheet: feste Kopf-/
    // Fußzeile mit Haarlinien-Trennern statt frei schwebendem Inhalt, siehe RuleDialogTheme.swift)

    var body: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            header(theme: theme)
            dialogDivider(theme)
            bodyContent(theme: theme)
            dialogDivider(theme)
            footer(theme: theme)
        }
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(width: 500)
        .frame(minHeight: 340)
        .task { await loadCollisions() }
        .alert(L10n.commonError, isPresented: Binding(
            get: { mergeFailureMessage != nil },
            set: { newValue in
                if !newValue { mergeFailureMessage = nil }
            }
        )) {
            Button(L10n.commonOK) { mergeFailureMessage = nil }
        } message: {
            Text(mergeFailureMessage ?? "")
        }
    }

    private func dialogDivider(_ theme: RuleDialogTheme) -> some View {
        Rectangle()
            .fill(theme.border)
            .frame(height: 1)
    }

    private func header(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.firstActivationTitle)
                .font(.system(size: 21, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(theme.text)

            // Verbesserung nach Nutzer-Feedback: der Dialog nannte bisher nicht, WAS er
            // eigentlich prüft (nur Tags/Ordner, nicht Feeds/Regeln/Artikelstatus — die laufen
            // über den separaten Last-Write-Wins-Konfliktpfad nach der Aktivierung). Immer
            // sichtbar, unabhängig vom Lade-/Ergebniszustand.
            Text(L10n.firstActivationScopeNote)
                .font(.system(size: 13.5))
                .foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private func bodyContent(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 36)
                    Spacer()
                }
            } else {
                if checkFailed {
                    statusBanner(
                        theme: theme,
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        text: checkFailedIsMissingIndex ? L10n.firstActivationCheckFailedMissingIndex : L10n.firstActivationCheckFailed
                    )
                }
                if collisions.isEmpty {
                    // Bei fehlgeschlagenem Check bewusst KEINE positive "keine Duplikate
                    // gefunden"-Meldung mehr zeigen — die Warnung oben ersetzt sie, statt beide
                    // widersprüchlichen Aussagen übereinander darzustellen.
                    if !checkFailed {
                        statusBanner(
                            theme: theme,
                            icon: "checkmark.circle.fill",
                            tint: RuleDialogTheme.switchOn,
                            text: L10n.firstActivationNoCollisions
                        )
                    }
                } else {
                    // Bei einem Teilfehlschlag (z. B. Tags-Abfrage erfolgreich, Ordner-Abfrage
                    // nicht) können trotzdem bereits gefundene Kollisionen vorliegen — die
                    // Warnung UND die Liste erscheinen dann gemeinsam, statt echte Funde zu
                    // verstecken.
                    collisionList(theme: theme)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }

    /// Einheitliche Statuszeile für Erfolg/Warnung — Ton (Icon + getönte Kapsel-Fläche) folgt
    /// derselben Sprache wie die Vorschau-Statuszeile im Regel-Assistenten
    /// (`RuleWizardView.previewMatchCount`/`.previewError`).
    private func statusBanner(theme: RuleDialogTheme, icon: String, tint: Color, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)

            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private func collisionList(theme: RuleDialogTheme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(collisions.enumerated()), id: \.element.cloudRecordID.recordName) { index, collision in
                    collisionRow(collision, theme: theme)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                    if index < collisions.count - 1 {
                        dialogDivider(theme)
                    }
                }
            }
        }
        .frame(maxHeight: 260)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func collisionRow(_ collision: CloudSyncFirstActivationAnalyzer.FirstActivationCollision, theme: RuleDialogTheme) -> some View {
        let key = collision.cloudRecordID.recordName

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(collision.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                // Wiederverwendet dieselbe Typ-Bezeichnung wie im Konflikt-Sheet
                // (`SyncConflictResolutionView.recordTypeLabel`), damit "Tag" vs. "Ordner"
                // app-weit konsistent benannt bleibt.
                Text(SyncConflictResolutionView.recordTypeLabel(forRecordType: collision.recordType))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.text2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(theme.card2, in: Capsule())
                    .overlay(
                        Capsule().stroke(theme.border, lineWidth: 1)
                    )

                Spacer(minLength: 0)
            }

            RuleSegmentedControl(
                options: [(true, L10n.firstActivationMerge), (false, L10n.firstActivationKeepBoth)],
                selection: Binding(
                    get: { decisions[key] ?? true },
                    set: { decisions[key] = $0 }
                ),
                theme: theme,
                fullWidth: true
            )
        }
    }

    private func footer(theme: RuleDialogTheme) -> some View {
        HStack {
            Spacer()
            RuleDialogButton(
                titleKey: L10n.firstActivationContinue,
                style: isLoading ? .secondary : .primary,
                theme: theme
            ) {
                // Whole-Branch-Review-Fund (Important 3): nur bei VOLLSTÄNDIGEM Erfolg
                // (keine einzige fehlgeschlagene Kollision) tatsächlich fortfahren — bei
                // jedem Fehlschlag bleibt das Sheet offen und zeigt den Alert weiter unten,
                // statt den Nutzer im Unklaren zu lassen, während `start()` bereits mit
                // einem unaufgelösten Duplikat losläuft.
                guard applyDecisions() else { return }
                // Review-Fix (Task 14, Critical 2): erst HIER, beim tatsächlichen
                // Abschluss des Erst-Aktivierungs-Ablaufs, wird die Sperre wieder
                // aufgehoben — siehe CloudSyncSettings.pendingFirstActivationKey und
                // FeedivoApp.init(). Muss vor onContinue() (löst CloudSyncEngine.start()
                // aus) geschehen, auch wenn es für den aktuellen start()-Aufruf selbst
                // keine Rolle spielt — die Reihenfolge macht den Zustand während des
                // gesamten Übergangs konsistent, falls onContinue() künftig einmal
                // asynchron würde.
                CloudSyncSettings.setPendingFirstActivation(false)
                onContinue()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isLoading)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }

    private func loadCollisions() async {
        let container = CKContainer(identifier: CloudSyncSettings.cloudKitContainerIdentifier)
        let (tags, folders, fetchFailed, missingQueryableIndex) = await CloudSyncFirstActivationAnalyzer.fetchExistingCloudRecords(container: container)
        checkFailed = fetchFailed
        checkFailedIsMissingIndex = missingQueryableIndex

        guard let feedivoDatabase else {
            isLoading = false
            return
        }
        do {
            collisions = try CloudSyncFirstActivationAnalyzer.findCollisions(database: feedivoDatabase, tagRecords: tags, folderRecords: folders)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Erst-Aktivierungs-Duplikat-Erkennung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            collisions = []
        }
        isLoading = false
    }

    /// Wendet alle getroffenen Merge-/Beide-behalten-Entscheidungen an. Liefert `true`, wenn
    /// ALLE Kollisionen erfolgreich verarbeitet wurden — nur dann darf der Aufrufer mit
    /// `start()` fortfahren. Whole-Branch-Review-Fund (Important 3): die ursprüngliche Version
    /// fing Fehler pro Kollision nur ab, loggte sie und lief unbeirrt weiter bis zu
    /// `setPendingFirstActivation(false)`/`onContinue()` — schlägt z. B. `keepBoth` fehl, weil
    /// der disambiguierte Name („X (2)") selbst schon existiert (UNIQUE-Index auf
    /// `tags.name`), würde die Sync-Engine trotzdem mit einem weiterhin unaufgelösten Duplikat
    /// starten, ohne dass der Nutzer davon je erfährt. Jetzt: Fehlschläge werden gesammelt und
    /// als Alert angezeigt (siehe `mergeFailureMessage`), der Aufrufer bricht ab statt
    /// fortzufahren.
    private func applyDecisions() -> Bool {
        guard let feedivoDatabase else { return true }
        var failedCollisionNames: [String] = []
        for collision in collisions {
            let shouldMerge = decisions[collision.cloudRecordID.recordName] ?? true
            do {
                if shouldMerge {
                    try CloudSyncFirstActivationMerger.merge(collision, database: feedivoDatabase)
                } else {
                    try CloudSyncFirstActivationMerger.keepBoth(collision, database: feedivoDatabase)
                }
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Erst-Aktivierungs-Entscheidung konnte nicht angewendet werden: \(error.localizedDescription, privacy: .public)")
                failedCollisionNames.append(collision.name)
            }
        }
        // Store-Konvention (siehe CLAUDE.md-Gotcha „GRDB statt SwiftData"): weder `merge`
        // noch `keepBoth` bumpen selbst den Statuszähler — ohne diesen Aufruf würde die
        // Sidebar nach einem Merge (z. B. verschwundener Duplikat-Tag) nicht neu laden. Läuft
        // bewusst auch bei Teilfehlschlägen, damit die erfolgreich verarbeiteten Kollisionen
        // sofort sichtbar werden, während der Nutzer die fehlgeschlagenen im Alert anpasst.
        if !collisions.isEmpty {
            SQLiteDataInvalidation.shared.bumpStatusVersion()
        }

        guard failedCollisionNames.isEmpty else {
            mergeFailureMessage = L10n.firstActivationMergeFailedMessage(
                failedCollisionNames.joined(separator: ", ")
            )
            return false
        }
        return true
    }
}
