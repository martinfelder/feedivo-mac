// Feedivo/Views/Settings/AboutSettingsView.swift
import AppKit
import SwiftUI

/// Neuer Settings-Tab "Über": App-Icon, Version, manueller Update-Check-
/// Button und ein Schalter für den automatischen Sparkle-Check. Liest den
/// Update-Zustand direkt aus dem zentralen SparkleUpdateCoordinator (Environment,
/// Task 7/8) statt eigenen lokalen Präsentationszustand zu halten - Sheet-/
/// Alert-Präsentation läuft seit Task 8 zentral über FeedivoApp.swift
/// (SparkleUpdatePresentationModifier), damit nicht zwei unabhängige
/// Präsentationsorte um denselben Coordinator-State konkurrieren.
struct AboutSettingsView: View {
    @Environment(\.sparkleUpdateCoordinator) private var coordinator

    @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)
    private var isAutomaticCheckEnabled = UpdateCheckSettings.defaultIsAutomaticCheckEnabled

    private var isChecking: Bool {
        coordinator?.state == .checking
    }

    private var hasUnseenUpdate: Bool {
        coordinator?.hasUnseenUpdate ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: L10n.settingsAboutSection) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Feedivo")
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.updateCheckVersionLabel(
                            marketingVersion: AppVersionInfo.marketingVersion,
                            buildNumber: AppVersionInfo.buildNumber
                        ))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)

                SettingRow(
                    title: L10n.updateCheckAutomaticCheckTitle,
                    description: L10n.updateCheckAutomaticCheckDescription
                ) {
                    Toggle("", isOn: $isAutomaticCheckEnabled)
                        .labelsHidden()
                        .onChange(of: isAutomaticCheckEnabled) { _, newValue in
                            coordinator?.setAutomaticChecksEnabled(newValue)
                        }
                }

                if coordinator?.isHomebrewInstall == true {
                    // Bei Homebrew-Installationen bleibt SPUUpdater komplett inaktiv
                    // (siehe SparkleUpdateCoordinator.start()) - ein Such-Button hätte
                    // hier keine Wirkung, Updates laufen ausschließlich über
                    // `brew upgrade --cask feedivo`.
                    Text(L10n.updateCheckHomebrewHint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    HStack(spacing: 8) {
                        Button(isChecking ? L10n.updateCheckCheckingButton : L10n.updateCheckMenuItem) {
                            coordinator?.checkForUpdatesManually()
                        }
                        .disabled(isChecking)

                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else if hasUnseenUpdate {
                            // Ersetzt den ursprünglich im App-Menü geplanten "•"-Präfix am
                            // Menü-Titel (siehe Kommentar in FeedivoApp.swift) — ein
                            // dynamischer NSMenu-Titel löste dort einen AppKit-Absturz aus.
                            // Als reine SwiftUI-View ist dieses Badge hier unkritisch, da es
                            // kein NSMenu-Item-Array live umbaut.
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                Text(L10n.updateCheckPendingBadge)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
