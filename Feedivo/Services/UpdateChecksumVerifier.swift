import Foundation
import CryptoKit

/// Reine, zustandslose SHA256-Prüfsummen-Logik für heruntergeladene Update-Assets.
/// Kein eigenes I/O - Daten/Hex-Strings kommen von außen (siehe UpdateInstaller).
enum UpdateChecksumVerifier {
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Vergleicht zwei Hex-Strings tolerant gegenüber Groß-/Kleinschreibung und
    /// umgebendem Whitespace (`.sha256`-Textdateien enthalten oft ein
    /// abschließendes Newline).
    static func matches(computedHex: String, expectedHex: String) -> Bool {
        normalized(computedHex) == normalized(expectedHex)
    }

    private static func normalized(_ hex: String) -> String {
        hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
