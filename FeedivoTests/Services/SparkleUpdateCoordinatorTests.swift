import Foundation
import Testing
import Sparkle
@testable import Feedivo

/// Fix Whole-Branch-Review (Important 7): `SparkleUpdateCoordinator` hatte zum
/// Zeitpunkt dieses Reviews bereits drei Bugs genau in der Continuation-
/// Auflösungslogik (zwei bereits vor diesem Review behobene Criticals, siehe
/// Kommentar auf `installUpdate()`, plus die hier gefixten Important-1/
/// Critical-1-Funde) - dieser Test isoliert genau diesen Bereich, ohne den
/// kompletten SPUUserDriver-Callback-Pfad (echter SPUUpdater, echte Sparkle-
/// Appcast-Objekte) nachstellen zu müssen. `pendingUpdateChoice`/
/// `pendingInstallChoice`/`pendingCancellation` sind dafür von `private` auf
/// `internal` gelockert (siehe Kommentar dort) - `@testable import` macht
/// `private`-Member nicht sichtbar, `internal`-Member innerhalb desselben
/// Moduls schon.
@MainActor
@Suite("SparkleUpdateCoordinator")
struct SparkleUpdateCoordinatorTests {
    @Test("installUpdate() löst pendingUpdateChoice mit .install auf und leert das Feld")
    func installUpdateLoestPendingUpdateChoiceMitInstallAuf() {
        let coordinator = SparkleUpdateCoordinator()
        var recordedChoice: SPUUserUpdateChoice?
        coordinator.pendingUpdateChoice = { choice in recordedChoice = choice }

        coordinator.installUpdate()

        #expect(recordedChoice == .install)
        #expect(coordinator.pendingUpdateChoice == nil)
    }

    @Test("installUpdate() löst pendingInstallChoice mit .install auf, wenn pendingUpdateChoice nil ist")
    func installUpdateLoestPendingInstallChoiceAufWennKeinUpdateChoiceAnsteht() {
        let coordinator = SparkleUpdateCoordinator()
        var recordedChoice: SPUUserUpdateChoice?
        coordinator.pendingInstallChoice = { choice in recordedChoice = choice }
        // pendingUpdateChoice bleibt bewusst nil - simuliert den
        // "Bereit zur Installation"-Dialog (showReadyToInstallAndRelaunch),
        // nicht den "Update gefunden"-Dialog (showUpdateFound).

        coordinator.installUpdate()

        #expect(recordedChoice == .install)
        #expect(coordinator.pendingInstallChoice == nil)
    }

    @Test("cancelDownload() löst eine ausstehende pendingUpdateChoice mit .dismiss auf, statt sie stillschweigend zu verwerfen")
    func cancelDownloadLoestPendingUpdateChoiceMitDismissAuf() {
        let coordinator = SparkleUpdateCoordinator()
        var recordedChoice: SPUUserUpdateChoice?
        coordinator.pendingUpdateChoice = { choice in recordedChoice = choice }

        coordinator.cancelDownload()

        #expect(recordedChoice == .dismiss)
        #expect(coordinator.pendingUpdateChoice == nil)
        #expect(coordinator.state == .idle)
    }
}
