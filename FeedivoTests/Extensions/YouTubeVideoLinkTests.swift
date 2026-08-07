import Foundation
import Testing
@testable import Feedivo

struct YouTubeVideoLinkTests {
    @Test func erkenntWatchURLMitWWWAlsVideo() {
        #expect(YouTubeVideoLink.isVideoURL(URL(string: "https://www.youtube.com/watch?v=abc123")))
    }

    @Test func erkenntWatchURLOhneWWWAlsVideo() {
        #expect(YouTubeVideoLink.isVideoURL(URL(string: "https://youtube.com/watch?v=abc123")))
    }

    @Test func erkenntMobileWatchURLAlsVideo() {
        #expect(YouTubeVideoLink.isVideoURL(URL(string: "https://m.youtube.com/watch?v=abc123")))
    }

    @Test func erkenntShortsURLAlsVideo() {
        #expect(YouTubeVideoLink.isVideoURL(URL(string: "https://www.youtube.com/shorts/abc123")))
    }

    @Test func erkenntYoutuBeKurzlinkAlsVideo() {
        #expect(YouTubeVideoLink.isVideoURL(URL(string: "https://youtu.be/abc123")))
    }

    @Test func erkenntKanalSeiteNichtAlsVideo() {
        #expect(!YouTubeVideoLink.isVideoURL(URL(string: "https://www.youtube.com/@Apple")))
    }

    @Test func erkenntFremdeDomaneMitWatchPfadNichtAlsVideo() {
        #expect(!YouTubeVideoLink.isVideoURL(URL(string: "https://example.com/watch")))
    }

    @Test func erkenntNilNichtAlsVideo() {
        #expect(!YouTubeVideoLink.isVideoURL(nil))
    }
}
