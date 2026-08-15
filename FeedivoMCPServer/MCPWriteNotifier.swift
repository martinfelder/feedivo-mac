import Foundation

/// Postet eine Darwin-Notification nach jedem erfolgreichen Schreib-Tool-Aufruf, damit eine
/// ggf. laufende Feedivo-App ihre UI aktualisiert — siehe Feedivo/Services/MCPWriteObserver.swift
/// (Empfänger-Seite) für die volle Erklärung, warum Darwin Notifications statt regulärem
/// NotificationCenter genutzt werden (funktioniert prozess-/sandbox-übergreifend ohne App Group).
enum MCPWriteNotifier {
    /// Namen aller Tools, nach deren erfolgreichem Aufruf main.swift notifyDidWrite() auslöst.
    static let writeToolNames: Set<String> = ["update_article_status", "assign_tag", "remove_tag"]

    static func notifyDidWrite() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(MCPWriteNotificationName.darwin),
            nil,
            nil,
            true
        )
    }
}
