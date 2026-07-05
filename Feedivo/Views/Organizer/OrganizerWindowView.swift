import SwiftUI

struct OrganizerWindowView: View {
    static let windowID = "feedivo-organizer-window"
    static let windowTitle = String(localized: "Verwaltung")

    @State private var selectedSection = OrganizerSection.feeds

    var body: some View {
        NavigationSplitView {
            List(OrganizerSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                organizerContent
                    .frame(maxWidth: 720, alignment: .topLeading)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private var organizerContent: some View {
        switch selectedSection {
        case .feeds:
            FeedManagementOrganizerView()
        case .tags:
            TagManagerView(showsDoneButton: false)
        case .smartFolders:
            OrganizerSectionContainer(
                title: "Intelligente Ordner",
                description: "Reihenfolge, Sichtbarkeit und Bedingungen der Seitenleisten-Ordner verwalten."
            ) {
                SmartFolderSettingsView()
            }
        case .rules:
            OrganizerSectionContainer(
                title: L10n.settingsRulesSection,
                description: L10n.ruleSettingsDescription
            ) {
                RuleSettingsView()
            }
        }
    }
}

private enum OrganizerSection: String, CaseIterable, Identifiable {
    case feeds
    case tags
    case smartFolders
    case rules

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .feeds:
            L10n.settingsFeedsSection
        case .tags:
            L10n.tagManagerTitle
        case .smartFolders:
            "Intelligente Ordner"
        case .rules:
            L10n.settingsRulesSection
        }
    }

    var systemImage: String {
        switch self {
        case .feeds:
            "dot.radiowaves.left.and.right"
        case .tags:
            "tag"
        case .smartFolders:
            "folder.badge.gearshape"
        case .rules:
            "sparkles"
        }
    }
}

struct OrganizerSectionContainer<Content: View>: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OrganizerSectionHeader(title: title, description: description)
            content
        }
    }
}

struct OrganizerSectionHeader: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}
