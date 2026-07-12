import Foundation
import Testing
@testable import Feedivo

struct SilentErrorLoggingTests {
    @Test func logIfThrowsRuftLoggerBeiErfolgNichtAuf() {
        var loggedMessages: [String] = []

        logIfThrows(context: "Test", logger: { loggedMessages.append($0) }) {
            // Kein throw — Erfolgsfall.
        }

        #expect(loggedMessages.isEmpty)
    }

    @Test func logIfThrowsLoggtKontextUndFehlerbeschreibungBeiFehlschlag() {
        struct SampleError: Error, LocalizedError {
            var errorDescription: String? { "Beispiel-Fehler" }
        }
        var loggedMessages: [String] = []

        logIfThrows(context: "Rollback", logger: { loggedMessages.append($0) }) {
            throw SampleError()
        }

        #expect(loggedMessages.count == 1)
        #expect(loggedMessages[0].contains("Rollback"))
        #expect(loggedMessages[0].contains("Beispiel-Fehler"))
    }

    @Test func logIfThrowsWirftDenFehlerNichtAnDenAufruferWeiter() {
        struct SampleError: Error {}

        // Kompiliert nur, wenn logIfThrows selbst nicht `throws` ist — kein
        // `try` am Aufruf nötig. Der Test besteht bereits durch erfolgreiches
        // Durchlaufen ohne Crash/Propagation.
        logIfThrows(context: "Egal", logger: { _ in }) {
            throw SampleError()
        }
    }
}
