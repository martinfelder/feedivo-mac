import SwiftUI

// Exakte Farb-Tokens aus RuleDialogCards.dc.html (Konzept A). Keine Werte
// aus dem System-Farbschema — der Dialog hat ein eigenes, festes Farbsystem
// für Light/Dark, das 1:1 dem Referenz-Prototyp entspricht.
struct RuleDialogTheme {
    let bg: Color
    let card: Color
    let card2: Color
    let text: Color
    let text2: Color
    let border: Color
    let accent: Color
    let track: Color
    let pill: Color
    let input: Color

    // Zusätzliche Tokens für den "Verwaltung"-Fensterrahmen (Sidebar/Fenster-Hintergrund
    // unterscheiden sich von der Dialog-Card-Optik oben) und für destruktive Aktionen
    // (Feeds/Regeln löschen), siehe design_handoff_verwaltung/README.md.
    let windowBg: Color
    let sidebarBg: Color
    let linkText: Color
    let tertiaryText: Color
    let destructiveText: Color
    let destructiveTint: Color
    let destructiveBorder: Color
    let selectionTint: Color

    static let switchOn = Color(hex: 0x34C759)
    static let thenBadgeText = Color(hex: 0x2FA84F)

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            bg = Color(hex: 0x28282B)
            card = Color(hex: 0x323235)
            card2 = Color(hex: 0x3A3A3D)
            text = Color(hex: 0xF5F5F7)
            text2 = Color(hex: 0x9A9AA0)
            border = Color.white.opacity(0.12)
            accent = Color(hex: 0x0A84FF)
            track = Color(hex: 0x48484B)
            pill = Color(hex: 0x6A6A6E)
            input = Color(hex: 0x1F1F22)
            windowBg = Color(hex: 0x1E1E20)
            sidebarBg = Color(hex: 0x2A2A2D)
            linkText = Color(hex: 0x6AB0FF)
            tertiaryText = Color(hex: 0x6A6A6E)
        } else {
            bg = Color(hex: 0xFFFFFF)
            card = Color(hex: 0xF5F5F7)
            card2 = Color(hex: 0xFFFFFF)
            text = Color(hex: 0x1D1D1F)
            text2 = Color(hex: 0x86868B)
            border = Color.black.opacity(0.10)
            accent = Color(hex: 0x0A84FF)
            track = Color(hex: 0xE9E9EB)
            pill = Color(hex: 0xFFFFFF)
            input = Color(hex: 0xFFFFFF)
            windowBg = Color(hex: 0xFFFFFF)
            sidebarBg = Color(hex: 0xFAFAFB)
            linkText = Color(hex: 0x5A5A5F)
            tertiaryText = Color(hex: 0xB8B8BD)
        }

        destructiveText = Color(hex: 0xD70015)
        destructiveTint = Color(hex: 0xFF453A).opacity(0.10)
        destructiveBorder = Color(hex: 0xFF453A).opacity(0.35)
        selectionTint = Color(hex: 0x0A84FF).opacity(0.05)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Marker-Protokoll für Typen, die in RuleSegmentedControl/RuleDialogSelectMenu
// verwendet werden dürfen (Regel- und Intelligenter-Ordner-Dialog teilen sich diese
// Bausteine, da beide Dialoge dieselbe Designsprache "Konzept A" nutzen).

protocol RuleSelectOption: Hashable {}

// MARK: - Segmented Control (macOS-Stil, weiße Pille)

struct RuleSegmentedControl<Option: RuleSelectOption>: View {
    let options: [(Option, LocalizedStringKey)]
    @Binding var selection: Option
    let theme: RuleDialogTheme
    var fullWidth = false
    var trackRadius: CGFloat = 8

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.0 == selection

                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? theme.text : theme.text2)
                        .padding(.horizontal, fullWidth ? 6 : 15)
                        .padding(.vertical, fullWidth ? 7 : 5)
                        .frame(maxWidth: fullWidth ? .infinity : nil)
                        .multilineTextAlignment(.center)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? theme.pill : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.black.opacity(isSelected ? 0.05 : 0), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(isSelected ? 0.14 : 0), radius: 1, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                .fill(theme.track)
        )
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

// MARK: - Text-Input im Dialog-Stil

struct RuleDialogTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let theme: RuleDialogTheme
    var horizontalPadding: CGFloat = 11
    var verticalPadding: CGFloat = 8
    var fontSize: CGFloat = 13

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize))
            .foregroundStyle(theme.text)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Auswahl-Menü (Feld/Operator) im Dialog-Stil

struct RuleDialogSelectMenu<Option: Hashable & RuleSelectOption>: View {
    @Binding var selection: Option
    let options: [Option]
    let titleKey: (Option) -> LocalizedStringKey
    let theme: RuleDialogTheme
    @State private var isExpanded = false

