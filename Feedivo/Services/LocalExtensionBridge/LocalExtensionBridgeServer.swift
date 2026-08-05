import Foundation
import Network
import OSLog

// Minimaler, nur auf 127.0.0.1 lauschender HTTP-Server, den die Browser-
// Erweiterung (BrowserExtensions/Chrome/popup.js) abfragt, um den Abo-Status
// eines Feeds zu prüfen (GET /status) und Feeds direkt hinzuzufügen (POST
// /add) — ohne dass das App-Fenster in den Vordergrund muss. Läuft die App
// nicht, schlagen diese Requests einfach fehl (Connection refused); die
// Erweiterung fällt dann auf den bestehenden feedivo://add-Deep-Link zurück.
// Siehe docs/superpowers/specs/2026-07-13-browser-erweiterung-ux-design.md.
@MainActor
final class LocalExtensionBridgeServer {
    // `nonisolated`, weil dieser Wert als Default-Parameter in `init(...)`
    // an der Aufrufstelle ausgewertet wird — der Aufrufer läuft nicht
    // zwangsläufig bereits auf dem MainActor (Default Actor Isolation des
    // Targets ist `MainActor`, siehe SWIFT_DEFAULT_ACTOR_ISOLATION).
    nonisolated static let defaultPort: UInt16 = 51823

    private let port: UInt16
    private let router: LocalExtensionBridgeRouter
    private var listener: NWListener?

    init(database: FeedivoDatabase, port: UInt16 = LocalExtensionBridgeServer.defaultPort) {
        self.port = port
        self.router = LocalExtensionBridgeRouter(
            checkSubscribed: { urlString in
                await LocalExtensionBridgeServer.isSubscribed(urlString, database: database)
            },
            addFeed: { urlString in
                await LocalExtensionBridgeServer.addFeed(urlString, database: database)
            }
        )
    }

    func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            AppLogger.dataAccess.error("LocalExtensionBridgeServer: ungültiger Port \(self.port, privacy: .public)")
            return
        }

        // Bewusst NUR an 127.0.0.1 binden, nie an alle Interfaces (0.0.0.0) —
        // dieser Server darf ausschließlich vom selben Rechner erreichbar sein.
        // NWParameters kennt kein direktes "bind an genau diese lokale
        // Adresse"-Property für den Listener selbst; stattdessen wird der
        // NWListener über einen expliziten IPv4-Loopback-NWEndpoint als
        // "required local endpoint" gebunden, was denselben Effekt erzielt.
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: nwPort
        )

        do {
            let listener = try NWListener(using: parameters)
            // `newConnectionHandler`/`stateUpdateHandler` sind reine
            // System-Callbacks von Network.framework (nicht MainActor-
            // isoliert, auch wenn sie über `listener.start(queue: .main)`
            // tatsächlich auf dem Main-Thread laufen) — deshalb hier explizit
            // per `Task { @MainActor in … }` in den MainActor-Kontext
            // zurückspringen, bevor MainActor-isolierte Methoden/Properties
            // (self.handle, AppLogger.dataAccess) angefasst werden.
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handle(connection)
                }
            }
            listener.stateUpdateHandler = { state in
                if case let .failed(error) = state {
                    Task { @MainActor in
                        AppLogger.dataAccess.error("LocalExtensionBridgeServer: Listener fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            AppLogger.dataAccess.error("LocalExtensionBridgeServer: Start fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveLoop(connection: connection, buffer: Data())
    }

    private func receiveLoop(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            var newBuffer = buffer
            if let data, !data.isEmpty {
                newBuffer.append(data)
            }

            if let request = HTTPRequestParser.parse(newBuffer) {
                Task { @MainActor in
                    let response = await self.router.handle(request)
                    connection.send(content: response.serialize(), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
                return
            }

            if error != nil || isComplete {
                connection.cancel()
                return
            }

            Task { @MainActor in
                self.receiveLoop(connection: connection, buffer: newBuffer)
            }
        }
    }

    // Case-insensitiver, getrimmter Abgleich — bewusst nicht dieselbe private
    // Normalisierung wie SQLiteFeedSubscriptionService.normalizedFeedURL
    // wiederverwendet (dort privat), sondern dieselbe einfache Logik
    // (trim + lowercase) hier dupliziert.
    static func isSubscribed(_ urlString: String, database: FeedivoDatabase) async -> Bool {
        let normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        let feeds = (try? FeedStore(database: database).feeds()) ?? []
        return feeds.contains {
            $0.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    static func addFeed(
        _ urlString: String,
        database: FeedivoDatabase,
        fetchFeed: @escaping @Sendable (String) async throws -> ParsedFeed = FeedService.fetchFeed
    ) async -> LocalExtensionBridgeAddResult {
        let service = SQLiteFeedActionService(database: database, fetchFeed: fetchFeed)
        do {
            try await service.addFeed(
                urlString: urlString,
                refreshIntervalMinutes: BackgroundRefreshSettings.defaultIntervalMinutes
            )
            SQLiteDataInvalidationSignal.shared.bumpStatusVersion()
            return .added
        } catch SQLiteFeedSubscriptionError.duplicateFeed {
            return .alreadyExists
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
