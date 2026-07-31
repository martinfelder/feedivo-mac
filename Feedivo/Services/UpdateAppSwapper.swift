import AppKit
import Foundation

protocol UpdateAppSwapping: Sendable {
    /// Ersetzt den Inhalt der App am Pfad `currentAppURL` atomar durch den Inhalt von
    /// `newAppURL` - Pfad/Name von `currentAppURL` bleiben erhalten. Braucht
    /// Schreibzugriff auf das übergeordnete Verzeichnis (siehe
    /// `UpdateInstallLocationGranting`).
    func replaceCurrentApp(at currentAppURL: URL, withNewAppAt newAppURL: URL) throws

    /// Startet die App an `appURL` neu und beendet bei Erfolg den aktuellen Prozess.
    /// Liefert `false`, wenn der Neustart fehlschlug - die aktuelle App bleibt dann
    /// bewusst weiterlaufen (kein Zustand ohne laufende App), der Aufrufer muss in
    /// diesem Fall selbst einen Fehler anzeigen.
    func relaunchAndQuit(appURL: URL) async -> Bool
}

struct FileManagerUpdateAppSwapper: UpdateAppSwapping {
    func replaceCurrentApp(at currentAppURL: URL, withNewAppAt newAppURL: URL) throws {
        do {
            _ = try FileManager.default.replaceItemAt(currentAppURL, withItemAt: newAppURL)
        } catch {
            throw UpdateInstallError.replaceFailed
        }
    }

    func relaunchAndQuit(appURL: URL) async -> Bool {
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            return false
        }

        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
        return true
    }
}