    var body: some View {
        Button {
            isExpanded = true
        } label: {
            HStack(spacing: 4) {
                Text(titleKey(selection))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("▾")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.text2)
            }
            .padding(.leading, 11)
            .padding(.trailing, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        // Eigenes Popover statt `Menu`/`Picker`: macOS erzwingt seit der
        // "Liquid Glass"-Systemoptik bei sichtbaren Menu-Controls immer die
        // native Pillen-Chrome (auch mit `.menuStyle(.borderlessButton)`),
        // und ein unsichtbarer Picker als Klick-Ziel im Hintergrund hat sein
        // eigenes AppKit-Hit-Testing, das die per SwiftUI gesetzte Frame-Größe
        // nicht übernimmt. Ein selbst gezeichnetes Popover umgeht beides.
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                        isExpanded = false
                    } label: {
                        Text(titleKey(option))
                            .font(.system(size: 13))
                            .foregroundStyle(theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                option == selection ? theme.card : Color.clear
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .frame(minWidth: 150)
            .background(theme.card2)
        }
    }
}

// MARK: - Checkbox (quadratisch, 18×18) — geteilt zwischen Intelligenter-Ordner-Dialog,
// Regel-Dialog und Verwaltung (Feeds-Auswahl, Sidebar-Sichtbarkeit, Regel-aktiv).

struct RuleDialogCheckbox: View {
    let isOn: Bool
    let theme: RuleDialogTheme

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isOn ? theme.accent : theme.input)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isOn ? theme.accent : theme.border, lineWidth: 1)
            )
            .overlay {
                if isOn {
                    Text("✓")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 18, height: 18)
            .shadow(color: isOn ? Color(hex: 0x0A84FF).opacity(0.4) : .black.opacity(0.04), radius: isOn ? 1 : 0.5, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.12), value: isOn)
    }
}

// MARK: - Button (secondary/primary/destructive) im Verwaltung/Dialog-Stil

enum RuleDialogButtonStyle {
    case secondary
    case primary
    /// `isActive` steuert die destruktive Einfärbung (z. B. nur wenn ≥1 Zeile ausgewählt ist);
    /// ohne aktive Auswahl sieht der Button wie ein neutraler, blasser Secondary-Button aus.
    case destructive(isActive: Bool)
}

struct RuleDialogButton: View {
    let titleKey: LocalizedStringKey
    let style: RuleDialogButtonStyle
    let theme: RuleDialogTheme
    var systemImage: String?
    /// Wird unlokalisiert direkt an den Titel angehängt, z. B. " (3)" für einen Auswahlzähler.
    var titleSuffix: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                HStack(spacing: 0) {
                    Text(titleKey)
                    if let titleSuffix {
                        Text(titleSuffix)
                    }
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: style.isPrimary ? 1.5 : 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var horizontalPadding: CGFloat {
        style.isPrimary ? 16 : 14
    }

    private var foregroundColor: Color {
        switch style {
        case .secondary:
            theme.text
        case .primary:
            .white
        case .destructive(let isActive):
            isActive ? theme.destructiveText : theme.text2
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .secondary:
            theme.card
        case .primary:
            theme.accent
        case .destructive(let isActive):
            isActive ? theme.destructiveTint : theme.card
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary:
            theme.border
        case .primary:
            .clear
        case .destructive(let isActive):
            isActive ? theme.destructiveBorder : theme.border
        }
    }

    private var shadowColor: Color {
        switch style {
        case .secondary, .destructive:
            Color.black.opacity(0.03)
        case .primary:
            theme.accent.opacity(0.45)
        }
    }
}

private extension RuleDialogButtonStyle {
    var isPrimary: Bool {
        if case .primary = self { return true }
        return false
    }
}

// MARK: - Farb-Swatches für Tags (geteilt zwischen Regel-Dialog-Tag-Erstellung und
// Tags-verwalten in der Verwaltung — Apple-System-Spec-Palette, siehe
// design_handoff_verwaltung/README.md → Tag/Swatch-Palette).

enum RuleDialogTagSwatches {
    static let colors = [
        "#0A84FF",
        "#30D158",
        "#FF9F0A",
        "#FF453A",
        "#BF5AF2",
        "#14B8A6",
        "#64748B"
    ]
}

// MARK: - Farb-Swatch (Kreis mit Doppelring bei Auswahl)

struct RuleColorSwatch: View {
    let colorHex: String
    let isSelected: Bool
    let theme: RuleDialogTheme
    var diameter: CGFloat = 22

    var body: some View {
        let color = TagColorPalette.color(for: colorHex)

        ZStack {
            if isSelected {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: diameter + 8, height: diameter + 8)
                Circle()
                    .stroke(theme.bg, lineWidth: 2)
                    .frame(width: diameter + 4, height: diameter + 4)
            }

            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter + 8, height: diameter + 8)
    }
}
