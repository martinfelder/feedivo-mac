import Testing
import Foundation
import MCP
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

@Suite("FeedivoMCPServer Prozess-Integration")
struct FeedivoMCPServerProcessTests {
    @Test("Server startet als eigener Prozess und beantwortet tools/list ohne Absturz")
    func serverStartetUndAntwortetAufToolsList() async throws {
        let executableURL = try Self.builtExecutableURL()

        let process = Process()
        process.executableURL = executableURL
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        try process.run()
        defer { process.terminate() }

        let clientTransport = StdioTransport(
            input: FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor),
            output: FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        )

        let client = Client(name: "FeedivoMCPServerTests", version: "1.0.0")
        try await client.connect(transport: clientTransport)

        let (tools, _) = try await client.listTools()
        #expect(tools.count >= 0)
    }

    private static func builtExecutableURL() throws -> URL {
        // Xcode legt das gebaute Produkt im selben Build-Ordner ab wie das
        // aktuell laufende Test-Bundle selbst.
        let testBundleURL = Bundle(for: BundleToken.self).bundleURL
        let buildProductsDir = testBundleURL.deletingLastPathComponent()
        return buildProductsDir.appendingPathComponent("FeedivoMCPServer")
    }
}

private final class BundleToken {}
