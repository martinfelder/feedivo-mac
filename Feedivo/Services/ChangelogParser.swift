import Foundation

/// Ein einzelner Versions-Eintrag aus CHANGELOG.md.
struct ChangelogEntry: Equatable {
    let version: String
    let date: String
    let bullets: [String]
}

/// Parst den Markdown-Text von CHANGELOG.md in strukturierte Versions-Einträge.
/// Erwartetes Format (siehe CHANGELOG.md): `## [Version] - Datum`-Überschriften,
/// gefolgt von `- `-Aufzählungspunkten, die über mehrere Zeilen umbrechen können
/// (Fortsetzungszeilen ohne "- "-Präfix werden an den letzten Punkt angehängt, da
/// CHANGELOG.md lange Sätze für die Lesbarkeit im Markdown-Quelltext umbricht).
enum ChangelogParser {
    static func parse(_ markdown: String) -> [ChangelogEntry] {
        var entries: [ChangelogEntry] = []
        var currentVersion: String?
        var currentDate: String?
        var currentBullets: [String] = []

        func flushCurrentEntry() {
            guard let version = currentVersion, let date = currentDate else { return }
            entries.append(ChangelogEntry(version: version, date: date, bullets: currentBullets))
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if rawLine.hasPrefix("## [") {
                if let heading = parseHeading(rawLine) {
                    flushCurrentEntry()
                    currentVersion = heading.version
                    currentDate = heading.date
                    currentBullets = []
                }
                // Ein nicht erkanntes Überschriftenformat wird übersprungen, darf aber
                // nicht als Fortsetzungszeile eines Bullets missverstanden werden -
                // deshalb eigener Zweig mit "continue", kein Fallthrough unten.
                continue
            }

            if trimmed.hasPrefix("- "), currentVersion != nil {
                currentBullets.append(String(trimmed.dropFirst(2)))
            } else if !trimmed.isEmpty, currentVersion != nil, !currentBullets.isEmpty {
                let lastIndex = currentBullets.count - 1
                currentBullets[lastIndex] += " " + trimmed
            }
        }
        flushCurrentEntry()

        return entries
    }

    /// Erwartet `## [Version] - Datum`, z. B. `## [1.0 (28)] - 2026-08-07`.
    private static func parseHeading(_ line: String) -> (version: String, date: String)? {
        guard let openBracket = line.firstIndex(of: "["),
              let closeBracket = line.firstIndex(of: "]"),
              openBracket < closeBracket else {
            return nil
        }
        let version = String(line[line.index(after: openBracket)..<closeBracket])

        let afterBracket = line[line.index(after: closeBracket)...]
        guard let dashRange = afterBracket.range(of: "- ") else {
            return nil
        }
        let date = afterBracket[dashRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !date.isEmpty else { return nil }

        return (version, date)
    }
}
