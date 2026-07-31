import Testing
import Foundation
@testable import Feedivo

struct GitHubReleaseCheckServiceTests {

    private static let sampleReleaseListJSON = """
    [
      {
        "html_url": "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-11",
        "tag_name": "v1.0-11",
        "name": "Feedivo 1.0 (11)",
        "draft": false,
        "prerelease": true,
        "published_at": "2026-07-30T18:21:00Z",
        "body": "- Feat: Sidebar-Header in Blau",
        "body_html": "<ul>\\n<li>Feat: Sidebar-Header in Blau</li>\\n</ul>",
        "assets": [
          {
            "name": "Feedivo-v1.0-11.zip",
            "browser_download_url": "https://github.com/martinfelder/feedivo-mac/releases/download/v1.0-11/Feedivo-v1.0-11.zip"
          },
          {
            "name": "Feedivo-v1.0-11.zip.sha256",
            "browser_download_url": "https://github.com/martinfelder/feedivo-mac/releases/download/v1.0-11/Feedivo-v1.0-11.zip.sha256"
          }
        ]
      },
      {
        "html_url": "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-10",
        "tag_name": "v1.0-10",
        "name": "Feedivo 1.0 (10)",
        "draft": false,
        "prerelease": true,
        "published_at": "2026-07-20T09:00:00Z",
        "body": "- Chore: Version 1.0 (10)",
        "body_html": "<ul>\\n<li>Chore: Version 1.0 (10)</li>\\n</ul>"
      }
    ]
    """.data(using: .utf8)!

    @Test func decodeReleasesLiestTagNameHTMLUndBodyHTML() throws {
        let releases = try GitHubReleaseCheckService.decodeReleases(from: Self.sampleReleaseListJSON)

        #expect(releases.count == 2)
        #expect(releases[0].tagName == "v1.0-11")
        #expect(releases[0].name == "Feedivo 1.0 (11)")
        #expect(releases[0].htmlURL.absoluteString == "https://github.com/martinfelder/feedivo-mac/releases/tag/v1.0-11")
        #expect(releases[0].bodyHTML == "<ul>\n<li>Feat: Sidebar-Header in Blau</li>\n</ul>")
        #expect(releases[0].publishedAt != nil)
    }

    @Test func decodeReleasesLiefertLeeresArrayBeiLeererListe() throws {
        let releases = try GitHubReleaseCheckService.decodeReleases(from: "[]".data(using: .utf8)!)

        #expect(releases.isEmpty)
    }

    @Test func decodeReleasesWirftDecodingFailedBeiKaputtemJSON() {
        let garbage = "not valid json".data(using: .utf8)!

        #expect(throws: GitHubReleaseCheckError.decodingFailed) {
            try GitHubReleaseCheckService.decodeReleases(from: garbage)
        }
    }

    @Test func decodeReleasesLiestAssetsUndFaelltAufLeeresArrayZurueckWennAssetsFehlt() throws {
        let releases = try GitHubReleaseCheckService.decodeReleases(from: Self.sampleReleaseListJSON)

        #expect(releases[0].assets.count == 2)
        #expect(releases[0].assets[0].name == "Feedivo-v1.0-11.zip")
        #expect(releases[0].assets[0].browserDownloadURL.absoluteString == "https://github.com/martinfelder/feedivo-mac/releases/download/v1.0-11/Feedivo-v1.0-11.zip")
        #expect(releases[0].assets[1].name == "Feedivo-v1.0-11.zip.sha256")
        // Zweiter Release in der Fixture hat bewusst KEIN "assets"-Feld im JSON - muss
        // trotzdem sauber auf ein leeres Array zurueckfallen statt einen Decoding-Fehler zu werfen.
        #expect(releases[1].assets.isEmpty)
    }
}
