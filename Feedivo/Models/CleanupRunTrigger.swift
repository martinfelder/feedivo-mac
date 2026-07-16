import Foundation

// Wer eine automatische oder manuelle Bereinigung ausgelöst hat — wird als String in
// cleanup_runs.triggerSource gespeichert, in der Bereinigungs-History in den
// Einstellungen wieder in einen lesbaren Text übersetzt.
enum CleanupRunTrigger: String, Codable, Sendable {
    case manual
    case appStart
    case schedule
    case onQuit
    case settingsChange
}
