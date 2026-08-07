import SwiftUI

/// Anzeige-Kategorie für eine einzelne Changelog-Zeile im "Update verfügbar"-Dialog.
/// `allCases`-Reihenfolge bestimmt gleichzeitig die Anzeigereihenfolge der Gruppen
/// (Neuerungen zuerst, interne Aufräumarbeiten zuletzt).
enum UpdateReleaseNoteCategory: CaseIterable {
    case feature
    case design
    case fix
    case refactor
    case text
    case docs
    case other

    var titleKey: LocalizedStringKey {
        switch self {
        case .feature: L10n.updateCheckCategoryFeature
        case .design: L10n.updateCheckCategoryDesign
        case .fix: L10n.updateCheckCategoryFix
        case .refactor: L10n.updateCheckCategoryRefactor
        case .text: L10n.updateCheckCategoryText
        case .docs: L10n.updateCheckCategoryDocs
        case .other: L10n.updateCheckCategoryOther
        }
    }

    var systemImage: String {
        switch self {
        case .feature: "sparkles"
        case .design: "paintbrush"
        case .fix: "wrench.and.screwdriver"
        case .refactor: "arrow.triangle.2.circlepath"
        case .text: "textformat"
        case .docs: "doc.text"
        case .other: "gearshape"
        }
    }
}

/// Ordnet eine Changelog-Zeile (CHANGELOG.md-Bullet) anhand ihres "Wort: "-Präfixes
/// einer `UpdateReleaseNoteCategory` zu. Deckt sowohl die rohen, englischen
/// Commit-Präfixe ab (siehe `git log`: "Feat:", "Fix:", "Design:", "Refactor:",
/// "Text:", "Docs:", "chore:", "test:") als auch die deutschen, in einfache Sprache
/// umformulierten Präfixe, die CHANGELOG.md nach einem manuellen Nachtrags-Commit
/// enthält ("Neu:", "Verbesserung:", "Fehlerbehebung:", "Cleanup:") - ein Eintrag
/// landet je nach Bearbeitungsstand mit dem einen oder anderen Präfix im Changelog,
/// beide müssen zur selben Kategorie führen. Unbekannte oder fehlende Präfixe landen
/// bewusst in `.other` statt zu crashen, damit ein Ausreißer-Eintrag die Anzeige nie
/// sprengt.
enum UpdateReleaseNoteCategorizer {
    private static let prefixMapping: [String: UpdateReleaseNoteCategory] = [
        "feat": .feature,
        "neu": .feature,
        "verbesserung": .feature,
        "design": .design,
        "fix": .fix,
        "fehlerbehebung": .fix,
        "refactor": .refactor,
        "cleanup": .refactor,
        "text": .text,
        "docs": .docs,
        "chore": .other,
        "test": .other
    ]

    /// Liefert die erkannte Kategorie sowie die Anzeige-Runs OHNE den Präfix
    /// (z. B. "Design: Einheitliches Blau..." -> "Einheitliches Blau..."), damit der
    /// Präfix nicht doppelt erscheint (einmal als Gruppen-Icon/-Titel, einmal als Text).
    static func categorize(_ runs: [ReaderInlineRun]) -> (category: UpdateReleaseNoteCategory, displayRuns: [ReaderInlineRun]) {
        guard let firstRun = runs.first,
              let match = match(firstRun.text) else {
            return (.other, runs)
        }

        var displayRuns = runs
        if match.remainder.isEmpty {
            displayRuns.removeFirst()
        } else {
            displayRuns[0] = ReaderInlineRun(
                text: match.remainder,
                isBold: firstRun.isBold,
                isItalic: firstRun.isItalic,
                linkURL: firstRun.linkURL,
                colorHex: firstRun.colorHex
            )
        }

        return (match.category, displayRuns)
    }

    /// Plain-Text-Pendant zu `categorize(_ runs:)` für einfache Bullet-Strings (z. B.
    /// `ChangelogEntry.bullets`, die keine Rich-Text-Formatierung tragen).
    static func categorize(_ text: String) -> (category: UpdateReleaseNoteCategory, displayText: String) {
        guard let match = match(text) else {
            return (.other, text)
        }
        return (match.category, match.remainder)
    }

    private static func match(_ text: String) -> (category: UpdateReleaseNoteCategory, remainder: String)? {
        guard let colonIndex = text.firstIndex(of: ":") else {
            return nil
        }

        let prefix = text[text.startIndex..<colonIndex].lowercased()
        guard let category = prefixMapping[prefix] else {
            return nil
        }

        var remainder = String(text[text.index(after: colonIndex)...])
        while remainder.first == " " {
            remainder.removeFirst()
        }

        return (category, remainder)
    }
}
