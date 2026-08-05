import Testing
@testable import Feedivo

@MainActor
struct SQLiteDataInvalidationTests {
    @Test func bumpStatusVersionErhoehtDenZaehler() {
        SQLiteDataInvalidationSignal.shared.reset()
        let initial = SQLiteDataInvalidationSignal.shared.statusVersion

        SQLiteDataInvalidationSignal.shared.bumpStatusVersion()

        #expect(SQLiteDataInvalidationSignal.shared.statusVersion == initial + 1)
    }

    @Test func mehrfachesBumpenErhoehtKumulativ() {
        SQLiteDataInvalidationSignal.shared.reset()

        SQLiteDataInvalidationSignal.shared.bumpStatusVersion()
        SQLiteDataInvalidationSignal.shared.bumpStatusVersion()
        SQLiteDataInvalidationSignal.shared.bumpStatusVersion()

        #expect(SQLiteDataInvalidationSignal.shared.statusVersion == 3)
    }

    @Test func resetSetztAufNullZurueck() {
        SQLiteDataInvalidationSignal.shared.bumpStatusVersion()

        SQLiteDataInvalidationSignal.shared.reset()

        #expect(SQLiteDataInvalidationSignal.shared.statusVersion == 0)
    }
}
