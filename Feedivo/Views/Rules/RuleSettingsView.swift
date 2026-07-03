import SwiftUI
import UniformTypeIdentifiers

struct RuleSettingsView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    @State private var rules: [RuleRecord] = []
    @State private var conditionsByRuleID: [String: [RuleConditionRecord]] = [:]
    @State private var tagsByID: [String: TagRecord] = [:]
    @State private var ruleEditing: RuleRecord?
    @State private var isCreatingRule = false
    @State private var rulePendingDeletion: RuleRecord?
    @State private var appliedExistingRuleActionCount: Int?
    @State private var draggedRuleID: String?
    @State private var matchingCounts: [String: Int] = [:]
    @State private var reloadVersion = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if orderedRules.isEmpty {
                ContentUnavailableView(L10n.ruleNoRules, systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ruleList
            }

            if let appliedExistingRuleActionCount {
                Text(L10n.ruleApplyExistingResult(count: appliedExistingRuleActionCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isCreatingRule, onDismiss: refreshRules) {
            RuleWizardView(existingRules: rules)
        }
        .sheet(item: $ruleEditing, onDismiss: refreshRules) { rule in
            RuleWizardView(rule: rule, existingRules: rules)
        }
        .confirmationDialog(
            L10n.ruleDeleteButton,
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        rulePendingDeletion = nil
                    }
                }
            ),
            presenting: rulePendingDeletion
        ) { rule in
            Button(L10n.ruleDeleteButton, role: .destructive) {
                delete(rule)
                rulePendingDeletion = nil
            }

            Button(L10n.commonCancel, role: .cancel) {
                rulePendingDeletion = nil
            }
        }
        .task(id: reloadVersion) {
            loadRules()
        }
        .task(id: matchingCountsReloadToken) {
            await reloadMatchingCounts()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.settingsRulesSection)
                    .font(.headline)

                Text(L10n.ruleSettingsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                applyRulesToExistingArticles()
            } label: {
                Label(L10n.ruleApplyExistingButton, systemImage: "play.circle")
            }
            .disabled(!canApplyRulesToExistingArticles)

            Button {
                isCreatingRule = true
            } label: {
                Label(L10n.ruleCreateButton, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var ruleList: some View {
        VStack(spacing: 0) {
            RuleSettingsListHeader()

            ForEach(Array(orderedRules.enumerated()), id: \.element.id) { index, rule in
                RuleSettingsRow(
                    rule: rule,
                    matchingArticleCount: matchingCounts[rule.id] ?? 0,
                    isDragged: draggedRuleID == rule.id,
                    isFirst: index == 0,
                    isLast: index == orderedRules.count - 1,
                    conditions: conditionsByRuleID[rule.id] ?? [],
                    assignTag: rule.assignTagID.flatMap { tagsByID[$0] },
                    toggleEnabled: { isEnabled in
                        updateEnabled(rule, isEnabled: isEnabled)
                    },
                    moveUp: { move(rule, direction: .up) },
                    moveDown: { move(rule, direction: .down) },
                    edit: { ruleEditing = rule },
                    duplicate: { duplicate(rule) },
                    delete: { rulePendingDeletion = rule }
                )
                .onDrag {
                    draggedRuleID = rule.id
                    return NSItemProvider(object: rule.id as NSString)
                } preview: {
                    RuleDragPreview(rule: rule)
                }
                .onDrop(
                    of: [.text],
                    delegate: RuleRowDropDelegate(
                        targetRule: rule,
                        orderedRules: orderedRules,
                        draggedRuleID: $draggedRuleID,
                        move: moveRule
                    )
                )

                if index < orderedRules.count - 1 {
                    Divider()
                        .padding(.leading, 82)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var orderedRules: [RuleRecord] {
        rules.sorted { firstRule, secondRule in
            if firstRule.sortOrder != secondRule.sortOrder {
                return firstRule.sortOrder < secondRule.sortOrder
            }

            return firstRule.name.localizedCaseInsensitiveCompare(secondRule.name) == .orderedAscending
        }
    }

    private var canApplyRulesToExistingArticles: Bool {
        feedivoDatabase != nil && rules.contains { $0.isEnabled }
    }

    private func applyRulesToExistingArticles() {
        guard let database = feedivoDatabase else {
            appliedExistingRuleActionCount = 0
            return
        }

        do {
            let snapshots = try SQLiteRuleStore(database: database).ruleSnapshots()
            let appliedActionCount = try SQLiteRuleEvaluationStore(database: database)
                .applyRulesToExistingArticles(snapshots)
            appliedExistingRuleActionCount = appliedActionCount
        } catch {
            appliedExistingRuleActionCount = 0
        }
    }

    private var matchingCountsReloadToken: String {
        orderedRules
            .map { rule in
                let conditionToken = (conditionsByRuleID[rule.id] ?? [])
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map { "\($0.field):\($0.conditionOperator):\($0.value):\($0.sortOrder)" }
                    .joined(separator: ",")
                return "\(rule.id):\(rule.isEnabled):\(rule.matchMode):\(rule.action):\(rule.sortOrder):\(conditionToken)"
            }
            .joined(separator: "|")
    }

    private func loadRules() {
        guard let database = feedivoDatabase else {
            rules = []
            conditionsByRuleID = [:]
            tagsByID = [:]
            return
        }

        let ruleStore = SQLiteRuleStore(database: database)
        let loadedRules = (try? ruleStore.rules()) ?? []
        var loadedConditions: [String: [RuleConditionRecord]] = [:]
        for rule in loadedRules {
            loadedConditions[rule.id] = (try? ruleStore.conditions(ruleID: rule.id)) ?? []
        }

        let tags = (try? TagStore(database: database).tags()) ?? []
        rules = loadedRules
        conditionsByRuleID = loadedConditions
        tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    }

    private func refreshRules() {
        reloadVersion += 1
    }

    private func reloadMatchingCounts() async {
        guard let database = feedivoDatabase else {
            matchingCounts = [:]
            return
        }

        let store = SQLiteRuleEvaluationStore(database: database)
        var counts: [String: Int] = [:]

        for rule in orderedRules {
            let drafts = RuleSettingsFormatter.conditionDrafts(
                for: conditionsByRuleID[rule.id] ?? []
            )

            counts[rule.id] = (try? store.matchingArticleCount(
                conditionDrafts: drafts,
                matchMode: RuleMatchMode.normalized(rule.matchMode)
            )) ?? 0
        }

        matchingCounts = counts
    }

    private func move(_ rule: RuleRecord, direction: RuleMoveDirection) {
        guard let index = orderedRules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }

        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = index - 1
        case .down:
            targetIndex = index + 1
        }

        guard orderedRules.indices.contains(targetIndex) else {
            return
        }

        moveRule(rule.id, orderedRules[targetIndex].id)
    }

    private func duplicate(_ rule: RuleRecord) {
        guard let database = feedivoDatabase else {
            return
        }

        _ = try? SQLiteRuleStore(database: database).duplicate(
            id: rule.id,
            copyName: "\(rule.name) Kopie"
        )
        refreshRules()
    }

    private func delete(_ rule: RuleRecord) {
        guard let database = feedivoDatabase else {
            return
        }

        try? SQLiteRuleStore(database: database).delete(id: rule.id)
        refreshRules()
    }

    private func updateEnabled(_ rule: RuleRecord, isEnabled: Bool) {
        guard let database = feedivoDatabase else {
            return
        }

        try? SQLiteRuleStore(database: database).updateEnabled(id: rule.id, isEnabled: isEnabled)
        refreshRules()
    }

    private func moveRule(_ sourceID: String, _ targetID: String) {
        guard let database = feedivoDatabase else {
            return
        }

        try? SQLiteRuleStore(database: database).move(id: sourceID, toPositionOf: targetID)
        refreshRules()
    }
}

private struct RuleRowDropDelegate: DropDelegate {
    let targetRule: RuleRecord
    let orderedRules: [RuleRecord]
    @Binding var draggedRuleID: String?
    let move: (String, String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedRuleID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggedRuleID,
              draggedRuleID != targetRule.id,
              orderedRules.contains(where: { $0.id == draggedRuleID })
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            move(draggedRuleID, targetRule.id)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedRuleID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

private struct RuleSettingsListHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.ruleListHeaderOrder)
                .frame(width: 78, alignment: .leading)
            Text(L10n.ruleListHeaderActive)
                .frame(width: 44, alignment: .leading)
            Text(L10n.ruleListHeaderRule)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.ruleListHeaderAction)
                .frame(width: 150, alignment: .leading)
            Text(L10n.ruleListHeaderMatches)
                .frame(width: 72, alignment: .trailing)
            Text("")
                .frame(width: 82)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct RuleSettingsRow: View {
    let rule: RuleRecord
    let matchingArticleCount: Int
    let isDragged: Bool
    let isFirst: Bool
    let isLast: Bool
    let conditions: [RuleConditionRecord]
    let assignTag: TagRecord?
    let toggleEnabled: (Bool) -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            orderControls

            Toggle(L10n.ruleEnabled, isOn: Binding(
                get: { rule.isEnabled },
                set: { isEnabled in
                    toggleEnabled(isEnabled)
                }
            ))
            .labelsHidden()
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Text(RuleSettingsFormatter.conditionSummary(for: rule, conditions: conditions))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RuleActionPill(rule: rule, assignTag: assignTag)
                .frame(width: 150, alignment: .leading)

            Text("\(matchingArticleCount)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            HStack(spacing: 6) {
                Button(action: edit) {
                    Image(systemName: "pencil")
                }
                .help(L10n.ruleEditButton)

                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .help(L10n.ruleDeleteButton)
            }
            .buttonStyle(.borderless)
            .frame(width: 82, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .opacity(isDragged ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button(L10n.ruleEditButton, action: edit)
            Button(L10n.commonDuplicate, action: duplicate)
            Divider()
            Button(L10n.ruleDeleteButton, role: .destructive, action: delete)
        }
    }

    private var orderControls: some View {
        HStack(spacing: 3) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)

            VStack(spacing: 0) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(isFirst)
                .help(L10n.ruleMoveUp)

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(isLast)
                .help(L10n.ruleMoveDown)
            }
            .buttonStyle(.borderless)
        }
        .frame(width: 78, alignment: .leading)
        .help(L10n.smartFolderDragToSort)
    }
}

