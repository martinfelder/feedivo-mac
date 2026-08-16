import Foundation
import Testing
@testable import Feedivo

@Suite("MCPToolInventory")
struct MCPToolInventoryTests {
    @Test("Ohne Schreibzugriff sind es die sieben lesenden Werkzeuge")
    func ohneSchreibzugriff() {
        #expect(MCPToolInventory.expectedToolCount(isWriteAccessEnabled: false) == 7)
    }

    @Test("Mit Schreibzugriff kommen drei Werkzeuge dazu")
    func mitSchreibzugriff() {
        #expect(MCPToolInventory.expectedToolCount(isWriteAccessEnabled: true) == 10)
    }

    @Test("Die Summe ergibt sich aus den beiden Teilmengen")
    func summeIstKonsistent() {
        // Haelt die beiden Konstanten und die Rechenfunktion aneinander gebunden: Wer eine
        // Zahl aendert, ohne die andere zu pruefen, faellt hier auf.
        #expect(
            MCPToolInventory.expectedToolCount(isWriteAccessEnabled: true)
                == MCPToolInventory.readOnlyToolCount + MCPToolInventory.writeToolCount
        )
    }
}
