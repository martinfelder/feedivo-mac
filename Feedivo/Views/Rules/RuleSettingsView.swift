import SwiftData
import SwiftUI

struct RuleSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Rule.name) private var rules: [Rule]

    @State private var viewModel = RuleViewModel()
    @State private var ruleEditing: Rule?
    @State private var isCreatingRule = false
    @State private var rulePendingDeletion: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.settingsRulesSection)
                    .font(.headline)

                Spacer()

                Button(L10n.ruleCreateButton) {
                    isCreatingRule = true
                }
            }

            if rules.isEmpty {
                ContentUnavailableView(L10n.ruleNoRules, systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(rules) { rule in
                    RuleSettingsRow(
                        rule: rule,
                        edit: { ruleEditing = rule },
                        delete: { rulePendingDeletion = rule }
                    )
                    Divider()
                }
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
}

private struct RuleSettingsRow: View {
    @Environment(\.modelContext) private var modelContext

    let rule: Rule
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(L10n.ruleEnabled, isOn: Binding(
                get: { rule.isEnabled },
                set: { isEnabled in
                    rule.isEnabled = isEnabled
                    try? modelContext.save()
                }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.body)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L10n.ruleEditButton, action: edit)

            Button(L10n.ruleDeleteButton, role: .destructive, action: delete)
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        let mode = RuleMatchMode.normalized(rule.conditionMatchMode) == .all ? "AND" : "OR"
        let tagName = rule.assignTag?.name ?? "-"
        return "\(rule.conditions.count) Bedingungen · \(mode) · Tag: \(tagName)"
    }
}
