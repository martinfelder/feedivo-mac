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
        }
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
