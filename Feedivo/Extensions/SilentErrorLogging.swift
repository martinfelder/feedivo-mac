import OSLog

/// Zentrale `os.Logger`-Instanz für Fehlerfälle, die bewusst NICHT über
/// `FeedLogStore` protokolliert werden — entweder weil kein passendes
/// `feedID` existiert (z. B. globale Vorgänge wie das Retention-Cleanup)
/// oder weil ein erneuter DB-Schreibversuch während eines bereits
/// fehlgeschlagenen DB-Vorgangs selbst riskant wäre (Rollback-Cleanup).
/// Landet im vereinheitlichten Apple-Systemlog (Console.app), nicht in der
/// App-eigenen Datenbank. Vorbild: der bereits bestehende, aber private
/// `Logger` in `ArticleWebContentBlocker` (`WebContentView.swift`).
enum AppLogger {
    static let dataAccess = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ch.martin.Feedivo",
        category: "DataAccess"
    )
}

/// Führt `operation` aus und loggt einen eventuellen Fehler, statt ihn wie
/// bisher per `try?` still zu verschlucken. Der Fehler wird NICHT an den
/// Aufrufer weitergereicht — gedacht für Stellen, die bewusst weiterlaufen
/// wollen, wenn `operation` fehlschlägt, den Fehlschlag aber nicht mehr
/// völlig unsichtbar machen wollen. `logger` ist injizierbar, damit das
/// Verhalten ohne echten Fehlerfall testbar ist.
func logIfThrows(
    context: String,
    logger: (String) -> Void = { message in
        AppLogger.dataAccess.error("\(message, privacy: .public)")
    },
    _ operation: () throws -> Void
) {
    do {
        try operation()
    } catch {
        logger("\(context): \(error.localizedDescription)")
    }
}
