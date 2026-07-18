import Foundation
import SwiftUI

/// Persistierte Reihenfolge und Sichtbarkeit der Reader-Toolbar-Icons
/// (Feature 19.4 "Toolbar anpassen"). Wird — analog zu
/// `KeyboardShortcutOverrides` — als JSON-codierter String in einem
/// einzigen `@AppStorage`-Key abgelegt statt in vielen Einzel-Keys.
struct ReaderToolbarLayout: Equatable {
    private struct StoredLayout: Codable {
        var order: [String]
        var hidden: [String]
    }

    var order: [String]
    var hiddenItemIDs: Set<String>

    init(
        order: [String] = ReaderToolbarItem.allCases.map(\.rawValue),
        hiddenItemIDs: Set<String> = []
    ) {
        self.order = order
        self.hiddenItemIDs = hiddenItemIDs
    }

    static let storageKey = "readerToolbarLayout"

    static func resolved(from rawValue: String) -> ReaderToolbarLayout {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(StoredLayout.self, from: data)
        else {
            return ReaderToolbarLayout()
        }

        return ReaderToolbarLayout(order: decoded.order, hiddenItemIDs: Set(decoded.hidden))
            .normalized()
    }

    static func resetToDefault() -> ReaderToolbarLayout {
        ReaderToolbarLayout()
    }

    var rawValue: String {
        let stored = StoredLayout(order: order, hidden: Array(hiddenItemIDs))
        guard let data = try? JSONEncoder().encode(stored),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }

    /// Alle Items in gespeicherter Reihenfolge inkl. ausgeblendeter — Grundlage
    /// für die Einstellungen-Liste, in der auch ausgeblendete Items sichtbar
    /// bleiben müssen, damit sie wieder eingeblendet werden können.
    var orderedItems: [ReaderToolbarItem] {
        order.compactMap { ReaderToolbarItem(rawValue: $0) }
    }

    /// Nur sichtbare Items in Reihenfolge — Grundlage für das tatsächliche
    /// Toolbar-Rendering in `SQLiteReaderView`.
    var visibleOrderedItems: [ReaderToolbarItem] {
        orderedItems.filter { !hiddenItemIDs.contains($0.rawValue) }
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var items = order
        items.move(fromOffsets: source, toOffset: destination)
        order = items
    }

    mutating func setHidden(_ isHidden: Bool, for item: ReaderToolbarItem) {
        if isHidden {
            hiddenItemIDs.insert(item.rawValue)
        } else {
            hiddenItemIDs.remove(item.rawValue)
        }
    }

    /// Hängt `ReaderToolbarItem`-Fälle, die noch nicht in `order` stehen (z. B.
    /// ein künftig neu hinzugefügtes Toolbar-Icon bei einem Bestandsnutzer),
    /// sichtbar ans Ende an, und entfernt unbekannte/veraltete Einträge aus
    /// `order` (z. B. ein in einer späteren Version wieder entferntes Icon).
    private func normalized() -> ReaderToolbarLayout {
        let knownRawValues = Set(ReaderToolbarItem.allCases.map(\.rawValue))
        var normalizedOrder = order.filter { knownRawValues.contains($0) }
        let present = Set(normalizedOrder)
        let missing = ReaderToolbarItem.allCases.map(\.rawValue).filter { !present.contains($0) }
        normalizedOrder.append(contentsOf: missing)

        return ReaderToolbarLayout(order: normalizedOrder, hiddenItemIDs: hiddenItemIDs)
    }
}
