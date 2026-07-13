import Foundation

struct HTTPRequest: Equatable {
    var method: String
    var path: String
    var queryItems: [String: String]
    var headers: [String: String]
    var body: Data
}

// Minimaler HTTP/1.1-Request-Parser für den lokalen Erweiterungs-Server
// (Feature: Browser-Erweiterung Popup-UX). Bewusst kein allgemeiner
// HTTP-Parser — nur so viel wie für kleine, lokale JSON-Requests von der
// eigenen Browser-Erweiterung nötig ist (kein Chunked Encoding, keine
// Multipart-Bodies).
enum HTTPRequestParser {
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    // `nil` bedeutet: `buffer` enthält noch keinen vollständigen Request
    // (Header-Ende \r\n\r\n fehlt noch, oder der Body ist kürzer als
    // Content-Length) — der Aufrufer muss weitere Bytes nachliefern, das
    // ist KEIN Fehlerfall.
    static func parse(_ buffer: Data) -> HTTPRequest? {
        guard let headerEndRange = buffer.range(of: headerTerminator) else {
            return nil
        }

        let headerData = buffer[..<headerEndRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }

        let requestLineParts = requestLine.split(separator: " ")
        guard requestLineParts.count >= 2 else {
            return nil
        }

        let method = String(requestLineParts[0])
        let (path, queryItems) = splitPathAndQuery(String(requestLineParts[1]))
        let headers = parseHeaders(lines.dropFirst())

        let bodyStart = headerEndRange.upperBound
        let expectedBodyLength = headers["content-length"].flatMap(Int.init) ?? 0
        let availableBody = buffer[bodyStart...]

        guard availableBody.count >= expectedBodyLength else {
            return nil
        }

        let body = Data(availableBody.prefix(expectedBodyLength))
        return HTTPRequest(method: method, path: path, queryItems: queryItems, headers: headers, body: body)
    }

    private static func parseHeaders(_ lines: ArraySlice<String>) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let separatorIndex = line.firstIndex(of: ":") else {
                continue
            }
            let name = line[line.startIndex..<separatorIndex]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = line[line.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return headers
    }

    private static func splitPathAndQuery(_ fullPath: String) -> (String, [String: String]) {
        guard let questionMarkIndex = fullPath.firstIndex(of: "?") else {
            return (fullPath, [:])
        }

        let path = String(fullPath[fullPath.startIndex..<questionMarkIndex])
        let queryString = String(fullPath[fullPath.index(after: questionMarkIndex)...])

        var queryItems: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let rawName = parts.first else {
                continue
            }
            let name = String(rawName).removingPercentEncoding ?? String(rawName)
            let value = parts.count > 1
                ? (String(parts[1]).removingPercentEncoding ?? String(parts[1]))
                : ""
            queryItems[name] = value
        }

        return (path, queryItems)
    }
}
