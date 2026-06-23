import Testing
@testable import Feedivo

struct ImageCacheSettingsTests {
    @Test func resolvedLimitFallsBackToDefaultForUnknownValues() {
        #expect(ImageCacheSettings.resolvedLimitMegabytes(123) == ImageCacheSettings.defaultLimitMegabytes)
    }

    @Test func bytesUsesResolvedMegabytes() {
        #expect(ImageCacheSettings.bytes(forMegabytes: 100) == 104_857_600)
        #expect(ImageCacheSettings.bytes(forMegabytes: 123) == 524_288_000)
    }
}
