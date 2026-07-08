import SwiftUI

struct OrganizerWindowView: View {
    static let windowID = "feedivo-organizer-window"
    static let windowTitle = String(localized: "Verwaltung")

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSection = OrganizerSection.feeds

    private var theme: RuleDialogTheme {
        RuleDialogTheme(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationSplitView {
            List(OrganizerSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .font(.system(size: 14))
                    .tag(section)
            }
            .scrollContentBackground(.hidden)
            .background(theme.sidebarBg)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 0) {
                toolbar

                ScrollView {
                    organizerContent
                        .frame(maxWidth: 720, alignment: .topLeading)
                        .padding(.horizontal, 34)
                        .padding(.top, 30)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(theme.windowBg)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Self.windowTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(theme.text)

                Spacer()
            }
            .padding(.horizontal, 26)
            .frame(height: 52)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
        }
        .background(theme.windowBg)
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
    @Environment(\.colorScheme) private var colorScheme

    let title: LocalizedStringKey
    let description: LocalizedStringKey

    private var theme: RuleDialogTheme {
        RuleDialogTheme(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 23, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(theme.text)

            Text(description)
                .font(.system(size: 13.5))
                .foregroundStyle(theme.text2)
        }
        .padding(.bottom, 8)
    }
}
