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

/// Ordnet eine Changelog-Zeile (CHANGELOG.md-Bullet, 1:1 aus einer Commit-Message
/// übernommen, siehe scripts/bump_version.sh) anhand ihres "Wort: "-Präfixes einer
/// `UpdateReleaseNoteCategory` zu. Der Präfix folgt der in diesem Projekt etablierten
/// Commit-Konvention (siehe `git log`: "Feat:", "Fix:", "Design:", "Refactor:",
/// "Text:", "Docs:", "chore:") - unbekannte oder fehlende Präfixe landen bewusst in
/// `.other` statt zu crashen, damit ein Ausreißer-Commit die Anzeige nie sprengt.
enum UpdateReleaseNoteCategorizer {
    private static let prefixMapping: [String: UpdateReleaseNoteCategory] = [
        "feat": .feature,
        "design": .design,
        "fix": .fix,
        "refactor": .refactor,
        "text": .text,
        "docs": .docs,
        "chore": .other
    ]

    /// Liefert die erkannte Kategorie sowie die Anzeige-Runs OHNE den Präfix
    /// (z. B. "Design: Einheitliches Blau..." -> "Einheitliches Blau..."), damit der
    /// Präfix nicht doppelt erscheint (einmal als Gruppen-Icon/-Titel, einmal als Text).
    static func categorize(_ runs: [ReaderInlineRun]) -> (category: UpdateReleaseNoteCategory, displayRuns: [ReaderInlineRun]) {
        guard let firstRun = runs.first,
              let colonIndex = firstRun.text.firstIndex(of: ":") else {
            return (.other, runs)
        }

        let prefix = firstRun.text[firstRun.text.startIndex..<colonIndex].lowercased()
        guard let category = prefixMapping[prefix] else {
            return (.other, runs)
        }

        var remainder = String(firstRun.text[firstRun.text.index(after: colonIndex)...])
        while remainder.first == " " {
            remainder.removeFirst()
        }

        var displayRuns = runs
        if remainder.isEmpty {
            displayRuns.removeFirst()
        } else {
            displayRuns[0] = ReaderInlineRun(
                text: remainder,
                isBold: firstRun.isBold,
                isItalic: firstRun.isItalic,
                linkURL: firstRun.linkURL,
                colorHex: firstRun.colorHex
            )
        }

        return (category, displayRuns)
    }
}
