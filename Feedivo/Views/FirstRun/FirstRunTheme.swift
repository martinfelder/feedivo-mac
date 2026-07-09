import SwiftUI

// Eigenes Dark-Mode-Farbschema für den First-Run-Assistenten, analog zu
// RuleDialogTheme (Verwaltung-Dialoge). Der Assistent hat einen bewusst
// hellen "Frosted-Glass"-Look (transluzente helle Karten auf einem
// Verlauf) — reines Color.white funktioniert dafür nur im Light Mode. Im
// Dark Mode braucht dieselbe Kartenoptik einen dunklen, leicht
// aufgehellten Ton statt striktem Weiss, sonst bleiben die Karten
// hell-verwaschene Fremdkörper auf dunklem Grund.
struct FirstRunTheme {
    let card: Color
    let dropZoneBackground: Color
    let accentStroke: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            // Startwerte für die visuelle Abstimmung in Step 12 — die Spec
            // hat die exakten Dark-Töne bewusst offengelassen ("passt so",
            // Wahl erfolgt beim Umsetzen per Screenshot-Vergleich). Diese
            // Werte sind ein plausibler Ausgangspunkt, kein Endergebnis.
            card = Color(hex: 0x3A3A3D)
            dropZoneBackground = Color(hex: 0x223244)
            accentStroke = Color(hex: 0x6AB0FF)
        } else {
            card = Color.white
            dropZoneBackground = Color(red: 0.94, green: 0.97, blue: 1.0)
            accentStroke = Color(red: 0.18, green: 0.44, blue: 0.78)
        }
    }
}
