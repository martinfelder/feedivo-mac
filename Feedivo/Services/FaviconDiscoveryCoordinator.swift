import Foundation

/// Dedupliziert GLEICHZEITIG laufende Favicon-Discovery-Anfragen für dieselbe
/// siteURL (NetNewsWire-Vergleich, 2026-07-27) — z. B. wenn mehrere Feeds im
/// selben Refresh-All-Batch dieselbe Blog-Plattform teilen. Kein
/// Langzeit-Cache: Einträge werden direkt nach Abschluss entfernt, ein
/// späterer Aufruf löst wieder eine echte Anfrage aus. `FaviconService`
/// selbst bleibt bewusst zustandslos — dieser Actor ist der einzige
/// stateful Baustein für die Deduplizierung.
actor FaviconDiscoveryCoordinator {
    private var inFlight: [String: Task<String?, Never>] = [:]

    func discover(
        siteURL: URL,
        using discover: @escaping @Sendable (URL) async -> String? = { url in
            await FaviconService.discoverFaviconURL(siteURL: url)
        }
    ) async -> String? {
        let key = siteURL.absoluteString
        if let existingTask = inFlight[key] {
            return await existingTask.value
        }

        let task = Task { await discover(siteURL) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
}
