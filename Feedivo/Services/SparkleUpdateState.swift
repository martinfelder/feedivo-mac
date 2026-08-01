import Foundation

/// Zustand des Sparkle-gestützten Update-Vorgangs - Pendant zum entfernten
/// UpdateInstallState/UpdateCheckOutcome, jetzt als eine gemeinsame
/// Zustandsmaschine für Check UND Installation.
enum SparkleUpdateState: Equatable {
    case idle
    case checking
    case updateAvailable(SparkleReleaseInfo)
    case downloading(fractionCompleted: Double, downloadedBytes: Int64, totalBytes: Int64)
    case extracting(progress: Double)
    case readyToInstall
    case installing
    case upToDate
    case failed(String)
}
