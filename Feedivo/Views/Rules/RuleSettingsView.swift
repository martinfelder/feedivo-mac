import SwiftUI
import UniformTypeIdentifiers

struct RuleSettingsView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme

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

    private var theme: RuleDialogTheme {
        RuleDialogTheme(colorScheme: colorScheme)
    }

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
                    .foregroundStyle(theme.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.settingsRulesSection)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.text)

                Text(L10n.ruleSettingsDescription)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RuleDialogButton(
                titleKey: L10n.ruleApplyExistingButton,
                style: .secondary,
                theme: theme,
                systemImage: "play.circle"
            ) {
                applyRulesToExistingArticles()
            }
            .disabled(!canApplyRulesToExistingArticles)
            .opacity(canApplyRulesToExistingArticles ? 1 : 0.45)

            RuleDialogButton(
                titleKey: L10n.ruleCreateButton,
                style: .primary,
                theme: theme,
                systemImage: "plus"
            ) {
                isCreatingRule = true
            }
        }
    }

    private var ruleList: some View {
        VStack(spacing: 0) {
            RuleSettingsListHeader(theme: theme)

            ForEach(Array(orderedRules.enumerated()), id: \.element.id) { index, rule in
                RuleSettingsRow(
                    rule: rule,
                    matchingArticleCount: matchingCounts[rule.id] ?? 0,
                    isDragged: draggedRuleID == rule.id,
                    isFirst: index == 0,
                    isLast: index == orderedRules.count - 1,
                    conditions: conditionsByRuleID[rule.id] ?? [],
                    assignTag: rule.assignTagID.flatMap { tagsByID[$0] },
                    theme: theme,
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
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

        let tags = TagStore.tagsIgnoringErrors(database: database)
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
    let theme: RuleDialogTheme

    var body: some View {
        HStack(spacing: 14) {
            Text(L10n.ruleListHeaderOrder)
                .frame(width: 92, alignment: .leading)
            Text(L10n.ruleListHeaderActive)
                .frame(width: 58, alignment: .leading)
            Text(L10n.ruleListHeaderRule)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.ruleListHeaderAction)
                .frame(width: 150, alignment: .leading)
            Text(L10n.ruleListHeaderMatches)
                .frame(width: 74, alignment: .trailing)
            Text("")
                .frame(width: 70)
        }
        .font(.system(size: 11, weight: .bold))
        .tracking(0.4)
        .textCase(.uppercase)
        .foregroundStyle(theme.text2)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(theme.card)
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
    let theme: RuleDialogTheme
    let toggleEnabled: (Bool) -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            orderControls

            Button {
                toggleEnabled(!rule.isEnabled)
            } label: {
                RuleDialogCheckbox(isOn: rule.isEnabled, theme: theme)
            }
            .buttonStyle(.plain)
            .help(L10n.ruleEnabled)
            .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(RuleSettingsFormatter.conditionSummary(for: rule, conditions: conditions))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text2)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RuleActionPill(rule: rule, assignTag: assignTag, theme: theme)
                .fixedSize()
                .frame(minWidth: 150, alignment: .leading)

            Text("\(matchingArticleCount)")
                .font(.system(size: 13.5).monospacedDigit())
                .foregroundStyle(theme.text2)
                .frame(width: 74, alignment: .trailing)

            HStack(spacing: 6) {
                Button(action: edit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text2)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(L10n.ruleEditButton)

                Button(action: delete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text2)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(L10n.ruleDeleteButton)
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)

            VStack(spacing: 0) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .disabled(isFirst)
                .help(L10n.ruleMoveUp)

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .disabled(isLast)
                .help(L10n.ruleMoveDown)
            }
        }
        .frame(width: 92, alignment: .leading)
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
    let theme: RuleDialogTheme

    var body: some View {
        switch RuleAction.normalized(rule.action) {
        case .assignTag:
            if let assignTag {
                HStack(spacing: 9) {
                    Circle()
                        .fill(TagColorPalette.color(for: assignTag.colorHex))
                        .frame(width: 9, height: 9)

                    Text(assignTag.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.card2, in: Capsule())
                .overlay(Capsule().stroke(theme.border, lineWidth: 1))
            } else {
                Text(L10n.ruleActionMissingTag)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text2)
            }
        case .hideArticle:
            Label {
                Text(L10n.ruleActionHideArticle)
            } icon: {
                Image(systemName: "eye.slash")
                    .font(.system(size: 14))
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Color(hex: 0xB25C00))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: 0xFF9500).opacity(0.16), in: Capsule())
        case .notify:
            Label {
                Text(L10n.ruleActionNotify)
            } icon: {
                Image(systemName: "bell.badge")
                    .font(.system(size: 14))
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(theme.accent.opacity(0.14), in: Capsule())
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
        case .author:
            return L10n.ruleFieldAuthor
        case .link:
            return L10n.ruleFieldLink
        case .feedTitle:
            return L10n.ruleFieldFeedTitle
        }
    }

    private static func operatorTitle(_ conditionOperator: RuleConditionOperator) -> String {
        switch conditionOperator {
        case .contains:
            return L10n.ruleOperatorContains
        case .notContains:
            return L10n.ruleOperatorNotContains
        case .equals:
            return L10n.ruleOperatorEquals
        case .startsWith:
            return L10n.ruleOperatorStartsWith
        case .endsWith:
            return L10n.ruleOperatorEndsWith
        case .regex:
            return L10n.ruleOperatorRegex
        }
    }
}
