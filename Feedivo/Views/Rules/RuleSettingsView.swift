import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RuleSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Rule.sortOrder) private var rules: [Rule]
    @Query private var articles: [Article]

    @State private var viewModel = RuleViewModel()
    @State private var ruleEditing: Rule?
    @State private var isCreatingRule = false
    @State private var rulePendingDeletion: Rule?
    @State private var appliedExistingRuleActionCount: Int?
    @State private var draggedRuleID: UUID?

    init() {
        // Artikel ohne die großen content/offlineContent-Blobs laden — beim
        // Treffer-Zählen und Anwenden der Regeln wird nur title/summary/feed-Titel
        // sowie tags/isHidden gebraucht, nie der Volltext (P1).
        _articles = Query(Article.lightFetchDescriptor())
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
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isCreatingRule) {
            RuleWizardView()
        }
        .sheet(item: $ruleEditing) { rule in
            RuleWizardView(rule: rule)
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
                viewModel.deleteRule(rule, context: modelContext)
                rulePendingDeletion = nil
            }

            Button(L10n.commonCancel, role: .cancel) {
                rulePendingDeletion = nil
            }
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
        // Treffer pro Regel einmal pro Render berechnen (Map), statt pro Zeile
        // jeweils über alle Artikel zu iterieren (P2: N × O(articles) im ForEach).
        let matchingCounts = RuleSettingsFormatter.matchingCounts(for: orderedRules, articles: articles)

        return VStack(spacing: 0) {
            RuleSettingsListHeader()

            ForEach(Array(orderedRules.enumerated()), id: \.element.id) { index, rule in
                RuleSettingsRow(
                    rule: rule,
                    matchingArticleCount: matchingCounts[rule.id] ?? 0,
                    isDragged: draggedRuleID == rule.id,
                    isFirst: index == 0,
                    isLast: index == orderedRules.count - 1,
                    moveUp: { move(rule, direction: .up) },
                    moveDown: { move(rule, direction: .down) },
                    edit: { ruleEditing = rule },
                    duplicate: { duplicate(rule) },
                    delete: { rulePendingDeletion = rule }
                )
                .onDrag {
                    draggedRuleID = rule.id
                    return NSItemProvider(object: rule.id.uuidString as NSString)
                } preview: {
                    RuleDragPreview(rule: rule)
                }
                .onDrop(
                    of: [.text],
                    delegate: RuleRowDropDelegate(
                        targetRule: rule,
                        orderedRules: orderedRules,
                        draggedRuleID: $draggedRuleID,
                        viewModel: viewModel,
                        modelContext: modelContext
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

    private var orderedRules: [Rule] {
        RuleViewModel.sortedRules(rules)
    }

    private var canApplyRulesToExistingArticles: Bool {
        !articles.isEmpty && rules.contains { rule in
            rule.isEnabled
        }
    }

    private func applyRulesToExistingArticles() {
        let appliedActionCount = RuleEngine.applyRulesToExistingArticles(orderedRules, articles: articles)
        appliedExistingRuleActionCount = appliedActionCount

        if appliedActionCount > 0 {
            try? modelContext.save()
        }
    }

    private func move(_ rule: Rule, direction: RuleMoveDirection) {
        viewModel.moveRule(rule, direction: direction, existingRules: orderedRules, context: modelContext)
    }

    private func duplicate(_ rule: Rule) {
        viewModel.duplicateRule(rule, existingRules: orderedRules, context: modelContext)
    }
}

private struct RuleRowDropDelegate: DropDelegate {
    let targetRule: Rule
    let orderedRules: [Rule]
    @Binding var draggedRuleID: UUID?
    let viewModel: RuleViewModel
    let modelContext: ModelContext

    func validateDrop(info: DropInfo) -> Bool {
        draggedRuleID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggedRuleID,
              draggedRuleID != targetRule.id,
              let sourceRule = orderedRules.first(where: { $0.id == draggedRuleID })
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            viewModel.moveRule(
                sourceRule,
                toPositionOf: targetRule,
                existingRules: orderedRules,
                context: modelContext
            )
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
    @Environment(\.modelContext) private var modelContext

    let rule: Rule
    let matchingArticleCount: Int
    let isDragged: Bool
    let isFirst: Bool
    let isLast: Bool
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
                    rule.isEnabled = isEnabled
                    try? modelContext.save()
                }
            ))
            .labelsHidden()
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Text(RuleSettingsFormatter.conditionSummary(for: rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RuleActionPill(rule: rule)
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
    let rule: Rule

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
    let rule: Rule

    var body: some View {
        switch RuleAction.normalized(rule.actionRaw) {
        case .assignTag:
            if let tag = rule.assignTag {
                HStack(spacing: 6) {
                    Circle()
                        .fill(TagColorPalette.color(for: tag.colorHex))
                        .frame(width: 8, height: 8)

                    Text(tag.name)
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
    static func conditionSummary(for rule: Rule) -> String {
        let conditionDrafts = conditionDrafts(for: rule)
        guard !conditionDrafts.isEmpty else {
            return L10n.ruleSummaryNoCondition
        }

        let connector = RuleMatchMode.normalized(rule.conditionMatchMode) == .all ? L10n.ruleSummaryAll : L10n.ruleSummaryAny
        return conditionDrafts
            .map { draft in
                conditionDescription(draft)
            }
            .joined(separator: " \(connector) ")
    }

    static func matchingArticleCount(for rule: Rule, articles: [Article]) -> Int {
        RuleEngine.matchingArticleCount(
            conditionDrafts: conditionDrafts(for: rule),
            matchMode: RuleMatchMode.normalized(rule.conditionMatchMode),
            articles: articles
        )
    }

    /// Berechnet die Trefferzahl für alle Regeln in einem Durchlauf und liefert sie
    /// als Map `rule.id → Trefferzahl`. So wird pro Render nur einmal über die
    /// Artikel iteriert statt pro Regelzeile (P2: zuvor N × O(articles) im ForEach).
    static func matchingCounts(for rules: [Rule], articles: [Article]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for rule in rules {
            counts[rule.id] = matchingArticleCount(for: rule, articles: articles)
        }
        return counts
    }

    private static func conditionDrafts(for rule: Rule) -> [RuleConditionDraft] {
        rule.conditions
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
