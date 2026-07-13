import Foundation
import Testing
@testable import Feedivo

struct HTTPRequestParserTests {
    @Test func parstEinenGETRequestMitQueryString() {
        let raw = "GET /status?url=https%3A%2F%2Fexample.com%2Ffeed.xml HTTP/1.1\r\nHost: 127.0.0.1:51823\r\n\r\n"
        let request = HTTPRequestParser.parse(Data(raw.utf8))

        #expect(request?.method == "GET")
        #expect(request?.path == "/status")
        #expect(request?.queryItems["url"] == "https://example.com/feed.xml")
        #expect(request?.headers["host"] == "127.0.0.1:51823")
        #expect(request?.body.isEmpty == true)
    }

    @Test func liefertNilWennHeaderEndeNochNichtErreicht() {
        let raw = "GET /status HTTP/1.1\r\nHost: 127.0.0.1"
        #expect(HTTPRequestParser.parse(Data(raw.utf8)) == nil)
    }

    @Test func parstEinenPOSTRequestMitJSONBody() {
        let body = "{\"url\":\"https://example.com/feed.xml\"}"
        let raw = "POST /add HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let request = HTTPRequestParser.parse(Data(raw.utf8))

        #expect(request?.method == "POST")
        #expect(request?.path == "/add")
        #expect(request?.headers["content-type"] == "application/json")
        #expect(request?.body == Data(body.utf8))
    }

    @Test func liefertNilWennBodyNochUnvollstaendigIst() {
        let raw = "POST /add HTTP/1.1\r\nContent-Length: 40\r\n\r\n{\"url\":\"https://example.com\""
        #expect(HTTPRequestParser.parse(Data(raw.utf8)) == nil)
    }

    @Test func headerNamenWerdenKleingeschriebenAbgeglichen() {
        let raw = "POST /add HTTP/1.1\r\nCONTENT-LENGTH: 0\r\n\r\n"
        let request = HTTPRequestParser.parse(Data(raw.utf8))
        #expect(request?.headers["content-length"] == "0")
    }
}
