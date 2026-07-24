import Foundation

/// Rein logische Gruppierungs-Operationen auf einer flachen Liste von
/// RuleConditionDraft fuer den Power-User-Modus des Regel-Assistenten
/// (RuleWizardView). Bewusst als reine, view-freie Funktionen ausgelagert
/// (Muster wie SidebarFeedOrder.swift/ReaderArrowKeyNavigation.swift in
/// diesem Projekt) -- testbar ohne SwiftUI-Rendering.
enum RuleConditionGroupLayout {
    /// Gruppiert Bedingungen nach groupIndex. Die aeussere Reihenfolge der
    /// Gruppen richtet sich nach dem ersten Auftreten eines groupIndex im
    /// Ursprungsarray (nicht nach dem numerischen Wert), damit eine neu per
    /// "+ ODER-Gruppe hinzufuegen" angehaengte Gruppe stets am Ende
    /// erscheint. Jede innere Liste behaelt die relative Reihenfolge ihrer
    /// Bedingungen im Ursprungsarray.
    static func groupedDraftIDs(_ drafts: [RuleConditionDraft]) -> [[UUID]] {
        var groupOrder: [Int] = []
        var idsByGroup: [Int: [UUID]] = [:]

        for draft in drafts {
            if idsByGroup[draft.groupIndex] == nil {
                idsByGroup[draft.groupIndex] = []
                groupOrder.append(draft.groupIndex)
            }
            idsByGroup[draft.groupIndex, default: []].append(draft.id)
        }

        return groupOrder.map { idsByGroup[$0] ?? [] }
    }

    /// Naechster, garantiert unbenutzter groupIndex fuer eine neue Gruppe.
    static func nextGroupIndex(in drafts: [RuleConditionDraft]) -> Int {
        (drafts.map(\.groupIndex).max() ?? -1) + 1
    }

    /// Entfernt eine einzelne Bedingung. War sie die letzte ihrer Gruppe,
    /// verschwindet die Gruppe dadurch automatisch aus groupedDraftIDs --
    /// kein Zustand mit einer leeren Box moeglich.
    static func removingCondition(id: UUID, from drafts: [RuleConditionDraft]) -> [RuleConditionDraft] {
        drafts.filter { $0.id != id }
    }

    /// Entfernt eine komplette Gruppe samt aller ihrer Bedingungen.
    static func removingGroup(_ groupIndex: Int, from drafts: [RuleConditionDraft]) -> [RuleConditionDraft] {
        drafts.filter { $0.groupIndex != groupIndex }
    }
}
