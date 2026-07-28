import Foundation
import Testing
@testable import Feedivo

struct RuleConditionGroupLayoutTests {
    @Test func groupedDraftIDsGruppiertNachGroupIndexInReihenfolgeDesErstenAuftretens() {
        let draftA = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A", groupIndex: 1)
        let draftB = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B", groupIndex: 0)
        let draftC = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "C", groupIndex: 1)

        let groups = RuleConditionGroupLayout.groupedDraftIDs([draftA, draftB, draftC])

        // Gruppe 1 (draftA) taucht zuerst im Array auf, daher zuerst in der
        // Ausgabe -- unabhaengig vom numerischen Wert des groupIndex.
        #expect(groups == [[draftA.id, draftC.id], [draftB.id]])
    }

    @Test func groupedDraftIDsLiefertLeeresArrayFuerLeereEingabe() {
        #expect(RuleConditionGroupLayout.groupedDraftIDs([]).isEmpty)
    }

    @Test func nextGroupIndexLiefertMaxPlusEins() {
        let drafts = [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A", groupIndex: 0),
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B", groupIndex: 3)
        ]

        #expect(RuleConditionGroupLayout.nextGroupIndex(in: drafts) == 4)
    }

    @Test func nextGroupIndexLiefertNullBeiLeererListe() {
        #expect(RuleConditionGroupLayout.nextGroupIndex(in: []) == 0)
    }

    @Test func removingConditionEntferntNurDieBedingungMitDieserID() {
        let draftA = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A", groupIndex: 0)
        let draftB = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B", groupIndex: 0)

        let result = RuleConditionGroupLayout.removingCondition(id: draftA.id, from: [draftA, draftB])

        #expect(result.map(\.id) == [draftB.id])
    }

    @Test func removingConditionEntferntAutomatischDieGruppeWennLetzteBedingungEntfernt() {
        let draftA = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A", groupIndex: 0)
        let draftB = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B", groupIndex: 1)

        let result = RuleConditionGroupLayout.removingCondition(id: draftA.id, from: [draftA, draftB])
        let groups = RuleConditionGroupLayout.groupedDraftIDs(result)

        // Gruppe 0 hatte nur draftA -- nach dem Entfernen bleibt genau eine
        // Gruppe (Gruppe 1) uebrig, keine leere Box.
        #expect(groups == [[draftB.id]])
    }

    @Test func removingGroupEntferntAlleBedingungenDieserGruppe() {
        let draftA = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A", groupIndex: 0)
        let draftB = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B", groupIndex: 0)
        let draftC = RuleConditionDraft(field: .title, conditionOperator: .contains, value: "C", groupIndex: 1)

        let result = RuleConditionGroupLayout.removingGroup(0, from: [draftA, draftB, draftC])

        #expect(result.map(\.id) == [draftC.id])
    }
}
