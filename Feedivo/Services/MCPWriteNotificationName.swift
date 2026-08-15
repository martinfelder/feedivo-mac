import Foundation

/// Gemeinsam von FeedivoMCPServer (Sender, siehe MCPWriteNotifier.swift) und Feedivo
/// (Empfänger, siehe MCPWriteObserver.swift) genutzter Name für die Darwin-Notification, die
/// nach jedem erfolgreichen Schreib-Tool-Aufruf gepostet wird. In einer eigenen, von beiden
/// Targets geteilten Datei definiert, damit Sender und Empfänger nicht unabhängig voneinander
/// denselben String-Literal pflegen (Tippfehler-Risiko würde die gesamte Live-Refresh-Kette
/// lautlos brechen, ohne dass irgendwo ein Fehler sichtbar würde).
enum MCPWriteNotificationName {
    static let darwin = "ch.martin.Feedivo.mcpServerDidWrite" as CFString
}
