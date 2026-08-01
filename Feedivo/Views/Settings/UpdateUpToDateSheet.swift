import SwiftUI

/// Zeigt "Kein Update verfügbar" mit der installierten Version (grün, da
/// bestätigt aktuell).
///
/// Eigene View statt `.alert()`: macOS' `.alert()` wird intern über
/// `NSAlert` gerendert, dessen `informativeText` reinen Plain-Text
/// erwartet — jede `.foregroundColor`/`.fontWeight`-Modifikation auf
/// `Text`-Segmenten innerhalb des `message:`-Closures wird dabei
/// stillschweigend ignoriert (Nutzer-Report 2026-07-31: grüne Version blieb
/// trotz korrektem Text-Konkatenations-Code unfarbig). Ein eigenes Sheet
/// (wie das bereits bestehende `UpdateAvailableSheet`) rendert echtes
/// SwiftUI und respektiert Farb-Modifikatoren.
///
/// Zeigt seit der Sparkle-Umstellung (Task 9) keine zweite Zeile mit einer
/// "zuletzt bekannten Version" mehr - Sparkles `showUpdateNotFoundWithError`
/// liefert dafür keinen Wert mehr (das war eine GitHub-API-Spezialität des
/// entfernten UpdateChecker-Stacks).
struct UpdateUpToDateSheet: View {
    let installedVersion: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.updateCheckUpToDateTitle)
                .font(.system(size: 15, weight: .semibold))

            (
                Text(L10n.updateCheckInstalledLabelPrefix)
                    + Text(installedVersion).foregroundColor(.green).fontWeight(.semibold)
            )
            .font(.system(size: 13))

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
