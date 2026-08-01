import Foundation

/// Reiner Wertetyp für ein Sparkle-Appcast-Item, so wie ihn die UI
/// (UpdateAvailableSheet, UpdateUpToDateSheet) konsumiert - absichtlich ohne
/// Sparkle-Import, damit die UI nicht direkt von SUAppcastItem abhängt
/// (Snapshot-Pattern-Konvention, siehe CLAUDE.md "Kernarchitektur").
struct SparkleReleaseInfo: Equatable, Sendable, Identifiable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let bodyHTML: String?

    var id: String { tagName }
}
