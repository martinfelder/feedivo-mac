import Testing
@testable import Feedivo

@MainActor
struct SQLiteDataInvalidationTests {
    @Test func bumpStatusVersionErhoehtDenZaehler() {
        SQLiteDataInvalidation.shared.reset()
        let initial = SQLiteDataInvalidation.shared.statusVersion

        SQLiteDataInvalidation.shared.bumpStatusVersion()

        #expect(SQLiteDataInvalidation.shared.statusVersion == initial + 1)
    }

    @Test func mehrfachesBumpenErhoehtKumulativ() {
        SQLiteDataInvalidation.shared.reset()

        SQLiteDataInvalidation.shared.bumpStatusVersion()
        SQLiteDataInvalidation.shared.bumpStatusVersion()
        SQLiteDataInvalidation.shared.bumpStatusVersion()

        #expect(SQLiteDataInvalidation.shared.statusVersion == 3)
    }

    @Test func resetSetztAufNullZurueck() {
        SQLiteDataInvalidation.shared.bumpStatusVersion()

        SQLiteDataInvalidation.shared.reset()

        #expect(SQLiteDataInvalidation.shared.statusVersion == 0)
    }
}
