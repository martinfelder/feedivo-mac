import Foundation

protocol UpdateAssetDownloading: Sendable {
    /// Lädt die Datei unter `url` herunter und liefert eine lokale, dauerhafte Datei-URL
    /// (im temporären Verzeichnis) zurück. `onProgress` wird wiederholt mit
    /// (Fortschrittsanteil 0...1, geladene Bytes, erwartete Gesamt-Bytes) aufgerufen -
    /// bei unbekannter Gesamtgröße (z. B. sehr kleine Textdateien) kann `onProgress`
    /// auch gar nicht aufgerufen werden, Aufrufer dürfen sich darauf nicht verlassen.
    func download(from url: URL, onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void) async throws -> URL
}

/// Lädt ein Release-Asset per URLSession-Download-Task herunter. Reiner I/O-Wrapper
/// ohne eigene Geschäftslogik - siehe UpdateInstaller für die eigentliche Sequenzierung.
final class URLSessionUpdateAssetDownloader: NSObject, UpdateAssetDownloading, URLSessionDownloadDelegate, @unchecked Sendable {
    private var progressHandler: (@Sendable (Double, Int64, Int64) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?

    func download(from url: URL, onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void) async throws -> URL {
        progressHandler = onProgress
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(fraction, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // `location` wird von URLSession geloescht, sobald diese Methode zurueckkehrt -
        // sofort in ein eigenes, stabiles Temp-File verschieben.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(location.pathExtension.isEmpty ? "download" : location.pathExtension)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
