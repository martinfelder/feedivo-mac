import SwiftUI
import AppKit

/// Mini-Reader-Sheet für Release-Notes eines gefundenen Updates.
/// Rendert release.bodyHTML über dieselbe ReaderContentRenderer/
/// ReaderInlineRun-Pipeline wie der Artikel-Reader (Fett/Kursiv/Links
/// funktionieren automatisch) - bewusst eine schlanke, eigene
/// Block-zu-View-Funktion statt SQLiteReaderView.contentBlock(_:)
/// wiederzuverwenden, da diese Reader-spezifisches Chrome (konfigurierbare
/// Schriftgrösse, Sticky-Header, Bild-Zoom) mitbringt, das hier nicht passt.
///
/// Nutzt das "Konzept A"-Theme (RuleDialogTheme) für Konsistenz mit den
/// übrigen Dialogen der App (Regeln, OPML, Suche, Organizer, Tags, Statistik).
/// Die Changelog-Bullets werden zusätzlich per UpdateReleaseNoteCategorizer nach
/// ihrem Commit-Präfix ("Feat:", "Fix:", "Design:", ...) in Gruppen mit Icon
/// sortiert, statt als eine unsortierte Liste roher Commit-Nachrichten zu erscheinen.
struct UpdateAvailableSheet: View {
    let release: SparkleReleaseInfo
    let onOpenOnGitHub: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sparkleUpdateCoordinator) private var coordinator

    private var blocks: [ReaderContentBlock] {
        ReaderContentRenderer.blocks(summary: nil, content: release.bodyHTML, fallbackImageURL: nil)
    }

    private var installedVersion: String {
        "\(AppVersionInfo.marketingVersion) (\(AppVersionInfo.buildNumber))"
    }

    /// Blöcke, die keine Changelog-Bullets sind (Absatz/Überschrift/Zitat) - kommen bei
    /// reinen CHANGELOG.md-Releases praktisch nie vor, sollen bei einem händisch
    /// abweichenden Release-Text aber nicht stillschweigend verschwinden.
    private var nonListBlocks: [ReaderContentBlock] {
        blocks.filter {
            if case .listItem = $0 { return false }
            return true
        }
    }

    /// Changelog-Bullets, gruppiert per UpdateReleaseNoteCategorizer und in fester
    /// Kategorie-Reihenfolge (Neu -> Design -> Fehlerbehebungen -> ... -> Sonstiges).
    /// Nur Kategorien mit mindestens einem Eintrag werden gerendert.
    private var categorizedGroups: [(category: UpdateReleaseNoteCategory, items: [[ReaderInlineRun]])] {
        var itemsByCategory: [UpdateReleaseNoteCategory: [[ReaderInlineRun]]] = [:]

        for block in blocks {
            guard case .listItem(let runs) = block else { continue }
            let (category, displayRuns) = UpdateReleaseNoteCategorizer.categorize(runs)
            itemsByCategory[category, default: []].append(displayRuns)
        }

        return UpdateReleaseNoteCategory.allCases.compactMap { category in
            guard let items = itemsByCategory[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    var body: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            header(theme: theme)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ReaderContentBlockEntry.entries(from: nonListBlocks)) { entry in
                        releaseNoteBlock(entry.block, theme: theme)
                    }

                    ForEach(Array(categorizedGroups.enumerated()), id: \.offset) { _, group in
                        categorySection(group.category, items: group.items, theme: theme)
                    }
                }
                .padding(20)
            }

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            footer(theme: theme)
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 360, idealHeight: 460)
        .background(theme.bg)
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    private func header(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.updateCheckAvailableTitle(tagName: release.tagName))
                .font(.system(size: 18, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(theme.text)

            if let name = release.name, !name.isEmpty {
                Text(name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.text2)
            }

            // Nutzerwunsch: installierte Version rot (veraltet), gefolgt
            // von der neuen, verfügbaren Version - Pendant zur grünen
            // Anzeige im "Kein Update"-Dialog (FeedivoApp.swift/
            // AboutSettingsView.swift). Farben jetzt aus RuleDialogTheme
            // statt hartcodiertem .red, damit sie zum Rest der App passen.
            (
                Text(L10n.updateCheckInstalledLabelPrefix)
                    .foregroundColor(theme.text2)
                    + Text(installedVersion).foregroundColor(theme.destructiveText).fontWeight(.semibold)
                    + Text(verbatim: " → ").foregroundColor(theme.text2)
                    + Text(release.tagName).foregroundColor(theme.accent).fontWeight(.semibold)
            )
            .font(.system(size: 12.5))
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private func categorySection(
        _ category: UpdateReleaseNoteCategory,
        items: [[ReaderInlineRun]],
        theme: RuleDialogTheme
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(category.titleKey)
                    .font(.system(size: 12.5, weight: .bold))
            } icon: {
                Image(systemName: category.systemImage)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(theme.text2)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, runs in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•")
                            .foregroundStyle(theme.text2)
                        Text(runs.attributedString(colorScheme: colorScheme))
                            .font(.system(size: 13))
                            .foregroundStyle(theme.text)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func footer(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // .idle/.checking/.upToDate treten praktisch nie auf, während dieses Sheet
            // sichtbar ist (FeedivoApp.swift präsentiert es nur für .updateAvailable bis
            // .installing, siehe SparkleUpdatePresentationModifier) - rein defensiv für
            // Exhaustivität und den `coordinator == nil`-Fallback (?? .idle) mitbehandelt.
            // .updateAvailable selbst braucht keinen eigenen Statustext, der Download-Button
            // in footerButtons() trägt die eigentliche Handlung.
            switch coordinator?.state ?? .idle {
            case .idle, .checking, .updateAvailable, .upToDate:
                EmptyView()
            case .downloading(let fraction, let downloaded, let total):
                downloadProgressView(fraction: fraction, downloaded: downloaded, total: total, theme: theme)
            case .extracting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.updateCheckVerifyingLabel)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.text2)
                }
            case .readyToInstall:
                Text(L10n.updateCheckReadyToInstallMessage)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.updateCheckInstallingLabel)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.text2)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.destructiveText)

                    Button(L10n.updateCheckOpenOnGitHubButton) {
                        onOpenOnGitHub()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.linkText)
                }
            }

            HStack(spacing: 10) {
                // Korrektur nach Task-10-Review (Nutzerentscheid: umsetzen): ohne diesen
                // Button gäbe es in keinem Zustand mehr eine Möglichkeit, den Dialog zu
                // schließen, ohne den Download zu starten - onDismiss() wäre unerreichbar.
                // Bewusst nur in .idle/.checking/.updateAvailable/.upToDate/.failed sichtbar
                // (kein aktiver, unterbrechbarer Vorgang im SparkleUpdateCoordinator);
                // während .downloading übernimmt "Abbrechen" dieselbe Rolle,
                // .extracting/.installing/.readyToInstall sind bewusst kurze, nicht
                // abbrechbare Zwischenschritte.
                if showsDismissButton {
                    Button(L10n.updateCheckDismissButton) {
                        onDismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.text2)
                }

                Spacer(minLength: 0)
                footerButtons(theme: theme)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var showsDismissButton: Bool {
        switch coordinator?.state ?? .idle {
        case .idle, .checking, .updateAvailable, .upToDate, .failed:
            true
        default:
            false
        }
    }

    @ViewBuilder
    private func downloadProgressView(fraction: Double, downloaded: Int64, total: Int64, theme: RuleDialogTheme) -> some View {
        let formatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter
        }()

        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: fraction)
            Text(L10n.updateCheckDownloadProgress(
                percent: Int(fraction * 100),
                downloaded: formatter.string(fromByteCount: downloaded),
                total: formatter.string(fromByteCount: total)
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(theme.text2)
        }
    }

    @ViewBuilder
    private func footerButtons(theme: RuleDialogTheme) -> some View {
        switch coordinator?.state ?? .idle {
        case .idle, .checking:
            // Defensiver Fallback (coordinator == nil, oder state ist zwischen zwei
            // Vorgängen kurz auf .idle zurückgefallen) - startet einen frischen Check.
            RuleDialogButton(titleKey: L10n.updateCheckDownloadButton, style: .primary, theme: theme) {
                coordinator?.checkForUpdatesManually()
            }
        case .updateAvailable:
            // Löst Sparkles offene "Update gefunden"-Continuation auf (pendingUpdateChoice
            // in SparkleUpdateCoordinator) - genau das startet den eigentlichen Download,
            // NICHT ein erneuter checkForUpdatesManually()-Aufruf.
            RuleDialogButton(titleKey: L10n.updateCheckDownloadButton, style: .primary, theme: theme) {
                coordinator?.installUpdate()
            }
        case .downloading:
            RuleDialogButton(titleKey: L10n.commonCancel, style: .secondary, theme: theme) {
                coordinator?.cancelDownload()
            }
        case .extracting, .installing, .upToDate:
            EmptyView()
        case .readyToInstall:
            // Löst Sparkles offene "Bereit zur Installation"-Continuation auf
            // (pendingInstallChoice) - dieselbe installUpdate()-Methode wie oben,
            // SparkleUpdateCoordinator unterscheidet selbst anhand des gesetzten Pending-Feldes.
            RuleDialogButton(titleKey: L10n.updateCheckReadyToInstallButton, style: .primary, theme: theme) {
                coordinator?.installUpdate()
            }
        case .failed:
            // SparkleUpdateState.failed(String) unterscheidet nicht mehr zwischen
            // "Neu-Download nötig" und "Relaunch fehlgeschlagen" wie der alte,
            // eigene UpdateInstallError - ein einheitlicher Neuversuch per Check
            // ist der einzige noch sinnvolle nächste Schritt.
            RuleDialogButton(titleKey: L10n.updateCheckRetryButton, style: .primary, theme: theme) {
                coordinator?.checkForUpdatesManually()
            }
        }
    }

    @ViewBuilder
    private func releaseNoteBlock(_ block: ReaderContentBlock, theme: RuleDialogTheme) -> some View {
        switch block {
        case .paragraph(let runs):
            Text(runs.attributedString(colorScheme: colorScheme))
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
        case .heading(let runs):
            Text(runs.attributedString(colorScheme: colorScheme))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
        case .quote(let runs):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(theme.border)
                    .frame(width: 3)
                Text(runs.attributedString(colorScheme: colorScheme))
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(theme.text2)
            }
        case .listItem, .image:
            // Changelog-Bullets werden separat über categorizedGroups gerendert;
            // Release-Notes dieses Projekts sind reiner CHANGELOG-Text ohne Bilder.
            EmptyView()
        }
    }
}
