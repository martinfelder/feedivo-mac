import SwiftUI

/// Zeigt "Kein Update verfügbar" mit installierter Version (grün, da
/// bestätigt aktuell) und der zuletzt auf GitHub gefundenen Version als
/// zweite Zeile.
///
/// Eigene View statt `.alert()`: macOS' `.alert()` wird intern über
/// `NSAlert` gerendert, dessen `informativeText` reinen Plain-Text
/// erwartet — jede `.foregroundColor`/`.fontWeight`-Modifikation auf
/// `Text`-Segmenten innerhalb des `message:`-Closures wird dabei
/// stillschweigend ignoriert (Nutzer-Report 2026-07-31: grüne Version blieb
/// trotz korrektem Text-Konkatenations-Code unfarbig). Ein eigenes Sheet
/// (wie das bereits bestehende `UpdateAvailableSheet`) rendert echtes
/// SwiftUI und respektiert Farb-Modifikatoren.
struct UpdateUpToDateSheet: View {
    let installedVersion: String
    let latestKnownRelease: GitHubRelease?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.updateCheckUpToDateTitle)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                (
                    Text(L10n.updateCheckInstalledLabelPrefix)
                        + Text(installedVersion).foregroundColor(.green).fontWeight(.semibold)
                )
                .font(.system(size: 13))

                // Ohne Antwort von GitHub (leere Release-Liste) ist die installierte
                // Version selbst der beste bekannte Wert - kein Fehlertext, da das
                // kein Problem, sondern nur eine fehlende Information ist.
                Text(L10n.updateCheckLatestAvailableLabel(tagName: latestKnownRelease?.tagName ?? installedVersion))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(L10n.commonOK) {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 140)
    }
}
