// Feedivo/Views/Settings/AboutSettingsView.swift
import AppKit
import SwiftUI

/// Settings-Tab "Über": App-Icon, Version, manueller Update-Check-Button und
/// ein Schalter für den automatischen Sparkle-Check. Seit der Umstellung auf
/// Sparkles eigenen `SPUStandardUserDriver` (2026-08-02, analog NetNewsWire)
/// zeigt Sparkle Fortschritt/Ergebnis eines Checks in seinen EIGENEN nativen
/// Fenstern - diese View hält deshalb bewusst keinen lokalen "wird gerade
/// geprüft"/"Update gefunden"-Zustand mehr (kein Spinner, kein Badge).
struct AboutSettingsView: View {
    @Environment(\.sparkleUpdateCoordinator) private var coordinator

    @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)
    private var isAutomaticCheckEnabled = UpdateCheckSettings.defaultIsAutomaticCheckEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingsSection(label: Text(L10n.settingsAboutSection) + Text(":")) {
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

                Toggle(isOn: $isAutomaticCheckEnabled) {
                    Text(L10n.updateCheckAutomaticCheckTitle)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .tint(Color.settingsBoldAccent)
                .onChange(of: isAutomaticCheckEnabled) { _, newValue in
                    coordinator?.setAutomaticChecksEnabled(newValue)
                }
                GeneralSettingsHelp(L10n.updateCheckAutomaticCheckDescription)

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
                    Button(L10n.updateCheckMenuItem) {
                        coordinator?.checkForUpdatesManually()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
