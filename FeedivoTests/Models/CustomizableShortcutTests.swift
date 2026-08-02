import Testing

@testable import Feedivo

struct CustomizableShortcutTests {
    @Test func neueTabShortcutsGehoerenZurReaderKategorie() {
        #expect(CustomizableShortcut.readerNewTab.category == .reader)
        #expect(CustomizableShortcut.readerCloseTab.category == .reader)
        #expect(CustomizableShortcut.readerNextTab.category == .reader)
        #expect(CustomizableShortcut.readerPreviousTab.category == .reader)
    }

    @Test func neueTabShortcutsHabenErwarteteDefaults() {
        #expect(CustomizableShortcut.readerNewTab.defaultSpec == KeyboardShortcutSpec(key: "t", modifiers: [.command]))
        #expect(CustomizableShortcut.readerCloseTab.defaultSpec == KeyboardShortcutSpec(key: "w", modifiers: [.command]))
        #expect(CustomizableShortcut.readerNextTab.defaultSpec == KeyboardShortcutSpec(key: "]", modifiers: [.command, .shift]))
        #expect(CustomizableShortcut.readerPreviousTab.defaultSpec == KeyboardShortcutSpec(key: "[", modifiers: [.command, .shift]))
    }
}
