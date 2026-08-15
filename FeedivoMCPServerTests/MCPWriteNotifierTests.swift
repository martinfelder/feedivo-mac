import Testing
@testable import FeedivoMCPServer

@Suite("MCPWriteNotifier")
struct MCPWriteNotifierTests {
    @Test("writeToolNames enthält genau die drei Schreib-Tools")
    func writeToolNamesEnthaeltDieDreiSchreibTools() {
        #expect(MCPWriteNotifier.writeToolNames == ["update_article_status", "assign_tag", "remove_tag"])
    }
}
