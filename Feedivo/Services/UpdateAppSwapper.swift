import AppKit
import Foundation

protocol UpdateAppSwapping: Sendable {
    /// Ersetzt den Inhalt der App am Pfad `currentAppURL` atomar durch den Inhalt von
    /// `newAppURL` - Pfad/Name von `currentAppURL` bleiben erhalten. Braucht
    /// Schreibzugriff auf das übergeordnete Verzeichnis (siehe
    /// `UpdateInstallLocationGranting`).
    func replaceCurrentApp(at currentAppURL: URL, withNewAppAt newAppURL: URL) throws

    /// Startet die App an `appURL` neu und beendet den aktuellen Prozess.
    func relaunchAndQuit(appURL: URL)
}

struct FileManagerUpdateAppSwapper: UpdateAppSwapping {
    func replaceCurrentApp(at currentAppURL: URL, withNewAppAt newAppURL: URL) throws {
        do {
            _ = try FileManager.default.replaceItemAt(currentAppURL, withItemAt: newAppURL)
        } catch {
            throw UpdateInstallError.replaceFailed
        }
    }

    func relaunchAndQuit(appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
