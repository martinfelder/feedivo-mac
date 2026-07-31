// Feedivo/Views/Settings/AboutSettingsView.swift
import AppKit
import SwiftUI

/// Neuer Settings-Tab "Über": App-Icon, Version, manueller Update-Check-
/// Button und ein Schalter für den stillen Start-Check. Ruft denselben
/// stateless UpdateChecker wie das App-Menü auf, hält aber bewusst eigenen,
/// lokalen Präsentationszustand (siehe Abweichung von der Spec im Plan-Header) -
/// vermeidet, dass ein hier ausgelöster Check gleichzeitig im Hauptfenster
/// ein Sheet öffnet, falls beide Fenster offen sind.
struct AboutSettingsView: View {
    @AppStorage(UpdateCheckSettings.isAutomaticCheckEnabledKey)
    private var isAutomaticCheckEnabled = UpdateCheckSettings.defaultIsAutomaticCheckEnabled

    @AppStorage(UpdateCheckSettings.hasUnseenUpdateKey)
    private var hasUnseenUpdate = UpdateCheckSettings.defaultHasUnseenUpdate

    @State private var isChecking = false
    @State private var releasePresentation: GitHubRelease?
    @State private var showsUpToDateAlert = false
    @State private var errorMessage: String?

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
                }

                HStack(spacing: 8) {
                    Button(isChecking ? L10n.updateCheckCheckingButton : L10n.updateCheckMenuItem) {
                        performCheck()
                    }
                    .disabled(isChecking)

                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
        }
        .sheet(item: $releasePresentation) { release in
            UpdateAvailableSheet(
                release: release,
                onOpenOnGitHub: { NSWorkspace.shared.open(release.htmlURL) },
                onDismiss: { releasePresentation = nil }
            )
        }
        .alert(L10n.updateCheckUpToDateTitle, isPresented: $showsUpToDateAlert) {
            Button(L10n.commonOK, role: .cancel) {}
        }
        .alert(
            L10n.updateCheckErrorTitle,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.commonOK, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func performCheck() {
        hasUnseenUpdate = false
        isChecking = true
        Task {
            let outcome = await UpdateChecker().check(
                currentMarketingVersion: AppVersionInfo.marketingVersion,
                currentBuildNumber: AppVersionInfo.buildNumber
            )
            isChecking = false
            switch outcome {
            case .updateAvailable(let release):
                releasePresentation = release
            case .upToDate:
                showsUpToDateAlert = true
            case .failed(let message):
                errorMessage = message
            }
        }
    }
}