private struct RuleDragPreview: View {
    let rule: RuleRecord

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)

            Text(rule.name)
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RuleActionPill: View {
    let rule: RuleRecord
    let assignTag: TagRecord?

    var body: some View {
        switch RuleAction.normalized(rule.action) {
        case .assignTag:
            if let assignTag {
                HStack(spacing: 6) {
                    Circle()
                        .fill(TagColorPalette.color(for: assignTag.colorHex))
                        .frame(width: 8, height: 8)

                    Text(assignTag.name)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
            } else {
                Text(L10n.ruleActionMissingTag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .hideArticle:
            Label(L10n.ruleActionHideArticle, systemImage: "eye.slash")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.14), in: Capsule())
        case .notify:
            Label(L10n.ruleActionNotify, systemImage: "bell.badge")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.14), in: Capsule())
        }
    }
}

enum RuleSettingsFormatter {
    static func conditionSummary(
        for rule: RuleRecord,
        conditions: [RuleConditionRecord]
    ) -> String {
        let conditionDrafts = conditionDrafts(for: conditions)
        guard !conditionDrafts.isEmpty else {
            return L10n.ruleSummaryNoCondition
        }

        let connector = RuleMatchMode.normalized(rule.matchMode) == .all ? L10n.ruleSummaryAll : L10n.ruleSummaryAny
        return conditionDrafts
            .map { draft in
                conditionDescription(draft)
            }
            .joined(separator: " \(connector) ")
    }

