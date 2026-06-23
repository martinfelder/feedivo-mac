import Foundation

enum ImageCacheSettings {
    static let limitMegabytesKey = "imageCache.limitMegabytes"
    static let defaultLimitMegabytes = 500
    static let allowedLimitMegabytes = [100, 250, 500, 1_024, 2_048]

    static func resolvedLimitMegabytes(_ value: Int) -> Int {
        allowedLimitMegabytes.contains(value) ? value : defaultLimitMegabytes
    }

    static func bytes(forMegabytes megabytes: Int) -> Int64 {
        Int64(resolvedLimitMegabytes(megabytes)) * 1_024 * 1_024
    }

    static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }
}
