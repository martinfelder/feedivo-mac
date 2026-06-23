import Foundation

enum ImageCacheSettings {
    nonisolated static let limitMegabytesKey = "imageCache.limitMegabytes"
    nonisolated static let defaultLimitMegabytes = 500
    nonisolated static let allowedLimitMegabytes = [100, 250, 500, 1_024, 2_048]

    nonisolated static func resolvedLimitMegabytes(_ value: Int) -> Int {
        allowedLimitMegabytes.contains(value) ? value : defaultLimitMegabytes
    }

    nonisolated static func bytes(forMegabytes megabytes: Int) -> Int64 {
        Int64(resolvedLimitMegabytes(megabytes)) * 1_024 * 1_024
    }

    nonisolated static var currentLimitInBytes: Int64 {
        let storedLimitMegabytes = UserDefaults.standard.integer(forKey: limitMegabytesKey)
        let limitMegabytes = storedLimitMegabytes == 0 ? defaultLimitMegabytes : storedLimitMegabytes
        return bytes(forMegabytes: limitMegabytes)
    }

    static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }
}