    static func conditionDrafts(for conditions: [RuleConditionRecord]) -> [RuleConditionDraft] {
        conditions
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { condition -> RuleConditionDraft? in
                guard let field = RuleConditionField(rawValue: condition.field),
                      let conditionOperator = RuleConditionOperator(rawValue: condition.conditionOperator)
                else {
                    return nil
                }

                return RuleConditionDraft(
                    field: field,
                    conditionOperator: conditionOperator,
                    value: condition.value
                )
        }
    }

    private static func conditionDescription(_ draft: RuleConditionDraft) -> String {
        let field = fieldTitle(draft.field)
        let conditionOperator = operatorTitle(draft.conditionOperator)
        return "\(field) \(conditionOperator) \"\(draft.value)\""
    }

    private static func fieldTitle(_ field: RuleConditionField) -> String {
        switch field {
        case .title:
            return L10n.ruleFieldTitle
        case .summary:
            return L10n.ruleFieldSummary
        case .feedTitle:
            return L10n.ruleFieldFeedTitle
        }
    }

    private static func operatorTitle(_ conditionOperator: RuleConditionOperator) -> String {
        switch conditionOperator {
        case .contains:
            return L10n.ruleOperatorContains
        case .startsWith:
            return L10n.ruleOperatorStartsWith
        case .endsWith:
            return L10n.ruleOperatorEndsWith
        case .regex:
            return L10n.ruleOperatorRegex
        }
    }
}
