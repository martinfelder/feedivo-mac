import Testing
import Foundation
@testable import Feedivo

struct GitHubReleaseAssetSelectionTests {

    private func asset(_ name: String) -> GitHubReleaseAsset {
        GitHubReleaseAsset(name: name, browserDownloadURL: URL(string: "https://example.com/\(name)")!)
    }

    @Test func zipAssetFindetDieZipDateiUnabhaengigVonGrossKleinschreibung() {
        let assets = [asset("Feedivo-v1.0-14.ZIP"), asset("Feedivo-v1.0-14.zip.sha256")]

        #expect(GitHubReleaseAsset.zipAsset(in: assets)?.name == "Feedivo-v1.0-14.ZIP")
    }

    @Test func checksumAssetFindetDieSha256Datei() {
        let assets = [asset("Feedivo-v1.0-14.zip"), asset("Feedivo-v1.0-14.zip.sha256")]

        #expect(GitHubReleaseAsset.checksumAsset(in: assets)?.name == "Feedivo-v1.0-14.zip.sha256")
    }

    @Test func liefertNilBeiFehlendemAsset() {
        #expect(GitHubReleaseAsset.zipAsset(in: []) == nil)
        #expect(GitHubReleaseAsset.checksumAsset(in: []) == nil)
    }
}
