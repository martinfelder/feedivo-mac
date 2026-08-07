import Foundation

/// Erkennt, ob eine URL auf ein einzelnes YouTube-Video zeigt (Watch-Seite, Shorts oder
/// youtu.be-Kurzlink) — genutzt vom Reader, um bei YouTube-Video-Artikeln auf die
/// Original-Ansicht hinzuweisen, wo das Video tatsächlich abspielbar ist.
enum YouTubeVideoLink {
    static func isVideoURL(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else {
            return false
        }

        if host == "youtu.be" {
            return true
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else {
            return false
        }

        let path = url?.path ?? ""
        return path == "/watch" || path.hasPrefix("/shorts/")
    }
}
