import AppKit
import Foundation

protocol UpdateInstallLocationGranting: Sendable {
    /// Liefert einen Ordner-URL mit Schreibzugriff, der `currentAppDirectory` enthält -
    /// aus einem gespeicherten Security-Scoped-Bookmark, falls vorhanden und gültig,
    /// sonst über eine einmalige `NSOpenPanel`-Berechtigungsabfrage. Wirft
    /// `.folderAccessDenied`, falls der Nutzer die Abfrage abbricht/ablehnt.
    func grantedInstallDirectory(currentAppDirectory: URL) async throws -> URL
}

@MainActor
final class SecurityScopedInstallLocationGrantor: UpdateInstallLocationGranting {
    private static let bookmarkDefaultsKey = "updateInstall.applicationsFolderBookmark"

    func grantedInstallDirectory(currentAppDirectory: URL) async throws -> URL {
        if let bookmarkedURL = Self.resolveStoredBookmark() {
            return bookmarkedURL
        }
        return try await requestFolderAccess(defaultDirectory: currentAppDirectory)
    }

    private static func resolveStoredBookmark() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale, url.startAccessingSecurityScopedResource() else {
            return nil
        }

        return url
    }

    private func requestFolderAccess(defaultDirectory: URL) async throws -> URL {
        let panel = NSOpenPanel()
        panel.message = String(localized: "updateInstall.folderPicker.message")
        panel.prompt = String(localized: "updateInstall.folderPicker.prompt")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultDirectory

        let response = await withCheckedContinuation { (continuation: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            panel.begin { result in
                continuation.resume(returning: result)
            }
        }

        guard response == .OK, let url = panel.url, url.startAccessingSecurityScopedResource() else {
            throw UpdateInstallError.folderAccessDenied
        }

        if let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmarkData, forKey: Self.bookmarkDefaultsKey)
        }

        return url
    }
}
