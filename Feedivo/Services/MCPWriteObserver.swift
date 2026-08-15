import Foundation

/// Beobachtet die Darwin-Notification, die FeedivoMCPServer nach jedem erfolgreichen
/// Schreib-Tool-Aufruf postet (siehe FeedivoMCPServer/MCPWriteNotifier.swift), und stößt bei
/// Empfang ein Neuladen der betroffenen Views an. Nutzt CFNotificationCenterGetDarwinNotifyCenter
/// (nicht NotificationCenter.default) — funktioniert prozess-/sandbox-übergreifend ohne App
/// Group, im Gegensatz zu regulären NotificationCenter-Postings, die pro Prozess isoliert sind.
///
/// Bumpt bewusst BEIDE bestehenden Invalidierungssignale (statusVersion UND
/// directTagVersion), unabhängig davon, welches der drei Schreib-Tools tatsächlich
/// aufgerufen wurde — die Darwin-Notification selbst trägt keine Nutzdaten (nur ein reiner
/// "Ping"), ein bisschen überflüssiges Neuladen ist laut bestehender Architektur bereits als
/// harmlos dokumentiert (siehe die @Observable-Migration vom 2026-08-05 in CLAUDE.md).
enum MCPWriteObserver {
    /// Einmalig beim App-Start aufrufen (siehe FeedivoAppDelegate.applicationDidFinishLaunching).
    /// Der Callback ist ein nicht-capturing @convention(c)-Funktionszeiger (CFNotificationCenter
    /// verlangt das) — referenziert deshalb bewusst nur globale/statische Symbole, kein `self`.
    static func startObserving() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    SQLiteDataInvalidation.shared.bumpStatusVersion()
                    SidebarBadgeInvalidation.shared.bumpDirectTagVersion()
                }
            },
            MCPWriteNotificationName.darwin,
            nil,
            .deliverImmediately
        )
    }
}
