import AppKit
import Foundation

protocol UpdateAppSwapping: Sendable {
    /// Ersetzt den Inhalt der App am Pfad `currentAppURL` atomar durch den Inhalt von
    /// `newAppURL` - Pfad/Name von `currentAppURL` bleiben erhalten. Braucht
    /// Schreibzugriff auf das übergeordnete Verzeichnis (siehe
    /// `UpdateInstallLocationGranting`). `@concurrent` + `async`, damit der blockierende
    /// Dateisystem-Austausch nicht synchron auf dem MainActor läuft (Whole-Branch-Review-
    /// Fund - dasselbe Muster wie der bereits dokumentierte Spotlight-Backfill-Gotcha).
    /// Reines `nonisolated` reicht dafür NICHT: bei aktivem `SWIFT_APPROACHABLE_CONCURRENCY`
    /// (`NonisolatedNonsendingByDefault`) läuft eine `nonisolated async`-Funktion weiterhin
    /// auf dem Actor des Aufrufers - `@concurrent` erzwingt den tatsächlichen Wechsel.
    @concurrent func replaceCurrentApp(at currentAppURL: URL, withNewAppAt newAppURL: URL) async throws

    /// Startet die App an `appURL` neu und beendet bei Erfolg den aktuellen Prozess.
    /// Liefert `false`, wenn der Neustart fehlschlug - die aktuelle App bleibt dann
    /// bewusst weiterlaufen (kein Zustand ohne laufende App), der Aufrufer muss in
    /// diesem Fall selbst einen Fehler anzeigen.
    func relaunchAndQuit(appURL: URL) async -> Bool
}

struct FileManagerUpdateAppSwapper: UpdateAppSwapping {
    @concurrent func replaceCurrentApp(at currentAppURL: URL, withNewAppAt newAppURL: URL) async throws {
        do {
            _ = try FileManager.default.replaceItemAt(currentAppURL, withItemAt: newAppURL)
        } catch {
            throw UpdateInstallError.replaceFailed
        }
    }

    func relaunchAndQuit(appURL: URL) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        // Whole-Branch-Review-Fund: ohne dies aktiviert openApplication die BEREITS
        // LAUFENDE (alte) Instanz statt eine neue zu starten, weil appURL == der Pfad
        // ist, von dem der aktuelle Prozess bereits läuft - terminate(nil) direkt danach
        // würde dann die App komplett beenden, ohne je die neue Version zu starten.
        configuration.createsNewApplicationInstance = true

        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } catch {
            return false
        }

        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
        return true
    }
}
