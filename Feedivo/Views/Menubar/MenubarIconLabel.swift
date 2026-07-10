import SwiftUI

/// Icon + Badge-Text für die Menubar-Scene (Feature 21.1). Nutzt denselben
/// Unread-Count wie das Dock-Icon-Badge (`AppIconBadgeService`).
struct MenubarIconLabel: View {
    let unreadCount: Int

    var body: some View {
        Label {
            Text(unreadCount > 0 ? "\(unreadCount)" : "")
        } icon: {
            Image(systemName: unreadCount > 0 ? "tray.full" : "tray")
        }
        .labelStyle(.titleAndIcon)
    }
}
