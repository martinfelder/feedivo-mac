import SwiftUI

private enum RuleWizardMode: String, CaseIterable, Identifiable {
    case simple
    case power

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .simple:
            L10n.ruleWizardModeSimple
        case .power:
            L10n.ruleWizardModePower
        }
    }
}

struct RuleWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    let rule: RuleRecord?
    let existingRules: [RuleRecord]

    @State private var tags: [TagRecord] = []
    @State private var mode: RuleWizardMode = .simple
    @State private var name = ""
    @State private var isEnabled = true
    @State private var action = RuleAction.assignTag
    @State private var matchMode = RuleMatchMode.all
    @State private var conditionDrafts = [
        RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")
    ]
    @State private var selectedTagID: String?
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.colors[0]
    @State private var notificationTemplate = "{Titel}"
    @State private var notificationPriority = RuleNotificationPriority.normal
    @State private var regexHelpDraftID: UUID?
    @State private var previewMatchingCount = 0
    @State private var ruleError: String?
    @State private var tagError: String?

    init(rule: RuleRecord? = nil, existingRules: [RuleRecord] = []) {
        self.rule = rule
        self.existingRules = existingRules
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            modePicker
            ruleBasics
            conditionsEditor
            rulePreview
            actionEditor
            if action == .assignTag {
                targetEditor
            }
            if action == .notify {
                notificationEditor
            }
            ruleErrorMessage
            footer
        }
        .padding(24)
        .frame(width: 640)
        .onAppear {
            loadInitialState()
        }
        .task {
            loadTags()
        }
        .task(id: previewReloadToken) {
            await reloadPreviewCount()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule == nil ? L10n.ruleWizardCreateTitle : L10n.ruleWizardEditTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.ruleWizardSummaryTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var modePicker: some View {
        Picker(L10n.ruleWizardModeTitle, selection: $mode) {
            ForEach(RuleWizardMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var ruleBasics: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.ruleWizardNamePlaceholder, text: $name)
                .textFieldStyle(.roundedBorder)

            Toggle(L10n.ruleEnabled, isOn: $isEnabled)

            if mode == .power {
                Picker(L10n.ruleWizardModeTitle, selection: $matchMode) {
                    ForEach(RuleMatchMode.allCases) { matchMode in
                        Text(matchMode.titleKey)
                            .tag(matchMode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var conditionsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.ruleWizardConditionsTitle)
                .font(.headline)

            ForEach($conditionDrafts) { $draft in
                HStack(alignment: .bottom, spacing: 8) {
                    Picker("", selection: $draft.field) {
                        ForEach(RuleConditionField.allCases) { field in
                            Text(field.titleKey)
                                .tag(field)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Picker("", selection: $draft.conditionOperator) {
                        ForEach(RuleConditionOperator.allCases) { conditionOperator in
                            Text(conditionOperator.titleKey)
                                .tag(conditionOperator)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    VStack(alignment: .trailing, spacing: 3) {
                        if draft.conditionOperator == .regex {
                            regexHelpButton(for: draft.id)
                        }

                        TextField(L10n.ruleWizardValuePlaceholder, text: $draft.value)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity)

                    if mode == .power && conditionDrafts.count > 1 {
                        Button {
                            removeCondition(draft)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.ruleWizardRemoveCondition)
                    }
                }
            }

            if mode == .power {
                Button {
                    conditionDrafts.append(
                        RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")
                    )
                } label: {
                    Label(L10n.ruleWizardAddCondition, systemImage: "plus")
                }
            }
        }
    }

    private func regexHelpButton(for draftID: UUID) -> some View {
        Button {
            regexHelpDraftID = draftID
        } label: {
            Text(L10n.ruleWizardRegexHelpButton)
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(L10n.ruleWizardRegexHelpButton)
        .popover(
            isPresented: Binding(
                get: { regexHelpDraftID == draftID },
                set: { isPresented in
                    regexHelpDraftID = isPresented ? draftID : nil
                }
            ),
            arrowEdge: .top
        ) {
            RegexHelpPopoverView()
        }
    }

    private var targetEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.ruleWizardTargetTitle)
                .font(.headline)

            Picker(L10n.ruleWizardExistingTag, selection: $selectedTagID) {
                Text(L10n.ruleWizardExistingTag)
                    .tag(Optional<String>.none)

                ForEach(tags) { tag in
                    Text(tag.name)
                        .tag(Optional(tag.id))
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 10) {
                TextField(L10n.ruleWizardNewTagName, text: $newTagName)
                    .textFieldStyle(.roundedBorder)

                ColorSwatchPicker(selection: $newTagColorHex)

                Button(L10n.commonAdd) {
                    createTag()
                }
                .disabled(TagViewModel.normalizedTagName(newTagName) == nil)
            }

            if let errorMessage = tagError {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var actionEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.ruleWizardActionTitle)
                .font(.headline)

            Picker(L10n.ruleWizardActionTitle, selection: $action) {
                ForEach(RuleAction.allCases) { action in
                    Text(action.titleKey)
                        .tag(action)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var notificationEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.ruleWizardNotificationTitle)
                .font(.headline)

            TextField(L10n.ruleWizardNotificationTemplate, text: $notificationTemplate)
                .textFieldStyle(.roundedBorder)

            Text(L10n.ruleWizardNotificationTemplateHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(L10n.ruleWizardNotificationPriority, selection: $notificationPriority) {
                ForEach(RuleNotificationPriority.allCases) { priority in
                    Text(priority.titleKey)
                        .tag(priority)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var ruleErrorMessage: some View {
        if let errorMessage = ruleError {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private var rulePreview: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: previewHasConditions ? "scope" : "exclamationmark.circle")
                .foregroundStyle(previewHasConditions ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.ruleWizardPreviewTitle)
                    .font(.headline)

                Text(previewDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button(L10n.commonCancel) {
                dismiss()
            }

            Button(L10n.ruleWizardSave) {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var selectedTag: TagRecord? {
        guard let selectedTagID else {
            return nil
        }

        return tags.first { $0.id == selectedTagID }
    }

    private var activeConditionDrafts: [RuleConditionDraft] {
        mode == .simple ? Array(conditionDrafts.prefix(1)) : conditionDrafts
    }

    private var activeMatchMode: RuleMatchMode {
        mode == .simple ? .all : matchMode
    }

    private var previewHasConditions: Bool {
        activeConditionDrafts.contains { draft in
            !draft.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var previewDescription: String {
        guard previewHasConditions else {
            return String(localized: "ruleWizard.preview.noConditions")
        }

        return L10n.ruleWizardPreviewMatchCount(count: previewMatchingCount)
    }

    private var previewReloadToken: String {
        let conditionToken = activeConditionDrafts
            .map { draft in
                "\(draft.field.rawValue):\(draft.conditionOperator.rawValue):\(draft.value)"
            }
            .joined(separator: "|")
        return "\(activeMatchMode.rawValue)|\(conditionToken)"
    }

    private func loadInitialState() {
        if let rule {
            load(rule)
        }
    }

    private func load(_ rule: RuleRecord) {
        name = rule.name
        isEnabled = rule.isEnabled
        action = RuleAction.normalized(rule.action)
        matchMode = RuleMatchMode.normalized(rule.matchMode)

        if let database = feedivoDatabase {
            let conditions = (try? SQLiteRuleStore(database: database).conditions(ruleID: rule.id)) ?? []
            conditionDrafts = RuleSettingsFormatter.conditionDrafts(for: conditions)
        }

        if conditionDrafts.isEmpty {
            conditionDrafts = [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")
            ]
        }

        selectedTagID = rule.assignTagID
        notificationTemplate = rule.notificationTemplate
        notificationPriority = RuleNotificationPriority.normalized(rule.notificationPriority)
        mode = conditionDrafts.count > 1 ? .power : .simple
    }

    private func removeCondition(_ draft: RuleConditionDraft) {
        conditionDrafts.removeAll { $0.id == draft.id }
    }

    private func createTag() {
        guard let database = feedivoDatabase else {
            tagError = L10n.feedPropertiesUnavailable
            return
        }

        guard let normalizedName = normalizedTagName(newTagName) else {
            tagError = L10n.tagManagerEmptyNameError
            return
        }

        do {
            let tag = TagRecord(
                id: UUID().uuidString,
                name: normalizedName,
                colorHex: newTagColorHex
            )
            try TagStore(database: database).save(tag)
            loadTags()
            selectedTagID = tag.id
            newTagName = ""
            tagError = nil
        } catch TagStore.TagStoreError.duplicateName {
            tagError = L10n.tagManagerDuplicateNameError
        } catch {
            tagError = error.localizedDescription
        }
    }

    private func reloadPreviewCount() async {
        guard previewHasConditions,
              let database = feedivoDatabase
        else {
            previewMatchingCount = 0
            return
        }

        do {
            previewMatchingCount = try SQLiteRuleEvaluationStore(database: database).matchingArticleCount(
                conditionDrafts: activeConditionDrafts,
                matchMode: activeMatchMode
            )
        } catch {
            previewMatchingCount = 0
        }
    }

    private func save() {
        guard let database = feedivoDatabase else {
            ruleError = L10n.feedPropertiesUnavailable
            return
        }

        let drafts = mode == .simple ? Array(conditionDrafts.prefix(1)) : conditionDrafts
        let normalizedDrafts = drafts.compactMap { draft -> RuleConditionDraft? in
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return RuleConditionDraft(
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: value
            )
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !normalizedDrafts.isEmpty,
              action != .assignTag || selectedTag != nil
        else {
            ruleError = L10n.ruleValidationError
            return
        }

        let ruleID = rule?.id ?? UUID().uuidString
        let sortOrder = rule?.sortOrder ?? ((existingRules.map(\.sortOrder).max() ?? -1) + 1)
        let record = RuleRecord(
            id: ruleID,
            name: trimmedName,
            isEnabled: isEnabled,
            matchMode: activeMatchMode.rawValue,
            action: action.rawValue,
            assignTagID: action == .assignTag ? selectedTagID : nil,
            notificationTemplate: notificationTemplate,
            notificationPriority: notificationPriority.rawValue,
            sortOrder: sortOrder,
            createdAt: rule?.createdAt ?? Date()
        )
        let conditions = normalizedDrafts.enumerated().map { index, draft in
            RuleConditionRecord(
                id: UUID().uuidString,
                ruleID: ruleID,
                field: draft.field.rawValue,
                conditionOperator: draft.conditionOperator.rawValue,
                value: draft.value,
                sortOrder: index
            )
        }

        do {
            try SQLiteRuleStore(database: database).save(record, conditions: conditions)
            ruleError = nil
            dismiss()
        } catch {
            ruleError = error.localizedDescription
        }
    }

    private func loadTags() {
        guard let database = feedivoDatabase else {
            tags = []
            return
        }

        tags = (try? TagStore(database: database).tags()) ?? []
    }

    private func normalizedTagName(_ rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

private struct RegexHelpPopoverView: View {
    private let rows: [(pattern: String, explanation: LocalizedStringKey)] = [
        (".", L10n.ruleWizardRegexHelpDot),
        (".*", L10n.ruleWizardRegexHelpAny),
        ("\\d", L10n.ruleWizardRegexHelpDigit),
        ("\\s", L10n.ruleWizardRegexHelpWhitespace),
        ("^", L10n.ruleWizardRegexHelpStart),
        ("$", L10n.ruleWizardRegexHelpEnd)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.ruleWizardRegexHelpTitle)
                .font(.headline)

            Text(L10n.ruleWizardRegexHelpIntro)
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.pattern) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.pattern)
                            .font(.system(.callout, design: .monospaced))
                            .frame(width: 34, alignment: .leading)

                        Text(row.explanation)
                            .font(.callout)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.ruleWizardRegexHelpExamplesTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(L10n.ruleWizardRegexHelpExampleSwift)
                    .font(.callout)

                Text(L10n.ruleWizardRegexHelpExampleBreaking)
                    .font(.callout)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
