import Foundation
import Testing
@testable import Feedivo

@Suite("HomebrewInstallationDetector")
struct HomebrewInstallationDetectorTests {
    @Test("erkennt Apple-Silicon-Caskroom-Pfad")
    func erkenntAppleSiliconCaskroomPfad() {
        let url = URL(fileURLWithPath: "/opt/homebrew/Caskroom/feedivo/1.0-15/Feedivo.app")
        #expect(HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL: url))
    }

    @Test("erkennt Intel-Caskroom-Pfad")
    func erkenntIntelCaskroomPfad() {
        let url = URL(fileURLWithPath: "/usr/local/Caskroom/feedivo/1.0-15/Feedivo.app")
        #expect(HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL: url))
    }

    @Test("erkennt normale Applications-Installation NICHT als Homebrew")
    func erkenntApplicationsInstallationNichtAlsHomebrew() {
        let url = URL(fileURLWithPath: "/Applications/Feedivo.app")
        #expect(!HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL: url))
    }

    @Test("erkennt Pfad mit 'Caskroom' als Teil eines anderen Ordnernamens NICHT")
    func erkenntAehnlichenPfadNicht() {
        let url = URL(fileURLWithPath: "/Users/martin/Downloads/NichtCaskroomOrdner/Feedivo.app")
        #expect(!HomebrewInstallationDetector.isHomebrewCaskInstall(bundleURL: url))
    }
}
