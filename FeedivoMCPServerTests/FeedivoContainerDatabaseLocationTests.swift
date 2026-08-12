import Testing
import Foundation
@testable import FeedivoMCPServer

@Suite("FeedivoContainerDatabaseLocation")
struct FeedivoContainerDatabaseLocationTests {
    @Test("Pfad zeigt auf den sandboxed Container von ch.martin.Feedivo")
    func pfadZeigtAufSandboxedContainer() {
        let home = URL(fileURLWithPath: "/Users/testuser")
        let url = FeedivoContainerDatabaseLocation.databaseURL(homeDirectory: home)

        #expect(
            url.path
                == "/Users/testuser/Library/Containers/ch.martin.Feedivo/Data/Library/Application Support/ch.martin.Feedivo/Feedivo/feedivo.sqlite"
        )
    }

    @Test("Nutzt standardmäßig das echte Home-Verzeichnis des aktuellen Nutzers")
    func nutztStandardmaessigEchtesHomeVerzeichnis() {
        let url = FeedivoContainerDatabaseLocation.databaseURL()
        let expectedPrefix = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(url.path.hasPrefix(expectedPrefix))
    }
}
